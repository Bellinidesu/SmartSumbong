-- =============================================================
-- SmartSumbong — 0147 The barangay's rules and hotlines, from the portal
--
-- Ready for Barangay 183, step 5 (Ace, 29 Oct 2026: "everything in the
-- system is customizable and tunable to the needs of 183"). The tables were
-- already there and already written only by a super admin (0145):
--
--   operational_settings   dispatch attempts, how fresh a tanod's position
--                          must be, the unattended-report alert, photos per
--                          report, deadline extensions, jobs per tanod,
--                          reports per resident a day, pausing new reports
--   sla_policies           per category: hours to resolve, minutes for a
--                          tanod to accept
--   hotline_groups/numbers the Emergency screen's directory (0025)
--
-- The portal now edits them (Settings > Rules and Hotlines). What this
-- migration adds is the part a category made in Settings (0146) was missing:
--
--   catalogue_fill()       gives every category a deadline and a first
--                          committee, copied from "Others". category_save
--                          cannot do it itself: a new value of an enum is
--                          usable only from the next transaction, so the
--                          portal calls this right after.
--   set_report_deadline    a category with no deadline row takes "Others'"
--                          hours instead of having no deadline at all.
--   hotlines read by admins 0145 replaced the hotlines' "admins do anything"
--                          rule with super-admin writes, which left only the
--                          public "what is on" read: no administrator could
--                          see a switched-off number, and switching one off
--                          failed (the row it leaves must be readable).
-- =============================================================

set search_path = public, extensions;

create policy hotline_groups_admin_read on public.hotline_groups for select using ((select public.is_admin()));
create policy hotline_numbers_admin_read on public.hotline_numbers for select using ((select public.is_admin()));

create or replace function public.catalogue_fill()
returns integer
language plpgsql security definer set search_path = public, extensions as $$
declare n integer; m integer;
begin
  if not public.is_super_admin() then raise exception 'Only a super admin edits the complaint categories' using errcode = 'insufficient_privilege'; end if;
  insert into public.sla_policies (category, resolution_hours, accept_minutes, auto_dispatch_on_file)
  select c.key::public.complaint_category, coalesce(o.resolution_hours, 120), coalesce(o.accept_minutes, 60), false
    from public.complaint_categories c
    left join public.sla_policies o on o.category = 'other'
   where not exists (select 1 from public.sla_policies s where s.category::text = c.key);
  get diagnostics n = row_count;
  insert into public.committee_for_category (category, committee)
  select c.key::public.complaint_category, o.committee
    from public.complaint_categories c
    join public.committee_for_category o on o.category = 'other'
   where not exists (select 1 from public.committee_for_category x where x.category::text = c.key);
  get diagnostics m = row_count;
  return n + m;
end $$;
revoke all on function public.catalogue_fill() from public, anon;
grant execute on function public.catalogue_fill() to authenticated;
comment on function public.catalogue_fill() is '0147: a deadline and a first committee for every category (copied from Others); the portal calls it after category_save.';

-- A category with no deadline row of its own takes Others' hours.
do $$
declare d text := pg_get_functiondef('public.set_report_deadline()'::regprocedure);
begin
  if position('category = ''other''' in d) = 0 then
    d := replace(d, E'    if hrs is not null then', E'    if hrs is null then\n      select resolution_hours into hrs from public.sla_policies where category = ''other'';\n    end if;\n    if hrs is not null then');
    if position('category = ''other''' in d) = 0 then raise exception '0147: set_report_deadline did not take the patch'; end if;
    execute d;
  end if;
end $$;
