"""SMART's offline lab: open-source tools that check the engine's rules from outside, never in the live path. Rules
decide in the database; this only measures them, so the barangay can see where a rule is weak before changing it.

    python lab.py words       the word reader against calamanCy (Tagalog lemmas) and a phonetic key (jellyfish)
    python lab.py language    which language a complaint is in: lingua and TagLID against a labelled set
    python lab.py hotspots    H3 hexagon cells against the DBSCAN hotspots of report_hotspots() (0042)
    python lab.py duplicates  MinHash (datasketch) against SMART's own duplicate check
    python lab.py patterns    change points (ruptures), outlier days (PyOD), a weekly forecast (Prophet)
    python lab.py explain     a glass-box model (InterpretML) of the triage score: which factors carry it
    python lab.py all

Reads the live project read-only through the Supabase CLI (`supabase db query --linked`). Prints tracking IDs and
counts, never a resident's name or words. Install: py -3.12 -m pip install -r requirements.txt. See README.md."""
import csv, json, os, subprocess, sys, tempfile, warnings
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
BENCH = os.path.join(HERE, '..', 'reader_benchmark', 'cases.tsv')
warnings.filterwarnings('ignore')


def sql(q):
    f = os.path.join(tempfile.mkdtemp(), 'q.sql')
    open(f, 'w', encoding='utf-8').write(q)
    out = subprocess.run(['supabase', 'db', 'query', '--linked', '-f', f], capture_output=True, text=True, encoding='utf-8',
                         shell=os.name == 'nt').stdout
    if '{' not in out:
        sys.exit('the Supabase CLI gave no answer (is the project linked?)')
    return json.loads(out[out.index('{'):out.rindex('}') + 1])['rows']


def head(title):
    print('\n== ' + title)


def reports():
    return sql("""select r.tracking_id, r.category::text as category, r.status::text as status, r.created_at,
                         r.latitude, r.longitude, t.score, t.level, t.reasons
                    from public.reports r left join public.report_triage t on t.report_id = r.id
                   where r.deleted_at is null order by r.created_at""")


def words():
    head('Word reader: SMART against calamanCy and a phonetic key')
    cases = list(csv.DictReader(open(BENCH, encoding='utf-8'), delimiter='\t'))
    vocab = {r['w'] for r in sql("select unnest(public._smart_vocab()) as w")}
    lex = {r['variant']: r['root'] for r in sql("select variant, root from public.smart_lexicon")}
    ws = ','.join("'" + c['word'].replace("'", "''") + "'" for c in cases)
    smart = {r['w']: r['root'] for r in sql(f"select w, (select root from public._smart_read(w) limit 1) as root from unnest(array[{ws}]) as w")}
    known = lambda w: w if w in vocab else lex.get(w)
    import calamancy, jellyfish
    nlp = calamancy.load('tl_calamancy_md-0.2.0')
    lemma = {c['word']: known(nlp(c['word'].replace('-', ''))[0].lemma_.lower()) for c in cases}
    keys = defaultdict(set)
    for v in vocab | set(lex):
        if len(v) >= 4:
            keys[jellyfish.metaphone(v)].add(known(v))
    def phon(w):
        hits = keys.get(jellyfish.metaphone(w.replace('-', '')), set())
        return next(iter(hits)) if len(hits) == 1 else None
    systems = {
        'SMART rules': lambda w: smart.get(w),
        'calamanCy lemma, then the word list': lambda w: lemma[w],
        'phonetic key (Metaphone) alone': phon,
        'SMART, calamanCy when SMART knows nothing': lambda w: smart.get(w) or lemma[w],
    }
    want = lambda c, got: got is None if c['root'] == 'NONE' else got == c['root']
    rec = [c for c in cases if c['root'] != 'NONE']; trap = [c for c in cases if c['root'] == 'NONE']
    for name, fn in systems.items():
        r = sum(want(c, fn(c['word'])) for c in rec); t = sum(want(c, fn(c['word'])) for c in trap)
        print(f'  {name:44s} recovered {r:2d}/{len(rec)}   traps kept unknown {t}/{len(trap)}')
    extra = [c['word'] for c in rec if not smart.get(c['word']) and lemma[c['word']] == c['root']]
    wrong = [c['word'] for c in trap if not smart.get(c['word']) and lemma[c['word']]]
    print(f'  calamanCy adds: {", ".join(extra) or "nothing SMART misses"}; and misreads: {", ".join(wrong) or "no trap"}')


SENTENCES = [
    ('Nasusunog yung bahay sa kanto, tulong po', 'tl'), ('May sunog sa likod ng palengke', 'tl'),
    ('Binaha na naman ang kalye namin', 'tl'), ('Walang ilaw sa poste dito sa amin', 'tl'),
    ('Maingay ang videoke ng kapitbahay hanggang madaling araw', 'tl'), ('May asong nangangagat sa daan', 'tl'),
    ('Barado ang kanal sa harap ng tindahan', 'tl'), ('Nagkagulo ang mga lasing sa kanto', 'tl'),
    ('There is a fire near the market', 'en'), ('The street light has been broken for a week', 'en'),
    ('Loud karaoke every night until 3 am', 'en'), ('A stray dog bit a child near the school', 'en'),
    ('Garbage has not been collected since Monday', 'en'), ('Two cars crashed at the corner', 'en'),
    ('Flooded na yung street namin, knee deep na', 'mix'), ('Sobrang ingay ng videoke, please paki-check', 'mix'),
    ('May fallen tree sa road, blocking the way', 'mix'), ('Yung garbage hindi pa nakukuha since Monday', 'mix'),
    ('Ang daming stray dogs dito, delikado sa kids', 'mix'), ('Live wire sa poste, sparking na po', 'mix'),
]


def language():
    head('Language: lingua and TagLID on a labelled set of 20 (Tagalog, English, Taglish)')
    from lingua import Language, LanguageDetectorBuilder
    det = LanguageDetectorBuilder.from_languages(Language.ENGLISH, Language.TAGALOG).build()
    from taglid.lid import lang_identify
    def lingua(s):
        conf = {c.language: c.value for c in det.compute_language_confidence_values(s)}
        en, tl = conf.get(Language.ENGLISH, 0), conf.get(Language.TAGALOG, 0)
        return 'mix' if min(en, tl) > 0.2 else ('en' if en > tl else 'tl')
    def taglid(s):
        # one score per word, {'eng': 0..1, 'tgl': 0..1}; a word with neither (a name, "Flooded") counts for nothing
        words = lang_identify(s)
        en = sum(1 for x in words if x['eng'] > x['tgl'])
        tl = sum(1 for x in words if x['tgl'] > x['eng'])
        return 'mix' if en and tl and min(en, tl) / (en + tl) >= 0.2 else ('en' if en > tl else 'tl')
    for name, fn in (('lingua (two languages)', lingua), ('TagLID (word by word)', taglid)):
        try:
            got = [(fn(s), want) for s, want in SENTENCES]
            print(f'  {name:26s} right {sum(g == w for g, w in got)}/{len(got)}   Taglish found {sum(g == w == "mix" for g, w in got)}/'
                  f'{sum(w == "mix" for _, w in SENTENCES)}')
        except Exception as e:
            print(f'  {name:26s} could not run: {e.__class__.__name__}: {str(e)[:80]}')


def hotspots():
    head('Hotspots: H3 cells (resolution 10, about 66 m a side) against DBSCAN clusters (45 m, 3 reports)')
    import h3
    rows = [r for r in reports() if r['latitude'] and r['longitude']]
    cells = Counter(h3.latlng_to_cell(float(r['latitude']), float(r['longitude']), 10) for r in rows)
    clusters = sql("select * from public.report_hotspots(now() - interval '20 years', now(), null) where cluster_id is not null")
    print(f'  {len(rows)} reports with a place; {len(cells)} cells; {len(clusters)} DBSCAN clusters')
    top = cells.most_common(5)
    for c, n in top:
        lat, lng = h3.cell_to_latlng(c)
        near = [k for k in clusters if h3.latlng_to_cell(k['centroid_lat'], k['centroid_lng'], 10) in (set(h3.grid_disk(c, 1)))]
        print(f'  cell {c}: {n} reports at {lat:.5f},{lng:.5f}; DBSCAN cluster here: {"yes" if near else "no"}')
    caught = sum(1 for k in clusters if cells.get(h3.latlng_to_cell(k['centroid_lat'], k['centroid_lng'], 10), 0) >= 2)
    print(f'  DBSCAN clusters whose centre cell holds 2+ reports: {caught}/{len(clusters)}')


def duplicates():
    head('Duplicates: MinHash on word triples against SMART (pg_trgm and meaning)')
    from datasketch import MinHash, MinHashLSH
    rows = sql("""select r.id, r.tracking_id, r.category::text as category, lower(r.subject || ' ' || r.description) as t
                    from public.reports r where r.deleted_at is null""")
    smart = {(r['a'], r['b']) for r in sql("""select r.tracking_id as a, d.tracking_id as b
                    from public.reports r, public.smart_duplicates_of(r.id) d where r.deleted_at is null""")}
    smart |= {(b, a) for a, b in smart}
    lsh, mh = MinHashLSH(threshold=0.5, num_perm=128), {}
    for r in rows:
        m = MinHash(num_perm=128)
        toks = r['t'].split()
        for i in range(max(1, len(toks) - 2)):
            m.update(' '.join(toks[i:i + 3]).encode())
        mh[r['tracking_id']] = (m, r['category'])
        lsh.insert(r['tracking_id'], m)
    pairs = set()
    for tid, (m, cat) in mh.items():
        for o in lsh.query(m):
            if o != tid and mh[o][1] == cat:
                pairs.add(tuple(sorted((tid, o))))
    both = {p for p in pairs if p in smart}
    print(f'  SMART pairs: {len(smart) // 2}; MinHash pairs (same kind): {len(pairs)}; both: {len(both)}')
    for a, b in sorted(pairs - both)[:8]:
        print(f'  MinHash only: {a} ~ {b} (SMART did not pair them: farther apart, older, or its similarity bar)')


def patterns():
    head('Patterns: change points, outlier days, a weekly forecast')
    rows = reports()
    if not rows:
        return print('  no reports')
    days = Counter(datetime.fromisoformat(r['created_at']).astimezone(timezone(timedelta(hours=8))).date() for r in rows)
    first, last = min(days), max(days)
    series = [(first + timedelta(d), days.get(first + timedelta(d), 0)) for d in range((last - first).days + 1)]
    weeks = len(series) // 7
    print(f'  {len(rows)} reports over {len(series)} days ({weeks} weeks)')
    import numpy as np
    y = np.array([n for _, n in series], dtype=float)
    try:
        import ruptures as rpt
        bk = rpt.Pelt(model='rbf', min_size=7).fit(y).predict(pen=3)[:-1]
        print('  ruptures: the daily rate changes on ' + (', '.join(str(series[b][0]) for b in bk) or 'no day'))
    except Exception as e:
        print(f'  ruptures could not run: {e}')
    try:
        from pyod.models.ecod import ECOD
        m = ECOD(contamination=0.05).fit(y.reshape(-1, 1))
        out = [str(series[i][0]) + f' ({int(y[i])})' for i in np.where(m.labels_ == 1)[0] if y[i] > 0]
        print('  PyOD (ECOD): unusual days: ' + (', '.join(out[:8]) or 'none'))
    except Exception as e:
        print(f'  PyOD could not run: {e}')
    if weeks < 8:
        return print(f'  Prophet: skipped, {weeks} weeks is too short to learn a weekly pattern (needs 8 or more)')
    try:
        import pandas as pd
        from prophet import Prophet
        df = pd.DataFrame({'ds': [d for d, _ in series], 'y': y})
        f = Prophet(weekly_seasonality=True, yearly_seasonality=False, daily_seasonality=False).fit(df)
        fc = f.predict(f.make_future_dataframe(periods=7)).tail(7)
        print('  Prophet, next 7 days: ' + ', '.join(f'{r.ds:%a} {max(0, r.yhat):.1f}' for r in fc.itertuples()))
    except Exception as e:
        print(f'  Prophet could not run: {e}')


def explain():
    head('Explain: a glass-box model of the triage score (InterpretML EBM)')
    rows = [r for r in reports() if r['score'] is not None]
    if len(rows) < 20:
        return print(f'  {len(rows)} scored reports: too few to fit')
    import pandas as pd
    from interpret.glassbox import ExplainableBoostingRegressor
    def feats(r):
        reasons = r['reasons'] if isinstance(r['reasons'], list) else json.loads(r['reasons'] or '[]')
        t = datetime.fromisoformat(r['created_at']).astimezone(timezone(timedelta(hours=8)))
        f = {'category': r['category'], 'hour': t.hour, 'weekday': t.weekday(),
             'words': sum(int(x.get('points') or 0) for x in reasons if x.get('factor') == 'words'),
             'nearby': sum(int(x.get('points') or 0) for x in reasons if x.get('factor') in ('nearby', 'nearby reports')),
             'zone': sum(int(x.get('points') or 0) for x in reasons if 'zone' in str(x.get('factor', '')))}
        return f
    X = pd.DataFrame([feats(r) for r in rows]); y = [r['score'] for r in rows]
    m = ExplainableBoostingRegressor(interactions=0, random_state=1).fit(X, y)
    g = m.explain_global().data()
    for name, imp in sorted(zip(g['names'], g['scores']), key=lambda x: -x[1]):
        print(f'  {name:10s} {imp:6.2f}')
    print('  The rules give points for kind, words, place and night; if hour or weekday ranked high here, the night rule')
    print('  would be carrying more than intended.')


CMDS = {'words': words, 'language': language, 'hotspots': hotspots, 'duplicates': duplicates, 'patterns': patterns, 'explain': explain}
if __name__ == '__main__':
    a = sys.argv[1:] or ['help']
    if a[0] == 'all':
        for f in CMDS.values():
            f()
    elif a[0] in CMDS:
        CMDS[a[0]]()
    else:
        sys.exit(__doc__)
