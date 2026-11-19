-- 0176: one category per case (19 Nov 2026, Rose).
--
-- A report can carry several concerns (0130, the panel's ask; options as sub-categories, 0163), and until now they could come
-- from different categories: a Peace and Order concern and a Health and Sanitation one in the same case. A case goes to one
-- committee and is handled as one thing, so from now on every concern in a case is under the case's own category (the
-- report's category, which is also its main concern): several options of that one category are still several concerns.
--
--   _one_category_refuse(category)   the one refusal, worded for the resident and the portal in English and Tagalog
--   one_category_per_case            before a concern is inserted: a category other than its report's is refused
--   file_report(...)                 refuses a report whose concerns are from more than one category, with that message,
--                                    instead of quietly leaving the others out (the app shows the message as it is)
--
-- New writes only. Concerns already there are not touched or checked, so a case that already mixes categories (2 live cases
-- on 19 Nov 2026, both still open) keeps them and can still be worked; a concern added to it must be of its own category.
-- A concern's category cannot change after it is raised (0163's snapshot trigger), and nothing changes a report's category,
-- so checking inserts is enough.

set search_path = public, extensions;

-- ---------- the refusal ----------

create or replace function public._one_category_refuse(p_category public.complaint_category)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_en text; v_fil text;
begin
  select c.label_en, c.label_fil into v_en, v_fil from public.complaint_categories c where c.key = p_category::text;
  v_en := coalesce(v_en, initcap(replace(p_category::text, '_', ' '))); v_fil := coalesce(v_fil, v_en);
  raise exception 'A report can have concerns from one category only: %. Report the other concern on its own. / Isang kategorya lamang ang maaaring sakupin ng mga alalahanin sa isang ulat: %. Isumbong nang hiwalay ang ibang alalahanin.', v_en, v_fil
    using errcode = 'check_violation', hint = 'one_category_per_case';
end $$;
revoke all on function public._one_category_refuse(public.complaint_category) from public, anon;
grant execute on function public._one_category_refuse(public.complaint_category) to authenticated, service_role;
comment on function public._one_category_refuse(public.complaint_category) is
  '0176: raises the one-category refusal (check_violation, hint one_category_per_case) naming the case''s category in English and Tagalog.';

-- ---------- every new concern is of its report's category ----------

create or replace function public._one_category_per_case()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_cat public.complaint_category;
begin
  select r.category into v_cat from public.reports r where r.id = new.report_id;
  if v_cat is not null and new.category is distinct from v_cat then
    perform public._one_category_refuse(v_cat);
  end if;
  return new;
end $$;
revoke all on function public._one_category_per_case() from public, anon, authenticated;

drop trigger if exists one_category_per_case on public.report_concerns;
create trigger one_category_per_case before insert on public.report_concerns
  for each row execute function public._one_category_per_case();
comment on trigger one_category_per_case on public.report_concerns is
  '0176: a new concern must be under its report''s category; rows from before 0176 are left as they are.';

-- ---------- filing: concerns from a second category are refused with that message, not left out ----------

create or replace function public.file_report(
  p_category public.complaint_category, p_subject text, p_description text, p_latitude double precision, p_longitude double precision,
  p_is_anonymous boolean default false, p_media jsonb default '[]'::jsonb, p_client_ref uuid default null,
  p_option bigint default null, p_concerns jsonb default '[]'::jsonb
) returns public.reports
language plpgsql set search_path = public, extensions
as $$
declare
  v_report public.reports;
  v_item   jsonb;
begin
  if jsonb_typeof(coalesce(p_media, '[]'::jsonb)) <> 'array' then
    raise exception 'p_media must be a JSON array of {media_url, mime_type, bytes}'
      using errcode = 'invalid_parameter_value';
  end if;
  if jsonb_typeof(coalesce(p_concerns, '[]'::jsonb)) <> 'array' then
    raise exception 'p_concerns must be a JSON array of {category, option}' using errcode = 'invalid_parameter_value';
  end if;

  -- Already filed under this ref: hand back that report, file nothing (also one filed before 0176 with mixed concerns).
  if p_client_ref is not null then
    select * into v_report from public.reports where resident_id = auth.uid() and client_ref = p_client_ref;
    if found then
      return v_report;
    end if;
  end if;

  -- 0176: every concern under the report's own category; anything else is refused before the report is filed
  if exists (select 1 from jsonb_array_elements(coalesce(p_concerns, '[]'::jsonb)) x
              where nullif(x.value ->> 'category', '') is not null and x.value ->> 'category' <> p_category::text) then
    perform public._one_category_refuse(p_category);
  end if;

  begin
    perform set_config('smartsumbong.main_option', coalesce(p_option::text, ''), true);
    insert into public.reports
      (resident_id, is_anonymous, category, subject, description, latitude, longitude, client_ref)
    values
      (auth.uid(), coalesce(p_is_anonymous, false), p_category, p_subject, p_description, p_latitude, p_longitude, p_client_ref)
    returning * into v_report;
    perform set_config('smartsumbong.main_option', '', true);
  exception when unique_violation then
    -- Two sends of the same queued report raced; the other one won.
    select * into v_report from public.reports where resident_id = auth.uid() and client_ref = p_client_ref;
    return v_report;
  end;

  for v_item in select value from jsonb_array_elements(coalesce(p_media, '[]'::jsonb))
  loop
    insert into public.report_media (report_id, media_url, mime_type, bytes)
    values (v_report.id, v_item ->> 'media_url', v_item ->> 'mime_type', (v_item ->> 'bytes')::integer);
  end loop;

  -- the other concerns; one switched off (or the same as another) while the report waited is left out, and the report still files
  for v_item in select value from jsonb_array_elements(coalesce(p_concerns, '[]'::jsonb)) limit 3
  loop
    begin
      perform public.add_report_concern(v_report.id, (v_item ->> 'category')::public.complaint_category, null, nullif(v_item ->> 'option', '')::bigint);
    exception when others then
      null;
    end;
  end loop;

  return v_report;
end $$;
revoke all on function public.file_report(public.complaint_category, text, text, double precision, double precision, boolean, jsonb, uuid, bigint, jsonb) from public, anon;
grant execute on function public.file_report(public.complaint_category, text, text, double precision, double precision, boolean, jsonb, uuid, bigint, jsonb) to authenticated, service_role;
