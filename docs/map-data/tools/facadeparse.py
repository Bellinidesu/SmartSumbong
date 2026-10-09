#!/usr/bin/env python3
"""
EXPERIMENTAL: the automatic reading is unreliable (it mixes up wall and glass on most facades); read facades with measure.py and write the numbers into the sheet by hand.
Facade parsing: read the structure of a real facade off its unwrapped street-view pictures (faces.py) and write it down as numbers a landmark's tile can be drawn
from: how wide a bay is and how tall a floor, where the window sits in its cell (fractions), how much is glass, piers between the bays, the spandrel under each
window, the colours of the glass, the wall, the piers and the frames, whether the glass runs in tall strips over many floors. The pictures are only measured; the
tile is drawn afresh in our style (tiles_lib.py, kind 'photo'), so nothing of the photograph is kept except these numbers.

    python docs/map-data/tools/facadeparse.py "Horizon Centre"        parse and print (and write landmarks/photo-params.json)
    python docs/map-data/tools/facadeparse.py --all                   every landmark that has a sheet
"""
import colorsys, json, math, os, sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as K
import faces

OUT = os.path.join(K.LM, 'photo-params.json')


def _masks(a):
    f = a.astype(np.float32)
    r, g, b = f[..., 0], f[..., 1], f[..., 2]
    lum = .299 * r + .587 * g + .114 * b
    mx, mn = f.max(-1), f.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1)
    leaf = (g > r + 8) & (g > b + 6) & (sat > .18) & (lum < 150)
    sky = (((lum > 185) & (b >= r - 6) & (sat < .38)) | (lum > 242))
    return lum, sat, leaf, sky


def _period(profile, ppm, lo_m, hi_m):
    """(metres, confidence, phase px) of the strongest repeat of a 1-D profile."""
    p = np.asarray(profile, dtype=np.float32)
    p = p - p.mean()
    if p.std() < 1e-4 or len(p) < 20:
        return None, 0.0, 0
    ac = np.correlate(p, p, 'full')[len(p) - 1:]
    ac /= max(ac[0], 1e-9)
    lo, hi = max(3, int(lo_m * ppm)), min(len(ac) - 2, int(hi_m * ppm))
    if hi <= lo + 2:
        return None, 0.0, 0
    peaks = [k for k in range(lo, hi) if ac[k] > ac[k - 1] and ac[k] >= ac[k + 1]]
    if not peaks:
        return None, 0.0, 0
    # prefer the smallest period whose peak is nearly as strong as the best (a bay, not two bays)
    best = max(peaks, key=lambda k: ac[k])
    for k in peaks:
        if ac[k] >= .8 * ac[best]:
            best = k
            break
    per = best
    ph = int(np.argmax([np.sum(p[(np.arange(len(p)) - s) % per == 0]) for s in range(per)])) if per > 2 else 0
    return per / ppm, float(max(0.0, ac[best])), ph


def parse_face(im, ppm, height, podium=None):
    a = np.asarray(im.convert('RGB'))
    H, W = a.shape[:2]
    lum, sat, leaf, sky = _masks(a)
    r0 = int(H * (.22 if podium is None else min(.5, podium / max(height, 1) + .03)))
    r1 = int(H * .88)
    c0, c1 = int(W * .06), int(W * .94)
    sub = a[r0:r1, c0:c1]
    L, S, lf, sk = lum[r0:r1, c0:c1], sat[r0:r1, c0:c1], leaf[r0:r1, c0:c1], sky[r0:r1, c0:c1]
    valid = ~lf & ~sk
    if valid.mean() < .25:
        return None
    # glass is what is unlike the wall: take the wall as the commonest colour of the valid pixels, glass as the cluster furthest from it
    px = sub[valid].astype(np.float32)
    km = _kmeans(px, 5)
    cen, share = km
    wall_i = int(np.argmax(share * (np.asarray([_hls(c)[1] for c in cen]) > .18)))   # the commonest not-black colour
    d = np.linalg.norm(sub.astype(np.float32)[..., None, :] - cen[None, None, :, :], axis=-1)
    lab = d.argmin(-1)
    # glass cluster: bluer/greener or darker than the wall, and with a regular spread: the cluster whose column-profile repeats most
    best = None
    for k in range(len(cen)):
        if k == wall_i or share[k] < .06:
            continue
        m = (lab == k) & valid
        cp = m.mean(0)
        per, conf, ph = _period(cp, ppm, 2.2, 10.0)
        if per and (best is None or conf * share[k] ** .3 > best[0]):
            best = (conf * share[k] ** .3, k, per, conf, ph)
    if not best:
        return None
    _, gk, bay, bconf, bph = best
    G = (lab == gk) & valid
    rp = G.mean(1)
    fl, fconf, fph = _period(rp, ppm, 2.7, 4.6)
    strip = False
    if not fl or fconf < .2:                    # tall strips of glass over many floors: no floor rhythm in the glass
        strip = True
        fl = 3.4
        fph = 0
    # the mean cell: fold the glass mask by (bay, floor)
    bw, fh = max(8, int(round(bay * ppm))), max(8, int(round(fl * ppm)))
    acc = np.zeros((fh, bw), np.float32)
    cnt = np.zeros((fh, bw), np.float32)
    ys, xs = np.nonzero(valid)
    np.add.at(acc, (((ys - fph) % fh), ((xs - bph) % bw)), G[ys, xs].astype(np.float32))
    np.add.at(cnt, (((ys - fph) % fh), ((xs - bph) % bw)), 1)
    cell = acc / np.maximum(cnt, 1)
    cx, cy = cell.mean(0), cell.mean(1)

    def span(p):
        t = (p.max() + p.min()) / 2
        on = p > t
        if on.all() or not on.any():
            return 0.1, 0.9
        # the longest run of "on" in the circular profile, centred on the strongest point
        idx = np.nonzero(on)[0]
        runs = np.split(idx, np.nonzero(np.diff(idx) > 1)[0] + 1)
        run = max(runs, key=len)
        return run[0] / len(p), (run[-1] + 1) / len(p)
    x0, x1 = span(cx)
    y0, y1 = span(cy)
    # roll so that the window is in the middle of the cell (the phase is arbitrary)
    mid_x = (x0 + x1) / 2
    mid_y = (y0 + y1) / 2
    x0, x1 = x0 - mid_x + .5, x1 - mid_x + .5
    y0, y1 = y0 - mid_y + .5, y1 - mid_y + .5
    # colours
    def hexof(c):
        return '%02X%02X%02X' % tuple(int(max(0, min(255, v))) for v in c)
    gl = sub[G & valid]
    glass = np.median(gl, axis=0) if len(gl) > 50 else cen[gk]
    wallc = cen[wall_i]
    # piers and spandrel: the pixels of the cell that are not glass, split by where they are (between windows, or under them)
    return dict(bay_w=round(bay, 2), floor_h=round(fl, 2), bay_conf=round(bconf, 2), floor_conf=round(fconf, 2), strip=strip,
                win=[round(max(0, x0), 3), round(min(1, x1), 3), round(max(0, y0), 3), round(min(1, y1), 3)],
                glass_share=round(float(G[valid].mean()), 3), glass=hexof(glass), wall=hexof(wallc),
                glass_spread=round(float(np.std(gl.mean(-1)) / 255), 3) if len(gl) > 50 else .1)


def _hls(c):
    return colorsys.rgb_to_hls(*[max(0, min(255, v)) / 255 for v in c])


def _kmeans(px, k=5, it=10, seed=3):
    rnd = np.random.default_rng(seed)
    if len(px) > 30000:
        px = px[rnd.choice(len(px), 30000, replace=False)]
    c = px[rnd.choice(len(px), k, replace=False)].astype(np.float32)
    for _ in range(it):
        a = ((px[:, None, :] - c[None]) ** 2).sum(-1).argmin(1)
        for j in range(k):
            if (a == j).any():
                c[j] = px[a == j].mean(0)
    return c, np.bincount(a, minlength=k) / len(px)


def parse(name, max_faces=3):
    bi, b = K.building_named(name)
    fs = faces.rectified_faces(name, max_faces, ppm=9.0, max_px=520)
    res = []
    for ln, i, im, pid, h, ppm in fs:
        try:
            r = parse_face(im, ppm, h)
        except Exception as e:
            r = None
        if r:
            r.update(face=i, length=round(ln, 1), pano=pid)
            res.append(r)
    if not res:
        return None
    good = [r for r in res if r['bay_conf'] >= .25] or res
    best = max(good, key=lambda r: r['bay_conf'] * r['length'] ** .5)
    best['faces_read'] = len(res)
    return best


def main():
    a = sys.argv[1:]
    db = json.load(open(OUT, encoding='utf-8')) if os.path.exists(OUT) else {}
    names = []
    if '--all' in a:
        for f in os.listdir(os.path.join(K.LM, 'sheets')):
            if f.endswith('.json'):
                names.append(json.load(open(os.path.join(K.LM, 'sheets', f), encoding='utf-8')).get('name'))
    else:
        names = [x for x in a if not x.startswith('--')]
    if not names:
        raise SystemExit(__doc__)
    for n in names:
        r = parse(n)
        if r:
            db[n] = r
            print('%-36s bay %.1f m (conf %.2f)  floor %.1f m%s  window %s  glass %d%%  glass #%s wall #%s' % (n, r['bay_w'], r['bay_conf'], r['floor_h'], ' STRIP' if r['strip'] else '', r['win'], r['glass_share'] * 100, r['glass'], r['wall']))
        else:
            print('%-36s nothing readable' % n)
    json.dump(db, open(OUT, 'w', encoding='utf-8'), indent=1)


if __name__ == '__main__':
    main()
