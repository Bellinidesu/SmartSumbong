"""Compares our Barangay 183 boundary (OpenStreetMap relation 2988704, the row in barangay_boundary) with the official
PSA/NAMRIA one, and writes the official outline to docs/data/brgy183-psa-namria.geojson. Standard library only; run by
hand when either source changes (see docs/BOUNDARY.md):
    python tools/boundary_compare.py
The official shapefile is 272 MB, so only Barangay 183's record is fetched: the .dbf finds its row, the .shx gives its
byte range, and an HTTP range request reads those bytes. Source: OCHA HDX cod-ab-phl (CC BY-IGO, NAMRIA and PSA), as
cleaned and kept by altcoder/philippines-psgc-shapefiles (MIT)."""
import json, math, os, re, struct, subprocess, sys, tempfile, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = 'altcoder/philippines-psgc-shapefiles/main/data/2023/BgySubMuns/phl_admbnda_adm4_psa_namria_20231106'
LFS, RAW = 'https://media.githubusercontent.com/media/' + BASE, 'https://raw.githubusercontent.com/' + BASE
NAME, CITY = 'Barangay 183', 'Pasay City'


def get(url, rng=None):
    # curl, not urllib: GitHub's LFS host drops a range answer that urllib reads, and curl retries
    # and it cuts long downloads short now and then (curl exit 18), so a short answer is tried again
    args = ['curl', '-sfL', '--http1.1', '--retry', '4'] + (['-r', rng] if rng else []) + [url]
    for _ in range(6):
        r = subprocess.run(args, capture_output=True)
        if r.returncode == 0:
            return r.stdout
    sys.exit('download failed (curl %d): %s' % (r.returncode, url))


def official():
    dbf = get(LFS + '.dbf')
    n, hlen, rlen = struct.unpack('<IHH', dbf[4:12])
    fields, p = [], 32
    while dbf[p] != 0x0D:
        fields.append((dbf[p:p + 11].split(b'\0')[0].decode(), dbf[p + 16])); p += 32
    for i in range(n):
        r, pos, rec = dbf[hlen + i * rlen: hlen + (i + 1) * rlen], 1, {}
        for name, ln in fields:
            rec[name] = r[pos:pos + ln].decode('latin-1').strip(); pos += ln
        if rec['ADM4_EN'] == NAME and rec['ADM3_EN'] == CITY:
            break
    else:
        sys.exit('not found in the .dbf')
    shx = get(RAW + '.shx')
    off, ln = struct.unpack('>ii', shx[100 + i * 8: 108 + i * 8])
    b = get(LFS + '.shp', '%d-%d' % (off * 2, off * 2 + ln * 2 + 7))
    assert struct.unpack('<i', b[8:12])[0] == 5, 'not a polygon'
    nparts, npts = struct.unpack('<ii', b[44:52])
    parts = list(struct.unpack('<%di' % nparts, b[52:52 + 4 * nparts])) + [npts]
    p0 = 52 + 4 * nparts
    pts = [list(struct.unpack('<dd', b[p0 + 16 * k: p0 + 16 * k + 16])) for k in range(npts)]
    return rec, [pts[parts[k]:parts[k + 1]] for k in range(nparts)]


def ours():
    sql = open(os.path.join(ROOT, 'supabase', 'migrations', '0005_proximity_dispatch.sql'), encoding='utf-8').read()
    wkt = re.search(r"MULTIPOLYGON\(\(\((.*?)\)\)\)", sql).group(1)
    return [[float(v) for v in p.split()] for p in wkt.split(',')]


# metres on a flat plane at the barangay's latitude: plenty for a 3 km place
KX, KY = 111320 * math.cos(math.radians(14.517)), 110574
xy = lambda p: ((p[0] - 121) * KX, (p[1] - 14.517) * KY)


def area(r):
    r = [xy(p) for p in r]
    return abs(sum(r[i][0] * r[i - 1][1] - r[i - 1][0] * r[i][1] for i in range(len(r)))) / 2e6


def inside(pt, ring):
    x, y, c = pt[0], pt[1], False
    for i in range(len(ring)):
        (x1, y1), (x2, y2) = ring[i - 1], ring[i]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c


def gap(p, ring):
    best = 1e18
    for i in range(len(ring)):
        (ax, ay), (bx, by) = ring[i - 1], ring[i]
        dx, dy = bx - ax, by - ay; L = dx * dx + dy * dy
        t = 0 if L == 0 else max(0, min(1, ((p[0] - ax) * dx + (p[1] - ay) * dy) / L))
        best = min(best, math.hypot(p[0] - ax - t * dx, p[1] - ay - t * dy))
    return best


rec, rings = official()
o = ours()
O, N = [xy(p) for p in o], [xy(p) for p in rings[0]]
both = only_o = only_n = 0
step = 10
xs, ys = [p[0] for p in O + N], [p[1] for p in O + N]
y = min(ys)
while y < max(ys):
    x = min(xs)
    while x < max(xs):
        a, c = inside((x, y), O), inside((x, y), N)
        both += a and c; only_o += a and not c; only_n += c and not a
        x += step
    y += step
k = step * step / 1e6
med = lambda v: sorted(v)[len(v) // 2]
print('official: %s, %s, code %s, valid on %s' % (rec['ADM4_EN'], rec['ADM3_EN'], rec['ADM4_PCODE'], rec['validOn']))
print('area: ours %.2f km2, official %.2f km2' % (area(o), sum(area(r) for r in rings)))
print('overlap %.2f km2; only ours %.2f; only official %.2f; IoU %.2f' % (both * k, only_o * k, only_n * k, both / (both + only_o + only_n)))
print('official corners to our line: median %.0f m' % med([gap(p, O) for p in N]))
print('our corners to the official line: median %.0f m' % med([gap(p, N) for p in O]))
out = os.path.join(ROOT, 'docs', 'data', 'brgy183-psa-namria.geojson')
json.dump({'type': 'FeatureCollection', 'features': [{'type': 'Feature', 'properties': {
    'name': rec['ADM4_EN'], 'city': rec['ADM3_EN'], 'pcode_2023': rec['ADM4_PCODE'], 'valid_on': rec['validOn'],
    'area_sqkm': round(float(rec['AREA_SQKM']), 4),
    'source': 'NAMRIA and PSA, via OCHA HDX cod-ab-phl (CC BY-IGO) and altcoder/philippines-psgc-shapefiles (MIT)'},
    'geometry': {'type': 'Polygon', 'coordinates': [[[round(v, 7) for v in p] for p in r] for r in rings]}}]},
    open(out, 'w', encoding='utf-8', newline='\n'), separators=(',', ':'))
print('wrote', os.path.relpath(out, ROOT))
