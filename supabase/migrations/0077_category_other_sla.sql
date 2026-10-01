-- 0077 — The deadline rule for "Others" (0076): the same windows as
-- Barangay Service, the broadest of the seven. The barangay can tune it in
-- sla_policies like any other category.

insert into public.sla_policies (category, resolution_hours, accept_minutes)
values ('other', 120, 60)
on conflict (category) do nothing;
