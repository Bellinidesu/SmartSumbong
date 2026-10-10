"""admin/assets/map/zones.json: the zones the City view treats differently. 'quiet' is a list of rings (lng, lat flat) inside which the by-rule details (doors, windows, air-conditioners, dishes, tanks,
awnings, balconies, solar panels, masts, rims) are not added: the building stays footprint, height, colour. Today: Villamor Air Base (docs/map-data/zones/villamor-air-base.md).
    python docs/map-data/tools/build_zones.py"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
import plain
v = plain.villamor()
quiet = []
if v is not None:
    quiet.append([round(c, 6) for xy in list(v.exterior.coords)[:-1] for c in xy])
out = os.path.join(HERE, '..', '..', '..', 'admin', 'assets', 'map', 'zones.json')
json.dump({'about': 'Zones of the City view (build_zones.py). quiet: no by-rule detail.', 'quiet': quiet}, open(out, 'w'), separators=(',', ':'))
print('zones.json: %d quiet zone(s), %d points' % (len(quiet), sum(len(q) // 2 for q in quiet)))
