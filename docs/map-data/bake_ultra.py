#!/usr/bin/env python3
"""
The "ultra" bake: ray-traced lighting for the day map, worked out ahead of time.

bake_shadows.py lights the barangay from a height map with soft shadows and horizon-based ambient occlusion. This goes
one step further, the step a game's offline lightmapper takes: it gathers light the way a path tracer does, from a
height map of the barangay, for every point of the ground, on a 1 m grid:

  * 96 rays, cosine-weighted over the hemisphere, are marched from each ground point. A ray that escapes sees the sky
    (a blue-white dome); a ray that hits a roof or a wall brings back that surface's own colour, lit or not. That is one
    bounce of global illumination: a pastel house throws a little of its colour onto the lane beside it, a white roof
    lifts the light under its eaves, and a narrow lane is dark because most of its rays hit something.
  * the sun is a disc, not a point: 24 rays jittered over its width, so a shadow is sharp where it starts and soft at its tip.
  * the result is compared with an open field under the same sky and sun, and written as an overlay on the ground
    (shadows-ultra.png): black where the ground is darker than open ground, tinted where the colour that comes back from
    its surroundings differs. The map lays it where it laid shadows.png, and sd-city.js reads the same picture to light every
    wall face (which faces the sun, and how dark the ground at its foot is).

Day only. The night is lit from its lamps and windows (glow.png), not from a sky.

Needs:  pip install numpy pillow scipy      Run:  python docs/map-data/bake_ultra.py      (about a minute)
"""
import json, math, os, sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw
from scipy.ndimage import gaussian_filter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from boundary import Boundary

MAP = os.path.normpath(os.path.join(HERE, '..', '..', 'admin', 'assets', 'map'))
PX = 1.0                                             # metres per pixel
AZ, TAN = 200.0, .9                                  # the sun: as bake_shadows.py
SUN_RADIUS = .12                                     # the sun's disc, as a share of its direction (the penumbra)
RAYS, SUN_RAYS = 96, 24
DISTS = [1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 18, 22, 27, 33, 40, 48, 58, 70]   # pixels
SKY = np.array([.52, .68, 1.0], np.float32)          # the sky's colour, as a light
SUN = np.array([1.0, .95, .86], np.float32)
GROUND = np.array([244, 242, 238], np.float32)       # the day map's ground, to work out what overlay gives a ratio
MAP_AREA = (121.0027, 14.5146, 121.0284, 14.5392)
LAT0 = math.radians(14.525)
MX, MY = 111320 * math.cos(LAT0), 110574
WALLS = [(243, 205, 184), (248, 226, 160), (190, 226, 203), (184, 214, 242), (211, 194, 240), (241, 236, 228), (235, 197, 144), (208, 208, 214)]


def mask_of(rings, w, s, e, n):
    W, H = int(math.ceil((e - w) * MX / PX)), int(math.ceil((n - s) * MY / PX))
    m = Image.new('1', (W, H), 0)
    for r in rings:
        layer = Image.new('1', (W, H), 0)
        ImageDraw.Draw(layer).polygon([((x - w) * MX / PX, (n - y) * MY / PX) for x, y in r], fill=1)
        m = ImageChops.logical_xor(m, layer)
    return np.asarray(m.convert('L'), dtype=np.float32) / 255, W, H


def main():
    B = Boundary()
    bw, bs, be, bn = B.bbox
    pad = .0004
    w, s, e, n = max(bw, MAP_AREA[0]) - pad, max(bs, MAP_AREA[1]) - pad, min(be, MAP_AREA[2]) + pad, min(bn, MAP_AREA[3]) + pad
    inside, W, H = mask_of(B.rings, w, s, e, n)
    print('ground: %d x %d px at %.1f m/px' % (W, H, PX))
    bld = json.load(open(os.path.join(MAP, 'buildings.json'), encoding='utf-8'))['b']
    det = json.load(open(os.path.join(MAP, 'city-detail.json'), encoding='utf-8'))
    to_px = lambda lng, lat: ((lng - w) * MX / PX, (n - lat) * MY / PX)

    # ---- the height map, and what colour each thing is (walls from the side, roofs and crowns from above) ----
    hm = Image.new('F', (W, H), 0.0)
    wall = Image.new('RGB', (W, H), (150, 160, 150))
    roof = Image.new('RGB', (W, H), (60, 120, 70))                # a crown seen from above
    hd, wd, rd = ImageDraw.Draw(hm), ImageDraw.Draw(wall), ImageDraw.Draw(roof)
    for lng, lat, r, h, v, shape, real in det['trees']:
        x, y = to_px(lng, lat)
        rr = (1.3 if shape == 2 else r * .9) / PX
        hd.ellipse([x - rr, y - rr, x + rr, y + rr], fill=float(h) * (.95 if shape == 2 else .85))
    for b in sorted(bld, key=lambda b: b[1]):
        pts = [to_px(b[0][i], b[0][i + 1]) for i in range(0, len(b[0]), 2)]
        hd.polygon(pts, fill=float(b[1]))
        hh = float(b[1])
        wd.polygon(pts, fill=WALLS[min(7, int(((math.sin(b[4] * 1e3 * 12.9898 + b[5] * 1e3 * 78.233) * 43758.5453) % 1) * 8))] if hh < 9 else (230, 228, 226))
        rd.polygon(pts, fill=(246, 244, 240))
    hmap = np.asarray(hm, dtype=np.float32)
    wallc = np.asarray(wall, dtype=np.float32) / 255
    roofc = np.asarray(roof, dtype=np.float32) / 255
    PADN = max(DISTS) + 2
    hp = np.pad(hmap, PADN)
    wp = np.pad(wallc, ((PADN, PADN), (PADN, PADN), (0, 0)))
    rp = np.pad(roofc, ((PADN, PADN), (PADN, PADN), (0, 0)))
    sl = lambda arr, dx, dy: arr[PADN + dy:PADN + dy + H, PADN + dx:PADN + dx + W]
    print('height map: tallest %.0f m' % hmap.max())

    # ---- the sky and what comes back from the surroundings: RAYS cosine-weighted rays from every ground point ----
    golden = math.pi * (3 - math.sqrt(5))
    acc = np.zeros((H, W, 3), np.float32)
    for i in range(RAYS):
        u = (i + .5) / RAYS
        sin_e = math.sqrt(1 - u)                       # cosine-weighted: more rays near the zenith
        tan_e = sin_e / max(math.sqrt(1 - sin_e * sin_e), 1e-3)
        a = golden * i
        ex, ey = math.cos(a), math.sin(a)
        hit = np.zeros((H, W), bool)
        col = np.zeros((H, W, 3), np.float32)
        for d in DISTS:
            dx, dy = int(round(d * ex)), int(round(d * ey))
            hs = sl(hp, dx, dy)
            blocked = (~hit) & (hs > d * PX * tan_e)
            if blocked.any():
                side = hs > d * PX * tan_e + .8        # entered from the side: a wall; just clipped: a roof
                c = np.where(side[..., None], sl(wp, dx, dy), sl(rp, dx, dy))
                col += blocked[..., None] * c * .62     # what is bounced: the surface's colour, not fully lit
                hit |= blocked
        acc += np.where(hit[..., None], col, SKY[None, None, :])
        if i % 16 == 15:
            print('  rays %d / %d' % (i + 1, RAYS))
    irr = acc / RAYS

    # ---- the sun, a disc: SUN_RAYS rays jittered over its width ----
    sun_vis = np.zeros((H, W), np.float32)
    az0 = math.radians(AZ)
    for j in range(SUN_RAYS):
        ang = az0 + (((j * .618) % 1) - .5) * SUN_RADIUS * 2
        tn = TAN * (1 + ((((j * .382) % 1) - .5) * SUN_RADIUS * 2))
        sx, sy = math.sin(ang), -math.cos(ang)
        vis = np.ones((H, W), bool)
        for d in range(1, 71):
            vis &= sl(hp, int(round(d * sx)), int(round(d * sy))) <= d * PX * tn
        sun_vis += vis
    sun_vis /= SUN_RAYS
    sun_cos = TAN / math.sqrt(1 + TAN * TAN)

    E = irr * .75 + SUN[None, None, :] * (sun_vis[..., None] * sun_cos * 1.05)
    E0 = SKY * .75 + SUN * sun_cos * 1.05              # an open field under the same sky and sun
    r = np.clip(E / E0[None, None, :], 0, 1)
    a = np.clip(1 - r.min(axis=2), 0, .86)
    tint = GROUND[None, None, :] * (r - r.min(axis=2, keepdims=True)) / np.maximum(a[..., None], 1e-3)
    foot = hmap >= 2.5
    soft = gaussian_filter(inside, 2.0)
    a = gaussian_filter(a, .6) * (~foot) * soft
    img = np.zeros((H, W, 4), np.uint8)
    img[..., :3] = (np.clip(tint, 0, 255) // 4 * 4).astype(np.uint8)
    img[..., 3] = ((a * 255).astype(np.uint8) // 4) * 4
    out = os.path.join(MAP, 'shadows-ultra.png')
    Image.fromarray(img, 'RGBA').save(out, optimize=True)
    print('wrote', os.path.basename(out), os.path.getsize(out) // 1024, 'KB; ground darker than open ground by %.0f%% on average' % (100 * float(a[inside > .5].mean())))
    sp = os.path.join(MAP, 'shadows.json')   # tell the map about it
    meta = json.load(open(sp)) if os.path.exists(sp) else {}
    meta['ultra'] = 'shadows-ultra.png'
    json.dump(meta, open(sp, 'w'), separators=(',', ':'))


main()
