"""
A small mesh library for the landmark models: walls, roofs, domes, canopies and the like, built in a landmark's own frame
(metres: x east, y north, z up). Every surface is cut into cells of about 3 m so that, once the lighting is baked into the vertices
by the graphics card, the light varies across a wall and a roof rather than being one tone for the whole face.

A vertex carries: position, a normal (for the bake only), a texture coordinate in tile units, a material (which tile of the facade
atlas), and a plain albedo colour. The atlas holds the detail that repeats (windows, roof sheet, grilles); the albedo colour is what
makes one building cream and another terracotta.
"""
import math

import numpy as np
from shapely.geometry import Polygon, box as sbox
from shapely import constrained_delaunay_triangles

# materials: tiles of the atlas (see atlas.py), with how many metres one tile covers (width, height)
MAT = {
    'plain': 0, 'windows': 1, 'ribbon': 2, 'glass': 3, 'sheet': 4, 'tile': 5, 'arches': 6, 'louvre': 7, 'sign': 8, 'panel': 9, 'column': 10, 'shop': 11, 'slots': 12, 'strip': 13, 'brick': 14, 'roofdeck': 15,
}
TILE_M = {  # metres a tile covers across and up
    0: (4.0, 4.0), 1: (6.4, 3.4), 2: (6.0, 3.4), 3: (3.2, 3.4), 4: (2.4, 2.4), 5: (2.4, 2.4), 6: (7.0, 7.0), 7: (3.0, 3.0), 8: (4.0, 1.2), 9: (4.0, 3.4), 10: (4.0, 4.0), 11: (6.0, 4.2), 12: (6.0, 3.4), 13: (6.0, 3.4), 14: (4.0, 3.4), 15: (6.0, 6.0),
}


class _TileM(dict):
    """Tiles from 16 up are one sign each, drawn 12 m by 1.6 m."""
    def __missing__(self, k):
        return (12.0, 1.6)


TILE_M = _TileM(TILE_M)
CELL = 3.0


class Mesh:
    def __init__(self):
        self.p, self.n, self.uv, self.mat, self.col, self.idx = [], [], [], [], [], []

    def _v(self, p, n, uv, mat, col):
        self.p.append(p)
        self.n.append(n)
        self.uv.append(uv)
        self.mat.append(mat)
        self.col.append(col)
        return len(self.p) - 1

    def tri(self, a, b, c):
        self.idx += [a, b, c]

    def grid(self, o, du, dv, nu, nv, n, mat, col, uv0=(0., 0.), uvs=(1., 1.), flip=False):
        """A flat parallelogram o + s*du + t*dv, cut into nu x nv cells. uv0, uvs: texture coordinate at the corner and over the whole."""
        rows = []
        for j in range(nv + 1):
            row = []
            for i in range(nu + 1):
                s, t = i / nu, j / nv
                p = (o[0] + du[0] * s + dv[0] * t, o[1] + du[1] * s + dv[1] * t, o[2] + du[2] * s + dv[2] * t)
                row.append(self._v(p, n, (uv0[0] + uvs[0] * s, uv0[1] + uvs[1] * t), mat, col))
            rows.append(row)
        for j in range(nv):
            for i in range(nu):
                a, b, c, d = rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i]
                if flip:
                    self.tri(a, c, b)
                    self.tri(a, d, c)
                else:
                    self.tri(a, b, c)
                    self.tri(a, c, d)

    def quad(self, p0, p1, p2, p3, mat, col, n=None, uv=None, cell=CELL):
        """A planar quad p0 p1 p2 p3 (counter-clockwise seen from outside), cut into cells."""
        du = (p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2])
        dv = (p3[0] - p0[0], p3[1] - p0[1], p3[2] - p0[2])
        lu, lv = math.sqrt(sum(x * x for x in du)), math.sqrt(sum(x * x for x in dv))
        if n is None:
            n = _norm(_cross(du, dv))
        tw, th = TILE_M[mat]
        nu, nv = max(1, math.ceil(lu / cell)), max(1, math.ceil(lv / cell))
        u0 = uv[0] if uv else 0.0
        v0 = uv[1] if uv else 0.0
        self.grid(p0, du, dv, nu, nv, n, mat, col, (u0, v0), (lu / tw, lv / th))

    def wall(self, p0, p1, z0, z1, mat, col, u_start=0.0, cell=CELL):
        """A vertical wall along p0 -> p1 (the outside on the right of the direction of travel)."""
        dx, dy = p1[0] - p0[0], p1[1] - p0[1]
        ln = math.hypot(dx, dy)
        if ln < 1e-6:
            return u_start
        n = (dy / ln, -dx / ln, 0.0)
        tw, th = TILE_M[mat]
        nu, nv = max(1, math.ceil(ln / cell)), max(1, math.ceil((z1 - z0) / cell))
        self.grid((p0[0], p0[1], z0), (dx, dy, 0), (0, 0, z1 - z0), nu, nv, n, mat, col, (u_start / tw, z0 / th), (ln / tw, (z1 - z0) / th))
        return u_start + ln

    def cap(self, ring, z, mat, col, up=True, cell=6.0):
        """A flat polygon at height z (a roof or a floor), cut by a grid so that it takes light in many places."""
        poly = Polygon(ring)
        if not poly.is_valid:
            poly = poly.buffer(0)
        if poly.is_empty:
            return
        tw, th = TILE_M[mat]
        minx, miny, maxx, maxy = poly.bounds
        pieces = []
        nx_, ny_ = max(1, math.ceil((maxx - minx) / cell)), max(1, math.ceil((maxy - miny) / cell))
        if nx_ * ny_ > 1:
            for i in range(nx_):
                for j in range(ny_):
                    c = poly.intersection(sbox(minx + i * cell, miny + j * cell, minx + (i + 1) * cell, miny + (j + 1) * cell))
                    pieces += [g for g in (c.geoms if hasattr(c, 'geoms') else [c]) if g.geom_type == 'Polygon' and g.area > .05]
        else:
            pieces = [poly]
        nrm = (0., 0., 1.) if up else (0., 0., -1.)
        for pc in pieces:
            tris = constrained_delaunay_triangles(pc)
            for t in tris.geoms:
                pts = list(t.exterior.coords)[:3]
                if abs(Polygon(pts).area) < 1e-4:
                    continue
                cc = (pts[1][0] - pts[0][0]) * (pts[2][1] - pts[0][1]) - (pts[1][1] - pts[0][1]) * (pts[2][0] - pts[0][0])
                if (cc > 0) != up:
                    pts = [pts[0], pts[2], pts[1]]
                ids = [self._v((p[0], p[1], z), nrm, (p[0] / tw, p[1] / th), mat, col) for p in pts]
                self.tri(*ids)

    def _tri2d(self, poly, cell):
        """Triangles (as 2D point triples) of a polygon cut into cells of about `cell`, so that light can vary across it."""
        if not poly.is_valid:
            poly = poly.buffer(0)
        minx, miny, maxx, maxy = poly.bounds
        nx_, ny_ = max(1, math.ceil((maxx - minx) / cell)), max(1, math.ceil((maxy - miny) / cell))
        pieces = []
        if nx_ * ny_ > 1:
            for i in range(nx_):
                for j in range(ny_):
                    c = poly.intersection(sbox(minx + i * cell, miny + j * cell, minx + (i + 1) * cell, miny + (j + 1) * cell))
                    pieces += [g for g in (c.geoms if hasattr(c, 'geoms') else [c]) if g.geom_type == 'Polygon' and g.area > .02]
        else:
            pieces = [poly]
        out = []
        for pc in pieces:
            for t in constrained_delaunay_triangles(pc).geoms:
                pts = list(t.exterior.coords)[:3]
                if abs(Polygon(pts).area) > 1e-5:
                    out.append(pts)
        return out

    def vprism(self, poly_uz, o, u, n, d0, d1, mat, col, cell=2.5):
        """A shape drawn in a vertical plane (u along the facade, z up), pushed out along the horizontal normal n from depth d0 to d1:
        its edges become walls and its front face (at d1) a cap. o is the plane's origin (x, y, z), u and n are horizontal unit vectors."""
        P = lambda a, z, d: (o[0] + u[0] * a + n[0] * d, o[1] + u[1] * a + n[1] * d, o[2] + z + 0.0)
        pts = list(poly_uz)
        if sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts))) < 0:
            pts = pts[::-1]
        tw, th = TILE_M[MAT[mat]]
        for i in range(len(pts)):
            a, b = pts[i], pts[(i + 1) % len(pts)]
            du, dz = b[0] - a[0], b[1] - a[1]
            ln = math.hypot(du, dz)
            if ln < 1e-4:
                continue
            nrm = _norm((u[0] * dz, u[1] * dz, -du))     # outward, in the plane
            seg = max(1, math.ceil(ln / 3.0))
            self.grid(P(a[0], a[1], d0), (P(b[0], b[1], d0)[0] - P(a[0], a[1], d0)[0], P(b[0], b[1], d0)[1] - P(a[0], a[1], d0)[1], b[1] - a[1]),
                      (n[0] * (d1 - d0), n[1] * (d1 - d0), 0.0), seg, 1, nrm, MAT[mat], col, (0, 0), (ln / tw, (d1 - d0) / th))
        for t in self._tri2d(Polygon(pts), cell):
            ids = [self._v(P(x, z, d1), (n[0], n[1], 0.0), (x / tw, z / th), MAT[mat], col) for x, z in t]
            self.tri(*ids)

    def arch_poly(self, half_w, leg_h, seg=14):
        """The outline (u, z) of an arched opening or a stepped arch: straight legs up to leg_h, then a semicircle."""
        pts = [(-half_w, 0.0)]
        for k in range(seg + 1):
            a = math.pi - math.pi * k / seg
            pts.append((half_w * math.cos(a), leg_h + half_w * math.sin(a)))
        pts.append((half_w, 0.0))
        return pts

    def prism(self, ring, z0, z1, wall_mat, wall_col, top_mat='sheet', top_col=None, top=True, cell=CELL):
        """A footprint extruded from z0 to z1: walls (outside normals) and, if asked for, a flat top."""
        ring = _ccw(ring)
        u = 0.0
        for i in range(len(ring)):
            u = self.wall(ring[i], ring[(i + 1) % len(ring)], z0, z1, MAT[wall_mat], wall_col, u, cell)
        if top:
            # a big flat roof is a roof deck (membrane panels, wear, vents), not a plain sheet
            if top_mat in ('sheet', 'plain') and z1 > 7 and Polygon(ring).area > 150:
                top_mat, top_col = 'roofdeck', (238, 238, 240)
            self.cap(ring, z1, MAT[top_mat], top_col or wall_col, True)

    def box(self, cx, cy, z0, L, W, H, th, wall_mat, wall_col, top_mat='sheet', top_col=None, top=True, cell=CELL):
        self.prism(_obb(cx, cy, L, W, th), z0, z0 + H, wall_mat, wall_col, top_mat, top_col, top, cell)

    def sloped(self, p0, p1, p2, p3, mat, col, cell=CELL):
        self.quad(p0, p1, p2, p3, MAT[mat], col, None, None, cell)

    def gable(self, cx, cy, L, W, th, z, rise, mat, col, over=.5, gable_mat='plain', gable_col=None):
        """A pitched roof with its ridge along the long side. Slopes are two quads; the gable ends are triangles."""
        c, s = math.cos(th), math.sin(th)
        R = lambda u, v, zz: (cx + u * c - v * s, cy + u * s + v * c, zz)
        hl, hw = L / 2 + over, W / 2 + over
        self.sloped(R(-hl, -hw, z), R(hl, -hw, z), R(hl, 0, z + rise * (hw / (W / 2)) * .0 + rise), R(-hl, 0, z + rise), mat, col)
        self.sloped(R(hl, hw, z), R(-hl, hw, z), R(-hl, 0, z + rise), R(hl, 0, z + rise), mat, col)
        gc = gable_col or col
        for sgn in (-1, 1):
            a, b, apex = R(sgn * L / 2, -W / 2, z), R(sgn * L / 2, W / 2, z), R(sgn * L / 2, 0, z + rise * (W / 2 / hw))
            n = (sgn * c, sgn * s, 0.)
            ia, ib, ic = self._v(a, n, (0, 0), MAT[gable_mat], gc), self._v(b, n, (W / TILE_M[MAT[gable_mat]][0], 0), MAT[gable_mat], gc), self._v(apex, n, (W / 2 / TILE_M[MAT[gable_mat]][0], rise / TILE_M[MAT[gable_mat]][1]), MAT[gable_mat], gc)
            if sgn > 0:
                self.tri(ia, ib, ic)
            else:
                self.tri(ia, ic, ib)

    def hip(self, cx, cy, L, W, th, z, rise, mat, col, over=.5, ridge=.45):
        c, s = math.cos(th), math.sin(th)
        R = lambda u, v, zz: (cx + u * c - v * s, cy + u * s + v * c, zz)
        hl, hw = L / 2 + over, W / 2 + over
        rl = max(0.0, L / 2 - W / 2) * (1 if ridge else 0)
        r0, r1 = R(-rl, 0, z + rise), R(rl, 0, z + rise)
        A, B, Cc, D = R(-hl, -hw, z), R(hl, -hw, z), R(hl, hw, z), R(-hl, hw, z)
        self.sloped(A, B, (r1[0], r1[1], r1[2]), (r0[0], r0[1], r0[2]), mat, col)
        self.sloped(Cc, D, r0, r1, mat, col)
        for (p, q, r) in ((B, Cc, r1), (D, A, r0)):
            n = _norm(_cross((q[0] - p[0], q[1] - p[1], q[2] - p[2]), (r[0] - p[0], r[1] - p[1], r[2] - p[2])))
            ids = [self._v(v, n, (0, 0), MAT[mat], col) for v in (p, q, r)]
            self.tri(*ids)

    def cylinder(self, cx, cy, z0, z1, r, mat, col, seg=16, cap_mat=None, cap_col=None):
        ring = [(cx + r * math.cos(2 * math.pi * i / seg), cy + r * math.sin(2 * math.pi * i / seg)) for i in range(seg)]
        self.prism(ring, z0, z1, mat, col, cap_mat or mat, cap_col, top=cap_mat is not None, cell=CELL)

    def dome(self, cx, cy, z, r, h, mat, col, seg=20, rings=7, ry=None):
        """A dome: a spherical cap of radius r at its base and height h."""
        ry = ry or r
        pts = []
        for j in range(rings + 1):
            a = (math.pi / 2) * j / rings
            for i in range(seg):
                t = 2 * math.pi * i / seg
                x, y, zz = r * math.cos(a) * math.cos(t), ry * math.cos(a) * math.sin(t), h * math.sin(a)
                n = _norm((x / (r * r), y / (ry * ry), (zz / (h * h)) if h else 1))
                pts.append(self._v((cx + x, cy + y, z + zz), n, (i / seg * 2, j / rings), MAT[mat], col))
        for j in range(rings):
            for i in range(seg):
                a, b = j * seg + i, j * seg + (i + 1) % seg
                c, d = (j + 1) * seg + (i + 1) % seg, (j + 1) * seg + i
                self.tri(pts[a], pts[b], pts[c])
                self.tri(pts[a], pts[c], pts[d])

    def barrel(self, cx, cy, L, W, th, z, rise, mat, col, seg=12):
        """A barrel vault over a rectangle: a half cylinder along the long side."""
        c, s = math.cos(th), math.sin(th)
        R = lambda u, v, zz: (cx + u * c - v * s, cy + u * s + v * c, zz)
        prev = None
        for k in range(seg + 1):
            a = math.pi * k / seg
            v, zz = -W / 2 * math.cos(a), rise * math.sin(a)
            cur = (R(-L / 2, v, z + zz), R(L / 2, v, z + zz))
            if prev:
                self.quad(prev[0], prev[1], cur[1], cur[0], MAT[mat], col, None, None, CELL)
            prev = cur

    def slab(self, cx, cy, L, W, th, z, thick, col, mat='plain'):
        self.box(cx, cy, z, L, W, thick, th, mat, col, mat, col, True)
        # the underside
        self.cap(_obb(cx, cy, L, W, th), z, MAT[mat], col, up=False)

    def column(self, cx, cy, z0, z1, r, col, mat='plain'):
        self.cylinder(cx, cy, z0, z1, r, mat, col, seg=8)

    # ---- finish: arrays for the baker and the map ----
    def arrays(self):
        P = np.array(self.p, dtype=np.float32).reshape(-1, 3)
        N = np.array(self.n, dtype=np.float32).reshape(-1, 3)
        U = np.array(self.uv, dtype=np.float32).reshape(-1, 2)
        M = np.array(self.mat, dtype=np.uint8)
        C = np.array(self.col, dtype=np.uint8).reshape(-1, 3)
        I = np.array(self.idx, dtype=np.uint32)
        return P, N, U, M, C, I


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _norm(v):
    ln = math.sqrt(sum(x * x for x in v)) or 1.0
    return (v[0] / ln, v[1] / ln, v[2] / ln)


def _ccw(ring):
    a = sum(ring[i][0] * ring[(i + 1) % len(ring)][1] - ring[(i + 1) % len(ring)][0] * ring[i][1] for i in range(len(ring)))
    return list(ring) if a > 0 else list(reversed(ring))


def _obb(cx, cy, L, W, th):
    c, s = math.cos(th), math.sin(th)
    return [(cx + u * c - v * s, cy + u * s + v * c) for u, v in ((-L / 2, -W / 2), (L / 2, -W / 2), (L / 2, W / 2), (-L / 2, W / 2))]


def rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
