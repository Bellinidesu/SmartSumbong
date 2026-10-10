"""
Every building of the Newport - NAIA zone as a model, by what it is: a hotel (a podium and a tower, a porte-cochere, a crown), a condominium (windows,
a balcony on every floor, a crown), an office tower (a glass curtain wall), a mall, a parking deck (open floors, ramp ends), an aircraft hangar (a
barrel roof and a door). What each is comes from its name and its class (Overture, OpenStreetMap), and, where neither says, from its size and
where it stands; its height from floors (num_floors, building:levels) or height tags where known, and from facts.py where a source says.

Colours are the barangay's pastels, picked from the building's own place so that no two neighbours match, but a hotel's tower stays one colour.
"""
import colorsys
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


# What a building is, in plain colour (the map's own pastels, one for each kind), and the model that stands for it
TYPECOL = dict(gas='F4F1EA', worship='EBC9A8', school='F2D98A', health='E6F0EE', safety='B9C9E0', civic='EBA7A4', shop='E8C9A0', mall='E3CFA6', hotel='C9D3E0', hangar='D9DBE0',
               warehouse='D2D4D8', parking='9CA3B5', office='C6D2E0', condo='E7DCC4', terminal='E3E6EC')
KIND_OF_TYPE = dict(gas='gas', worship='church', school='school', health='civic', safety='civic', civic='civic', shop='generic', mall='mall', hotel='hotel', parking='parking', hangar='hangar',
                    warehouse='hangar', office='office', condo='condo', terminal='mall')


def seen(ctx, pool, salt=0):
    """The building's own wall colour as the street shows it (tools/stylise.py reads it from Mapillary's 360 panoramas), drawn in our palette: the hue
    it really has, softened to a pastel, light as our baked shading wants it. Where nothing was seen, the barangay's pastel for that place."""
    if ctx.get('tcol'):
        return rgb(ctx['tcol'])
    st = ctx.get('style')
    if st and st.get('wall'):
        r, g, b = [max(0, min(255, v)) / 255 for v in st['wall']]
        hh, ll, ss = colorsys.rgb_to_hls(r, g, b)
        ll = .60 + .34 * ll
        ss = min(.40, ss * 1.15 + .03)
        return rgb('%02X%02X%02X' % tuple(int(round(v * 255)) for v in colorsys.hls_to_rgb(hh, ll, ss)))
    return pick(ctx, pool, salt)


def glass_of(ctx, default):
    st = ctx.get('style')
    return st['glass'] if st and st.get('glass') is not None else default


def body_style(ctx, default_pool, salt):
    """What the upper floors look like: mostly glass (a curtain wall), mostly wall with windows, or in between, as the street shows it."""
    g = glass_of(ctx, None)
    if g is None:
        return pick(ctx, default_pool, salt)
    if g >= .50:
        return 'glass'
    if g >= .33:
        return 'ribbon'
    if g >= .20:
        return 'windows'
    return 'slots'


def looked(ctx, mat, salt=0):
    """One of the four looks of a glazed material (atlas.py), by the building: which panes are lit at night, how the panes differ by day.
    Hotels lean to the busier looks, offices to the emptier."""
    if mat not in ('windows', 'ribbon', 'glass', 'slots', 'strip'):
        return mat
    k = zlib.crc32(('%.5f,%.5f,%d,w' % (ctx['lng'], ctx['lat'], salt)).encode()) % 4
    return mat if k == 0 else '%s%d' % (mat, k)


def floors_of(h):
    return max(2, int(round((h - 1.2) / 3.4)))


def crown(m, ring, h, ctx, col, big=True):
    """A cornice band, a setback of mechanical floor with louvres, and rooftop plant."""
    poly = Polygon(ring).buffer(.4, join_style=2)
    if h >= 34 and ctx.get('glow', True):
        # a tall tower's crown is a band of light at night (violet, teal, amber or blue by the building), a plain cornice by day
        m.prism(list(poly.exterior.coords)[:-1], h - 2.6, h + .5, 'glow%d' % (zlib.crc32(('%.5f,%.5f,g' % (ctx['lng'], ctx['lat'])).encode()) % 4), C['white'], 'roofdeck', C['white'], top=True, cell=4)
    else:
        m.prism(list(poly.exterior.coords)[:-1], h - 1.2, h + .5, 'plain', col, 'roofdeck', C['white'], top=True, cell=4)
    inner = Polygon(ring).buffer(-3.2, join_style=2)
    if big and not inner.is_empty and inner.geom_type == 'Polygon' and inner.area > 120:
        m.prism(list(inner.exterior.coords)[:-1], h + .5, h + 4.2, 'louvre', C['grey'], 'roofdeck', C['white'], top=True, cell=4)
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
    base = seen(ctx, PASTELS, 1)
    gh = min(6.0, h * .3)
    m.prism(ring, 0, gh, 'shop', C['white'], 'plain', base, top=False, cell=4)
    m.grade = (gh, h - 1.2, .22)
    m.prism(ring, gh, h - 1.2, looked(ctx, body_style(ctx, ['windows', 'strip', 'slots'], 11), 11), base, 'plain', base, top=False, cell=4)
    crown(m, ring, h, ctx, pick(ctx, ACCENT, 2))
    porte_cochere(m, ring, ctx, h)


def z_condo(m, ring, ctx, p):
    h = p['h']
    ring = _ccw(ring)
    col = seen(ctx, PASTELS, 3)
    m.prism(ring, 0, 4.6, 'shop', C['white'], 'plain', col, top=False, cell=4)
    m.grade = (4.6, h - 1.2, .22)
    m.prism(ring, 4.6, h - 1.2, looked(ctx, body_style(ctx, ['windows', 'strip', 'slots', 'windows'], 12), 12), col, 'plain', col, top=False, cell=4)
    crown(m, ring, h, ctx, pick(ctx, ACCENT, 4))


def z_office(m, ring, ctx, p):
    h = p['h']
    ring = _ccw(ring)
    m.prism(ring, 0, 5.0, 'ribbon', C['glass'], 'plain', C['grey'], top=False, cell=4)
    m.grade = (5.0, h - 1.2, .30)
    m.prism(ring, 5.0, h - 1.2, looked(ctx, 'glass', 5), seen(ctx, [C['glass'], rgb('C6D2E0'), rgb('B3C4D6')], 5), 'plain', C['grey'], top=False, cell=4)
    crown(m, ring, h, ctx, C['slate'])


def z_mall(m, ring, ctx, p):
    h = p['h']
    ring = _ccw(ring)
    col = seen(ctx, PASTELS, 6)
    gh = min(6.0, h * .45)
    m.prism(ring, 0, gh, 'shop', C['white'], 'plain', col, top=False, cell=4)
    m.prism(ring, gh, h - .6, looked(ctx, 'ribbon', 6) if h > 12 else 'plain', col, 'plain', col, top=False, cell=4)
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
    m.cap(ring, h, MAT['roofdeck'], C['white'], True)


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
    col = seen(ctx, PASTELS, 8)
    m.prism(ring, 0, h, looked(ctx, 'windows', 8) if h > 5 else 'panel', col, 'roofdeck', C['white'], top=True, cell=4)
    if Polygon(ring).area > 300:
        poly = Polygon(ring).buffer(.25, join_style=2)
        m.prism(list(poly.exterior.coords)[:-1], h - .5, h + .6, 'plain', C['white'], 'plain', C['white'], top=True, cell=5)


def z_gas(m, ring, ctx, p):
    """A filling station: a flat canopy on columns over the forecourt, a red band on its edge, two pump islands under it, a small kiosk at one end."""
    L, W, th, cx, cy = ctx['L'], ctx['W'], ctx['th'], ctx['cx'], ctx['cy']
    c, s_ = math.cos(th), math.sin(th)
    big = L > 14 and W > 9
    cl, cw = (min(L, 26.0), min(W, 14.0)) if big else (max(L, 9.0), max(W, 7.0))
    z = 5.2
    m.slab(cx, cy, cl, cw, th, z, .5, C['white'])
    m.box(cx, cy, z + .5, cl, .25, .45, th, 'plain', C['red'], 'plain', C['red'], True, 40.0) if False else None
    for sx in (-1, 1):
        for sy in (-1, 1):
            m.column(cx + c * sx * (cl / 2 - 1.0) - s_ * sy * (cw / 2 - 1.0), cy + s_ * sx * (cl / 2 - 1.0) + c * sy * (cw / 2 - 1.0), 0, z, .3, C['white'])
    for sy in (-1, 1):                                      # the red band along both long edges, and two pump islands
        m.box(cx - s_ * sy * (cw / 2), cy + c * sy * (cw / 2), z + .5, cl, .3, .5, th, 'plain', C['red'], 'plain', C['red'], True, 40.0)
        m.box(cx - s_ * sy * (cw * .22), cy + c * sy * (cw * .22), 0, cl * .6, 1.0, .35, th, 'plain', C['grey'], 'plain', C['grey'], True, 40.0)
    kx, ky = cx + c * (cl / 2 + 2.6), cy + s_ * (cl / 2 + 2.6)
    m.box(kx, ky, 0, 5.0, 4.0, 3.2, th, 'plain', C['white'], 'roofdeck', C['grey'], True, 40.0)


def z_church(m, ring, ctx, p):
    """A church: a nave under a gabled roof, a square bell tower with a pointed top at the front end, a cross."""
    h = max(p['h'], 7.0)
    ring = _ccw(ring)
    col = seen(ctx, PASTELS, 21)
    m.prism(ring, 0, h, 'plain', col, 'plain', col, top=False, cell=5)
    L, W, th, cx, cy = ctx['L'], ctx['W'], ctx['th'], ctx['cx'], ctx['cy']
    m.gable(cx, cy, L, W, th, h, min(4.5, W * .32), 'tile', C['terra'], over=.4, gable_col=col)
    c, s_ = math.cos(th), math.sin(th)
    tx, ty = cx + c * (L / 2 - 2.2), cy + s_ * (L / 2 - 2.2)
    th_ = h + min(4.0, h * .5)                                 # the tower stands above the nave in proportion, not by a fixed amount
    m.box(tx, ty, 0, 3.6, 3.6, th_, th, 'plain', col, 'plain', col, True, 6.0)
    m.hip(tx, ty, 3.6, 3.6, th, th_, 3.0, 'tile', C['terra'], over=.2)
    m.cylinder(tx, ty, th_ + 2.8, th_ + 4.4, .1, 'plain', C['yellow'], seg=6)


def z_school(m, ring, ctx, p):
    """A school: a long low block of classrooms with a ribbon of windows, a low hipped roof."""
    h = p['h']
    ring = _ccw(ring)
    col = seen(ctx, PASTELS, 22)
    m.prism(ring, 0, h, 'plain', col, 'plain', col, top=False, cell=5)
    m.hip(ctx['cx'], ctx['cy'], ctx['L'], ctx['W'], ctx['th'], h, min(2.4, ctx['W'] * .18), 'sheet', C['rooftile'], over=.5)


def z_civic(m, ring, ctx, p):
    """A civic or health building: a plain block with a flat roof and a coloured parapet."""
    h = p['h']
    ring = _ccw(ring)
    col = seen(ctx, PASTELS, 23)
    m.prism(ring, 0, h, 'plain', col, 'roofdeck', C['white'], top=True, cell=5)
    poly = Polygon(ring).buffer(.25, join_style=2)
    m.prism(list(poly.exterior.coords)[:-1], h - .5, h + .6, 'plain', C['white'], 'plain', C['white'], top=True, cell=5)


TEMPLATES = dict(gas=z_gas, church=z_church, school=z_school, civic=z_civic, hotel=z_hotel, condo=z_condo, office=z_office, mall=z_mall, parking=z_parking, hangar=z_hangar, generic=z_generic)


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
