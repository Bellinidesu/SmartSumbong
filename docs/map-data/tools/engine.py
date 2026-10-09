#!/usr/bin/env python3
"""
The landmark engine, one command for everything about designing a landmark.

    engine.py find <words>        search every named building, sheet, model and reference we know (fuzzy; shows what each already has)
    engine.py status              the landmarks that have a sheet: built or not, size, references, how close the wall colour is to the street's
    engine.py refs <name>         reference search: photos, street views, models, ranked, one board         (refsearch.py)
    engine.py finder              Google image search on a page of ours: press + on a picture to put it on a landmark's board       (finder.py)
    engine.py sources <name>      what the owners, builders and open databases say about the area (OSM links, Wikidata facts); --grab takes their pictures   (sources.py)
    engine.py suggest <name>      colours, floor height, bay width and glass read off the street view         (suggest.py)
    engine.py draft <name>        a first sheet from those numbers, to edit                                    (suggest.py --draft)
    engine.py bench <name>        one landmark from four sides, day and night, beside the street view          (bench.py)
    engine.py sil                 the skyline test: landmarks must not share an outline                        (silhouettes.py)
    engine.py new <name>          refs + suggest + draft + build + bench, the whole first pass in one go
    engine.py build               rebuild the models, their light and the washes                                (make_city.py)
"""
import difflib, glob, json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import common as K


def norm(s):
    return re.sub(r'[^a-z0-9 ]+', ' ', (s or '').lower()).split()


def score(q, text):
    """0 to 1: how well the words of q are found in text (prefix and substring beat fuzzy)."""
    qw, tw = norm(q), norm(text)
    if not qw or not tw:
        return 0.0
    joined = ' '.join(tw)
    s = 0.0
    for w in qw:
        if w in tw:
            s += 1.0
        elif any(t.startswith(w) for t in tw):
            s += .85
        elif w in joined:
            s += .6
        else:
            s += max((difflib.SequenceMatcher(None, w, t).ratio() for t in tw), default=0) * .55
    s /= len(qw)
    if ' '.join(qw) == joined:
        s += .3
    return min(s, 1.3)


def sheets():
    out = {}
    for f in sorted(glob.glob(os.path.join(K.LM, 'sheets', '*.json'))):
        try:
            sh = json.load(open(f, encoding='utf-8'))
        except Exception:
            continue
        sh['slug'] = os.path.splitext(os.path.basename(f))[0]
        out[sh.get('name') or sh['slug']] = sh
    return out


def models():
    p = os.path.join(K.MAPDIR, 'landmarks3d.json')
    return {m['name']: m for m in json.load(open(p, encoding='utf-8'))['models']} if os.path.exists(p) else {}


def refs_index():
    p = os.path.join(K.LM, 'refs-index.json')
    return json.load(open(p, encoding='utf-8')) if os.path.exists(p) else {}


def find(q, limit=15):
    b, info = K.buildings()
    S, M, R = sheets(), models(), refs_index()
    hits = []
    for k, (nm, cls) in info.items():
        if not nm:
            continue
        sc = score(q, nm) + .25 * score(q, cls)
        if sc >= .55:
            bb = b[int(k)]
            hits.append((sc + (.15 if nm in S else 0) + min(bb[6] * bb[7], 20000) / 200000, nm, cls, int(k), bb))
    hits.sort(key=lambda t: -t[0])
    seen, rows = set(), []
    for sc, nm, cls, k, bb in hits:
        if (nm, k) in seen:
            continue
        seen.add((nm, k))
        rows.append((nm, cls, k, bb))
        if len(rows) >= limit:
            break
    if not rows:
        print('nothing found for "%s"' % q)
        return
    print('%-40s %-14s %5s %7s  %s' % ('name', 'class', 'm', 'area', 'has'))
    for nm, cls, k, bb in rows:
        has = []
        if nm in S:
            has.append('sheet')
        if nm in M:
            has.append('model:%s' % M[nm]['template'])
        if nm in R:
            has.append('refs:%d/%d picked' % (len(R[nm]), sum(1 for e in R[nm] if e.get('picked'))))
        print('%-40s %-14s %5.0f %7.0f  %s' % (nm[:40], (cls or '')[:14], bb[1], bb[6] * bb[7], ', '.join(has) or '-'))
    # sheets and references that mention the words but are not a building name
    for nm, sh in S.items():
        if score(q, (sh.get('about') or '') + ' ' + ' '.join(f.get('type', '') for f in sh.get('features', [])) + ' ' + str(sh.get('use'))) > .8 and nm not in [r[0] for r in rows]:
            print('sheet:', nm, '-', (sh.get('about') or '')[:80])
    for nm, es in R.items():
        for e in es:
            if score(q, e['title']) > .9 and e.get('picked'):
                print('reference for %s: %s (%s)' % (nm, e['title'], e['url']))


def wall_colour(name):
    """The median albedo of a model's wall vertices (what the sheet painted), from the built model."""
    import gzip
    import numpy as np
    M = models()
    if name not in M:
        return None
    m = M[name]
    meta = json.load(open(os.path.join(K.MAPDIR, 'landmarks3d.json'), encoding='utf-8'))
    raw = gzip.decompress(open(os.path.join(K.MAPDIR, 'landmarks3d.bin.gz'), 'rb').read())
    rec = np.frombuffer(raw[:meta['indexOffsetBytes']], dtype=[('p', '<f4', 3), ('uv', '<f4', 2), ('m', 'u1'), ('c', 'u1', 3)])
    v = rec[m['voff']:m['voff'] + m['v']]
    sel = v[(v['m'] >= 100) | np.isin(v['m'], [1, 2, 11, 12, 13])]
    return tuple(int(x) for x in np.median(sel['c'].astype(float), axis=0)) if len(sel) else None


def lab(c):
    import colorsys
    r, g, b = [x / 255 for x in c]
    f = lambda t: ((t + .055) / 1.055) ** 2.4 if t > .04045 else t / 12.92
    r, g, b = f(r), f(g), f(b)
    x, y, z = (r * .4124 + g * .3576 + b * .1805) / .95047, r * .2126 + g * .7152 + b * .0722, (r * .0193 + g * .1192 + b * .9505) / 1.08883
    h = lambda t: t ** (1 / 3) if t > .008856 else 7.787 * t + 16 / 116
    return 116 * h(y) - 16, 500 * (h(x) - h(y)), 200 * (h(y) - h(z))


def delta_e(a, b):
    return sum((p - q) ** 2 for p, q in zip(lab(a), lab(b))) ** .5


def status():
    S, M = sheets(), models()
    R = refs_index()
    if not S:
        print('no sheets yet')
        return
    import suggest
    print('%-24s %-8s %7s %6s  %-14s  %s' % ('landmark', 'built', 'verts', 'tris', 'references', 'wall colour vs the street'))
    for nm, sh in S.items():
        m = M.get(nm)
        refs = R.get(nm, [])
        cmp_ = '-'
        try:
            s = suggest.analyse(nm, 2)
            ours = wall_colour(nm)
            if s.get('wall') and ours:
                real = tuple(int(s['wall'].lstrip('#')[i:i + 2], 16) for i in (0, 2, 4))
                de = delta_e(real, ours)
                cmp_ = 'dE %.0f (%s)' % (de, 'close' if de < 12 else 'near' if de < 24 else 'far')
        except SystemExit:
            pass
        except Exception as e:
            cmp_ = 'n/a (%s)' % str(e)[:30]
        print('%-24s %-8s %7s %6s  %-14s  %s' % (nm[:24], 'yes' if m else 'NO', m['v'] if m else '-', int(m['i'] / 3) if m else '-', '%d (%d picked)' % (len(refs), sum(1 for e in refs if e.get('picked'))), cmp_))


def run(script, *args):
    return subprocess.run([sys.executable, os.path.join(HERE, script)] + list(args)).returncode


def main():
    a = sys.argv[1:]
    if not a:
        raise SystemExit(__doc__)
    c, rest = a[0], a[1:]
    name = rest[0] if rest and not rest[0].startswith('--') else None
    if c == 'find':
        return find(' '.join(x for x in rest if not x.startswith('--')))
    if c == 'status':
        return status()
    if c == 'refs' and name:
        return run('refsearch.py', *rest)
    if c == 'suggest' and name:
        return run('suggest.py', *rest)
    if c == 'draft' and name:
        return run('suggest.py', name, '--draft')
    if c == 'bench' and name:
        return run('bench.py', *rest)
    if c == 'finder':
        return run('finder.py', *rest)
    if c == 'sources' and name:
        return run('sources.py', *rest)
    if c == 'sil':
        return run('silhouettes.py', *rest)
    if c == 'build':
        return run('make_city.py', '--only', 'models,light,wash')
    if c == 'new' and name:
        run('refsearch.py', name)
        run('suggest.py', name, '--draft')
        run('bench.py', name, '--rebuild')
        return
    raise SystemExit(__doc__)


if __name__ == '__main__':
    main()
