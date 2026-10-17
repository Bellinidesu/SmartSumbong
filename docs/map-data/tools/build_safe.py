"""admin/assets/map/safe.json: which buildings hold a safe point (the same kinds as the Safe points layer, admin/layers.php, from OpenStreetMap): evacuation or shelter (assembly points, schools, community centres,
social facilities, shelters, sports halls), health facilities, fire stations and police, the barangay or town hall. Every point is matched to the footprint it stands in (or the nearest within 25 m).
Fire hydrants are points on the street, not buildings, so they are left out. Written as {p: {building index: kind letter}}, kinds e (evac), h (health), r (responder), a (hall).
    python docs/map-data/tools/build_safe.py"""
import json, os, urllib.parse, urllib.request
from shapely.geometry import Point, Polygon
from shapely.strtree import STRtree
HERE = os.path.dirname(os.path.abspath(__file__))
MAP = os.path.join(HERE, '..', '..', '..', 'admin', 'assets', 'map')
MX, MY = 107750.0, 110574.0
Q = '[out:json][timeout:90];(nwr["emergency"="assembly_point"](14.5126,121.0007,14.5412,121.0304);nwr["amenity"~"^(hospital|clinic|doctors|fire_station|police|townhall|school|community_centre|social_facility|shelter)$"](14.5126,121.0007,14.5412,121.0304);nwr["leisure"~"^(sports_hall|sports_centre)$"](14.5126,121.0007,14.5412,121.0304);nwr["office"="government"]["name"~"[Bb]arangay"](14.5126,121.0007,14.5412,121.0304););out center tags;'
els = None
for h in ('overpass.openstreetmap.fr', 'overpass-api.de', 'z.overpass-api.de'):
    try:
        els = json.load(urllib.request.urlopen(urllib.request.Request('https://%s/api/interpreter' % h, data=urllib.parse.urlencode({'data': Q}).encode(), headers={'User-Agent': 'SmartSumbong/1.0'}), timeout=100))['elements']; break
    except Exception as e:
        print(h, e)
d = json.load(open(os.path.join(MAP, 'buildings.json'), encoding='utf-8'))
polys = [Polygon([(b[0][k] * MX, b[0][k + 1] * MY) for k in range(0, len(b[0]), 2)]).buffer(0) for b in d['b']]
tree = STRtree(polys)
out = {}
RANK = 'rhea'                                   # the more urgent kind wins when a building holds two
for e in els:
    t = e.get('tags', {}); am = t.get('amenity', ''); nm = (t.get('name') or '')
    lng = e.get('lon') or (e.get('center') or {}).get('lon'); lat = e.get('lat') or (e.get('center') or {}).get('lat')
    if not lng:
        continue
    if am in ('fire_station', 'police'): k = 'r'
    elif am in ('hospital', 'clinic', 'doctors'): k = 'h'
    elif am == 'townhall' or (t.get('office') == 'government' and 'barangay' in nm.lower()): k = 'a'
    else: k = 'e'
    p = Point(lng * MX, lat * MY)
    hits = [j for j in tree.query(p.buffer(25)) if polys[j].distance(p) <= 25]
    if not hits:
        continue
    j = min(hits, key=lambda j: polys[j].distance(p))
    if str(j) not in out or RANK.index(k) < RANK.index(out[str(j)]):
        out[str(j)] = k
json.dump({'about': 'Buildings holding a safe point (build_safe.py): e evacuation or shelter, h health, r fire or police, a hall', 'p': out}, open(os.path.join(MAP, 'safe.json'), 'w'), separators=(',', ':'))
import collections
print(len(els), 'safe-point elements;', len(out), 'buildings:', dict(collections.Counter(out.values())))
