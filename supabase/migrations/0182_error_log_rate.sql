-- 0182: the error log is rationed per caller (backend sweep, 19 Nov 2026).
-- DRAFT: not applied until Ace says "apply 0182".
--
-- log_portal_error is callable signed out (a browser reports a script error before anyone signs in) and files each new message as a
-- new row; the table keeps the 500 most recently seen. Anyone with the public key could post 500 made-up messages and push every
-- real error out, or raise the hourly health alert (it counts recent errors) on demand. Now a source address may file at most 60
-- browser errors an hour; the portal's own server (one address, 'server') 600; the Edge Functions (service role) are not limited.
-- Repeats of one message were never the problem (they only raise its count), but they are counted too, which keeps the rule simple.

set search_path = public, extensions;

create or replace function public.log_portal_error(p_source text, p_page text, p_message text, p_detail text default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_page text := left(coalesce(nullif(trim(p_page), ''), '?'), 200);
  v_msg  text := left(coalesce(nullif(trim(p_message), ''), '(no message)'), 500);
  v_sig  text;
begin
  if p_source not in ('server', 'browser', 'function') then return; end if;
  -- 0119: only the Edge Functions themselves (service role) log as 'function'.
  if p_source = 'function' and coalesce(auth.role(), '') <> 'service_role' then return; end if;
  -- 0182: an address cannot flood the log
  if p_source <> 'function'
     and not public.take_rate_slot('error-log:' || p_source || ':' || coalesce(public.request_source(), 'unknown'),
                                   case p_source when 'server' then 600 else 60 end, interval '1 hour') then
    return;
  end if;
  v_sig := md5(p_source || '|' || v_page || '|' || v_msg);
  insert into public.portal_errors (source, page, message, detail, signature)
  values (p_source, v_page, v_msg, left(p_detail, 2000), v_sig)
  on conflict (signature) do update
     set count = portal_errors.count + 1, last_seen = now(),
         detail = coalesce(excluded.detail, portal_errors.detail);
  -- Keep the table small: the 500 most recently seen.
  delete from public.portal_errors where id in (
    select id from public.portal_errors order by last_seen desc offset 500);
end $$;
