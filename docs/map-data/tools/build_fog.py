"""admin/assets/map/fog.json: the fog of war's soft edge, in metres on the ground (no screen-space blur, which tears at sharp corners and in perspective). Steps outward from the barangay boundary:
for each distance d, the world minus the boundary grown by d metres; the page lays them over each other at a low opacity each, so the fog deepens the farther out you look.
    python docs/map-data/tools/build_fog.py"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
from boundary import Boundary
from shapely.geometry import Polygon, box
from shapely.ops import unary_union
M = 1 / 107500.0
b = Boundary()
base = unary_union([Polygon(r).buffer(0) for r in b.rings if len(r) > 3])
world = box(-179.9, -85, 179.9, 85)
STEPS = [15, 40, 80, 140, 230, 360]
feats = []
for k, d in enumerate(STEPS):
    g = world.difference(base.buffer(d * M, join_style=1, resolution=6).simplify(2.5 * M))
    polys = [g] if g.geom_type == 'Polygon' else list(g.geoms)
    for p in polys:
        coords = [[[round(x, 6), round(y, 6)] for x, y in p.exterior.coords]] + [[[round(x, 6), round(y, 6)] for x, y in h.coords] for h in p.interiors]
        feats.append({'type': 'Feature', 'properties': {'step': k + 1}, 'geometry': {'type': 'Polygon', 'coordinates': coords}})
out = os.path.join(HERE, '..', '..', '..', 'admin', 'assets', 'map', 'fog.json')
json.dump({'type': 'FeatureCollection', 'features': feats, 'about': 'fog steps (build_fog.py)'}, open(out, 'w'), separators=(',', ':'))
print('fog.json: %d steps, %d polygons, %d KB' % (len(STEPS), len(feats), os.path.getsize(out) // 1024))
