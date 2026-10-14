-- 07_smart_language.sql: SMART reading Taglish (0125). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_a uuid; v_b uuid; v_adm uuid;
  r1 uuid; r2 uuid;
  s record;
  j jsonb;
  n integer;
  lng constant double precision := 121.01219; lat constant double precision := 14.51944;
begin
  v_a := gen_random_uuid(); v_b := gen_random_uuid(); v_adm := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'),
         now(), now()
    from (values (v_a, '+639999999941', 'Wika, Ana', 'resident'),
                 (v_b, '+639999999942', 'Wika, Ben', 'resident'),
                 (v_adm, '+639999999943', 'Wika, Admin', 'resident')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_a, v_b, v_adm);
  update public.users set role = 'admin' where id = v_adm;
  v_log := 'setup ok';

  -- word forms
  begin
    select * into s from public._smart_score('other', '', 'Nasusunog yung bahay sa kanto!', null, now(), null);
    if not s.reasons @> '[{"factor": "words", "detail": "fire", "matched": "nasusunog → sunog", "how": "grammar"}]' then raise exception '%', s.reasons; end if;
    select * into s from public._smart_score('other', '', 'May sinaksak dito, duguan yung lalaki.', null, now(), null);
    if not (s.reasons @> '[{"detail": "weapon", "matched": "sinaksak → saksak"}]' and s.reasons @> '[{"detail": "injury", "matched": "duguan → dugo"}]') then raise exception '%', s.reasons; end if;
    select * into s from public._smart_score('other', '', 'Binaha na naman ang kalye namin.', null, now(), null);
    if not s.reasons @> '[{"detail": "flooding", "matched": "binaha → baha"}]' then raise exception '%', s.reasons; end if;
    v_log := v_log || E'\n' || 'ok  nasusunog, sinaksak, duguan and binaha are read as sunog, saksak, dugo and baha';
  exception when others then v_log := v_log || E'\n' || 'FAIL word forms: ' || sqlerrm; end;

  begin
    select * into s from public._smart_score('other', '', 'Asong gala sa kanto, may mga batang naglalaro.', null, now(), null);
    if not s.reasons @> '[{"detail": "vulnerable", "matched": "batang → bata"}]' then raise exception '%', s.reasons; end if;
    v_log := v_log || E'\n' || 'ok  the linker -ng is read (batang: bata)';
  exception when others then v_log := v_log || E'\n' || 'FAIL linker: ' || sqlerrm; end;

  -- negation
  begin
    select * into s from public._smart_score('other', '', 'Walang sunog dito, nag-iihaw lang kami.', null, now(), null);
    if s.reasons @> '[{"factor": "words", "detail": "fire"}]' then raise exception 'counted: %', s.reasons; end if;
    if not s.reasons @> '[{"factor": "not counted", "detail": "fire", "how": "negated"}]' then raise exception 'not explained: %', s.reasons; end if;
    v_log := v_log || E'\n' || 'ok  "walang sunog" is not counted as a fire, and the reasons say so';
  exception when others then v_log := v_log || E'\n' || 'FAIL negation: ' || sqlerrm; end;

  begin
    select * into s from public._smart_score('other', '', 'Hindi sunog, pero may usok na makapal.', null, now(), null);
    if not s.reasons @> '[{"factor": "words", "detail": "fire", "matched": "usok"}]' then raise exception '%', s.reasons; end if;
    select * into s from public._smart_score('other', '', 'No flood but the kids are trapped.', null, now(), null);
    if s.reasons @> '[{"factor": "words", "detail": "flooding"}]' or not s.reasons @> '[{"factor": "words", "detail": "vulnerable"}]' then raise exception '%', s.reasons; end if;
    v_log := v_log || E'\n' || 'ok  a negation stops at a comma and at pero / but';
  exception when others then v_log := v_log || E'\n' || 'FAIL negation scope: ' || sqlerrm; end;

  -- spelling
  begin
    select * into s from public._smart_score('other', '', 'snog sa tabi ng poste', null, now(), null);
    if not s.reasons @> '[{"detail": "fire", "matched": "snog → sunog", "how": "spelling"}]' then raise exception '%', s.reasons; end if;
    select * into s from public._smart_score('other', '', 'nakuryinte yung lalaki sa poste', null, now(), null);
    if not s.reasons @> '[{"detail": "live wire"}]' then raise exception 'kuryinte %', s.reasons; end if;
    select * into s from public._smart_score('other', '', 'may kurynte na lumalabas sa poste', null, now(), null);
    if not s.reasons @> '[{"detail": "live wire", "how": "guess"}]' then raise exception 'guess %', s.reasons; end if;
    v_log := v_log || E'\n' || 'ok  texting spellings (snog, kuryinte) and one-letter slips (kurynte) are read';
  exception when others then v_log := v_log || E'\n' || 'FAIL spelling: ' || sqlerrm; end;

  begin
    select * into s from public._smart_score('other', '', 'May batas tungkol sa bahay at sa banta.', null, now(), null);
    if s.reasons @> '[{"factor": "words"}]' then raise exception '%', s.reasons; end if;
    v_log := v_log || E'\n' || 'ok  near words are not over-read (bahay, batas, banta count for nothing)';
  exception when others then v_log := v_log || E'\n' || 'FAIL over-reading: ' || sqlerrm; end;

  -- phrases
  begin
    j := public._smart_category_hint('other', '', 'Walang helmet yung nag-counterflow na tricycle.');
    if j ->> 'category' <> 'traffic_violation' or not (j -> 'words') ? 'walang helmet' then raise exception '%', j; end if;
    v_log := v_log || E'\n' || 'ok  a phrase ("walang helmet") counts as written, its negation word included';
  exception when others then v_log := v_log || E'\n' || 'FAIL phrase: ' || sqlerrm; end;

  -- duplicates by meaning
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
  values (v_a, 'environmental_waste_hazard', 'Garbage', 'Tambak na garbage sa drainage, amoy na amoy.', lat, lng, now() - interval '3 hours')
  returning id into r1;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
  values (v_b, 'environmental_waste_hazard', 'Basura sa imburnal', 'Puno ng basura ang imburnal sa harap namin.', lat + 0.0004, lng, now())
  returning id into r2;
  begin
    if extensions.similarity(lower('Garbage Tambak na garbage sa drainage, amoy na amoy.'),
                             lower('Basura sa imburnal Puno ng basura ang imburnal sa harap namin.')) >= 0.3 then
      raise exception 'the spelling alone would have found it; the test proves nothing';
    end if;
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    select count(*) into n from public.smart_duplicates(r2) d where d.report_id = r1;
    execute 'reset role';
    if n <> 1 then raise exception 'not found'; end if;
    v_log := v_log || E'\n' || 'ok  "garbage sa drainage" and "basura sa imburnal" are found as the same problem';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL meaning: ' || sqlerrm; end;

  -- the word list is the barangay's
  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    insert into public.smart_lexicon (variant, root, kind, note) values ('nagliliyab', 'sunog', 'form', 'ablaze');
    execute 'reset role';
    select * into s from public._smart_score('other', '', 'Nagliliyab ang bubong!', null, now(), null);
    if not s.reasons @> '[{"detail": "fire", "matched": "nagliliyab → sunog"}]' then raise exception '%', s.reasons; end if;
    v_log := v_log || E'\n' || 'ok  an admin adds a word (nagliliyab: sunog) and it counts at once';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL lexicon: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    insert into public.smart_lexicon (variant, root, kind) values ('ingay', 'sunog', 'synonym');
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD a resident changed the word list (should have been refused)';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'ok  a resident cannot change the word list (refused: ' || left(sqlerrm, 60) || ')'; end;

  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    perform * from public.smart_read('may sunog');
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD a resident used smart_read (should have been refused)';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'ok  a resident cannot use smart_read (refused: ' || left(sqlerrm, 60) || ')'; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
