-- 0133: SMART reads more word forms (21 Oct 2026).
--
-- Rules still decide; this only teaches the reader (0125's _smart_stem)
-- forms residents write every day that it missed. The ideas follow the
-- Tagalog stemmers and lemmatisers in open source (calamanCy, MIT, and
-- the affix-stripping stemmers it builds on); no model is added and no
-- library is installed. A form still counts only if it ends at a word
-- SMART knows, and the reasons still show it ("bumabaha → baha").
--
--   the present tense   bumabaha, sinusunog, kinakagat: the infix comes
--                       off first and leaves a repeated syllable
--                       (babaha), so the repeated syllable is now looked
--                       for again after the infix. 0125 looked only
--                       before it, and missed them.
--   doubled words       sunog-sunog, away-away (sunogsunog once the
--                       hyphen is gone) are read as the word once.
--   stretched letters   sunoooog, bahaaaa, tulonggg: a letter written
--                       three or more times is read once.
--   English endings     fires, wires, burning, flooded, stabbed: -s,
--                       -es, -ies, -ing, -ed come off (and a doubled
--                       last letter: stabb- → stab) when what is left
--                       is a word SMART knows or has in its word list.

set search_path = public, extensions;

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
  v_tok text := p_tok;
  half integer;
begin
  if p_tok = any (p_vocab) then return query select p_tok, 'exact'; return; end if;
  select l.root, l.kind into hit, w from public.smart_lexicon l where l.variant = p_tok;
  if hit is not null then return query select hit, w; return; end if;

  -- a letter written three or more times is read once (sunoooog -> sunog)
  v_tok := public._smart_unstretch(p_tok);
  if v_tok <> p_tok then
    if v_tok = any (p_vocab) then return query select v_tok, 'spelling'; return; end if;
    select l.root into hit from public.smart_lexicon l where l.variant = v_tok;
    if hit is not null then return query select hit, 'spelling'; return; end if;
  end if;
  if length(v_tok) < 4 then return; end if;

  c := array[v_tok];
  -- a doubled word (sunogsunog -> sunog)
  half := length(v_tok) / 2;
  if length(v_tok) % 2 = 0 and half >= 3 and left(v_tok, half) = right(v_tok, half) then c := c || left(v_tok, half); end if;
  -- the linker -ng (asong gala, batang naglalaro)
  if v_tok ~ '[aeiou]ng$' then c := c || left(v_tok, -2); end if;
  -- prefixes
  foreach p in array array['ipinag', 'pinag', 'nakaka', 'makaka', 'nagka', 'naka', 'maka', 'nang', 'mang',
                           'nag', 'mag', 'pag', 'ka', 'na', 'ma', 'pa', 'ni', 'i'] loop
    if v_tok like p || '%' and length(v_tok) - length(p) >= 3 then c := c || substr(v_tok, length(p) + 1); end if;
  end loop;
  -- repeated first syllable (susunog -> sunog)
  c := c || public._smart_unrepeat(c);
  -- infixes -um- and -in- (bumaha, binaha -> baha)
  nxt := c;
  foreach w in array c loop
    if w ~ '^[^aeiou]?(um|in)[a-z]{2,}$' then
      nxt := nxt || regexp_replace(w, '^([^aeiou]?)(um|in)', '\1');
    end if;
  end loop;
  -- and the syllable the infix leaves repeated (bumabaha -> babaha -> baha)
  c := nxt || public._smart_unrepeat(nxt);
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
  -- English endings (fires, burning, flooded, stabbed); only a known word or word-list entry counts
  if v_tok ~ '[a-z]{3,}(ies|es|s|ing|ed)$' then
    foreach p in array array[regexp_replace(v_tok, 'ies$', 'y'), regexp_replace(v_tok, 'es$', ''),
                             regexp_replace(v_tok, 's$', ''), regexp_replace(v_tok, 'ing$', ''),
                             regexp_replace(v_tok, 'ing$', 'e'), regexp_replace(v_tok, 'ed$', ''),
                             regexp_replace(v_tok, 'd$', '')] loop
      if p <> v_tok and length(p) >= 3 then
        c := c || p;
        if p ~ '([b-df-hj-np-tv-z])\1$' then c := c || left(p, -1); end if;   -- stabb -> stab
      end if;
    end loop;
  end if;

  select x into hit from unnest(c) x where x = any (p_vocab) order by length(x) desc limit 1;
  if hit is not null then return query select hit, 'grammar'; return; end if;
  select l.root into hit from unnest(c) x join public.smart_lexicon l on l.variant = x order by length(x) desc limit 1;
  if hit is not null then return query select hit, 'grammar'; return; end if;

  -- one letter off exactly one known word
  select min(v), count(*) into hit, n
    from unnest(p_vocab) v where length(v) >= 5 and levenshtein(v_tok, v) = 1;
  if n = 1 then return query select hit, 'guess'; end if;
end $$;

/** A letter written three or more times in a row, written once (sunoooog -> sunog); a doubled one stays (kill). */
create or replace function public._smart_unstretch(p_tok text)
returns text
language plpgsql
immutable
set search_path = public, extensions
as $$
declare
  v_out text := '';
  ch text;
  i integer := 1;
  n integer := length(coalesce(p_tok, ''));
begin
  while i <= n loop
    ch := substr(p_tok, i, 1);
    if i + 2 <= n and substr(p_tok, i + 1, 1) = ch and substr(p_tok, i + 2, 1) = ch then
      while i <= n and substr(p_tok, i, 1) = ch loop i := i + 1; end loop;
    else
      i := i + 1;
    end if;
    v_out := v_out || ch;
  end loop;
  return v_out;
end $$;

/** The repeated first syllable taken off each word that has one (susunog -> sunog, babaha -> baha). */
create or replace function public._smart_unrepeat(p_words text[])
returns text[]
language plpgsql
immutable
set search_path = public, extensions
as $$
declare
  v_out text[] := '{}';
  w text;
  syl text;
begin
  foreach w in array p_words loop
    syl := substring(w from '^[^aeiou]*[aeiou]');
    if syl is not null and length(w) >= length(syl) + 3 and substr(w, length(syl) + 1, length(syl)) = syl then
      v_out := v_out || substr(w, length(syl) + 1);
    end if;
  end loop;
  return v_out;
end $$;

revoke all on function public._smart_stem(text, text[]) from public, anon, authenticated;
revoke all on function public._smart_unrepeat(text[]) from public, anon, authenticated;
revoke all on function public._smart_unstretch(text) from public, anon, authenticated;
