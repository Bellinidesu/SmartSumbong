#!/usr/bin/env python3
"""
Bakes the light of the landmark models on the graphics card: for every vertex of every model, a day colour (how much of the sun and
the sky reaches it, with three bounces from the walls, roofs and ground round it) and a night colour (moonlight under the open sky,
the street lamps, the glow of lit windows), written to admin/assets/map/landmarks3d-light.bin as 8 bytes a vertex:
day r g b, night r g b, two spare. The map multiplies each vertex's albedo (and the facade atlas) by these, so the models are lit
like the rest of the City view without a single light being live.

Same path tracer as bake_gpu.py (gpu/bake.html); only the probes are different: the vertices.
Run after models.py and bake_gpu.py.        python docs/map-data/landmarks/bake_models.py
"""
import json, math, os, subprocess, sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
from boundary import Boundary
sys.path.insert(0, HERE)
import modelheights

MAP = os.path.normpath(os.path.join(HERE, '..', '..', '..', 'admin', 'assets', 'map'))
WORK = os.path.join(HERE, '..', 'gpu', 'work-models')
PX = float(os.environ.get('GPU_PX', .5))
AZ, TAN = 200.0, .9
PASSES = int(os.environ.get('GPU_PASSES', 24))
RAYS = 64
NIGHT_RAYS = int(os.environ.get('GPU_NIGHT_RAYS', 384))
MAP_AREA = (121.0027, 14.5146, 121.0284, 14.5392)
LAT0 = math.radians(14.525)
MX, MY = 111320 * math.cos(LAT0), 110574
WALLS = [(243, 205, 184), (248, 226, 160), (190, 226, 203), (184, 214, 242), (211, 194, 240), (241, 236, 228), (235, 197, 144), (208, 208, 214)]


def main():
    meta = json.load(open(os.path.join(MAP, 'landmarks3d.json')))
    bin_ = np.fromfile(os.path.join(MAP, 'landmarks3d.bin'), dtype=np.uint8)
    NV = meta['vertices']
    rec = np.dtype([('p', '<f4', 3), ('uv', '<f4', 2), ('m', 'u1'), ('c', 'u1', 3)])
    verts = np.frombuffer(bin_[:NV * 24].tobytes(), dtype=rec)
    idx = np.frombuffer(bin_[NV * 24:].tobytes(), dtype='<u4')
    # the normals the model builder wrote down for every vertex (work-normals.f32)
    P = verts['p'].astype(np.float64)
    Nrm = np.fromfile(os.path.join(HERE, 'work-normals.f32'), dtype='<f4').reshape(-1, 3).astype(np.float64)
    assert len(Nrm) == NV, 'run models.py first'
    Nrm /= np.maximum(np.linalg.norm(Nrm, axis=1), 1e-9)[:, None]

    # ---- the scene (as bake_gpu.py): the barangay's height map, with the models' heights where they replace a building ----
    B = Boundary()
    bw, bs, be, bn = B.bbox
    pad = .0004
    w, s, e, n = max(bw, MAP_AREA[0]) - pad, max(bs, MAP_AREA[1]) - pad, min(be, MAP_AREA[2]) + pad, min(bn, MAP_AREA[3]) + pad
    W, H = int(math.ceil((e - w) * MX / PX)), int(math.ceil((n - s) * MY / PX))
    bdoc = json.load(open(os.path.join(MAP, 'buildings.json'), encoding='utf-8'))
    bld = bdoc['b']
    det = json.load(open(os.path.join(MAP, 'city-detail.json'), encoding='utf-8'))
    over = {md['replaces']: md['height'] for md in meta['models']}
    to_px = lambda lng, lat: ((lng - w) * MX / PX, (n - lat) * MY / PX)
    hm = Image.new('F', (W, H), 0.0)
    wall = Image.new('RGB', (W, H), (150, 160, 150))
    wlit = Image.new('L', (W, H), 0)
    roof = Image.new('RGB', (W, H), (70, 130, 80))
    rtree = Image.new('L', (W, H), 255)
    hd, wd, rd, ld, td = ImageDraw.Draw(hm), ImageDraw.Draw(wall), ImageDraw.Draw(roof), ImageDraw.Draw(wlit), ImageDraw.Draw(rtree)
    for lng, lat, r, h, v, shape, real in det['trees']:
        x, y = to_px(lng, lat)
        rr = (1.3 if shape == 2 else r * .9) / PX
        hd.ellipse([x - rr, y - rr, x + rr, y + rr], fill=float(h) * (.95 if shape == 2 else .85))
        td.ellipse([x - rr, y - rr, x + rr, y + rr], fill=60)
    for bi, b in sorted(enumerate(bld), key=lambda t: t[1][1]):
        pts = [to_px(b[0][i], b[0][i + 1]) for i in range(0, len(b[0]), 2)]
        hh = float(over.get(bi, b[1]))
        if bi not in over:
            hd.polygon(pts, fill=hh)
        k = int(((math.sin(b[4] * 1e3 * 12.9898 + b[5] * 1e3 * 78.233) * 43758.5453) % 1) * 8)
        wd.polygon(pts, fill=WALLS[min(7, k)] if hh < 9 else (230, 228, 226))
        rd.polygon(pts, fill=(246, 244, 240))
        td.polygon(pts, fill=255)
        ld.polygon(pts, fill=int(max(0.0, min(1.0, float(b[12]) if len(b) > 12 else 0.0)) * 255))
    hmap = np.asarray(hm, dtype=np.float32)
    print('rasterising the models into the height map...')
    hmap = np.maximum(hmap, modelheights.raster(meta, bin_, w, n, PX, W, H))
    rgba = lambda im, a: np.dstack([np.asarray(im, dtype=np.uint8), np.asarray(a, dtype=np.uint8)])

    # ---- the probes: every vertex, in the picture's metres (x east, y south) ----
    pr = []
    for md in meta['models']:
        v0, nv = md['voff'], md['v']
        ox, oy = (md['lng'] - w) * MX, (n - md['lat']) * MY
        pos, nr = P[v0:v0 + nv], Nrm[v0:v0 + nv]
        pr.append(np.c_[ox + pos[:, 0], oy - pos[:, 1], pos[:, 2], nr[:, 0], -nr[:, 1], nr[:, 2]])
    pr = np.concatenate(pr).astype(np.float32)
    flat = np.zeros((len(pr) * 2, 4), dtype=np.float32)
    flat[0::2, :3] = pr[:, :3]
    flat[1::2, :3] = pr[:, 3:]
    print('vertices to light: %d' % len(pr))
    os.makedirs(os.path.join(WORK, 'in'), exist_ok=True)
    os.makedirs(os.path.join(WORK, 'out'), exist_ok=True)
    for f in os.listdir(os.path.join(WORK, 'out')):
        os.remove(os.path.join(WORK, 'out', f))
    inp = lambda f: os.path.join(WORK, 'in', f)
    hmap.tofile(inp('hmap.f32'))
    rgba(wall, wlit).tofile(inp('wall.rgba'))
    rgba(roof, rtree).tofile(inp('roof.rgba'))
    flat.tofile(inp('probes.f32'))
    lamps = det.get('lamps', [])
    np.array([[(l[0] - w) * MX, (n - l[1]) * MY, l[2], l[3]] for l in lamps], dtype=np.float32).tofile(inp('lamps.f32'))
    az = math.radians(AZ)
    ce = 1 / math.sqrt(1 + TAN * TAN)
    sun = [math.sin(az) * ce, -math.cos(az) * ce, TAN * ce]
    json.dump({'w': W, 'h': H, 'px': PX, 'sun': sun, 'passes': PASSES, 'rays': RAYS, 'ground': False, 'probes': len(pr), 'rgb': True, 'night': True,
               'lamps': len(lamps), 'nightK': 1.15, 'nightKw': 3.2, 'nightRays': NIGHT_RAYS}, open(inp('meta.json'), 'w'))
    r = subprocess.run(['node', os.path.join(HERE, '..', 'gpu', 'bake.mjs'), WORK])
    if r.returncode:
        raise SystemExit('the GPU bake failed')
    out = lambda f: os.path.join(WORK, 'out', f)
    res = np.fromfile(out('probes.f32'), dtype=np.float32).reshape(-1, 7)
    Er, Ef = res[:, 0:3], res[:, 3:6]
    up = pr[:, 5] > .95
    E0 = Ef[up].mean(axis=0) if up.any() else Ef.mean(axis=0)
    day = np.clip(Er / np.maximum(E0, 1e-4), 0, 1.25) / 1.25
    # night: moonlight under what is left of the open sky, the lamps, the lit windows
    nres = np.fromfile(out('nprobes.f32'), dtype=np.float32).reshape(-1, 3)
    sky = np.clip((Er.mean(axis=1) / np.maximum(Ef.mean(axis=1), 1e-4)), .15, 1.0)
    moon = np.array([.46, .50, .80])[None, :] * (.5 + .5 * sky)[:, None]
    lamp_w = np.array([1.0, .60, .28])[None, :] * nres[:, 0:1] * 1.5
    lamp_b = np.array([.72, .84, 1.0])[None, :] * nres[:, 1:2] * 1.5
    win = np.array([1.0, .70, .42])[None, :] * nres[:, 2:3] * 1.4
    night = np.clip(moon + lamp_w + lamp_b + win, 0, 1.25) / 1.25
    lb = np.zeros((NV, 8), dtype=np.uint8)
    lb[:, 0:3] = np.round(day * 255)
    lb[:, 3:6] = np.round(night * 255)
    lb.tofile(os.path.join(MAP, 'landmarks3d-light.bin'))
    print('wrote landmarks3d-light.bin: %d KB; day light mean %.2f, night mean %.2f' % (os.path.getsize(os.path.join(MAP, 'landmarks3d-light.bin')) // 1024, day.mean(), night.mean()))


main()
