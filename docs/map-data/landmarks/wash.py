#!/usr/bin/env python3
"""
The night wash of a landmark: a colour of light that climbs its walls from the ground (the way Marina Bay Sands is washed in violet), different for every
landmark that asks for one in its sheet (night.wash: colour, height, strength). Baked, never live: it goes into the two spare bytes of each vertex of
landmarks3d-light.bin.gz (how much, which of the eight colours), and the map adds it to the night light.

Run after bake_models.py.        python docs/map-data/landmarks/wash.py
"""
import gzip, json, os

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
MAP = os.path.normpath(os.path.join(HERE, '..', '..', '..', 'admin', 'assets', 'map'))


def main():
    meta = json.load(open(os.path.join(MAP, 'landmarks3d.json'), encoding='utf-8'))
    NV = meta['vertices']
    raw = open(os.path.join(HERE, 'work', 'landmarks3d.bin'), 'rb').read()
    rec = np.dtype([('p', '<f4', 3), ('uv', '<f4', 2), ('m', 'u1'), ('c', 'u1', 3)])
    P = np.frombuffer(raw[:NV * 24], dtype=rec)['p']
    N = np.fromfile(os.path.join(HERE, 'work', 'normals.f32'), dtype='<f4').reshape(-1, 3)
    path = os.path.join(MAP, 'landmarks3d-light.bin.gz')
    lb = np.frombuffer(gzip.decompress(open(path, 'rb').read()), dtype=np.uint8).reshape(NV, 8).copy()
    lb[:, 6:8] = 0
    n = 0
    for md in meta['models']:
        w = md.get('wash')
        if not w:
            continue
        a, b = md['voff'], md['voff'] + md['v']
        z = P[a:b, 2]
        wall = 1.0 - np.abs(N[a:b, 2])                       # walls take the wash; roofs do not
        up = np.clip(1.0 - z / max(w['h'], 1.0), 0, 1) ** 1.6
        v = np.clip(w['s'] * up * wall, 0, 1)
        lb[a:b, 6] = np.round(v * 255).astype(np.uint8)
        lb[a:b, 7] = w['c']
        n += 1
    open(path, 'wb').write(gzip.compress(lb.tobytes(), 9))
    print('wash: %d landmarks washed' % n)


main()
