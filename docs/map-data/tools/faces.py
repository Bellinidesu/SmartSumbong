"""The faces of a real building as the street sees them: every wall of its footprint that a Mapillary 360 panorama looks at squarely, unwrapped flat and upright
(mly_rectify.py). Used by the bench (to show the real thing beside the model) and by suggest.py (to read colours and rhythm off it)."""
import math, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as K
import mly_rectify as R
from shapely.geometry import LineString, Polygon


def rectified_faces(name, max_faces=3, ppm=7.0, max_px=420, min_len=10.0):
    """[(length m, edge index, PIL image of the wall from ground to roof, pano id)], longest walls first."""
    from PIL import Image
    bi, b = K.building_named(name)
    if b is None:
        return []
    imgs = [i for i in K.mly_index() if i.get('is_pano') and i.get('computed_geometry')]
    if not imgs:
        return []
    bld, _ = K.buildings()
    o = (b[4], b[5])
    ring = [((b[0][i] - o[0]) * K.MX, (b[0][i + 1] - o[1]) * K.MY) for i in range(0, len(b[0]), 2)]
    others = [Polygon([((q[0][k] - o[0]) * K.MX, (q[0][k + 1] - o[1]) * K.MY) for k in range(0, len(q[0]), 2)]).buffer(0) for q in bld if q is not b and abs(q[4] - b[4]) < .0012 and abs(q[5] - b[5]) < .0012]
    found = []
    n = len(ring)
    for i in range(n):
        a_, b_ = ring[i], ring[(i + 1) % n]
        ln = math.hypot(b_[0] - a_[0], b_[1] - a_[1])
        if ln < min_len:
            continue
        mid = ((a_[0] + b_[0]) / 2, (a_[1] + b_[1]) / 2)
        ux, uy = (b_[0] - a_[0]) / ln, (b_[1] - a_[1]) / ln
        nx, ny = uy, -ux
        for dd, im in R.nearest_panos(imgs, (o[0] + mid[0] / K.MX, o[1] + mid[1] / K.MY), o, rmin=10, rmax=90, limit=40):
            lg, lt = im['computed_geometry']['coordinates']
            cx, cy = (lg - o[0]) * K.MX, (lt - o[1]) * K.MY
            vx, vy = cx - mid[0], cy - mid[1]
            D = math.hypot(vx, vy)
            if (vx * nx + vy * ny) / D < .6 or any(q.intersects(LineString([(mid[0] + nx * .6, mid[1] + ny * .6), (cx, cy)])) for q in others):
                continue
            found.append((ln, i, im))
            break
    found.sort(key=lambda t: -t[0])
    out = []
    for ln, i, im in found[:max_faces]:
        pano, meta = R.fetch(im['id'])
        arr, dist, ang = R.rectify(pano, meta, ring[i], ring[(i + 1) % n], min(b[1], 45), o, ppm=ppm, max_px=max_px)
        out.append((ln, i, Image.fromarray(arr), im['id'], float(min(b[1], 45)), ppm))
    return out
