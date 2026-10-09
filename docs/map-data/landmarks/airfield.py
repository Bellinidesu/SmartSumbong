"""
The airfield inside the barangay, as a diorama: runways with their markings and rubber, taxiways with centre lines and edge lights, aprons with their slab
joints, stand lines, the painted H of every helipad, jet bridges at the gates, approach and runway lights, and a parked airliner on most stands.

Everything comes from what OpenStreetMap maps (aeroway=*): no position is guessed except the aircraft's own shape, one airliner of the A320 class, and
which stands hold one (a hash of the stand, so it never changes between builds). Nothing is drawn outside the Barangay 183 boundary. Nothing moves.
"""
import math, os, sys, zlib

from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union
from shapely.prepared import prep

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..'))
import infra
from meshlib import MAT, rgb

Z_SURF, Z_MARK = .10, .17

COL = dict(
    asphalt=rgb('565B68'), runway=rgb('4B505C'), rubber=rgb('363A45'), apron=rgb('D3D6DE'), white=rgb('F4F1EA'), yellow=rgb('F2C14E'),
    jet=rgb('E6E9EF'), jetroof=rgb('C7CCD6'), glass=rgb('9DB4CE'), dark=rgb('2B2F3B'), grey=rgb('8C93A3'),
    tail=[rgb('3F67B0'), rgb('C9544A'), rgb('F2C14E'), rgb('2FA6AB'), rgb('4C9A6A'), rgb('3A4C86')],
)


def _hash(*a):
    return zlib.crc32(repr(a).encode())


def local_polygon(boundary, origin):
    rs = []
    for r in boundary.rings:
        p = Polygon([infra.loc(x, y, origin) for x, y in r]).buffer(0)
        if not p.is_empty:
            rs.append(p)
    return unary_union(rs)


def ribbon(m, pts, w, z, col, mat=0, cell=14.0):
    """A flat strip w metres wide along a polyline, at height z (no sides: it is paint or a thin layer)."""
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        dx, dy = x1 - x0, y1 - y0
        ln = math.hypot(dx, dy)
        if ln < .05:
            continue
        nx, ny = -dy / ln * w / 2, dx / ln * w / 2
        m.quad((x0 + nx, y0 + ny, z), (x1 + nx, y1 + ny, z), (x1 - nx, y1 - ny, z), (x0 - nx, y0 - ny, z), mat, col, (0., 0., 1.), None, cell)


def dashes(m, pts, w, z, col, dash, gap):
    """Dashes along a polyline (a runway's centre line), the pattern running on from one segment to the next."""
    run = 0.0
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        seg = math.hypot(x1 - x0, y1 - y0)
        if seg < .05:
            continue
        ux, uy = (x1 - x0) / seg, (y1 - y0) / seg
        pos = -(run % (dash + gap))
        while pos < seg:
            a, b = max(pos, 0.0), min(pos + dash, seg)
            if b - a > .3:
                ribbon(m, [(x0 + ux * a, y0 + uy * a), (x0 + ux * b, y0 + uy * b)], w, z, col, 0, 40.0)
            pos += dash + gap
        run += seg


def along(pts, dist):
    """The point and heading (radians) a distance along a polyline."""
    d = 0.0
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        seg = math.hypot(x1 - x0, y1 - y0)
        if d + seg >= dist or i == len(pts) - 2:
            t = max(0.0, min(1.0, (dist - d) / seg)) if seg else 0
            return (x0 + (x1 - x0) * t, y0 + (y1 - y0) * t), math.atan2(y1 - y0, x1 - x0)
        d += seg


def length(pts):
    return sum(math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]) for i in range(len(pts) - 1))


def inside_runs(pts, pp):
    """The runs of a polyline that lie inside the boundary (cut at every segment whose middle is outside)."""
    runs, cur = [], []
    for i in range(len(pts) - 1):
        mid = Point((pts[i][0] + pts[i + 1][0]) / 2, (pts[i][1] + pts[i + 1][1]) / 2)
        if pp.contains(mid):
            if not cur:
                cur = [pts[i]]
            cur.append(pts[i + 1])
        elif cur:
            runs.append(cur)
            cur = []
    if cur:
        runs.append(cur)
    return runs


# ---------------------------------------------------------------- the airliner
def loft(m, o, th, L, prof, col, mat=0, seg=12):
    """A body of revolution along the heading th from o = (x, y, z of its axis at the start), length L: prof(t) -> (radius, rise of the axis)."""
    c, s = math.cos(th), math.sin(th)
    N = 14
    rings = []
    for k in range(N + 1):
        t = k / N
        r, up = prof(t)
        cx, cy, cz = o[0] + c * L * t, o[1] + s * L * t, o[2] + up
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


def airliner(m, x, y, th):
    """One airliner of the A320 class, nose at (x, y), heading th: white, a coloured tail, grey belly, engines under the wings."""
    L, R, zc = 37.6, 2.0, 3.6
    tail = COL['tail'][_hash(round(x), round(y)) % len(COL['tail'])]
    back = th + math.pi                                  # from the nose to the tail
    cb, sb = math.cos(back), math.sin(back)

    def pt(t, lat, z):                                   # t metres back from the nose, lat to the left of the way it faces
        return (x + cb * t - sb * lat, y + sb * t + cb * lat, z)

    def prof(t):
        if t < .10:
            return max(R * math.sqrt(max(0.0, 1 - ((.10 - t) / .10) ** 2)), .08), 0.0
        if t > .80:
            u = (t - .80) / .20
            return max(R * (1 - .82 * u * u), .12), R * .9 * u * u
        return R, 0.0
    loft(m, (x, y, zc), back, L, prof, COL['white'])
    p = pt(2.6, 0, 0)                                    # the cockpit windows
    m.box(p[0], p[1], zc + .55, 1.0, 2.1, .55, back, 'plain', COL['dark'], 'plain', COL['dark'], True, 40.0)
    for side in (-1, 1):                                 # a window row down each side
        p = pt(L * .48, side * (R - .03), 0)
        m.box(p[0], p[1], zc + .45, L * .62, .06, .42, back, 'plain', COL['glass'], 'plain', COL['glass'], False, 40.0)
    p = pt(L * .45, 0, 0)                                # the belly
    m.box(p[0], p[1], zc - R * .85, L * .62, R * 1.5, R * .42, back, 'plain', COL['grey'], 'plain', COL['grey'], False, 40.0)
    for side in (-1, 1):
        rf, rb = pt(L * .30, 0, 0), pt(L * .30 + 7.0, 0, 0)
        tf, tb = pt(L * .30 + 7.0, side * 17.5, 0), pt(L * .30 + 9.2, side * 17.5, 0)
        ring = [(rf[0], rf[1]), (tf[0], tf[1]), (tb[0], tb[1]), (rb[0], rb[1])]
        m.prism(ring, zc - .55, zc - .25, 'plain', COL['white'], 'plain', COL['white'], True, 40.0)
        e = pt(L * .30 + 2.0, side * 5.7, zc - 1.9)      # an engine under the wing
        loft(m, (e[0], e[1], e[2]), back, 3.8, lambda t: (1.0 - (.3 * (t - .85) / .15 if t > .85 else 0.0), 0.0), COL['grey'], 0, 10)
        w = pt(L * .30 + 8.6, side * 17.5, 0)            # the winglet
        m.box(w[0], w[1], zc - .25, 1.6, .12, 1.5, back, 'plain', tail, 'plain', tail, True, 40.0)
        a, b = pt(L * .88, 0, 0), pt(L * .88 + 3.0, side * 6.6, 0)
        a2, b2 = pt(L * .88 + 3.2, 0, 0), pt(L * .88 + 4.7, side * 6.6, 0)
        m.prism([(a[0], a[1]), (b[0], b[1]), (b2[0], b2[1]), (a2[0], a2[1])], zc + R * .5, zc + R * .62, 'plain', COL['white'], 'plain', COL['white'], True, 40.0)
    f = pt(L * .84, 0, 0)                                # the tail fin
    m.vprism([(0, 0), (4.2, 0), (2.0, 5.6), (0.0, 5.6)], (f[0], f[1], zc + R * .75), (cb, sb), (-sb, cb), -.18, .18, 'plain', tail)
    for t, lat in ((4.5, 0.0), (L * .42, -2.8), (L * .42, 2.8)):      # the gear
        g = pt(t, lat, 0)
        m.box(g[0], g[1], 0, .35, .35, zc - R * .6, back, 'plain', COL['dark'], 'plain', COL['dark'], True, 40.0)


# ---------------------------------------------------------------- the airfield
def helipad(m, x, y):
    m.cylinder(x, y, Z_SURF, Z_SURF + .04, 6.4, 'plain', COL['white'], seg=24)
    m.cylinder(x, y, Z_SURF + .04, Z_SURF + .08, 5.7, 'plain', COL['apron'], seg=24)
    for dx, L_, W_ in ((-1.3, .7, 4.4), (1.3, .7, 4.4), (0, 2.0, .7)):
        m.box(x + dx, y, Z_SURF + .08, L_, W_, .05, 0, 'plain', COL['white'], 'plain', COL['white'], True, 40.0)


def light(m, x, y, k, h=.36):
    m.box(x, y, 0, .34, .34, h, 0, 'glow%d' % k, COL['white'], 'glow%d' % k, COL['white'], True, 40.0)


def build(m, origin, boundary):
    q = '[out:json][timeout:120];(nwr["aeroway"](%s,%s,%s,%s););out geom;' % infra.BBOX
    els = infra.overpass('aeroway', q)
    poly = local_polygon(boundary, origin)
    pp = prep(poly)
    L = lambda e: [infra.loc(g['lon'], g['lat'], origin) for g in e.get('geometry', [])]
    N = lambda e: infra.loc(e['lon'], e['lat'], origin)
    ins = lambda x, y: pp.contains(Point(x, y))
    by = {}
    for e in els:
        by.setdefault(e['tags'].get('aeroway'), []).append(e)
    st = {}
    cnt = lambda k: st.__setitem__(k, st.get(k, 0) + 1)
    for e in by.get('apron', []):                        # aprons: slab concrete, cut to the boundary
        pts = L(e)
        if len(pts) < 4:
            continue
        try:
            g = Polygon(pts).buffer(0).intersection(poly)
        except Exception:
            continue
        for p in (g.geoms if hasattr(g, 'geoms') else [g]):
            if p.geom_type == 'Polygon' and p.area > 40:
                m.cap(list(p.exterior.coords)[:-1], Z_SURF, MAT['apron'], COL['apron'], True, 12.0)
                cnt('apron')
    taxi = []
    for e in by.get('taxiway', []):                      # taxiways: asphalt and a yellow centre line
        pts = L(e)
        if len(pts) < 2:
            continue
        w = 23.0 if len(e['tags'].get('ref', '')) <= 2 else 17.0
        try:
            w = float(e['tags'].get('width', w))
        except ValueError:
            pass
        taxi.append((pts, w))
        for run in inside_runs(pts, pp):
            ribbon(m, run, w, Z_SURF, COL['asphalt'], 0, 14.0)
            ribbon(m, run, .30, Z_MARK, COL['yellow'], 0, 60.0)
            cnt('taxiway')
    for e in by.get('runway', []):                       # runways: asphalt, edge lines, centre dashes, threshold bars, rubber
        pts = L(e)
        if len(pts) < 2:
            continue
        try:
            w = float(e['tags'].get('width', 45))
        except ValueError:
            w = 45.0
        tot = length(pts)
        for run in inside_runs(pts, pp):
            ribbon(m, run, w, Z_SURF + .02, COL['runway'], 0, 16.0)
            for sgn in (-1, 1):
                off = []
                for i, (x, y) in enumerate(run):
                    a, b = run[max(0, i - 1)], run[min(len(run) - 1, i + 1)]
                    dx, dy = b[0] - a[0], b[1] - a[1]
                    ln = math.hypot(dx, dy) or 1
                    off.append((x - dy / ln * sgn * (w / 2 - 1.4), y + dx / ln * sgn * (w / 2 - 1.4)))
                ribbon(m, off, .5, Z_MARK, COL['white'], 0, 60.0)
            dashes(m, run, .9, Z_MARK, COL['white'], 30.0, 20.0)
            cnt('runway')
        for end in (0.0, tot):
            (x, y), th = along(pts, end)
            sgn = 1 if end == 0 else -1
            c, s = math.cos(th) * sgn, math.sin(th) * sgn
            if not ins(x + c * 20, y + s * 20):
                continue
            for k in range(-5, 6):
                if k == 0:
                    continue
                lat = k * (w - 6) / 11
                bx, by_ = x + c * 6 - s * lat, y + s * 6 + c * lat
                ribbon(m, [(bx, by_), (bx + c * 30, by_ + s * 30)], 1.3, Z_MARK, COL['white'], 0, 60.0)
            ribbon(m, [(x + c * 330, y + s * 330), (x + c * 480, y + s * 480)], w * .34, Z_SURF + .035, COL['rubber'], 0, 60.0)
    for e in by.get('holding_position', []):             # a hold-short bar across the taxiway
        x, y = N(e)
        if not ins(x, y) or not taxi:
            continue
        best = None
        for pts, w in taxi:
            for i in range(len(pts) - 1):
                d = LineString([pts[i], pts[i + 1]]).distance(Point(x, y))
                if best is None or d < best[0]:
                    best = (d, pts[i], pts[i + 1], w)
        if best and best[0] < 25:
            _, a, b, w = best
            th = math.atan2(b[1] - a[1], b[0] - a[0])
            nx, ny = -math.sin(th), math.cos(th)
            for off in (0.0, .9):
                ox, oy = math.cos(th) * off, math.sin(th) * off
                ribbon(m, [(x - nx * w / 2 + ox, y - ny * w / 2 + oy), (x + nx * w / 2 + ox, y + ny * w / 2 + oy)], .35, Z_MARK, COL['yellow'], 0, 60.0)
            cnt('hold')
    placed = []
    for e in by.get('parking_position', []):             # stands: a lead-in line, and an airliner on most
        pts = L(e) if e['type'] == 'way' else []
        if len(pts) < 2:
            continue
        for run in inside_runs(pts, pp):
            ribbon(m, run, .22, Z_MARK, COL['yellow'], 0, 60.0)
        (x, y), th = pts[-1], math.atan2(pts[-1][1] - pts[-2][1], pts[-1][0] - pts[-2][0])
        if not ins(x, y) or length(pts) < 20 or _hash(round(x), round(y)) % 100 >= 62:
            continue
        nx, ny = x + math.cos(th) * 4.5, y + math.sin(th) * 4.5
        if any(math.hypot(nx - px, ny - py) < 33 for px, py in placed):
            continue
        if not (ins(nx, ny) and ins(nx - math.cos(th) * 38, ny - math.sin(th) * 38)):
            continue
        placed.append((nx, ny))
        airliner(m, nx, ny, th)
        cnt('aircraft')
    for e in by.get('helipad', []):
        if e['type'] == 'node':
            x, y = N(e)
            if ins(x, y):
                helipad(m, x, y)
                cnt('helipad')
    for e in by.get('jet_bridge', []):                   # a covered tube from the terminal to the aircraft door
        pts = L(e)
        if len(pts) < 2 or not ins(*pts[0]):
            continue
        for i in range(len(pts) - 1):
            (x0, y0), (x1, y1) = pts[i], pts[i + 1]
            ln = math.hypot(x1 - x0, y1 - y0)
            if ln >= 1:
                m.box((x0 + x1) / 2, (y0 + y1) / 2, 2.6, ln, 2.8, 2.7, math.atan2(y1 - y0, x1 - x0), 'ribbon', COL['jet'], 'roofdeck', COL['jetroof'], True, 8.0)
        m.cylinder(pts[-1][0], pts[-1][1], 0, 2.6, .3, 'plain', COL['grey'], seg=8)
        cnt('jetbridge')
    for e in by.get('navigationaid', []):                # lights: taxiway edge blue, runway edge and approach warm white
        x, y = N(e)
        if not ins(x, y):
            continue
        k = e['tags'].get('navigationaid')
        if k == 'txe':
            light(m, x, y, 3)
        elif k in ('rwe', 'als', 'papi'):
            light(m, x, y, 2, .9 if k == 'als' else .45)
        else:
            continue
        cnt(k)
    print('  airfield:', st)
