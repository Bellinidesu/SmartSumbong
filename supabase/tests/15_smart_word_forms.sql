-- 15_smart_word_forms.sql: the word forms SMART learned to read in 0133. Rolled back.
do $sweep$
declare
  v_log text := 'setup ok';
  s record;
  r text;   -- the word SMART reads a word of the text as (null when it does not know it)
begin
  -- the present tense: the infix, then the repeated syllable it leaves
  begin
    select * into s from public._smart_score('other', '', 'Bumabaha na naman sa kanto namin.', null, now(), null);
    if not s.reasons @> '[{"factor": "words", "detail": "flooding", "matched": "bumabaha → baha", "how": "grammar"}]' then raise exception '%', s.reasons; end if;
    select * into s from public._smart_score('other', '', 'Sinusunog nila yung basura sa likod.', null, now(), null);
    if not s.reasons @> '[{"factor": "words", "detail": "fire", "matched": "sinusunog → sunog"}]' then raise exception '%', s.reasons; end if;
    select root into r from public._smart_read('Kinakagat ng aso ang mga bata') where word = 'kinakagat';
    if r is distinct from 'kagat' then raise exception 'kinakagat read as %', r; end if;
    v_log := v_log || E'\n' || 'ok  bumabaha, sinusunog and kinakagat are read as baha, sunog and kagat';
  exception when others then v_log := v_log || E'\n' || 'FAIL present tense: ' || sqlerrm; end;

  -- doubled words and stretched letters
  begin
    select root into r from public._smart_read('sunog-sunog na yung kabila') where word = 'sunogsunog';
    if r is distinct from 'sunog' then raise exception 'sunog-sunog read as %', r; end if;
    select * into s from public._smart_score('other', '', 'SUNOOOOG!! tulong po', null, now(), null);
    if not s.reasons @> '[{"factor": "words", "detail": "fire", "matched": "sunoooog → sunog", "how": "spelling"}]' then raise exception '%', s.reasons; end if;
    select root into r from public._smart_read('bahaaaa dito') where word = 'bahaaaa';
    if r is distinct from 'baha' then raise exception 'bahaaaa read as %', r; end if;
    v_log := v_log || E'\n' || 'ok  sunog-sunog, sunoooog and bahaaaa are read as sunog and baha';
  exception when others then v_log := v_log || E'\n' || 'FAIL doubled and stretched: ' || sqlerrm; end;

  -- English endings
  begin
    select root into r from public._smart_read('there are wires down') where word = 'wires';
    if r is distinct from 'kawad' then raise exception 'wires read as %', r; end if;
    select root into r from public._smart_read('a stabbing near the store') where word = 'stabbing';
    if r is distinct from 'stab' then raise exception 'stabbing read as %', r; end if;
    select root into r from public._smart_read('two cars crashed') where word = 'crashed';
    if r is distinct from 'crash' then raise exception 'crashed read as %', r; end if;
    select * into s from public._smart_score('other', '', 'Fires near the market', null, now(), null);
    if not s.reasons @> '[{"factor": "words", "detail": "fire", "matched": "fires → sunog"}]' then raise exception '%', s.reasons; end if;
    v_log := v_log || E'\n' || 'ok  wires, stabbing, crashed and fires are read as kawad, stab, crash and sunog';
  exception when others then v_log := v_log || E'\n' || 'FAIL English endings: ' || sqlerrm; end;

  -- no over-reading: a form only counts when it ends at a known word
  begin
    select root into r from public._smart_read('bumili ng bigas sa pulis') where word = 'bigas';
    if r is not null then raise exception 'bigas read as %', r; end if;
    select root into r from public._smart_read('bumili ng bigas sa pulis') where word = 'pulis';
    if r is not null then raise exception 'pulis read as %', r; end if;
    select root into r from public._smart_read('walang sunogsunog dito') where word = 'sunogsunog';
    if r is distinct from 'sunog' then raise exception 'negated doubled word read as %', r; end if;
    if not exists (select 1 from public._smart_read('walang bumabaha dito') where word = 'bumabaha' and negated) then
      raise exception 'a negated new form is counted';
    end if;
    v_log := v_log || E'\n' || 'ok  bigas and pulis stay unknown; a negation still cancels the new forms';
  exception when others then v_log := v_log || E'\n' || 'FAIL over-reading: ' || sqlerrm; end;

  -- 0125's forms are still read the same way, one word at a time (a sentence of four urgent words hits the word cap)
  begin
    select root into r from public._smart_read('nasusunog') where word = 'nasusunog';
    if r is distinct from 'sunog' then raise exception 'nasusunog read as %', r; end if;
    select root into r from public._smart_read('sinaksak') where word = 'sinaksak';
    if r is distinct from 'saksak' then raise exception 'sinaksak read as %', r; end if;
    select root into r from public._smart_read('duguan') where word = 'duguan';
    if r is distinct from 'dugo' then raise exception 'duguan read as %', r; end if;
    select root into r from public._smart_read('batas') where word = 'batas';
    if r is not distinct from 'bata' then raise exception 'batas (law) read as bata (child)'; end if;
    v_log := v_log || E'\n' || 'ok  nasusunog, sinaksak and duguan read as before, and batas is not read as bata';
  exception when others then v_log := v_log || E'\n' || 'FAIL old forms: ' || sqlerrm; end;

  -- the helper is not for the app
  begin
    execute 'set local role authenticated';
    perform public._smart_unrepeat(array['susunog']);
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD a resident called _smart_unrepeat (should have been refused)';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'ok  a resident cannot call _smart_unrepeat'; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
