#!/usr/bin/env python3
"""
The skyline test: a landmark must not share its outline with another. Each model is drawn as a flat black shape from eight sides (the way it reads against the
sky from 300 m), every outline is scaled to the same height so that size does not hide a likeness, and every pair of landmarks is compared (best match over the
sides, intersection over union). Pairs that match more than the limit are listed: one of the two needs a different shape.

    python docs/map-data/tools/silhouettes.py                 the heroes (every landmark with a sheet) against every other landmark
    python docs/map-data/tools/silhouettes.py --all           every model against every model
    python docs/map-data/tools/silhouettes.py --limit 0.80
"""
import gzip, json, os, sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
MAP = os.path.normpath(os.path.join(HERE, '..', '..', '..', 'admin', 'assets', 'map'))
N = 96
SIDES = 8


def load():
    meta = json.load(open(os.path.join(MAP, 'landmarks3d.json'), encoding='utf-8'))
    raw = gzip.decompress(open(os.path.join(MAP, 'landmarks3d.bin.gz'), 'rb').read())
    rec = np.frombuffer(raw[:meta['indexOffsetBytes']], dtype=[('p', '<f4', 3), ('uv', '<f4', 2), ('m', 'u1'), ('c', 'u1', 3)])
    idx = np.frombuffer(raw[meta['indexOffsetBytes']:], dtype='<u4')
    return meta, rec['p'], idx


def outlines(P, I):
    """Eight silhouettes of one model, each fitted to the frame by its longer side (so a long low block and a tall slim one do not look alike)."""
    h = float(P[:, 2].max())
    out = []
    cx, cy = (P[:, 0].min() + P[:, 0].max()) / 2, (P[:, 1].min() + P[:, 1].max()) / 2
    for k in range(SIDES):
        a = k * np.pi / SIDES * 2
        u = (P[:, 0] - cx) * np.cos(a) + (P[:, 1] - cy) * np.sin(a)
        ext = max(float(u.max() - u.min()), h, 1.0)
        X = (u / ext * (N * .9) + N / 2)
        Y = N - 2 - P[:, 2] / ext * (N * .9)
        im = Image.new('L', (N, N), 0)
        d = ImageDraw.Draw(im)
        for t in I.reshape(-1, 3):
            d.polygon([(X[t[0]], Y[t[0]]), (X[t[1]], Y[t[1]]), (X[t[2]], Y[t[2]])], fill=255)
        out.append(np.asarray(im) > 0)
    return out


def iou(a, b):
    u = np.logical_or(a, b).sum()
    return np.logical_and(a, b).sum() / u if u else 0.0


def main():
    lim = float(sys.argv[sys.argv.index('--limit') + 1]) if '--limit' in sys.argv else .85
    meta, P, idx = load()
    models = meta['models']
    hero = [i for i, m in enumerate(models) if m.get('template') == 'sheet']
    pool = list(range(len(models))) if '--all' in sys.argv else [i for i, m in enumerate(models) if m.get('template') not in ('furniture', 'tower', 'generic', 'condo', 'hotel', 'office', 'mall', 'parking', 'hangar') or i in hero]
    use = sorted(set(hero + pool)) if '--all' not in sys.argv else pool
    O = {}
    for i in use:
        m = models[i]
        v = P[m['voff']:m['voff'] + m['v']]
        ii = idx[m['ioff']:m['ioff'] + m['i']]
        if len(v) < 8 or m.get('furniture'):
            continue
        O[i] = outlines(v, ii)
    pairs = []
    keys = list(O)
    for a in keys:
        for b in keys:
            if a >= b or (hero and '--all' not in sys.argv and a not in hero and b not in hero):
                continue
            best = max(iou(O[a][s], O[b][s2]) for s in range(SIDES) for s2 in range(SIDES))
            pairs.append((best, a, b))
    pairs.sort(reverse=True)
    print('%d models compared, %d pairs' % (len(O), len(pairs)))
    bad = [p for p in pairs if p[0] >= lim]
    for s, a, b in (bad[:40] or pairs[:5]):
        print('%.2f  %s  <->  %s%s' % (s, models[a]['name'], models[b]['name'], '' if s >= lim else '   (closest, under the limit)'))
    print('%d pair(s) share an outline above %.2f' % (len(bad), lim))


main()
