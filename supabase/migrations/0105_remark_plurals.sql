-- SmartSumbong — "extended 2 time(s)" reads as "extended 2 times" (phone run, 7 Oct 2026).
--
-- The hand-to-a-higher-official note (0079) writes "time(s)" into the
-- status log. The stored history stays as written; what the resident is
-- shown (resident_remark, 0099) says it properly. The portal does the same
-- when it displays a remark.

create or replace function public.resident_remark(p_remark text, p_is_system boolean)
returns text language sql immutable set search_path = public as $$
  select regexp_replace(regexp_replace(
    case
      when p_remark is null or btrim(p_remark) = '' then null
      when p_remark ~* '^(auto-dispatched|manually assigned)' then 'A tanod was assigned to your report.'
      when p_remark ~* '^(re-dispatching|rerouted)' then 'The barangay is sending another available tanod.'
      when p_remark ~* '^no tanod' then 'Waiting for an available tanod.'
      when p_remark ~* '^sla breach' then 'Past the expected date. The barangay has been alerted.'
      when p_remark ~* '^resolution target moved from' then 'The barangay changed the expected resolution date.'
      else p_remark
    end,
    '\m1 time\(s\)', '1 time', 'g'),
    'time\(s\)', 'times', 'g')
$$;
comment on function public.resident_remark(text, boolean) is
  'A status-log note as a resident should read it: assignment, re-dispatch and SLA notes (tanod names, distances, system jargon) become plain wording, and "time(s)" reads properly. 0099, 0105.';
