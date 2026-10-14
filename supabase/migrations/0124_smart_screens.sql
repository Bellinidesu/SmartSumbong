-- 0124: what the SMART screens call (docs/SMART_SCREENS.md), 10 Oct 2026.
--
--   smart_case_card(report)   everything the case page's SMART card shows,
--                             in one call: level, reasons, override,
--                             duplicates, estimate, category hint, and the
--                             top three tanods.
--   smart_summary()           the dashboard's two tiles.
--   smart_preview(...)        Settings -> SMART -> Try it: the score a
--                             complaint would get, without saving anything.
--   category hint             the words of a report that point to another
--                             kind of complaint ("counterflow", filed as
--                             Other, suggests Traffic violation). A
--                             suggestion only; the admin changes the kind.

set search_path = public, extensions;

-- ---------- category hint ------------------------------------------------------

alter table public.smart_rules
  add column category_words jsonb not null default '{
    "street_obstruction":           "\\m(obstruction|nakaharang|harang|sidewalk|bangketa|nagtitinda|vendors?|debris|construction materials)\\M",
    "public_safety_infrastructure": "\\m(sunog|fire|streetlights?|street lights?|poste|pothole|lubak|manhole|live wire|kuryente|kawad|tulay|bridge|gumuho)\\M",
    "environmental_waste_hazard":   "\\m(basura|garbage|trash|tambak|kanal|drainage|barado|imburnal|usok|smoke|mabaho|baho|lamok|stagnant)\\M",
    "animal_welfare":               "\\m(aso|dogs?|pusa|cats?|askal|kinagat|nangangagat|stray|hayop|animals?)\\M",
    "traffic_violation":            "\\m(counterflow|counter-flow|overspeeding|trapik|traffic|walang helmet|no helmet|tricycle|double parking|beating the red)\\M",
    "peace_order_nuisance":         "\\m(ingay|maingay|noise|videoke|karaoke|inuman|lasing|drunk|nag-?aaway|rambol|tambay|sugal|gambling|harassment)\\M",
    "barangay_service":             "\\m(clearance|certificate|sertipiko|indigency|cedula|permit|barangay id)\\M"
  }';

/** The kind of complaint the words point to, when it is not the one chosen:
    the kind with the most matching words, offered only if the chosen kind
    matches none. Null when there is nothing to suggest. */
create or replace function public._smart_category_hint(p_category public.complaint_category,
                                                       p_subject text, p_description text)
returns jsonb
language sql
stable
security definer
set search_path = public, extensions
as $$
  with k as (select category_words from public.smart_rules where id = 1),
       txt as (select lower(coalesce(p_subject, '') || ' ' || coalesce(p_description, '')) as t),
       hits as (
         select c.key as cat,
                array(select distinct m[1] from regexp_matches(txt.t, c.value #>> '{}', 'g') as m) as words
           from k, txt, jsonb_each(k.category_words) c
       ),
       scored as (select cat, words, cardinality(words) as n from hits)
  select case
           when coalesce((select n from scored where cat = p_category::text), 0) > 0 then null
           else (select jsonb_build_object('category', s.cat, 'words', to_jsonb(s.words))
                   from scored s where s.n > 0 and s.cat <> p_category::text
                  order by s.n desc, s.cat limit 1)
         end
$$;

revoke all on function public._smart_category_hint(public.complaint_category, text, text) from public, anon, authenticated;

-- ---------- Try it --------------------------------------------------------------

/** Admins: the score, level, reasons and category hint a complaint would
    get if filed now at this spot. Saves nothing. */
create or replace function public.smart_preview(p_category public.complaint_category, p_subject text,
                                                p_description text, p_lat double precision default null,
                                                p_lng double precision default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  s record;
  v_geom geography;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can try the rules.' using errcode = 'insufficient_privilege';
  end if;
  if p_lat is not null and p_lng is not null then
    v_geom := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;
  end if;
  select * into s from public._smart_score(p_category, p_subject, p_description, v_geom, now(), null, null);
  return jsonb_build_object('score', s.score, 'level', s.level, 'reasons', s.reasons,
                            'category_hint', public._smart_category_hint(p_category, p_subject, p_description));
end $$;

revoke all on function public.smart_preview(public.complaint_category, text, text, double precision, double precision) from public, anon;
grant execute on function public.smart_preview(public.complaint_category, text, text, double precision, double precision) to authenticated;

-- ---------- the case card ----------------------------------------------------------

/** Admins: the case page's SMART card in one call (docs/SMART_SCREENS.md, 2 and 3). */
create or replace function public.smart_case_card(p_report uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  r public.reports%rowtype;
  t public.report_triage%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can see SMART results.' using errcode = 'insufficient_privilege';
  end if;
  select * into r from public.reports where id = p_report and deleted_at is null;
  if not found then return null; end if;
  select * into t from public.report_triage where report_id = p_report;

  return jsonb_build_object(
    'score', t.score,
    'level', t.level,
    'effective_level', t.effective_level,
    'reasons', coalesce(t.reasons, '[]'),
    'computed_at', t.computed_at,
    'override', case when t.override_level is null then null else jsonb_build_object(
        'level', t.override_level, 'reason', t.override_reason, 'at', t.override_at,
        'by', (select public.display_name(u.full_name) from public.users u where u.id = t.override_by)) end,
    'duplicates', coalesce((select jsonb_agg(to_jsonb(d)) from public.smart_duplicates_of(p_report) d), '[]'),
    'eta', (select to_jsonb(e) from public.smart_eta(r.category) e),
    'category_hint', public._smart_category_hint(r.category, r.subject, r.description),
    'tanods', coalesce((select jsonb_agg(to_jsonb(x)) from (
        select * from public.smart_tanod_ranking(p_report) limit 3) x), '[]'));
end $$;

revoke all on function public.smart_case_card(uuid) from public, anon;
grant execute on function public.smart_case_card(uuid) to authenticated;

-- ---------- the dashboard tiles ------------------------------------------------------

/** Admins: the dashboard's SMART tiles (docs/SMART_SCREENS.md, 5). */
create or replace function public.smart_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v jsonb;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can see SMART results.' using errcode = 'insufficient_privilege';
  end if;
  select jsonb_build_object(
           'urgent_waiting', count(*) filter (where t.effective_level = 'urgent'),
           'high_waiting',   count(*) filter (where t.effective_level = 'high'))
    into v
    from public.report_triage t
    join public.reports r on r.id = t.report_id
   where r.deleted_at is null
     and r.status in ('pending_review', 'validated')
     and t.effective_level in ('urgent', 'high')
     and not exists (select 1 from public.dispatches d
                      where d.report_id = r.id and d.state in ('assigned', 'accepted'));
  return v || (select jsonb_build_object(
                 'recurring', count(*),
                 'recurring_open', count(*) filter (where p.still_open > 0))
                 from public._smart_patterns(null) p);
end $$;

revoke all on function public.smart_summary() from public, anon;
grant execute on function public.smart_summary() to authenticated;
