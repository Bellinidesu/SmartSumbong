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

insert into public.sla_policies (category, resolution_hours, accept_minutes) values
  ('street_obstruction',           72,  30),
  ('public_safety_infrastructure', 48,  20),
  ('environmental_waste_hazard',   72,  30),
  ('animal_welfare',               96,  30),
  ('traffic_violation',            48,  20),
  ('barangay_service',            120,  60),
  ('peace_order_nuisance',         24,  15)
on conflict (category) do update
  set resolution_hours = excluded.resolution_hours,
      accept_minutes   = excluded.accept_minutes,
      updated_at       = now();
