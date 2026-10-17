"""
Reads real facades from Mapillary 360 panoramas (CC BY-SA street-level imagery), by geometry rather than by guesswork: a panorama is an
equirectangular picture, so every point of the world has exactly one pixel in it, given where the camera stood and which way it faced. For a wall of
a building (two corners on the ground, a height) this unwraps the pixels of that wall into a flat, upright picture: the face as it stands.
That picture is only ever studied for colours and for the pattern of windows and floors (see stylise.py); it is never shipped.
"""
import json, math, os, sys, urllib.parse, urllib.request

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
MX, MY = 111320 * math.cos(math.radians(14.525)), 110574
CACHE = os.path.join(HERE, 'mly-cache')
UA = {'User-Agent': 'SmartSumbong/1.0 (acelediac@gmail.com)'}


def token():
    for l in open(os.path.join(ROOT, '.env'), encoding='utf-8'):
        if l.startswith('MAPILLARY_TOKEN='):
            return l.split('=', 1)[1].strip().strip('"\'')
    raise SystemExit('MAPILLARY_TOKEN is not in .env')


def pano_url(image_id):
    u = 'https://graph.mapillary.com/%s?access_token=%s&fields=thumb_2048_url,compass_angle,computed_geometry,computed_compass_angle,computed_altitude,altitude,sequence' % (image_id, token())
    return json.load(urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=40))


def fetch(image_id):
    os.makedirs(CACHE, exist_ok=True)
    f = os.path.join(CACHE, image_id + '.jpg')
    meta_f = os.path.join(CACHE, image_id + '.json')
    if os.path.exists(f) and os.path.exists(meta_f):
        return Image.open(f).convert('RGB'), json.load(open(meta_f))
    d = pano_url(image_id)
    open(f, 'wb').write(urllib.request.urlopen(urllib.request.Request(d['thumb_2048_url'], headers=UA), timeout=60).read())
    json.dump(d, open(meta_f, 'w'))
    return Image.open(f).convert('RGB'), d


def rectify(pano, meta, a, b, height, origin, ppm=6.0, cam_h=2.4, max_px=360):
    """Unwrap the wall from corner a to corner b (metres east, north from origin), from the ground to `height`, out of a panorama.
    Returns an RGB array [rows, cols] (top row the roof), and the camera's distance and viewing angle for the face."""
    lng, lat = meta['computed_geometry']['coordinates']
    cx, cy = (lng - origin[0]) * MX, (lat - origin[1]) * MY
    comp = math.radians(meta.get('computed_compass_angle') or meta.get('compass_angle') or 0)
    W, H = pano.size
    ln = math.hypot(b[0] - a[0], b[1] - a[1])
    cols = int(min(max_px, max(16, ln * ppm)))
    rows = int(min(max_px, max(16, height * ppm)))
    us = (np.arange(cols) + .5) / cols
    zs = height * (1 - (np.arange(rows) + .5) / rows)
    px = a[0] + (b[0] - a[0]) * us
    py = a[1] + (b[1] - a[1]) * us
    dx = px[None, :] - cx
    dy = py[None, :] - cy
    dz = (zs[:, None] - cam_h)
    az = np.arctan2(dx, dy)
    el = np.arctan2(dz, np.hypot(dx, dy))
    xx = (.5 + ((az - comp + math.pi) % (2 * math.pi) - math.pi) / (2 * math.pi)) * W
    yy = (.5 - el / math.pi) * H
    arr = np.asarray(pano, dtype=np.float32)
    x0 = np.clip(np.floor(xx).astype(int), 0, W - 1)
    y0 = np.clip(np.floor(yy).astype(int), 0, H - 1)
    x1 = (x0 + 1) % W
    y1 = np.clip(y0 + 1, 0, H - 1)
    fx = (xx - np.floor(xx))[..., None]
    fy = (yy - np.floor(yy))[..., None]
    out = (arr[y0, x0] * (1 - fx) * (1 - fy) + arr[y0, x1] * fx * (1 - fy) + arr[y1, x0] * (1 - fx) * fy + arr[y1, x1] * fx * fy)
    mid = (.5 * (a[0] + b[0]), .5 * (a[1] + b[1]))
    dist = math.hypot(mid[0] - cx, mid[1] - cy)
    # the angle between the camera's line of sight and the wall's normal (0 = square on)
    ux, uy = (b[0] - a[0]) / ln, (b[1] - a[1]) / ln
    nx, ny = uy, -ux
    vx, vy = (cx - mid[0]) / max(dist, .01), (cy - mid[1]) / max(dist, .01)
    ang = math.degrees(math.acos(max(-1, min(1, nx * vx + ny * vy))))
    return out.astype(np.uint8), dist, ang


def nearest_panos(images, pt_lnglat, origin, rmin=10, rmax=75, limit=40):
    out = []
    x0, y0 = (pt_lnglat[0] - origin[0]) * MX, (pt_lnglat[1] - origin[1]) * MY
    for i in images:
        if not i.get('is_pano') or not i.get('computed_geometry'):
            continue
        lg, lt = i['computed_geometry']['coordinates']
        d = math.hypot((lg - origin[0]) * MX - x0, (lt - origin[1]) * MY - y0)
        if rmin <= d <= rmax:
            out.append((d, i))
    out.sort(key=lambda t: t[0])
    return out[:limit]
