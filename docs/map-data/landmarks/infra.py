"""
The infrastructure of the zone, drawn from what OpenStreetMap maps there (no guessing where things are): the elevated roads (NAIA
Expressway, the Skyway ramps) with their piers and parapets, the covered walkways that link Newport's buildings, the light-rail viaduct, walls, fences and
hedges, bus shelters, traffic signals, flagpoles and water towers. One mesh, lit by the same GPU bake as the landmarks.

Heights: a way on a bridge stands at 6 m a layer plus the deck; a link (a ramp) climbs from the ground to its height over its first and last 90 m
(OpenStreetMap does not say how steep a ramp is; this is a stand-in). Widths come from the lanes tag, or the road's class.
"""
import json, math, os, sys, time, urllib.parse, urllib.request

from shapely.geometry import Point, Polygon

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from meshlib import Mesh, rgb

MX, MY = 111320 * math.cos(math.radians(14.525)), 110574
BBOX = (14.5019, 120.9996, 14.5309, 121.0328)          # south, west, north, east
CACHE = os.path.join(HERE, 'osm-cache')
MIRRORS = ['overpass.openstreetmap.fr', 'overpass-api.de', 'z.overpass-api.de']
UA = 'SmartSumbong/1.0 (barangay portal; contact acelediac@gmail.com)'

COL = dict(deck=rgb('6B7285'), side=rgb('B9BDC8'), pier=rgb('A7ACB8'), rail=rgb('D4D7DE'), wall=rgb('CDBFA8'), hedge=rgb('4C9A6A'), fence=rgb('8C93A3'),
           pole=rgb('7C849A'), shelterroof=rgb('3F67B0'), shelter=rgb('B9C9DA'), red=rgb('C9544A'), blue=rgb('3F67B0'), dark=rgb('2B2F3B'), tank=rgb('D9DDE6'),
           glass=rgb('B9C9DA'), white=rgb('F4F1EA'), green=rgb('3FA66B'), amber=rgb('F2B84E'))


def overpass(name, q):
    os.makedirs(CACHE, exist_ok=True)
    f = os.path.join(CACHE, name + '.json')
    if os.path.exists(f) and time.time() - os.path.getmtime(f) < 7 * 86400:
        return json.load(open(f, encoding='utf-8'))
    for h in MIRRORS:
        try:
            req = urllib.request.Request('https://%s/api/interpreter' % h, data=urllib.parse.urlencode({'data': q}).encode(), headers={'User-Agent': UA})
            d = json.loads(urllib.request.urlopen(req, timeout=150).read().decode('utf-8'))['elements']
            json.dump(d, open(f, 'w', encoding='utf-8'))
            return d
        except Exception as e:
            print('  %s: %s' % (h, str(e)[:60]), file=sys.stderr)
            time.sleep(3)
    raise SystemExit('Overpass is not answering')


def load():
    bb = '%s,%s,%s,%s' % BBOX
    bridges = overpass('bridges', '[out:json][timeout:120];(way["bridge"]["highway"](%s);way["bridge"]["railway"](%s););out geom tags;' % (bb, bb))
    walls = overpass('walls', '[out:json][timeout:120];way["barrier"~"^(wall|fence|hedge|retaining_wall|city_wall)$"](%s);out geom tags;' % bb)
    nodes = overpass('furniture', '[out:json][timeout:120];(node["highway"~"^(bus_stop|traffic_signals)$"](%s);node["man_made"~"^(flagpole|water_tower)$"](%s);way["man_made"="water_tower"](%s);node["amenity"="shelter"](%s););out geom tags;' % ((bb,) * 4))
    return bridges, walls, nodes


def loc(lng, lat, o):
    return ((lng - o[0]) * MX, (lat - o[1]) * MY)


def deck_width(t):
    h = t.get('highway') or ''
    if t.get('railway'):
        return 8.0
    try:
        lanes = int(t.get('lanes', 0))
    except ValueError:
        lanes = 0
    if h in ('footway', 'corridor', 'path', 'steps', 'pedestrian', 'cycleway'):
        return 3.2
    base = {'motorway': 2, 'trunk': 2, 'primary': 2, 'secondary': 2, 'tertiary': 2, 'motorway_link': 1, 'trunk_link': 1, 'primary_link': 1}.get(h, 2 if h not in ('service', 'residential') else 1.6)
    n = lanes if lanes else base
    return max(4.5, n * 3.4 + 2.2)


def strip(m, pts, zs, w, thick, top_col, side_col, parapet=None):
    """A deck along a polyline: its top, both sides and underside, and a parapet on each edge if asked."""
    L, R = [], []
    for i, (x, y) in enumerate(pts):
        a = pts[max(0, i - 1)]
        b = pts[min(len(pts) - 1, i + 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / ln, dx / ln
        L.append((x + nx * w / 2, y + ny * w / 2))
        R.append((x - nx * w / 2, y - ny * w / 2))
    for i in range(len(pts) - 1):
        z0, z1 = zs[i], zs[i + 1]
        l0, l1, r0, r1 = L[i], L[i + 1], R[i], R[i + 1]
        m.quad((r0[0], r0[1], z0), (r1[0], r1[1], z1), (l1[0], l1[1], z1), (l0[0], l0[1], z0), 0, top_col, (0., 0., 1.), None, cell=9.0)                       # top
        m.quad((r0[0], r0[1], z0 - thick), (l0[0], l0[1], z0 - thick), (l1[0], l1[1], z1 - thick), (r1[0], r1[1], z1 - thick), 0, side_col, (0., 0., -1.), None, cell=9.0)  # under
        for (a0, a1, sgn) in ((l0, l1, 1), (r0, r1, -1)):   # the two edges
            dx, dy = a1[0] - a0[0], a1[1] - a0[1]
            ln = math.hypot(dx, dy) or 1.0
            nrm = (-dy / ln * sgn, dx / ln * sgn, 0.0) if False else ((dy / ln) * (-1 if sgn > 0 else 1) * -1, (-dx / ln) * (-1 if sgn > 0 else 1) * -1, 0.0)
            nrm = ((-dy / ln) * sgn, (dx / ln) * sgn, 0.0)
            m.quad((a0[0], a0[1], z0 - thick), (a1[0], a1[1], z1 - thick), (a1[0], a1[1], z1), (a0[0], a0[1], z0), 0, side_col, nrm, None, cell=9.0)
            if parapet:
                m.quad((a0[0], a0[1], z0), (a1[0], a1[1], z1), (a1[0], a1[1], z1 + parapet), (a0[0], a0[1], z0 + parapet), 0, COL['rail'], nrm, None, cell=9.0)


def piers(m, pts, zs, thick, every=30.0, w=1.7, col=None, skip_low=2.5):
    d = 0.0
    nxt = every / 2
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        seg = math.hypot(x1 - x0, y1 - y0)
        while d + seg >= nxt:
            t = (nxt - d) / seg if seg else 0
            x, y, z = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, zs[i] + (zs[i + 1] - zs[i]) * t
            if z - thick > skip_low:
                m.box(x, y, 0, w, w, z - thick, math.atan2(y1 - y0, x1 - x0), 'plain', col or COL['pier'], 'plain', col or COL['pier'], True)
            nxt += every
        d += seg


def build(m, origin, boundary=None):
    bridges, walls, nodes = load()
    n_roads = n_walk = n_rail = 0
    for e in bridges:
        t = e.get('tags', {})
        g = e.get('geometry') or []
        if len(g) < 2:
            continue
        pts = [loc(p['lon'], p['lat'], origin) for p in g]
        if boundary and not any(boundary.inside(p['lon'], p['lat'], 80) for p in g):
            continue
        try:
            layer = int(t.get('layer', 1))
        except ValueError:
            layer = 1
        walk = (t.get('highway') in ('footway', 'corridor', 'path', 'steps', 'pedestrian', 'cycleway'))
        if t.get('highway') == 'steps':
            continue
        deck = max(1, layer) * 6.0 + (0 if walk else 1.0)
        # a ramp climbs from the ground over its first and last 90 m (unless its end is a bridge's); everything else is level
        total = sum(math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]) for i in range(len(pts) - 1))
        link = (t.get('highway', '').endswith('_link')) and total > 40
        zs, d = [], 0.0
        for i, (x, y) in enumerate(pts):
            if i:
                d += math.hypot(x - pts[i - 1][0], y - pts[i - 1][1])
            z = deck
            if link:
                z = deck * min(1.0, min(d, total - d) / 90.0 + .08)
            zs.append(max(z, .4))
        # sample long segments so that a climb is smooth and the deck is lit in many places
        P2, Z2 = [pts[0]], [zs[0]]
        for i in range(len(pts) - 1):
            seg = math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
            k = max(1, math.ceil(seg / 12))
            for j in range(1, k + 1):
                f = j / k
                P2.append((pts[i][0] + (pts[i + 1][0] - pts[i][0]) * f, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * f))
                Z2.append(zs[i] + (zs[i + 1] - zs[i]) * f)
        w = deck_width(t)
        if t.get('railway'):
            strip(m, P2, Z2, w, 1.8, COL['deck'], COL['side'], .9)
            piers(m, P2, Z2, 1.8, 26.0, 2.2)
            n_rail += 1
        elif walk:
            h = 2.6
            # a covered walkway: a floor, glazed sides and a roof, on slim columns
            strip(m, P2, Z2, w, .35, COL['deck'], COL['side'])
            for i in range(len(P2) - 1):
                a, b = P2[i], P2[i + 1]
                z0, z1 = Z2[i], Z2[i + 1]
                dx, dy = b[0] - a[0], b[1] - a[1]
                ln = math.hypot(dx, dy) or 1.0
                nx, ny = -dy / ln, dx / ln
                for sgn in (1, -1):
                    pa = (a[0] + nx * w / 2 * sgn, a[1] + ny * w / 2 * sgn)
                    pb = (b[0] + nx * w / 2 * sgn, b[1] + ny * w / 2 * sgn)
                    m.quad((pa[0], pa[1], z0), (pb[0], pb[1], z1), (pb[0], pb[1], z1 + h), (pa[0], pa[1], z0 + h), 2, COL['glass'], (ny * sgn * -1 * -1, -nx * sgn * -1 * -1, 0.0) if False else (nx * sgn, ny * sgn, 0.0), None, cell=3.0)
                m.quad((a[0] - nx * w / 2 - nx * .3, a[1] - ny * w / 2 - ny * .3, z0 + h), (b[0] - nx * w / 2 - nx * .3, b[1] - ny * w / 2 - ny * .3, z1 + h),
                       (b[0] + nx * w / 2 + nx * .3, b[1] + ny * w / 2 + ny * .3, z1 + h), (a[0] + nx * w / 2 + nx * .3, a[1] + ny * w / 2 + ny * .3, z0 + h), 4, COL['white'], (0., 0., 1.), None, cell=6.0)
            piers(m, P2, Z2, .35, 22.0, .6)
            n_walk += 1
        else:
            strip(m, P2, Z2, w, 1.5, COL['deck'], COL['side'], .9)
            piers(m, P2, Z2, 1.5, 28.0, 1.7)
            n_roads += 1
    print('  elevated: %d roads, %d walkways, %d rail viaducts' % (n_roads, n_walk, n_rail))
    # walls, fences and hedges
    nw = 0
    for e in walls:
        t = e.get('tags', {})
        g = e.get('geometry') or []
        if len(g) < 2 or (boundary and not any(boundary.inside(p['lon'], p['lat'], 20) for p in g)):
            continue
        kind = t.get('barrier')
        try:
            h = float(str(t.get('height', '')).replace('m', ''))
        except ValueError:
            h = {'hedge': 1.6, 'fence': 1.9, 'wall': 2.4, 'retaining_wall': 1.6, 'city_wall': 3.0}.get(kind, 2.0)
        col = COL['hedge'] if kind == 'hedge' else COL['fence'] if kind == 'fence' else COL['wall']
        th = .9 if kind == 'hedge' else .12 if kind == 'fence' else .3
        pts = [loc(p['lon'], p['lat'], origin) for p in g]
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            ln = math.hypot(b[0] - a[0], b[1] - a[1])
            if ln < .5:
                continue
            m.box((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 0, ln + .05, th, h, math.atan2(b[1] - a[1], b[0] - a[0]), 'plain', col, 'plain', col, True)
        nw += 1
    print('  walls, fences, hedges:', nw)
    # point things
    nb = ns = nf = nt = 0
    for e in nodes:
        t = e.get('tags', {})
        if e['type'] == 'way':
            g = e.get('geometry') or []
            if not g:
                continue
            lng, lat = sum(p['lon'] for p in g) / len(g), sum(p['lat'] for p in g) / len(g)
        else:
            lng, lat = e.get('lon'), e.get('lat')
        if lng is None or (boundary and not boundary.inside(lng, lat, 30)):
            continue
        x, y = loc(lng, lat, origin)
        if t.get('highway') == 'bus_stop' or t.get('amenity') == 'shelter':
            # a shelter: a roof on two posts and a glass back, a pole with the stop's sign beside it
            m.box(x, y, 2.3, 3.0, 1.5, .18, 0.0, 'plain', COL['shelterroof'], 'plain', COL['shelterroof'], True)
            m.box(x + .6, y + .6, 0, .12, .12, 2.3, 0.0, 'plain', COL['pole'], 'plain', COL['pole'], True)
            m.box(x - .6, y + .6, 0, .12, .12, 2.3, 0.0, 'plain', COL['pole'], 'plain', COL['pole'], True)
            m.box(x, y + .72, .3, 2.8, .06, 2.0, 0.0, 'glass', COL['shelter'], 'plain', COL['shelter'], True)
            nb += 1
        elif t.get('highway') == 'traffic_signals':
            m.box(x, y, 0, .16, .16, 5.8, 0.0, 'plain', COL['pole'], 'plain', COL['pole'], True)
            m.box(x, y, 4.6, .42, .34, 1.15, 0.0, 'plain', COL['dark'], 'plain', COL['dark'], True)
            m.box(x, y - .18, 5.35, .22, .03, .22, 0.0, 'sign', COL['red'], 'sign', COL['red'], True)
            m.box(x, y - .18, 4.95, .22, .03, .22, 0.0, 'sign', COL['amber'], 'sign', COL['amber'], True)
            m.box(x, y - .18, 4.6, .22, .03, .22, 0.0, 'sign', COL['green'], 'sign', COL['green'], True)
            ns += 1
        elif t.get('man_made') == 'flagpole':
            m.box(x, y, 0, .1, .1, 11.0, 0.0, 'plain', COL['white'], 'plain', COL['white'], True)
            m.box(x + .65, y, 8.6, 1.3, .03, .85, 0.0, 'sign', COL['blue'], 'sign', COL['red'], True)
            nf += 1
        elif t.get('man_made') == 'water_tower':
            m.cylinder(x, y, 14.0, 22.0, 4.5, 'plain', COL['tank'], seg=20, cap_mat='plain', cap_col=COL['tank'])
            for k in range(4):
                a = math.pi / 2 * k + math.pi / 4
                m.box(x + 3.0 * math.cos(a), y + 3.0 * math.sin(a), 0, .8, .8, 14.0, 0.0, 'plain', COL['pier'], 'plain', COL['pier'], True)
            nt += 1
    print('  bus shelters %d, signals %d, flagpoles %d, water towers %d' % (nb, ns, nf, nt))
