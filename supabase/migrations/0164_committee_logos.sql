-- =============================================================
-- SmartSumbong — 0164 Each rung's own portal: the committee's logo, and staff in Personnel
--
-- Ace, 4 Nov 2026 (Priority 2): a Kagawad's and a staff member's sidebar carries their committee's logo beside the barangay
-- seal; the super admin chooses each committee's logo. Staff get Personnel, scoped to their committee and view only: their
-- committee's tanods (already theirs through account_directory and personnel_committees) and their fellow staff's cards (not
-- their Kagawad's: 0153 keeps a Kagawad's card from the staff under them).
--
--   committees.logo_url            the committee's logo (an upload; null: the committee's symbol in its colour stands in)
--   committee_set_logo(key, url)   a super admin sets or clears it
--   _sees_punch_card(user)         a staff member also sees the punch cards of their committee's other staff
-- =============================================================

set search_path = public, extensions;

alter table public.committees add column if not exists logo_url text
  check (logo_url is null or logo_url ~ '^https://res\.cloudinary\.com/');
comment on column public.committees.logo_url is '0164: the committee''s logo, shown beside the barangay seal in its admins'' sidebar. Null: its symbol stands in. Set by committee_set_logo().';

create or replace function public.committee_set_logo(p_key text, p_url text)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare v_url text := nullif(trim(coalesce(p_url, '')), '');
begin
  if not public.is_super_admin() then raise exception 'Only a super admin sets a committee''s logo' using errcode = 'insufficient_privilege'; end if;
  if v_url is not null and v_url !~ '^https://res\.cloudinary\.com/' then raise exception 'The logo must be an uploaded picture' using errcode = 'check_violation'; end if;
  update public.committees set logo_url = v_url, updated_by = auth.uid(), updated_at = now() where key = p_key;
  if not found then raise exception 'No such committee' using errcode = 'check_violation'; end if;
  perform public._smart_event('access', null, format(case when v_url is null then 'Committee logo removed: %s' else 'Committee logo set: %s' end, p_key),
                              jsonb_build_object('committee', p_key, 'logo', v_url));
end $$;
revoke all on function public.committee_set_logo(text, text) from public, anon;
grant execute on function public.committee_set_logo(text, text) to authenticated;
comment on function public.committee_set_logo(text, text) is '0164: a super admin sets (or, with null, clears) a committee''s logo.';

-- A staff member (moderator) sees the other staff of their own committee; a Kagawad still sees their staff; nobody in a
-- committee sees another committee's cards, and staff never see their Kagawad's.
create or replace function public._sees_punch_card(p_user uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select p_user = auth.uid()
      or coalesce(public.is_full_viewer(), false)
      or (public.admin_tier() in ('committee', 'moderator') and exists (
            select 1 from public.users t, public.users me
             where t.id = p_user and me.id = auth.uid() and t.role = 'admin' and me.committee is not null and t.committee = me.committee
               and t.admin_tier = 'moderator'))
$$;
revoke all on function public._sees_punch_card(uuid) from public;
grant execute on function public._sees_punch_card(uuid) to authenticated;
