#!/usr/bin/env python3
"""
Bakes the lighting of the Spatial Distribution City view ahead of time, so the map pays nothing for it while it moves.

The classic game trick: do the expensive part once and keep the result in a texture or in the data. With plain,
untextured buildings there is nothing else to light, so three things are baked here:

  1. shadows.png    the ground picture: the shadow each building and tree throws (away from the sun, fading towards
                    its tip) and ambient occlusion (the dark at the foot of a wall and down a narrow lane). Black with
                    an alpha channel, so the same picture serves day and night.
  2. a tone         for every building, written into buildings.json (field 10): 1.0 in the open, down to about 0.62 for
                    a house in a crowded block with a taller one on the sun side. The map multiplies the building's plain
                    colour by it, which is what lets plain colours still look shaded.
  3. fog-day.png / fog-night.png    the fog of war: nothing is drawn outside the barangay, and the ground beyond its edge
                    fades into haze (day) or dark (night) over about 300 m, so a tilted map has a soft vignette instead of
                    a hard edge. Only what is inside the boundary has shadows (boundary.py).

The sun is at azimuth 200 degrees (south-south-west), so shadows fall north-north-east; sd-city.js lights the walls from
the same side. The files shadows.json says where each picture goes.

Run after build_buildings.py and build_city_detail.py.
Needs:  pip install numpy pillow scipy      Run:  python docs/map-data/bake_shadows.py
"""
import json, math, os, sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw
from scipy.ndimage import distance_transform_edt, gaussian_filter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from boundary import Boundary

MAP = os.path.normpath(os.path.join(HERE, '..', '..', 'admin', 'assets', 'map'))
# The look can be tried with other values: BAKE_AZ (sun azimuth), BAKE_LEN (shadow length per height), BAKE_SIGMA (shadow softness in pixels),
# BAKE_SHALPHA (shadow strength), BAKE_AO (ambient occlusion strength), BAKE_SUFFIX (writes shadows<suffix>.png and nothing else),
# BAKE_TONE=0 and BAKE_FOG=0 (leave the building tones and the fog alone).
AZ = float(os.environ.get('BAKE_AZ', 200))     # the sun, degrees clockwise from north
LEN = float(os.environ.get('BAKE_LEN', .75))   # shadow length as a share of the height (a low-slung afternoon sun, softened)
SIGMA = float(os.environ.get('BAKE_SIGMA', .9))
SHALPHA = float(os.environ.get('BAKE_SHALPHA', .62))
AOK = float(os.environ.get('BAKE_AO', 1))
SUFFIX = os.environ.get('BAKE_SUFFIX', '')
WRITE_TONE = os.environ.get('BAKE_TONE', '1') != '0' and not SUFFIX
WRITE_FOG = os.environ.get('BAKE_FOG', '1') != '0' and not SUFFIX
PX = 1.5                                        # ground picture, metres per pixel
FOG_PX = 5.0                                    # fog picture, metres per pixel
FOG_RANGE = 300.0                               # metres over which the ground beyond the boundary fades out
MAP_AREA = (121.0027, 14.5146, 121.0284, 14.5392)   # west, south, east, north: what the page lets you pan to (spatial.php: AREA)
LAT0 = math.radians(14.525)
MX, MY = 111320 * math.cos(LAT0), 110574


def raster(rings, w, s, e, n, px):
    """The boundary as a mask (255 inside) on a grid of px metres per pixel."""
    W, H = int(math.ceil((e - w) * MX / px)), int(math.ceil((n - s) * MY / px))
    mask = Image.new('L', (W, H), 0)
    for r in rings:   # even-odd across rings: draw each ring and flip
        layer = Image.new('L', (W, H), 0)
        ImageDraw.Draw(layer).polygon([((x - w) * MX / px, (n - y) * MY / px) for x, y in r], fill=255)
        mask = ImageChops.logical_xor(mask.convert('1'), layer.convert('1')).convert('L')
    return np.asarray(mask, dtype=np.float32) / 255, W, H


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
    az = math.radians(AZ + 180)                  # the way a shadow points
    ex, ny = math.sin(az), math.cos(az)          # east, north
    to_px = lambda lng, lat: ((lng - w) * MX / PX, (n - lat) * MY / PX)

    foot = Image.new('L', (W, H), 0)
    fd = ImageDraw.Draw(foot)
    draws = []   # (t, polygon, value): far end first, so the dark near end paints over the pale far end
    for b in bld:
        ring, h = b[0], b[1]
        pts = [to_px(ring[i], ring[i + 1]) for i in range(0, len(ring), 2)]
        fd.polygon(pts, fill=255)
        length = min(60.0, h * LEN) / PX
        steps = max(2, min(24, int(math.ceil(length / 1.6))))
        for k in range(steps + 1):
            t = 1 - k / steps
            dx, dy = ex * length * t, -ny * length * t
            draws.append((t, [(x + dx, y + dy) for x, y in pts], int(255 * (1 - .45 * t))))
    draws.sort(key=lambda d: -d[0])
    sh = Image.new('L', (W, H), 0)
    sd = ImageDraw.Draw(sh)
    for t, poly, v in draws:
        sd.polygon(poly, fill=v)
    tr = Image.new('L', (W, H), 0)   # trees: an oval of shadow thrown from each crown
    td = ImageDraw.Draw(tr)
    for lng, lat, r, h, v, shape, real in det['trees']:
        x, y = to_px(lng, lat)
        rr = (1.4 if shape == 2 else r * .95) / PX
        cxp, cyp = x + ex * h * .42 / PX, y - ny * h * .42 / PX
        td.ellipse([cxp - rr, cyp - rr, cxp + rr, cyp + rr], fill=210)

    f = np.asarray(foot, dtype=np.float32) / 255
    shadow = gaussian_filter(np.asarray(sh, dtype=np.float32) / 255, SIGMA)
    trees = gaussian_filter(np.asarray(tr, dtype=np.float32) / 255, 0.8)
    near = gaussian_filter(f, 2.0)                  # about 3 m: the dark line at the foot of a wall
    wide = gaussian_filter(f, 7.0)                  # about 10 m: lanes and courtyards, where less sky is seen
    ao = np.clip(near * .5 + wide * .42, 0, 1) * (1 - np.clip(f, 0, 1))
    soft = gaussian_filter(inside, 2.0)             # nothing outside the boundary, with a soft edge
    alpha = np.clip(np.maximum.reduce([shadow * SHALPHA, trees * .36, np.clip(ao * AOK, 0, 1) * .5]), 0, 1) * soft
    img = np.zeros((H, W, 4), dtype=np.uint8)
    img[..., 0], img[..., 1], img[..., 2] = 12, 14, 34
    img[..., 3] = (alpha * 255).astype(np.uint8)
    out = os.path.join(MAP, 'shadows%s.png' % SUFFIX)
    Image.fromarray(img, 'RGBA').save(out, optimize=True)
    print('wrote', os.path.basename(out), os.path.getsize(out) // 1024, 'KB')
    if not WRITE_TONE and not WRITE_FOG:
        return

    if WRITE_TONE:
        # ---- a tone for every building: crowded, and in the shade of a taller neighbour on the sun side, is darker ----
        sx, sy = -ex, -ny                               # towards the sun
        cell = 60.0
        grid = {}
        for i, b in enumerate(bld):
            grid.setdefault((int(b[4] * MX // cell), int(b[5] * MY // cell)), []).append(i)
        tones = 0
        for i, b in enumerate(bld):
            hb, cxm, cym = b[1], b[4] * MX, b[5] * MY
            shade = 0.0
            for gx in range(int(cxm // cell) - 1, int(cxm // cell) + 2):
                for gy in range(int(cym // cell) - 1, int(cym // cell) + 2):
                    for j in grid.get((gx, gy), []):
                        if j == i:
                            continue
                        o = bld[j]
                        hn = o[1]
                        if hn <= hb + 1.5:
                            continue
                        dx, dy = o[4] * MX - cxm, o[5] * MY - cym
                        along = dx * sx + dy * sy       # how far towards the sun the neighbour stands
                        across = abs(dx * -sy + dy * sx)
                        reach = min(60.0, hn * LEN)
                        half = (o[7] + b[7]) / 2 + 2    # its width, ours and a little more
                        if along <= 0 or across > half + 3 or along - o[6] / 2 > reach:
                            continue
                        shade = max(shade, min(1.0, (1 - max(0.0, along - o[6] / 2) / reach)) * min(1.0, (hn - hb) / max(hn, 1)))
            px_, py_ = int((b[4] - w) * MX / PX), int((n - b[5]) * MY / PX)
            dens = float(wide[min(H - 1, max(0, py_)), min(W - 1, max(0, px_))])
            tone = max(.62, min(1.0, 1 - .36 * shade - .10 * min(1.0, dens * 1.6)))
            t = round(tone, 2)
            if len(b) > 10:
                b[10] = t
            else:
                b.append(t)
            tones += tone < .97
        bdoc['fields'] = bdoc['fields'].rstrip(']') + ', baked tone 0.62 to 1]' if 'baked tone' not in bdoc['fields'] else bdoc['fields']
        json.dump(bdoc, open(bpath, 'w', encoding='utf-8'), separators=(',', ':'))
        print('tone: %d of %d buildings shaded below 0.97' % (tones, len(bld)))

    if not WRITE_FOG:
        return
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
        out = os.path.join(MAP, 'fog-%s.png' % name)
        Image.fromarray(im, 'RGBA').save(out, optimize=True)
        print('wrote', os.path.basename(out), os.path.getsize(out) // 1024, 'KB', '(%d x %d px)' % (FW, FH))
    json.dump({'bounds': [w, s, e, n], 'metresPerPixel': PX, 'sunAzimuth': AZ,
               'fog': {'bounds': [fw, fs, fe, fn], 'night': 'fog-night.png', 'day': 'fog-day.png', 'alpha': {'night': .93, 'day': .88}},
               'about': 'Baked by docs/map-data/bake_shadows.py'}, open(os.path.join(MAP, 'shadows.json'), 'w'), separators=(',', ':'))


main()
