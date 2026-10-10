"""The Ballroom's roof from the Esri satellite (sat.py's View), in the Ballroom's own metres (way310487805.json: origin, x east, y north): the solar fields and the tile-roof area as polygons.
Written to landmarks/blend/ballroom_roof.json and drawn over the picture (mly-cache/ballroom_roof.png) to check by eye."""
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from shapely.geometry import Polygon, MultiPolygon
from shapely.ops import unary_union
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as K, sat

HERE = os.path.dirname(os.path.abspath(__file__))
D = json.load(open(os.path.join(HERE, '..', 'landmarks', 'blend', 'way310487805.json')))
o_lng, o_lat = D['origin']
ring = D['ring']
pad = 30 / K.MX
lngs = [o_lng + x / K.MX for x, y in ring]; lats = [o_lat + y / K.MY for x, y in ring]
v = sat.View((min(lngs) - pad, min(lats) - pad, max(lngs) + pad, max(lats) + pad), sat.Z, 'esri')
a = np.asarray(v.im, dtype=np.float32)
r, g, b = a[..., 0], a[..., 1], a[..., 2]
lum = a.mean(-1)
poly = Polygon([v.px(o_lng + x / K.MX, o_lat + y / K.MY) for x, y in ring]).buffer(4 / v.mpp)   # a few metres' slack: the footprint sits a little off the roof
mask = Image.new('L', v.im.size, 0); ImageDraw.Draw(mask).polygon(list(poly.exterior.coords), fill=255)
inside = np.asarray(mask) > 0
solar = inside & (b > r + 2) & (lum < 100) & (lum > 30) & (g > r - 2)       # slate blue-grey and dark: not the lighter skylights, not the brown shaded tile (red above blue)
tile = inside & (r > g + 12) & (r > b + 18) & (lum > 45)                       # sunlit terracotta and the shaded brown slope
def clean(m, close, opn, min_m2):
    m = ndimage.binary_closing(m, iterations=close)
    m = ndimage.binary_opening(m, iterations=opn)
    lab, n = ndimage.label(m)
    out = np.zeros_like(m)
    for k in range(1, n + 1):
        if (lab == k).sum() * v.mpp ** 2 >= min_m2:
            out |= lab == k
    return out
solar = clean(solar, 6, 3, 40)
tile = clean(tile, 3, 2, 40)

def to_local(px, py):
    lg, lt = v.ll(px, py)
    return [round((lg - o_lng) * K.MX, 2), round((lt - o_lat) * K.MY, 2)]

def polys(m, simplify_m, min_m2):
    res = []
    lab, n = ndimage.label(m)
    for k in range(1, n + 1):
        ys, xs = np.nonzero(lab == k)
        # trace the component as a union of its pixel squares, then simplify in metres
        sq = unary_union([Polygon([(x, y), (x + 1, y), (x + 1, y + 1), (x, y + 1)]) for x, y in zip(xs[::2], ys[::2])]).buffer(1.2).buffer(-1.2) if len(xs) < 40000 else None
        if sq is None or sq.is_empty:
            continue
        for p in (sq.geoms if isinstance(sq, MultiPolygon) else [sq]):
            p = p.simplify(simplify_m / v.mpp)
            if p.area * v.mpp ** 2 >= min_m2:
                res.append({'m2': round(p.area * v.mpp ** 2, 1), 'ring': [to_local(x, y) for x, y in list(p.exterior.coords)[:-1]]})
    return res

out = {'solar': polys(solar, 0.8, 25), 'tile': polys(tile, 1.0, 40), 'mpp': v.mpp}
json.dump(out, open(os.path.join(HERE, '..', 'landmarks', 'blend', 'ballroom_roof.json'), 'w'))
print('solar fields %d (%.0f m2), tile areas %d (%.0f m2)' % (len(out['solar']), sum(s['m2'] for s in out['solar']), len(out['tile']), sum(s['m2'] for s in out['tile'])))
im = v.im.copy(); d = ImageDraw.Draw(im, 'RGBA')
def back(rg):
    return [((o_lng + x / K.MX), (o_lat + y / K.MY)) for x, y in rg]
for key, col in (('tile', (255, 140, 0, 90)), ('solar', (0, 200, 255, 110))):
    for s in out[key]:
        d.polygon([v.px(*p) for p in back(s['ring'])], fill=col, outline=col[:3] + (255,))
d.line([v.px(o_lng + x / K.MX, o_lat + y / K.MY) for x, y in ring], fill=(255, 255, 0, 255), width=2)
im.thumbnail((900, 900)); im.save(os.path.join(HERE, 'mly-cache', 'ballroom_roof.png'))
