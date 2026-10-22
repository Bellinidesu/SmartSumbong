-- =============================================================
-- SmartSumbong — 0137 The engine: work the database hands out
--
-- Ace (22 Oct 2026): the portal's features and labs run as engine
-- functions, on the server, not on the phone. The first job is reading
-- ID photos (the OCR lab's pick, PaddleOCR; tools/ocr_lab). It used to run
-- on the phone, which needed a 31 MB model in the app; now the app only
-- uploads the photo, as it already does, and the engine reads it.
--
-- The engine (engine/, its own small service) is a pure function: a signed
-- link to one ID photo in, the card's type, name and number out. It holds
-- no database or Cloudinary credential. This file:
--   - queues a reading for each pending account with a private ID photo
--     and no reading yet (or a rescan the barangay asked for);
--   - every minute, files the engine's answers (through the same save as
--     submit_id_reading, so 0126's checks judge them) and asks for the
--     next ones, signing each link here with the Cloudinary secret;
--   - stays off until Vault holds engine_url, engine_secret and
--     cloudinary_api_secret (DEPLOY.md), the way media cleanup does (0118).
-- A reading never verifies anyone: it only tells the barangay where to
-- look first (0039, 0126).
-- =============================================================

set search_path = public, extensions;

create table public.engine_jobs (
  id          bigint generated always as identity primary key,
  kind        text not null default 'id_read' check (kind in ('id_read')),
  user_id     uuid not null references public.users (id) on delete cascade,
  photo_url   text not null,
  state       text not null default 'waiting' check (state in ('waiting', 'asked', 'done', 'failed')),
  request_id  bigint,
  tries       smallint not null default 0,
  last_error  text,
  created_at  timestamptz not null default clock_timestamp(),
  asked_at    timestamptz,
  done_at     timestamptz
);
create unique index engine_jobs_one_open on public.engine_jobs (kind, user_id) where state in ('waiting', 'asked');
create index engine_jobs_state_idx on public.engine_jobs (state, created_at);

alter table public.engine_jobs enable row level security;
create policy engine_jobs_admin_read on public.engine_jobs for select using ((select public.is_admin()));

comment on table public.engine_jobs is
  '0137: work handed to the engine (engine/). id_read: one ID photo to read. Written only by engine_enqueue() and engine_tick().';

-- ---------- one reading saved, by the app (0126) or the engine ----------------

create or replace function public._id_reading_save(p_user uuid, p_type public.id_document_type, p_name text, p_number text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform set_config('smartsumbong.id_reading', 'on', true);
  update public.users
     set ocr_detected_type = p_type,
         ocr_extracted_name = nullif(left(trim(p_name), 120), ''),
         ocr_extracted_number = nullif(left(trim(p_number), 40), ''),
         ocr_processed_at = clock_timestamp(),
         ocr_rescan_requested_at = null
   where id = p_user;
  update public.users
     set ocr_flags = array(select jsonb_array_elements_text(public._smart_verify(p_user) -> 'flags'))
   where id = p_user;
  perform set_config('smartsumbong.id_reading', 'off', true);
end $$;
revoke all on function public._id_reading_save(uuid, public.id_document_type, text, text) from public, anon, authenticated;

create or replace function public.submit_id_reading(p_detected_type public.id_document_type, p_name text, p_number text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in' using errcode = 'insufficient_privilege';
  end if;
  perform public._id_reading_save(auth.uid(), p_detected_type, p_name, p_number);
end $$;

-- ---------- signing a link to a private photo ----------------------------------

-- The portal's cld_private_url() in SQL: Cloudinary's signed delivery address, the first eight characters of the
-- URL-safe base64 SHA-256 of the transformation and asset path followed by the API secret.
create or replace function public._cld_sign(p_url text, p_transformation text, p_secret text)
returns text
language plpgsql immutable set search_path = public, extensions as $$
declare m text[];
begin
  m := regexp_match(p_url, '^(https://res\.cloudinary\.com/[^/]+/image/authenticated/)(v[0-9]+)/(.+)$');
  if m is null or coalesce(p_secret, '') = '' then return null; end if;
  return m[1] || 's--' ||
         left(translate(encode(extensions.digest(p_transformation || '/' || m[3] || p_secret, 'sha256'), 'base64'), '+/', '-_'), 8) ||
         '--/' || p_transformation || '/' || m[2] || '/' || m[3];
end $$;
revoke all on function public._cld_sign(text, text, text) from public, anon, authenticated;

create or replace function public._engine_config()
returns table (url text, secret text, cloudinary text)
language plpgsql stable security definer set search_path = public as $$
begin
  if to_regclass('vault.decrypted_secrets') is null then return; end if;
  return query execute $q$
    select max(decrypted_secret) filter (where name = 'engine_url'),
           max(decrypted_secret) filter (where name = 'engine_secret'),
           max(decrypted_secret) filter (where name = 'cloudinary_api_secret')
      from vault.decrypted_secrets $q$;
end $$;
revoke all on function public._engine_config() from public, anon, authenticated;

-- ---------- the queue ------------------------------------------------------

create or replace function public.engine_enqueue()
returns integer
language plpgsql security definer set search_path = public, extensions as $$
declare n integer;
begin
  insert into public.engine_jobs (user_id, photo_url)
  select u.id, u.id_image_url
    from public.users u
   where u.verification_status = 'pending'
     and u.id_image_url ~ '^https://res\.cloudinary\.com/[^/]+/image/authenticated/v[0-9]+/ids/'
     and not exists (select 1 from public.engine_jobs j where j.kind = 'id_read' and j.user_id = u.id and j.state in ('waiting', 'asked'))
     and (
       -- every photo is read once (a new upload too, and those the app read before the engine)
       not exists (select 1 from public.engine_jobs j where j.kind = 'id_read' and j.user_id = u.id and j.photo_url = u.id_image_url)
       -- and again when the barangay asks, once per ask
       or (u.ocr_rescan_requested_at > coalesce(u.ocr_processed_at, '-infinity')
           and not exists (select 1 from public.engine_jobs j where j.kind = 'id_read' and j.user_id = u.id
                             and j.photo_url = u.id_image_url and j.created_at > u.ocr_rescan_requested_at)))
   order by u.created_at
   limit 50
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

-- Every minute: file what the engine answered, then ask for the next ones. Two at a time: the engine reads one
-- photo at a time, and a sleeping engine takes up to a minute to wake.
create or replace function public.engine_tick()
returns text
language plpgsql security definer set search_path = public, extensions as $$
declare
  c record;
  j record;
  r record;
  a jsonb;
  v_type public.id_document_type;
  v_link text;
  v_rid bigint;
  v_filed int := 0;
  v_asked int := 0;
begin
  select * into c from public._engine_config();
  if c.url is null or c.secret is null or c.cloudinary is null then return 'off'; end if;
  perform public.engine_enqueue();

  for j in select * from public.engine_jobs where state = 'asked' order by asked_at for update skip locked loop
    select status_code, content, timed_out, error_msg into r from net._http_response where id = j.request_id;
    if not found then
      if j.asked_at < now() - interval '5 minutes' then
        update public.engine_jobs set state = case when tries >= 3 then 'failed' else 'waiting' end,
               last_error = 'no answer' where id = j.id;
      end if;
      continue;
    end if;
    begin
      if r.status_code <> 200 then raise exception 'engine answered %', coalesce(r.status_code::text, r.error_msg, 'nothing'); end if;
      a := r.content::jsonb;
      if (select id_image_url from public.users where id = j.user_id) is distinct from j.photo_url then
        -- a new photo came in while this one was read: this reading is for the old one
        update public.engine_jobs set state = 'done', done_at = now(), last_error = 'photo replaced' where id = j.id;
      else
        v_type := case when a ->> 'type' in (select unnest(enum_range(null::public.id_document_type))::text)
                       then (a ->> 'type')::public.id_document_type end;
        perform public._id_reading_save(j.user_id, v_type, a ->> 'name', a ->> 'number');
        update public.engine_jobs set state = 'done', done_at = now(), last_error = null where id = j.id;
        v_filed := v_filed + 1;
      end if;
    exception when others then
      update public.engine_jobs set state = case when tries >= 3 then 'failed' else 'waiting' end,
             last_error = left(sqlerrm, 200) where id = j.id;
    end;
    -- the answer held a name and a number: not left in pg_net's table for its six hours
    delete from net._http_response where id = j.request_id;
  end loop;

  for j in select * from public.engine_jobs where state = 'waiting' order by created_at limit 2 for update skip locked loop
    v_link := public._cld_sign(j.photo_url, 'c_limit,w_1600', c.cloudinary);
    if v_link is null then
      update public.engine_jobs set state = 'failed', last_error = 'not a private ID photo' where id = j.id;
      continue;
    end if;
    v_rid := net.http_post(url := rtrim(c.url, '/') || '/read',
                           body := jsonb_build_object('url', v_link),
                           headers := jsonb_build_object('Content-Type', 'application/json', 'x-engine-secret', c.secret),
                           timeout_milliseconds := 120000);
    update public.engine_jobs set state = 'asked', request_id = v_rid, tries = tries + 1, asked_at = now() where id = j.id;
    v_asked := v_asked + 1;
  end loop;

  return format('filed %s, asked %s', v_filed, v_asked);
end $$;

revoke all on function public.engine_enqueue() from public, anon, authenticated;
revoke all on function public.engine_tick() from public, anon, authenticated;

-- What Settings > System status shows.
create or replace function public.engine_status()
returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare c record;
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  select * into c from public._engine_config();
  return jsonb_build_object(
    'configured', c.url is not null and c.secret is not null and c.cloudinary is not null,
    'waiting', (select count(*) from public.engine_jobs where state in ('waiting', 'asked')),
    'failed_week', (select count(*) from public.engine_jobs where state = 'failed' and created_at > now() - interval '7 days'),
    'read_week', (select count(*) from public.engine_jobs where state = 'done' and done_at > now() - interval '7 days'),
    'last_read_at', (select max(done_at) from public.engine_jobs where state = 'done'));
end $$;
revoke all on function public.engine_status() from public, anon;
grant execute on function public.engine_status() to authenticated;

select cron.schedule('engine-tick', '* * * * *', $$ select public.engine_tick() $$);

-- Done jobs are kept a month (Settings counts the last week), then go.
select cron.schedule('engine-jobs-purge', '50 3 * * *', $$ delete from public.engine_jobs where state in ('done', 'failed') and created_at < now() - interval '30 days' $$);
