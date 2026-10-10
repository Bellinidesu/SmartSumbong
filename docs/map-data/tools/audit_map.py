#!/usr/bin/env python3
"""
The map audit: looks for errors, glitches and models that are missing, from the built files (no browser needed).

  * every model: no NaN or infinite corner, a sane size, a triangle count, a height next to the open-data height of the building it replaces, its position inside the boundary (the map shows
    nothing outside it), degenerate triangles, two models on one building, two models standing on each other;
  * every typed building (poi-types.json) and every named building: modelled, or plain on purpose (the airfield side and Villamor, plain.py), or MISSING;
  * the files the page loads: they exist, the model data and its index agree, the light file matches or is absent.

    python docs/map-data/tools/audit_map.py
"""
import gzip, json, math, os, sys, collections

import numpy as np
from shapely.geometry import Point, Polygon
from shapely.strtree import STRtree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..'))
import common as K
from boundary import Boundary
import plain as _plain


def main():
    B = Boundary()
    PL = _plain.load()
    meta = json.load(open(os.path.join(K.MAPDIR, 'landmarks3d.json'), encoding='utf-8'))
    raw = gzip.decompress(open(os.path.join(K.MAPDIR, 'landmarks3d.bin.gz'), 'rb').read())
    rec = np.frombuffer(raw[:meta['indexOffsetBytes']], dtype=[('p', '<f4', 3), ('uv', '<f4', 2), ('m', 'u1'), ('c', 'u1', 3)])
    idx = np.frombuffer(raw[meta['indexOffsetBytes']:], dtype='<u4')
    bld, info = K.buildings()
    problems, notes = [], []
    if len(rec) != meta['vertices']:
        problems.append('vertex count: file %d, index %d' % (len(rec), meta['vertices']))
    lp = os.path.join(K.MAPDIR, 'landmarks3d-light.bin.gz')
    if os.path.exists(lp):
        n = len(gzip.decompress(open(lp, 'rb').read())) // 8
        if n != meta['vertices']:
            notes.append('the baked light file is for %d vertices, the models have %d: the page uses its flat light (this is expected when you skip the bake)' % (n, meta['vertices']))
    for f in ('landmarks3d-atlas.png', 'landmarks3d-emis.png', 'landmarks3d-atlas2.png', 'landmarks3d-emis2.png', 'buildings.json', 'city-detail.json'):
        if not os.path.exists(os.path.join(K.MAPDIR, f)):
            problems.append('missing file ' + f)
    foots = {}
    taken = collections.defaultdict(list)
    tot_tris = 0
    for md in meta['models']:
        if md.get('furniture'):
            continue
        v = rec['p'][md['voff']:md['voff'] + md['v']]
        ii = idx[md['ioff']:md['ioff'] + md['i']]
        nm = md['name']
        tot_tris += md['i'] // 3
        if not np.isfinite(v).all():
            problems.append('%s: NaN or infinite corner' % nm)
            continue
        if ii.size and (ii.max() >= md['v']):
            problems.append('%s: an index points past its vertices' % nm)
        ext = v.max(0) - v.min(0)
        if ext[0] > 600 or ext[1] > 1200 or ext[2] > 120:
            problems.append('%s: odd size %.0f x %.0f x %.0f m' % (nm, *ext))
        if ext[2] < .5:
            problems.append('%s: flat (%.2f m high)' % (nm, ext[2]))
        tri = v[ii.reshape(-1, 3)]
        area = np.linalg.norm(np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]), axis=1) / 2
        degen = int((area < 1e-6).sum())
        if degen > .02 * len(area):
            problems.append('%s: %d degenerate triangles of %d' % (nm, degen, len(area)))
        if not B.inside(md['lng'], md['lat'], 60):
            problems.append('%s: stands outside the boundary' % nm)
        r = md['replaces']
        if r >= 0:
            if r >= len(bld):
                problems.append('%s: replaces building %d which does not exist' % (nm, r))
            else:
                taken[r].append(nm)
                oh = float(bld[r][1])
                if ext[2] > oh * 2.2 + 8 and not md.get('sheet'):
                    notes.append('%s: %.0f m tall, the open data says %.0f m' % (nm, ext[2], oh))
        if md['i'] // 3 > 40000:
            notes.append('%s: %d triangles (heavy)' % (nm, md['i'] // 3))
        c = Point((md['lng']) * K.MX, md['lat'] * K.MY)
        foots[nm] = Point(c).buffer(max(3.0, math.hypot(ext[0], ext[1]) / 3))
    for r, names in taken.items():
        if len(names) > 1:
            problems.append('building %d is replaced by %d models: %s' % (r, len(names), ', '.join(names)))
    names = list(foots)
    tree = STRtree([foots[n] for n in names])
    for i, n in enumerate(names):
        for j in tree.query(foots[n]):
            if j > i and foots[n].intersection(foots[names[j]]).area > .5 * min(foots[n].area, foots[names[j]].area):
                notes.append('%s and %s overlap' % (n, names[j]))
    # what is typed or named but not modelled
    poi = json.load(open(os.path.join(K.LM, 'poi-types.json'), encoding='utf-8')) if os.path.exists(os.path.join(K.LM, 'poi-types.json')) else {'types': {}}
    modelled = set(taken)
    miss, plain_ok, hero = collections.Counter(), 0, 0
    missing = []
    for k, t in poi['types'].items():
        b = bld[int(k)]
        if int(k) in modelled:
            continue
        if PL.plain(b[4], b[5]):
            plain_ok += 1
        else:
            miss[t] += 1
            missing.append((t, (info.get(k) or ['', ''])[0] or ('building %s' % k), round(b[4], 5), round(b[5], 5)))
    named = [(int(k), v[0]) for k, v in info.items() if v[0] and int(k) not in modelled and not PL.plain(bld[int(k)][4], bld[int(k)][5])]
    print('MODELS: %d, %d triangles in all' % (len([m for m in meta['models'] if not m.get('furniture')]), tot_tris))
    print('typed buildings kept plain on purpose (airfield side, Villamor): %d' % plain_ok)
    print('typed buildings with NO model: %d %s' % (sum(miss.values()), dict(miss)))
    for t, nm, lng, lat in missing[:25]:
        print('   missing: [%s] %s (%s, %s)' % (t, nm, lng, lat))
    print('named buildings with no model: %d' % len(named))
    for i, n in named[:20]:
        print('   named, plain: %s' % n)
    print('PROBLEMS: %d' % len(problems))
    for p in problems:
        print('  !', p)
    print('NOTES: %d' % len(notes))
    for n in notes[:25]:
        print('  -', n)


if __name__ == '__main__':
    main()
