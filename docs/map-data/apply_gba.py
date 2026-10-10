"""Puts the atlas's heights (gba.py) on the estimated buildings of admin/assets/map/buildings.json without rebuilding the footprints:  python docs/map-data/apply_gba.py
(build_buildings.py does the same when it runs, so a rebuild keeps them.)"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gba
P = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'admin', 'assets', 'map', 'buildings.json')
d = json.load(open(P, encoding='utf-8'))
idx = gba.Index(gba.load((121.0007, 14.5126, 121.0304, 14.5412)))
n = tall = 0
changed = []
KEEP = {'hangar', 'warehouse', 'industrial', 'service', 'garage', 'garages'}   # long-span sheds: the atlas reads 3 m for a hangar, our footprint guess (8 to 13 m) is nearer
for i, b in enumerate(d['b']):
    if not b[9] or (len(b) > 13 and b[13]):
        continue
    nm_cls = (d['info'].get(str(i)) or ['', ''])
    if nm_cls[1] in KEEP or 'hangar' in nm_cls[0].lower():
        continue
    ring = [(b[0][k], b[0][k + 1]) for k in range(0, len(b[0]), 2)]
    h = gba.height(idx, ring)
    if h is None:
        continue
    if b[6] * b[7] >= 900:
        h = max(h, b[1])                   # a wide roof is what the atlas reads lowest: never below our own guess for a big building
    if abs(h - b[1]) > .05:
        changed.append((b[1], h))
    b[1] = h
    while len(b) < 14:
        b.append(0)
    b[13] = 1                       # 1: the height is the atlas's
    n += 1
    tall += h >= 20
d['about'] = d['about'].replace('Heights are estimated where no source has one;', 'Heights are OpenStreetMap or Overture where they have one, else the Global Building Atlas (TU Munich, CC BY 4.0; scaled up on towers, where it reads low), else estimated from the footprint;')
if 'height source' not in d['fields']:
    d['fields'] = d['fields'].rstrip(']') + ', baked ... (see below), height source 0 tag/fact/guess 1 atlas]'
json.dump(d, open(P, 'w', encoding='utf-8'), separators=(',', ':'))
print('atlas heights put on %d buildings (%d of them 20 m or more); mean change %+.1f m' % (n, tall, sum(h - o for o, h in changed) / max(1, len(changed))))
