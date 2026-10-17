"""Building heights from the Global Building Atlas LoD1 (TU Munich, CC BY 4.0; a Parquet copy on Source Cooperative), for the buildings no tag gives a height for.
Only the map area is read (an HTTP range read of one 5-degree tile, about ten seconds), cached in tools/mly-cache/gba_heights.json.
How far to trust it, measured here against the 40 tower blocks whose height IS tagged (OpenStreetMap): on houses and low blocks it agrees with what we had (mean 5.8 m against our guess of 6.5 m),
but on towers it reads about 45 % low (16 to 21 m where the tag says 32 to 38 m), because its model is trained mostly on low-rise cities. So below 16 m it is used as it is, and at 16 m and over it is scaled
by 1.8 (the ratio on those towers), to 50 m at most: an estimate still, and flagged as one."""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, 'tools', 'mly-cache', 'gba_heights.json')
URL = 'https://data.source.coop/tge-labs/globalbuildingatlas-lod1/e120_n15_e125_n10.parquet'   # lon 120-125, lat 10-15: Manila
TOWER_FROM, TOWER_SCALE, TOWER_MAX = 16.0, 1.8, 50.0


def load(bbox):
    if os.path.exists(CACHE):
        return json.load(open(CACHE))
    import duckdb
    W, S, E, N = bbox
    con = duckdb.connect()
    con.execute('INSTALL httpfs; LOAD httpfs; INSTALL spatial; LOAD spatial;')
    rows = con.execute("SELECT height, ST_AsText(ST_Centroid(geometry)) FROM read_parquet('%s') WHERE bbox.xmin<%s AND bbox.xmax>%s AND bbox.ymin<%s AND bbox.ymax>%s" % (URL, E, W, N, S)).fetchall()
    out = []
    for h, c in rows:
        if h is None:
            continue
        x, y = c.replace('POINT (', '').replace(')', '').split()
        out.append([round(float(x), 6), round(float(y), 6), round(h, 1)])
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    json.dump(out, open(CACHE, 'w'))
    return out


class Index:
    def __init__(self, pts, cell=0.0005):
        self.cell, self.g = cell, {}
        for x, y, h, *_ in pts:
            if h is None:
                continue
            self.g.setdefault((int(x / cell), int(y / cell)), []).append((x, y, h))

    def inside(self, ring):
        """Heights of the atlas buildings whose centre lies in the footprint (ring: [(lng, lat), ...])."""
        xs, ys = [p[0] for p in ring], [p[1] for p in ring]
        out = []
        for gx in range(int(min(xs) / self.cell), int(max(xs) / self.cell) + 1):
            for gy in range(int(min(ys) / self.cell), int(max(ys) / self.cell) + 1):
                for x, y, h in self.g.get((gx, gy), ()):
                    if min(xs) <= x <= max(xs) and min(ys) <= y <= max(ys) and _in(x, y, ring):
                        out.append(h)
        return out


def _in(x, y, ring):
    c = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi:
            c = not c
        j = i
    return c


def height(idx, ring):
    """The atlas's height for a footprint, corrected for towers (see the top), or None where it has nothing."""
    hs = sorted(idx.inside(ring))
    if not hs:
        return None
    h = hs[len(hs) // 2]
    if h >= TOWER_FROM:
        h = min(TOWER_MAX, h * TOWER_SCALE)
    return round(max(h, 2.8), 1)
