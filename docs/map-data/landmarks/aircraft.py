"""
Aircraft and the vehicles that serve them, for the airfield diorama (airfield.py).

Each type is drawn from its manufacturer's published dimensions (length, wingspan, fuselage diameter, height of the tail, where the engines hang, how far the
wing is swept) with the proportions read off reference models (Sketchfab, CC BY: looked at, not copied): the A320 family and the 737 with their under-wing fans,
the widebodies with their raked tips, the ATR and the Q400 with a high wing, propellers and a T-tail. Liveries are the colours of the airlines that fly into
NAIA, reduced to a tail, a stripe and a belly: flat colour, as everywhere on this map.
"""
import math
import zlib

from meshlib import rgb

# length, span, fuselage radius, axis height above the apron, tail height above the axis, wing root (fraction of length from the nose), root chord, tip chord,
# sweep of the leading edge (metres back, root to tip), engines: [(lateral m, radius, length)], kind, winglet ('blend' | 'rake' | 'none')
TYPES = {
    'A320': dict(L=37.6, span=35.8, R=2.07, zc=3.95, fin=7.7, root=.355, c0=7.0, c1=1.6, sweep=8.4, eng=[(5.75, 1.2, 4.4)], kind='jet', tip='blend', stab=12.4),
    'A321': dict(L=44.5, span=35.8, R=2.07, zc=3.95, fin=7.7, root=.38, c0=7.0, c1=1.6, sweep=8.4, eng=[(5.75, 1.2, 4.4)], kind='jet', tip='blend', stab=12.4),
    'B738': dict(L=39.5, span=35.8, R=1.88, zc=3.7, fin=7.2, root=.375, c0=7.2, c1=1.6, sweep=8.6, eng=[(5.0, 1.1, 4.2)], kind='jet', tip='blend', stab=14.4),
    'A333': dict(L=63.7, span=60.3, R=2.82, zc=5.2, fin=8.9, root=.36, c0=10.4, c1=2.2, sweep=15.5, eng=[(10.6, 1.75, 6.0)], kind='jet', tip='wing', stab=19.0),
    'A359': dict(L=66.8, span=64.75, R=2.98, zc=5.5, fin=8.7, root=.355, c0=11.0, c1=2.0, sweep=17.5, eng=[(10.2, 1.95, 6.6)], kind='jet', tip='rake', stab=20.0),
    'B77W': dict(L=73.9, span=64.8, R=3.1, zc=5.7, fin=9.7, root=.37, c0=12.2, c1=2.2, sweep=17.5, eng=[(10.9, 2.45, 7.0)], kind='jet', tip='wing', stab=21.5),
    'B789': dict(L=62.8, span=60.1, R=2.9, zc=5.4, fin=8.8, root=.36, c0=10.6, c1=1.9, sweep=17.0, eng=[(9.6, 1.75, 6.2)], kind='jet', tip='rake', stab=19.5),
    'AT76': dict(L=27.2, span=27.05, R=1.4, zc=3.2, fin=4.3, root=.40, c0=2.3, c1=1.4, sweep=1.4, eng=[(4.0, .75, 3.6)], kind='prop', tip='none', stab=7.3),
    'DH8D': dict(L=32.8, span=28.4, R=1.35, zc=3.1, fin=4.8, root=.40, c0=2.6, c1=1.3, sweep=1.5, eng=[(4.3, .8, 4.0)], kind='prop', tip='none', stab=8.2),
}
# what flies into NAIA, by how often: a mix that looks like the apron looks
MIX = ['A320'] * 5 + ['A321'] * 2 + ['B738'] * 2 + ['A333'] * 2 + ['A359'] + ['B77W'] * 2 + ['B789'] + ['AT76'] * 2 + ['DH8D']
# tail, stripe (the cheat line), belly
LIV = {
    'pal': (rgb('3F67B0'), rgb('C9544A'), rgb('E6E9EF')),
    'ceb': (rgb('F2C14E'), rgb('3F67B0'), rgb('E6E9EF')),
    'air': (rgb('C9544A'), rgb('C9544A'), rgb('E6E9EF')),
    'uae': (rgb('B3363B'), rgb('8C93A3'), rgb('C7CCD6')),
    'qtr': (rgb('7B2D4A'), rgb('7B2D4A'), rgb('E6E9EF')),
    'sia': (rgb('3A4C86'), rgb('3A4C86'), rgb('E6E9EF')),
    'cpa': (rgb('3C8F6B'), rgb('3C8F6B'), rgb('E6E9EF')),
    'kal': (rgb('5E96D6'), rgb('5E96D6'), rgb('E6E9EF')),
    'dhl': (rgb('F2C14E'), rgb('C9544A'), rgb('F2C14E')),
}
NARROW = ['pal', 'ceb', 'ceb', 'air', 'pal']
WIDE = ['pal', 'uae', 'qtr', 'sia', 'cpa', 'kal', 'pal']
PROP = ['pal', 'ceb', 'ceb']
WHITE, DARK, GLASS, GREY = rgb('F4F1EA'), rgb('2B2F3B'), rgb('9DB4CE'), rgb('8C93A3')


def _h(*a):
    return zlib.crc32(repr(a).encode())


def pick_type(x, y):
    return MIX[_h(round(x), round(y), 'type') % len(MIX)]


def livery_of(tp, x, y):
    pool = PROP if TYPES[tp]['kind'] == 'prop' else (WIDE if TYPES[tp]['L'] > 55 else NARROW)
    return LIV[pool[_h(round(x), round(y), 'liv') % len(pool)]]


def loft(m, o, th, L, prof, col, mat=0, seg=12, N=12):
    """A body of revolution along the heading th from o = (x, y, z of its axis at the start), length L: prof(t) -> (radius, rise of the axis)."""
    c, s = math.cos(th), math.sin(th)
    rings = []
    for k in range(N + 1):
        r, up = prof(k / N)
        cx, cy, cz = o[0] + c * L * k / N, o[1] + s * L * k / N, o[2] + up
        ring = []
        for j in range(seg):
            a = 2 * math.pi * j / seg
            lat, vz = math.cos(a), math.sin(a)
            ring.append(((cx - s * lat * r, cy + c * lat * r, cz + vz * r), (-s * lat, c * lat, vz)))
        rings.append(ring)
    for k in range(N):
        for j in range(seg):
            j2 = (j + 1) % seg
            ids = [m._v(p, n, (0, 0), mat, col) for p, n in (rings[k][j], rings[k][j2], rings[k + 1][j2], rings[k + 1][j])]
            m.tri(ids[0], ids[2], ids[1])
            m.tri(ids[0], ids[3], ids[2])


def airliner(m, x, y, th, tp, liv):
    """The aircraft of type tp, nose at (x, y), heading th."""
    S = TYPES[tp]
    L, R, zc, span = S['L'], S['R'], S['zc'], S['span']
    tail, stripe, belly = liv
    back = th + math.pi
    cb, sb = math.cos(back), math.sin(back)

    def pt(t, lat, z=0.0):                               # t metres back from the nose, lat to the left of the way it faces
        return (x + cb * t - sb * lat, y + sb * t + cb * lat, z)

    def prof(t):                                         # nose cone, the barrel, the tail cone that sweeps up
        if t < .085:
            return max(R * math.sqrt(max(0.0, 1 - ((.085 - t) / .085) ** 2)), .08), -R * .12 * (1 - t / .085)
        if t > .80:
            u = (t - .80) / .20
            return max(R * (1 - .86 * u * u), .10), R * .95 * u * u
        return R, 0.0
    loft(m, (x, y, zc), back, L, prof, WHITE)
    p = pt(R * 1.1, 0)                                   # the cockpit windows
    m.box(p[0], p[1], zc + R * .22, R * .62, R * 1.05, R * .27, back, 'plain', DARK, 'plain', DARK, True, 40.0)
    for side in (-1, 1):                                 # the window row and the cheat line under it
        p = pt(L * .50, side * (R - .03))
        m.box(p[0], p[1], zc + R * .20, L * .70, .06, R * .22, back, 'plain', GLASS, 'plain', GLASS, False, 40.0)
        m.box(p[0], p[1], zc - R * .14, L * .72, .05, R * .09, back, 'plain', stripe, 'plain', stripe, False, 40.0)
    p = pt(L * .46, 0)                                   # the belly
    m.box(p[0], p[1], zc - R * .98, L * .62, R * 1.6, R * .36, back, 'plain', belly, 'plain', belly, False, 40.0)
    hi = S['kind'] == 'prop'
    zw = zc + R * .62 if hi else zc - R * .45            # a high wing for the turboprops
    for side in (-1, 1):
        rf, rb = pt(L * S['root'], 0), pt(L * S['root'] + S['c0'], 0)
        half = span / 2
        tf, tb = pt(L * S['root'] + S['sweep'], side * half), pt(L * S['root'] + S['sweep'] + S['c1'], side * half)
        ring = [(rf[0], rf[1]), (tf[0], tf[1]), (tb[0], tb[1]), (rb[0], rb[1])]
        if side == 1:
            ring = ring[::-1]
        dz = 0.0 if hi else 1.0                          # the dihedral: the tip stands a metre above the root
        m.prism(ring, zw - .28, zw + .06, 'plain', WHITE, 'plain', WHITE, True, 40.0)
        for lat, r, ln in S['eng']:
            e = pt(L * S['root'] + S['sweep'] * (lat / half) - ln * .55, side * lat)
            ez = zw - r * 1.05 if not hi else zw - r * .2
            loft(m, (e[0], e[1], ez), back, ln, lambda t, r=r: (r * (1.0 - (.35 * (t - .82) / .18 if t > .82 else 0.0)), 0.0), GREY, 0, 10, 6)
            if S['kind'] == 'prop':                      # a propeller disc
                fx, fy = pt(L * S['root'] + S['sweep'] * (lat / half) - ln * .55 - .25, side * lat)[:2]
                m.box(fx, fy, ez - 1.9, .08, 3.9, 3.9, back, 'plain', DARK, 'plain', DARK, True, 40.0)
        if S['tip'] in ('blend', 'rake'):                # winglet: a blended fin at the tip, or a raked extension
            w = pt(L * S['root'] + S['sweep'] + S['c1'] * .5, side * (half - .1))
            if S['tip'] == 'blend':
                m.box(w[0], w[1], zw, S['c1'] * 1.0, .10, 2.3, back, 'plain', tail, 'plain', tail, True, 40.0)
            else:
                rr = pt(L * S['root'] + S['sweep'] + 1.6, side * (half + .6))
                m.box(rr[0], rr[1], zw + .2, S['c1'] * .9, .6, .12, back, 'plain', WHITE, 'plain', WHITE, True, 40.0)
        st = S['stab'] / 2                               # the horizontal stabiliser
        a, b = pt(L * .86, 0), pt(L * .86 + st * .45, side * st)
        a2, b2 = pt(L * .86 + 3.4, 0), pt(L * .86 + st * .45 + 1.7, side * st)
        zt = zc + R * (1.55 if S['kind'] == 'prop' else .55) + (S['fin'] if S['kind'] == 'prop' else 0) * .92
        m.prism([(a[0], a[1]), (b[0], b[1]), (b2[0], b2[1]), (a2[0], a2[1])] if side == -1 else [(a2[0], a2[1]), (b2[0], b2[1]), (b[0], b[1]), (a[0], a[1])],
                zt, zt + .14, 'plain', WHITE, 'plain', WHITE, True, 40.0)
    f = pt(L * .83, 0)                                   # the fin
    fl = max(5.0, S['fin'] * .7)
    base = zc + R * .72
    m.vprism([(0, 0), (fl * .82, 0), (fl * .35, S['fin']), (-fl * .05, S['fin'])], (f[0], f[1], base), (cb, sb), (-sb, cb), -.17, .17, 'plain', tail)
    # the gear: nose and two mains
    for t, lat in ((R * 3.0 + 1.0, 0.0), (L * (S['root'] + .09), -R * 1.4), (L * (S['root'] + .09), R * 1.4)):
        g = pt(t, lat)
        m.box(g[0], g[1], 0, .34, .34, zc - R * .75, back, 'plain', DARK, 'plain', DARK, True, 40.0)
        m.box(g[0], g[1], 0, .5, 1.2, .55, back, 'plain', DARK, 'plain', DARK, True, 40.0)


# ---------------------------------------------------------------- ground support
YEL, ORG, STEEL, WHT = rgb('F2C14E'), rgb('F08C3A'), rgb('8C93A3'), rgb('F4F1EA')


def ground_support(m, x, y, th, tp):
    """The vehicles that stand around an aircraft: a tug with two baggage carts, a belt loader at the rear hold, a fuel truck at the wing, a catering truck at
    the rear door, a power unit at the nose. Which ones come is a hash of the stand."""
    S = TYPES[tp]
    L, R = S['L'], S['R']
    back = th + math.pi
    cb, sb = math.cos(back), math.sin(back)
    pt = lambda t, lat: (x + cb * t - sb * lat, y + sb * t + cb * lat)
    k = _h(round(x), round(y), 'gse')
    side = 1 if k & 1 else -1
    if k % 10 < 7:                                       # the baggage train
        for i, (t, w, h, col) in enumerate(((L * .60, 2.3, 1.5, YEL), (L * .60 + 3.6, 1.8, .9, STEEL), (L * .60 + 6.2, 1.8, .9, STEEL))):
            p = pt(t, -side * (R + 5.2))
            m.box(p[0], p[1], 0, 3.0 if i else 2.5, w, h, back + math.pi / 2, 'plain', col, 'plain', col, True, 40.0)
    if k % 7 < 5:                                        # the belt loader at the rear hold
        p = pt(L * .66, -side * (R + 2.6))
        m.box(p[0], p[1], 0, 4.6, 1.5, 1.4, back + math.pi / 2 - .35 * side, 'plain', STEEL, 'plain', YEL, True, 40.0)
    if k % 5 < 3:                                        # the fuel truck under the wing
        p = pt(L * S['root'] + 5.0, side * (S['span'] * .20))
        loft(m, (p[0] - cb * 3.4, p[1] - sb * 3.4, 1.7), back, 6.8, lambda t: (1.15, 0.0), WHT, 0, 10, 4)
        c = pt(L * S['root'] + 5.0 - 4.6, side * (S['span'] * .20))
        m.box(c[0], c[1], .35, 2.0, 2.4, 2.3, back, 'plain', ORG, 'plain', ORG, True, 40.0)
    if k % 9 < 5:                                        # the catering truck at the rear door
        p = pt(L * .79, side * (R + 3.4))
        m.box(p[0], p[1], .5, 6.8, 2.4, 3.6, back, 'plain', WHT, 'plain', WHT, True, 40.0)
        c = pt(L * .79 - 4.3, side * (R + 3.4))
        m.box(c[0], c[1], .4, 1.8, 2.3, 1.9, back, 'plain', STEEL, 'plain', STEEL, True, 40.0)
    if k % 4 < 3:                                        # the ground power unit at the nose
        p = pt(R * 2.6, side * (R + 1.4))
        m.box(p[0], p[1], 0, 1.6, 1.0, 1.0, back, 'plain', YEL, 'plain', YEL, True, 40.0)
    for t, lat in ((R * 2.0, R * 2.6), (R * 2.0, -R * 2.6), (L * S['root'], S['span'] * .5 + 1.5), (L * S['root'], -S['span'] * .5 - 1.5)):   # cones
        p = pt(t, lat)
        m.cylinder(p[0], p[1], 0, .55, .22, 'plain', ORG, seg=6)
