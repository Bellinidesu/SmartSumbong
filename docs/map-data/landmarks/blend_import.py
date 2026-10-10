"""Reads a model exported from Blender (blend/export_model.py: an .npz of triangle corners) into the arrays the map's model builder uses. Colours are flat; every material is the map's plain tile except the
glow bands (a material named glow0 .. glow3) and signs."""
import os

import numpy as np

from meshlib import MAT


def load(sh, here):
    path = os.path.join(here, 'blend', 'models', sh['blend']) if not os.path.isabs(sh['blend']) else sh['blend']
    if not os.path.exists(path):
        print('  blend model missing:', path)
        return None
    d = np.load(path, allow_pickle=False)
    P = d['p'].astype(np.float64)
    N = d['n'].astype(np.float64)
    C = d['c'].astype(np.uint8)
    names = [str(x) for x in d['names']]
    ids = []
    for nm in names:
        base = nm.split('.')[0].split(':')[0]
        ids.append(MAT.get(base, MAT['plain']))
    M = np.asarray([ids[i] for i in d['m']], dtype=np.uint8)
    U = np.zeros((len(P), 2), dtype=np.float32)
    Ix = np.arange(len(P), dtype=np.uint32)
    return P, N, U, M, C, Ix
