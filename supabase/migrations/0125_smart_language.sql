-- 0125: SMART reads Taglish (10 Oct 2026).
--
-- Smart without a model: the engine understands how residents actually
-- write, using Tagalog grammar and a word list the barangay can read and
-- edit, and it still shows exactly why. docs/SMART.md, "Reading the words".
--
--   word forms   nasusunog, binaha, sinaksak, nasugatan and duguan are read
--                as sunog, baha, saksak, sugat and dugo: Tagalog prefixes,
--                infixes (-um-, -in-), suffixes (-an, -in) and the repeated
--                first syllable are taken off, and the result only counts
--                if it is a word SMART knows.
--   spelling     a known texting spelling (snog, kuryinte) from the word
--                list, or a word one letter away from exactly one known word.
--   negation     "walang sunog", "no fire", "hindi baha" are not counted,
--                and the reasons say so.
--   meaning      fire and sunog, garbage and basura, drainage and kanal are
--                the same word to SMART, so duplicates are found by meaning
--                as well as by spelling.
--
-- The rules become plain word lists instead of regular expressions:
-- keyword_groups[].words and category_words.<kind>. A word with a space is
-- a phrase ("live wire", "walang helmet") and is matched as written.

set search_path = public, extensions;

create extension if not exists fuzzystrmatch with schema extensions;

-- ---------- the word list ---------------------------------------------------

create table public.smart_lexicon (
  variant text primary key check (variant = lower(variant) and variant !~ '\s'),
  root    text not null check (root = lower(root)),
  kind    text not null check (kind in ('spelling', 'synonym', 'form')),
  note    text
);
alter table public.smart_lexicon enable row level security;
create policy smart_lexicon_admin_read on public.smart_lexicon for select using ((select public.is_admin()));
create policy smart_lexicon_admin_write on public.smart_lexicon for all
  using ((select public.is_admin())) with check ((select public.is_admin()));
comment on table public.smart_lexicon is
  '0125: words SMART reads as another word: texting spellings (snog: sunog), English and Tagalog synonyms (garbage: basura), and forms the grammar rules do not reach (nangangagat: kagat). Admins edit it.';

insert into public.smart_lexicon (variant, root, kind) values
  -- texting spellings
  ('snog', 'sunog', 'spelling'), ('sunug', 'sunog', 'spelling'), ('sonog', 'sunog', 'spelling'),
  ('apuy', 'apoy', 'spelling'), ('kuryinte', 'kuryente', 'spelling'), ('koryente', 'kuryente', 'spelling'),
  ('aksidinte', 'aksidente', 'spelling'), ('bta', 'bata', 'spelling'), ('sgat', 'sugat', 'spelling'),
  ('bsura', 'basura', 'spelling'), ('knal', 'kanal', 'spelling'), ('trapic', 'trapik', 'spelling'),
  -- same meaning
  ('fire', 'sunog', 'synonym'), ('smoke', 'usok', 'synonym'), ('flood', 'baha', 'synonym'),
  ('flooding', 'baha', 'synonym'), ('flooded', 'baha', 'synonym'), ('garbage', 'basura', 'synonym'),
  ('trash', 'basura', 'synonym'), ('drainage', 'kanal', 'synonym'), ('imburnal', 'kanal', 'synonym'),
  ('estero', 'kanal', 'synonym'), ('canal', 'kanal', 'synonym'), ('dog', 'aso', 'synonym'),
  ('dogs', 'aso', 'synonym'), ('askal', 'aso', 'synonym'), ('cat', 'pusa', 'synonym'), ('cats', 'pusa', 'synonym'),
  ('blood', 'dugo', 'synonym'), ('bleeding', 'dugo', 'synonym'), ('wire', 'kawad', 'synonym'),
  ('gun', 'baril', 'synonym'), ('knife', 'kutsilyo', 'synonym'), ('child', 'bata', 'synonym'),
  ('children', 'bata', 'synonym'), ('kids', 'bata', 'synonym'), ('elderly', 'matanda', 'synonym'),
  ('noise', 'ingay', 'synonym'), ('drunk', 'lasing', 'synonym'), ('accident', 'aksidente', 'synonym'),
  ('fight', 'gulo', 'synonym'), ('fighting', 'gulo', 'synonym'), ('injured', 'sugat', 'synonym'),
  ('injury', 'sugat', 'synonym'), ('wound', 'sugat', 'synonym'), ('collapsed', 'guho', 'synonym'),
  ('collapse', 'guho', 'synonym'), ('pothole', 'lubak', 'synonym'), ('streetlight', 'poste', 'synonym'),
  -- forms the grammar rules do not reach
  ('nangangagat', 'kagat', 'form'), ('nanganganib', 'panganib', 'form'), ('nagaaway', 'gulo', 'form'),
  ('nagaway', 'gulo', 'form'), ('magaaway', 'gulo', 'form'), ('nagaawayan', 'gulo', 'form'),
  ('nagkagulo', 'gulo', 'form');

-- ---------- the rules as word lists -------------------------------------------

alter table public.smart_rules alter column keyword_groups set default '[
  {"label": "fire",       "points": 30, "words": ["sunog", "apoy", "usok", "burning"]},
  {"label": "weapon",     "points": 30, "words": ["baril", "kutsilyo", "patalim", "saksak", "holdap", "holdup", "nakaw", "stab", "stabbed", "shooting", "robbery"]},
  {"label": "injury",     "points": 30, "words": ["sugat", "dugo", "unconscious", "walang malay"]},
  {"label": "gas leak",   "points": 30, "words": ["lpg", "gas leak", "tagas ng gas", "amoy gas"]},
  {"label": "live wire",  "points": 25, "words": ["kuryente", "kawad", "spark", "sparking", "transformer", "live wire"]},
  {"label": "collapse",   "points": 25, "words": ["guho", "bagsak", "tumba", "buwal", "fallen tree"]},
  {"label": "accident",   "points": 25, "words": ["aksidente", "bangga", "collision", "crash"]},
  {"label": "fight",      "points": 20, "words": ["gulo", "rambol", "riot", "suntok", "bugbog"]},
  {"label": "flooding",   "points": 15, "words": ["baha", "lubog"]},
  {"label": "vulnerable", "points": 10, "words": ["bata", "matanda", "lola", "lolo", "senior", "pwd", "buntis", "pregnant"]}
]';

alter table public.smart_rules alter column category_words set default '{
  "street_obstruction":           ["harang", "bangketa", "tinda", "vendor", "vendors", "debris", "sidewalk", "obstruction", "parada", "construction materials"],
  "public_safety_infrastructure": ["sunog", "poste", "lubak", "manhole", "kuryente", "kawad", "tulay", "bridge", "guho", "street light", "live wire"],
  "environmental_waste_hazard":   ["basura", "tambak", "kanal", "barado", "usok", "baho", "lamok", "stagnant"],
  "animal_welfare":               ["aso", "pusa", "kagat", "stray", "hayop", "animal", "animals"],
  "traffic_violation":            ["counterflow", "overspeeding", "trapik", "traffic", "tricycle", "walang helmet", "no helmet", "double parking", "beating the red"],
  "peace_order_nuisance":         ["ingay", "videoke", "karaoke", "inuman", "lasing", "gulo", "rambol", "tambay", "sugal", "gambling", "harassment"],
  "barangay_service":             ["clearance", "certificate", "sertipiko", "indigency", "cedula", "permit", "barangay id"]
}';

update public.smart_rules set keyword_groups = default, category_words = default;

-- ---------- reading -----------------------------------------------------------

/** Words of a text, lower case, hyphens out ("nag-aaway" becomes
    "nagaaway"); a comma, full stop or other clause mark becomes "|", which
    ends a negation and a phrase. */
create or replace function public._smart_tokens(p_text text)
returns text[]
language sql
immutable
set search_path = public, extensions
as $$
  select coalesce(array_remove(regexp_split_to_array(
           trim(regexp_replace(regexp_replace(replace(lower(coalesce(p_text, '')), '-', ''),
                                              '[,.;:!?]+', ' | ', 'g'),
                               '[^a-z0-9ñ|]+', ' ', 'g')), ' '), ''), '{}')
$$;

/** Every single word SMART knows: the rules' words and the word list's roots. */
create or replace function public._smart_vocab()
returns text[]
language sql
stable
security definer
set search_path = public, extensions
as $$
  select array(select distinct coalesce(l.root, w.word)
    from (select jsonb_array_elements_text(g -> 'words') as word
            from public.smart_rules k, jsonb_array_elements(k.keyword_groups) g where k.id = 1
          union
          select jsonb_array_elements_text(c.value)
            from public.smart_rules k, jsonb_each(k.category_words) c where k.id = 1
          union
          select root from public.smart_lexicon) w
    left join public.smart_lexicon l on l.variant = w.word
   where w.word !~ '\s')
$$;

/** One word to the word SMART knows, and how: exact, spelling, synonym or
    form (from the word list), grammar (affixes taken off), or guess (one
    letter from exactly one known word of five letters or more). Null if
    it is not a word SMART knows. */
create or replace function public._smart_stem(p_tok text, p_vocab text[])
returns table (root text, how text)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  c text[];
  nxt text[];
  w text;
  p text;
  syl text;
  hit text;
  n integer;
begin
  if p_tok = any (p_vocab) then return query select p_tok, 'exact'; return; end if;
  select l.root, l.kind into hit, w from public.smart_lexicon l where l.variant = p_tok;
  if hit is not null then return query select hit, w; return; end if;
  if length(p_tok) < 4 then return; end if;

  c := array[p_tok];
  -- the linker -ng (asong gala, batang naglalaro)
  if p_tok ~ '[aeiou]ng$' then c := c || left(p_tok, -2); end if;
  -- prefixes
  foreach p in array array['ipinag', 'pinag', 'nakaka', 'makaka', 'nagka', 'naka', 'maka', 'nang', 'mang',
                           'nag', 'mag', 'pag', 'ka', 'na', 'ma', 'pa', 'ni', 'i'] loop
    if p_tok like p || '%' and length(p_tok) - length(p) >= 3 then c := c || substr(p_tok, length(p) + 1); end if;
  end loop;
  -- repeated first syllable (susunog -> sunog)
  nxt := c;
  foreach w in array c loop
    syl := substring(w from '^[^aeiou]*[aeiou]');
    if syl is not null and length(w) >= length(syl) + 3 and substr(w, length(syl) + 1, length(syl)) = syl then
      nxt := nxt || substr(w, length(syl) + 1);
    end if;
  end loop;
  c := nxt;
  -- infixes -um- and -in- (bumaha, binaha -> baha)
  nxt := c;
  foreach w in array c loop
    if w ~ '^[^aeiou]?(um|in)[a-z]{2,}$' then
      nxt := nxt || regexp_replace(w, '^([^aeiou]?)(um|in)', '\1');
    end if;
  end loop;
  c := nxt;
  -- suffixes -an, -han, -in, -hin, and the o that turns to u before them (duguan -> dugo)
  nxt := c;
  foreach w in array c loop
    if w ~ '(han|hin|an|in)$' and length(w) >= 5 then
      p := regexp_replace(w, '(han|hin|an|in)$', '');
      nxt := nxt || p;
      if p ~ 'u$' then nxt := nxt || regexp_replace(p, 'u$', 'o'); end if;
    end if;
  end loop;
  c := nxt;

  select x into hit from unnest(c) x where x = any (p_vocab) order by length(x) desc limit 1;
  if hit is not null then return query select hit, 'grammar'; return; end if;
  select l.root into hit from unnest(c) x join public.smart_lexicon l on l.variant = x limit 1;
  if hit is not null then return query select hit, 'grammar'; return; end if;

  -- one letter off exactly one known word
  select min(v), count(*) into hit, n
    from unnest(p_vocab) v where length(v) >= 5 and levenshtein(p_tok, v) = 1;
  if n = 1 then return query select hit, 'guess'; end if;
end $$;

revoke all on function public._smart_stem(text, text[]) from public, anon, authenticated;

/** A text read word by word: each word, the word SMART knows it as, how,
    and whether a negation just before it ("walang", "hindi", "no", "not")
    cancels it. A negation reaches the next two words, not counting little
    words like na, ng, po, ang, mga, the, any, and stops at a comma or full
    stop and at pero / but. */
create or replace function public._smart_read(p_text text)
returns table (pos integer, word text, root text, how text, negated boolean)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_toks  text[] := public._smart_tokens(p_text);
  v_vocab text[] := public._smart_vocab();
  v_left  integer := 0;
  i integer;
  s record;
begin
  for i in 1 .. coalesce(array_length(v_toks, 1), 0) loop
    if v_toks[i] in ('|', 'pero', 'but', 'kaso', 'however') then
      v_left := 0;
      continue;
    end if;
    if v_toks[i] in ('wala', 'walang', 'hindi', 'di', 'huwag', 'wag', 'no', 'not', 'never', 'without', 'none') then
      v_left := 2;
      continue;
    end if;
    if v_toks[i] in ('na', 'nang', 'ng', 'naman', 'po', 'pa', 'ang', 'mga', 'yung', 'the', 'a', 'an', 'any') then
      continue;
    end if;
    select * into s from public._smart_stem(v_toks[i], v_vocab);
    pos := i; word := v_toks[i]; root := s.root; how := s.how; negated := v_left > 0;
    return next;
    v_left := greatest(v_left - 1, 0);
  end loop;
end $$;

revoke all on function public._smart_read(text) from public, anon, authenticated;

/** Admins: how SMART reads a text, word by word (Settings -> SMART -> Try it). */
create or replace function public.smart_read(p_text text)
returns table (pos integer, word text, root text, how text, negated boolean)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can try the rules.' using errcode = 'insufficient_privilege';
  end if;
  return query select * from public._smart_read(p_text);
end $$;

revoke all on function public.smart_read(text) from public, anon;
grant execute on function public.smart_read(text) to authenticated;

/** Whether a rule word (single or phrase) appears in a reading. For a
    phrase, the words as written, in order; for a single word, its root
    among the words not cancelled by a negation. */
create or replace function public._smart_words_hit(p_words jsonb, p_text text, p_read jsonb)
returns jsonb
language sql
stable
security definer
set search_path = public, extensions
as $$
  with words as (
    select w, coalesce((select l.root from public.smart_lexicon l where l.variant = w), w) as root
      from jsonb_array_elements_text(p_words) w
  ), flat as (select ' ' || array_to_string(public._smart_tokens(p_text), ' ') || ' ' as t)
  select coalesce(
    (select jsonb_build_object('matched', w.w, 'how', 'phrase')
       from words w, flat where w.w ~ '\s' and flat.t like '% ' || array_to_string(public._smart_tokens(w.w), ' ') || ' %' limit 1),
    (select jsonb_build_object('matched', case when r ->> 'how' = 'exact' then r ->> 'word'
                                               else (r ->> 'word') || ' → ' || (r ->> 'root') end,
                               'how', r ->> 'how')
       from words w, jsonb_array_elements(p_read) r
      where w.w !~ '\s' and r ->> 'root' = w.root and not (r ->> 'negated')::boolean
      order by (r ->> 'pos')::integer limit 1),
    (select jsonb_build_object('matched', r ->> 'word', 'how', 'negated', 'negated', true)
       from words w, jsonb_array_elements(p_read) r
      where w.w !~ '\s' and r ->> 'root' = w.root and (r ->> 'negated')::boolean
      order by (r ->> 'pos')::integer limit 1))
$$;

revoke all on function public._smart_words_hit(jsonb, text, jsonb) from public, anon, authenticated;

/** The known words of a text, in a fixed order: what "the same meaning"
    compares for duplicates ("garbage sa drainage" and "basura sa kanal"
    both read "basura kanal"). */
create or replace function public._smart_concepts(p_text text)
returns text
language sql
stable
security definer
set search_path = public, extensions
as $$
  select coalesce(string_agg(distinct root, ' ' order by root), '')
    from public._smart_read(p_text) where root is not null and not negated
$$;

revoke all on function public._smart_concepts(text) from public, anon, authenticated;

-- ---------- the score, reading Taglish --------------------------------------------

create or replace function public._smart_score(
  p_category    public.complaint_category,
  p_subject     text,
  p_description text,
  p_geom        geography,
  p_at          timestamptz,
  p_resident    uuid,
  p_exclude     uuid default null)
returns table (score smallint, level text, reasons jsonb)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  k       public.smart_rules%rowtype;
  v_text  text := coalesce(p_subject, '') || ' ' || coalesce(p_description, '');
  v_read  jsonb;
  v_hit   jsonb;
  v_pts   integer;
  v_kw    integer := 0;
  v_score integer := 0;
  v_why   jsonb := '[]';
  v_lvl   smallint;
  v_haz   text;
  v_n     integer;
  v_hour  integer;
  g       jsonb;
begin
  select * into k from public.smart_rules where id = 1;
  select coalesce(jsonb_agg(to_jsonb(r) order by r.pos), '[]') into v_read from public._smart_read(v_text) r;

  -- the kind of complaint
  v_pts := coalesce((k.category_points ->> p_category::text)::integer, 0);
  v_score := v_pts;
  v_why := v_why || jsonb_build_object('factor', 'category', 'detail', p_category::text, 'points', v_pts);

  -- words, each group once, read as Taglish
  for g in select * from jsonb_array_elements(k.keyword_groups) loop
    v_hit := public._smart_words_hit(g -> 'words', v_text, v_read);
    if v_hit is null then continue; end if;
    if coalesce((v_hit ->> 'negated')::boolean, false) then
      v_why := v_why || jsonb_build_object('factor', 'not counted', 'detail', g ->> 'label',
                                           'points', 0, 'matched', v_hit ->> 'matched', 'how', 'negated');
      continue;
    end if;
    v_pts := least((g ->> 'points')::integer, k.keyword_cap - v_kw);
    if v_pts > 0 then
      v_kw := v_kw + v_pts;
      v_why := v_why || jsonb_build_object('factor', 'words', 'detail', g ->> 'label', 'points', v_pts,
                                           'matched', v_hit ->> 'matched', 'how', v_hit ->> 'how');
    end if;
  end loop;
  v_score := v_score + v_kw;

  if p_geom is not null then
    -- hazard zone
    select z.level, z.hazard into v_lvl, v_haz
      from public.hazard_zones z
     where st_intersects(z.geom, p_geom::geometry)
     order by z.level desc, z.hazard
     limit 1;
    if v_lvl is not null then
      v_pts := coalesce((k.hazard_points ->> v_lvl::text)::integer, 0);
      v_score := v_score + v_pts;
      v_why := v_why || jsonb_build_object('factor', 'hazard zone',
        'detail', format('NOAH %s zone, %s', v_haz, (array['low', 'medium', 'high'])[v_lvl]), 'points', v_pts);
    end if;

    -- other residents, same kind, close in place and time
    select count(distinct o.resident_id) into v_n
      from public.reports o
     where o.id is distinct from p_exclude
       and o.category = p_category
       and o.resident_id is distinct from p_resident
       and o.deleted_at is null
       and o.status not in ('rejected', 'cancelled')
       and o.created_at between p_at - make_interval(hours => k.corroboration_hours)
                            and p_at + make_interval(hours => k.corroboration_hours)
       and st_dwithin(o.geom, p_geom, k.corroboration_metres);
    if v_n > 0 then
      v_pts := least(v_n * k.corroboration_points, k.corroboration_cap);
      v_score := v_score + v_pts;
      v_why := v_why || jsonb_build_object('factor', 'nearby reports',
        'detail', format('%s other resident%s reported this within %s m', v_n, case when v_n = 1 then '' else 's' end,
                         k.corroboration_metres),
        'points', v_pts);
    end if;
  end if;

  -- night, for safety kinds
  v_hour := extract(hour from p_at at time zone 'Asia/Manila');
  if (v_hour >= 22 or v_hour < 5)
     and p_category in ('peace_order_nuisance', 'public_safety_infrastructure', 'traffic_violation') then
    v_score := v_score + k.night_points;
    v_why := v_why || jsonb_build_object('factor', 'night', 'detail', format('filed at %s:00', v_hour),
                                         'points', k.night_points);
  end if;

  v_score := greatest(0, least(100, v_score));
  return query select v_score::smallint,
         case when v_score >= k.urgent_from then 'urgent'
              when v_score >= k.high_from   then 'high'
              when v_score >= k.normal_from then 'normal'
              else 'low' end,
         v_why;
end $$;

-- ---------- the category hint, reading Taglish --------------------------------------

create or replace function public._smart_category_hint(p_category public.complaint_category,
                                                       p_subject text, p_description text)
returns jsonb
language sql
stable
security definer
set search_path = public, extensions
as $$
  with txt as (select coalesce(p_subject, '') || ' ' || coalesce(p_description, '') as t),
       rd as (select r.* from txt, public._smart_read(txt.t) r where r.root is not null and not r.negated),
       flat as (select ' ' || array_to_string(public._smart_tokens(txt.t), ' ') || ' ' as t from txt),
       words as (
         select c.key as cat, w,
                coalesce((select l.root from public.smart_lexicon l where l.variant = w), w) as root
           from public.smart_rules k, jsonb_each(k.category_words) c, jsonb_array_elements_text(c.value) w
          where k.id = 1
       ),
       found as (
         select w.cat, w.w as matched from words w, flat
          where w.w ~ '\s' and flat.t like '% ' || array_to_string(public._smart_tokens(w.w), ' ') || ' %'
         union
         select w.cat, rd.word from words w join rd on rd.root = w.root
          where w.w !~ '\s'
       ),
       per as (select cat, count(*) as n, jsonb_agg(matched order by matched) as words from found group by cat)
  select case when exists (select 1 from per where cat = p_category::text) then null
              else (select jsonb_build_object('category', cat, 'words', words)
                      from per order by n desc, cat limit 1) end
$$;

-- ---------- duplicates by meaning as well as spelling ----------------------------------

create or replace function public.smart_duplicates_of(p_report uuid)
returns table (report_id uuid, tracking_id text, metres integer, hours_apart numeric,
               similarity real, status public.report_status)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with k as (select * from public.smart_rules where id = 1),
       r as (select rp.*, public._smart_concepts(rp.subject || ' ' || rp.description) as concepts
               from public.reports rp where rp.id = p_report),
       c as (
         select o.*, public._smart_concepts(o.subject || ' ' || o.description) as concepts
           from r, k, public.reports o
          where o.id <> r.id
            and o.category = r.category
            and o.deleted_at is null
            and o.status not in ('rejected', 'cancelled', 'closed', 'archived')
            and o.created_at <= r.created_at
            and o.created_at > r.created_at - make_interval(hours => k.duplicate_hours)
            and st_dwithin(o.geom, r.geom, k.duplicate_metres)
       ), s as (
         select c.*, greatest(
                  extensions.similarity(lower(c.subject || ' ' || c.description), lower(r.subject || ' ' || r.description)),
                  case when c.concepts <> '' and r.concepts <> '' then extensions.similarity(c.concepts, r.concepts) else 0 end
                ) as sim,
                st_distance(c.geom, r.geom) as d,
                r.created_at as r_at
           from c, r
       )
  select s.id, s.tracking_id, round(s.d)::integer,
         round(extract(epoch from (s.r_at - s.created_at)) / 3600.0, 1), s.sim, s.status
    from s, k
   where s.sim >= k.duplicate_similarity or s.d <= 25
   order by s.sim desc, s.d
   limit 5
$$;
