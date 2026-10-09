#!/usr/bin/env python3
"""
The satellite view as a measuring tool, from open tile servers that need no login and no key (Esri World Imagery; Sentinel-2 cloudless by EOX as a second look).
Tiles are stitched into one picture for an area at a chosen zoom, with the exact longitude and latitude of every pixel known (Web Mercator), cached on this computer
and never committed or shipped (the imagery is the providers'; it is looked at to measure and read colours, the map draws its own roofs).

What it gives the landmark engine:
  roof(name)      the colours of a building's roof (the footprint cut out of the picture: sky-lit flat colours, shadows and plant removed), the share of the roof that is
                  plant (dark, small, scattered), a green/blue roof or a pitched one (two tones split by a ridge), and the roof's real size against the footprint's (a check on the data)
  shadow_height   a height cross-check: the length of the shadow a building casts on open ground along the sun's direction, from the time the image was taken, is a
                  floor count (needs the shadow to fall on flat ground; the answer is a range, not a figure)
  fit(name)       how well OpenStreetMap's footprint lines up with the roof in the picture (offset in metres), so a sheet's features stand where they really are

    python docs/map-data/tools/sat.py "Belmont Hotel"            roof report and a picture: the satellite beside the model's top view
    python docs/map-data/tools/sat.py --area 121.0165,14.5195,121.0205,14.5230 out.png
"""
import io, json, math, os, sys, concurrent.futures as cf

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as K

TILES = os.path.join(K.CACHE, 'tiles')
SOURCES = {
    'esri': 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    'eox': 'https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2023_3857/default/g/{z}/{y}/{x}.jpg',
}
Z = 19          # about 0.3 m a pixel at this latitude


def tile_xy(lng, lat, z):
    n = 2 ** z
    x = (lng + 180) / 360 * n
    y = (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n
    return x, y


def lnglat(x, y, z):
    n = 2 ** z
    return x / n * 360 - 180, math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / n))))


def fetch_tile(src, z, x, y):
    p = os.path.join(TILES, src, str(z), '%d_%d.jpg' % (x, y))
    if os.path.exists(p):
        return Image.open(p).convert('RGB')
    os.makedirs(os.path.dirname(p), exist_ok=True)
    data = K.get(SOURCES[src].format(z=z, x=x, y=y), timeout=40)
    open(p, 'wb').write(data)
    return Image.open(io.BytesIO(data)).convert('RGB')


class View:
    """A stitched picture of an area: pixel (px, py) is the longitude and latitude given by .ll(px, py), and the other way round with .px(lng, lat)."""
    def __init__(self, bbox, z=Z, src='esri'):
        self.z, self.src = z, src
        x0, y1 = tile_xy(bbox[0], bbox[1], z)
        x1, y0 = tile_xy(bbox[2], bbox[3], z)
        self.tx0, self.ty0, tx1, ty1 = int(x0), int(y0), int(x1), int(y1)
        W, H = (tx1 - self.tx0 + 1) * 256, (ty1 - self.ty0 + 1) * 256
        self.im = Image.new('RGB', (W, H))
        jobs = [(tx, ty) for ty in range(self.ty0, ty1 + 1) for tx in range(self.tx0, tx1 + 1)]
        with cf.ThreadPoolExecutor(8) as ex:
            for (tx, ty), t in zip(jobs, ex.map(lambda j: fetch_tile(src, z, j[0], j[1]), jobs)):
                self.im.paste(t, ((tx - self.tx0) * 256, (ty - self.ty0) * 256))
        self.mpp = 156543.03392 * math.cos(math.radians((bbox[1] + bbox[3]) / 2)) / 2 ** z

    def px(self, lng, lat):
        x, y = tile_xy(lng, lat, self.z)
        return (x - self.tx0) * 256, (y - self.ty0) * 256

    def ll(self, px, py):
        return lnglat(px / 256 + self.tx0, py / 256 + self.ty0, self.z)

    def crop(self, bbox, pad=0):
        a = self.px(bbox[0], bbox[3])
        b = self.px(bbox[2], bbox[1])
        return self.im.crop((int(a[0]) - pad, int(a[1]) - pad, int(b[0]) + pad, int(b[1]) + pad)), (int(a[0]) - pad, int(a[1]) - pad)


def footprint(name):
    bi, b = K.building_named(name)
    if b is None:
        raise SystemExit('no building called %s' % name)
    return bi, b, [(b[0][i], b[0][i + 1]) for i in range(0, len(b[0]), 2)]


def roof(name, src='esri'):
    from shapely.geometry import Polygon
    bi, b, ring = footprint(name)
    lngs, lats = [p[0] for p in ring], [p[1] for p in ring]
    pad = 25 / K.MX
    v = View((min(lngs) - pad, min(lats) - pad, max(lngs) + pad, max(lats) + pad), Z, src)
    pts = [v.px(*p) for p in ring]
    inner = Polygon(pts).buffer(-1.2 / v.mpp)          # a metre in from the parapet: the roof surface, not the wall edge in the picture
    mask = Image.new('L', v.im.size, 0)
    if not inner.is_empty:
        ImageDraw.Draw(mask).polygon(list(inner.exterior.coords) if inner.geom_type == 'Polygon' else list(max(inner.geoms, key=lambda g: g.area).exterior.coords), fill=255)
    a = np.asarray(v.im, dtype=np.float32)
    m = np.asarray(mask) > 0
    px = a[m]
    if len(px) < 200:
        return dict(name=name, error='the roof is too small in the picture')
    lum = px.mean(-1)
    sat = (px.max(-1) - px.min(-1)) / np.maximum(px.max(-1), 1)
    lo, hi = np.percentile(lum, 12), np.percentile(lum, 98)
    flat = px[(lum >= lo) & (lum <= hi)]                # the shadows and the specular highlights out
    med = np.median(flat, axis=0)
    # roof equipment: small dark and bright patches (condensers, vents, lift motor rooms) as a share of the roof
    from scipy import ndimage
    L = np.zeros(m.shape, np.float32)
    L[m] = lum
    bg = ndimage.uniform_filter(L, 31)
    dev = np.abs(L - bg) * m
    equip = (dev > 28) & m
    equip = ndimage.binary_opening(equip, iterations=1)
    lab, nlab = ndimage.label(equip)
    sizes = ndimage.sum(equip, lab, range(1, nlab + 1)) * v.mpp ** 2 if nlab else []
    objs = [s for s in sizes if 1.0 <= s <= 80]
    found = []                 # where each roof object stands (longitude, latitude), how big it is (m2), and how much brighter or darker than the roof round it
    for k in range(1, nlab + 1):
        area = float(sizes[k - 1])
        if not (1.5 <= area <= 60):
            continue
        yy, xx = np.nonzero(lab == k)
        lg, lt = v.ll(float(xx.mean()), float(yy.mean()))
        found.append(dict(lng=round(lg, 7), lat=round(lt, 7), m2=round(area, 1), dl=round(float(L[lab == k].mean() - bg[lab == k].mean()), 1)))
    found.sort(key=lambda o: -o['m2'])
    # a ridge: the two halves of the roof differ in brightness along an axis
    ys, xs = np.nonzero(m)
    best = 0.0
    for ang in range(0, 180, 15):
        t = math.radians(ang)
        proj = xs * math.cos(t) + ys * math.sin(t)
        cut = np.median(proj)
        d = abs(lum[proj < cut].mean() - lum[proj >= cut].mean()) / max(lum.mean(), 1)
        best = max(best, d)
    greenish = float(((px[:, 1] > px[:, 0] + 8) & (px[:, 1] > px[:, 2] + 4)).mean())
    return dict(name=name, src=src, mpp=round(v.mpp, 2), roof_rgb=[int(x) for x in med], roof_hex='#%02X%02X%02X' % tuple(int(x) for x in med),
                brightness=round(float(lum.mean()), 1), equipment_objects=len(objs), equipment_share=round(float(equip.sum()) / m.sum(), 3), plant_area_m2=round(float(sum(objs)), 1),
                objects=found[:12], pitched=bool(best > .22), ridge_contrast=round(best, 2), green_share=round(greenish, 2), roof_area_m2=round(float(m.sum()) * v.mpp ** 2, 0)), v, pts


def fit(name, src='esri'):
    """The offset in metres between OpenStreetMap's footprint and the roof in the picture: slide the footprint over the picture and keep the place where its inside is most
    unlike its surround (a roof is flatter and lighter or darker than the street round it). Positive east and north."""
    from shapely.geometry import Polygon
    bi, b, ring = footprint(name)
    lngs, lats = [p[0] for p in ring], [p[1] for p in ring]
    pad = 25 / K.MX
    v = View((min(lngs) - pad, min(lats) - pad, max(lngs) + pad, max(lats) + pad), Z, src)
    pts = [v.px(*p) for p in ring]
    g = np.asarray(v.im.convert('L'), dtype=np.float32)
    best = (-1, 0, 0)
    for dy in range(-14, 15, 2):
        for dx in range(-14, 15, 2):
            poly = Polygon([(x + dx, y + dy) for x, y in pts])
            if poly.is_empty or not poly.is_valid:
                continue
            ins = Image.new('L', v.im.size, 0)
            ImageDraw.Draw(ins).polygon(list(poly.buffer(-1.5 / v.mpp).exterior.coords), fill=255)
            out = Image.new('L', v.im.size, 0)
            ImageDraw.Draw(out).polygon(list(poly.buffer(6 / v.mpp).exterior.coords), fill=255)
            ImageDraw.Draw(out).polygon(list(poly.buffer(1.5 / v.mpp).exterior.coords), fill=0)
            mi, mo = np.asarray(ins) > 0, np.asarray(out) > 0
            if mi.sum() < 100 or mo.sum() < 100:
                continue
            # a roof edge is a strong gradient along the footprint's outline: the mean gradient on the ring between the two
            score = abs(g[mi].mean() - g[mo].mean()) / (g[mi].std() + g[mo].std() + 1)
            if score > best[0]:
                best = (score, dx, dy)
    return dict(name=name, east_m=round(best[1] * v.mpp, 1), north_m=round(-best[2] * v.mpp, 1), confidence=round(best[0], 2))


def zones(name, src='esri', min_m2=60):
    """The coloured regions of a roof as polygons (longitude, latitude): terracotta or red tile and membrane, solar panels (dark blue), planting (green), a pool (light blue).
    Everything else (white, grey, black membrane) is the roof's own colour and is not a zone."""
    from shapely.geometry import Polygon, shape
    import rasterio.features
    from affine import Affine
    bi, b, ring = footprint(name)
    lngs, lats = [p[0] for p in ring], [p[1] for p in ring]
    pad = 25 / K.MX
    v = View((min(lngs) - pad, min(lats) - pad, max(lngs) + pad, max(lats) + pad), Z, src)
    pts = [v.px(*p) for p in ring]
    reach = Polygon(pts).buffer(5 / v.mpp)               # the roof leans away from its footprint in the picture, up to a few metres
    mask = Image.new('L', v.im.size, 0)
    ImageDraw.Draw(mask).polygon(list(reach.exterior.coords), fill=255)
    a = np.asarray(v.im, dtype=np.float32)
    r, g, bl = a[..., 0], a[..., 1], a[..., 2]
    lum = .299 * r + .587 * g + .114 * bl
    m = np.asarray(mask) > 0
    cls = np.zeros(lum.shape, np.uint8)
    cls[(r > 80) & (r - g > 24) & (r - bl > 32) & (r - g < 110)] = 1                      # tile
    cls[(bl > r + 14) & (lum < 125) & (bl > g + 4)] = 2                                    # solar
    cls[(g > r + 10) & (g > bl + 6) & (lum < 160)] = 3                                     # green
    cls[(bl > r + 35) & (lum > 135)] = 4                                                   # water
    cls[~m] = 0
    from scipy import ndimage
    out = []
    names = {1: 'tile', 2: 'solar', 3: 'green', 4: 'water'}
    for c, nm in names.items():
        mk = ndimage.binary_closing(ndimage.binary_opening(cls == c, iterations=2), iterations=3)
        for geom, val in rasterio.features.shapes(mk.astype(np.uint8), mask=mk, transform=Affine.identity()):
            pg = shape(geom).simplify(1.4)
            area = pg.area * v.mpp ** 2
            if area < min_m2 or pg.geom_type != 'Polygon':
                continue
            out.append(dict(cls=nm, m2=round(area), poly=[[round(x, 7) for x in v.ll(px, py)] for px, py in pg.exterior.coords]))
    out.sort(key=lambda z: -z['m2'])
    return out[:8]


def apply(name, src='esri'):
    """Write what the satellite shows into the landmark's sheet: the roof colour (lifted and softened to our palette) and the roof plant (boxes where the objects are)."""
    import colorsys
    path = os.path.join(K.LM, 'sheets', __import__('re').sub(r'[^a-z0-9]+', '-', name.lower()).strip('-') + '.json')
    if not os.path.exists(path):
        raise SystemExit('no sheet for %s yet' % name)
    rep, v, pts = roof(name, src)
    r, g, b = [c / 255 for c in rep['roof_rgb']]
    h, l, sat_ = colorsys.rgb_to_hls(r, g, b)
    l = .78 + .18 * l
    sat_ = min(.25, sat_ * .8)
    hexc = '%02X%02X%02X' % tuple(int(round(c * 255)) for c in colorsys.hls_to_rgb(h, l, sat_))
    sh = json.load(open(path, encoding='utf-8'))
    sh['roof'] = {'colour': hexc, 'from': 'satellite (%s, %.2f m a pixel)' % (src, rep['mpp']), 'plant': rep.get('objects', [])[:10], 'zones': zones(name, src)}
    json.dump(sh, open(path, 'w', encoding='utf-8'), indent=2)
    print('%-34s roof #%s, %d plant objects, zones: %s' % (name, hexc, len(sh['roof']['plant']), ', '.join('%s %d m2' % (z['cls'], z['m2']) for z in sh['roof']['zones']) or 'none'))


def sheet_image(name, out, src='esri'):
    rep, v, pts = roof(name, src)
    bi, b, ring = footprint(name)
    lngs, lats = [p[0] for p in ring], [p[1] for p in ring]
    pad = 18 / K.MX
    crop, (ox, oy) = v.crop((min(lngs) - pad, min(lats) - pad, max(lngs) + pad, max(lats) + pad))
    im = crop.copy()
    d = ImageDraw.Draw(im)
    d.line([(x - ox, y - oy) for x, y in pts + [pts[0]]], fill=(255, 154, 46), width=2)
    s = 560 / max(im.size)
    im = im.resize((int(im.width * s), int(im.height * s)), Image.LANCZOS)
    im.save(out, quality=90)
    return rep


def main():
    a = sys.argv[1:]
    if '--area' in a:
        bb = tuple(float(x) for x in a[a.index('--area') + 1].split(','))
        v = View(bb)
        c, _ = v.crop(bb)
        c.save(a[a.index('--area') + 2], quality=90)
        print('saved', c.size, 'at %.2f m a pixel' % v.mpp)
        return
    name = next((x for x in a if not x.startswith('--')), None)
    if not name:
        raise SystemExit(__doc__)
    if '--apply' in a:
        return apply(name)
    out = os.path.join(K.CACHE, 'sat_%s.jpg' % ''.join(ch if ch.isalnum() else '-' for ch in name.lower()))
    rep = sheet_image(name, out)
    print(json.dumps(rep, indent=1, default=float))
    print(json.dumps(fit(name), indent=1, default=float))
    print('picture:', out)


if __name__ == '__main__':
    main()
