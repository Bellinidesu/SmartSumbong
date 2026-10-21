# Reader benchmark

How well does SMART's reader (migrations 0125 and 0133) recover a word's root,
compared with plain fuzzy matching? `cases.tsv` holds 71 words: 64 that must
read as a known root (Tagalog affixes, texting spellings, English words and
endings, stretched and doubled words) and 7 **traps** that must stay unknown
because they are real words that only look like a known one (batas, bigas,
bahay, bahagi, basa, sunod).

    python run.py -v

Needs the Supabase CLI linked to the project. It calls two read-only
functions (`_smart_vocab`, `_smart_read`) on single words; no report or
resident data is read. `pip install rapidfuzz` for the baseline.

## Result (21 Oct 2026, after 0133)

| Reader | Words recovered | Traps kept unknown |
|---|---|---|
| SMART (rules) | 64 / 64 | 6 / 7 |
| RapidFuzz alone, cut-off 80 | 34 / 64 | 2 / 7 |
| RapidFuzz alone, cut-off 70 | 46 / 64 | 2 / 7 |

- Fuzzy matching alone cannot do the grammar (nasusunog, bumabaha), the
  English words (fire, garbage, accident), or the doubled and stretched
  words, and it treats batas, bahay and bahagi as the words they resemble.
  A lower cut-off recovers more words and falls for more traps.
- SMART's one trap miss is **sunod** (to follow), read as **sunog**: the
  "one letter off exactly one known word" rule from 0125. It is a real
  weakness, left as it is for now: tightening it also loses true slips such
  as kurynte.
- This is a small, hand-made set. It shows the rules beat fuzzy matching on
  these forms; it is not an accuracy figure for real complaints (the barangay
  has too few real reports to measure on yet). Add words to `cases.tsv` when a
  miss turns up.
