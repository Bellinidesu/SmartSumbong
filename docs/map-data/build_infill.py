#!/usr/bin/env python3
"""
Builds admin/assets/map/infill.json: buildings Overture Maps has that OpenStreetMap does not, for the
Spatial Distribution City view to draw as low plain blocks so that dense areas do not read as empty.

Overture Maps (CDLA Permissive 2.0 / ODbL) merges OpenStreetMap with Google Open Buildings and Microsoft ML
Buildings. Only the footprints that come from the last two are kept (OpenStreetMap's are already in the map
tiles). None of them carries a height, so the height here is an ESTIMATE from the footprint's area: a small
footprint is a one-storey house, a big one a warehouse. They are drawn as the plain blocks they are.

Needs:  pip install overturemaps      Run:  python docs/map-data/build_infill.py
Edit BBOX if the map area changes (spatial.php: AREA).
"""
import json, math, os, subprocess, sys, tempfile

BBOX = (121.0027, 14.5146, 121.0284, 14.5392)   # west, south, east, north
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'admin', 'assets', 'map', 'infill.json')
LAT0 = math.radians((BBOX[1] + BBOX[3]) / 2)
MX, MY = 111320 * math.cos(LAT0), 110574


def area_m2(ring):
    s = 0
    for i in range(len(ring)):
        x1, y1 = ring[i][0] * MX, ring[i][1] * MY
        x2, y2 = ring[(i + 1) % len(ring)][0] * MX, ring[(i + 1) % len(ring)][1] * MY
        s += x1 * y2 - x2 * y1
    return abs(s) / 2


def estimate(a):
    return 3.2 if a < 30 else 4.2 if a < 80 else 5.5 if a < 200 else 7 if a < 600 else 9


def main():
    tmp = os.path.join(tempfile.mkdtemp(), 'ov.geojson')
    subprocess.check_call([sys.executable, '-m', 'overturemaps', 'download', '--bbox=%s,%s,%s,%s' % BBOX, '-f', 'geojson', '-t', 'building', '-o', tmp])
    feats = json.load(open(tmp, encoding='utf-8'))['features']
    out = []
    for f in feats:
        src = ((f['properties'].get('sources') or [{}])[0] or {}).get('dataset')
        if src == 'OpenStreetMap':
            continue
        g = f['geometry']
        polys = [g['coordinates']] if g['type'] == 'Polygon' else g['coordinates'] if g['type'] == 'MultiPolygon' else []
        for p in polys:
            ring = [[round(x, 6), round(y, 6)] for x, y in p[0]]
            a = area_m2(ring)
            if a < 8:
                continue
            out.append({'type': 'Feature', 'properties': {'render_height': estimate(a), 'est': 1}, 'geometry': {'type': 'Polygon', 'coordinates': [ring]}})
    with open(OUT, 'w', encoding='utf-8') as fh:
        json.dump({'type': 'FeatureCollection', 'features': out, 'about': 'Overture Maps (Google Open Buildings, Microsoft ML Buildings). Heights are estimated from the footprint area.'}, fh, separators=(',', ':'))
    print('infill: %d buildings, %d KB' % (len(out), os.path.getsize(OUT) // 1024))


main()
