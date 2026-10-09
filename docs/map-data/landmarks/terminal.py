"""
The shapes of a terminal (sheet features), drawn in a frame along the building: u along it, v across it (sheet "frame": {origin: [lng, lat], th: degrees}). Sections of different height,
a row of barrel vaults over the hall with a glazed valley between, rows of skylights on a flat roof, pitched concourse roofs, a canopy over the kerb, the jet bridges of the gates.
Everything is geometry; nothing moves.
"""
import math

from shapely.geometry import Point, Polygon

from meshlib import MAT, rgb

MXm, MYm = 111320 * math.cos(math.radians(14.525)), 110574


def hexc(s):
    return rgb(s.lstrip('#'))


def mat_of(mats, name, default='plain'):
    return mats[name] if name in mats else (name if name in MAT else default)


def uv(ctx, sh, u, v):
    fr = sh['frame']
    th = math.radians(fr['th'])
    c, s = math.cos(th), math.sin(th)
    ox, oy = (fr['origin'][0] - ctx['lng']) * MXm, (fr['origin'][1] - ctx['lat']) * MYm
    return ox + u * c - v * s, oy + u * s + v * c


def frame_th(sh):
    return math.radians(sh['frame']['th'])


def slab_poly(ctx, sh, u0, u1, v0, v1):
    return Polygon([uv(ctx, sh, u0, v0), uv(ctx, sh, u1, v0), uv(ctx, sh, u1, v1), uv(ctx, sh, u0, v1)])


def sections(m, ring, ctx, sh, wall, podium_col, roof_col):
    """The body in lengths, each with its own height and surfaces: the footprint is cut by slabs across the building."""
    mats = sh['mats']
    for sc in sh['sections']:
        piece = Polygon(ring).intersection(slab_poly(ctx, sh, sc['u0'], sc['u1'], -400, 400))
        h = float(sc['h'])
        pod = float(sc.get('podium', 0))
        for g in (piece.geoms if hasattr(piece, 'geoms') else [piece]):
            if g.geom_type != 'Polygon' or g.area < 20:
                continue
            r = list(g.exterior.coords)[:-1]
            if pod:
                m.prism(r, 0, pod, mat_of(mats, sc.get('podium_mat', 'plain')), podium_col, 'plain', podium_col, top=False, cell=5)
            m.grade = (pod, h, float(sc.get('grade', 0))) if sc.get('grade') else None
            m.prism(r, pod, h, mat_of(mats, sc.get('mat', 'plain')), wall, 'roofdeck', roof_col, top=True, cell=6)
            m.grade = None


def vaults(m, ctx, sh, ft):
    """A row of barrel vaults side by side (axis across the building), a glazed valley between neighbours, and the vault ends closed with glass."""
    mats = sh['mats']
    u0, u1, v0, v1 = ft['u0'], ft['u1'], ft['v0'], ft['v1']
    n = int(ft.get('n', 5))
    z = float(ft['z'])
    rise = float(ft.get('rise', 6.0))
    col = hexc(ft.get('colour', 'F2F1EC'))
    valley = hexc(ft.get('valley', '3F8F8E'))
    endc = hexc(ft.get('end_colour', '9FB7C4'))
    th = frame_th(sh) + math.pi / 2
    w = (u1 - u0) / n
    for k in range(n):
        ua, ub = u0 + k * w, u0 + (k + 1) * w
        um = (ua + ub) / 2
        cx, cy = uv(ctx, sh, um, (v0 + v1) / 2)
        m.barrel(cx, cy, v1 - v0, w - .8, th, z, rise, mat_of(mats, ft.get('mat', 'sheet')), col, seg=14)
        for sgn, vv in ((-1, v0), (1, v1)):
            segs = 14
            c0 = uv(ctx, sh, um, vv)
            nrm = (math.cos(th) * sgn, math.sin(th) * sgn, 0.0)
            base = m._v((c0[0], c0[1], z), nrm, (0, 0), MAT['plain'], endc)
            ids = []
            for i in range(segs + 1):
                a = math.pi * i / segs
                x, y = uv(ctx, sh, um - (w - .8) / 2 * math.cos(a), vv)
                ids.append(m._v((x, y, z + rise * math.sin(a)), nrm, (0, 0), MAT['plain'], endc))
            for i in range(segs):
                if sgn > 0:
                    m.tri(base, ids[i], ids[i + 1])
                else:
                    m.tri(base, ids[i + 1], ids[i])
        if k:
            vx, vy = uv(ctx, sh, ua, (v0 + v1) / 2)
            m.box(vx, vy, z + .02, v1 - v0 - 1.0, 1.2, .35, th, 'glass', valley, 'glass', valley, True, 40.0)


def skylights(m, ctx, sh, ft):
    """Rows of narrow raised skylights on a flat roof, every `step` metres along the building."""
    u0, u1, v0, v1 = ft['u0'], ft['u1'], ft['v0'], ft['v1']
    step = float(ft.get('step', 7.0))
    z = float(ft['z'])
    col = hexc(ft.get('colour', '7FA3A6'))
    th = frame_th(sh) + math.pi / 2
    u = u0
    while u < u1:
        cx, cy = uv(ctx, sh, u, (v0 + v1) / 2)
        m.box(cx, cy, z, v1 - v0, 1.6, .55, th, 'glass', col, 'plain', hexc('F2F1EC'), True, 40.0)
        u += step


def pitched(m, ctx, sh, ft):
    """A pitched roof over a long rectangle (a concourse), ridge along the building."""
    u0, u1, v0, v1 = ft['u0'], ft['u1'], ft['v0'], ft['v1']
    cx, cy = uv(ctx, sh, (u0 + u1) / 2, (v0 + v1) / 2)
    m.gable(cx, cy, u1 - u0, v1 - v0, frame_th(sh), float(ft['z']), float(ft.get('rise', 2.5)), mat_of(sh['mats'], ft.get('mat', 'sheet')), hexc(ft.get('colour', 'ECEBE6')), over=.6, gable_mat='plain', gable_col=hexc(ft.get('gable', '9FB0BB')))


def kerb_canopy(m, ctx, sh, ft):
    """A canopy over the kerb: a thin slab on columns along the landside."""
    u0, u1, v0, v1 = ft['u0'], ft['u1'], ft['v0'], ft['v1']
    z = float(ft.get('z', 8.0))
    th = frame_th(sh)
    cx, cy = uv(ctx, sh, (u0 + u1) / 2, (v0 + v1) / 2)
    m.slab(cx, cy, u1 - u0, v1 - v0, th, z, .5, hexc(ft.get('colour', 'F2F1EC')))
    n = int((u1 - u0) // float(ft.get('spacing', 18)))
    for k in range(n + 1):
        x, y = uv(ctx, sh, u0 + (u1 - u0) * k / max(n, 1), v1 - .8)
        m.column(x, y, 0, z, .35, hexc(ft.get('column', 'D8D6D0')))


def jet_bridges(m, ctx, sh, ft):
    """The jet bridges of the gates (OpenStreetMap aeroway=jet_bridge) along the terminal: a covered tube from the building to the aircraft door."""
    import infra
    near = slab_poly(ctx, sh, ft['u0'], ft['u1'], ft['v0'], ft['v1'])
    q = '[out:json][timeout:120];(nwr["aeroway"](%s,%s,%s,%s););out geom;' % infra.BBOX
    n = 0
    for e in infra.overpass('aeroway', q):
        if e['tags'].get('aeroway') != 'jet_bridge' or len(e.get('geometry', [])) < 2:
            continue
        pts = [((g['lon'] - ctx['lng']) * MXm, (g['lat'] - ctx['lat']) * MYm) for g in e['geometry']]
        if not near.buffer(30).contains(Point(*pts[0])):
            continue
        for i in range(len(pts) - 1):
            (x0, y0), (x1, y1) = pts[i], pts[i + 1]
            ln = math.hypot(x1 - x0, y1 - y0)
            if ln >= 1:
                m.box((x0 + x1) / 2, (y0 + y1) / 2, 3.2, ln, 3.0, 2.8, math.atan2(y1 - y0, x1 - x0), 'ribbon', hexc('ECEEF0'), 'roofdeck', hexc('C9CED6'), True, 8.0)
        m.cylinder(pts[-1][0], pts[-1][1], 0, 3.2, .35, 'plain', hexc('8C93A3'), seg=8)
        n += 1
    print('    jet bridges at the terminal: %d' % n)
