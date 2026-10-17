"""
The facade pass: every face of a building gets what that face would really have, not the same thing all round.

  * a face onto open ground (a street, a forecourt, a car park) is a street face: shopfront awnings over its ground floor, an entrance with a canopy and a
    dark door on the front one, the building's name on a sign band above it (lit at night), balconies on a hotel or a condominium, belt courses at the top of the
    podium and every fifth floor, pilasters at its corners;
  * a face onto a neighbour a few metres off is a party face: nothing hangs on it but a pipe or two;
  * the rest are side and rear faces: a service door, air-conditioner units at every window on a hotel or a condominium, plain belt courses.

Everything here is real geometry (small boxes), lit by the same GPU bake as the rest; the details are cut in as few triangles as they can be (one cell per face).
"""
import math
import zlib

from shapely.geometry import Point, Polygon

import atlas
from meshlib import MAT, _ccw
from models_common import C

CELL1 = 60.0      # a detail box is one cell a wall


def _hash(*a):
    return zlib.crc32(repr(a).encode())


def apply(m, ring, ctx, kind, h, name=None, flags=None):
    f = dict(awnings=True, entrance=True, sign=True, balconies=kind in ('hotel', 'condo'), ac=kind in ('hotel', 'condo'), belts=True, pilasters=kind in ('hotel', 'mall', 'generic', 'school', 'psca', 'hospital'))
    f.update(flags or {})
    ring = _ccw(ring)
    others = ctx.get('others', [])
    n = len(ring)
    floors = max(2, int(round((h - 1.2) / 3.4)))
    gh = min(6.0, max(4.2, h * .3)) if h > 9 else 3.6
    # the front: the face with the most open ground and the best length
    best, front = -1, 0
    faces = []
    for i in range(n):
        a, b = ring[i], ring[(i + 1) % n]
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy)
        if ln < 3.0:
            faces.append(None)
            continue
        ux, uy = dx / ln, dy / ln
        nx, ny = uy, -ux
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        free = min([Point(mid[0] + nx * d, mid[1] + ny * d).distance(o) for d in (2.5, 6, 11) for o in others] + [60.0])
        faces.append(dict(a=a, b=b, ln=ln, u=(ux, uy), nrm=(nx, ny), th=math.atan2(dy, dx), free=free))
        score = ln * (1 + min(free, 30) / 15)
        if score > best:
            best, front = score, i
    ac_budget = 160
    belt_levels = [gh] + [1.2 + k * 3.4 for k in range(5, floors, 5)]
    sign = atlas.sign_id(name) if (name and f['sign']) else None
    for i, fc in enumerate(faces):
        if not fc:
            continue
        a, ln, (ux, uy), (nx, ny), th, free = fc['a'], fc['ln'], fc['u'], fc['nrm'], fc['th'], fc['free']
        street = free >= 8.0
        party = free < 3.2
        P = lambda t, off: (a[0] + ux * t + nx * off, a[1] + uy * t + ny * off)
        box = lambda t, off, z0, L, W, H, col, mat='plain': m.box(P(t, off)[0], P(t, off)[1], z0, L, W, H, th, mat, col, 'plain', col, True, CELL1)
        if party:
            continue
        # belt courses
        if f['belts'] and ln >= 5 and h > 8:
            for z in belt_levels:
                if z < h - 1.5:
                    box(ln / 2, .2, z, ln - .2, .5, .3, C['white'])
        # corner pilasters
        if f['pilasters'] and ln >= 6 and h > 7:
            box(.35, .12, 0, .7, .7, h - .2, C['cream'])
        if street and ln >= 7 and h >= 5:
            # shopfront awnings, one for every bay of about 5.5 m
            if f['awnings']:
                k = max(1, int((ln - 1.5) // 5.5))
                step = ln / k
                for j in range(k):
                    col = (C['blue'], C['red'], C['teal'], C['orange'], C['navy'])[_hash(round(a[0], 1), round(a[1], 1), j) % 5]
                    box(step * (j + .5), .8, 3.3, step - 1.2, 1.6, .14, col)
            if i == front:
                if f['entrance']:
                    box(ln / 2, 1.2, 3.8, 4.4, 2.6, .3, C['white'])
                    for sgn in (-1, 1):
                        box(ln / 2 + sgn * 1.9, 2.1, 0, .22, .22, 3.8, C['white'])
                    box(ln / 2, .06, 0, 2.6, .14, 2.8, C['navy'], 'panel')
                if sign and ln >= 9.5 and h > 6:
                    w = min(12.0, ln * .8)
                    t0 = (ln - w) / 2
                    p0 = P(t0, .14)
                    z0 = max(gh + .4, 4.3) if h > 8 else 3.3
                    z1 = z0 + 1.6
                    m.grid((p0[0], p0[1], z0), (ux * w, uy * w, 0.0), (0.0, 0.0, 1.6), 1, 1, (nx, ny, 0.0), sign, (255, 255, 255), (0.0, 0.0), (1.0, 1.0))
        if f['balconies'] and ln >= 9 and h > 12 and (street or free >= 3.2):
            for fl in range(1, floors - 1):
                z = 1.2 + fl * 3.4 - .15
                box(ln / 2, .65, z, ln * .84, 1.2, .16, C['white'])
                box(ln / 2, 1.22, z + .16, ln * .84, .05, .95, C['glass'], 'glass')
        elif f['ac'] and ln >= 6 and h > 10 and not street:
            # the back of the building: a condenser at every window
            bays = int(ln // 3.2)
            for fl in range(1, floors):
                for j in range(bays):
                    if ac_budget <= 0:
                        break
                    box(3.2 * (j + .5) + (ln - bays * 3.2) / 2, .3, 1.2 + fl * 3.4 + .35, .75, .55, .5, C['grey'])
                    ac_budget -= 1
        if not street and ln >= 6 and h > 5 and i != front:
            box(ln * .3, .06, 0, 1.6, .12, 2.2, C['slate'], 'panel')     # a service door
    # a mast on the roof of a tall building
    if h >= 28:
        m.cylinder(ctx['cx'], ctx['cy'], h + 4, h + 12, .12, 'plain', C['slate'], seg=6)
