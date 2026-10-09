#!/usr/bin/env python3
"""
Bakes the lighting of the Spatial Distribution City view ahead of time, so the map pays nothing for it while it moves.

The classic game trick: do the expensive part once and keep the result in a texture or in the data. With plain,
untextured buildings there is nothing else to light, so all the shading is worked out here, from a height map of the
barangay (every building at its height, every tree at its crown height, on a 1.5 m grid):

  1. shadows.png    the ground picture. Two things in one alpha channel:
                    * cast shadows, by marching from every ground point towards the sun through the height map, with a
                      penumbra that widens with the distance to the thing casting it (soft shadow, as in a game's baked
                      lightmap): a wall's shadow is crisp where it starts and soft at its tip;
                    * ambient occlusion: horizon-based, from how much of the sky each point can see (16 directions, out to
                      40 m), so the foot of a wall, a narrow lane and a courtyard darken, an open plaza does not.
  2. two tones      written into every building in buildings.json: field 10 for its walls (how shut in the street at its foot
                    is, and how much of it a neighbour's shadow covers, set against the rest of the barangay), field 11 for its roof (how much sky the roof sees,
                    and whether a taller neighbour shades it). The map multiplies the plain colour by the tone.
  3. fog-day.png / fog-night.png    the fog of war: nothing is drawn outside the barangay, and the ground beyond its edge
                    fades into haze (day) or dark (night) over about 300 m, a soft vignette on a tilted map.

Trees are in the height map, so they shade the ground and the roofs near them as buildings do. Only what is inside the
boundary is baked (boundary.py).

The sun is at azimuth 200 degrees (south-south-west) and 42 degrees up (tan 0.9, a little steeper than a true low sun,
so shadows stay short and the map stays readable); sd-city.js lights the walls from the same side.

Run after build_buildings.py and build_city_detail.py.
Needs:  pip install numpy pillow scipy      Run:  python docs/map-data/bake_shadows.py
Other values can be tried with BAKE_AZ, BAKE_TAN (tangent of the sun's height), BAKE_SOFT (penumbra, 0.1 hard to 0.6 soft),
BAKE_SHALPHA (shadow strength), BAKE_AO (occlusion strength), BAKE_SUFFIX (writes shadows<suffix>.png and nothing else).
"""
import json, math, os, sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw
from scipy.ndimage import distance_transform_edt, gaussian_filter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from boundary import Boundary

MAP = os.path.normpath(os.path.join(HERE, '..', '..', 'admin', 'assets', 'map'))
AZ = float(os.environ.get('BAKE_AZ', 200))          # the sun, degrees clockwise from north
TAN = float(os.environ.get('BAKE_TAN', .9))         # tangent of the sun's height above the horizon
SOFT = float(os.environ.get('BAKE_SOFT', .32))      # how fast the penumbra widens with distance
SHALPHA = float(os.environ.get('BAKE_SHALPHA', .7))
AOK = float(os.environ.get('BAKE_AO', 1.0))
SUFFIX = os.environ.get('BAKE_SUFFIX', '')
PX = 1.5                                            # ground picture, metres per pixel
FOG_PX = 5.0                                        # fog picture, metres per pixel
FOG_RANGE = 300.0                                   # metres over which the ground beyond the boundary fades out
AO_DISTS = [1, 2, 3, 4, 6, 8, 11, 15, 20, 27]       # pixels: out to 40 m
SHADOW_REACH = 44                                   # pixels: 66 m, the longest shadow of the tallest building
MAP_AREA = (121.0027, 14.5146, 121.0284, 14.5392)   # west, south, east, north: what the page lets you pan to (spatial.php: AREA)
LAT0 = math.radians(14.525)
MX, MY = 111320 * math.cos(LAT0), 110574


def raster(rings, w, s, e, n, px):
    """The boundary as a mask (1 inside) on a grid of px metres per pixel."""
    W, H = int(math.ceil((e - w) * MX / px)), int(math.ceil((n - s) * MY / px))
    mask = Image.new('1', (W, H), 0)
    for r in rings:   # even-odd across rings: draw each ring and flip
        layer = Image.new('1', (W, H), 0)
        ImageDraw.Draw(layer).polygon([((x - w) * MX / px, (n - y) * MY / px) for x, y in r], fill=1)
        mask = ImageChops.logical_xor(mask, layer)
    return np.asarray(mask.convert('L'), dtype=np.float32) / 255, W, H


class Field:
    """The height map, and the two things worked out from it: soft shadows and ambient occlusion."""
    def __init__(self, hmap, pad):
        self.h = hmap
        self.H, self.W = hmap.shape
        self.pad = pad
        self.p = np.pad(hmap, pad)

    def shift(self, dx, dy):
        return self.p[self.pad + dy:self.pad + dy + self.H, self.pad + dx:self.pad + dx + self.W]

    def shadow(self, base, ex, ey):
        """1 where the sun is hidden, 0 where it shines, soft at the edges; base is the height each point is lit from."""
        vis = np.ones((self.H, self.W), dtype=np.float32)
        for d in range(1, SHADOW_REACH + 1):
            hs = self.shift(int(round(d * ex)), int(round(d * ey)))
            margin = base + d * PX * TAN - hs
            vis = np.minimum(vis, np.clip(.5 + margin / (SOFT * d * PX), 0, 1))
        return 1 - vis

    def occlusion(self, base, dirs=16):
        """0 for a point that sees the whole sky, towards 1 as more of it is hidden (horizon-based, cosine weighted)."""
        occ = np.zeros((self.H, self.W), dtype=np.float32)
        for k in range(dirs):
            a = 2 * math.pi * k / dirs
            ex, ey = math.cos(a), math.sin(a)
            mt = np.zeros((self.H, self.W), dtype=np.float32)
            for d in AO_DISTS:
                hs = self.shift(int(round(d * ex)), int(round(d * ey)))
                mt = np.maximum(mt, (hs - base) / (d * PX))
            occ += mt / np.sqrt(1 + mt * mt)
        return occ / dirs


def main():
    B = Boundary()
    bw, bs, be, bn = B.bbox
    # the ground picture: the boundary's box, limited to what the page can show, with a little over
    pad = .0004
    w, s, e, n = max(bw, MAP_AREA[0]) - pad, max(bs, MAP_AREA[1]) - pad, min(be, MAP_AREA[2]) + pad, min(bn, MAP_AREA[3]) + pad
    inside, W, H = raster(B.rings, w, s, e, n, PX)
    print('ground picture: %d x %d px at %.1f m/px' % (W, H, PX))
    bpath = os.path.join(MAP, 'buildings.json')
    bdoc = json.load(open(bpath, encoding='utf-8'))
    bld = bdoc['b']
    det = json.load(open(os.path.join(MAP, 'city-detail.json'), encoding='utf-8'))
    to_px = lambda lng, lat: ((lng - w) * MX / PX, (n - lat) * MY / PX)
    az = math.radians(AZ)
    ex, ey = math.sin(az), -math.cos(az)             # towards the sun, in picture pixels (x east, y down)

    # ---- the height map: trees first, then buildings from the lowest up, so the tallest wins ----
    hm = Image.new('F', (W, H), 0.0)
    hd = ImageDraw.Draw(hm)
    for lng, lat, r, h, v, shape, real in det['trees']:
        x, y = to_px(lng, lat)
        rr = (1.3 if shape == 2 else r * .9) / PX
        hd.ellipse([x - rr, y - rr, x + rr, y + rr], fill=float(h) * (.95 if shape == 2 else .85))
    for b in sorted(bld, key=lambda b: b[1]):
        pts = [to_px(b[0][i], b[0][i + 1]) for i in range(0, len(b[0]), 2)]
        hd.polygon(pts, fill=float(b[1]))
    hmap = np.asarray(hm, dtype=np.float32)
    fld = Field(hmap, SHADOW_REACH + 2)
    foot = hmap >= 2.5
    print('height map: tallest %.0f m' % hmap.max())

    # ---- the ground picture ----
    sh = fld.shadow(0.0, ex, ey)
    ao = fld.occlusion(0.0)
    ao_a = np.clip((ao ** 1.15) * 1.25 * AOK, 0, 1) * (~foot)
    sh_s = gaussian_filter(sh, .6)
    ao_a = gaussian_filter(ao_a.astype(np.float32), .8)
    soft = gaussian_filter(inside, 2.0)             # nothing outside the boundary, with a soft edge
    alpha = np.clip(np.maximum(sh_s * SHALPHA, ao_a * .55), 0, 1) * soft
    img = np.zeros((H, W, 4), dtype=np.uint8)
    img[..., 0], img[..., 1], img[..., 2] = 12, 14, 34
    img[..., 3] = (alpha * 255).astype(np.uint8)
    out = os.path.join(MAP, 'shadows%s.png' % SUFFIX)
    Image.fromarray(img, 'RGBA').save(out, optimize=True)
    print('wrote', os.path.basename(out), os.path.getsize(out) // 1024, 'KB')
    if SUFFIX:
        return

    # ---- two tones for every building: its walls, and its roof ----
    px_ = lambda lng, lat: (int(round((lng - w) * MX / PX)), int(round((n - lat) * MY / PX)))
    dirs = [(math.cos(2 * math.pi * k / 16), math.sin(2 * math.pi * k / 16)) for k in range(16)]
    at = lambda arr, x, y: float(arr[min(H - 1, max(0, y)), min(W - 1, max(0, x))])
    wt, rt = [], []
    for b in bld:
        hb = float(b[1])
        cx, cy = px_(b[4], b[5])
        # the roof: how much sky it sees (taller things round it), and whether a taller neighbour shades it
        occ = 0.0
        for dx, dy in dirs:
            mt = 0.0
            for d in AO_DISTS:
                x, y = cx + int(round(d * dx)), cy + int(round(d * dy))
                if 0 <= x < W and 0 <= y < H:
                    mt = max(mt, (float(hmap[y, x]) - hb) / (d * PX))
            occ += mt / math.sqrt(1 + mt * mt)
        occ /= len(dirs)
        vis = 1.0
        for d in range(1, SHADOW_REACH + 1):
            x, y = cx + int(round(d * ex)), cy + int(round(d * ey))
            if 0 <= x < W and 0 <= y < H:
                vis = min(vis, max(0.0, min(1.0, .5 + (hb + d * PX * TAN - float(hmap[y, x])) / (SOFT * d * PX))))
        roof = max(.72, min(1.0, 1 - .30 * occ - .30 * (1 - vis)))
        # the walls: how shut in the ground at their foot is, and how much of it a neighbour shades; sampled 3 m outside the footprint
        ring = b[0]
        n_pts = len(ring) // 2
        a_sum = s_sum = cnt = 0
        step = max(1, n_pts // 8)
        ccx, ccy = b[4] * MX, b[5] * MY
        for i in range(0, n_pts, step):
            vx, vy = ring[2 * i] * MX - ccx, ring[2 * i + 1] * MY - ccy
            ln = math.hypot(vx, vy) or 1.0
            x, y = px_((ring[2 * i] * MX + vx / ln * 3.0) / MX, (ring[2 * i + 1] * MY + vy / ln * 3.0) / MY)
            a_sum += at(ao, x, y)
            s_sum += at(sh, x, y)
            cnt += 1
        wt.append(1 - .55 * (a_sum / max(cnt, 1)) - .22 * (s_sum / max(cnt, 1)))   # raw: scaled below against the rest of the barangay
        rt.append(round(roof, 2))
    # Nearly every street here is shut in, so the raw wall numbers all come out dark; what matters is which walls are darker than
    # the rest, so they are stretched over 0.74 to 1 between the 5th and the 95th percentile.
    lo, hi = np.percentile(wt, 5), np.percentile(wt, 95)
    wt = [round(float(.74 + .26 * min(1.0, max(0.0, (v - lo) / max(hi - lo, 1e-6)))), 2) for v in wt]
    for b, a, c in zip(bld, wt, rt):
        while len(b) < 12:
            b.append(1.0)
        b[10], b[11] = a, c
    bdoc['fields'] = '[ring (lng,lat flat), height m, roof 0 flat 1 gable 2 hip, roof colour index, centre lng, centre lat, long side m, short side m, angle rad, height estimated, baked wall tone 0.74 to 1, baked roof tone 0.72 to 1]'
    json.dump(bdoc, open(bpath, 'w', encoding='utf-8'), separators=(',', ':'))
    print('tones: walls %.2f to %.2f (mean %.2f), roofs %.2f to %.2f (mean %.2f)' % (min(wt), max(wt), sum(wt) / len(wt), min(rt), max(rt), sum(rt) / len(rt)))

    # ---- the fog of war: nothing outside the boundary, and its edge fades out ----
    m = 300.0
    fw, fs, fe, fn = min(bw, MAP_AREA[0]) - m / MX, min(bs, MAP_AREA[1]) - m / MY, max(be, MAP_AREA[2]) + m / MX, max(bn, MAP_AREA[3]) + m / MY
    fin, FW, FH = raster(B.rings, fw, fs, fe, fn, FOG_PX)
    dist = distance_transform_edt(fin < .5) * FOG_PX            # metres from the boundary, outside it
    t = np.clip(dist / FOG_RANGE, 0, 1)
    fa = t * t * (3 - 2 * t)
    for name, rgb, top in (('night', (14, 18, 38), .93), ('day', (238, 242, 248), .88)):
        im = np.zeros((FH, FW, 4), dtype=np.uint8)
        im[..., 0], im[..., 1], im[..., 2] = rgb
        im[..., 3] = (fa * top * 255).astype(np.uint8)
        fo = os.path.join(MAP, 'fog-%s.png' % name)
        Image.fromarray(im, 'RGBA').save(fo, optimize=True)
        print('wrote', os.path.basename(fo), os.path.getsize(fo) // 1024, 'KB', '(%d x %d px)' % (FW, FH))
    json.dump({'bounds': [w, s, e, n], 'metresPerPixel': PX, 'sunAzimuth': AZ,
               'fog': {'bounds': [fw, fs, fe, fn], 'night': 'fog-night.png', 'day': 'fog-day.png', 'alpha': {'night': .93, 'day': .88}},
               'about': 'Baked by docs/map-data/bake_shadows.py'}, open(os.path.join(MAP, 'shadows.json'), 'w'), separators=(',', ':'))


main()
