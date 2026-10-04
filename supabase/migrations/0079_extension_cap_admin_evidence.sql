-- 0079 — Rose's workflow suggestions (4 Oct 2026).
--
-- 1. A LIMIT ON DEADLINE EXTENSIONS. Moving a complaint's target date
--    later is an extension. Each one is now recorded in sla_extensions
--    (0002, which until now nothing wrote to) with the admin's reason, and
--    there is a cap: operational_settings.max_deadline_extensions, 2 by
--    default. Once a complaint has used them up, the date cannot move
--    again; the admin hands the case to a higher official instead
--    (hand_to_higher_official), which stands down any tanod on it and
--    starts a fresh allowance under that official.
--
-- 2. THE ADMIN ATTACHES EVIDENCE WHEN RESOLVING. admin_set_status takes
--    photos (p_media), kept in report_evidence and shown to the resident.
--
-- 3. THE ADMIN ACTS WITHOUT A TANOD. admin_barangay_update posts an
--    update (with photos) to the complaint's timeline and the resident,
--    with no dispatch needed. set_resolution_target already worked without
--    one; the portal now offers it outside the dispatch form.
--
-- Adds: report_evidence; reports.higher_official, higher_official_note,
-- handed_up_at; operational_settings.max_deadline_extensions.

set search_path = public, extensions;

-- ---------- the barangay's own photos ----------------------------------

-- The portal uploads to a fourth folder, 'barangay', in the same cloud.
create or replace function public.is_barangay_media_url(p_url text)
returns boolean
language sql
immutable
parallel safe
as $$
  select p_url ~
    '^https://res\.cloudinary\.com/nwb2kryl/image/upload/v[0-9]+/barangay/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|jpeg|png|webp)$'
$$;

comment on function public.is_barangay_media_url(text) is
  'A delivery URL in the barangay''s Cloudinary cloud, folder barangay, '
  'UUIDv4 name, image extension. The pin for report_evidence (0079); '
  'mirrored by cloudinary_upload() in admin/includes/supabase.php.';

revoke all on function public.is_barangay_media_url(text) from public, anon;
grant execute on function public.is_barangay_media_url(text) to authenticated, service_role;

create table if not exists public.report_evidence (
  id          uuid primary key default gen_random_uuid(),
  report_id   uuid not null references public.reports (id) on delete cascade,
  posted_by   uuid not null references public.users (id),
  kind        text not null check (kind in ('update', 'resolution')),
  media_url   text not null check (public.is_barangay_media_url(media_url)),
  mime_type   text not null check (mime_type in ('image/jpeg', 'image/png', 'image/webp')),
  bytes       integer not null check (bytes > 0 and bytes <= 10485760),
  log_id      uuid references public.status_logs (id) on delete set null,
  created_at  timestamptz not null default now()
);

comment on table public.report_evidence is
  'Photos the barangay attaches from the portal: with an update '
  '(admin_barangay_update) or when it resolves a complaint '
  '(admin_set_status). log_id ties each to its timeline entry.';

create index if not exists report_evidence_report_idx on public.report_evidence (report_id);

alter table public.report_evidence enable row level security;

drop policy if exists report_evidence_read on public.report_evidence;
create policy report_evidence_read on public.report_evidence
  for select using (
    (select public.is_admin())
    or exists (select 1 from public.reports r
                where r.id = report_evidence.report_id
                  and r.resident_id = (select auth.uid()))
  );
-- No write policies: rows arrive only through the functions below.

-- ---------- the cap and the higher official ----------------------------

alter table public.operational_settings
  add column if not exists max_deadline_extensions smallint not null default 2
    check (max_deadline_extensions between 0 and 10);

comment on column public.operational_settings.max_deadline_extensions is
  'How many times a complaint''s target date may be moved later before it '
  'must be handed to a higher official (0079).';

alter table public.reports
  add column if not exists higher_official      text check (char_length(higher_official) between 2 and 80),
  add column if not exists higher_official_note text check (char_length(higher_official_note) <= 300),
  add column if not exists handed_up_at         timestamptz;

comment on column public.reports.higher_official is
  'The barangay official the case was handed to after its extensions ran '
  'out (0079). The case stays open here, under that official.';

-- Extensions used since the case was last handed up (a hand-up starts a
-- fresh allowance).
create or replace function public.extensions_used(p_report uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer
    from public.sla_extensions e
    join public.reports r on r.id = e.report_id
   where e.report_id = p_report
     and e.created_at > coalesce(r.handed_up_at, '-infinity'::timestamptz)
$$;

revoke all on function public.extensions_used(uuid) from public, anon;
grant execute on function public.extensions_used(uuid) to authenticated;

-- ---------- set_resolution_target, now with the cap -------------------

drop function if exists public.set_resolution_target(uuid, timestamptz);

create or replace function public.set_resolution_target(
  p_report uuid,
  p_due    timestamptz,
  p_reason text default null)
returns timestamptz
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report public.reports%rowtype;
  v_when   text;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_cap    integer;
  v_used   integer;
  v_extend boolean;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may change a resolution target';
  end if;

  select * into v_report from public.reports
   where id = p_report and deleted_at is null for update;
  if not found then
    raise exception 'No such report';
  end if;
  if p_due is null then
    raise exception 'A target date is required';
  end if;
  if p_due <= now() then
    raise exception 'The target date must be in the future';
  end if;
  if v_report.status in ('resolved', 'closed', 'archived', 'rejected', 'cancelled') then
    raise exception 'This complaint is already finished; its target cannot be moved';
  end if;
  if v_report.due_at is not distinct from p_due then
    return p_due;
  end if;

  -- Later than the current date: an extension, recorded and capped.
  v_extend := v_report.due_at is not null and p_due > v_report.due_at;
  if v_extend then
    select max_deadline_extensions into v_cap from public.operational_settings where id = 1;
    v_cap  := coalesce(v_cap, 2);
    v_used := public.extensions_used(p_report);
    if v_used >= v_cap then
      raise exception 'This complaint''s target date has already been extended % time(s), the limit. Hand it to a higher official instead.', v_used;
    end if;
    if v_reason is null or char_length(v_reason) < 5 or char_length(v_reason) > 300 then
      raise exception 'Give a reason (5 to 300 characters) for extending the target date';
    end if;
    insert into public.sla_extensions (report_id, requested_by, approved_by, previous_due, new_due, reason, approved_at)
    values (p_report, auth.uid(), auth.uid(), v_report.due_at, p_due, v_reason, now());
  end if;

  update public.reports set due_at = p_due where id = p_report;

  v_when := to_char(p_due at time zone 'Asia/Manila', 'FMMonth FMDD, YYYY, FMHH12:MI AM');

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (p_report, auth.uid(), v_report.status, v_report.status,
          case when v_report.due_at is null
            then format('Expected to be resolved by %s.', v_when)
            else format('Expected resolution moved to %s.', v_when)
          end || case when v_extend then ' Reason: ' || v_reason else '' end);

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_report.resident_id, p_report, 'status_change',
          case when v_report.due_at is null
            then format('The barangay expects to resolve %s by %s.', v_report.tracking_id, v_when)
            else format('The expected resolution of %s is now %s.', v_report.tracking_id, v_when)
          end);

  return p_due;
end $$;

comment on function public.set_resolution_target(uuid, timestamptz, text) is
  'The admin sets or moves a complaint''s target date (0071). Moving it '
  'later is an extension (0079): it needs a reason, is recorded in '
  'sla_extensions, and is capped by max_deadline_extensions.';

revoke all on function public.set_resolution_target(uuid, timestamptz, text) from public, anon;
grant execute on function public.set_resolution_target(uuid, timestamptz, text) to authenticated;

-- ---------- hand the case to a higher official ------------------------

create or replace function public.hand_to_higher_official(
  p_report   uuid,
  p_official text,
  p_note     text default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report   public.reports%rowtype;
  v_official text := nullif(trim(coalesce(p_official, '')), '');
  v_note     text := nullif(trim(coalesce(p_note, '')), '');
  v_cap      integer;
  v_used     integer;
  d          record;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may hand a case to a higher official';
  end if;
  if v_official is null or char_length(v_official) < 2 or char_length(v_official) > 80 then
    raise exception 'Name the official (2 to 80 characters)';
  end if;
  if v_note is not null and char_length(v_note) > 300 then
    raise exception 'The note can be at most 300 characters';
  end if;

  select * into v_report from public.reports
   where id = p_report and deleted_at is null for update;
  if not found then
    raise exception 'No such report';
  end if;
  if v_report.status in ('pending_review', 'resolved', 'closed', 'archived', 'rejected', 'cancelled')
     or v_report.referred_to is not null then
    raise exception 'Only an open complaint can be handed to a higher official';
  end if;

  select max_deadline_extensions into v_cap from public.operational_settings where id = 1;
  v_cap  := coalesce(v_cap, 2);
  v_used := public.extensions_used(p_report);
  if v_used < v_cap then
    raise exception 'The target date can still be extended (% of % used). Hand the case up once the extensions run out.', v_used, v_cap;
  end if;

  -- Whoever is on it is stood down and told.
  for d in select id, tanod_id from public.dispatches
            where report_id = p_report and state in ('assigned', 'accepted') loop
    update public.dispatches
       set state = 'rerouted', rerouted_at = now(),
           reroute_reason = 'Handed to ' || v_official
     where id = d.id;
    insert into public.notifications (user_id, report_id, kind, message)
    values (d.tanod_id, p_report, 'reroute',
            v_report.tracking_id || ' was handed to ' || v_official || '. You no longer need to act on it.');
  end loop;

  update public.reports
     set higher_official      = v_official,
         higher_official_note = v_note,
         handed_up_at         = now(),
         status = case when status in ('validated', 'assigned') then 'in_progress'::report_status else status end
   where id = p_report;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (p_report, auth.uid(), v_report.status,
          case when v_report.status in ('validated', 'assigned') then 'in_progress'::report_status else v_report.status end,
          format('Handed to %s after the target date was extended %s time(s).', v_official, v_used)
          || coalesce(' ' || v_note, ''));

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_report.resident_id, p_report, 'status_change',
          'Your complaint ' || v_report.tracking_id || ' is now handled by ' || v_official || '.'
          || coalesce(' ' || v_note, ''));
end $$;

comment on function public.hand_to_higher_official(uuid, text, text) is
  'Once a complaint''s extensions are used up (0079), the admin hands it '
  'to a barangay official: any tanod is stood down, the case stays open '
  'under that official, and a fresh extension allowance starts.';

revoke all on function public.hand_to_higher_official(uuid, text, text) from public, anon;
grant execute on function public.hand_to_higher_official(uuid, text, text) to authenticated;

-- ---------- evidence rows, shared by the two functions below ----------

create or replace function public._add_report_evidence(
  p_report uuid, p_log uuid, p_kind text, p_media jsonb)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  m jsonb;
begin
  if jsonb_array_length(coalesce(p_media, '[]'::jsonb)) > 6 then
    raise exception 'At most 6 photos';
  end if;
  for m in select * from jsonb_array_elements(coalesce(p_media, '[]'::jsonb)) loop
    insert into public.report_evidence (report_id, posted_by, kind, media_url, mime_type, bytes, log_id)
    values (p_report, auth.uid(), p_kind, m->>'media_url', m->>'mime_type', (m->>'bytes')::integer, p_log);
  end loop;
end $$;

revoke all on function public._add_report_evidence(uuid, uuid, text, jsonb) from public, anon, authenticated;

-- ---------- an update from the barangay, no tanod needed --------------

create or replace function public.admin_barangay_update(
  p_report uuid,
  p_body   text,
  p_media  jsonb default '[]'::jsonb)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report public.reports%rowtype;
  v_body   text := nullif(trim(coalesce(p_body, '')), '');
  v_count  integer := jsonb_array_length(coalesce(p_media, '[]'::jsonb));
  v_log    uuid;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may post a barangay update';
  end if;
  if v_body is null and v_count = 0 then
    raise exception 'Write an update or attach a photo';
  end if;
  if v_body is not null and char_length(v_body) > 500 then
    raise exception 'The update can be at most 500 characters';
  end if;

  select * into v_report from public.reports
   where id = p_report and deleted_at is null for update;
  if not found then
    raise exception 'No such report';
  end if;
  if v_report.status in ('pending_review', 'closed', 'archived', 'rejected', 'cancelled') then
    raise exception 'Updates can be posted on an accepted, open complaint';
  end if;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (p_report, auth.uid(), v_report.status, v_report.status,
          coalesce('Update from the barangay: ' || v_body,
                   format('The barangay added %s photo(s).', v_count)))
  returning id into v_log;

  perform public._add_report_evidence(p_report, v_log, 'update', p_media);

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_report.resident_id, p_report, 'status_change',
          'Update on ' || v_report.tracking_id || ': '
          || coalesce(v_body, 'the barangay added photos.'));

  return v_log;
end $$;

comment on function public.admin_barangay_update(uuid, text, jsonb) is
  'The admin posts an update, with up to 6 photos, to a complaint''s '
  'timeline and its resident, with or without a tanod on it (0079).';

revoke all on function public.admin_barangay_update(uuid, text, jsonb) from public, anon;
grant execute on function public.admin_barangay_update(uuid, text, jsonb) to authenticated;

-- ---------- admin_set_status, now with evidence -----------------------
-- 0073's body unchanged, plus p_media kept against the log entry.

drop function if exists public.admin_set_status(uuid, text, text);

create or replace function public.admin_set_status(
  p_report uuid, p_status text, p_remark text default null, p_media jsonb default '[]'::jsonb)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report public.reports%rowtype;
  v_new    report_status;
  v_remark text := nullif(trim(coalesce(p_remark, '')), '');
  v_log    uuid;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may change a complaint''s status';
  end if;
  if p_status not in ('in_progress', 'offline_investigation', 'resolved') then
    raise exception 'Choose In Progress, Offline Investigation or Resolved';
  end if;
  v_new := p_status::report_status;

  select * into v_report from public.reports
   where id = p_report and deleted_at is null for update;
  if not found then
    raise exception 'No such report';
  end if;
  if v_report.status in ('closed', 'archived', 'rejected', 'cancelled', 'pending_review') then
    raise exception 'This complaint''s status cannot be changed here';
  end if;
  if v_report.status = v_new then
    raise exception 'The complaint is already %', replace(p_status, '_', ' ');
  end if;

  if v_new = 'resolved' then
    update public.dispatches
       set state = 'rerouted', rerouted_at = now(), reroute_reason = 'Resolved by the barangay'
     where report_id = p_report and state in ('assigned', 'accepted');
    update public.reports
       set status = 'resolved', resolved_at = now(), resolution_submitted_at = null
     where id = p_report;
  else
    update public.reports set status = v_new where id = p_report;
  end if;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (p_report, auth.uid(), v_report.status, v_new,
          coalesce(v_remark, case v_new
            when 'in_progress' then 'Status set to In Progress by the barangay.'
            when 'offline_investigation' then 'Status set to Offline Investigation by the barangay.'
            else 'Marked resolved by the barangay.' end))
  returning id into v_log;

  perform public._add_report_evidence(p_report, v_log,
          case when v_new = 'resolved' then 'resolution' else 'update' end, p_media);

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_report.resident_id, p_report, 'status_change',
          case v_new
            when 'in_progress' then 'Your complaint ' || v_report.tracking_id || ' is in progress.'
            when 'offline_investigation' then 'Your complaint ' || v_report.tracking_id || ' is under offline investigation by the barangay.'
            else 'Your complaint ' || v_report.tracking_id || ' has been resolved.' end
          || coalesce(' ' || v_remark, ''));
end $$;

revoke all on function public.admin_set_status(uuid, text, text, jsonb) from public, anon;
grant execute on function public.admin_set_status(uuid, text, text, jsonb) to authenticated;
