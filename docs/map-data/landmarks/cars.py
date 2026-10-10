"""Cars on the streets: low-poly, in a few body colours, standing along the kerb of residential streets and driving in the lanes of the main roads. Every road comes from
OpenStreetMap (highway=*, one Overpass query, cached by infra.overpass); where a car stands, which colour, which way it faces is a hash of the road and the distance along it, so nothing
changes between builds. A car is never put inside a building, outside the barangay, or on a bridge. Nothing moves."""
import math, zlib
from shapely.geometry import Point

import infra
from meshlib import rgb

BODY = [rgb('D9DDE6'), rgb('F4F1EA'), rgb('3A4C86'), rgb('C9544A'), rgb('8C93A3'), rgb('2B2F3B'), rgb('4C79C4'), rgb('F2C14E'), rgb('7C849A')]
GLASS = rgb('9DB4CE')
Q = '[out:json][timeout:120];way["highway"~"^(residential|tertiary|secondary|primary|unclassified|service|trunk|living_street)$"][!"bridge"][!"tunnel"](%s,%s,%s,%s);out geom tags;' % (14.5126, 121.0007, 14.5412, 121.0304)
MAXCARS = 1800


def _h(*a):
    return (zlib.crc32(repr(a).encode()) & 0xffffff) / 0xffffff


def car(m, x, y, th, col):
    c, s = math.cos(th), math.sin(th)
    m.box(x, y, .22, 4.3, 1.8, .78, th, 'plain', col, 'plain', col, True, 40.0)                        # the body
    m.box(x - c * .25, y - s * .25, 1.0, 2.2, 1.6, .62, th, 'plain', GLASS, 'plain', col, True, 40.0)  # the cabin, a little back of the middle


JEEP = [rgb('E4572E'), rgb('F2C14E'), rgb('3A4C86'), rgb('2FA6AB'), rgb('C9544A'), rgb('4C9A6A')]


def jeepney(m, x, y, th, col):
    """A jeepney: a long coloured body, a pale roof, a darker stripe along it."""
    c, s = math.cos(th), math.sin(th)
    m.box(x, y, .35, 7.0, 2.0, 1.15, th, 'plain', col, 'plain', col, True, 40.0)
    m.box(x - c * .3, y - s * .3, 1.5, 6.0, 1.85, .7, th, 'plain', GLASS, 'plain', rgb('EDEDED'), True, 40.0)
    m.box(x, y, .35, 7.05, 2.05, .22, th, 'plain', rgb('2B2F3B'), 'plain', rgb('2B2F3B'), True, 40.0)


def motorcycle(m, x, y, th, col):
    m.box(x, y, .3, 1.9, .55, .55, th, 'plain', col, 'plain', col, True, 40.0)
    m.box(x - math.cos(th) * .1, y - math.sin(th) * .1, .85, .7, .45, .35, th, 'plain', rgb('2B2F3B'), 'plain', rgb('2B2F3B'), True, 40.0)


def tricycle(m, x, y, th, col):
    """A tricycle: a motorcycle with a covered sidecar."""
    c, s = math.cos(th), math.sin(th)
    motorcycle(m, x, y, th, rgb('2B2F3B'))
    m.box(x - s * .95, y + c * .95, .35, 1.7, 1.1, .75, th, 'plain', col, 'plain', col, True, 40.0)
    m.box(x - s * .95, y + c * .95, 1.1, 1.5, 1.2, .55, th, 'plain', GLASS, 'plain', rgb('F4F1EA'), True, 40.0)


def vehicle(m, x, y, th, key, parked):
    r = _h(*key, 'v')
    col = BODY[int(_h(*key, 'c') * len(BODY))]
    if parked:
        if r < .40:
            motorcycle(m, x, y, th, col)
        elif r < .52:
            tricycle(m, x, y, th, JEEP[int(_h(*key, 'j') * len(JEEP))])
        else:
            car(m, x, y, th, col)
    else:
        if r < .24:
            jeepney(m, x, y, th, JEEP[int(_h(*key, 'j') * len(JEEP))])
        elif r < .36:
            motorcycle(m, x, y, th, col)
        else:
            car(m, x, y, th, col)


def build(m, origin, boundary, blocked):
    """blocked(lng, lat) -> True where a building stands. Returns the number of cars."""
    ways = infra.overpass('roads', Q)
    n = 0
    for w in ways:
        g = w.get('geometry') or []
        t = w.get('tags', {})
        hw = t.get('highway')
        if len(g) < 2:
            continue
        parked = hw in ('residential', 'service', 'unclassified', 'living_street')
        step, prob = (13.0, .32) if parked else (30.0, .5)
        off = 2.4 if parked else 1.7
        d = 0.0
        for a, b in zip(g, g[1:]):
            ax, ay = (a['lon'] - origin[0]) * infra.MX, (a['lat'] - origin[1]) * infra.MY
            bx, by = (b['lon'] - origin[0]) * infra.MX, (b['lat'] - origin[1]) * infra.MY
            ln = math.hypot(bx - ax, by - ay)
            if ln < 1:
                continue
            ux, uy = (bx - ax) / ln, (by - ay) / ln
            pos = (step - d % step) % step
            while pos < ln:
                key = (w['id'], int((d + pos) // step))
                if _h(*key) < prob and n < MAXCARS:
                    side = 1 if _h(*key, 's') < .5 else -1
                    x, y = ax + ux * pos - uy * off * side, ay + uy * pos + ux * off * side
                    lng, lat = origin[0] + x / infra.MX, origin[1] + y / infra.MY
                    if boundary is None or boundary.inside(lng, lat):
                        if not blocked(lng, lat):
                            th = math.atan2(uy, ux) + (math.pi if side < 0 and not parked else 0)
                            vehicle(m, x, y, th, key, parked)
                            n += 1
                pos += step
            d += ln
    return n
