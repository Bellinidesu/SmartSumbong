"""
Every building of the Newport - NAIA zone as a model, by what it is: a hotel (a podium and a tower, a porte-cochere, a crown), a condominium (windows,
a balcony on every floor, a crown), an office tower (a glass curtain wall), a mall, a parking deck (open floors, ramp ends), an aircraft hangar (a
barrel roof and a door). What each is comes from its name and its class (Overture, OpenStreetMap), and, where neither says, from its size and
where it stands; its height from floors (num_floors, building:levels) or height tags where known, and from facts.py where a source says.

Colours are the barangay's pastels, picked from the building's own place so that no two neighbours match, but a hotel's tower stays one colour.
"""
import math
import re
import zlib

from shapely.geometry import Polygon

from meshlib import MAT, rgb, _ccw
from models_common import C, front_of

PASTELS = [C['cream'], C['peach'], C['sand'], C['rose'], C['white'], rgb('DCE6EA'), rgb('E7DCC4'), rgb('D9E5DB')]
ACCENT = [C['blue'], C['teal'], C['navy'], C['terra'], C['green'], C['slate']]


def pick(ctx, pool, salt=0):
    return pool[zlib.crc32(('%.5f,%.5f,%d' % (ctx['lng'], ctx['lat'], salt)).encode()) % len(pool)]


def floors_of(h):
    return max(2, int(round((h - 1.2) / 3.4)))


def crown(m, ring, h, ctx, col, big=True):
    """A cornice band, a setback of mechanical floor with louvres, and rooftop plant."""
    poly = Polygon(ring).buffer(.4, join_style=2)
    m.prism(list(poly.exterior.coords)[:-1], h - 1.2, h + .5, 'plain', col, 'sheet', C['sheetwhite'], top=True, cell=4)
    inner = Polygon(ring).buffer(-3.2, join_style=2)
    if big and not inner.is_empty and inner.geom_type == 'Polygon' and inner.area > 120:
        m.prism(list(inner.exterior.coords)[:-1], h + .5, h + 4.2, 'louvre', C['grey'], 'plain', C['grey'], top=True, cell=4)
        for k in range(min(4, int(inner.area // 400) + 1)):
            u = zlib.crc32(('%d%.4f' % (k, ctx['lng'])).encode()) % 100 / 100 - .5
            v = zlib.crc32(('%d%.4f' % (k + 9, ctx['lat'])).encode()) % 100 / 100 - .5
            m.box(ctx['cx'] + u * ctx['L'] * .5 * math.cos(ctx['th']) - v * ctx['W'] * .5 * math.sin(ctx['th']), ctx['cy'] + u * ctx['L'] * .5 * math.sin(ctx['th']) + v * ctx['W'] * .5 * math.cos(ctx['th']),
                  h + 4.2, 3.2, 2.4, 1.6, ctx['th'], 'louvre', C['grey'], 'plain', C['grey'])
    else:
        for k in range(min(3, int(Polygon(ring).area // 500) + 1)):
            m.box(ctx['cx'] + (k - 1) * ctx['L'] * .2 * math.cos(ctx['th']), ctx['cy'] + (k - 1) * ctx['L'] * .2 * math.sin(ctx['th']), h + .5, 3.0, 2.2, 1.5, ctx['th'], 'louvre', C['grey'], 'plain', C['grey'])


def porte_cochere(m, ring, ctx, h):
    fr, half, across, along = front_of(ctx)
    nx, ny = fr
    ux, uy = along
    w = min(11.0, across * 1.2)
    cx, cy = ctx['cx'] + nx * (half + 3.2), ctx['cy'] + ny * (half + 3.2)
    th = math.atan2(uy, ux)
    m.slab(cx, cy, w, 6.4, th, 4.6, .45, C['white'])
    for sgn in (-1, 1):
        m.column(cx + ux * sgn * (w / 2 - .5) + nx * 2.4, cy + uy * sgn * (w / 2 - .5) + ny * 2.4, 0, 4.6, .3, C['white'])


def balconies(m, ring, ctx, h, col):
    """A balcony slab and rail on every floor, on the two long sides: a thin box a metre out from the wall."""
    L, W, th = ctx['L'], ctx['W'], ctx['th']
    c, s = math.cos(th), math.sin(th)
    n = floors_of(h)
    for f in range(1, n):
        z = 1.2 + f * 3.4 - .15
        for side in (-1, 1):
            cx, cy = ctx['cx'] - side * (W / 2 + .45) * s, ctx['cy'] + side * (W / 2 + .45) * c
            m.box(cx, cy, z, L * .86, 1.0, .18, th, 'plain', col, 'plain', col)
            m.box(cx - side * .5 * s, cy + side * .5 * c, z + .18, L * .86, .06, .9, th, 'glass', C['glass'], 'plain', C['glass'])


def z_hotel(m, ring, ctx, p):
    h = p['h']
    ring = _ccw(ring)
    base = pick(ctx, PASTELS, 1)
    gh = min(6.0, h * .3)
    m.prism(ring, 0, gh, 'shop', C['white'], 'plain', base, top=False, cell=4)
    m.prism(ring, gh, h - 1.2, 'windows', base, 'plain', base, top=False, cell=4)
    crown(m, ring, h, ctx, pick(ctx, ACCENT, 2))
    porte_cochere(m, ring, ctx, h)


def z_condo(m, ring, ctx, p):
    h = p['h']
    ring = _ccw(ring)
    col = pick(ctx, PASTELS, 3)
    m.prism(ring, 0, 4.6, 'shop', C['white'], 'plain', col, top=False, cell=4)
    m.prism(ring, 4.6, h - 1.2, 'windows', col, 'plain', col, top=False, cell=4)
    if ctx['L'] > 18:
        balconies(m, ring, ctx, h, C['white'])
    crown(m, ring, h, ctx, pick(ctx, ACCENT, 4))


def z_office(m, ring, ctx, p):
    h = p['h']
    ring = _ccw(ring)
    m.prism(ring, 0, 5.0, 'ribbon', C['glass'], 'plain', C['grey'], top=False, cell=4)
    m.prism(ring, 5.0, h - 1.2, 'glass', pick(ctx, [C['glass'], rgb('C6D2E0'), rgb('B3C4D6')], 5), 'plain', C['grey'], top=False, cell=4)
    crown(m, ring, h, ctx, C['slate'])


def z_mall(m, ring, ctx, p):
    h = p['h']
    ring = _ccw(ring)
    col = pick(ctx, PASTELS, 6)
    gh = min(6.0, h * .45)
    m.prism(ring, 0, gh, 'shop', C['white'], 'plain', col, top=False, cell=4)
    m.prism(ring, gh, h - .6, 'ribbon' if h > 12 else 'plain', col, 'plain', col, top=False, cell=4)
    crown(m, ring, h, ctx, C['cream'], big=False)


def z_parking(m, ring, ctx, p):
    """A parking deck: open floors behind louvre, a slab edge at every floor, a sign band."""
    h = p['h']
    ring = _ccw(ring)
    n = max(2, int(round(h / 3.0)))
    step = h / n
    for f in range(n):
        m.prism(ring, f * step + .9, (f + 1) * step - .15, 'louvre', C['grey'], 'plain', C['grey'], top=False, cell=4)
        poly = Polygon(ring).buffer(.12, join_style=2)
        m.prism(list(poly.exterior.coords)[:-1], f * step, f * step + .9, 'plain', C['pier'] if 'pier' in C else C['grey'], 'plain', C['grey'], top=False, cell=4)
    m.cap(ring, h, MAT['plain'], C['grey'], True)


def z_hangar(m, ring, ctx, p):
    h = p.get('wall', 9.0)
    ring = _ccw(ring)
    m.prism(ring, 0, h, 'panel', C['sheetwhite'], 'plain', C['grey'], top=False, cell=5)
    cx, cy, L, W, th = ctx['cx'], ctx['cy'], ctx['L'], ctx['W'], ctx['th']
    m.barrel(cx, cy, L, W, th, h, min(W * .28, 6.0), 'sheet', C['roofgrey'], seg=10)
    fr, half, across, along = front_of(ctx)
    m.vprism([(-across * .8, 0), (across * .8, 0), (across * .8, h * .85), (-across * .8, h * .85)], (ctx['cx'] + fr[0] * (half + .08), ctx['cy'] + fr[1] * (half + .08), 0), along, fr, 0, .3, 'panel', C['slate'])


def z_generic(m, ring, ctx, p):
    h = p['h']
    ring = _ccw(ring)
    col = pick(ctx, PASTELS, 8)
    m.prism(ring, 0, h, 'windows' if h > 5 else 'panel', col, 'sheet', C['grey'], top=True, cell=4)
    if Polygon(ring).area > 300:
        poly = Polygon(ring).buffer(.25, join_style=2)
        m.prism(list(poly.exterior.coords)[:-1], h - .5, h + .6, 'plain', C['white'], 'plain', C['white'], top=True, cell=5)


TEMPLATES = dict(hotel=z_hotel, condo=z_condo, office=z_office, mall=z_mall, parking=z_parking, hangar=z_hangar, generic=z_generic)


def kind_of(name, cls, area, h, floors, lng, lat):
    n = (name or '').lower()
    if re.search(r'hangar', n):
        return 'hangar'
    if re.search(r'hotel|marriott|marriot|hilton|sheraton|okura|belmont|holiday inn|savoy|resort|inn\b', n) or cls == 'hotel':
        return 'hotel'
    if re.search(r'park(ing)?|carpark', n) or cls == 'parking':
        return 'parking'
    if re.search(r'mall|plaza|centre|center|market|theat|casino|grand wing|store|runway', n) or cls in ('retail',):
        return 'mall'
    if re.search(r'tower|residen|condo|mansion|villas|suites|place', n) or cls in ('apartments', 'residential'):
        return 'condo'
    if re.search(r'office|building|headquarters|hq|bank|institute|centre', n) or cls in ('commercial', 'office'):
        return 'office'
    if area >= 1500 and h <= 16 and not (121.0140 < lng):
        return 'hangar'       # a wide low shed by the airport is a hangar or a warehouse
    if h >= 24:
        return 'condo' if area < 2200 else 'hotel'
    if area >= 900:
        return 'mall'
    return 'generic'
