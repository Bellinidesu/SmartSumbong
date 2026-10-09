"""
A building described as parts placed in its own frame (a sheet's "frame": origin [lng, lat], th degrees: u along the building, v across it, z up), the way a plan is read off the
satellite view rotated to the building's axis. Parts: semicircular barrel vaults (with the buttress ribs and the stepped concentric arch at an end), boxes (flat roofs, annexes,
with an optional trellis face), domes on drums, solar strips, rings of paving, a pediment of stepped arches. Everything is real geometry in flat colours; nothing moves.
"""
import math

import terminal as T
from meshlib import MAT
from models_common import C

hexc = T.hexc


def corners(ctx, sh, u0, u1, v0, v1):
    return [T.uv(ctx, sh, u0, v0), T.uv(ctx, sh, u1, v0), T.uv(ctx, sh, u1, v1), T.uv(ctx, sh, u0, v1)]


def box(m, ctx, sh, p):
    """u0 u1 v0 v1 z0 z1: walls in `colour`, a roof in `roof`; `trellis` puts a frame of posts and a wire panel on the faces that look out (a side in `faces`: any of +u -u +v -v);
    `parapet` a low rim; `planters` dark troughs along the top."""
    u0, u1, v0, v1 = p['u0'], p['u1'], p['v0'], p['v1']
    z0, z1 = float(p.get('z0', 0)), float(p['z1'])
    col, roof = hexc(p.get('colour', 'D98B66')), hexc(p.get('roof', p.get('colour', 'D98B66')))
    m.prism(corners(ctx, sh, u0, u1, v0, v1), z0, z1, 'plain', col, 'roofdeck', roof, top=True, cell=8)
    th = T.frame_th(sh)
    for face in p.get('faces', []):
        post, panel = hexc(p.get('post', 'E7A27E')), hexc(p.get('panel', '6E8A5A'))
        sgn = 1 if face[0] == '+' else -1
        along_u = face[1] == 'v'                   # a face on a v side runs along u
        n = max(1, int(((u1 - u0) if along_u else (v1 - v0)) // float(p.get('bay', 4.0))))
        for k in range(n + 1):
            a = (u0 + (u1 - u0) * k / n) if along_u else (v0 + (v1 - v0) * k / n)
            x, y = T.uv(ctx, sh, a, (v1 if sgn > 0 else v0) + sgn * .25) if along_u else T.uv(ctx, sh, (u1 if sgn > 0 else u0) + sgn * .25, a)
            m.box(x, y, z0, .5, .5, z1 - z0 - .2, th, 'plain', post, 'plain', post, True, 40.0)
        # the wire panel, set a hand's breadth back
        for k in range(n):
            a = (u0 + (u1 - u0) * (k + .5) / n) if along_u else (v0 + (v1 - v0) * (k + .5) / n)
            x, y = T.uv(ctx, sh, a, (v1 if sgn > 0 else v0) + sgn * .05) if along_u else T.uv(ctx, sh, (u1 if sgn > 0 else u0) + sgn * .05, a)
            L = ((u1 - u0) if along_u else (v1 - v0)) / n - .6
            m.box(x, y, z0 + (z1 - z0) * .35, L, .12, (z1 - z0) * .5, th if along_u else th + math.pi / 2, 'plain', panel, 'plain', panel, True, 40.0)
    if p.get('planters'):
        pc = hexc(p.get('planter_colour', '3B3F3A'))
        poly = corners(ctx, sh, u0 + .3, u1 - .3, v0 + .3, v1 - .3)
        from shapely.geometry import Polygon
        rim = Polygon(poly)
        m.prism(list(rim.exterior.coords)[:-1], z1, z1 + .55, 'plain', pc, 'plain', pc, top=False, cell=8)
        m.prism(list(rim.buffer(-.9).exterior.coords)[:-1], z1 + .05, z1 + .5, 'plain', hexc(p.get('green', '5E8F4F')), 'plain', hexc(p.get('green', '5E8F4F')), top=True, cell=8)


def stepped_arch(m, ctx, sh, u, v, facing, width, base_z, wall_h, cols, steps=4, step=.6, window=True, cross=False):
    """The concentric stepped arch of an end: `steps` arches, each a little proud and lighter at the edge, a tall recessed stained-glass arch and two small ones. (u, v) is the middle
    of its foot; `facing` the way it looks, in frame degrees from +u (0 = +u, 90 = +v, 180 = -u, 270 = -v)."""
    th = T.frame_th(sh) + math.radians(facing)
    nx, ny = math.cos(th), math.sin(th)
    ux, uy = -ny, nx
    x, y = T.uv(ctx, sh, u, v)
    R0 = width / 2
    for k in range(steps):
        R = R0 - k * .9
        leg = max(.5, wall_h - 0 + 0)
        m.vprism(m.arch_poly(R, leg), (x, y, base_z), (ux, uy), (nx, ny), k * step, k * step + step + .02, 'plain', cols[k % len(cols)])
    if window:
        Rg = R0 * .34
        m.vprism(m.arch_poly(Rg, wall_h * .5), (x, y, base_z + 1.0), (ux, uy), (nx, ny), steps * step, steps * step + .25, 'plain', hexc('33466F'))
        m.vprism(m.arch_poly(Rg * .55, wall_h * .36), (x, y, base_z + 1.6), (ux, uy), (nx, ny), steps * step + .25, steps * step + .4, 'plain', hexc('E8B965'))
        for s in (-1, 1):
            xx, yy = x + ux * s * R0 * .62, y + uy * s * R0 * .62
            m.vprism(m.arch_poly(R0 * .13, wall_h * .22), (xx, yy, base_z + 1.0), (ux, uy), (nx, ny), steps * step, steps * step + .2, 'plain', hexc('33466F'))
    if cross:
        top = base_z + wall_h + R0 + .1
        m.vprism([(-.16, 0), (.16, 0), (.16, 3.2), (-.16, 3.2)], (x, y, top), (ux, uy), (nx, ny), .2, .5, 'plain', C['yellow'])
        m.vprism([(-1.0, 2.0), (1.0, 2.0), (1.0, 2.4), (-1.0, 2.4)], (x, y, top), (ux, uy), (nx, ny), .2, .5, 'plain', C['yellow'])


def barrel(m, ctx, sh, p):
    """A semicircular barrel vault on straight walls. axis 'u' or 'v'; span [a0, a1] along it; across [c0, c1] its width; wall: the height of the straight walls; rise: the vault above them
    (the full half circle when it is left out); ribs: buttress fins every `every` metres on both sides; ends: ['+', '-'] ends given a stepped arch (the rest are closed flat)."""
    ax = p['axis']
    a0, a1 = p['span']
    c0, c1 = p['across']
    wall, W = float(p.get('wall', 7.0)), c1 - c0
    rise = float(p.get('rise', W / 2))
    col, vcol = hexc(p.get('colour', 'D98B66')), hexc(p.get('vault', 'E8D9B8'))
    mid_a, mid_c = (a0 + a1) / 2, (c0 + c1) / 2
    uu, vv = (mid_a, mid_c) if ax == 'u' else (mid_c, mid_a)
    cx, cy = T.uv(ctx, sh, uu, vv)
    th = T.frame_th(sh) + (0 if ax == 'u' else math.pi / 2)
    L = a1 - a0
    if wall > 0:
        if ax == 'u':
            m.prism(corners(ctx, sh, a0, a1, c0, c1), 0, wall, 'plain', col, 'plain', col, top=False, cell=8)
        else:
            m.prism(corners(ctx, sh, c0, c1, a0, a1), 0, wall, 'plain', col, 'plain', col, top=False, cell=8)
    m.barrel(cx, cy, L, W, th, wall, rise, 'plain', vcol, seg=16)
    ribs = p.get('ribs')
    if ribs:
        rc = hexc(ribs.get('colour', 'F0E4C8'))
        n = max(1, int(L // float(ribs.get('every', 7.0))))
        for k in range(n + 1):
            a = a0 + L * k / n
            for side in (-1, 1):
                cc = mid_c + side * (W / 2 + .35)
                x, y = T.uv(ctx, sh, a, cc) if ax == 'u' else T.uv(ctx, sh, cc, a)
                m.box(x, y, 0, .7, .7, wall + rise * .45, th, 'plain', rc, 'plain', rc, True, 40.0)
    for end in p.get('ends', []):
        cols = [hexc(c) for c in p.get('arch', ['EBB197', 'F6D3BC', 'EBB197', 'F6D3BC'])]
        if ax == 'u':
            u = a1 if end == '+' else a0
            stepped_arch(m, ctx, sh, u, mid_c, 0 if end == '+' else 180, W, 0.0, wall, cols, window=p.get('window', True), cross=p.get('cross', False))
        else:
            v = a1 if end == '+' else a0
            stepped_arch(m, ctx, sh, mid_c, v, 90 if end == '+' else 270, W, 0.0, wall, cols, window=p.get('window', True), cross=p.get('cross', False))


def dome(m, ctx, sh, p):
    cx, cy = T.uv(ctx, sh, *p['at'])
    R, z0 = float(p['r']), float(p['z'])
    dh, rise = float(p.get('drum', 3.0)), float(p.get('rise', R * .8))
    wall = hexc(p.get('drum_colour', 'EAD9C0'))
    ca, cb = hexc(p.get('colour', 'A8503F')), hexc(p.get('colour2', p.get('colour', 'A8503F')))
    seg = int(p.get('ribs', 12)) * 2
    ring = [(cx + R * math.cos(2 * math.pi * i / seg), cy + R * math.sin(2 * math.pi * i / seg)) for i in range(seg)]
    if p.get('base', 0):
        m.prism(ring, float(p['base']), z0, 'plain', wall, 'plain', wall, top=False, cell=6)
    m.prism(ring, z0, z0 + dh, 'plain', wall, 'plain', wall, top=False, cell=4)
    if p.get('windows', True):
        for i in range(8):
            a = 2 * math.pi * i / 8
            x, y = cx + (R + .04) * math.cos(a), cy + (R + .04) * math.sin(a)
            m.box(x, y, z0 + dh * .25, .1, min(1.1, R * .22), dh * .5, a, 'plain', hexc('3B4A66'), 'plain', hexc('3B4A66'), True, 40.0)
    m.cylinder(cx, cy, z0 + dh, z0 + dh + .35, R * 1.04, 'plain', hexc(p.get('cornice', 'EAD9C0')), seg=seg)
    zb = z0 + dh + .35
    rings = 8
    pts = []
    for j in range(rings + 1):
        a = (math.pi / 2) * j / rings
        r, zz = R * math.cos(a), rise * math.sin(a)
        pts.append([(cx + r * math.cos(2 * math.pi * i / seg), cy + r * math.sin(2 * math.pi * i / seg), zb + zz) for i in range(seg + 1)])
    k2 = (R / max(rise, .1)) ** 2
    for j in range(rings):
        for i in range(seg):
            col = ca if i % 2 == 0 else cb
            p0, p1, p2, p3 = pts[j][i], pts[j][i + 1], pts[j + 1][i + 1], pts[j + 1][i]
            mid = ((p0[0] + p2[0]) / 2 - cx, (p0[1] + p2[1]) / 2 - cy, ((p0[2] + p2[2]) / 2 - zb) * k2)
            ln = math.sqrt(mid[0] ** 2 + mid[1] ** 2 + mid[2] ** 2) or 1
            n = (mid[0] / ln, mid[1] / ln, mid[2] / ln)
            ids = [m._v(q, n, (0, 0), MAT['plain'], col) for q in (p0, p1, p2, p3)]
            m.tri(ids[0], ids[1], ids[2])
            m.tri(ids[0], ids[2], ids[3])
    zt = zb + rise
    if p.get('lantern', True):
        lr = max(.5, R * .12)
        m.cylinder(cx, cy, zt - .1, zt + lr * 3, lr, 'plain', wall, seg=8, cap_mat='plain', cap_col=hexc('EAD9C0'))
        m.dome(cx, cy, zt + lr * 3, lr * 1.1, lr * .8, 'plain', ca, seg=8, rings=3)
        zt += lr * 3 + lr * .8
    if p.get('cross', True):
        m.cylinder(cx, cy, zt, zt + 1.9, .07, 'plain', C['yellow'], seg=4)
        m.box(cx, cy, zt + 1.15, 1.0, .09, .09, 0, 'plain', C['yellow'], 'plain', C['yellow'], True, 40.0)


def solar(m, ctx, sh, p):
    u0, u1, v0, v1, z = p['u0'], p['u1'], p['v0'], p['v1'], float(p['z'])
    th = T.frame_th(sh)
    col = hexc(p.get('colour', '2E3A66'))
    rows = max(1, int((v1 - v0) // 1.8))
    for r in range(rows):
        v = v0 + (r + .5) * (v1 - v0) / rows
        x, y = T.uv(ctx, sh, (u0 + u1) / 2, v)
        m.box(x, y, z + .7, u1 - u0, (v1 - v0) / rows * .82, .12, th, 'plain', col, 'plain', col, True, 40.0)
        for s in (-.42, 0, .42):
            xx, yy = T.uv(ctx, sh, (u0 + u1) / 2 + s * (u1 - u0), v)
            m.box(xx, yy, z + .05, .12, (v1 - v0) / rows * .5, .65, th, 'plain', C['grey'], 'plain', C['grey'], True, 40.0)


def rings(m, ctx, sh, p):
    cx, cy = T.uv(ctx, sh, *p['at'])
    r0, r1, k = float(p.get('r0', 2.0)), float(p.get('r1', 12.0)), int(p.get('n', 6))
    z = float(p.get('z', .13))
    pale, dark = hexc(p.get('pale', 'D9D4CC')), hexc(p.get('dark', '6A6670'))
    seg = 40
    for i in range(k):
        ra, rb = r0 + (r1 - r0) * i / k, r0 + (r1 - r0) * (i + .55) / k
        col = dark if i % 2 == 0 else pale
        for s in range(seg):
            t0, t1 = 2 * math.pi * s / seg, 2 * math.pi * (s + 1) / seg
            Pq = lambda r, t: (cx + r * math.cos(t), cy + r * math.sin(t), z)
            m.quad(Pq(ra, t0), Pq(ra, t1), Pq(rb, t1), Pq(rb, t0), MAT['plain'], col, (0., 0., 1.), None, 8.0)


def hedge(m, ctx, sh, p):
    """A hedge along a line: a green box, a metre and a half high, with a few flowering patches."""
    (a0, b0), (a1, b1) = p['line']
    x0, y0 = T.uv(ctx, sh, a0, b0)
    x1, y1 = T.uv(ctx, sh, a1, b1)
    ln = math.hypot(x1 - x0, y1 - y0)
    m.box((x0 + x1) / 2, (y0 + y1) / 2, 0, ln, float(p.get('width', 1.4)), float(p.get('height', 1.7)), math.atan2(y1 - y0, x1 - x0), 'plain', hexc(p.get('colour', '4F8A47')), 'plain', hexc(p.get('colour', '4F8A47')), True, 8.0)


def build(m, ctx, sh, ft, mats):
    kind = ft.get('kind')
    for p in ft['parts']:
        k = p['type']
        {'barrel': barrel, 'box': box, 'dome': dome, 'solar': solar, 'rings': rings, 'hedge': hedge}.get(k, lambda *a: None)(m, ctx, sh, p)
        if k == 'pediment':
            stepped_arch(m, ctx, sh, p['u'], p['v'], p.get('facing', 0), p['width'], float(p['z']), float(p['wall']), [hexc(c) for c in p.get('arch', ['E9987A', 'F6C9AE'])], steps=p.get('steps', 4), window=False, cross=p.get('cross', True))
