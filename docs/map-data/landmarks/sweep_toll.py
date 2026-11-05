"""Toll booths from OpenStreetMap (barrier=toll_booth) with the direction of the road each one stands on, for the toll plaza model (zone.z_toll). Written to landmarks/poi-toll.json:
a list of {at: [lng, lat], ang: the road's direction in radians (east = 0, anticlockwise), name}.   python docs/map-data/landmarks/sweep_toll.py"""
import json, math, os, urllib.parse, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__))
BBOX = (14.5126, 121.0007, 14.5412, 121.0304)       # south, west, north, east (build_buildings.py's)
Q = '[out:json][timeout:90];node["barrier"="toll_booth"](%s,%s,%s,%s)->.t;.t out;way(around.t:25)["highway"];out geom;' % BBOX
data = None
for h in ('overpass.openstreetmap.fr', 'overpass-api.de', 'z.overpass-api.de'):
    try:
        data = json.load(urllib.request.urlopen(urllib.request.Request('https://%s/api/interpreter' % h, data=urllib.parse.urlencode({'data': Q}).encode(), headers={'User-Agent': 'SmartSumbong/1.0'}), timeout=100))
        break
    except Exception as e:
        print(h, e)
els = data['elements']
nodes = [e for e in els if e['type'] == 'node']
ways = [e for e in els if e['type'] == 'way']
LAT0 = math.radians((BBOX[0] + BBOX[2]) / 2)
MX, MY = 111320 * math.cos(LAT0), 110574
out = []
for n in nodes:
    best = None
    for w in ways:
        g = w['geometry']
        for a, b in zip(g, g[1:]):
            ax, ay, bx, by = a['lon'], a['lat'], b['lon'], b['lat']
            dx, dy = (bx - ax) * MX, (by - ay) * MY
            L2 = dx * dx + dy * dy
            if L2 < 1:
                continue
            t = max(0, min(1, (((n['lon'] - ax) * MX) * dx + ((n['lat'] - ay) * MY) * dy) / L2))
            d = math.hypot((n['lon'] - ax) * MX - t * dx, (n['lat'] - ay) * MY - t * dy)
            if best is None or d < best[0]:
                best = (d, math.atan2(dy, dx))
    out.append(dict(at=[n['lon'], n['lat']], ang=round(best[1], 3) if best else 0.0, name=(n.get('tags') or {}).get('name', 'Toll gate')))
json.dump(out, open(os.path.join(HERE, 'poi-toll.json'), 'w', encoding='utf-8'), indent=1)
print('toll booths:', len(out), ' with a road direction:', sum(1 for o in out if o['ang']))
