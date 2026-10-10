"""admin/assets/map/zones.json: the zones of the City view and what each one leaves out. The build starts from everything (every by-rule detail, every vehicle) and a zone removes from it; this file is the list of removals.
  quiet    rings (lng, lat flat) with no by-rule detail at all: Villamor Air Base
  zones    {name, ring, off}: `off` names what is left out inside the ring (first match wins; outside every ring is the residential core, which has its own list)
Switches: highrise_extras (balconies, solar panels, antenna masts), house_gadgets (air-conditioners, dishes), chimneys, tanks_most (water tanks and stair heads kept on one house in three),
awn_generic (awnings only where a place is in the building), cars_parked (no parked vehicles), cars_all (no vehicles), lamps (no street lamps), hangar_rules (no rim, tank or dish on a hangar).
The zone sheets are docs/map-data/zones/*.md.   python docs/map-data/tools/build_zones.py"""
import json, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
import plain
from shapely.geometry import Point
from shapely.ops import unary_union
M = 1 / 107500.0
MAP = os.path.join(HERE, '..', '..', '..', 'admin', 'assets', 'map')


def ring(p):
    return [round(c, 6) for xy in list(p.exterior.coords)[:-1] for c in xy]


def polys(g):
    return [g] if g.geom_type == 'Polygon' else list(g.geoms)


vil = plain.villamor()
PL = plain.load()
d = json.load(open(os.path.join(MAP, 'buildings.json'), encoding='utf-8'))
B, info = d['b'], d['info']
NP = re.compile(r'newport|marriott|marriot|resorts|belmont|okura|hilton|sheraton|holiday inn|mall|grand wing|horizon|hotel', re.I)
pts = []
for i, r in enumerate(B):
    if not (121.0140 <= r[4] <= 121.0245 and 14.5120 <= r[5] <= 14.5262) or (vil is not None and vil.contains(Point(r[4], r[5]))):
        continue
    if r[1] >= 20 or NP.search((info.get(str(i)) or ['', ''])[0] or ''):
        pts.append(Point(r[4], r[5]).buffer(70 * M))
newport = unary_union(pts).buffer(25 * M).buffer(-25 * M)
airfield = PL.area.difference(vil) if vil is not None else PL.area
golf = None
for f in os.listdir(plain.CACHE):
    if not f.endswith('.json'):
        continue
    try:
        els = json.load(open(os.path.join(plain.CACHE, f), encoding='utf-8'))
    except Exception:
        continue
    if isinstance(els, list):
        for e in els:
            if e.get('id') == 128616401 and e.get('geometry'):
                golf = plain._poly(e)
zones = []
for nm, g, off in (('Newport City', newport, ['highrise_extras', 'cars_parked']),
                   ('NAIA Terminal 3 and the airfield', airfield, ['cars_all', 'lamps', 'hangar_rules']),
                   ('Golf course and its edges', golf.buffer(20 * M) if golf is not None else None, ['cars_all', 'lamps'])):
    if g is None or g.is_empty:
        continue
    for p in polys(g):
        if p.area * 107500 * 110574 > 3000:
            zones.append({'name': nm, 'ring': ring(p), 'off': off})
core_off = ['house_gadgets', 'chimneys', 'tanks_most', 'awn_generic']
quiet = [ring(p) for p in polys(vil)] if vil is not None else []
json.dump({'about': 'Zones of the City view (build_zones.py).', 'quiet': quiet, 'zones': zones, 'core_off': core_off, 'core_cars': ['cars_service']}, open(os.path.join(MAP, 'zones.json'), 'w'), separators=(',', ':'))
print('zones.json: %d quiet, %d zone rings (%s), core off: %s' % (len(quiet), len(zones), ', '.join(sorted({z['name'] for z in zones})), core_off))
