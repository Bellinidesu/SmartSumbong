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
import aircraft

Z_SURF, Z_MARK = .10, .17
# The map can only be moved over this box (admin/spatial.php, AREA); nothing outside it can ever be seen, so nothing outside it is drawn. A margin of 40 m.
AREA = (121.002663 - .0004, 14.514585 - .0004, 121.028423 + .0004, 14.539225 + .0004)

COL = dict(
    asphalt=rgb('565B68'), runway=rgb('4B505C'), rubber=rgb('363A45'), apron=rgb('D3D6DE'), white=rgb('F4F1EA'), yellow=rgb('F2C14E'),
    jet=rgb('E6E9EF'), jetroof=rgb('C7CCD6'), glass=rgb('9DB4CE'), dark=rgb('2B2F3B'), grey=rgb('8C93A3'),
    tail=[rgb('3F67B0'), rgb('C9544A'), rgb('F2C14E'), rgb('2FA6AB'), rgb('4C9A6A'), rgb('3A4C86')],
)


def _hash(*a):
    return zlib.crc32(repr(a).encode())


def local_polygon(boundary, origin):
    rs = []
    view = Polygon([infra.loc(AREA[0], AREA[1], origin), infra.loc(AREA[2], AREA[1], origin), infra.loc(AREA[2], AREA[3], origin), infra.loc(AREA[0], AREA[3], origin)])
    for r in boundary.rings:
        p = Polygon([infra.loc(x, y, origin) for x, y in r]).buffer(0)
        if not p.is_empty:
            rs.append(p.intersection(view))
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
    for e in by.get('parking_position', []):             # stands: a lead-in line, and an aircraft on most
        pts = L(e) if e['type'] == 'way' else []
        if len(pts) < 2:
            continue
        for run in inside_runs(pts, pp):
            ribbon(m, run, .22, Z_MARK, COL['yellow'], 0, 60.0)
        (x, y), th = pts[-1], math.atan2(pts[-1][1] - pts[-2][1], pts[-1][0] - pts[-2][0])
        if not ins(x, y) or length(pts) < 20 or _hash(round(x), round(y)) % 100 >= 62:
            continue
        tp = aircraft.pick_type(x, y)
        S = aircraft.TYPES[tp]
        nx, ny = x + math.cos(th) * 4.5, y + math.sin(th) * 4.5
        cx, cy = nx - math.cos(th) * S['L'] / 2, ny - math.sin(th) * S['L'] / 2
        # it must fit: its tail and both wing tips inside the boundary, and clear of the aircraft already there
        tipx, tipy = -math.sin(th) * S['span'] / 2, math.cos(th) * S['span'] / 2
        if not (ins(nx, ny) and ins(nx - math.cos(th) * S['L'], ny - math.sin(th) * S['L']) and ins(cx + tipx, cy + tipy) and ins(cx - tipx, cy - tipy)):
            continue
        if any(math.hypot(cx - px, cy - py) < (S['span'] + sp) * .5 * .92 for px, py, sp in placed):
            continue
        placed.append((cx, cy, S['span']))
        aircraft.airliner(m, nx, ny, th, tp, aircraft.livery_of(tp, x, y))
        aircraft.ground_support(m, nx, ny, th, tp)
        cnt('aircraft')
        cnt(tp)
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


# ---------------------------------------------------------------- towers: air traffic control, radars, a lattice mast
def tower_list(boundary):
    q = '[out:json][timeout:120];(nwr["man_made"="tower"](14.5019,120.9996,14.5309,121.0328);nwr["building"="control_tower"](14.5019,120.9996,14.5309,121.0328);nwr["man_made"="mast"]["name"](14.5019,120.9996,14.5309,121.0328););out geom tags;'
    out = []
    for e in infra.overpass('towers', q):
        t = e['tags']
        g = e.get('geometry')
        pt = (sum(p['lon'] for p in g) / len(g), sum(p['lat'] for p in g) / len(g)) if g else (e.get('lon'), e.get('lat'))
        if pt[0] is None or not boundary.inside(*pt) or not (AREA[0] <= pt[0] <= AREA[2] and AREA[1] <= pt[1] <= AREA[3]):
            continue
        ty = t.get('tower:type', '')
        kind = 'atc' if ty == 'aircraft_control' or t.get('building') == 'control_tower' else 'radar' if ty == 'radar' else 'mast' if ty == 'communication' else None
        if not kind:
            continue
        try:
            h = float(str(t.get('height', '')).split()[0])
        except (ValueError, IndexError):
            h = {'atc': 40.0, 'radar': 22.0, 'mast': 45.0}[kind]
        out.append(dict(kind=kind, name=t.get('name') or {'atc': 'Air traffic control tower', 'radar': 'Radar tower', 'mast': 'Communication mast'}[kind], lng=pt[0], lat=pt[1], h=h))
    return out


def tower_mesh(m, kind, h):
    W, G, D = COL['white'], COL['glass'], COL['dark']
    if kind == 'atc':
        cab = h * .74
        m.cylinder(0, 0, 0, cab, 2.7, 'plain', W, seg=16)
        m.cylinder(0, 0, cab * .35, cab * .38, 3.0, 'plain', COL['grey'], seg=16)           # a service ring
        m.cylinder(0, 0, cab, cab + 4.4, 5.3, 'glass', G, seg=16)                             # the cab: glass all round
        m.cylinder(0, 0, cab + 4.4, cab + 5.0, 5.8, 'plain', W, seg=16, cap_mat='roofdeck', cap_col=W)
        m.cylinder(0, 0, cab + 5.0, cab + 9.0, .12, 'plain', COL['grey'], seg=6)              # the mast
        m.box(0, 0, h + 4.0, .5, .5, .5, 0, 'glow2', COL['white'], 'glow2', COL['white'], True, 40.0)
    elif kind == 'radar':
        m.cylinder(0, 0, 0, h, 1.6, 'plain', W, seg=12)
        m.dome(0, 0, h, 4.2, 4.2, 'plain', W, seg=18, rings=6)
    else:
        for k in range(3):
            a = 2 * math.pi * k / 3
            m.cylinder(math.cos(a) * 1.6, math.sin(a) * 1.6, 0, h, .20, 'plain', COL['grey'], seg=6)
        for z in range(6, int(h), 8):
            m.cylinder(0, 0, z, z + .25, 1.7, 'plain', COL['grey'], seg=3)
        m.cylinder(0, 0, h, h + 6, .10, 'plain', COL['red'] if 'red' in COL else COL['grey'], seg=5)
        m.box(0, 0, h + 5.8, .4, .4, .4, 0, 'glow0', COL['white'], 'glow0', COL['white'], True, 40.0)
