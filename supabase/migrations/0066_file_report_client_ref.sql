-- 0066: file_report() becomes safe to retry.
--
-- The resident app now queues a report filed with no signal and sends it
-- when the connection returns (branch B, lib/outbox.dart). A retry is only
-- safe if the server can tell "the same report again" from "a new report":
-- a submit whose request reached the database but whose reply was lost to
-- a dropped connection would otherwise be filed twice when the queue
-- resends it.
--
-- Each queued report carries a client-generated UUID, p_client_ref. The
-- first call files it; any later call with the same (resident, ref)
-- returns that same report instead of inserting another. Callers that
-- send no ref (older app builds, the online path) behave exactly as
-- before.

alter table public.reports
  add column if not exists client_ref uuid;

comment on column public.reports.client_ref is
  'Client-generated id of the submission (resident app outbox). Unique per '
  'resident, so a resent report returns the one already filed instead of '
  'creating a duplicate. Null for reports filed without one.';

create unique index if not exists reports_resident_client_ref_key
  on public.reports (resident_id, client_ref)
  where client_ref is not null;

-- Same signature plus one defaulted parameter. Dropped and recreated
-- rather than overloaded: two file_report()s differing only by a trailing
-- default would leave PostgREST unable to choose between them for a call
-- that omits it.
drop function if exists public.file_report(
  public.complaint_category, text, text, double precision,
  double precision, boolean, jsonb);

create function public.file_report(
  p_category      public.complaint_category,
  p_subject       text,
  p_description   text,
  p_latitude      double precision,
  p_longitude     double precision,
  p_is_anonymous  boolean default false,
  p_media         jsonb   default '[]'::jsonb,
  p_client_ref    uuid    default null
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

  -- Already filed under this ref: hand back that report, file nothing.
  if p_client_ref is not null then
    select * into v_report
      from public.reports
     where resident_id = auth.uid()
       and client_ref = p_client_ref;
    if found then
      return v_report;
    end if;
  end if;

  begin
    insert into public.reports
      (resident_id, is_anonymous, category, subject, description,
       latitude, longitude, client_ref)
    values
      (auth.uid(), coalesce(p_is_anonymous, false), p_category,
       p_subject, p_description, p_latitude, p_longitude, p_client_ref)
    returning * into v_report;
  exception when unique_violation then
    -- Two sends of the same queued report raced; the other one won.
    select * into v_report
      from public.reports
     where resident_id = auth.uid()
       and client_ref = p_client_ref;
    return v_report;
  end;

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
  'never stored with its evidence silently missing. p_client_ref (0066) '
  'makes a resend of the same submission return the report already filed.';

revoke all on function public.file_report(
  public.complaint_category, text, text, double precision,
  double precision, boolean, jsonb, uuid) from public, anon;

grant execute on function public.file_report(
  public.complaint_category, text, text, double precision,
  double precision, boolean, jsonb, uuid) to authenticated;
