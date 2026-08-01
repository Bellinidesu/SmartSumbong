-- =============================================================
-- SmartSumbong — seed data
-- FAKE DATA ONLY. This repository is public: never commit real
-- resident names, real complaints, or ID images.
--
-- SLA windows below are PLACEHOLDERS. The barangay captain gave
-- 30–45 days for Katarungang Pambarangay, but that is the manual
-- mediation timeline, not the digital response target. Confirm
-- these with the barangay before defense.
-- =============================================================

insert into public.sla_policies (category, resolution_hours, accept_minutes, auto_dispatch_on_file) values
  ('street_obstruction',           72,  30, false),
  ('public_safety_infrastructure', 48,  20, true),
  ('environmental_waste_hazard',   72,  30, false),
  ('animal_welfare',               96,  30, false),
  ('traffic_violation',            48,  20, true),
  ('barangay_service',            120,  60, false),
  ('peace_order_nuisance',         24,  15, true)
on conflict (category) do update
  set resolution_hours = excluded.resolution_hours,
      accept_minutes   = excluded.accept_minutes,
      auto_dispatch_on_file = excluded.auto_dispatch_on_file,
      updated_at       = now();
