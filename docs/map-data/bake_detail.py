#!/usr/bin/env python3
"""
The detail bake: light for every wall face, and a ray-traced night ground.

bake_shadows.py gives each building one wall tone and one roof tone; this works out the light one wall face at a time,
from the same height map, the way a game's lightmapper bakes a lightmap for each face:

  faces.json   for every edge of every building footprint, two bands of the wall (the foot, up to 4.5 m, and the rest):
               * day: how much of the sun reaches it and how much of the sky it sees (soft shadow march towards the sun with a
                 penumbra that widens with distance, and horizon-based occlusion over the half of the sky the face looks at),
                 as a tone from 0.5 to 1 (a base-36 digit each, so the file stays small);
               * night: how much light the street lamps put on it (every lamp within 26 m, a line of sight through the height
                 map, falling off with distance), 0 to 1.
               The map builds a thin plate over each face and paints it with its own tone, so one house can be lit on its
               sunward side and dark under a taller neighbour's shadow, and a lamp warms the wall beside it.
  glow-rt.png  the night ground, ray traced: every lamp casts light on every ground point it can see (a line march through the
               height map for each), so the pool of light is stopped by buildings, bends round corners no further than the eye
               would, and falls off the way light does; plus the spill from lit windows. It replaces glow.png on the map.

Run after bake_shadows.py (it needs the lights-on amount that writes).
Needs:  pip install numpy pillow scipy      Run:  python docs/map-data/bake_detail.py      (about two minutes)
"""
import json, math, os, sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw
from scipy.ndimage import gaussian_filter
from scipy.spatial import cKDTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from boundary import Boundary

MAP = os.path.normpath(os.path.join(HERE, '..', '..', 'admin', 'assets', 'map'))
PX = 1.5
AZ, TAN, SOFT = 200.0, .9, .32
LAMP_H = 7.5
LAMP_REACH = 26.0
AO_DISTS = [1, 2, 3, 4, 6, 8, 11, 15, 20, 27]
SHADOW_REACH = 44
LOW_BAND = 4.5
MAP_AREA = (121.0027, 14.5146, 121.0284, 14.5392)
LAT0 = math.radians(14.525)
MX, MY = 111320 * math.cos(LAT0), 110574
B36 = '0123456789abcdefghijklmnopqrstuvwxyz'


def main():
    B = Boundary()
    bw, bs, be, bn = B.bbox
    pad = .0004
    w, s, e, n = max(bw, MAP_AREA[0]) - pad, max(bs, MAP_AREA[1]) - pad, min(be, MAP_AREA[2]) + pad, min(bn, MAP_AREA[3]) + pad
    W, H = int(math.ceil((e - w) * MX / PX)), int(math.ceil((n - s) * MY / PX))
    m = Image.new('1', (W, H), 0)
    for r in B.rings:
        layer = Image.new('1', (W, H), 0)
        ImageDraw.Draw(layer).polygon([((x - w) * MX / PX, (n - y) * MY / PX) for x, y in r], fill=1)
        m = ImageChops.logical_xor(m, layer)
    inside = np.asarray(m.convert('L'), dtype=np.float32) / 255
    soft = gaussian_filter(inside, 2.0)

    bdoc = json.load(open(os.path.join(MAP, 'buildings.json'), encoding='utf-8'))
    bld = bdoc['b']
    det = json.load(open(os.path.join(MAP, 'city-detail.json'), encoding='utf-8'))
    to_px = lambda lng, lat: ((lng - w) * MX / PX, (n - lat) * MY / PX)

    hm = Image.new('F', (W, H), 0.0)
    hd = ImageDraw.Draw(hm)
    for lng, lat, r, h, v, shape, real in det['trees']:
        x, y = to_px(lng, lat)
        rr = (1.3 if shape == 2 else r * .9) / PX
        hd.ellipse([x - rr, y - rr, x + rr, y + rr], fill=float(h) * (.95 if shape == 2 else .85))
    for b in sorted(bld, key=lambda b: b[1]):
        hd.polygon([to_px(b[0][i], b[0][i + 1]) for i in range(0, len(b[0]), 2)], fill=float(b[1]))
    hmap = np.asarray(hm, dtype=np.float32)
    PADN = 90
    hp = np.pad(hmap, PADN)
    print('height map %d x %d, tallest %.0f m' % (W, H, hmap.max()))

    def hat(xs, ys):                                   # the height map at pixel positions (float arrays), clamped to the picture
        xi = np.clip(np.round(xs).astype(int), -PADN, W + PADN - 1) + PADN
        yi = np.clip(np.round(ys).astype(int), -PADN, H + PADN - 1) + PADN
        return hp[yi, xi]

    # ---- every wall face: its middle, outward normal, and the building's height ----
    face_b, fx, fy, fnx, fny, fh = [], [], [], [], [], []
    spans = []
    for bi, b in enumerate(bld):
        ring = b[0]
        pts = [(ring[i] * MX, ring[i + 1] * MY) for i in range(0, len(ring), 2)]
        k = len(pts)
        area = sum(pts[i][0] * pts[(i + 1) % k][1] - pts[(i + 1) % k][0] * pts[i][1] for i in range(k)) / 2
        sgn = 1.0 if area > 0 else -1.0                 # counter-clockwise: the outside is on the right of an edge
        start = len(fx)
        for i in range(k):
            (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % k]
            dx, dy = x1 - x0, y1 - y0
            ln = math.hypot(dx, dy) or 1.0
            nx, ny = sgn * dy / ln, -sgn * dx / ln
            face_b.append(bi)
            fx.append((x0 + x1) / 2)
            fy.append((y0 + y1) / 2)
            fnx.append(nx)
            fny.append(ny)
            fh.append(float(b[1]))
        spans.append((start, len(fx)))
    fx, fy, fnx, fny, fh = (np.array(a, dtype=np.float64) for a in (fx, fy, fnx, fny, fh))
    NF = len(fx)
    print('faces: %d on %d buildings' % (NF, len(bld)))
    # picture position of a point 1.4 m out from each face, and the picture's y axis points south
    px_of = lambda off: (((fx + fnx * off) / MX - w) * MX / PX, (n - (fy + fny * off) / MY) * MY / PX)

    sun_e, sun_n = math.sin(math.radians(AZ)), math.cos(math.radians(AZ))
    facing = np.clip(fnx * sun_e + fny * sun_n, 0, 1)

    def band(z):
        """Day tone of a band of wall at height z: the sun and the sky, 0.5 to 1."""
        x0, y0 = px_of(1.4)
        vis = np.ones(NF)
        for d in range(2, SHADOW_REACH + 1):
            hs = hat(x0 + d * sun_e, y0 - d * sun_n)
            vis = np.minimum(vis, np.clip(.5 + (z + d * PX * TAN - hs) / (SOFT * d * PX), 0, 1))
        occ = np.zeros(NF)
        cnt = np.zeros(NF)
        for kk in range(16):
            a = 2 * math.pi * kk / 16
            ex, ey = math.cos(a), math.sin(a)                    # east, north
            out = (ex * fnx + ey * fny) > .05                    # only the half of the sky the face looks at
            mt = np.zeros(NF)
            for d in AO_DISTS:
                mt = np.maximum(mt, (hat(x0 + d * ex, y0 - d * ey) - z) / (d * PX))
            occ += np.where(out, mt / np.sqrt(1 + mt * mt), 0)
            cnt += out
        occ = occ / np.maximum(cnt, 1)
        return np.clip(1 - .5 * occ - .34 * (1 - vis) * facing, .5, 1)

    zlo = np.minimum(fh * .45, 1.6)
    zhi = np.maximum(np.minimum(fh * .85, LOW_BAND + 4), 1.0)
    day_lo, day_hi = band(zlo), band(zhi)
    print('day tones: foot %.2f to %.2f, upper %.2f to %.2f' % (day_lo.min(), day_lo.max(), day_hi.min(), day_hi.max()))

    # ---- the lamps ----
    lamps = det.get('lamps', [])
    lx = np.array([(l[0] - w) * MX / PX for l in lamps])
    ly = np.array([(n - l[1]) * MY / PX for l in lamps])
    lbr = np.array([l[2] for l in lamps])
    lwh = np.array([l[3] for l in lamps])

    # lamps on wall faces
    fpx, fpy = px_of(.6)
    tree = cKDTree(np.c_[fpx, fpy])
    warm_lo, warm_hi = np.zeros(NF), np.zeros(NF)
    steps = np.linspace(.05, .95, 14)
    for li in range(len(lamps)):
        idx = tree.query_ball_point([lx[li], ly[li]], LAMP_REACH / PX)
        if not idx:
            continue
        idx = np.array(idx)
        for z, acc in ((zlo[idx], warm_lo), (zhi[idx], warm_hi)):
            dx, dy = (lx[li] - fpx[idx]) * PX, -(ly[li] - fpy[idx]) * PX          # metres east, north towards the lamp
            dist = np.sqrt(dx * dx + dy * dy + (LAMP_H - z) ** 2)
            lam = np.clip((fnx[idx] * dx + fny[idx] * dy) / np.maximum(np.hypot(dx, dy), .01), 0, 1)
            ok = np.ones(len(idx), bool)
            for t in steps:
                hs = hat(fpx[idx] + (lx[li] - fpx[idx]) * t, fpy[idx] + (ly[li] - fpy[idx]) * t)
                ok &= hs < (z + (LAMP_H - z) * t) + .2
            acc[idx] += lbr[li] * ok * lam / (1 + (dist / 7.5) ** 2) * 1.7
    warm_lo, warm_hi = np.clip(warm_lo, 0, 1), np.clip(warm_hi * .8, 0, 1)
    print('night: %d of %d low faces lit by a lamp' % (int((warm_lo > .1).sum()), NF))

    # ---- write the faces file: per building, the day tones and the lamp light of each face, one base-36 digit each ----
    tone = lambda a: B36[int(round((float(a) - .5) / .5 * 35))]
    warm = lambda a: B36[int(round(float(a) * 35))]
    rows = []
    for (a, b2) in spans:
        rows.append([''.join(tone(x) for x in day_lo[a:b2]) + '|' + ''.join(tone(x) for x in day_hi[a:b2]),
                     ''.join(warm(x) for x in warm_lo[a:b2]) + '|' + ''.join(warm(x) for x in warm_hi[a:b2])])
    out = os.path.join(MAP, 'faces.json')
    json.dump({'about': 'Per wall face light, baked by docs/map-data/bake_detail.py. For each building, in the order of buildings.json: "foot|upper" day tones (digit 0-z = 0.5 to 1) and "foot|upper" lamp light (digit 0-z = 0 to 1), one digit per footprint edge; low band is the foot up to %.1f m' % LOW_BAND,
               'lowBand': LOW_BAND, 'f': rows}, open(out, 'w'), separators=(',', ':'))
    print('wrote faces.json', os.path.getsize(out) // 1024, 'KB')

    # ---- the night ground, ray traced ----
    foot = hmap >= 2.5
    warmA = np.zeros((H, W), np.float32)
    whiteA = np.zeros((H, W), np.float32)
    R = int(LAMP_REACH / PX) + 1
    gz = .3
    for li in range(len(lamps)):
        cx, cy = int(round(lx[li])), int(round(ly[li]))
        x0, x1, y0, y1 = max(0, cx - R), min(W, cx + R + 1), max(0, cy - R), min(H, cy + R + 1)
        if x1 <= x0 or y1 <= y0:
            continue
        gy, gx = np.mgrid[y0:y1, x0:x1]
        dx, dy = (cx - gx) * PX, (cy - gy) * PX
        dh = np.hypot(dx, dy)
        near = dh < LAMP_REACH
        ok = near.copy()
        for t in np.linspace(.04, .96, 18):
            hs = hat(gx + (cx - gx) * t, gy + (cy - gy) * t)
            ok &= hs < gz + (LAMP_H - gz) * t + .15
        dist3 = np.sqrt(dh * dh + (LAMP_H - gz) ** 2)
        lum = lbr[li] * ok * ((LAMP_H - gz) / dist3) / (1 + (dh / 6.5) ** 2) * 1.05
        (whiteA if lwh[li] else warmA)[y0:y1, x0:x1] += lum.astype(np.float32)
        if li % 500 == 499:
            print('  lamps %d / %d' % (li + 1, len(lamps)))
    litimg = Image.new('F', (W, H), 0.0)
    ld = ImageDraw.Draw(litimg)
    for b in bld:
        if len(b) > 12 and b[12] > .05:
            ld.polygon([to_px(b[0][i], b[0][i + 1]) for i in range(0, len(b[0]), 2)], fill=float(b[12]))
    a_win = np.clip(gaussian_filter(np.asarray(litimg, dtype=np.float32), 2.6) * 1.9, 0, 1) * (~foot) * .6
    a_warm = np.clip(gaussian_filter(warmA, .7), 0, .9) * (~foot)
    a_white = np.clip(gaussian_filter(whiteA, .7), 0, .9) * (~foot)
    warmc, whitec, winc = np.array([255, 178, 92], np.float32), np.array([214, 228, 255], np.float32), np.array([255, 196, 120], np.float32)
    tot = a_warm + a_white + a_win + 1e-6
    col = (a_warm[..., None] * warmc + a_white[..., None] * whitec + a_win[..., None] * winc) / tot[..., None]
    a_all = (1 - (1 - a_warm) * (1 - a_white) * (1 - a_win)) * soft
    img = np.zeros((H, W, 4), np.uint8)
    img[..., :3] = (np.clip(col, 0, 255).astype(np.uint8) // 8) * 8
    img[..., 3] = ((np.clip(a_all, 0, 1) * 255).astype(np.uint8) // 4) * 4
    go = os.path.join(MAP, 'glow-rt.png')
    Image.fromarray(img, 'RGBA').save(go, optimize=True)
    print('wrote glow-rt.png', os.path.getsize(go) // 1024, 'KB')
    sp = os.path.join(MAP, 'shadows.json')
    meta = json.load(open(sp))
    meta['glowRt'] = 'glow-rt.png'
    meta['faces'] = 'faces.json'
    json.dump(meta, open(sp, 'w'), separators=(',', ':'))


main()
