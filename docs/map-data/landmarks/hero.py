"""
The shapes of a hero landmark (sheet features that are drawn once, for one building): a ribbed dome on a drum, a stepped-arch facade, rows of solar panels, a flat deck, an annex
beside the footprint, an ivy wall, paving in rings on the ground. Positions are in metres east and north of the sheet's "anchor" (a longitude and latitude, read off the satellite
view with a metre grid, tools/sat.py grid), so a sheet is written the way the satellite shows the building. Everything is geometry or a flat colour; nothing moves.
"""
import math

from shapely.geometry import Polygon

from meshlib import MAT, rgb
from models_common import C

MXm, MYm = 111320 * math.cos(math.radians(14.525)), 110574


def hexc(s):
    return rgb(s.lstrip('#'))


def local(ctx, sh, x, y):
    ax, ay = sh['anchor']
    return (ax - ctx['lng']) * MXm + x, (ay - ctx['lat']) * MYm + y


def _mat(mats, name, default='plain'):
    return mats[name] if name in mats else (name if name in MAT else default)


def dome(m, ctx, sh, ft, mats):
    """A dome on a drum: the drum with arched windows, the dome in gores of two colours (ribs), a lantern and a cross."""
    cx, cy = local(ctx, sh, *ft['at'])
    R = float(ft['r'])
    z0 = float(ft.get('z', sh.get('height', 12.0)))
    dh = float(ft.get('drum', 3.0))
    rise = float(ft.get('rise', R * .8))
    wall = hexc(ft.get('drum_colour', sh['palette']['wall']))
    ca, cb = hexc(ft.get('colour', 'B8553F')), hexc(ft.get('colour2', ft.get('colour', 'B8553F')))
    seg = int(ft.get('ribs', 16)) * 2
    ring = [(cx + R * math.cos(2 * math.pi * i / seg), cy + R * math.sin(2 * math.pi * i / seg)) for i in range(seg)]
    m.prism(ring, z0, z0 + dh, _mat(mats, ft.get('drum_mat', 'arches')), wall, 'plain', wall, top=False, cell=4)
    m.cylinder(cx, cy, z0 + dh, z0 + dh + .35, R * 1.04, 'plain', hexc(ft.get('cornice', 'EAD9C0')), seg=seg)
    zb = z0 + dh + .35
    rings = 8
    pts = []
    for j in range(rings + 1):
        a = (math.pi / 2) * j / rings
        r, zz = R * math.cos(a), rise * math.sin(a)
        pts.append([(cx + r * math.cos(2 * math.pi * i / seg), cy + r * math.sin(2 * math.pi * i / seg), zb + zz) for i in range(seg + 1)])
    for j in range(rings):
        for i in range(seg):
            col = ca if i % 2 == 0 else cb
            p0, p1, p2, p3 = pts[j][i], pts[j][i + 1], pts[j + 1][i + 1], pts[j + 1][i]
            mid = ((p0[0] + p2[0]) / 2 - cx, (p0[1] + p2[1]) / 2 - cy, (p0[2] + p2[2]) / 2 - zb)
            ln = math.sqrt(mid[0] ** 2 + mid[1] ** 2 + (mid[2] * (R / max(rise, .1)) ** 2) ** 2) or 1
            n = (mid[0] / ln, mid[1] / ln, mid[2] * (R / max(rise, .1)) ** 2 / ln)
            ids = [m._v(p, n, (0, 0), MAT['plain'], col) for p in (p0, p1, p2, p3)]
            m.tri(ids[0], ids[1], ids[2])
            m.tri(ids[0], ids[2], ids[3])
    zt = zb + rise
    if ft.get('lantern', True):
        lr = max(.5, R * .12)
        m.cylinder(cx, cy, zt - .1, zt + lr * 3, lr, 'arches', wall, seg=8, cap_mat='plain', cap_col=hexc('EAD9C0'))
        m.dome(cx, cy, zt + lr * 3, lr * 1.1, lr * .8, 'plain', ca, seg=8, rings=3)
        zt = zt + lr * 3 + lr * .8
    if ft.get('cross', True):
        m.cylinder(cx, cy, zt, zt + 1.8, .07, 'plain', C['yellow'], seg=4)
        m.box(cx, cy, zt + 1.1, .9, .09, .09, 0, 'plain', C['yellow'], 'plain', C['yellow'], True, 40.0)


def arch_facade(m, ctx, sh, ft, mats):
    """The stepped-arch front: concentric arches, each a little proud of the one behind and lighter at the edge, a niche with the saint, a stained-glass arch, the door, a cross on top,
    a flat porch on columns. (cx, cy) is the middle of its foot; it faces the direction `facing` (degrees from east, counter-clockwise)."""
    cx, cy = local(ctx, sh, *ft['at'])
    a = math.radians(float(ft.get('facing', 43.4)))
    nx, ny = math.cos(a), math.sin(a)
    ux, uy = -ny, nx
    W = float(ft.get('width', 22.0))
    H = float(ft.get('height', 21.0))
    cols = [hexc(c) for c in ft.get('colours', ['D2825F', 'EBB197', 'D2825F', 'EBB197'])]
    base = (cx, cy, 0.0)
    steps = [(.50, 0.0), (.43, .55), (.35, 1.1), (.27, 1.65)]
    for k, (rf, off) in enumerate(steps):
        R = W * rf
        leg = max(1.0, H - R - .6 * k)
        m.vprism(m.arch_poly(R, leg), base, (ux, uy), (nx, ny), off, off + .6, 'plain', cols[k % len(cols)])
    # the stained glass: a tall dark arch, with a lit pane at night through its tile
    Rg = W * .12
    m.vprism(m.arch_poly(Rg, 4.4), (cx, cy, 8.0), (ux, uy), (nx, ny), 2.0, 2.25, 'plain', hexc('2F3E6B'))
    m.vprism(m.arch_poly(Rg * .55, 3.0), (cx, cy, 8.7), (ux, uy), (nx, ny), 2.25, 2.4, 'plain', hexc('E8B965'))
    # the niche and the saint
    m.vprism(m.arch_poly(.9, 1.4), (cx, cy, 15.6), (ux, uy), (nx, ny), 2.0, 2.2, 'plain', hexc('5A3F36'))
    m.vprism([(-.38, 0), (.38, 0), (.3, 2.1), (-.3, 2.1)], (cx, cy, 15.6), (ux, uy), (nx, ny), 2.2, 2.45, 'plain', hexc('F1E6D2'))
    # the door
    m.vprism(m.arch_poly(1.7, 1.8), (cx, cy, 0), (ux, uy), (nx, ny), 2.0, 2.2, 'plain', hexc('4A2F28'))
    # the cross
    top = H + .2
    m.vprism([(-.16, 0), (.16, 0), (.16, 3.0), (-.16, 3.0)], (cx, cy, top), (ux, uy), (nx, ny), .9, 1.2, 'plain', C['yellow'])
    m.vprism([(-1.0, 1.9), (1.0, 1.9), (1.0, 2.3), (-1.0, 2.3)], (cx, cy, top), (ux, uy), (nx, ny), .9, 1.2, 'plain', C['yellow'])
    # the porch: a flat roof on four columns, steps up to it
    pd, pw, pz = 5.0, W * .52, 4.6
    pcx, pcy = cx + nx * (pd / 2 + 2.4), cy + ny * (pd / 2 + 2.4)
    th = math.atan2(uy, ux)
    m.box(pcx, pcy, pz, pw, pd, .55, th, 'plain', cols[0], 'plain', hexc('EAD9C0'))
    for s in (-1.5, -.5, .5, 1.5):
        m.column(pcx + ux * s * pw / 3.4 + nx * (pd / 2 - .5), pcy + uy * s * pw / 3.4 + ny * (pd / 2 - .5), 0, pz, .32, hexc('EBB197'))
    for k in range(3):
        m.box(cx + nx * (7.6 + k * .55), cy + ny * (7.6 + k * .55), 0, pw * (1.0 + .06 * k), .6, .22 * (3 - k), th, 'plain', hexc('E7D9C0'), 'plain', hexc('E7D9C0'))


def solar(m, ctx, sh, ft):
    """Rows of solar panels on a strip of the roof (at: its middle, length and width along and across `axis` degrees): panels raised on a frame, a gap between rows."""
    cx, cy = local(ctx, sh, *ft['at'])
    a = math.radians(float(ft.get('axis', 43.4)))
    L, W = float(ft['length']), float(ft['width'])
    z = float(ft.get('z', sh.get('height', 12.0)))
    rows = max(1, int(W // 1.7))
    ux, uy = math.cos(a), math.sin(a)
    vx, vy = -uy, ux
    col = hexc(ft.get('colour', '2E3A66'))
    for r in range(rows):
        off = (r - (rows - 1) / 2) * (W / rows)
        px, py = cx + vx * off, cy + vy * off
        m.box(px, py, z + .75, L, W / rows * .82, .12, a, 'plain', col, 'plain', col, True, 40.0)
        for s in (-.45, 0, .45):
            m.box(px + ux * s * L, py + uy * s * L, z + .1, .12, W / rows * .5, .7, a, 'plain', C['grey'], 'plain', C['grey'], True, 40.0)


def deck(m, ctx, sh, ft, mats):
    pts = [local(ctx, sh, x, y) for x, y in ft['poly']]
    col = hexc(ft.get('colour', 'E6D7BC'))
    z = float(ft.get('z', sh.get('height', 12.0)))
    if ft.get('wall'):
        m.prism(pts, float(ft.get('from', 0.0)), z, _mat(mats, ft.get('wall_mat', 'plain')), hexc(ft['wall']), _mat(mats, ft.get('top_mat', 'roofdeck')), col, top=True, cell=4)
    else:
        m.cap(pts, z, MAT[_mat(mats, ft.get('top_mat', 'roofdeck'))], col, True, 6.0)


def ivy(m, ctx, sh, ft, mats):
    """A wall covered in climbing plant: a green face (tile 'ivy' of the sheet, absolute colours) along a line, with a hedge at its foot."""
    (x0, y0), (x1, y1) = [local(ctx, sh, *p) for p in ft['line']]
    H = float(ft.get('height', 9.0))
    dx, dy = x1 - x0, y1 - y0
    ln = math.hypot(dx, dy)
    n = (dy / ln, -dx / ln)
    if ft.get('flip'):
        n = (-n[0], -n[1])
        x0, y0, x1, y1 = x1, y1, x0, y0
    mat = _mat(mats, ft.get('mat', 'plain'))
    m.quad((x0, y0, 0.0), (x1, y1, 0.0), (x1, y1, H), (x0, y0, H), MAT[mat], (255, 255, 255), (n[0], n[1], 0.0), None, 4.0)
    hx0, hy0 = x0 + n[0] * .5, y0 + n[1] * .5
    hx1, hy1 = x1 + n[0] * .5, y1 + n[1] * .5
    m.quad((hx0, hy0, 0.0), (hx1, hy1, 0.0), (hx1, hy1, 1.0), (hx0, hy0, 1.0), MAT[mat], (255, 255, 255), (n[0], n[1], 0.0), None, 4.0)


def rings(m, ctx, sh, ft):
    """Paving laid in concentric rings on the ground (the forecourt): alternating pale and dark bands."""
    cx, cy = local(ctx, sh, *ft['at'])
    r0, r1, k = float(ft.get('r0', 2.0)), float(ft.get('r1', 14.0)), int(ft.get('n', 6))
    z = float(ft.get('z', .13))
    pale, dark = hexc(ft.get('pale', 'D9D4CC')), hexc(ft.get('dark', '6A6670'))
    seg = 40
    arc = ft.get('arc')               # a sector (degrees from, to) when the rings stop at a wall
    for i in range(k):
        ra, rb = r0 + (r1 - r0) * i / k, r0 + (r1 - r0) * (i + .55) / k
        col = dark if i % 2 == 0 else pale
        a0, a1 = (math.radians(arc[0]), math.radians(arc[1])) if arc else (0.0, 2 * math.pi)
        for s in range(seg):
            t0, t1 = a0 + (a1 - a0) * s / seg, a0 + (a1 - a0) * (s + 1) / seg
            P = lambda r, t: (cx + r * math.cos(t), cy + r * math.sin(t), z)
            m.quad(P(ra, t0), P(ra, t1), P(rb, t1), P(rb, t0), MAT['plain'], col, (0., 0., 1.), None, 8.0)


def belt(m, ring, ft):
    """A string course: a thin band standing a little proud of the walls all round, at a height."""
    out = float(ft.get('out', .4))
    poly = Polygon(ring).buffer(out, join_style=2)
    z = float(ft['z'])
    m.prism(list(poly.exterior.coords)[:-1], z, z + float(ft.get('h', .4)), 'plain', hexc(ft.get('colour', 'F4F1EA')), 'plain', hexc(ft.get('colour', 'F4F1EA')), top=True, cell=6)
