#!/usr/bin/env python3
"""
Structure from motion on the public street-level images round a building (Mapillary, CC BY-SA: the perspective frames, and the 360 panoramas cut into upright views), with pycolmap on the
CPU: finds where every camera stood and a sparse cloud of points on the building. Used to read a building's true size and the positions of its parts, in metres, from many views at once.
Never run on Google imagery (its terms forbid it).

    python docs/map-data/tools/sfm.py "Shrine of St. Thérèse of the Child Jesus" --radius 90
Output: tools/sfm-out/<slug>/ (images, database, sparse model, points.ply, report.txt)
"""
import json, math, os, re, sys, concurrent.futures as cf

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as K
import mly_rectify as R

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'sfm-out')


def pano_views(im, yaw_deg, fov=70, size=900):
    """An upright perspective view out of an equirectangular panorama, looking along yaw (compass degrees from the pano's own heading)."""
    W, H = im.size
    a = np.asarray(im)
    f = (size / 2) / math.tan(math.radians(fov) / 2)
    xs = (np.arange(size) - size / 2 + .5) / f
    ys = (np.arange(size) - size / 2 + .5) / f
    X, Y = np.meshgrid(xs, ys)
    d = np.stack([X, -Y, np.ones_like(X)], -1)
    d /= np.linalg.norm(d, axis=-1, keepdims=True)
    t = math.radians(yaw_deg)
    c, s = math.cos(t), math.sin(t)
    dx = d[..., 0] * c + d[..., 2] * s
    dz = -d[..., 0] * s + d[..., 2] * c
    lon = np.arctan2(dx, dz)
    lat = np.arcsin(np.clip(d[..., 1], -1, 1))
    u = ((lon / (2 * math.pi) + .5) * W).astype(int) % W
    v = np.clip(((.5 - lat / math.pi) * H).astype(int), 0, H - 1)
    return Image.fromarray(a[v, u])


def main():
    a = sys.argv[1:]
    name = next(x for x in a if not x.startswith('--'))
    radius = float(a[a.index('--radius') + 1]) if '--radius' in a else 90
    bi, b = K.building_named(name)
    o = (b[4], b[5])
    slug = re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')
    work = os.path.join(OUT, slug + ('-panos' if '--panos' in a else ''))
    imgdir = os.path.join(work, 'images')
    os.makedirs(imgdir, exist_ok=True)
    sel = []
    for i in K.mly_index():
        g = i.get('computed_geometry')
        if not g:
            continue
        x, y = (g['coordinates'][0] - o[0]) * K.MX, (g['coordinates'][1] - o[1]) * K.MY
        if math.hypot(x, y) < radius and i.get('camera_type') in ('perspective',) and '--panos' not in a and i.get('thumb_1024_url'):
            sel.append(i)
    if '--panos' in a:
        sel = []
        for i in K.mly_index():
            g = i.get('computed_geometry')
            if g and i.get('is_pano') and i.get('thumb_1024_url') and math.hypot((g['coordinates'][0] - o[0]) * K.MX, (g['coordinates'][1] - o[1]) * K.MY) < radius:
                sel.append(i)
    print('frames:', len(sel))

    def get(i):
        p = os.path.join(imgdir, 'p_%s.jpg' % i['id'])
        if i.get('is_pano'):
            if not os.path.exists(p.replace('.jpg', '_0.jpg')):
                try:
                    full = Image.open(__import__('io').BytesIO(K.get(R.pano_url(i['id'])['thumb_2048_url']))).convert('RGB')
                except Exception:
                    return None
                for k, yaw in enumerate((0, 60, 120, 180, 240, 300)):
                    pano_views(full, yaw).save(p.replace('.jpg', '_%d.jpg' % k), quality=92)
            return p
        if not os.path.exists(p):
            try:
                open(p, 'wb').write(K.get(i['thumb_1024_url']))
            except Exception:
                return None
        return p
    with cf.ThreadPoolExecutor(8) as ex:
        files = [f for f in ex.map(get, sel) if f]
    print('downloaded', len(files))
    import pycolmap
    db = os.path.join(work, 'db.db')
    if os.path.exists(db):
        os.remove(db)
    sparse = os.path.join(work, 'sparse')
    os.makedirs(sparse, exist_ok=True)
    pycolmap.extract_features(db, imgdir, camera_mode=pycolmap.CameraMode.PER_IMAGE)
    pycolmap.match_exhaustive(db)
    recs = pycolmap.incremental_mapping(db, imgdir, sparse)
    rep = []
    for k, r in recs.items():
        rep.append('model %s: %d images registered, %d points' % (k, r.num_reg_images(), r.num_points3D()))
        r.export_PLY(os.path.join(work, 'points_%s.ply' % k))
    open(os.path.join(work, 'report.txt'), 'w').write('\n'.join(rep) or 'no model')
    print('\n'.join(rep) or 'no model')


if __name__ == '__main__':
    main()
