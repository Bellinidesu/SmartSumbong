-- 60_error_log_rate.sql: the error log is rationed per source address (0182, backend sweep). Rolled back.
do $sweep$
declare
  v_log text := 'setup ok';   -- the first line is joined to psql's ERROR line, so the checks start on the next
  i integer; n integer;
begin
  delete from public.portal_errors;
  delete from public.rate_limit_hits;

  -- 1. one address files 60 browser errors an hour and no more; another address still gets through
  begin
    execute 'set local role anon';
    perform set_config('request.headers', '{"cf-connecting-ip": "203.0.113.7"}', true);
    for i in 1 .. 100 loop perform public.log_portal_error('browser', '/admin/x.php', 'made up ' || i); end loop;
    reset role;
    select count(*) into n from public.portal_errors where message like 'made up %';
    if n <> 60 then raise exception '% rows from one address, not 60', n; end if;
    execute 'set local role anon';
    perform set_config('request.headers', '{"cf-connecting-ip": "203.0.113.8"}', true);
    perform public.log_portal_error('browser', '/admin/x.php', 'a real error');
    reset role;
    if not exists (select 1 from public.portal_errors where message = 'a real error') then raise exception 'a second address was refused'; end if;
    v_log := v_log || E'\n' || 'ok  one address files 60 browser errors an hour; another address is not held back';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL browser rate: ' || sqlerrm; end;

  -- 2. the Edge Functions (service role) and the portal's server are not held to the browser limit; an unknown source files nothing
  begin
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    for i in 1 .. 100 loop perform public.log_portal_error('function', 'password-otp', 'fn error ' || i); end loop;
    select count(*) into n from public.portal_errors where message like 'fn error %';
    if n <> 100 then raise exception 'the functions were limited: %', n; end if;
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    perform set_config('request.headers', '{"cf-connecting-ip": "203.0.113.9"}', true);
    for i in 1 .. 100 loop perform public.log_portal_error('server', '/admin/y.php', 'server error ' || i); end loop;
    perform public.log_portal_error('other', 'x', 'nope');
    perform public.log_portal_error('function', 'x', 'a signed-out caller as the function');
    reset role;
    select count(*) into n from public.portal_errors where message like 'server error %';
    if n <> 100 then raise exception 'the server was limited below 600: %', n; end if;
    if exists (select 1 from public.portal_errors where message in ('nope', 'a signed-out caller as the function')) then raise exception 'an unknown or forged source filed'; end if;
    v_log := v_log || E'\n' || 'ok  the functions are not limited, the portal''s server has room, an unknown or forged source files nothing';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL others: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
