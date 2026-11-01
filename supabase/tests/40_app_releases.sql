-- 40_app_releases.sql: the self-updater's releases (0161). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_sup uuid := gen_random_uuid(); v_po uuid := gen_random_uuid(); v_res uuid := gen_random_uuid();
  v_a uuid; v_b uuid; j jsonb; n integer;
  sha constant text := repeat('a1', 32);
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999961', 'Update, Super'), (v_po, '+639999999962', 'Update, Peace'), (v_res, '+639999999963', 'Update, Ana')) as x(id, mob, nm);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_sup, v_po, v_res);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'peace_order' where id = v_po;

  -- 1. only a super admin publishes; the build must rise; the link, the checksum and the version must be well formed
  begin
    perform set_config('request.jwt.claim.sub', v_po::text, true);
    begin perform public.app_release_publish('1.0.1', 2, 'https://example.org/a.apk', sha); raise exception 'a committee admin published a version';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    begin perform public.app_release_publish('1.0.1', 2, 'https://example.org/a.apk', sha); raise exception 'a resident published a version';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    v_a := public.app_release_publish('1.0.1', 2, 'https://example.org/a.apk', upper(sha), 'Faster map', 'Mas mabilis na mapa', false);
    if (select sha256 from public.app_releases where id = v_a) <> sha then raise exception 'the checksum was not kept in lower case'; end if;
    begin perform public.app_release_publish('1.0.2', 2, 'https://example.org/b.apk', sha); raise exception 'the same build number was published twice';
    exception when check_violation then null; end;
    begin perform public.app_release_publish('1.0.2', 1, 'https://example.org/b.apk', sha); raise exception 'a lower build number was published';
    exception when check_violation then null; end;
    begin perform public.app_release_publish('1.0.2', 3, 'http://example.org/b.apk', sha); raise exception 'a link that is not https was accepted';
    exception when check_violation then null; end;
    begin perform public.app_release_publish('1.0.2', 3, 'https://example.org/b.apk', 'abc123'); raise exception 'a short checksum was accepted';
    exception when check_violation then null; end;
    begin perform public.app_release_publish('one', 3, 'https://example.org/b.apk', sha); raise exception 'a version that is not numbers was accepted';
    exception when check_violation then null; end;
    v_log := v_log || E'\n' || 'ok  only a super admin publishes; the build number must rise; the link must be https, the checksum 64 hex characters, the version numbers';
  exception when others then v_log := v_log || E'\n' || 'FAIL publish: ' || sqlerrm; end;

  -- 2. everyone, signed in or not, asks for the newest active one; withdrawing it brings the one before back
  begin
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    v_b := public.app_release_publish('1.1.0', 5, 'https://example.org/c.apk', repeat('b2', 32), 'Update', null, true);
    set local role anon;
    j := public.latest_app_release();
    if j->>'version' <> '1.1.0' or (j->>'build')::int <> 5 or not (j->>'mandatory')::boolean then raise exception 'the newest was not offered to a signed-out phone: %', j; end if;
    reset role;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    begin perform public.app_release_set_active(v_b, false); raise exception 'a resident withdrew a release'; exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.app_release_set_active(v_b, false);
    set local role anon;
    j := public.latest_app_release();
    if j->>'version' <> '1.0.1' then raise exception 'withdrawing it did not bring the earlier one back: %', j; end if;
    reset role;
    perform public.app_release_set_active(v_b, true);
    v_log := v_log || E'\n' || 'ok  a signed-out phone is offered the newest active release; a resident cannot withdraw one; withdrawing brings the earlier one back';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL latest: ' || sqlerrm; end;

  -- 3. the table is read only by a super admin; the switch turns the offers off
  begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    select count(*) into n from public.app_releases; if n <> 0 then raise exception 'a resident read % releases', n; end if;
    perform set_config('request.jwt.claim.sub', v_po::text, true);
    select count(*) into n from public.app_releases; if n <> 0 then raise exception 'a committee admin read % releases', n; end if;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    select count(*) into n from public.app_releases; if n < 2 then raise exception 'the super admin read only % releases', n; end if;
    reset role;
    update public.feature_switches set enabled = false where key = 'app_updates';
    if public.latest_app_release() is not null then raise exception 'a release was offered while updates were switched off'; end if;
    update public.feature_switches set enabled = true where key = 'app_updates';
    v_log := v_log || E'\n' || 'ok  residents and committee admins read no release; the super admin reads them all; the switch turns the offers off';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL reading and switch: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
