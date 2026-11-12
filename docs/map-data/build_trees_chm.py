#!/usr/bin/env python3
"""
Real trees for the City view, from Meta and the World Resources Institute's global canopy height map (1.2 m resolution, open data on AWS:
dataforgood-fb-data, forests/v1/alsgedi_global_v6_float), read through GDAL's HTTP range requests so only the window we need comes down.

The canopy height of every metre of the barangay and Newport-NAIA is a picture of how high the leaves stand there. Each crown shows
as a blob: a local maximum of the (smoothed) picture is a tree, its height is the picture's height there, and its crown is as wide as the
blob. That is what trees.json holds: where each stands, how high it is, how wide its crown. Trees that OpenStreetMap maps by hand are kept too.

Writes admin/assets/map/city-detail.json 'trees' (replacing the planted ones) in the same format: [lng, lat, canopy radius m, height m,
variation, shape (0 deciduous, 1 evergreen, 2 palm), mapped(1)/measured(2)/planted(0)].

Run:  python docs/map-data/build_trees_chm.py        Needs: pip install rasterio scipy numpy
"""
import json, math, os, sys

import numpy as np
import rasterio
from rasterio.warp import transform_bounds
from rasterio.windows import from_bounds
from scipy.ndimage import gaussian_filter, maximum_filter, label, binary_dilation

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from boundary import Boundary

MAP = os.path.normpath(os.path.join(HERE, '..', '..', 'admin', 'assets', 'map'))
ZOOM9 = 9
AREA = (120.9996, 14.5019, 121.0328, 14.5412)     # west, south, east, north: the barangay and the whole Newport / NAIA zone


def quadkey(lng, lat, z):
    x = int((lng + 180) / 360 * 2 ** z)
    y = int((1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * 2 ** z)
    return ''.join(str(((x >> (z - i)) & 1) + 2 * ((y >> (z - i)) & 1)) for i in range(1, z + 1))


def main():
    qk = quadkey((AREA[0] + AREA[2]) / 2, (AREA[1] + AREA[3]) / 2, ZOOM9)
    url = '/vsicurl/https://dataforgood-fb-data.s3.amazonaws.com/forests/v1/alsgedi_global_v6_float/chm/%s.tif' % qk
    print('reading', url)
    with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN='EMPTY_DIR', CPL_VSIL_CURL_ALLOWED_EXTENSIONS='.tif'):
        with rasterio.open(url) as ds:
            b = transform_bounds('EPSG:4326', ds.crs, *AREA)
            win = from_bounds(*b, transform=ds.transform)
            a = ds.read(1, window=win).astype('float32')
            tr = ds.window_transform(win)
    print('window', a.shape, 'tallest %.0f m' % a.max())
    px = tr.a
    x0, y0 = tr.c, tr.f
    B = Boundary()
    # smooth, then each local maximum above 3 m is a tree; two trees closer than 3.5 m are one
    sm = gaussian_filter(a, 1.1)
    peak = (sm == maximum_filter(sm, size=5)) & (sm >= 3.0)
    ys, xs = np.nonzero(peak)
    trees = []
    # the crown's width: how far the picture stays above 60% of the peak, along four directions
    for y, x in zip(ys, xs):
        h = float(sm[y, x])
        rr = 0
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            k = 0
            while k < 9:
                yy, xx = y + dy * (k + 1), x + dx * (k + 1)
                if not (0 <= yy < sm.shape[0] and 0 <= xx < sm.shape[1]) or sm[yy, xx] < .6 * h:
                    break
                k += 1
            rr += k
        r = max(1.8, min(6.0, (rr / 4 + .8) * px))
        X, Y = x0 + (x + .5) * px, y0 - (y + .5) * px
        lng = X / 20037508.34 * 180
        lat = math.degrees(2 * math.atan(math.exp(Y / 20037508.34 * math.pi)) - math.pi / 2)
        if not (AREA[0] <= lng <= AREA[2] and AREA[1] <= lat <= AREA[3]):
            continue
        trees.append([round(lng, 6), round(lat, 6), round(r, 1), round(h, 1), round(((x * 7 + y * 13) % 100) / 100, 2), 0, 2])
    print('trees found:', len(trees))
    # palms are tall and narrow: a crown under 2.6 m wide that stands over 9 m
    for t in trees:
        if t[3] >= 9 and t[2] <= 2.6:
            t[5] = 2
    # keep the ones inside the boundary or in the Newport / NAIA zone, drop the ones standing on a building (the map's building footprints)
    bpath = os.path.join(MAP, 'buildings.json')
    from shapely.geometry import Point, Polygon
    from shapely.strtree import STRtree
    MX, MY = 111320 * math.cos(math.radians(14.525)), 110574
    bld = json.load(open(bpath, encoding='utf-8'))['b']
    polys = [Polygon([(b[0][i] * MX, b[0][i + 1] * MY) for i in range(0, len(b[0]), 2)]).buffer(0) for b in bld]
    tree = STRtree(polys)
    keep = []
    for t in trees:
        pt = Point(t[0] * MX, t[1] * MY)
        hit = tree.query(pt.buffer(1.0))
        if any(polys[i].contains(pt) for i in hit):
            continue
        if not B.inside(t[0], t[1]):
            continue
        keep.append(t)
    print('off buildings:', len(keep))
    path = os.path.join(MAP, 'city-detail.json')
    d = json.load(open(path, encoding='utf-8'))
    mapped = [t for t in d['trees'] if t[6] == 1]
    d['trees'] = mapped + keep
    d['about'] = d['about'].replace('trees: [', 'trees (measured ones from the Meta / WRI canopy height map, 2 in the last field): [', 1) if 'canopy height map' not in d['about'] else d['about']
    json.dump(d, open(path, 'w', encoding='utf-8'), separators=(',', ':'))
    print('wrote', path, 'with', len(d['trees']), 'trees (%d mapped, %d measured)' % (len(mapped), len(keep)), os.path.getsize(path) // 1024, 'KB')


main()
