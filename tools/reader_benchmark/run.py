"""How well do the candidate readers recover a word's root? Scores SMART's live reader (migration 0125 + 0133) and a plain
fuzzy-matching baseline (RapidFuzz, MIT) on cases.tsv: a word, the root it should read as, or NONE when it must stay unknown
(a trap: a real word that only looks like a known one).

    python run.py            # needs the Supabase CLI linked to the project (read-only: calls _smart_read and _smart_vocab)
Pass --offline to score the baseline only. Words, not residents' reports: no personal data is read."""
import csv, json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
cases = [r for r in csv.DictReader(open(os.path.join(HERE, 'cases.tsv'), encoding='utf-8'), delimiter='\t')]


def sql(q):
    f = os.path.join(tempfile.mkdtemp(), 'q.sql')
    open(f, 'w', encoding='utf-8').write(q)
    out = subprocess.run(['supabase', 'db', 'query', '--linked', '-f', f], capture_output=True, text=True, shell=os.name == 'nt').stdout
    return json.loads(out[out.index('{'):out.rindex('}') + 1])['rows']


vocab = [r['w'] for r in sql("select unnest(public._smart_vocab()) as w")] if '--offline' not in sys.argv else []
smart = {}
if vocab:
    words = ','.join("'" + c['word'].replace("'", "''") + "'" for c in cases)
    for r in sql(f"select w, (select root from public._smart_read(w) limit 1) as root from unnest(array[{words}]) as w"):
        smart[r['w']] = r['root']

try:
    from rapidfuzz import process, fuzz
except ImportError:
    process = None


def fuzzy(word, cut):
    if not process or not vocab:
        return None
    best = process.extractOne(word, vocab, scorer=fuzz.ratio, score_cutoff=cut)
    return best[0] if best else None


def mark(got, want):
    return (got is None) if want == 'NONE' else (got == want)


systems = {'SMART (rules, 0133)': lambda w: smart.get(w), 'RapidFuzz alone, cut 80': lambda w: fuzzy(w, 80), 'RapidFuzz alone, cut 70': lambda w: fuzzy(w, 70)}
print(f'{len(cases)} cases: {sum(c["root"] != "NONE" for c in cases)} words to recover, {sum(c["root"] == "NONE" for c in cases)} traps that must stay unknown\n')
for name, fn in systems.items():
    rec = [c for c in cases if c['root'] != 'NONE']; trap = [c for c in cases if c['root'] == 'NONE']
    r = sum(mark(fn(c['word']), c['root']) for c in rec); t = sum(mark(fn(c['word']), c['root']) for c in trap)
    print(f'{name:28s} recovered {r}/{len(rec)}   traps kept unknown {t}/{len(trap)}')
    if '-v' in sys.argv:
        for c in cases:
            if not mark(fn(c['word']), c['root']):
                print(f'    miss: {c["word"]:14s} wanted {c["root"]:10s} got {fn(c["word"])}   ({c["note"]})')
