-- =============================================================
-- SmartSumbong — 0150 Committee colours and the super admin colour
--
-- Roles and pages, step 1b (docs/ROLES_AND_PAGES.md, section 2, locked with
-- Ace on 29-30 Oct 2026). A committee admin's sidebar wears the committee's
-- colour, so a screenshot says which committee it came from; every super
-- admin shares one colour, branding blue unless they change it.
--
--   committees.colour            chosen by a super admin when making or
--                                editing a committee (committee_save)
--   barangay_profile.super_colour  the one colour of every super admin
--
-- "Too close counts as taken" (Ace: "exact color and all close to it is
-- taken so no confusion"): an active committee's colour may not be near the
-- super admin colour or another active committee's, and the super admins
-- may not move their colour near an active committee's. Near means a
-- distance under 70 between the two colours' red, green and blue. The rule
-- is in triggers, so it holds whichever way a colour is set.
-- =============================================================

set search_path = public, extensions;

/** The distance between two #RRGGBB colours, by their red, green and blue. */
create or replace function public._colour_dist(a text, b text)
returns double precision
language sql immutable parallel safe as $$
  select sqrt(power(('x' || substr(a, 2, 2))::bit(8)::int - ('x' || substr(b, 2, 2))::bit(8)::int, 2)
            + power(('x' || substr(a, 4, 2))::bit(8)::int - ('x' || substr(b, 4, 2))::bit(8)::int, 2)
            + power(('x' || substr(a, 6, 2))::bit(8)::int - ('x' || substr(b, 6, 2))::bit(8)::int, 2))
$$;

alter table public.barangay_profile
  add column super_colour text not null default '#00308F' check (super_colour ~ '^#[0-9A-Fa-f]{6}$');
comment on column public.barangay_profile.super_colour is '0150: the one colour every super admin''s sidebar wears (branding blue by default); no active committee may be near it.';

alter table public.committees add column colour text check (colour is null or colour ~ '^#[0-9A-Fa-f]{6}$');
-- the starting colours: the four committees switched on keep apart from each other and from branding blue
update public.committees set colour = case key
    when 'peace_order' then '#D32F2F' when 'environment' then '#00838F' when 'health_sanitation' then '#1E9E4A'
    when 'anti_drug' then '#5C6BC0' when 'education' then '#039BE5' when 'infrastructure' then '#6D4C41'
    when 'women_family' then '#D81B60' when 'youth_sports' then '#8E24AA' when 'agriculture' then '#7CB342'
    when 'appropriations' then '#78909C' else '#F4511E' end;
comment on column public.committees.colour is '0150: the committee''s colour, chosen by a super admin; its admins'' sidebar wears it.';

/** What a colour is too close to, for a committee (null: free). Inactive committees do not count. */
create or replace function public._colour_clash(p_colour text, p_committee text)
returns text
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select 'the super admin colour' from public.barangay_profile where id = 1 and public._colour_dist(super_colour, p_colour) < 70),
    (select format('the %s committee''s colour', short_en) from public.committees
      where active and colour is not null and key is distinct from p_committee and public._colour_dist(colour, p_colour) < 70
      order by sort, key limit 1))
$$;

/** The first colour of the palette that no active committee and no super admin is near. */
create or replace function public._committee_free_colour()
returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select c from unnest(array['#D32F2F', '#F4511E', '#F9A825', '#7CB342', '#1E9E4A', '#00838F', '#039BE5', '#5C6BC0',
                                               '#8E24AA', '#D81B60', '#6D4C41', '#78909C']) with ordinality as t(c, n)
                    where public._colour_clash(c, null) is null order by n limit 1), '#78909C')
$$;
alter table public.committees alter column colour set default public._committee_free_colour();
update public.committees set colour = public._committee_free_colour() where colour is null;
alter table public.committees alter column colour set not null;

create or replace function public._committee_colour_check()
returns trigger
language plpgsql set search_path = public as $$
declare v text;
begin
  if new.active and (tg_op = 'INSERT' or new.colour is distinct from old.colour or not old.active) then
    v := public._colour_clash(new.colour, new.key);
    if v is not null then
      raise exception 'That colour is too close to %. Pick another.', v using errcode = 'check_violation';
    end if;
  end if;
  return new;
end $$;
create trigger committees_colour before insert or update on public.committees
  for each row execute function public._committee_colour_check();

create or replace function public._super_colour_check()
returns trigger
language plpgsql set search_path = public as $$
declare v text;
begin
  if new.super_colour is distinct from old.super_colour then
    select short_en into v from public.committees
     where active and public._colour_dist(colour, new.super_colour) < 70 order by sort, key limit 1;
    if v is not null then
      raise exception 'That colour is too close to the % committee''s colour. Pick another, or change theirs first.', v using errcode = 'check_violation';
    end if;
  end if;
  return new;
end $$;
create trigger barangay_profile_super_colour before update on public.barangay_profile
  for each row execute function public._super_colour_check();

-- committee_save takes a colour (none: the first free one for a new committee, the same for an old one)
drop function public.committee_save(text, text, text, boolean, text);
create function public.committee_save(p_key text, p_name_en text, p_name_fil text, p_active boolean default true,
                                      p_short text default null, p_colour text default null)
returns text
language plpgsql security definer set search_path = public, extensions as $$
declare v_key text := nullif(trim(coalesce(p_key, '')), ''); v_en text := nullif(trim(coalesce(p_name_en, '')), ''); v_fil text := nullif(trim(coalesce(p_name_fil, '')), '');
  v_short text := left(coalesce(nullif(trim(coalesce(p_short, '')), ''), nullif(trim(coalesce(p_name_en, '')), '')), 40);
  v_colour text := nullif(trim(coalesce(p_colour, '')), '');
begin
  if not public.is_super_admin() then raise exception 'Only a super admin sets up committees' using errcode = 'insufficient_privilege'; end if;
  if v_en is null or char_length(v_en) < 3 then raise exception 'Name the committee' using errcode = 'check_violation'; end if;
  if v_colour is not null and v_colour !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'The colour is a # and six hex digits' using errcode = 'check_violation'; end if;
  v_colour := upper(v_colour);
  v_fil := coalesce(v_fil, v_en);
  if v_key is null then
    v_key := left(trim(both '_' from regexp_replace(lower(translate(v_en, 'ñÑáéíóúÁÉÍÓÚ', 'nNaeiouAEIOU')), '[^a-z0-9]+', '_', 'g')), 40);
    if v_key !~ '^[a-z]' then v_key := 'c_' || v_key; end if;
    if exists (select 1 from public.committees where key = v_key) then v_key := left(v_key, 34) || '_' || substr(md5(random()::text), 1, 5); end if;
    insert into public.committees (key, name_en, name_fil, short_en, active, sort, colour, updated_by)
    values (v_key, left(v_en, 120), left(v_fil, 120), v_short, coalesce(p_active, true), coalesce((select max(sort) + 1 from public.committees where active), 1),
            coalesce(v_colour, public._committee_free_colour()), auth.uid());
  else
    update public.committees set name_en = left(v_en, 120), name_fil = left(v_fil, 120), short_en = v_short, active = coalesce(p_active, active),
           colour = coalesce(v_colour, colour), updated_by = auth.uid(), updated_at = now()
     where key = v_key;
    if not found then raise exception 'No such committee' using errcode = 'check_violation'; end if;
  end if;
  perform public._smart_event('access', null, format('Committee saved: %s', left(v_en, 120)), jsonb_build_object('committee', v_key, 'active', coalesce(p_active, true), 'colour', v_colour));
  return v_key;
end $$;
revoke all on function public.committee_save(text, text, text, boolean, text, text) from public, anon;
grant execute on function public.committee_save(text, text, text, boolean, text, text) to authenticated;
