#!/usr/bin/env python3
"""
Builds admin/assets/map/city-detail.json: the extra detail the Spatial Distribution
City view (the tilted map) draws: trees and zebra crossings. All from OpenStreetMap
(ODbL), nothing hand-drawn.

  * every tree OpenStreetMap has mapped here (natural=tree) is drawn as it is mapped;
  * mapped greens (parks, the Villamor golf course rough, woods, grass) are planted with
    stylised trees on a jittered grid, because OpenStreetMap does not map every tree. The
    spacing says what the place is (a park is closer planted than a golf course rough);
    the golf course fairways, greens, tees, bunkers and water are left clear;
  * every highway=crossing is drawn as zebra bars across the road it sits on;
  * the golf course is drawn as it is mapped (fairways, greens, tees, bunkers, water), and the pitches,
    playgrounds, pools and tracks as flat coloured areas, as Apple Maps does.

Run:  python docs/map-data/build_city_detail.py   (only the Python standard library and
internet; the public Overpass servers are shared, so it tries several)
Edit BBOX if the map area changes (spatial.php: AREA).
"""
import json, math, os, random, sys, time, urllib.parse, urllib.request

BBOX = (14.5146, 121.0027, 14.5392, 121.0284)   # south, west, north, east
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'admin', 'assets', 'map', 'city-detail.json')
MIRRORS = ['overpass.openstreetmap.fr', 'overpass-api.de', 'z.overpass-api.de', 'overpass.kumi.systems']
UA = 'SmartSumbong/1.0 (barangay portal; contact acelediac@gmail.com)'
bb = '%s,%s,%s,%s' % BBOX


def overpass(q):
    for h in MIRRORS:
        try:
            req = urllib.request.Request('https://%s/api/interpreter' % h, data=urllib.parse.urlencode({'data': q}).encode(), headers={'User-Agent': UA})
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.loads(r.read().decode('utf-8'))['elements']
        except Exception as e:
            print('  %s: %s' % (h, e), file=sys.stderr)
            time.sleep(3)
    raise SystemExit('Overpass is not answering; try again later')


LAT0 = math.radians((BBOX[0] + BBOX[2]) / 2)
MX, MY = 111320 * math.cos(LAT0), 110574     # metres per degree of lng, lat


def ring_has(pt, ring):
    c = False
    j = len(ring) - 1
    for i in range(len(ring)):
        a, b = ring[i], ring[j]
        if (a[1] > pt[1]) != (b[1] > pt[1]) and pt[0] < (b[0] - a[0]) * (pt[1] - a[1]) / (b[1] - a[1]) + a[0]:
            c = not c
        j = i
    return c


def rings_of(el):
    """Outer rings as [(lng, lat), ...] for a way or a multipolygon relation."""
    if el['type'] == 'way' and 'geometry' in el:
        g = [(p['lon'], p['lat']) for p in el['geometry']]
        return [g] if len(g) > 3 else []
    out = []
    for m in el.get('members', []):
        if m.get('role') == 'outer' and m.get('geometry'):
            g = [(p['lon'], p['lat']) for p in m['geometry']]
            if len(g) > 3:
                out.append(g)
    return out


def area_m2(ring):
    s = 0
    for i in range(len(ring)):
        x1, y1 = ring[i][0] * MX, ring[i][1] * MY
        x2, y2 = ring[(i + 1) % len(ring)][0] * MX, ring[(i + 1) % len(ring)][1] * MY
        s += x1 * y2 - x2 * y1
    return abs(s) / 2


def main():
    random.seed(183)
    print('trees, greens, crossings from OpenStreetMap...')
    trees_el = overpass('[out:json][timeout:90];node["natural"="tree"](%s);out;' % bb)
    greens = overpass('[out:json][timeout:90];(way["leisure"~"^(park|garden|golf_course|recreation_ground|nature_reserve)$"](%s);way["landuse"~"^(grass|forest|recreation_ground|village_green|cemetery|meadow)$"](%s);'
                      'way["natural"~"^(wood|scrub|grassland)$"](%s);way["golf"](%s);relation["leisure"~"^(park|golf_course)$"](%s);relation["landuse"~"^(grass|forest)$"](%s);relation["natural"="wood"](%s););out geom tags;' % ((bb,) * 7))
    flat = overpass('[out:json][timeout:90];(way["leisure"~"^(pitch|playground|swimming_pool|track|sports_centre|stadium)$"](%s);way["golf"="driving_range"](%s););out geom tags;' % (bb, bb))
    cross_el = overpass('[out:json][timeout:90];node["highway"="crossing"](%s);out;' % bb)
    cross_ways = overpass('[out:json][timeout:90];node["highway"="crossing"](%s)->.c;way(bn.c)["highway"];out geom tags;' % bb)

    # ---- trees: [lng, lat, canopy radius m, height m, variation 0..1, shape (0 round, 1 cone), mapped 1 / planted 0] ----
    trees = []
    for n in trees_el:
        t = n.get('tags', {})
        palm = 'palm' in (t.get('species', '') + t.get('genus', '') + t.get('leaf_type', '')).lower() or t.get('genus') in ('Cocos', 'Roystonea', 'Areca', 'Veitchia', 'Washingtonia', 'Phoenix')
        trees.append([n['lon'], n['lat'], round(3.0 + random.random() * 1.6, 1), round(9 + random.random() * 4, 1) if palm else round(7 + random.random() * 4, 1), round(random.random(), 2), 2 if palm else 0, 1])
    keep_clear = []   # golf fairways, greens, tees, bunkers, water, the clubhouse
    plant = []        # (rings, spacing m, kind)
    for el in greens:
        t = el.get('tags', {})
        rings = rings_of(el)
        if not rings:
            continue
        golf = t.get('golf')
        if golf in ('fairway', 'green', 'tee', 'bunker', 'water_hazard', 'lateral_water_hazard', 'driving_range', 'clubhouse'):
            keep_clear += rings
            continue
        if t.get('leisure') == 'golf_course':
            plant.append((rings, 15, 'golf'))
        elif t.get('leisure') in ('park', 'garden', 'nature_reserve') or t.get('landuse') == 'village_green':
            plant.append((rings, 9, 'park'))
        elif t.get('natural') in ('wood', 'scrub') or t.get('landuse') == 'forest':
            plant.append((rings, 6.5, 'wood'))
        elif t.get('landuse') == 'cemetery':
            plant.append((rings, 15, 'park'))
        elif t.get('landuse') in ('grass', 'meadow', 'recreation_ground') or t.get('leisure') == 'recreation_ground':
            if sum(area_m2(r) for r in rings) > 700:
                plant.append((rings, 12, 'park'))
    for rings, step, kind in plant:
        for ring in rings:
            xs = [p[0] for p in ring]
            ys = [p[1] for p in ring]
            gx, gy = step / MX, step / MY
            y = min(ys)
            while y < max(ys):
                x = min(xs)
                while x < max(xs):
                    px, py = x + (random.random() - .5) * .7 * gx, y + (random.random() - .5) * .7 * gy
                    if ring_has((px, py), ring) and not any(ring_has((px, py), c) for c in keep_clear):
                        r = 2.3 + random.random() * 1.9
                        u = random.random()
                        shape = 2 if u < (.14 if kind == 'park' else .07) else 1 if (kind == 'wood' and u > .9) else 0   # palm, evergreen, deciduous
                        trees.append([round(px, 6), round(py, 6), round(r, 1), round((9 + random.random() * 4) if shape == 2 else (6 + r * 1.3 + random.random() * 2.5), 1), round(random.random(), 2), shape, 0])
                    x += gx
                y += gy
    print('  before thinning: %d' % len(trees))
    if len(trees) > 7000:   # keep the map light: the mapped ones first, then a share of the rest
        real = [t for t in trees if t[6]]
        rest = [t for t in trees if not t[6]]
        random.shuffle(rest)
        trees = real + rest[:7000 - len(real)]
    print('  trees: %d (%d mapped in OpenStreetMap)' % (len(trees), sum(t[6] for t in trees)))

    # ---- zebra crossings ----
    ways = {w['id']: w for w in cross_ways}
    WIDTH = {'motorway': 14, 'trunk': 13, 'primary': 12, 'secondary': 10, 'tertiary': 8, 'residential': 6, 'unclassified': 6, 'living_street': 5, 'service': 4.5}
    FOOT = ('footway', 'path', 'pedestrian', 'steps', 'cycleway', 'track')
    at_node = {}   # a crossing is a vertex of its road, so match by position
    for w in ways.values():
        for i, p in enumerate(w.get('geometry', [])):
            at_node.setdefault((round(p['lat'], 7), round(p['lon'], 7)), []).append((w, i))
    feats = []
    for n in cross_el:
        hits = at_node.get((round(n['lat'], 7), round(n['lon'], 7)), [])
        road = next(((w, i) for w, i in hits if w['tags'].get('highway') not in FOOT), None)
        foot = next(((w, i) for w, i in hits if w['tags'].get('highway') in FOOT), None)
        src = road or foot
        if not src:
            continue
        w, i = src
        g = w['geometry']
        a = g[max(0, i - 1)]
        b = g[min(len(g) - 1, i + 1)]
        ang = math.atan2((b['lat'] - a['lat']) * MY, (b['lon'] - a['lon']) * MX)   # direction of that way, east = 0
        if not road:
            ang += math.pi / 2     # a footway runs across the road, so the road runs at a right angle to it
        width = WIDTH.get(road[0]['tags'].get('highway'), 6) if road else 6
        lanes = road[0]['tags'].get('lanes') if road else None
        if lanes and lanes.isdigit():
            width = max(width, int(lanes) * 3.2)
        width = min(width, 16)
        ux, uy = math.cos(ang), math.sin(ang)
        vx, vy = -uy, ux           # along the road, across it
        cx, cy = n['lon'] * MX, n['lat'] * MY
        k = int(width / 1.1)
        bars = []
        for j in range(k):
            off = (j - (k - 1) / 2) * 1.1
            pts = []
            for dl, dw in ((-1.6, -.3), (1.6, -.3), (1.6, .3), (-1.6, .3)):
                x = cx + ux * dl + vx * (off + dw)
                y = cy + uy * dl + vy * (off + dw)
                pts.append([round(x / MX, 6), round(y / MY, 6)])
            pts.append(pts[0])
            bars.append([pts])
        feats.append({'type': 'Feature', 'properties': {}, 'geometry': {'type': 'MultiPolygon', 'coordinates': bars}})
    print('  crossings: %d' % len(feats))

    # ---- golf and sports areas, drawn flat ----
    areas = []
    for el in greens + flat:
        t = el.get('tags', {})
        golf = t.get('golf')
        k = None
        if golf in ('fairway', 'green', 'tee', 'bunker', 'driving_range'):
            k = golf
        elif golf in ('water_hazard', 'lateral_water_hazard'):
            k = 'water'
        elif t.get('leisure') == 'pitch':
            k = 'pitch:' + (t.get('sport') or 'other').split(';')[0]
        elif t.get('leisure') in ('playground', 'swimming_pool', 'track'):
            k = t['leisure']
        if not k:
            continue
        for ring in rings_of(el):
            areas.append({'type': 'Feature', 'properties': {'k': k}, 'geometry': {'type': 'Polygon', 'coordinates': [[[round(x, 6), round(y, 6)] for x, y in ring]]}})
    print('  golf and sports areas: %d' % len(areas))
    out = {'about': 'OpenStreetMap contributors (ODbL). Built by docs/map-data/build_city_detail.py. trees: [lng, lat, canopy radius m, height m, variation, shape (0 deciduous, 1 evergreen, 2 palm), mapped(1)/planted(0)]',
           'trees': trees, 'crossings': {'type': 'FeatureCollection', 'features': feats}, 'areas': {'type': 'FeatureCollection', 'features': areas}}
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(out, f, separators=(',', ':'))
    print('wrote', os.path.normpath(OUT), os.path.getsize(OUT) // 1024, 'KB')


main()
