#!/usr/bin/env python3
"""
Bakes the shadows of the Spatial Distribution City view into one picture of the ground.

The classic game trick: do the expensive lighting once, ahead of time, and paint the result on the ground as a
texture, so the map pays nothing for it while it moves. This takes every building in admin/assets/map/buildings.json
and every tree in city-detail.json and works out
  * the shadow each casts on the ground, thrown away from the sun, fading towards its tip;
  * ambient occlusion: the darkening at the foot of a wall and down a narrow lane, where less sky is seen;
and writes admin/assets/map/shadows.png (black with an alpha channel) and shadows.json (where it goes).
The City view lays it on the ground under the buildings; the same picture serves day and night, only its
opacity changes.

The sun is at azimuth 200 degrees (south-south-west), so shadows fall north-north-east; sd-city.js lights the
walls from the same side.

Needs:  pip install numpy pillow scipy      Run:  python docs/map-data/bake_shadows.py
"""
import json, math, os

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter

HERE = os.path.dirname(os.path.abspath(__file__))
MAP = os.path.normpath(os.path.join(HERE, '..', '..', 'admin', 'assets', 'map'))
BBOX = (121.0007, 14.5126, 121.0304, 14.5412)   # west, south, east, north (as build_buildings.py)
PX = 1.5                                        # metres per pixel
AZ = 200.0                                      # the sun, degrees clockwise from north
LEN = 0.75                                      # shadow length as a share of the height (a low-slung afternoon sun, softened)
LAT0 = math.radians((BBOX[1] + BBOX[3]) / 2)
MX, MY = 111320 * math.cos(LAT0), 110574


def main():
    w, s, e, n = BBOX
    W, H = int(math.ceil((e - w) * MX / PX)), int(math.ceil((n - s) * MY / PX))
    print('ground picture: %d x %d px at %.1f m/px' % (W, H, PX))
    bld = json.load(open(os.path.join(MAP, 'buildings.json'), encoding='utf-8'))['b']
    det = json.load(open(os.path.join(MAP, 'city-detail.json'), encoding='utf-8'))
    az = math.radians(AZ + 180)                  # the way a shadow points
    ex, ny = math.sin(az), math.cos(az)          # east, north
    to_px = lambda lng, lat: ((lng - w) * MX / PX, (n - lat) * MY / PX)

    foot = Image.new('L', (W, H), 0)
    fd = ImageDraw.Draw(foot)
    draws = []   # (t, polygon, value): far end first, so the dark near end paints over the pale far end
    for ring, h, rt, ci, cx, cy, L, Wd, th, est in bld:
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
    # trees: an oval of shadow thrown from each crown
    tr = Image.new('L', (W, H), 0)
    td = ImageDraw.Draw(tr)
    for lng, lat, r, h, v, shape, real in det['trees']:
        x, y = to_px(lng, lat)
        rr = (1.4 if shape == 2 else r * .95) / PX
        cxp, cyp = x + ex * h * .42 / PX, y - ny * h * .42 / PX
        td.ellipse([cxp - rr, cyp - rr, cxp + rr, cyp + rr], fill=210)

    f = np.asarray(foot, dtype=np.float32) / 255
    shadow = gaussian_filter(np.asarray(sh, dtype=np.float32) / 255, 0.9)
    trees = gaussian_filter(np.asarray(tr, dtype=np.float32) / 255, 0.8)
    near = gaussian_filter(f, 2.0 / 1.0)            # about 3 m: the dark line at the foot of a wall
    wide = gaussian_filter(f, 7.0)                  # about 10 m: lanes and courtyards, where less sky is seen
    ao = np.clip(near * .5 + wide * .42, 0, 1) * (1 - np.clip(f, 0, 1))
    alpha = np.clip(np.maximum.reduce([shadow * .62, trees * .36, ao * .5]), 0, 1)
    img = np.zeros((H, W, 4), dtype=np.uint8)
    img[..., 0], img[..., 1], img[..., 2] = 12, 14, 34
    img[..., 3] = (alpha * 255).astype(np.uint8)
    out = os.path.join(MAP, 'shadows.png')
    Image.fromarray(img, 'RGBA').save(out, optimize=True)
    json.dump({'bounds': [w, s, e, n], 'metresPerPixel': PX, 'sunAzimuth': AZ, 'about': 'Baked by docs/map-data/bake_shadows.py'}, open(os.path.join(MAP, 'shadows.json'), 'w'), separators=(',', ':'))
    print('wrote', out, os.path.getsize(out) // 1024, 'KB')


main()
