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
OUTJ = os.path.join(HERE, '..', 'landmarks', 'blend', 'ballroom_roof.json')
if '--smooth' in sys.argv:
    # no picture needed: the colour test leaves ragged tile outlines, and a hip roof over a ragged outline is lumpy; round them off (in, then out) and straighten
    R = json.load(open(OUTJ))
    out_ = []
    for z in R['tile']:
        p = Polygon(z['ring']).buffer(0).buffer(-3.0).buffer(3.0).simplify(1.0)
        for q in (p.geoms if hasattr(p, 'geoms') else [p]):
            if q.geom_type == 'Polygon' and q.area > 40:
                out_.append({'m2': round(q.area, 1), 'ring': [[round(x, 2), round(y, 2)] for x, y in list(q.exterior.coords)[:-1]]})
    # the big central roof is one clean hip: its outline becomes the tightest rectangle round it, cut to the footprint
    if out_:
        big = max(out_, key=lambda q: q['m2'])
        rect = Polygon(big['ring']).minimum_rotated_rectangle.intersection(Polygon(D['ring']).buffer(0)).simplify(0.5)
        if rect.geom_type == 'Polygon':
            big['ring'] = [[round(x, 2), round(y, 2)] for x, y in list(rect.exterior.coords)[:-1]]
            big['m2'] = round(rect.area, 1)
    R['tile'] = out_
    json.dump(R, open(OUTJ, 'w'))
    print('tile outlines smoothed: %d roofs, %.0f m2' % (len(out_), sum(q['m2'] for q in out_)))
    sys.exit(0)
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
solar = clean(solar, 12, 3, 40)
tile = clean(tile, 3, 2, 40)
sky = inside & (lum > 118) & (g >= r) & (b >= r - 4) & ((a.max(-1) - a.min(-1)) / np.maximum(a.max(-1), 1) < .25) & ~solar
sky = clean(sky, 2, 2, 20)
# the roofs in the picture lie off the footprint (the picture's lean and its registration): slide them back by sat.fit's offset, so they stand on the walls OpenStreetMap draws
SHIFT = (4.0, -0.6)

def to_local(px, py):
    lg, lt = v.ll(px, py)
    return [round((lg - o_lng) * K.MX + SHIFT[0], 2), round((lt - o_lat) * K.MY + SHIFT[1], 2)]

def polys(m, simplify_m, min_m2, rect=False):
    res = []
    lab, n = ndimage.label(m)
    for k in range(1, n + 1):
        ys, xs = np.nonzero(lab == k)
        # trace the component as a union of its pixel squares, then simplify in metres
        sq = unary_union([Polygon([(x, y), (x + 1, y), (x + 1, y + 1), (x, y + 1)]) for x, y in zip(xs[::2], ys[::2])]).buffer(1.2).buffer(-1.2) if len(xs) < 40000 else None
        if sq is None or sq.is_empty:
            continue
        for p in (sq.geoms if isinstance(sq, MultiPolygon) else [sq]):
            if rect:
                rr = p.minimum_rotated_rectangle
                if p.area / max(rr.area, 1) > .6:
                    p = rr          # a field of panels is a rectangle: the stripes between them made the colour patchy
                else:
                    p = p.convex_hull
            p = p.simplify(simplify_m / v.mpp)
            if p.area * v.mpp ** 2 >= min_m2:
                res.append({'m2': round(p.area * v.mpp ** 2, 1), 'ring': [to_local(x, y) for x, y in list(p.exterior.coords)[:-1]]})
    return res

out = {'solar': polys(solar, 0.8, 25, True), 'tile': polys(tile, 1.0, 40), 'sky': polys(sky, 0.6, 15, True), 'shift': SHIFT, 'mpp': v.mpp}
# keep each zone to the footprint (the walls the map draws); what falls outside it is the picture's lean over the street
foot = Polygon(ring).buffer(0)
# the shaded slope of a tile roof reads brown, not terracotta, so the colour test left holes: the tile roof is the tile and the solar fields together with the gaps closed, minus the flat/glass areas
_t = unary_union([Polygon(z['ring']).buffer(0) for z in out['tile'] + out['solar']]).buffer(3.5).buffer(-3.5)
_f = unary_union([Polygon(z['ring']).buffer(0) for z in out['sky']])
_t = _t.difference(_f)
out['tile'] = [{'m2': 0, 'ring': [[round(x, 2), round(y, 2)] for x, y in list(p.exterior.coords)[:-1]]} for p in (_t.geoms if hasattr(_t, 'geoms') else [_t]) if p.geom_type == 'Polygon' and p.area > 20]
for key in ('solar', 'tile', 'sky'):
    kept = []
    for z in out[key]:
        c = Polygon(z['ring']).buffer(0).intersection(foot)
        for p in (c.geoms if hasattr(c, 'geoms') else [c]):
            if p.geom_type == 'Polygon' and p.area >= 8:
                kept.append({'m2': round(p.area, 1), 'ring': [[round(x, 2), round(y, 2)] for x, y in list(p.exterior.coords)[:-1]]})
    out[key] = kept
json.dump(out, open(os.path.join(HERE, '..', 'landmarks', 'blend', 'ballroom_roof.json'), 'w'))
print('clipped: solar %d (%.0f m2), tile %d (%.0f m2), skylights %d (%.0f m2)' % (len(out['solar']), sum(q['m2'] for q in out['solar']), len(out['tile']), sum(q['m2'] for q in out['tile']), len(out['sky']), sum(q['m2'] for q in out['sky'])))
im = v.im.copy(); d = ImageDraw.Draw(im, 'RGBA')
def back(rg):
    return [((o_lng + (x - SHIFT[0]) / K.MX), (o_lat + (y - SHIFT[1]) / K.MY)) for x, y in rg]
for key, col in (('tile', (255, 140, 0, 90)), ('solar', (0, 200, 255, 110)), ('sky', (120, 255, 120, 130))):
    for s in out[key]:
        d.polygon([v.px(*p) for p in back(s['ring'])], fill=col, outline=col[:3] + (255,))
d.line([v.px(o_lng + x / K.MX, o_lat + y / K.MY) for x, y in ring], fill=(255, 255, 0, 255), width=2)
im.thumbnail((900, 900)); im.save(os.path.join(HERE, 'mly-cache', 'ballroom_roof.png'))
