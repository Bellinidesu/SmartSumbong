-- 0120: tracking IDs past 9,999 (backend review, 10 Oct 2026).
--
-- assign_tracking_id() (0001) padded the counter with lpad(n, 4, '0'), and
-- PostgreSQL's lpad also CUTS longer text to that length: report 10,000
-- became BRG-YYYY-1000, the same ID as report 1,000, the unique index
-- refused it, and from then on every new complaint would have failed to
-- file. Found by the volume test (supabase/tests/perf). The counter never
-- resets, so this was the 10,000th complaint ever, not per year.
-- Now four digits at least, as many as the number needs after that.

create or replace function public.assign_tracking_id()
returns trigger language plpgsql as $$
declare
  v_n bigint;
begin
  if new.tracking_id is null then
    v_n := nextval('public.report_seq');
    new.tracking_id := 'BRG-' || to_char(now(), 'YYYY') || '-' ||
                       lpad(v_n::text, greatest(4, length(v_n::text)), '0');
  end if;
  return new;
end $$;
