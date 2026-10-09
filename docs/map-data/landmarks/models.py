#!/usr/bin/env python3
"""
Builds the 3D models of the landmarks: admin/assets/map/landmarks3d.json (what each is, where it stands, which OSM building it
replaces), landmarks3d.bin (every vertex: position, texture coordinate, material, albedo colour; and the triangles),
landmarks3d-atlas.png and landmarks3d-emis.png (the facade atlas by day and its lit windows by night).

The models are drawn here, in the barangay's own style (flat pastel colours, plain facades, a few honest details), from the
proportions and colours seen in reference photos (fetch_refs.py; those photos are not shipped). A landmark stands on the real footprint
of its building (buildings.json), so it fits its lot; its height, roof, colours and details come from a template for what kind of
building it is (a church, a terminal, a mall, a school...) and, for the ones with photos, from what the photos show.

The lighting is not here: bake_models.py has the graphics card trace every vertex and writes landmarks3d-light.bin.

Run:  python docs/map-data/landmarks/models.py
"""
import json, math, os, re, sys

import numpy as np
from shapely.geometry import Point, Polygon

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..'))
from meshlib import Mesh, MAT, rgb, _obb, _ccw
import atlas

ROOT = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
MAP = os.path.join(ROOT, 'admin', 'assets', 'map')
LAT0 = math.radians(14.525)
MX, MY = 111320 * math.cos(LAT0), 110574

# our identity: soft pastels, one strong accent each
C = dict(
    cream=rgb('F1E6D2'), white=rgb('F4F1EA'), peach=rgb('EBC2A8'), terra=rgb('CC8A66'), sand=rgb('E3CFA6'), rose=rgb('E6B7B0'),
    blue=rgb('4C79C4'), navy=rgb('3A4C86'), teal=rgb('2FA6AB'), green=rgb('4C9A6A'), grey=rgb('B8BDC8'), slate=rgb('7C849A'),
    red=rgb('C9544A'), orange=rgb('F08C3A'), yellow=rgb('F2C14E'), glass=rgb('B9C9DA'), dome=rgb('3F6FB5'), roofblue=rgb('3F67B0'),
    rooftile=rgb('B9654F'), roofgrey=rgb('7F8794'), sheetwhite=rgb('EDEDED'),
)


def local_ring(b, lng0, lat0):
    r = b[0]
    return [((r[i] - lng0) * MX, (r[i + 1] - lat0) * MY) for i in range(0, len(r), 2)]


# ---------- templates ----------------------------------------------------------------------------------------------------------------

def _front(ctx, others):
    """The way a building faces: of its four oriented-box sides, the one with the most open ground in front of it (a road, a forecourt).
    Returns (unit vector out of the front, half the length across it, half the length behind it, the unit vector along the front)."""
    th, L, W = ctx['th'], ctx['L'], ctx['W']
    c, s_ = math.cos(th), math.sin(th)
    best = None
    for k, (dx, dy, half, across, along) in enumerate(((c, s_, L / 2, W / 2, (-s_, c)), (-c, -s_, L / 2, W / 2, (s_, -c)),
                                                         (-s_, c, W / 2, L / 2, (c, s_)), (s_, -c, W / 2, L / 2, (-c, -s_)))):
        mid = Point(dx * (half + 1), dy * (half + 1))
        free = min([mid.distance(o) for o in others] + [80.0])
        score = free + (6 if k < 2 else 0)
        if best is None or score > best[0]:
            best = (score, (dx, dy), half, across, along)
    _, d, half, across, along = best
    return d, half, across, along


def t_shrine(m, ring, ctx, p):
    """The Shrine of St. Therese (Newport City): from the photographs: terracotta walls, a facade of four stepped concentric arches with the
    saint above and a cross, a flat portico on columns with planter boxes and a columbarium band, two drum towers with blue domes, a long
    side wall of arched windows behind a hedge. The way it faces is the side with the most open ground."""
    h = p.get('h', 11.5)
    ring = _ccw(ring)
    m.prism(ring, 0, h, 'arches', C['terra'], 'plain', C['sand'], top=True)
    fr, half, across, along = _front(ctx, ctx.get('others', []))
    cx, cy = ctx['cx'], ctx['cy']
    nx, ny = fr
    ux, uy = along
    wf = min(2 * across * .86, 24.0)
    ox, oy = cx + nx * (half + .05), cy + ny * (half + .05)
    # the stepped arches: each a little proud of the one behind, lighter at the front
    steps = [(.50, .46, C['terra']), (.41, .50, C['peach']), (.32, .54, C['terra']), (.23, .58, C['peach'])]
    fh = h + 9.0
    for k, (rf, leg, col) in enumerate(steps):
        R = wf * rf
        leg_h = fh - R - 0.5 - k * .6
        m.vprism(m.arch_poly(R, max(1.0, leg_h)), (ox, oy, 0), (ux, uy), (nx, ny), .25 + k * .55, .8 + k * .55, 'plain', col)
    # the stained glass: a dark recessed arch
    R = wf * .16
    m.vprism(m.arch_poly(R, 4.2), (ox, oy, 6.2), (ux, uy), (nx, ny), 2.2, 2.45, 'plain', C['navy'])
    # a cross and the statue above the arch
    top = fh + .3
    m.vprism([(-.14, 0), (.14, 0), (.14, 2.6), (-.14, 2.6)], (ox, oy, top), (ux, uy), (nx, ny), 2.0, 2.3, 'plain', C['yellow'])
    m.vprism([(-.9, 1.6), (.9, 1.6), (.9, 1.95), (-.9, 1.95)], (ox, oy, top), (ux, uy), (nx, ny), 2.0, 2.3, 'plain', C['yellow'])
    m.vprism([(-.55, 0), (.55, 0), (.45, 3.4), (-.45, 3.4)], (ox, oy, top - 3.8), (ux, uy), (nx, ny), 2.0, 3.0, 'plain', C['cream'])
    # the portico: a flat roof on columns, a band with the shrine's name, planter boxes along its edge
    pd, pw, pz = 6.5, wf * .9, 5.4
    pcx, pcy = ox + nx * (pd / 2 + .3), oy + ny * (pd / 2 + .3)
    thp = math.atan2(uy, ux)
    m.box(pcx, pcy, pz, pw, pd, .6, thp, 'plain', C['terra'], 'plain', C['sand'])
    m.box(pcx + nx * (pd / 2 - .05), pcy + ny * (pd / 2 - .05), pz + .6, pw, .3, 1.1, thp, 'sign', C['cream'], 'plain', C['cream'])      # the band
    for k in range(5):
        t = (k / 4 - .5) * pw * .86
        m.column(pcx + ux * t + nx * (pd / 2 - .5), pcy + uy * t + ny * (pd / 2 - .5), 0, pz, .38, C['terra'])
        m.box(pcx + ux * t + nx * (pd / 2 - .2), pcy + uy * t + ny * (pd / 2 - .2), pz + .6, 1.6, 1.0, .8, thp, 'plain', C['green'], 'plain', C['green'])   # a planter
    # two drum towers beside the facade, each with a blue dome and a little cross
    for sgn in (-1, 1):
        tx, ty = ox + ux * sgn * wf * .62 - nx * 4.0, oy + uy * sgn * wf * .62 - ny * 4.0
        r = min(3.8, wf * .17)
        m.prism([(tx + r * math.cos(2 * math.pi * i / 8), ty + r * math.sin(2 * math.pi * i / 8)) for i in range(8)], h, h + 4.4, 'arches', C['terra'], 'plain', C['sand'], top=True)
        m.dome(tx, ty, h + 4.4, r * 1.04, r * .62, 'plain', C['dome'], seg=16)
        m.cylinder(tx, ty, h + 4.4 + r * .62, h + 4.4 + r * .62 + 1.6, .1, 'plain', C['yellow'], seg=6)
    # a low parapet round the roof
    poly = Polygon(ring).buffer(-.35, join_style=2)
    if not poly.is_empty and poly.geom_type == 'Polygon':
        m.prism(list(poly.exterior.coords)[:-1], h, h + .8, 'plain', C['sand'], 'plain', C['sand'], top=False)


def t_chapel(m, ring, ctx, p):
    """A small chapel: white walls with arched windows, a grey pitched roof, a little bell tower at one end."""
    h = p.get('h', 6.0)
    m.prism(ring, 0, h, 'arches', C['white'], 'plain', C['white'], top=False)
    cx, cy, L, W, th = ctx['cx'], ctx['cy'], ctx['L'], ctx['W'], ctx['th']
    m.gable(cx, cy, L, W, th, h, min(3.4, W * .3), 'sheet', C['roofgrey'], over=.45, gable_col=C['white'])
    c, s = math.cos(th), math.sin(th)
    tx, ty = cx + (L / 2 - 1.6) * c, cy + (L / 2 - 1.6) * s
    m.box(tx, ty, h, 2.6, 2.6, 4.6, th, 'plain', C['white'], 'plain', C['white'])
    m.hip(tx, ty, 2.6, 2.6, th, h + 4.6, 2.4, 'sheet', C['roofblue'], over=.25)
    m.box(tx, ty, h + 7.0, .18, .18, 1.5, th, 'plain', C['cream'])


def _free_side(ctx, ring, others):
    """The long side of a building whose outside is the most open (where a canopy or a drop-off would go): its index."""
    poly = Polygon(ring)
    best, bi = -1.0, 0
    n = len(ring)
    for i in range(n):
        a, b = ring[i], ring[(i + 1) % n]
        ln = math.hypot(b[0] - a[0], b[1] - a[1])
        if ln < 6:
            continue
        mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
        nx, ny = (b[1] - a[1]) / ln, -(b[0] - a[0]) / ln
        free = min([Point(mx + nx * d, my + ny * d).distance(o) for d in (6, 12) for o in others] + [60])
        if ln * (1 + free / 30) > best:
            best, bi = ln * (1 + free / 30), i
    return bi


def t_terminal(m, ring, ctx, p):
    """An airport terminal: a long low building with a white fascia, a deep canopy on slim steel columns on its open side."""
    h = p.get('h', 12.0)
    ring = _ccw(ring)
    m.prism(ring, 0, h - .9, p.get('wall', 'ribbon'), p.get('col', C['white']), 'plain', C['sheetwhite'], top=False)
    # the white fascia band, a little proud of the wall
    poly = Polygon(ring).buffer(.5, join_style=2)
    m.prism(list(poly.exterior.coords)[:-1], h - 1.5, h + .3, 'plain', C['white'], 'sheet', C['sheetwhite'], top=True)
    i = ctx.get('side', 0)
    a, b = ring[i], ring[(i + 1) % len(ring)]
    ln = math.hypot(b[0] - a[0], b[1] - a[1])
    if ln > 10:
        ux, uy = (b[0] - a[0]) / ln, (b[1] - a[1]) / ln
        nx, ny = uy, -ux
        d = p.get('canopy', 7.0)
        quad = [(a[0], a[1]), (b[0], b[1]), (b[0] + nx * d, b[1] + ny * d), (a[0] + nx * d, a[1] + ny * d)]
        zc = min(h - 3.0, 7.5)
        m.prism(quad, zc, zc + .55, 'plain', C['white'], 'sheet', C['sheetwhite'], top=True)
        m.cap(quad, zc, MAT['plain'], C['grey'], up=False)
        k = max(2, int(ln // 9))
        for j in range(k + 1):
            t = j / k
            m.column(a[0] + ux * ln * t + nx * (d - .7), a[1] + uy * ln * t + ny * (d - .7), 0, zc, .22, C['slate'])
    # plant on the roof
    for q in range(p.get('plant', 3)):
        t = (q + .5) / p.get('plant', 3)
        px, py = ctx['cx'] + (t - .5) * ctx['L'] * .8 * math.cos(ctx['th']), ctx['cy'] + (t - .5) * ctx['L'] * .8 * math.sin(ctx['th'])
        m.box(px, py, h + .3, 4.5, 3.0, 1.6, ctx['th'], 'louvre', C['grey'], 'plain', C['grey'])


def t_mall(m, ring, ctx, p):
    """A shopping mall: a shopfront ground floor, upper floors of windows in a pastel, a cornice and rooftop plant."""
    h = p.get('h', 16.0)
    ring = _ccw(ring)
    gh = min(5.0, h * .4)
    m.prism(ring, 0, gh, 'shop', p.get('base', C['cream']), 'plain', C['sand'], top=False)
    m.prism(ring, gh, h, p.get('wall', 'windows'), p.get('col', C['peach']), 'plain', C['sand'], top=False)
    poly = Polygon(ring).buffer(.45, join_style=2)
    m.prism(list(poly.exterior.coords)[:-1], h - .1, h + .9, 'plain', p.get('trim', C['cream']), 'sheet', C['sheetwhite'], top=True)
    n = max(1, min(8, int(Polygon(ring).area // 500)))
    for q in range(n):
        t = (q + .5) / n
        px, py = ctx['cx'] + (t - .5) * ctx['L'] * .7 * math.cos(ctx['th']), ctx['cy'] + (t - .5) * ctx['L'] * .7 * math.sin(ctx['th'])
        m.box(px, py, h + .9, 5.0, 3.4, 1.8, ctx['th'], 'louvre', C['grey'], 'plain', C['grey'])


def t_hospital(m, ring, ctx, p):
    """A hospital: cream walls with rows of windows, a blue band at the top, a rooftop water tank."""
    h = p.get('h', 18.0)
    ring = _ccw(ring)
    m.prism(ring, 0, h - 2.2, 'windows', C['cream'], 'plain', C['cream'], top=False)
    m.prism(ring, h - 2.2, h, 'sign', p.get('band', C['blue']), 'plain', C['white'], top=True)
    poly = Polygon(ring).buffer(.35, join_style=2)
    m.prism(list(poly.exterior.coords)[:-1], h, h + .7, 'plain', C['white'], 'sheet', C['sheetwhite'], top=True)
    m.cylinder(ctx['cx'], ctx['cy'], h + .7, h + 4.2, 1.7, 'plain', C['grey'], seg=12, cap_mat='plain', cap_col=C['slate'])


def t_school(m, ring, ctx, p):
    """A school: cream walls, ribbon windows, a pitched green sheet roof."""
    h = p.get('h', 8.5)
    m.prism(ring, 0, h, p.get('wall', 'ribbon'), p.get('col', C['cream']), 'plain', C['cream'], top=False)
    cx, cy, L, W, th = ctx['cx'], ctx['cy'], ctx['L'], ctx['W'], ctx['th']
    if W < 20:
        m.gable(cx, cy, L, W, th, h, min(3.0, W * .22), 'sheet', p.get('roof', C['green']), over=.5, gable_col=p.get('col', C['cream']))
    else:
        m.cap(_ccw(ring), h, MAT['sheet'], p.get('roof', C['green']), True)


def t_psca(m, ring, ctx, p):
    """The Philippine State College of Aeronautics: cream with blue columns and trim, a pediment over the entrance."""
    h = p.get('h', 12.0)
    ring = _ccw(ring)
    m.prism(ring, 0, h, 'windows', C['cream'], 'plain', C['white'], top=True)
    cx, cy, L, W, th = ctx['cx'], ctx['cy'], ctx['L'], ctx['W'], ctx['th']
    c, s = math.cos(th), math.sin(th)
    n = max(3, int(L // 6))
    for i in range(n + 1):
        u = -L / 2 + L * i / n
        for side in (-1, 1):
            m.box(cx + u * c - side * (W / 2 + .1) * s * -1, cy + u * s + side * (W / 2 + .1) * c * 1, 0, 1.0, 1.0, h, th, 'column', C['blue'], 'plain', C['blue'])
    m.box(cx, cy, h, L, W, .9, th, 'plain', C['blue'], 'plain', C['blue'])
    m.gable(cx, cy, min(L * .3, 14), W + .6, th + math.pi / 2, h + .9, 2.2, 'plain', C['white'], over=.2, gable_col=C['white'])


def t_shop(m, ring, ctx, p):
    """A small shop: a shopfront with a sign band in the shop's colour, a flat roof with a parapet."""
    h = p.get('h', 6.0)
    ring = _ccw(ring)
    gh = min(4.2, h * .62)
    m.prism(ring, 0, gh, 'shop', p.get('base', C['white']), 'plain', C['white'], top=False)
    m.prism(ring, gh, h, p.get('upper', 'windows'), p.get('col', C['cream']), 'plain', C['sand'], top=True)
    # the sign band: a coloured strip right round, a little proud
    poly = Polygon(ring).buffer(.18, join_style=2)
    m.prism(list(poly.exterior.coords)[:-1], gh - .2, gh + 1.0, 'sign', p.get('sign', C['teal']), 'plain', p.get('sign', C['teal']), top=False)


def t_hall(m, ring, ctx, p):
    """The barangay hall: two storeys, cream walls with windows, a blue pitched roof, an entrance canopy, a flagpole."""
    h = p.get('h', 7.0)
    ring = _ccw(ring)
    m.prism(ring, 0, h, 'windows', C['cream'], 'plain', C['cream'], top=False)
    cx, cy, L, W, th = ctx['cx'], ctx['cy'], ctx['L'], ctx['W'], ctx['th']
    m.gable(cx, cy, L, W, th, h, min(3.4, W * .3), 'sheet', C['roofblue'], over=.55, gable_col=C['cream'])
    c, s = math.cos(th), math.sin(th)
    # a covered entrance on the middle of one long side, and a blue sign band above it
    for side in (1,):
        ex, ey = cx - side * (W / 2 + 1.6) * s, cy + side * (W / 2 + 1.6) * c
        m.slab(ex, ey, min(9, L * .4), 3.4, th, 3.6, .35, C['blue'])
        for q in (-1, 1):
            m.column(ex + q * min(9, L * .4) / 2 * .8 * c - side * 1.3 * s * .0, ey + q * min(9, L * .4) / 2 * .8 * s, 0, 3.6, .22, C['white'])
    m.cylinder(cx + (L / 2 + 2.2) * c, cy + (L / 2 + 2.2) * s, 0, 9.0, .11, 'plain', C['slate'], seg=6)
    m.box(cx + (L / 2 + 2.7) * c, cy + (L / 2 + 2.7) * s, 7.4, 1.0, .05, .7, th, 'plain', C['red'], 'plain', C['red'])


def t_tower(m, ring, ctx, p):
    """A tower: a glass curtain wall, a crown, a setback near the top."""
    h = p.get('h', 40.0)
    ring = _ccw(ring)
    m.prism(ring, 0, h * .9, 'glass', p.get('col', C['glass']), 'plain', C['grey'], top=False)
    poly = Polygon(ring).buffer(-2.0, join_style=2)
    if not poly.is_empty and poly.geom_type == 'Polygon':
        m.prism(list(poly.exterior.coords)[:-1], h * .9, h, 'glass', C['slate'], 'plain', C['grey'], top=True)
        m.cap(ring, h * .9, MAT['plain'], C['grey'], True)
    else:
        m.cap(ring, h * .9, MAT['plain'], C['grey'], True)


def t_police(m, ring, ctx, p):
    h = p.get('h', 6.5)
    m.prism(ring, 0, h, 'windows', C['white'], 'plain', C['white'], top=False)
    cx, cy, L, W, th = ctx['cx'], ctx['cy'], ctx['L'], ctx['W'], ctx['th']
    m.hip(cx, cy, L, W, th, h, min(2.6, W * .25), 'sheet', C['navy'], over=.5)
    poly = Polygon(_ccw(ring)).buffer(.15, join_style=2)
    m.prism(list(poly.exterior.coords)[:-1], 2.9, 3.9, 'sign', C['blue'], 'plain', C['blue'], top=False)


def t_fire(m, ring, ctx, p):
    h = p.get('h', 7.0)
    ring = _ccw(ring)
    m.prism(ring, 0, 4.4, 'louvre', C['red'], 'plain', C['red'], top=False)
    m.prism(ring, 4.4, h, 'windows', C['white'], 'plain', C['grey'], top=True)


def t_prayer(m, ring, ctx, p):
    h = p.get('h', 5.0)
    m.prism(ring, 0, h, 'arches', C['white'], 'plain', C['white'], top=True)
    cx, cy, L, W, th = ctx['cx'], ctx['cy'], ctx['L'], ctx['W'], ctx['th']
    r = min(L, W) * .3
    m.cylinder(cx, cy, h, h + 1.2, r, 'plain', C['white'], seg=16)
    m.dome(cx, cy, h + 1.2, r, r * .9, 'plain', C['green'], seg=20)


def t_generic(m, ring, ctx, p):
    h = p.get('h', 7.0)
    m.prism(ring, 0, h, 'windows', p.get('col', C['cream']), 'sheet', C['grey'], top=True)


TEMPLATES = dict(shrine=t_shrine, chapel=t_chapel, terminal=t_terminal, mall=t_mall, hospital=t_hospital, school=t_school, psca=t_psca, shop=t_shop,
                 hall=t_hall, tower=t_tower, police=t_police, fire=t_fire, prayer=t_prayer, generic=t_generic)

# landmark name -> (template, parameters). Heights are for a model that stands where the OSM building stands; where the photos
# say more (colours, floors, fittings) it is written here.
SPECS = [
    (r'Shrine', 'shrine', {'h': 11.5}),
    (r'Our Lady of Loreto|Chapel', 'chapel', {'h': 6.0}),
    (r'Philippines State College|Aeronautics', 'psca', {'h': 12.0}),
    (r'NAIA Terminal 3', 'terminal', {'h': 17.0, 'canopy': 9.0, 'plant': 5, 'wall': 'glass', 'col': C['glass']}),
    (r'Terminal 2 (North|South) Wing|NAIA Centennial', 'terminal', {'h': 11.0, 'canopy': 7.0, 'plant': 4}),
    (r'Bureau of Immigration', 'terminal', {'h': 13.0, 'canopy': 6.0, 'plant': 3}),
    (r'^Newport Mall', 'mall', {'h': 18.0, 'col': C['peach'], 'trim': C['cream']}),
    (r'Eighty One Mall', 'mall', {'h': 20.0, 'col': C['sand'], 'trim': C['cream']}),
    (r"Airmen's Mall|Post Exchange", 'mall', {'h': 9.0, 'col': C['cream'], 'trim': C['white']}),
    (r'Metro Supermarket', 'mall', {'h': 16.0, 'col': C['sand'], 'base': C['cream'], 'trim': C['peach']}),
    (r'Hospital', 'hospital', {'h': 22.0, 'band': C['blue']}),
    (r'Elementary School|High School|Office School|School', 'school', {'h': 9.0, 'roof': C['green']}),
    (r'Barangay 183 Hall', 'hall', {'h': 7.0}),
    (r'Police', 'police', {'h': 6.5}),
    (r'Fire Station', 'fire', {'h': 7.5}),
    (r'Prayer Room', 'prayer', {'h': 5.0}),
    (r'Church of God', 'tower', {'h': 48.0}),
    (r'Watsons', 'shop', {'h': 6.5, 'sign': C['teal']}),
    (r'LBC', 'shop', {'h': 6.5, 'sign': C['red']}),
    (r'TGP', 'shop', {'h': 6.0, 'sign': C['orange']}),
    (r'Zoe', 'shop', {'h': 6.0, 'sign': C['rose']}),
    (r'Royal Air Charter', 'shop', {'h': 6.0, 'sign': C['navy']}),
    (r'Finance Center|Aviation Security|PNP', 'generic', {'h': 8.0, 'col': C['white']}),
]


def match_building(bld, lng, lat):
    """The building the landmark's point is in, else the nearest within 28 m (a big building may be far, by its middle, from the point)."""
    pt = Point(lng * MX, lat * MY)
    best, bd = None, 28.0
    for i, b in enumerate(bld):
        r = b[0]
        xs, ys = r[0::2], r[1::2]
        if lng < min(xs) - .0004 or lng > max(xs) + .0004 or lat < min(ys) - .0004 or lat > max(ys) + .0004:
            continue
        poly = Polygon([(r[k] * MX, r[k + 1] * MY) for k in range(0, len(r), 2)])
        if not poly.is_valid:
            poly = poly.buffer(0)
        d = 0.0 if poly.contains(pt) else poly.distance(pt)
        if d < bd:
            best, bd = i, d
    return best


def main():
    bdoc = json.load(open(os.path.join(MAP, 'buildings.json'), encoding='utf-8'))
    bld = bdoc['b']
    lms = json.load(open(os.path.join(MAP, 'landmarks.geojson'), encoding='utf-8'))['features']
    allpolys = [Polygon([(b[0][k] * MX, b[0][k + 1] * MY) for k in range(0, len(b[0]), 2)]).buffer(0) for b in bld]
    models, V, I = [], [], []
    taken, done = set(), set()
    voff = ioff = 0
    for f in sorted(lms, key=lambda f: 0 if 'Terminal 3' in f['properties']['name'] else 1):   # the biggest building belongs to Terminal 3
        name = f['properties']['name']
        if name in done:
            continue
        spec = next(((t, p) for pat, t, p in SPECS if re.search(pat, name)), None)
        if not spec:
            continue
        lng, lat = f['geometry']['coordinates']
        bi = match_building(bld, lng, lat)
        if bi is None or bi in taken:
            print('  no building for', name)
            continue
        taken.add(bi)
        done.add(name)
        b = bld[bi]
        lng0, lat0 = b[4], b[5]
        ring = local_ring(b, lng0, lat0)
        ctx = dict(cx=0.0, cy=0.0, L=b[6], W=b[7], th=b[8])
        # the model's own frame is centred on the footprint's middle: shift the ring so its OBB centre is the origin
        ox = sum(p[0] for p in ring) / len(ring)
        oy = sum(p[1] for p in ring) / len(ring)
        ring = [(p[0] - ox, p[1] - oy) for p in ring]
        lng0 += ox / MX
        lat0 += oy / MY
        tname, params = spec
        params = dict(params)
        if len(b) > 9 and not b[9]:
            params['h'] = round(float(b[1]), 1)    # OpenStreetMap or Overture knows this building's real height: it wins over the template's guess
            print('    (real height %.1f m)' % b[1])
        others = [Polygon([(q[0] - lng0 * MX, q[1] - lat0 * MY) for q in allpolys[j].exterior.coords]) for j in range(len(bld)) if j != bi and abs(bld[j][4] - lng0) < .0009 and abs(bld[j][5] - lat0) < .0009]
        ctx['side'] = _free_side(ctx, _ccw(ring), others)
        ctx['others'] = others
        m = Mesh()
        TEMPLATES[tname](m, ring, ctx, dict(params))
        P, N, U, M, Cc, Ix = m.arrays()
        if not len(P):
            continue
        height = float(P[:, 2].max())
        models.append({'name': name, 'template': tname, 'lng': lng0, 'lat': lat0, 'replaces': bi, 'height': round(height, 1), 'v': int(len(P)), 'i': int(len(Ix)), 'voff': voff, 'ioff': ioff})
        V.append((P, U, M, Cc, N))
        I.append(Ix)
        voff += len(P)
        ioff += len(Ix)
        print('%-42s %-9s %6d vertices %6d triangles  h %.0f m' % (name, tname, len(P), len(Ix) // 3, height))
    # street lamps: a pole and a lamp head for every lamp (city-detail.json), as one more model at the middle of the map
    det = json.load(open(os.path.join(MAP, 'city-detail.json'), encoding='utf-8'))
    lamps = det.get('lamps', [])
    if lamps:
        lng0, lat0 = 121.0135, 14.5240
        m = Mesh()
        for lng, lat, br, white in lamps:
            x, y = (lng - lng0) * MX, (lat - lat0) * MY
            sq = [(x - .09, y - .09), (x + .09, y - .09), (x + .09, y + .09), (x - .09, y + .09)]
            m.prism(sq, 0, 7.2, 'plain', C['slate'], 'plain', C['slate'], top=False, cell=8.0)
            head = C['yellow'] if not white else rgb('D8E6FF')
            m.prism([(x - .30, y - .16), (x + .30, y - .16), (x + .30, y + .16), (x - .30, y + .16)], 7.2, 7.4, 'sign', head, 'sign', head, top=True, cell=3.0)
        P, N, U, M, Cc, Ix = m.arrays()
        models.append({'name': 'Street lamps', 'template': 'furniture', 'furniture': True, 'lng': lng0, 'lat': lat0, 'replaces': -1, 'height': 7.4, 'v': int(len(P)), 'i': int(len(Ix)), 'voff': voff, 'ioff': ioff})
        V.append((P, U, M, Cc, N))
        I.append(Ix)
        voff += len(P)
        ioff += len(Ix)
        print('%-42s %-9s %6d vertices %6d triangles' % ('Street lamps (%d)' % len(lamps), 'furniture', len(P), len(Ix) // 3))
    # elevated roads, walkways, the rail viaduct, walls, bus shelters, signals, flagpoles, water towers: what OpenStreetMap maps in the zone
    import infra
    from boundary import Boundary
    lng0, lat0 = 121.0135, 14.5240
    m = Mesh()
    infra.build(m, (lng0, lat0), Boundary())
    P, N, U, M, Cc, Ix = m.arrays()
    if len(P):
        models.append({'name': 'Infrastructure', 'template': 'furniture', 'furniture': True, 'lng': lng0, 'lat': lat0, 'replaces': -1, 'height': float(P[:, 2].max()), 'v': int(len(P)), 'i': int(len(Ix)), 'voff': voff, 'ioff': ioff})
        V.append((P, U, M, Cc, N))
        I.append(Ix)
        voff += len(P)
        ioff += len(Ix)
        print('%-42s %-9s %6d vertices %6d triangles' % ('Infrastructure', 'furniture', len(P), len(Ix) // 3))
    # one binary: vertices (x y z u v as float32, mat r g b as uint8) then triangles (uint32)
    vb = bytearray()
    for P, U, M, Cc, N in V:
        rec = np.zeros(len(P), dtype=[('p', '<f4', 3), ('uv', '<f4', 2), ('m', 'u1'), ('c', 'u1', 3)])
        rec['p'], rec['uv'], rec['m'], rec['c'] = P, U, M, Cc
        vb += rec.tobytes()
    ib = b''.join(np.asarray(x, dtype='<u4').tobytes() for x in I)
    os.makedirs(os.path.join(HERE, 'work'), exist_ok=True)
    raw = bytes(vb) + ib
    open(os.path.join(HERE, 'work', 'landmarks3d.bin'), 'wb').write(raw)     # for the baker
    import gzip
    open(os.path.join(MAP, 'landmarks3d.bin.gz'), 'wb').write(gzip.compress(raw, 9))     # what the page loads (the browser unzips it)
    if os.path.exists(os.path.join(MAP, 'landmarks3d.bin')):
        os.remove(os.path.join(MAP, 'landmarks3d.bin'))
    # the normals, for the baker only
    np.concatenate([n for *_, n in V]).astype('<f4').tofile(os.path.join(HERE, 'work', 'normals.f32')) if V else None
    A, E, rects = atlas.build(MAP)
    A.save(os.path.join(MAP, 'landmarks3d-atlas.png'), optimize=True)
    E.save(os.path.join(MAP, 'landmarks3d-emis.png'), optimize=True)
    meta = {'about': 'Landmark models drawn by docs/map-data/landmarks/models.py. Vertex: float32 x y z (metres, east north up from the model origin), float32 u v (tile units), uint8 material, uint8 r g b (albedo); 24 bytes. Then uint32 triangle indices, per model offset by voff.',
            'vertexBytes': 24, 'vertices': voff, 'indices': ioff, 'indexOffsetBytes': voff * 24, 'tiles': rects, 'models': models}
    json.dump(meta, open(os.path.join(MAP, 'landmarks3d.json'), 'w'), separators=(',', ':'))
    print('wrote landmarks3d.json/.bin:', len(models), 'models,', voff, 'vertices,', ioff // 3, 'triangles,', os.path.getsize(os.path.join(MAP, 'landmarks3d.bin.gz')) // 1024, 'KB zipped')


main()
