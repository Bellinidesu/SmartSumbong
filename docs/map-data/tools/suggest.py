#!/usr/bin/env python3
"""
Sheet suggestions from the real building: what colours it is, how its floors and bays repeat, how much of it is glass, read off the street-view faces of the
building (faces.py). The numbers are a starting point for a landmark sheet (draft), and a measure of how close the model is (compare): the palette of the real
walls against the palette of the rendered ones.

    python docs/map-data/tools/suggest.py "Plaza 66"             prints what the street shows
    python docs/map-data/tools/suggest.py "Plaza 66" --draft     writes landmarks/sheets/<slug>.json (if there is none yet) from it
"""
import colorsys, json, math, os, re, sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as K
import faces


def slug_of(name):
    return re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')


def kmeans(px, k=6, it=12, seed=1):
    rnd = np.random.default_rng(seed)
    if len(px) > 20000:
        px = px[rnd.choice(len(px), 20000, replace=False)]
    c = px[rnd.choice(len(px), k, replace=False)].astype(np.float32)
    for _ in range(it):
        d = ((px[:, None, :] - c[None]) ** 2).sum(-1)
        a = d.argmin(1)
        for j in range(k):
            if (a == j).any():
                c[j] = px[a == j].mean(0)
    sh = np.bincount(a, minlength=k) / len(px)
    return c, sh


def palette(im):
    """The colours of a wall picture: sky, leaves and the ground floor left out, six clusters, largest first: [(rgb, share)]."""
    a = np.asarray(im.convert('RGB'), dtype=np.float32)
    H = a.shape[0]
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    lum = .299 * r + .587 * g + .114 * b
    mx, mn = a.max(-1), a.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1)
    leaf = (g > r + 6) & (g > b + 4) & (sat > .15)
    sky = ((lum > 190) & (b >= r - 4) & (sat < .35)) | (lum > 240)
    ys = np.arange(H)[:, None] * np.ones((1, a.shape[1]))
    keep = ~leaf & ~sky & (ys > H * .12) & (ys < H * .80) & (lum > 25)
    px = a[keep]
    if len(px) < 500:
        return []
    c, sh = kmeans(px)
    order = np.argsort(-sh)
    return [(tuple(int(v) for v in c[i]), float(sh[i])) for i in order]


def hexof(c):
    return '%02X%02X%02X' % tuple(int(max(0, min(255, v))) for v in c)


def pastel(c):
    """The way zone.py softens a real wall colour into our palette."""
    r, g, b = [max(0, min(255, v)) / 255 for v in c]
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    l = .60 + .34 * l
    s = min(.40, s * 1.15 + .03)
    return tuple(int(round(v * 255)) for v in colorsys.hls_to_rgb(h, l, s))


def rhythm(im, ppm, height):
    """Floor height and bay width from the repeat of the edges: the autocorrelation of the picture's horizontal and vertical edge energy. (metres, confidence 0 to 1)."""
    g = np.asarray(im.convert('L'), dtype=np.float32)
    H, W = g.shape

    def period(profile, lo_m, hi_m):
        p = profile - profile.mean()
        if p.std() < 1e-3:
            return None, 0.0
        ac = np.correlate(p, p, 'full')[len(p) - 1:]
        ac /= ac[0]
        lo, hi = int(lo_m * ppm), min(len(ac) - 1, int(hi_m * ppm))
        if hi <= lo + 2:
            return None, 0.0
        peaks = [k for k in range(lo + 1, hi) if ac[k] > ac[k - 1] and ac[k] >= ac[k + 1]]        # a real repeat is a peak, not the edge of the search
        if not peaks:
            return None, 0.0
        k = max(peaks, key=lambda j: ac[j])
        return k / ppm, float(max(0.0, ac[k]))
    rows = np.abs(np.diff(g, axis=0)).mean(1)          # horizontal edges: the slab lines, one a floor
    cols = np.abs(np.diff(g, axis=1))[int(H * .15):int(H * .75)].mean(0)    # vertical edges: the bays
    fl, fc = period(rows[int(H * .1):int(H * .9)], 2.6, 4.6)
    bw, bc = period(cols, 2.4, 9.0)
    return dict(floor_h=fl, floor_conf=fc, bay_w=bw, bay_conf=bc)


def analyse(name, max_faces=3):
    bi, b = K.building_named(name)
    if b is None:
        raise SystemExit('no building called %s' % name)
    fs = faces.rectified_faces(name, max_faces)
    pals, rh = [], []
    for ln, i, im, pid, h, ppm in fs:
        p = palette(im)
        if p:
            pals.append((ln, p))
        rh.append(rhythm(im, ppm, h))
    style = json.load(open(os.path.join(K.LM, 'facade-style.json'))).get('%.5f,%.5f' % (b[4], b[5])) if os.path.exists(os.path.join(K.LM, 'facade-style.json')) else None
    out = dict(name=name, index=bi, height=b[1], faces=len(fs))
    # a wall seen from under a flyover is black: when the unwrapped faces are dark or grey, read the colours off the best street-level frames of the search instead
    def dull(p):
        lum = sum((.299 * c[0] + .587 * c[1] + .114 * c[2]) * w for c, w in p)
        sat = sum((max(c) - min(c)) / max(max(c), 1) * w for c, w in p)
        return lum < 85 or sat < .10
    if not pals or all(dull(p) for _, p in pals):
        try:
            import refsearch
            db = json.load(open(refsearch.INDEX, encoding='utf-8')) if os.path.exists(refsearch.INDEX) else {}
            got = []
            for e in sorted([e for e in db.get(name, []) if e['src'] in ('mapillary', 'user')], key=lambda e: -e.get('score', 0))[:4]:
                import hashlib
                f = os.path.join(refsearch.INBOX, slug_of(name), e['id']) if e['src'] == 'user' else os.path.join(K.REFS, 'mapillary_%s.jpg' % hashlib.md5(e['id'].encode()).hexdigest()[:12])
                if os.path.exists(f):
                    im = Image.open(f).convert('RGB')
                    W, H = im.size
                    p = palette(im.crop((int(W * .15), int(H * .12), int(W * .85), int(H * .62))))
                    if p:
                        got.append((1.0, p))
            if got:
                pals = got
                out['palette_from'] = 'street frames'
        except Exception:
            pass
    if pals:
        allc = {}
        for ln, p in pals:
            for c, s in p:
                key = tuple(v // 24 for v in c)
                cur = allc.setdefault(key, [np.zeros(3), 0.0])
                cur[0] += np.array(c) * s * ln
                cur[1] += s * ln
        ranked = sorted(((v[0] / v[1], v[1]) for v in allc.values()), key=lambda t: -t[1])
        tot = sum(w for _, w in ranked)
        cols = [(tuple(int(x) for x in c), w / tot) for c, w in ranked]
        wall = cols[0][0]
        # the accent: the most saturated colour that has a real share and is not the wall's hue
        def sat_of(c):
            return colorsys.rgb_to_hls(*[v / 255 for v in c])[2]
        acc = [c for c, w in cols[1:] if w > .04 and sat_of(c) > .22]
        out['palette'] = [('#' + hexof(c), round(w, 3)) for c, w in cols[:6]]
        out['wall'] = '#' + hexof(pastel(wall))
        out['wall_real'] = '#' + hexof(wall)
        out['accent'] = '#' + hexof(max(acc, key=sat_of)) if acc else None
    good = [r for r in rh if r['floor_h'] and r['floor_conf'] > .25]
    if good:
        out['floor_h'] = round(float(np.median([r['floor_h'] for r in good])), 2)
        out['floors_est'] = int(round((b[1] - 1.2) / out['floor_h']))
    goodb = [r for r in rh if r['bay_w'] and r['bay_conf'] > .25]
    if goodb:
        out['bay_w'] = round(float(np.median([r['bay_w'] for r in goodb])), 2)
    if style:
        out['glass'] = round(style.get('glass') or 0, 2)
    return out


def draft(name, s):
    path = os.path.join(K.LM, 'sheets', slug_of(name) + '.json')
    if os.path.exists(path):
        print('there is a sheet already (%s): not overwritten' % path)
        return
    wall = (s.get('wall') or '#EADFC6').lstrip('#')
    acc = (s.get('accent') or '#3F67B0').lstrip('#')
    glass = s.get('glass') or 0
    bay = s.get('bay_w') or 6.4
    body = 'tower' if glass > .45 else 'floors'
    sheet = {
        'name': name,
        'match': {'name': name},
        'about': 'DRAFT from the street view (suggest.py): colours, floor height %s m, bay %s m, glass %.0f%%. Everything below is a starting point to edit with the bench.' % (s.get('floor_h', '?'), bay, glass * 100),
        'palette': {'wall': wall, 'trim': 'F4F1EA', 'accent': acc, 'podium': wall},
        'use': 'commercial-residential',
        'tiles': {
            'floors': {'kind': 'curtain' if glass > .45 else 'loggia', 'm': [round(bay, 1), s.get('floor_h') or 3.4], 'fit': True, 'seed': 1, 'p': .4, 'graded': glass > .45},
            'shops': {'kind': 'shopfront', 'm': [8.0, 4.2], 'fit': True, 'seed': 2, 'p': .7},
            'band': {'kind': 'band', 'm': [7.2, 3.4], 'fit': True, 'seed': 3, 'p': .3},
        },
        'body': {'podium': 6.0, 'podium_mat': 'shops', 'floors_mat': 'floors', 'band': 3.4, 'band_mat': 'band', 'band_colour': 'accent'},
        'features': [{'type': 'canopy', 'at': .5, 'colour': 'accent', 'width': 9.0}, {'type': 'roof_sign', 'text': name.upper(), 'at': .5, 'width': 14.0, 'neon': 'blue'}],
        'facade': {'awnings': True, 'entrance': False, 'sign': False},
        'night': {'wash': {'color': 'blue', 'height': 20, 'strength': .5}},
        'ref': [],
    }
    json.dump(sheet, open(path, 'w', encoding='utf-8'), indent=2)
    print('draft written:', path)


def main():
    a = [x for x in sys.argv[1:] if not x.startswith('--')]
    if not a:
        raise SystemExit(__doc__)
    s = analyse(a[0])
    print(json.dumps(s, indent=1))
    if '--draft' in sys.argv:
        draft(a[0], s)


if __name__ == '__main__':
    main()
