"""
Where the City view goes back to plain colours.

Ace's rule (9 Oct 2026): the 3D detail is for the barangay's own streets and its landmarks. The airfield side is not one: NAIA Terminal 3 is the landmark there, the
building itself, so the runways, taxiways, aprons, hangars and the planes on them go back to the flat map and the plain coloured buildings. Villamor Air Base the
same, but for the Air Force Aerospace Museum and its Retired Aircraft Garden; the Villamor Air Base Golf Course stays as the green of the area.

plain(lng, lat) is true for a point that belongs to those areas and is not in a place that stays detailed. Built from OpenStreetMap (the same caches the
airfield and the Villamor query fill), in degrees (1 m is about 9e-6 degrees here, near enough for a buffer).
"""
import json, math, os, sys

from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union
from shapely.prepared import prep

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, 'landmarks', 'osm-cache')
M = 9e-6

# what stays detailed inside the plain areas: OpenStreetMap way ids (the Air Force Museum Complex, its Aerospace Museum, the Retired Aircraft Garden,
# the Villamor golf course) and the one building that is NAIA Terminal 3
KEEP_WAYS = {132908042, 306082625, 306248808, 128616401}
KEEP_BUILDING_NAMES = ('NAIA Terminal 3',)
VILLAMOR_WAY = 43762468


def _poly(e):
    g = e.get('geometry') or []
    return Polygon([(p['lon'], p['lat']) for p in g]).buffer(0) if len(g) > 3 else None


def _line(e):
    g = e.get('geometry') or []
    return LineString([(p['lon'], p['lat']) for p in g]) if len(g) > 1 else None


class Plain:
    def __init__(self, buildings=None, info=None):
        air = json.load(open(os.path.join(CACHE, 'aeroway.json'), encoding='utf-8'))
        vil = json.load(open(os.path.join(CACHE, 'villamor.json'), encoding='utf-8'))
        parts = []
        for e in air:
            k = e['tags'].get('aeroway')
            if k == 'runway' and _line(e):
                parts.append(_line(e).buffer(90 * M))
            elif k in ('taxiway', 'parking_position') and _line(e):
                parts.append(_line(e).buffer(45 * M))
            elif k in ('apron', 'hangar') and _poly(e):
                parts.append(_poly(e).buffer(20 * M))
            elif k in ('helipad', 'gate', 'navigationaid', 'holding_position') and e.get('lon') is not None:
                parts.append(Point(e['lon'], e['lat']).buffer(30 * M))
            elif k == 'jet_bridge' and _line(e):
                parts.append(_line(e).buffer(20 * M))
        for e in vil:
            if e['id'] == VILLAMOR_WAY:
                parts.append(_poly(e))
        keep = [_poly(e) for e in vil if e['id'] in KEEP_WAYS and _poly(e)]
        self.area = unary_union([p for p in parts if p is not None and not p.is_empty])
        self.keep = unary_union([k.buffer(12 * M) for k in keep]) if keep else Polygon()
        # NAIA Terminal 3's own footprint (and 40 m round it: the canopy, the forecourt) stays
        if buildings is not None:
            for bi, nm in (info or {}).items():
                if nm and nm[0] in KEEP_BUILDING_NAMES:
                    b = buildings[int(bi)]
                    ring = [(b[0][i], b[0][i + 1]) for i in range(0, len(b[0]), 2)]
                    self.keep = unary_union([self.keep, Polygon(ring).buffer(40 * M)])
        self.plain_area = self.area.difference(self.keep)
        self._p = prep(self.plain_area)

    def plain(self, lng, lat):
        return self._p.contains(Point(lng, lat))


_cache = {}


def load():
    if 'p' not in _cache:
        d = json.load(open(os.path.join(HERE, '..', '..', 'admin', 'assets', 'map', 'buildings.json'), encoding='utf-8'))
        _cache['p'] = Plain(d['b'], d.get('info'))
    return _cache['p']


def apply_to_city_detail():
    """Take the trees and street lamps out of the plain areas (the museum garden and the golf course keep theirs)."""
    p = load()
    path = os.path.join(HERE, '..', '..', 'admin', 'assets', 'map', 'city-detail.json')
    d = json.load(open(path, encoding='utf-8'))
    t0, l0 = len(d['trees']), len(d['lamps'])
    d['trees'] = [t for t in d['trees'] if not p.plain(t[0], t[1])]
    d['lamps'] = [t for t in d['lamps'] if not p.plain(t[0], t[1])]
    json.dump(d, open(path, 'w', encoding='utf-8'), separators=(',', ':'))
    print('plain areas: trees %d -> %d, lamps %d -> %d' % (t0, len(d['trees']), l0, len(d['lamps'])))


if __name__ == '__main__':
    if '--apply' in sys.argv:
        apply_to_city_detail()
        sys.exit(0)
    p = load()
    print('plain area: %.1f ha, kept inside it: %.1f ha' % (p.area.area / M / M / 1e4, p.keep.intersection(p.area).area / M / M / 1e4))
    d = json.load(open(os.path.join(HERE, '..', '..', 'admin', 'assets', 'map', 'buildings.json'), encoding='utf-8'))
    n = sum(1 for b in d['b'] if p.plain(b[4], b[5]))
    print('buildings that go plain:', n, 'of', len(d['b']))
