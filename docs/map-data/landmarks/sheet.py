"""
Landmark sheets: a landmark described as data (landmarks/sheets/<slug>.json) instead of as code, and the builder that turns a sheet and a building's real
footprint into a model. A sheet says what makes that building itself: its own surfaces (tiles drawn by tiles_lib.py), its colours (a wall, a trim, one accent),
its storeys (a podium, a body, a band under the cornice), its signature shapes (a glass corner tower, a canopy, a roof sign), its brand (the name, in lights),
and its night (the colour of the wash up its walls, how many windows are lit).

Everything a sheet draws is real geometry or a tile; nothing is live and nothing moves. See sheets/README.md for the file format.
"""
import glob
import json
import math
import os
import re
import sys

from shapely.geometry import Point, Polygon

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import atlas
import facade
import tiles_lib
from meshlib import MAT, TILE_M, _ccw, rgb
from models_common import C

GLOW = {'violet': 0, 'teal': 1, 'amber': 2, 'blue': 3}
WASH = {'none': 0, 'violet': 1, 'teal': 2, 'amber': 3, 'blue': 4, 'rose': 5, 'green': 6, 'white': 7}
# what a sheet's colours may be: the map's palette (models_common.C) and each sheet's own wall and accent
BUDGET = dict(vertices=24000, triangles=14000, tiles=8)
# how many of a building's windows are lit at night, by what it is (a sheet's night.lit overrides it): a hotel glows late, an office is dark by 20:00, a terminal never sleeps
USE_LIT = {'hotel': .72, 'residential': .50, 'commercial-residential': .48, 'mall': .62, 'office': .16, 'terminal': .95, 'shrine': .25, 'hospital': .70, 'school': .12}


def _hex(s):
    return rgb(s.lstrip('#'))


class Sheets:
    def __init__(self, folder=None):
        self.folder = folder or os.path.join(HERE, 'sheets')
        self.items = []
        for f in sorted(glob.glob(os.path.join(self.folder, '*.json'))):
            try:
                sh = json.load(open(f, encoding='utf-8'))
            except Exception as e:
                print('  sheet %s: %s' % (os.path.basename(f), e))
                continue
            sh['slug'] = os.path.splitext(os.path.basename(f))[0]
            lit = sh.get('night', {}).get('lit', USE_LIT.get(sh.get('use')))
            if lit is not None:
                for t in sh.get('tiles', {}).values():
                    if 'p' in t and not t.get('p_fixed'):
                        t['p'] = round(float(lit) * float(t.get('p_scale', 1.0)), 3)
            ref = (sh.get('palette') or {}).get('wall', 'FFFFFF')
            sh['mats'] = {n: tiles_lib.register(sh['slug'], n, t, ref) for n, t in sh.get('tiles', {}).items()}
            self.items.append(sh)

    def find(self, name, idx=None):
        for sh in self.items:
            m = sh.get('match', {})
            if idx is not None and m.get('index') == idx:
                return sh
            if name and m.get('name') and re.fullmatch(m['name'], name):
                return sh
        return None


def _edges(ring, others):
    out = []
    n = len(ring)
    for i in range(n):
        a, b = ring[i], ring[(i + 1) % n]
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy)
        if ln < 3:
            out.append(None)
            continue
        ux, uy = dx / ln, dy / ln
        nx, ny = uy, -ux
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        free = min([Point(mid[0] + nx * d, mid[1] + ny * d).distance(o) for d in (2.5, 6, 11) for o in others] + [60.0])
        out.append(dict(a=a, b=b, ln=ln, u=(ux, uy), n=(nx, ny), mid=mid, free=free, th=math.atan2(dy, dx), score=ln * (1 + min(free, 30) / 15)))
    return out


def front_edge(ring, others):
    es = _edges(ring, others)
    best = max((e['score'], i) for i, e in enumerate(es) if e)
    return best[1], es


def build(m, ring, ctx, sh, h, name):
    """Build the landmark described by sheet sh on the footprint ring (local metres, any winding) of height h (the sheet's own height wins: measured off the photographs); returns what the model entry should carry."""
    h = float(sh.get('height', h))
    ring = _ccw(ring)
    pal = sh.get('palette', {})
    wall = _hex(pal.get('wall', 'F1E6D2'))
    trim = _hex(pal.get('trim', 'F4F1EA'))
    accent = _hex(pal.get('accent', '3F67B0'))
    podium_col = _hex(pal.get('podium', 'F4F1EA'))
    mats = sh['mats']
    body = sh.get('body', {})
    pod = float(body.get('podium', 6.0)) if h > 12 else min(4.2, h * .4)
    band_h = float(body.get('band', 3.4)) if body.get('band_mat') else 0.0
    top = h - band_h - .7
    def sel(k, default):
        n = body.get(k)
        return mats[n] if n in mats else (n if n in MAT else default)
    m.prism(ring, 0, pod, sel('podium_mat', 'shop'), podium_col, 'plain', podium_col, top=False, cell=4)
    m.grade = (pod, top, float(body.get('grade', 0.0))) if body.get('grade') else None
    m.prism(ring, pod, top, sel('floors_mat', 'windows'), wall, 'plain', wall, top=False, cell=4)
    m.grade = None
    if band_h:
        m.prism(ring, top, h - .7, sel('band_mat', 'plain'), accent if body.get('band_colour', 'accent') == 'accent' else wall, 'plain', wall, top=False, cell=4)
    poly = Polygon(ring).buffer(.35, join_style=2)                                       # the cornice
    roof = sh.get('roof') or {}
    roof_col = _hex(roof['colour']) if roof.get('colour') else C['white']               # read off the satellite view (tools/sat.py --apply), softened to our palette
    m.prism(list(poly.exterior.coords)[:-1], h - .7, h + .45, 'plain', trim, 'roofdeck', roof_col, top=True, cell=4)
    MXm, MYm = 111320 * math.cos(math.radians(14.525)), 110574
    inside = Polygon(ring).buffer(-1.5)
    hips = _roof_zones(m, ctx, ring, roof.get('zones', []), h)
    for o in roof.get('plant', [])[:10]:                                                # the plant on the roof, where the satellite sees it
        x, y = (o['lng'] - ctx['lng']) * MXm, (o['lat'] - ctx['lat']) * MYm
        if inside.is_empty or not inside.contains(Point(x, y)):
            continue
        side = max(1.2, min(6.0, math.sqrt(o['m2'])))
        m.box(x, y, h + .45, side, side * .8, 1.2 + min(2.2, side * .35), ctx['th'], 'louvre', C['grey'], 'plain', C['slate'], True, 4)
    fe, es = front_edge(ring, ctx.get('others', []))
    F = es[fe]
    for ft in sh.get('features', []):
        t = ft.get('type')
        if t == 'corner_tower':
            _corner_tower(m, es, fe, ft, h, accent, trim, mats, pod)
        elif t == 'canopy':
            _canopy(m, F, ft, accent if ft.get('colour', 'accent') == 'accent' else trim)
        elif t == 'roof_sign':
            _roof_sign(m, F, ft, h, name or ft.get('text', ''), accent)
        elif t == 'flag':
            _flag(m, F, ft, h, accent)
        elif t == 'vault':
            _vault(m, ctx, ft, h, mats)
        elif t == 'piers':
            _piers(m, es, ft, h, pod, trim)
    fa = sh.get('facade')
    if fa is not False:
        flags = dict(awnings=True, entrance=False, sign=False, balconies=False, ac=False, belts=False, pilasters=False)
        flags.update(fa or {})
        facade.apply(m, ring, ctx, 'mall', h, name, flags)
    night = sh.get('night', {})
    w = night.get('wash')
    return dict(sheet=sh['slug'], wash=({'c': WASH.get(w.get('color', 'blue'), 4), 'h': float(w.get('height', 20)), 's': float(w.get('strength', .5))} if w else None))


def _corner_tower(m, es, fe, ft, h, accent, trim, mats, pod):
    """A glass tower at one end of the front: it stands a little proud of the wall and a few metres above the roof."""
    F = es[fe]
    sx, sy = ft.get('size', [7.0, 6.0])
    end = ft.get('end', 'start')
    ux, uy = F['u']
    nx, ny = F['n']
    along = (sx / 2) if end == 'start' else (F['ln'] - sx / 2)
    ox, oy = F['a'][0] + ux * along, F['a'][1] + uy * along
    depth = float(ft.get('proud', 1.6))
    cx, cy = ox + nx * (depth - sy / 2), oy + ny * (depth - sy / 2)
    z1 = h + float(ft.get('extra', 4.0))
    mat = mats.get(ft.get('mat'), ft.get('mat') if ft.get('mat') in MAT else 'glass')
    m.grade = (pod, z1, .26) if ft.get('graded', True) else None
    m.box(cx, cy, 0, sx, sy, z1, F['th'], mat, accent, 'roofdeck', C['white'], True, 4)
    m.grade = None
    m.box(cx, cy, z1 - .1, sx + .7, sy + .7, .6, F['th'], 'plain', trim, 'roofdeck', trim, True, 4)         # its crown
    m.box(cx, cy, z1 + .5, sx * .5, sy * .5, 1.2, F['th'], 'louvre', C['grey'], 'plain', C['grey'], True, 4)


def _canopy(m, F, ft, col):
    w = float(ft.get('width', 9.0))
    ux, uy = F['u']
    nx, ny = F['n']
    t = F['ln'] * float(ft.get('at', .5))
    cx, cy = F['a'][0] + ux * t + nx * 2.4, F['a'][1] + uy * t + ny * 2.4
    z = float(ft.get('z', 4.4))
    m.slab(cx, cy, w, 5.0, F['th'], z, .4, col)
    for s in (-1, 1):
        m.column(cx + ux * s * (w / 2 - .5) + nx * 1.8, cy + uy * s * (w / 2 - .5) + ny * 1.8, 0, z, .22, C['white'])


def _roof_sign(m, F, ft, h, name, accent):
    """The name on the roof, over the front, in a frame of light (violet, teal, amber or blue neon): a board on two posts."""
    text = ft.get('text') or name
    sid = atlas.sign_id(text)
    if sid is None:
        return
    w = min(float(ft.get('width', 16.0)), F['ln'] * .8)
    hh = float(ft.get('height', 2.6))
    ux, uy = F['u']
    nx, ny = F['n']
    t = F['ln'] * float(ft.get('at', .5))
    cx, cy = F['a'][0] + ux * t - nx * 1.2, F['a'][1] + uy * t - ny * 1.2
    z0 = h + .45 + float(ft.get('lift', 1.4))
    p0 = (cx - ux * w / 2, cy - uy * w / 2, z0)
    m.grid(p0, (ux * w, uy * w, 0.0), (0.0, 0.0, hh), 1, 1, (nx, ny, 0.0), sid, (255, 255, 255), (0.0, 0.0), (1.0, 1.0))
    for s in (-1, 1):
        m.column(cx + ux * s * w * .38, cy + uy * s * w * .38, h + .4, z0, .12, C['slate'])
    g = 'glow%d' % GLOW.get(ft.get('neon', 'blue'), 3)
    for (a, b, c_, d_) in ((0, -.06, w + .3, .12), (0, hh - .06, w + .3, .12)):
        m.box(cx, cy + 0, z0 + b, w + .3, .12, .12, F['th'], g, C['white'], g, C['white'], True, 40.0)
    for s in (-1, 1):
        m.box(cx + ux * s * (w / 2 + .1), cy + uy * s * (w / 2 + .1), z0, .12, .12, hh, F['th'], g, C['white'], g, C['white'], True, 40.0)


ZONE_COL = dict(tile=C['rooftile'], solar=rgb('2E3A66'), green=rgb('62A072'), water=rgb('A9D4F0'), red=rgb('C9544A'))


def _roof_zones(m, ctx, ring, zones, h):
    """A pitched roof shows in the picture as a sunny slope (tile colour) and a shaded one (dark, or covered in solar panels): the two together are one hip. Tile and solar regions that touch
    are merged and a hip is built over each merged region's own outline; the zones left over are laid flat on the roof."""
    from shapely.geometry import Polygon as P
    from shapely.ops import unary_union
    MXm, MYm = 111320 * math.cos(math.radians(14.525)), 110574
    loc = lambda z: P([((lng - ctx['lng']) * MXm, (lat - ctx['lat']) * MYm) for lng, lat in z['poly']]).buffer(0)
    pitched = [loc(z) for z in zones if z['cls'] in ('tile', 'solar')]
    hips = []
    if any(z['cls'] == 'tile' for z in zones) and pitched:
        merged = unary_union([g.buffer(3) for g in pitched]).buffer(-3)
        for g in (merged.geoms if hasattr(merged, 'geoms') else [merged]):
            has_tile = any(z['cls'] == 'tile' and loc(z).intersects(g) for z in zones)
            if g.geom_type != 'Polygon' or g.area < 300 or not has_tile:
                continue
            rect = g.minimum_rotated_rectangle
            xs, ys = rect.exterior.coords.xy
            e0, e1 = math.hypot(xs[1] - xs[0], ys[1] - ys[0]), math.hypot(xs[2] - xs[1], ys[2] - ys[1])
            L, W = max(e0, e1), min(e0, e1)
            th = math.atan2(ys[1] - ys[0], xs[1] - xs[0]) if e0 >= e1 else math.atan2(ys[2] - ys[1], xs[2] - xs[1])
            c = rect.centroid
            m.hip(c.x, c.y, L, W, th, h + .45, min(9.0, W * .26), 'tile', ZONE_COL['tile'], over=.6, ridge=.4)
            hips.append(rect)
    for z in zones:
        if z['cls'] in ('tile', 'solar') and any(r.buffer(2).contains(loc(z).centroid) for r in hips):
            continue
        _zone(m, ctx, ring, z, h, hips)
    return hips


def _zone(m, ctx, ring, z, h, hips=None):
    from shapely.geometry import Polygon as P
    MXm, MYm = 111320 * math.cos(math.radians(14.525)), 110574
    pts = [((lng - ctx['lng']) * MXm, (lat - ctx['lat']) * MYm) for lng, lat in z['poly']]
    raw = P(pts).buffer(0)
    cls = z['cls']
    if cls == 'solar' and hips and any(r.buffer(2).contains(raw.centroid) for r in hips):
        return                                             # panels on a hip roof lie on its slope: not drawn flat under it
    poly = raw.intersection(P(ring).buffer(1.0 if cls in ('tile', 'red', 'solar') else -1.5))
    if poly.is_empty or poly.area < 25:
        return
    for g in (poly.geoms if hasattr(poly, 'geoms') else [poly]):
        if g.geom_type == 'Polygon' and g.area >= 25:
            m.cap(list(g.exterior.coords)[:-1], h + .52, MAT['roofdeck'], ZONE_COL.get(cls, C['grey']), True, 8.0)


def _piers(m, es, ft, h, pod, trim):
    """Vertical piers (or fins) standing proud of the wall at every bay, from the podium to the cornice: real geometry, so the light finds them."""
    bay = float(ft.get('bay', 4.0))
    depth, wid = float(ft.get('depth', .5)), float(ft.get('width', .55))
    z0 = float(ft.get('from', pod))
    z1 = h - float(ft.get('to_below', .7))
    col = _hex(ft['colour']) if ft.get('colour') else trim
    for e in es:
        if not e or e['ln'] < 9 or (ft.get('street_only', True) and e['free'] < 6):
            continue
        n = max(1, int(e['ln'] // bay))
        step = e['ln'] / n
        for k in range(n + 1):
            t = k * step
            cx, cy = e['a'][0] + e['u'][0] * t + e['n'][0] * depth / 2, e['a'][1] + e['u'][1] * t + e['n'][1] * depth / 2
            m.box(cx, cy, z0, wid, depth, z1 - z0, e['th'], 'plain', col, 'plain', col, True, 40.0)


def _vault(m, ctx, ft, h, mats):
    """A glass vault on the roof over the middle of the building (the mall's skylight), as long as a share of the footprint's long side."""
    L, W, th = ctx['L'], ctx['W'], ctx['th']
    mat = mats.get(ft.get('mat'), ft.get('mat') if ft.get('mat') in MAT else 'glass')
    col = _hex(ft['colour']) if ft.get('colour') else C['glass']
    m.barrel(ctx['cx'], ctx['cy'], L * float(ft.get('length', .55)), W * float(ft.get('width', .32)), th, h + .45, float(ft.get('rise', 4.5)), mat, col)


def _flag(m, F, ft, h, accent):
    ux, uy = F['u']
    nx, ny = F['n']
    t = F['ln'] * float(ft.get('at', .12))
    cx, cy = F['a'][0] + ux * t - nx * 1.0, F['a'][1] + uy * t - ny * 1.0
    m.cylinder(cx, cy, h + .4, h + 9.0, .08, 'plain', C['grey'], seg=6)
    m.box(cx + ux * .8, cy + uy * .8, h + 6.6, 1.6, .05, 1.0, F['th'], 'plain', accent, 'plain', accent, True, 40.0)


def lint(sh, nv, nt):
    """Warnings for a built sheet: its budget, its palette, its tiles."""
    out = []
    if nv > BUDGET['vertices']:
        out.append('%d vertices (budget %d)' % (nv, BUDGET['vertices']))
    if nt > BUDGET['triangles']:
        out.append('%d triangles (budget %d)' % (nt, BUDGET['triangles']))
    if len(sh.get('tiles', {})) > BUDGET['tiles']:
        out.append('%d own tiles (budget %d)' % (len(sh['tiles']), BUDGET['tiles']))
    pal = sh.get('palette', {})
    known = {'#%02X%02X%02X' % tuple(c) for c in C.values() if isinstance(c, tuple) and len(c) == 3}
    for k in ('trim', 'podium'):
        v = '#' + pal.get(k, '').lstrip('#').upper()
        if k in pal and v not in known and sh.get('palette_strict'):
            out.append('palette %s %s is not one of the map\'s colours (models_common.C)' % (k, v))
    for k, v in pal.items():
        if not re.fullmatch(r'#?[0-9A-Fa-f]{6}', v):
            out.append('palette %s is not a colour: %s' % (k, v))
    if 'accent' not in pal:
        out.append('no accent colour: a landmark needs its one accent')
    return out
