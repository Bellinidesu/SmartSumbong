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

from shapely.geometry import Point, Polygon

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


def front_on_edge(ring, ctx):
    """Where the front of a building really is: the OBB's front point (front_of) moved onto the footprint's own edge, with the unit vector out of the building there. An L-shaped or
    curved footprint has no front at its bounding box, so a canopy or a door put there would stand in the air or in the street."""
    from shapely.geometry import Point as _P
    fr, half, across, along = front_of(ctx)
    poly = Polygon(ring)
    c = _P(ctx['cx'] + fr[0] * half, ctx['cy'] + fr[1] * half)
    ex = poly.exterior
    q = ex.interpolate(ex.project(c))
    nx, ny = c.x - q.x, c.y - q.y
    ln = math.hypot(nx, ny)
    if ln < .5:
        nx, ny = fr
    else:
        nx, ny = nx / ln, ny / ln
        if poly.contains(_P(q.x + nx * .5, q.y + ny * .5)):
            nx, ny = -nx, -ny
    return (q.x, q.y), (nx, ny), (-ny, nx), across


QUIET = None          # a shapely polygon in degrees, set by models.py: no entrance, porch or flagpole is added to a building inside it


def entrance(m, ring, ctx, depth, width, zc, col, roof_col=None, pole=0.0, keep=False):
    """A porch or portico on the footprint's own front edge: a slab roof on four columns, two steps, a dark door, and optionally a flagpole beside it."""
    if QUIET is not None and not keep and ctx.get('lng') is not None and QUIET.contains(Point(ctx['lng'], ctx['lat'])):
        return
    (qx, qy), fr, al, across = front_on_edge(ring, ctx)
    width = max(3.0, min(width, across * 1.6))
    tf = math.atan2(al[1], al[0])
    mx, my = qx + fr[0] * depth / 2, qy + fr[1] * depth / 2
    m.slab(mx, my, width, depth, tf, zc, .45, col)
    for sx in (-1, 1):
        m.column(qx + fr[0] * (depth - .45) + al[0] * sx * (width / 2 - .45), qy + fr[1] * (depth - .45) + al[1] * sx * (width / 2 - .45), 0, zc, .24, C['white'])
    if width > 6.5:
        for sx in (-.33, .33):
            m.column(qx + fr[0] * (depth - .45) + al[0] * sx * width, qy + fr[1] * (depth - .45) + al[1] * sx * width, 0, zc, .24, C['white'])
    m.box(qx + fr[0] * (depth + .35), qy + fr[1] * (depth + .35), 0, width * .8, .7, .3, tf, 'plain', C['grey'], 'plain', C['grey'], True, 40.0)
    m.box(qx + fr[0] * (depth + .8), qy + fr[1] * (depth + .8), 0, width * .6, .6, .15, tf, 'plain', C['grey'], 'plain', C['grey'], True, 40.0)
    m.vprism([(-.9, 0), (.9, 0), (.9, 2.2), (-.9, 2.2)], (qx + fr[0] * .06, qy + fr[1] * .06, 0), al, fr, 0, .25, 'panel', C['slate'])
    if pole:
        px, py = qx + fr[0] * (depth + 1.6) + al[0] * (width / 2 + 1.4), qy + fr[1] * (depth + 1.6) + al[1] * (width / 2 + 1.4)
        m.cylinder(px, py, 0, pole, .09, 'plain', C['grey'], seg=6)
        m.box(px + al[0] * .5, py + al[1] * .5, pole - 1.3, 1.0, .05, .7, tf, 'plain', C['red'], 'plain', C['red'], True, 40.0)


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
            px_, py_ = ctx['cx'] + u * ctx['L'] * .5 * math.cos(ctx['th']) - v * ctx['W'] * .5 * math.sin(ctx['th']), ctx['cy'] + u * ctx['L'] * .5 * math.sin(ctx['th']) + v * ctx['W'] * .5 * math.cos(ctx['th'])
            if inner.contains(Point(px_, py_)):
                m.box(px_, py_, h + 4.2, 3.2, 2.4, 1.6, ctx['th'], 'louvre', C['grey'], 'plain', C['grey'])
    else:
        for k in range(min(3, int(Polygon(ring).area // 500) + 1)):
            qx_, qy_ = ctx['cx'] + (k - 1) * ctx['L'] * .2 * math.cos(ctx['th']), ctx['cy'] + (k - 1) * ctx['L'] * .2 * math.sin(ctx['th'])
            if Polygon(ring).buffer(-1.5).contains(Point(qx_, qy_)):
                m.box(qx_, qy_, h + .5, 3.0, 2.2, 1.5, ctx['th'], 'louvre', C['grey'], 'plain', C['grey'])


def porte_cochere(m, ring, ctx, h):
    (qx, qy), (nx, ny), (ux, uy), across = front_on_edge(ring, ctx)
    w = min(11.0, across * 1.2)
    cx, cy = qx + nx * 3.2, qy + ny * 3.2
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
    if Polygon(ring).area / max(L * W, 1) > .93:                      # a barrel roof over the bounding box only where the footprint is nearly a rectangle (it stood 25 m off a bent one)
        m.barrel(cx, cy, L, W, th, h, min(W * .28, 6.0), 'sheet', C['roofgrey'], seg=10)
    else:
        m.cap(ring, h, MAT['roofdeck'], C['roofgrey'], True)
    (qx, qy), fr, along, across = front_on_edge(ring, ctx)
    dw = min(across * .8, 7.0)                                       # a hangar door is 14 m wide at most, however wide the bounding box of a bent footprint is
    m.vprism([(-dw, 0), (dw, 0), (dw, h * .85), (-dw, h * .85)], (qx + fr[0] * .08, qy + fr[1] * .08, 0), along, fr, 0, .3, 'panel', C['slate'])


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
    for sy in (-1, 1):                                      # the pumps: three on each island
        for k in (-1, 0, 1):
            m.box(cx - s_ * sy * (cw * .22) + c * k * cl * .2, cy + c * sy * (cw * .22) + s_ * k * cl * .2, .35, .7, .5, 1.3, th, 'plain', C['white'], 'plain', C['red'], True, 40.0)
    m.cylinder(cx - c * (cl / 2 + 1.2) + s_ * (cw / 2 + 1.0), cy - s_ * (cl / 2 + 1.2) - c * (cw / 2 + 1.0), 0, 7.0, .12, 'plain', C['grey'], seg=6)   # the price pole
    m.box(cx - c * (cl / 2 + 1.2) + s_ * (cw / 2 + 1.0), cy - s_ * (cl / 2 + 1.2) - c * (cw / 2 + 1.0), 6.6, 1.6, .25, 2.2, th, 'plain', C['red'], 'plain', C['red'], True, 40.0)
    kx, ky = cx + c * (cl / 2 + 2.6), cy + s_ * (cl / 2 + 2.6)
    m.box(kx, ky, 0, 5.0, 4.0, 3.2, th, 'plain', C['white'], 'roofdeck', C['grey'], True, 40.0)


def z_toll(m, ring, ctx, p):
    """A toll plaza: a flat canopy across the lanes on columns, a blue band on its edges, a raised island between every two lanes with a booth on it, a gantry sign over the middle.
    th is the direction ACROSS the road (the canopy's long side); the lanes run along the short side."""
    th, cx, cy = ctx['th'], ctx['cx'], ctx['cy']
    c, s_ = math.cos(th), math.sin(th)
    lanes = 5
    lw = 3.3
    cl, cw = lanes * lw + 2.6, 7.0
    z = 5.4
    m.slab(cx, cy, cl, cw, th, z, .55, C['white'])
    for sy in (-1, 1):                                             # the blue band on both long edges
        m.box(cx - s_ * sy * (cw / 2), cy + c * sy * (cw / 2), z + .55, cl, .3, .5, th, 'plain', C['blue'], 'plain', C['blue'], True, 40.0)
    for k in range(lanes + 1):                                     # an island between every two lanes (the outer two are the kerbs), a booth on each inner island
        u = (k - lanes / 2) * lw
        ix, iy = cx + c * u, cy + s_ * u
        m.box(ix, iy, 0, 1.3, cw * .8, .3, th + math.pi / 2, 'plain', C['grey'], 'plain', C['grey'], True, 40.0)
        if 0 < k < lanes:
            m.box(ix, iy, .3, 1.5, 2.6, 2.5, th + math.pi / 2, 'plain', C['white'], 'roofdeck', C['grey'], True, 40.0)
            m.column(ix + s_ * 0.0, iy, .3, z, .22, C['white'])
    for sx in (-1, 1):
        m.column(cx + c * sx * (cl / 2 - .6), cy + s_ * sx * (cl / 2 - .6), 0, z, .32, C['white'])
    m.box(cx, cy, z + 1.05, cl * .38, .35, 1.1, th, 'plain', C['blue'], 'plain', C['blue'], True, 40.0)   # the sign over the middle


def z_church(m, ring, ctx, p):
    """A church: a nave under a gabled roof, a square bell tower with a pointed top at the front end, a cross."""
    h = max(p['h'], 7.0)
    ring = _ccw(ring)
    col = seen(ctx, PASTELS, 21)
    m.prism(ring, 0, h, 'plain', col, 'plain', col, top=False, cell=5)
    L, W, th, cx, cy = ctx['L'], ctx['W'], ctx['th'], ctx['cx'], ctx['cy']
    if Polygon(ring).area / max(L * W, 1) > .78:                      # a roof over the bounding box only when the footprint is nearly a rectangle
        m.gable(cx, cy, L, W, th, h, min(4.5, W * .32), 'tile', C['terra'], over=.4, gable_col=col)
    else:
        m.cap(ring, h, MAT['roofdeck'], C['white'], True)
    c, s_ = math.cos(th), math.sin(th)
    tx, ty = cx + c * (L / 2 - 2.2), cy + s_ * (L / 2 - 2.2)
    th_ = h + min(4.0, h * .5)                                 # the tower stands above the nave in proportion, not by a fixed amount
    m.box(tx, ty, 0, 3.6, 3.6, th_, th, 'plain', col, 'plain', col, True, 6.0)
    m.hip(tx, ty, 3.6, 3.6, th, th_, 3.0, 'tile', C['terra'], over=.2)
    m.cylinder(tx, ty, th_ + 2.8, th_ + 4.4, .1, 'plain', C['yellow'], seg=6)
    entrance(m, ring, ctx, 2.8, 5.0, min(h * .7, 6.0), C['white'], keep=True)   # the porch on the front, an arched door in it


def z_school(m, ring, ctx, p):
    """A school: a long low block of classrooms with a ribbon of windows, a low hipped roof."""
    h = p['h']
    ring = _ccw(ring)
    col = seen(ctx, PASTELS, 22)
    m.prism(ring, 0, h, 'plain', col, 'plain', col, top=False, cell=5)
    if Polygon(ring).area / max(ctx['L'] * ctx['W'], 1) > .78:
        m.hip(ctx['cx'], ctx['cy'], ctx['L'], ctx['W'], ctx['th'], h, min(2.4, ctx['W'] * .18), 'sheet', C['rooftile'], over=.5)
    else:
        m.cap(ring, h, MAT['roofdeck'], C['white'], True)
    entrance(m, ring, ctx, 2.6, 6.0, min(3.6, h * .8), C['white'], pole=7.5)


def z_civic(m, ring, ctx, p):
    """A civic or health building: a plain block with a flat roof and a coloured parapet."""
    h = p['h']
    ring = _ccw(ring)
    col = seen(ctx, PASTELS, 23)
    m.prism(ring, 0, h, 'plain', col, 'roofdeck', C['white'], top=True, cell=5)
    poly = Polygon(ring).buffer(.25, join_style=2)
    m.prism(list(poly.exterior.coords)[:-1], h - .5, h + .6, 'plain', C['white'], 'plain', C['white'], top=True, cell=5)
    entrance(m, ring, ctx, 3.4, 9.0, min(h * .6, 5.2), C['white'], pole=9.0)


# The facade kit: Apple's plain buildings are detailed by shape, not by picture, so every type that stands on a footprint gets thin ribs and floor lines laid along its own edges
# (pilasters, floor ledges, buttresses), as boxes: twelve triangles each. kind -> (bottom, top as a function of h, pilaster spacing m, pilaster half-width, depth, floor spacing m, pilaster colour)
KIT = dict(
    condo=(4.6, lambda h: h - 1.2, 5.0, .3, .32, 3.2, 'white'), hotel=(4.0, lambda h: h - 1.2, 5.5, .3, .32, 3.4, 'white'), office=(5.0, lambda h: h - 1.2, 0, 0, 0, 3.8, 'slate'),
    mall=(0.0, lambda h: h - .6, 7.0, .35, .35, 5.0, 'white'), civic=(0.0, lambda h: h, 6.0, .35, .35, 3.6, 'white'), school=(0.0, lambda h: h, 5.0, .28, .28, 3.4, 'white'),
    parking=(0.0, lambda h: h, 4.0, .25, .3, 3.0, 'white'),
    hangar=(0.0, lambda h: p_wall(h), 6.0, .3, .45, 0, 'slate'), church=(0.0, lambda h: h * .8, 5.0, .4, .6, 0, 'white'),
)


ENTRANCE = dict(mall=(4.0, 12.0, 5.5), condo=(3.0, 7.0, 4.2), hotel=(4.5, 10.0, 5.5), office=(3.5, 8.0, 4.5), parking=(3.0, 6.0, 3.6))


def p_wall(h):
    return min(h, 9.0)


def facade_kit(m, ring, ctx, kind, h):
    """Ribs and floor lines along every long enough edge of the footprint, outward of the wall by a hand's depth."""
    ent = ENTRANCE.get(kind)
    if ent and h >= 8:
        try:
            entrance(m, _ccw(ring), ctx, ent[0], ent[1], ent[2], C['white'])      # a canopy on columns, steps and a door on the front edge
        except Exception:
            pass
    spec = KIT.get(kind)
    if not spec or h < 5:
        return
    z0, ztop, sp, hw, dep, fl, ccol = spec
    z1 = ztop(h)
    if z1 - z0 < 3:
        return
    ring = _ccw(ring)
    col = C.get(ccol, C['white'])
    n_pil = 0
    for i in range(len(ring)):
        (x0, y0), (x1, y1) = ring[i], ring[(i + 1) % len(ring)]
        E = math.hypot(x1 - x0, y1 - y0)
        if E < 6.0:
            continue
        ux, uy = (x1 - x0) / E, (y1 - y0) / E
        nx, ny = uy, -ux                                   # outward for a counter-clockwise ring
        th = math.atan2(uy, ux)
        if sp:
            cnt = int(E // sp)
            for k in range(cnt):
                t = (k + .5) / cnt * E
                if n_pil >= 70:
                    break
                m.box(x0 + ux * t + nx * dep / 2, y0 + uy * t + ny * dep / 2, z0, hw * 2, dep, z1 - z0, th, 'plain', col, 'plain', col, True, 40.0)
                n_pil += 1
        if fl:
            step = fl * (2 if h > 28 else 1)
            z = z0 + step
            nl_ = 0
            while z < z1 - .4 and nl_ < 18:
                m.box(x0 + ux * E / 2 + nx * .13, y0 + uy * E / 2 + ny * .13, z, E, .26, .22, th, 'plain', col, 'plain', col, True, 40.0)
                z += step
                nl_ += 1


TEMPLATES = dict(toll=z_toll, gas=z_gas, church=z_church, school=z_school, civic=z_civic, hotel=z_hotel, condo=z_condo, office=z_office, mall=z_mall, parking=z_parking, hangar=z_hangar, generic=z_generic)


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
