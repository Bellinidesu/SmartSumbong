"""Builds admin/assets/data/transit-b183.json from an Overpass answer (relations with geometry): one line per unique road (roads shared
by many routes appear once, with the list of routes that use them), plus the bus stops. Run by hand when the routes change:
    python build_transit.py overpass.json out.json"""
import json, sys, collections
d = json.load(open(sys.argv[1], encoding='utf-8'))
ways, stops = {}, {}
for el in d['elements']:
    t = el.get('tags') or {}
    if el['type'] == 'relation':
        ref = (t.get('ref') or '').strip(); name = (t.get('name') or '').strip()
        label = ref if ref and len(ref) <= 14 else (name or ref)[:34]
        if not label: continue
        mode = t.get('route', 'bus')
        for m in el.get('members', []):
            if m.get('type') != 'way' or not m.get('geometry'): continue
            line = [[round(p['lon'], 5), round(p['lat'], 5)] for p in m['geometry'] if p]      # points outside the box come back as null
            if len(line) < 2: continue
            w = ways.setdefault(m['ref'], {'g': line, 'refs': set(), 'modes': set()})
            w['refs'].add(label); w['modes'].add(mode)
    elif el['type'] == 'node' and 'lat' in el:
        stops[(round(el['lat'], 5), round(el['lon'], 5))] = (el.get('tags') or {}).get('name', '')
feats = []
for w in ways.values():
    rail = bool(w['modes'] & {'train', 'light_rail', 'subway', 'tram'})
    refs = sorted(w['refs'], key=lambda r: (len(r), r))
    feats.append({'type': 'Feature', 'properties': {'k': 'route', 'n': len(refs), 'refs': ', '.join(refs[:14]) + (' +%d more' % (len(refs) - 14) if len(refs) > 14 else ''), 'mode': 'rail' if rail else 'road'},
                  'geometry': {'type': 'LineString', 'coordinates': w['g']}})
for (lat, lng), name in stops.items():
    feats.append({'type': 'Feature', 'properties': {'k': 'stop', 'name': name}, 'geometry': {'type': 'Point', 'coordinates': [lng, lat]}})
json.dump({'type': 'FeatureCollection', 'features': feats}, open(sys.argv[2], 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
print(len(ways), 'roads,', len(stops), 'stops,', collections.Counter(min(len(w['refs']), 9) for w in ways.values()))
