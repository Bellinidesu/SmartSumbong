#!/usr/bin/env python3
"""
The GPU bake: the City view's daylight, path traced on the graphics card.

bake_shadows.py and bake_detail.py light the barangay on the processor. This does the day lighting again, properly, on the
graphics card: a path tracer written as a shader (gpu/bake.html) runs in a headless browser on the card (Direct3D, through ANGLE),
over a 1 m height map of the barangay, for three kinds of probe:

  * every metre of ground: 1,024 cosine weighted rays each, two bounces of light (what the first round of ground light is bounced
    back by walls and roofs), a sun that is a disc, so shadows have a penumbra. Writes shadows-ultra.png, the day ground;
  * every wall face, at five heights (0-3, 3-8, 8-16, 16-32, 32-64 m), so a neighbour's shadow stops at the height it really
    reaches and a tall wall is no longer one tone. Rewrites the day half of faces.json;
  * every roof. Rewrites field 11 (the roof tone) of buildings.json.

Run order:  build_buildings.py, build_city_detail.py, bake_shadows.py, bake_detail.py, then this.
Needs:  pip install numpy pillow scipy; node 22 or later; Brave, Chrome or Edge; a graphics card with float render targets.
Environment: GPU_PASSES (default 16), GPU_RAYS (default 64: passes x rays rays a probe), GPU_GROUND=0 to skip the ground.
"""
import json, math, os, subprocess, sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw
from scipy.ndimage import gaussian_filter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from boundary import Boundary

MAP = os.path.normpath(os.path.join(HERE, '..', '..', 'admin', 'assets', 'map'))
WORK = os.path.join(HERE, 'gpu', 'work')
PX = 1.0
AZ, TAN = 200.0, .9
PASSES = int(os.environ.get('GPU_PASSES', 16))
RAYS = int(os.environ.get('GPU_RAYS', 64))
DO_GROUND = os.environ.get('GPU_GROUND', '1') != '0'
MAP_AREA = (121.0027, 14.5146, 121.0284, 14.5392)
LAT0 = math.radians(14.525)
MX, MY = 111320 * math.cos(LAT0), 110574
WALLS = [(243, 205, 184), (248, 226, 160), (190, 226, 203), (184, 214, 242), (211, 194, 240), (241, 236, 228), (235, 197, 144), (208, 208, 214)]
B36 = '0123456789abcdefghijklmnopqrstuvwxyz'


def main():
    B = Boundary()
    bw, bs, be, bn = B.bbox
    pad = .0004
    w, s, e, n = max(bw, MAP_AREA[0]) - pad, max(bs, MAP_AREA[1]) - pad, min(be, MAP_AREA[2]) + pad, min(bn, MAP_AREA[3]) + pad
    W, H = int(math.ceil((e - w) * MX / PX)), int(math.ceil((n - s) * MY / PX))
    print('height map %d x %d px at %.1f m' % (W, H, PX))
    bdoc = json.load(open(os.path.join(MAP, 'buildings.json'), encoding='utf-8'))
    bld = bdoc['b']
    det = json.load(open(os.path.join(MAP, 'city-detail.json'), encoding='utf-8'))
    fdoc = json.load(open(os.path.join(MAP, 'faces.json'), encoding='utf-8'))
    BANDS = fdoc['bands']
    to_px = lambda lng, lat: ((lng - w) * MX / PX, (n - lat) * MY / PX)

    hm = Image.new('F', (W, H), 0.0)
    wall = Image.new('RGB', (W, H), (150, 160, 150))
    roof = Image.new('RGB', (W, H), (70, 130, 80))             # a crown seen from above
    hd, wd, rd = ImageDraw.Draw(hm), ImageDraw.Draw(wall), ImageDraw.Draw(roof)
    for lng, lat, r, h, v, shape, real in det['trees']:
        x, y = to_px(lng, lat)
        rr = (1.3 if shape == 2 else r * .9) / PX
        hd.ellipse([x - rr, y - rr, x + rr, y + rr], fill=float(h) * (.95 if shape == 2 else .85))
    for b in sorted(bld, key=lambda b: b[1]):
        pts = [to_px(b[0][i], b[0][i + 1]) for i in range(0, len(b[0]), 2)]
        hd.polygon(pts, fill=float(b[1]))
        hh = float(b[1])
        k = int(((math.sin(b[4] * 1e3 * 12.9898 + b[5] * 1e3 * 78.233) * 43758.5453) % 1) * 8)
        wd.polygon(pts, fill=WALLS[min(7, k)] if hh < 9 else (230, 228, 226))
        rd.polygon(pts, fill=(246, 244, 240))
    hmap = np.asarray(hm, dtype=np.float32)
    rgba = lambda im: np.dstack([np.asarray(im, dtype=np.uint8), np.full((H, W), 255, np.uint8)])

    # ---- the probes: wall faces at several heights, then roofs ----
    probes, mapping = [], []     # mapping: ('f', building, band, edge) or ('r', building)
    for bi, b in enumerate(bld):
        ring, hb = b[0], float(b[1])
        pts = [(ring[i] * MX, ring[i + 1] * MY) for i in range(0, len(ring), 2)]
        k = len(pts)
        area = sum(pts[i][0] * pts[(i + 1) % k][1] - pts[(i + 1) % k][0] * pts[i][1] for i in range(k)) / 2
        sgn = 1.0 if area > 0 else -1.0
        nb = max(1, sum(1 for t in range(len(BANDS) - 1) if BANDS[t] < hb - .5))
        for t in range(nb):
            z = min(max((BANDS[t] + min(BANDS[t + 1], hb)) / 2, .3), max(hb - .2, .3))
            for i in range(k):
                (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % k]
                dx, dy = x1 - x0, y1 - y0
                ln = math.hypot(dx, dy) or 1.0
                nx, ny = sgn * dy / ln, -sgn * dx / ln          # outward, north up
                mx, my = (x0 + x1) / 2 - w * MX, n * MY - (y0 + y1) / 2   # the face's middle in the picture, metres, y down
                probes.append((mx + nx * .35, my - ny * .35, z, nx, -ny, 0.0))
                mapping.append(('f', bi, t, i))
        cx, cy = (b[4] - w) * MX, (n - b[5]) * MY
        probes.append((cx, cy, hb + .2, 0., 0., 1.))
        mapping.append(('r', bi))
    pr = np.array(probes, dtype=np.float32)
    flat = np.zeros((len(pr) * 2, 4), dtype=np.float32)
    flat[0::2, :3] = pr[:, :3]
    flat[1::2, :3] = pr[:, 3:]
    print('probes: %d (%d on faces, %d on roofs)' % (len(pr), sum(1 for m in mapping if m[0] == 'f'), sum(1 for m in mapping if m[0] == 'r')))

    os.makedirs(os.path.join(WORK, 'in'), exist_ok=True)
    os.makedirs(os.path.join(WORK, 'out'), exist_ok=True)
    for f in os.listdir(os.path.join(WORK, 'out')):
        os.remove(os.path.join(WORK, 'out', f))
    inp = lambda f: os.path.join(WORK, 'in', f)
    hmap.tofile(inp('hmap.f32'))
    rgba(wall).tofile(inp('wall.rgba'))
    rgba(roof).tofile(inp('roof.rgba'))
    flat.tofile(inp('probes.f32'))
    az = math.radians(AZ)
    ce = 1 / math.sqrt(1 + TAN * TAN)
    sun = [math.sin(az) * ce, -math.cos(az) * ce, TAN * ce]       # towards the sun: east, south (picture y), up
    json.dump({'w': W, 'h': H, 'px': PX, 'sun': sun, 'passes': PASSES, 'rays': RAYS, 'ground': DO_GROUND, 'probes': len(pr)}, open(inp('meta.json'), 'w'))

    print('tracing on the graphics card: %d passes of %d rays (%d rays a probe)' % (PASSES, RAYS, PASSES * RAYS))
    r = subprocess.run(['node', os.path.join(HERE, 'gpu', 'bake.mjs'), WORK])
    if r.returncode:
        raise SystemExit('the GPU bake failed')
    out = lambda f: os.path.join(WORK, 'out', f)

    # ---- the day ground ----
    if DO_GROUND:
        g = np.fromfile(out('ground.rgba'), dtype=np.uint8).reshape(H, W, 4)
        inside = Image.new('1', (W, H), 0)
        for ring in B.rings:
            layer = Image.new('1', (W, H), 0)
            ImageDraw.Draw(layer).polygon([((x - w) * MX / PX, (n - y) * MY / PX) for x, y in ring], fill=1)
            inside = ImageChops.logical_xor(inside, layer)
        soft = gaussian_filter(np.asarray(inside.convert('L'), dtype=np.float32) / 255, 2.0)
        a = gaussian_filter(g[..., 3].astype(np.float32) / 255, .6) * (hmap < 2.5) * soft
        img = np.zeros((H, W, 4), np.uint8)
        img[..., :3] = (g[..., :3] // 4) * 4
        img[..., 3] = ((a * 255).astype(np.uint8) // 4) * 4
        po = os.path.join(MAP, 'shadows-ultra.png')
        Image.fromarray(img, 'RGBA').save(po, optimize=True)
        print('wrote shadows-ultra.png', os.path.getsize(po) // 1024, 'KB')

    # ---- wall faces and roofs ----
    res = np.fromfile(out('probes.f32'), dtype=np.float32).reshape(-1, 2)
    ratio = np.clip(res[:, 0] / np.maximum(res[:, 1], 1e-4), 0, 1.2)
    rows = [[[] for _ in range(len(BANDS) - 1)] for _ in bld]
    for (m, rt) in zip(mapping, ratio):
        if m[0] == 'f':
            rows[m[1]][m[2]].append(B36[int(round(max(0.0, min(1.0, (rt - .25) / .75)) * 35))])
    tone = [float(.72 + .28 * max(0.0, min(1.0, (rt - .4) / .6))) for (m, rt) in zip(mapping, ratio) if m[0] == 'r']
    for bi, b in enumerate(bld):
        while len(b) < 13:
            b.append(1.0)
        b[11] = round(tone[bi], 2)
    fnew = []
    for bi, row in enumerate(fdoc['f']):
        nb = len(row[0].split('|'))
        fnew.append(['|'.join(''.join(row_) for row_ in rows[bi][:nb]), row[1]])
    # the digits above are 0..35 over a ratio of 0.25..1, while the map reads 0..35 over a tone of 0.5..1: the same scale
    fdoc['f'] = fnew
    fdoc['about'] = 'Per wall face light. Day tones path traced on the graphics card by docs/map-data/bake_gpu.py; lamp light by bake_detail.py. For each building, in the order of buildings.json: day tones and lamp light, one group per wall band (see "bands", metres), one base-36 digit each per footprint edge.'
    json.dump(fdoc, open(os.path.join(MAP, 'faces.json'), 'w'), separators=(',', ':'))
    json.dump(bdoc, open(os.path.join(MAP, 'buildings.json'), 'w'), separators=(',', ':'))
    d = np.array([B36.index(c) for row in fnew for sset in row[0].split('|') for c in sset])
    print('wall tones: mean %.2f; %d%% of wall bands are in shade (below 0.7)' % (.5 + .5 * d.mean() / 35, 100 * float((d < 14).mean())))
    print('roof tones: %.2f to %.2f, mean %.2f' % (min(tone), max(tone), sum(tone) / len(tone)))


main()
