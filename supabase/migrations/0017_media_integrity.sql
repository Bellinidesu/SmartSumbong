-- =============================================================
-- SmartSumbong — 0017 Media integrity
--
-- Preparation for the resident Flutter app. Four findings, all of
-- which the media upload path would otherwise exercise on day one.
--
-- FINDING 1. media_url is unconstrained text.
--   report_media.media_url, dispatch_media.media_url, users.id_image_url
--   and users.selfie_url accept any string. A verified resident can
--   PostgREST-insert a report_media row pointing at a host they control;
--   users.id_image_url is worse, because 0004's signup trigger copies it
--   straight out of raw_user_meta_data, which is entirely client-written
--   and is read before the account is verified by anyone.
--
--   The admin portal renders these in <img src>. So an unverified signup
--   can plant a URL that an administrator's browser will fetch: a
--   read receipt on when the verification queue is opened and by which
--   IP, at minimum. That contradicts the portal's stated position that
--   nothing third-party executes or loads in an admin browser.
--
--   Fix: pin every media column to the barangay's own Cloudinary cloud,
--   its own folder, and an image extension. No query string, so no
--   cache-buster or tracking parameter can ride along.
--
-- FINDING 2. The 10 MB cap is advisory.
--   enforce_media_cap() sums report_media.bytes, which the client
--   asserts. Nothing compares it to the actual asset. A client can
--   declare bytes = 1 for a 9 MB photo. Server-side byte verification
--   needs a Cloudinary Admin API call, which needs the API secret, which
--   cannot live in a phone. So bytes stays advisory and the real limit
--   moves to something the database can actually count: rows.
--
--   Fix: cap photos per report at MAX_REPORT_PHOTOS. Byte enforcement
--   stays where it can be enforced — the upload preset's max file size,
--   which Cloudinary applies before the asset exists at all.
--
-- FINDING 3. Dispatch fires before the photos land.
--   0010's reports_dispatch_on_file is AFTER INSERT ON reports. Media
--   rows can only be written after the report row exists (their RLS
--   policy joins to it). So for any auto-dispatch category, the tanod
--   gets the ticket, opens it, and sees no evidence — the photos appear
--   underneath him seconds later. "View Ticket Details" promises
--   "attached citizen evidence media" as a precondition of arrival.
--
--   Fix: make it a deferred constraint trigger. It now fires at COMMIT,
--   after every media row in the same transaction is in place. A lone
--   INSERT from PostgREST behaves exactly as before, because PostgREST
--   wraps each request in its own transaction.
--
-- FINDING 4. There is no single call that files a complete complaint.
--   Without one the app must insert the report, then insert media, and
--   handle the case where the second call fails and leaves a complaint
--   whose evidence is missing forever. file_report() makes it one
--   transaction. It is SECURITY INVOKER on purpose: RLS still decides
--   whether this caller may file at all.
--
-- PREFLIGHT — run this first. It must return zero rows, or the ALTERs
-- below will fail and you will need to correct the offending rows:
--
--   select 'report_media' as t, id, media_url from public.report_media
--     where not public.is_media_url(media_url)
--   union all
--   select 'dispatch_media', id, media_url from public.dispatch_media
--     where not public.is_media_url(media_url)
--   union all
--   select 'users.id_image_url', id, id_image_url from public.users
--     where id_image_url is not null and not public.is_media_url(id_image_url)
--   union all
--   select 'users.selfie_url', id, selfie_url from public.users
--     where selfie_url is not null and not public.is_media_url(selfie_url);
--
-- (Create the function first, then run the preflight, then the rest.)
-- =============================================================

set search_path = public, extensions;

-- ---------- the pin ------------------------------------------
-- Cloud name and folder are deployment constants. They are public by
-- design — they appear in every delivery URL — so hardcoding them here
-- leaks nothing. Changing clouds is a new migration, not an edit to
-- this one: CREATE OR REPLACE on a function used by a CHECK constraint
-- changes what the constraint means without revalidating existing rows.

create or replace function public.is_media_url(p_url text)
returns boolean
language sql
immutable
parallel safe
as $$
  select p_url ~
    '^https://res\.cloudinary\.com/nwb2kryl/image/upload/(v[0-9]+/)?smartsumbong/[A-Za-z0-9_/-]+\.(jpg|jpeg|png|webp)$'
$$;

comment on function public.is_media_url(text) is
  'True only for delivery URLs in the barangay''s own Cloudinary cloud and '
  'folder, ending in an image extension, with no query string. Every media '
  'column is CHECKed against this so that no client-written string can '
  'cause an administrator''s browser to fetch a third-party host.';

alter table public.report_media
  add constraint report_media_url_pinned
  check (public.is_media_url(media_url));

alter table public.dispatch_media
  add constraint dispatch_media_url_pinned
  check (public.is_media_url(media_url));

alter table public.users
  add constraint users_id_image_url_pinned
  check (id_image_url is null or public.is_media_url(id_image_url));

alter table public.users
  add constraint users_selfie_url_pinned
  check (selfie_url is null or public.is_media_url(selfie_url));

-- ---------- photo count cap ----------------------------------
-- Placeholder, like the SLA windows and the attempt cap. Five photos is
-- a developer guess about what a resident needs to evidence a complaint
-- and what a tanod can review on a phone in the field. Barangay input
-- replaces it.

alter table public.operational_settings
  add column if not exists max_report_photos smallint not null default 5
    check (max_report_photos between 1 and 20);

comment on column public.operational_settings.max_report_photos is
  'Photos per complaint. Enforced because row counts are verifiable; the '
  '10 MB byte cap is not, because bytes is client-asserted.';

create or replace function public.enforce_media_cap()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_total bigint;
  v_count integer;
  v_max   smallint;
begin
  select coalesce(sum(bytes), 0), count(*)
    into v_total, v_count
    from public.report_media
   where report_id = new.report_id;

  select max_report_photos into v_max from public.operational_settings limit 1;
  v_max := coalesce(v_max, 5);

  if v_count + 1 > v_max then
    raise exception 'This complaint already has the maximum of % photos', v_max
      using errcode = 'check_violation';
  end if;

  -- Advisory. bytes is asserted by the client and is not verified here;
  -- the enforceable byte limit is the upload preset's max file size.
  if v_total + new.bytes > 10 * 1024 * 1024 then
    raise exception 'Combined media for this report exceeds the 10 MB limit'
      using errcode = 'check_violation';
  end if;

  return new;
end $$;

-- ---------- media insert follows account standing -------------
-- reports_resident_insert already refuses a suspended or unverified
-- resident. report_media_insert did not, so a resident suspended for
-- filing fraudulent complaints could still attach photos to a complaint
-- filed before the suspension.

drop policy if exists report_media_insert on public.report_media;

create policy report_media_insert on public.report_media
  for insert with check (
    exists (select 1
              from public.reports r
              join public.users   u on u.id = auth.uid()
             where r.id = report_media.report_id
               and r.resident_id = auth.uid()
               and r.deleted_at is null
               and u.verification_status = 'verified'
               and not u.is_suspended)
  );

-- ---------- defer dispatch to commit --------------------------

drop trigger if exists reports_dispatch_on_file on public.reports;

create constraint trigger reports_dispatch_on_file
  after insert on public.reports
  deferrable initially deferred
  for each row execute function public.dispatch_on_file();

comment on function public.dispatch_on_file() is
  'Fires at COMMIT, not at INSERT, so that a complaint filed through '
  'file_report() has its photos attached before a tanod is dispatched to it.';

-- ---------- file a complete complaint in one transaction ------

create or replace function public.file_report(
  p_category      public.complaint_category,
  p_subject       text,
  p_description   text,
  p_latitude      double precision,
  p_longitude     double precision,
  p_is_anonymous  boolean default false,
  p_media         jsonb   default '[]'::jsonb
)
returns public.reports
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  v_report public.reports;
  v_item   jsonb;
begin
  if jsonb_typeof(coalesce(p_media, '[]'::jsonb)) <> 'array' then
    raise exception 'p_media must be a JSON array of {media_url, mime_type, bytes}'
      using errcode = 'invalid_parameter_value';
  end if;

  insert into public.reports
    (resident_id, is_anonymous, category, subject, description, latitude, longitude)
  values
    (auth.uid(), coalesce(p_is_anonymous, false), p_category,
     p_subject, p_description, p_latitude, p_longitude)
  returning * into v_report;

  for v_item in select value from jsonb_array_elements(coalesce(p_media, '[]'::jsonb))
  loop
    insert into public.report_media (report_id, media_url, mime_type, bytes)
    values (v_report.id,
            v_item ->> 'media_url',
            v_item ->> 'mime_type',
            (v_item ->> 'bytes')::integer);
  end loop;

  return v_report;
end $$;

comment on function public.file_report is
  'Submit Complaint Report, one transaction. SECURITY INVOKER: '
  'reports_resident_insert still decides whether this caller may file, and '
  'report_media_insert still decides whether these photos may attach. If any '
  'photo row is rejected the whole complaint rolls back, so a complaint is '
  'never stored with its evidence silently missing.';

revoke all on function public.file_report(
  public.complaint_category, text, text, double precision,
  double precision, boolean, jsonb) from public, anon;

grant execute on function public.file_report(
  public.complaint_category, text, text, double precision,
  double precision, boolean, jsonb) to authenticated;

revoke all on function public.is_media_url(text) from public, anon;
grant execute on function public.is_media_url(text) to authenticated, service_role;
