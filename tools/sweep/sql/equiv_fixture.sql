-- K-04 equivalence fixture (THROWAWAY database only; tools/sweep/equiv_case_rule.py). Every person of every rung and state x every case variant
-- that the case rule looks at (category, committee incl. a switched-off one, waiting for placement, handler, assignment, earlier hands in the log,
-- concerns in another committee's category, forwarded in/away, deleted), with one or more rows in every table that hangs off a case.
-- Rows are written as the superuser with triggers off (replica): the point is to read them back as each person, not to file them.
\set ON_ERROR_STOP on
create schema if not exists eq;
create table if not exists eq.actors (name text primary key, id uuid not null);
create table if not exists eq.snap (label text, actor text, tbl text, k text);
create table if not exists eq.cfg (k text primary key, v text);
grant usage on schema eq to authenticated;
grant select, insert on eq.snap to authenticated;
grant select on eq.actors, eq.cfg to authenticated;

do $fx$
declare
  a record; v_id uuid; i int := 0; r uuid; d uuid; d2 uuid; u uuid;
  ca text; cb text; coff text := 'eq_off';
  cat_a public.complaint_category; cat_b public.complaint_category; cat_none public.complaint_category;
  cats public.complaint_category[]; coms text[]; hands text[] := array[null, 'kA', 'sA', 'kB', 'sup']; asg text[] := array[null, 'sA', 'sB'];
  logs text[] := array['none', 'took', 'assign']; extra text[] := array['none', 'a', 'b'];
  c_cat public.complaint_category; c_com text; c_aw boolean; c_h text; c_as text; c_log text; c_ex text; c_del boolean; res uuid;
  sts public.report_status[] := array['pending_review','validated','assigned','in_progress','offline_investigation','resolved','closed','rejected','cancelled']::public.report_status[];
  img text := 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/';
begin
  -- two active committees with categories, and a category no active committee owns
  select c.key into ca from public.committees c where c.active and exists (select 1 from public.committee_categories cc where cc.committee = c.key) order by c.sort, c.key limit 1;
  select c.key into cb from public.committees c where c.active and c.key <> ca and exists (select 1 from public.committee_categories cc where cc.committee = c.key
          and cc.category not in (select category from public.committee_categories where committee = ca)) order by c.sort, c.key limit 1;
  select cc.category into cat_a from public.committee_categories cc where cc.committee = ca and cc.category not in (select category from public.committee_categories where committee = cb) limit 1;
  select cc.category into cat_b from public.committee_categories cc where cc.committee = cb and cc.category not in (select category from public.committee_categories where committee = ca) limit 1;
  select e.v into cat_none from (select unnest(enum_range(null::public.complaint_category)) v) e
   where not exists (select 1 from public.committee_categories cc join public.committees c on c.key = cc.committee and c.active where cc.category = e.v) limit 1;
  if cat_none is null then   -- every category has an active committee: free one by giving it only to a switched-off committee
    select e.v into cat_none from (select unnest(enum_range(null::public.complaint_category)) v) e where e.v not in (cat_a, cat_b) order by 1 desc limit 1;
    delete from public.committee_categories where category = cat_none;
  end if;
  insert into public.committees (key, name_en, name_fil, short_en, active) select coff, 'Switched off (equivalence)', 'Patay (equivalence)', 'Off', false where not exists (select 1 from public.committees where key = coff);
  update public.committees set active = false where key = coff;
  insert into public.committee_categories (committee, category) values (coff, cat_none) on conflict do nothing;
  insert into eq.cfg values ('ca', ca), ('cb', cb), ('cat_a', cat_a::text), ('cat_b', cat_b::text), ('cat_none', cat_none::text) on conflict (k) do update set v = excluded.v;

  -- the people
  for a in select * from (values
      ('res1','resident',null,null,false,false), ('res2','resident',null,null,false,false), ('res3','resident',null,null,false,false),
      ('res4','resident',null,null,false,false), ('res5','resident',null,null,false,false), ('res_susp','resident',null,null,true,false),
      ('tan1','tanod',null,null,false,false), ('tan2','tanod',null,null,false,false), ('tan3','tanod',null,null,false,false),
      ('kA','admin','committee','A',false,false), ('kA2','admin','committee','A',false,false), ('kB','admin','committee','B',false,false),
      ('kOff','admin','committee','OFF',false,false), ('kNone','admin','committee',null,false,false),
      ('kAsusp','admin','committee','A',true,false), ('kAret','admin','committee','A',false,true),
      ('sA','admin','moderator','A',false,false), ('sA2','admin','moderator','A',false,false), ('sB','admin','moderator','B',false,false),
      ('sNone','admin','moderator',null,false,false), ('sAsusp','admin','moderator','A',true,false), ('sAret','admin','moderator','A',false,true),
      ('cap','admin','captain',null,false,false), ('capSusp','admin','captain',null,true,false),
      ('sup','admin','super',null,false,false), ('supNull','admin',null,null,false,false), ('supRet','admin','super',null,false,true)
    ) x(name, role, tier, com, susp, ret)
  loop
    i := i + 1;
    if exists (select 1 from eq.actors where name = a.name) then continue; end if;
    v_id := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', public.auth_email_for('+63977' || lpad(i::text, 7, '0')),
            jsonb_build_object('full_name', 'Equiv, ' || a.name, 'mobile_number', '+63977' || lpad(i::text, 7, '0'), 'role', 'resident', 'id_type', 'barangay_id',
              'id_image_url', img || 'ids/' || gen_random_uuid() || '.jpg', 'selfie_url', img || 'selfies/' || gen_random_uuid() || '.jpg'), now(), now());
    set local session_replication_role = replica;
    update public.users set verification_status = 'verified', verified_at = now(), role = a.role::public.user_role, admin_tier = a.tier,
           committee = case a.com when 'A' then ca when 'B' then cb when 'OFF' then coff end,
           is_suspended = a.susp, is_retired = a.ret,
           duty_status = case when a.role = 'tanod' then 'on_duty' else duty_status end
     where id = v_id;
    set local session_replication_role = origin;
    insert into eq.actors values (a.name, v_id);
  end loop;
  insert into eq.actors values ('ghost', '00000000-0000-4000-8000-00000000e0e0') on conflict do nothing;   -- signed in, no account row

  -- the cases: the full product of what the rule reads
  i := 0;
  set local session_replication_role = replica;
  foreach c_cat in array array[cat_a, cat_b, cat_none] loop
   foreach c_com in array array[null, ca, cb, coff] loop
    foreach c_aw in array array[false, true] loop
     foreach c_h in array hands loop
      foreach c_as in array asg loop
       continue when c_h is null and c_as is not null;
       foreach c_log in array logs loop
        foreach c_ex in array extra loop
         foreach c_del in array array[false, true] loop
          i := i + 1;
          res := case when c_del and i % 2 = 0 then (select id from eq.actors where name = 'res5')
                      else (select id from eq.actors where name = (array['res1','res2','res4'])[1 + i % 3]) end;
          insert into public.reports (tracking_id, resident_id, category, subject, description, latitude, longitude, status, is_anonymous, is_sensitive, is_public,
                                      committee, awaiting_placement, handler_id, assigned_to, assigned_by, deleted_at, created_at)
          values ('EQ-' || lpad(i::text, 5, '0'), res, c_cat, 'Equiv case ' || i, 'Equivalence fixture case number ' || i, 14.519 + i / 1e6, 121.012, sts[1 + i % 9],
                  i % 3 = 0, i % 5 = 0, i % 4 = 0, c_com, c_aw,
                  (select id from eq.actors where name = c_h), (select id from eq.actors where name = c_as),
                  case when c_as is not null then (select id from eq.actors where name = 'kA') end,
                  case when c_del then now() end, now() - make_interval(mins => i))
          returning id into r;
          insert into public.report_concerns (report_id, category) values (r, c_cat);
          if c_ex = 'a' and c_cat <> cat_a then insert into public.report_concerns (report_id, category) values (r, cat_a); end if;
          if c_ex = 'b' and c_cat <> cat_b then insert into public.report_concerns (report_id, category) values (r, cat_b); end if;
          if c_log = 'took' then
            insert into public.case_handler_log (report_id, admin_id, action) values (r, (select id from eq.actors where name = 'sA'), (array['take','take_over','accept'])[1 + i % 3]);
          elsif c_log = 'assign' then
            insert into public.case_handler_log (report_id, admin_id, action) values (r, (select id from eq.actors where name = 'sA'), (array['assign','decline','release','unassign','escalate','return'])[1 + i % 6]);
          end if;
          if i % 5 = 0 then insert into public.case_handler_log (report_id, admin_id, action) values (r, (select id from eq.actors where name = 'kA'), 'take'); end if;
          if i % 6 = 0 then insert into public.case_forwards (report_id, kind, from_committee, to_committee, actor) values (r, 'forward', ca, cb, (select id from eq.actors where name = 'sup'));
          elsif i % 6 = 1 then insert into public.case_forwards (report_id, kind, from_committee, to_committee, actor) values (r, 'forward', cb, ca, (select id from eq.actors where name = 'sup'));
          elsif i % 6 = 2 then insert into public.case_forwards (report_id, kind, from_committee, to_committee, actor) values (r, 'forward', coff, null, (select id from eq.actors where name = 'kA'));
          end if;
          insert into public.status_logs (report_id, changed_by, new_status, remark, is_system) values (r, res, sts[1 + i % 9], 'equiv', true);
          -- notices: to the scoped people and a rotating one, so every rung reads (or not) a notice of every case
          insert into public.notifications (user_id, report_id, kind, message)
          select x.id, r, 'status_change', 'Equiv notice ' || i from eq.actors x
           where x.name in ('kA','sA','kB','sB','kNone','sNone','kOff','kAret','sAsusp','res1','tan1','cap')
              or x.name = (select name from eq.actors where name <> 'ghost' order by name offset (i % 27) limit 1);
          if i % 5 = 0 then insert into public.detail_requests (report_id, requested_by, message) values (r, (select id from eq.actors where name = 'kA'), 'equiv'); end if;
          d := null; d2 := null;
          if i % 4 = 1 then
            insert into public.dispatches (report_id, tanod_id, assigned_by, state, accepted_at, is_primary) values (r, (select id from eq.actors where name = 'tan1'), (select id from eq.actors where name = 'kA'), 'accepted', now(), true) returning id into d;
          elsif i % 4 = 2 then
            insert into public.dispatches (report_id, tanod_id, assigned_by, state, is_primary) values (r, (select id from eq.actors where name = 'tan2'), (select id from eq.actors where name = 'kB'), 'assigned', true) returning id into d;
          elsif i % 4 = 3 then
            insert into public.dispatches (report_id, tanod_id, assigned_by, state, rerouted_at, reroute_reason, is_primary) values (r, (select id from eq.actors where name = 'tan1'), (select id from eq.actors where name = 'sup'), 'rerouted', now(), 'equiv', false) returning id into d;
            insert into public.dispatches (report_id, tanod_id, assigned_by, state, accepted_at, is_primary) values (r, (select id from eq.actors where name = 'tan3'), (select id from eq.actors where name = 'sup'), 'accepted', now(), true) returning id into d2;
          end if;
          if d is not null then
            insert into public.dispatch_updates (dispatch_id, author_id, kind, body) values (d, (select tanod_id from public.dispatches where id = d), 'note', 'equiv') returning id into u;
            insert into public.dispatch_media (dispatch_id, media_url, mime_type, bytes) values (d, img || 'dispatch/' || gen_random_uuid() || '.jpg', 'image/jpeg', 100);
            insert into public.dispatch_media (dispatch_id, update_id, media_url, mime_type, bytes) values (d, u, img || 'dispatch/' || gen_random_uuid() || '.jpg', 'image/jpeg', 100);
          end if;
          if d2 is not null then insert into public.dispatch_updates (dispatch_id, author_id, kind, step) values (d2, (select id from eq.actors where name = 'tan3'), 'step', 'arrived'); end if;
          if i % 7 = 0 then insert into public.escalation_requests (report_id, dispatch_id, requested_by, reason, status) values (r, d, (select id from eq.actors where name = (case when d is null then 'kA' else 'tan1' end)), 'equiv', 'pending'); end if;
          if i % 5 = 1 then insert into public.feedback (report_id, resident_id, rating) values (r, res, 4); end if;
          if i % 8 = 0 then insert into public.look_shares (report_id, tanod_id, sent_by, message) values (r, (select id from eq.actors where name = 'tan2'), (select id from eq.actors where name = 'kA'), 'equiv'); end if;
          if i % 6 = 2 then insert into public.report_evidence (report_id, posted_by, kind, media_url, mime_type, bytes) values (r, (select id from eq.actors where name = 'kA'), 'update', img || 'barangay/' || gen_random_uuid() || '.jpg', 'image/jpeg', 100); end if;
          insert into public.report_media (report_id, media_url, mime_type, bytes) values (r, img || 'reports/' || gen_random_uuid() || '.jpg', 'image/jpeg', 100);
          if i % 3 = 0 then insert into public.report_messages (report_id, author_id, from_barangay, body) values (r, res, false, 'equiv'); end if;
          if i % 3 = 1 then insert into public.report_messages (report_id, author_id, from_barangay, body) values (r, (select id from eq.actors where name = 'kA'), true, 'equiv'); end if;
          insert into public.report_triage (report_id, score, level, reasons) values (r, 10 + i % 80, 'normal', '[]');
          if i % 9 = 0 then insert into public.resolution_checks (report_id, resident_id) values (r, res); end if;
          if i % 10 = 0 then insert into public.sla_extensions (report_id, requested_by, previous_due, new_due, reason) values (r, (select id from eq.actors where name = 'kA'), now(), now() + interval '1 day', 'equiv reason'); end if;
          if i % 5 = 3 then insert into public.smart_events (report_id, kind, summary) values (r, 'equiv', 'equiv'); end if;
          if i % 11 = 0 then insert into public.smart_overrides (report_id, from_level, to_level, score, reasons, reason, by_user) values (r, 'normal', 'high', 10, '[]', 'equiv', (select id from eq.actors where name = 'kA')); end if;
         end loop;
        end loop;
       end loop;
      end loop;
     end loop;
    end loop;
   end loop;
  end loop;
  insert into public.notifications (user_id, report_id, kind, message) select x.id, null, 'status_change', 'Equiv notice without a case' from eq.actors x where x.name <> 'ghost';
  insert into public.smart_events (report_id, kind, summary) values (null, 'equiv', 'no case');
  set local session_replication_role = origin;
end $fx$;
analyze;
select (select count(*) from public.reports where tracking_id like 'EQ-%') as cases, (select count(*) from eq.actors) as people;
