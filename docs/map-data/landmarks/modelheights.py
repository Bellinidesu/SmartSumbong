"""
Rasterises the landmark models' real triangles into a height map (the highest surface over every pixel), so that the lighting bake sees
the shrine's domes and the terminal's canopy as they are, not a box as tall as the tallest part of the model.
"""
import math

import numpy as np

MX = 111320 * math.cos(math.radians(14.525))
MY = 110574


def read(meta, bin_):
    NV = meta['vertices']
    rec = np.dtype([('p', '<f4', 3), ('uv', '<f4', 2), ('m', 'u1'), ('c', 'u1', 3)])
    verts = np.frombuffer(bin_[:NV * 24].tobytes(), dtype=rec)
    idx = np.frombuffer(bin_[NV * 24:].tobytes(), dtype='<u4')
    return verts, idx


def raster(meta, bin_, w, n, px, W, H):
    verts, idx = read(meta, bin_)
    hm = np.zeros((H, W), dtype=np.float32)
    P = verts['p'].astype(np.float64)
    for md in meta['models']:
        v0, i0, ni = md['voff'], md['ioff'], md['i']
        ox, oy = (md['lng'] - w) * MX / px, (n - md['lat']) * MY / px
        tri = idx[i0:i0 + ni].reshape(-1, 3).astype(np.int64) + v0
        X = ox + P[:, 0] / px
        Y = oy - P[:, 1] / px
        Z = P[:, 2]
        for a, b, c in tri:
            xs, ys, zs = (X[a], X[b], X[c]), (Y[a], Y[b], Y[c]), (Z[a], Z[b], Z[c])
            x0, x1 = int(math.floor(min(xs))), int(math.ceil(max(xs)))
            y0, y1 = int(math.floor(min(ys))), int(math.ceil(max(ys)))
            x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, W - 1), min(y1, H - 1)
            if x1 < x0 or y1 < y0:
                continue
            den = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
            if abs(den) < 1e-9:
                # a vertical sliver: its top edge is what stands there
                for xx, yy, zz in zip(xs, ys, zs):
                    xi, yi = int(round(xx)), int(round(yy))
                    if 0 <= xi < W and 0 <= yi < H:
                        hm[yi, xi] = max(hm[yi, xi], zz)
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + .5, np.arange(y0, y1 + 1) + .5)
            l1 = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / den
            l2 = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / den
            l3 = 1 - l1 - l2
            ins = (l1 >= -.02) & (l2 >= -.02) & (l3 >= -.02)
            z = l1 * zs[0] + l2 * zs[1] + l3 * zs[2]
            sub = hm[y0:y1 + 1, x0:x1 + 1]
            np.maximum(sub, np.where(ins, z, 0), out=sub)
    return hm
