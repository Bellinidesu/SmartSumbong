# SMART lab

Open-source tools that check the SMART engine **from outside**. The engine's
rules run in the database and decide; nothing here runs in the portal or the
app, or changes a report. The lab measures the rules against other methods so
a weak rule shows up before anyone changes it.

    py -3.12 -m pip install -r requirements.txt     # once (Python 3.12: some of these have no 3.15 wheels yet)
    py -3.12 lab.py all                              # or one: words, language, hotspots, duplicates, patterns, explain

It reads the live project **read-only** through the Supabase CLI and prints
tracking IDs and counts, never a resident's name or words. calamanCy downloads
its Tagalog model (about 200 MB) the first time.

| Check | Open-source tool (licence) | Measured against |
|---|---|---|
| `words` | calamanCy (MIT), jellyfish Metaphone (MIT) | the reader's 71-word benchmark (`../reader_benchmark`) |
| `language` | lingua (Apache-2.0), TagLID (MIT) | 20 labelled sentences: Tagalog, English, Taglish |
| `hotspots` | H3 (Apache-2.0) | the DBSCAN clusters of `report_hotspots()` (0042) |
| `duplicates` | datasketch MinHash (MIT) | `smart_duplicates_of()` (pg_trgm and meaning, 0125) |
| `patterns` | ruptures (BSD-2), PyOD (BSD-2), Prophet (MIT) | the daily count of reports |
| `explain` | InterpretML (MIT) | the triage scores in `report_triage` |

## What it found (22 Oct 2026, 45 reports over 8 weeks)

- **Words.** SMART's rules recover 64 of 64; calamanCy's lemmas recover 47
  (they miss English words and some present-tense forms) and add nothing SMART
  misses; a phonetic key alone recovers 32. Keep the rules; calamanCy is not
  needed as a fallback today.
- **Language.** TagLID tells Taglish apart best: 18 of 20 right and 5 of 6
  Taglish complaints found, against lingua's 17 and 3. If SMART ever needs to
  know a complaint's language (to reply in it, or to pick a word list), TagLID
  is the one to use, offline or as a suggestion.
- **Hotspots.** All 5 DBSCAN clusters sit in H3 cells holding 2 or more
  reports, and the 5 busiest cells each hold a cluster: the two methods agree.
  H3 cells are an even grid, simpler to draw and compare week to week; the
  map keeps them off for now (Rose, 2 Oct: the hotspots switch was removed).
- **Duplicates.** SMART pairs 2; MinHash pairs none. With short complaints,
  word-triple MinHash is too strict; SMART's trigram and meaning match is the
  better fit. Keep SMART's.
- **Patterns.** No change point; three unusual days (17 and 21 Aug, 7 Oct);
  Prophet runs but 8 weeks is the least it should learn from. Worth rerunning
  monthly as reports grow.
- **Explain.** 15 scored reports are too few to fit a model; it runs once
  there are 20.

These are small numbers on a young system. They show the tools work and
where the rules stand; they are not accuracy figures to quote. Rerun `all`
after each month of real reports.
