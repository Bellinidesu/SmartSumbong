#!/usr/bin/env python3
"""
Builds admin/assets/map/buildings.json: every building in the map area, for the Spatial Distribution City view
to stand up with windows and pitched roofs.

Footprints come from Overture Maps (OpenStreetMap, plus Google Open Buildings and Microsoft ML Buildings for the
houses OpenStreetMap does not have); tags (height, building:levels, roof:shape, colours, names, the kind of
building) come from OpenStreetMap through Overpass and are joined by OpenStreetMap's own way id.

What is real and what is estimated:
  * a footprint is real;
  * a height is real where OpenStreetMap or Overture has one (height, levels); otherwise ESTIMATED from the
    footprint's size, with a stable variation, because nothing open says how tall a house is;
  * a roof is PITCHED (gable, or hip if square) on a small, compact, low building and flat otherwise; this is
    drawn from what the satellite picture shows of this neighbourhood (nearly every house has a pitched
    sheet-metal roof), not read from each house; its colour is picked from the colours those roofs have here
    (rust red, brick, blue, green, grey, cream), not each house's own colour. A roof:shape or roof:colour tag
    in OpenStreetMap wins over all of that.

Only what is inside the Barangay 183 boundary is kept (boundary.py): the City view shows nothing outside it.

Needs:  pip install overturemaps      Run:  python docs/map-data/build_buildings.py
Edit BBOX if the map area changes (spatial.php: AREA).
"""
import json, math, os, subprocess, sys, tempfile, time, urllib.parse, urllib.request, zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from boundary import Boundary
import re as _re
import facts as _facts

BBOX = (121.0007, 14.5126, 121.0304, 14.5412)   # west, south, east, north (the map area and a margin for the tilted horizon)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'admin', 'assets', 'map', 'buildings.json')
MIRRORS = ['overpass.openstreetmap.fr', 'overpass-api.de', 'z.overpass-api.de', 'overpass.kumi.systems']
UA = 'SmartSumbong/1.0 (barangay portal; contact acelediac@gmail.com)'
LAT0 = math.radians((BBOX[1] + BBOX[3]) / 2)
MX, MY = 111320 * math.cos(LAT0), 110574


def overpass(q):
    for h in MIRRORS:
        try:
            req = urllib.request.Request('https://%s/api/interpreter' % h, data=urllib.parse.urlencode({'data': q}).encode(), headers={'User-Agent': UA})
            with urllib.request.urlopen(req, timeout=150) as r:
                return json.loads(r.read().decode('utf-8'))['elements']
        except Exception as e:
            print('  %s: %s' % (h, e), file=sys.stderr)
            time.sleep(3)
    raise SystemExit('Overpass is not answering; try again later')


def area_m2(ring):
    s = 0
    for i in range(len(ring)):
        x1, y1 = ring[i][0] * MX, ring[i][1] * MY
        x2, y2 = ring[(i + 1) % len(ring)][0] * MX, ring[(i + 1) % len(ring)][1] * MY
        s += x1 * y2 - x2 * y1
    return abs(s) / 2


def hull(pts):
    pts = sorted(set(pts))
    if len(pts) < 3:
        return pts
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo = []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    up = []
    for p in reversed(pts):
        while len(up) >= 2 and cross(up[-2], up[-1], p) <= 0:
            up.pop()
        up.append(p)
    return lo[:-1] + up[:-1]


def obb(ring):
    """Smallest rectangle round the footprint: (centre lng, centre lat, long side m, short side m, angle of the long side, rad)."""
    pts = [(x * MX, y * MY) for x, y in ring]
    h = hull(pts)
    best = None
    for i in range(len(h)):
        a, b = h[i], h[(i + 1) % len(h)]
        th = math.atan2(b[1] - a[1], b[0] - a[0])
        c, s = math.cos(-th), math.sin(-th)
        us = [p[0] * c - p[1] * s for p in h]
        vs = [p[0] * s + p[1] * c for p in h]
        du, dv = max(us) - min(us), max(vs) - min(vs)
        if best is None or du * dv < best[0]:
            cu, cv = (max(us) + min(us)) / 2, (max(vs) + min(vs)) / 2
            best = (du * dv, du, dv, th, cu, cv)
    _, du, dv, th, cu, cv = best
    cx = cu * math.cos(th) - cv * math.sin(th)
    cy = cu * math.sin(th) + cv * math.cos(th)
    if dv > du:
        du, dv, th = dv, du, th + math.pi / 2
    return cx / MX, cy / MY, du, dv, th


def hash01(x, y, salt=''):
    return (zlib.crc32(('%.6f,%.6f%s' % (x, y, salt)).encode()) % 100000) / 100000.0


# roof colours seen from above in this neighbourhood: rust red, brick, blue, green, grey, cream, brown, white
ROOF_P = [.34, .15, .11, .09, .14, .07, .05, .05]
ROOF_HEX = ['#B5473A', '#C96A3A', '#2F5FB5', '#2E7D5B', '#8D9097', '#D9C9A3', '#5C4033', '#E8E8E8']


def nearest_roof(hexv):
    try:
        r, g, b = [int(hexv[i:i + 2], 16) for i in (1, 3, 5)]
    except Exception:
        return None
    return min(range(len(ROOF_HEX)), key=lambda i: sum((int(ROOF_HEX[i][j:j + 2], 16) - v) ** 2 for j, v in zip((1, 3, 5), (r, g, b))))


def pick_roof(u):
    acc = 0
    for i, p in enumerate(ROOF_P):
        acc += p
        if u < acc:
            return i
    return 0


def parse_num(v):
    try:
        return float(str(v).replace('m', '').strip())
    except Exception:
        return None


def main():
    tmp = os.path.join(tempfile.mkdtemp(), 'ov.geojson')
    subprocess.check_call([sys.executable, '-m', 'overturemaps', 'download', '--bbox=%s,%s,%s,%s' % BBOX, '-f', 'geojson', '-t', 'building', '-o', tmp])
    feats = json.load(open(tmp, encoding='utf-8'))['features']
    bb = '%s,%s,%s,%s' % (BBOX[1], BBOX[0], BBOX[3], BBOX[2])
    print('tags from OpenStreetMap...')
    els = overpass('[out:json][timeout:150];(way["building"]["building"!="yes"](%s);way["building"][~"^(height|building:levels|roof:shape|roof:colour|roof:levels|building:colour|name|amenity|shop|tourism|office)$"~"."](%s););out tags;' % (bb, bb))
    tags = {e['id']: e.get('tags', {}) for e in els}
    out = []
    info = {}
    B = Boundary()
    # a landmark's building is kept even when its middle lies outside the boundary (the airport terminals are bigger than the barangay's edge)
    from shapely.geometry import Point, Polygon as _P
    lmf = json.load(open(os.path.join(os.path.dirname(OUT), 'landmarks.geojson'), encoding='utf-8'))['features']
    lm_pts = [Point(f['geometry']['coordinates'][0] * MX, f['geometry']['coordinates'][1] * MY) for f in lmf]
    def holds_landmark(ring):
        poly = _P([(x * MX, y * MY) for x, y in ring])
        if not poly.is_valid:
            poly = poly.buffer(0)
        return any(poly.distance(p) < 28 for p in lm_pts)
    stats = {'pitched': 0, 'flat': 0, 'real_h': 0}
    for f in feats:
        p = f['properties']
        src = (p.get('sources') or [{}])[0] or {}
        t = {}
        rid = src.get('record_id') or ''
        if src.get('dataset') == 'OpenStreetMap' and rid.startswith('w'):
            try:
                t = tags.get(int(rid[1:].split('@')[0]), {})
            except ValueError:
                t = {}
        g = f['geometry']
        polys = [g['coordinates']] if g['type'] == 'Polygon' else g['coordinates'] if g['type'] == 'MultiPolygon' else []
        for poly in polys:
            ring = [(round(x, 6), round(y, 6)) for x, y in poly[0]][:-1]
            if len(ring) < 3:
                continue
            a = area_m2(ring)
            if a < 10:
                continue
            cx, cy, L, W, th = obb(ring)
            if not B.inside(cx, cy, 12) and not (a > 400 and holds_landmark(ring)):
                continue
            fill = a / max(1.0, L * W)
            aspect = L / max(0.5, W)
            u = hash01(cx, cy)
            # height
            h = parse_num(t.get('height')) or parse_num(p.get('height'))
            lv = parse_num(t.get('building:levels')) or parse_num(p.get('num_floors'))
            est = 0
            if h:
                stats['real_h'] += 1
            elif lv:
                h = lv * 3.1 + 1.2
                stats['real_h'] += 1
            else:
                est = 1
                if a >= 900:
                    h = 8 + u * 5
                elif a >= 300:
                    h = 5.5 + u * 5
                elif a >= 120:
                    h = (6.4, 6.4, 9.6)[int(u * 3)]
                elif a >= 45:
                    h = (3.4, 6.4, 6.4, 9.6)[int(u * 4)]
                else:
                    h = 3.4 if u < .7 else 6.4
            kind = (t.get('building') or p.get('class') or '').lower()
            name = ((p.get('names') or {}).get('primary') or t.get('name') or '')
            cls = (p.get('class') or t.get('building') or '')
            # a fact found for this building (facts.py) beats a guess from its size
            for pat, fl, why in _facts.FLOORS:
                if name and _re.search(pat, name, _re.I) and fl:
                    h, est = fl * 3.4 + 1.2, 0
                    stats['real_h'] += 1
                    break
            # the Newport side, where nothing says how tall a wide building is, is hotels, condominiums and malls, not sheds: a stand-in
            if est and 121.0140 < cx < 121.0240 and 14.5120 < cy < 14.5262 and a >= 1200 and 'hangar' not in name.lower():
                h = 31.0 if a >= 2500 else 24.0 if a >= 1700 else 17.0
            civic = kind in ('commercial', 'retail', 'industrial', 'warehouse', 'office', 'public', 'civic', 'school', 'hospital', 'hotel', 'supermarket', 'terminal', 'train_station', 'transportation', 'government', 'hangar', 'roof', 'garage', 'garages', 'parking', 'service')
            shape = (t.get('roof:shape') or '').lower()
            pitched = (not civic and shape not in ('flat',) and 22 <= a <= 450 and fill >= .78 and aspect <= 4.8 and h <= 11.5) or shape in ('gabled', 'gable', 'hipped', 'hip', 'pyramidal') and a <= 900
            rt = 0
            if pitched:
                rt = 2 if (shape in ('hipped', 'hip', 'pyramidal') or aspect < 1.25) else 1
                stats['pitched'] += 1
            else:
                stats['flat'] += 1
            ci = nearest_roof(t.get('roof:colour') or t.get('building:colour') or '')
            if ci is None:
                ci = pick_roof(hash01(cx, cy, 'c'))
            flat_ring = []
            for x, y in ring:
                flat_ring += [x, y]
            if name or cls:
                info[len(out)] = [name, cls]
            out.append([flat_ring, round(h, 1), rt, ci, round(cx, 6), round(cy, 6), round(L, 1), round(W, 1), round(th, 3), est])
    data = {'about': 'Footprints: Overture Maps (OpenStreetMap, Google Open Buildings, Microsoft ML Buildings). Tags: OpenStreetMap. Heights are estimated where no source has one; pitched roofs and roof colours are stylised from the satellite look of the neighbourhood. Built by docs/map-data/build_buildings.py.',
            'info': info, 'roofHex': ROOF_HEX, 'fields': '[ring (lng,lat flat), height m, roof 0 flat 1 gable 2 hip, roof colour index, centre lng, centre lat, long side m, short side m, angle rad, height estimated]', 'b': out}
    with open(OUT, 'w', encoding='utf-8') as fh:
        json.dump(data, fh, separators=(',', ':'))
    print('buildings: %d (pitched %d, flat %d, real heights %d) %d KB' % (len(out), stats['pitched'], stats['flat'], stats['real_h'], os.path.getsize(OUT) // 1024))


main()
