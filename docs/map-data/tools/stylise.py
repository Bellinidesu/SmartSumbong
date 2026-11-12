"""
For every building of the Newport - NAIA zone that Mapillary's 360 panoramas can see, read what it really looks like from the street (see
mly_rectify.py) and keep only a few numbers per building: its wall colour, how much of its face is glass, and the colour of its ground floor.
Nothing but these numbers is kept (no photograph is stored or shipped): zone.py draws the building in our own style, from our own palette, but
leaning the way the real one does. Mapillary images are CC BY-SA 4.0 (credited in Settings, Appearance, Credits).

Run:  python docs/map-data/tools/stylise.py [--limit N] [--min-h 10]       writes docs/map-data/landmarks/facade-style.json
"""
import colorsys, json, math, os, sys, concurrent.futures as cf

import numpy as np
from shapely.geometry import Polygon, LineString

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mly_rectify as R

ROOT = R.ROOT
MX, MY = R.MX, R.MY
ZONE = (121.0105, 14.5120, 121.0240, 14.5262)
OUT = os.path.join(HERE, '..', 'landmarks', 'facade-style.json')


def read_panos():
    p = os.path.join(os.environ.get('LOCALAPPDATA', ''), 'Temp', 'ic', 'src', 'mly_zone.json')
    if not os.path.exists(p):
        p = os.path.join(HERE, 'mly_zone.json')
    return [i for i in json.load(open(p)) if i.get('is_pano') and i.get('computed_geometry')]


def classify(arr):
    """Per pixel: sky, leaf, glass, wall."""
    a = arr.astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    lum = .299 * r + .587 * g + .114 * b
    mx, mn = a.max(-1), a.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1)
    leaf = (g > r + 6) & (g > b + 4) & (sat > .15)
    sky = (lum > 190) & (b >= r - 4) & (sat < .35) | (lum > 238)
    glass = ~leaf & ~sky & ((lum < 70) | ((b > r + 10) & (b > g - 4) & (sat > .12)))
    wall = ~leaf & ~sky & ~glass & (lum >= 70) & (lum <= 235)
    return sky, leaf, glass, wall


def facade_numbers(rect_list):
    """rect_list: [(array, weight)] from the same building's faces, ground to roof."""
    cols, wts, glass_f, base_cols = [], [], [], []
    for arr, w in rect_list:
        h = arr.shape[0]
        sky, leaf, glass, wall = classify(arr)
        lo, hi = int(h * .22), int(h * .92)               # above the shopfronts and trees, below the roof edge
        wm = wall[lo:hi]
        gm = glass[lo:hi]
        solid = int(wm.sum() + gm.sum())
        if solid < 250:
            continue
        cols.append(np.median(arr[lo:hi][wm], axis=0) if wm.sum() > 120 else None)
        wts.append(w)
        glass_f.append(gm.sum() / solid)
        # the ground floor
        bl = arr[int(h * .62):int(h * .96)]
        bw = wall[int(h * .62):int(h * .96)]
        base_cols.append(np.median(bl[bw], axis=0) if bw.sum() > 80 else None)
    if not wts:
        return None
    def wavg(vals):
        v = [(c, w) for c, w in zip(vals, wts) if c is not None]
        if not v:
            return None
        return (sum(np.asarray(c) * w for c, w in v) / sum(w for c, w in v)).tolist()
    return dict(wall=wavg(cols), base=wavg(base_cols), glass=float(np.average(glass_f, weights=wts)), n=len(wts))


def process(args):
    k, b, polys_near, imgs = args
    origin = (b[4], b[5])
    ring = [((b[0][i] - origin[0]) * MX, (b[0][i + 1] - origin[1]) * MY) for i in range(0, len(b[0]), 2)]
    h = min(b[1], 60.0)
    n = len(ring)
    cands = []
    for i in range(n):
        a_, b_ = ring[i], ring[(i + 1) % n]
        ln = math.hypot(b_[0] - a_[0], b_[1] - a_[1])
        if ln < 8:
            continue
        mid = ((a_[0] + b_[0]) / 2, (a_[1] + b_[1]) / 2)
        ux, uy = (b_[0] - a_[0]) / ln, (b_[1] - a_[1]) / ln
        nx, ny = uy, -ux
        ps = R.nearest_panos(imgs, (origin[0] + mid[0] / MX, origin[1] + mid[1] / MY), origin, rmin=9, rmax=80, limit=40)
        for d, im in ps:
            lg, lt = im['computed_geometry']['coordinates']
            cx, cy = (lg - origin[0]) * MX, (lt - origin[1]) * MY
            vx, vy = cx - mid[0], cy - mid[1]
            dd = math.hypot(vx, vy)
            cs = (vx * nx + vy * ny) / dd
            if cs < .55:
                continue
            ls = LineString([(mid[0] + nx * .6, mid[1] + ny * .6), (cx, cy)])
            if any(o.intersects(ls) for o in polys_near):
                continue
            cands.append((cs * ln / (1 + dd / 30), i, im, a_, b_))
    cands.sort(key=lambda t: -t[0])
    used, rects = set(), []
    for score, i, im, a_, b_ in cands:
        if (i, im['id']) in used or len([1 for u in used if u[0] == i]) >= 2 or len(rects) >= 4:
            continue
        used.add((i, im['id']))
        try:
            pano, meta = R.fetch(im['id'])
            arr, dist, ang = R.rectify(pano, meta, a_, b_, h, origin)
        except Exception as e:
            continue
        rects.append((arr, score))
    if not rects:
        return k, None
    return k, facade_numbers(rects)


def main():
    lim = 10 ** 9
    minh = 10
    if '--limit' in sys.argv:
        lim = int(sys.argv[sys.argv.index('--limit') + 1])
    if '--min-h' in sys.argv:
        minh = float(sys.argv[sys.argv.index('--min-h') + 1])
    doc = json.load(open(os.path.join(ROOT, 'admin', 'assets', 'map', 'buildings.json')))
    bld = doc['b']
    imgs = read_panos()
    print('panoramas:', len(imgs))
    sel = [i for i, b in enumerate(bld) if ZONE[0] <= b[4] <= ZONE[2] and ZONE[1] <= b[5] <= ZONE[3] and b[1] >= minh]
    sel = sel[:lim]
    print('buildings to read:', len(sel))
    cache = {}
    if os.path.exists(OUT):
        cache = json.load(open(OUT))
    polys = {}
    def poly_of(q):
        return Polygon([(q[0][k] , q[0][k + 1]) for k in range(0, len(q[0]), 2)]).buffer(0)
    jobs = []
    for i in sel:
        key = '%.5f,%.5f' % (bld[i][4], bld[i][5])
        if key in cache:
            continue
        b = bld[i]
        origin = (b[4], b[5])
        near = []
        for q in bld:
            if q is b or abs(q[4] - b[4]) > .0012 or abs(q[5] - b[5]) > .0012:
                continue
            near.append(Polygon([((q[0][k] - origin[0]) * MX, (q[0][k + 1] - origin[1]) * MY) for k in range(0, len(q[0]), 2)]).buffer(0))
        jobs.append((key, b, near, imgs))
    print('new:', len(jobs))
    done = 0
    with cf.ThreadPoolExecutor(6) as ex:
        for key, res in ex.map(process, jobs):
            cache[key] = res
            done += 1
            if done % 20 == 0:
                json.dump(cache, open(OUT, 'w'), separators=(',', ':'))
                print(done, '/', len(jobs), flush=True)
    json.dump(cache, open(OUT, 'w'), separators=(',', ':'))
    ok = [v for v in cache.values() if v]
    print('read', len(ok), 'of', len(cache), 'buildings')


main()
