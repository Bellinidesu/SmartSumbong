"""
The Barangay 183 boundary, for the scripts in this folder: read from admin/brgy183.json (the OpenStreetMap relation the
Spatial Distribution page draws its outline from) and joined into rings. The City view shows nothing outside it, so
build_buildings.py, build_city_detail.py and bake_shadows.py cut their data to it.
"""
import json, math, os

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, '..', '..', 'admin', 'brgy183.json'))


def _stitch(ways):
    """Join way geometries end to end into closed rings of (lng, lat)."""
    ways = [[(p['lon'], p['lat']) for p in w] for w in ways if len(w) > 1]
    rings = []
    while ways:
        ring = ways.pop(0)
        grown = True
        while grown and ring[0] != ring[-1]:
            grown = False
            for i, w in enumerate(ways):
                if w[0] == ring[-1]:
                    ring += w[1:]
                elif w[-1] == ring[-1]:
                    ring += w[::-1][1:]
                elif w[-1] == ring[0]:
                    ring = w[:-1] + ring
                elif w[0] == ring[0]:
                    ring = w[::-1][:-1] + ring
                else:
                    continue
                ways.pop(i)
                grown = True
                break
        if len(ring) > 3:
            rings.append(ring if ring[0] == ring[-1] else ring + [ring[0]])
    return rings


def rings():
    data = json.load(open(SRC, encoding='utf-8'))
    rel = next(e for e in data['elements'] if e['type'] == 'relation')
    return _stitch([m['geometry'] for m in rel['members'] if m['type'] == 'way' and m.get('geometry')])


def _in_ring(pt, ring):
    c = False
    j = len(ring) - 1
    for i in range(len(ring)):
        a, b = ring[i], ring[j]
        if (a[1] > pt[1]) != (b[1] > pt[1]) and pt[0] < (b[0] - a[0]) * (pt[1] - a[1]) / (b[1] - a[1]) + a[0]:
            c = not c
        j = i
    return c


class Boundary:
    def __init__(self):
        self.rings = rings()
        xs = [p[0] for r in self.rings for p in r]
        ys = [p[1] for r in self.rings for p in r]
        self.bbox = (min(xs), min(ys), max(xs), max(ys))

    def inside(self, lng, lat, slack_m=0.0):
        """Inside the boundary (even-odd over its rings), or within slack_m metres of an edge vertex."""
        w, s, e, n = self.bbox
        pad = slack_m / 100000.0
        if lng < w - pad or lng > e + pad or lat < s - pad or lat > n + pad:
            return False
        if sum(_in_ring((lng, lat), r) for r in self.rings) % 2 == 1:
            return True
        if slack_m:
            lat0 = math.radians(lat)
            for r in self.rings:
                for x, y in r:
                    if math.hypot((x - lng) * 111320 * math.cos(lat0), (y - lat) * 110574) <= slack_m:
                        return True
        return False
