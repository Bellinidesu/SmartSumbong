"""admin/assets/map/places.json: what is IN each building, from Overture Maps' places (shops, restaurants, services, hotels, banks...): for every building a short string of group letters,
one per kind of place found in it or within 15 m of its wall (the places' own points are rarely exactly in the footprint). The City view draws a sign board and an awning on the building in each group's colour.
Groups: f food, c cafe, s shop, h health, e education, l lodging, b bank, w worship, g government, v services (beauty, repair, professional), a auto.
The places come from Overture's release on S3 (CDR, ODbL/CDLA by source; the Overture places theme is CDLA-Permissive 2.0), read by DuckDB for the map area only and cached in tools/mly-cache/places.json.
    python docs/map-data/tools/build_places.py"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
MAP = os.path.join(HERE, '..', '..', '..', 'admin', 'assets', 'map')
CACHE = os.path.join(HERE, 'mly-cache', 'places.json')
BBOX = (121.0007, 14.5126, 121.0304, 14.5412)
REL = '2026-09-23.1'
LAT0 = 14.5269
MX, MY = 111320 * 0.9679, 110574


def fetch():
    import duckdb
    con = duckdb.connect()
    con.execute("INSTALL httpfs; LOAD httpfs; INSTALL spatial; LOAD spatial; SET s3_region='us-west-2';")
    u = "s3://overturemaps-us-west-2/release/%s/theme=places/type=place/*" % REL
    W, S, E, N = BBOX
    rows = con.execute("SELECT names.primary, basic_category, taxonomy.primary, ST_X(geometry), ST_Y(geometry), confidence, operating_status FROM read_parquet('%s', hive_partitioning=1) "
                       "WHERE bbox.xmin>%s AND bbox.xmax<%s AND bbox.ymin>%s AND bbox.ymax<%s" % (u, W, E, S, N)).fetchall()
    rows = [[r[0], r[1], r[2], round(r[3], 6), round(r[4], 6), round(r[5] or 0, 2)] for r in rows if r[6] in (None, 'open')]
    json.dump(rows, open(CACHE, 'w'))
    return rows


def group(cat, tax):
    s = ((cat or '') + ' ' + (tax or '')).lower()
    for g, keys in (('c', ('coffee', 'cafe', 'tea_room', 'bakery', 'dessert', 'ice_cream')), ('f', ('restaurant', 'eatery', 'fast_food', 'bar', 'food_stand', 'food_court', 'pub', 'diner')),
                    ('l', ('hotel', 'lodging', 'hostel', 'resort', 'motel')), ('h', ('medical', 'dentist', 'pharmacy', 'hospital', 'clinic', 'doctor', 'health', 'wellness', 'veterinar')),
                    ('e', ('school', 'education', 'college', 'university', 'kindergarten', 'tutor')), ('b', ('bank', 'credit_union', 'atm', 'financial', 'insurance')),
                    ('w', ('worship', 'church', 'chapel', 'temple', 'mosque')), ('g', ('government', 'police', 'fire_station', 'embassy', 'public_service')),
                    ('a', ('auto_', 'car_', 'gas_station', 'automotive', 'motorcycle', 'parking')), ('s', ('store', 'shop', 'retail', 'market', 'mall', 'supermarket', 'convenience', 'fashion', 'boutique')),
                    ('v', ('service', 'salon', 'beauty', 'barber', 'repair', 'laundry', 'real_estate', 'professional', 'event', 'studio', 'agency'))):
        if any(k in s for k in keys):
            return g
    return None


def main():
    from shapely.geometry import Polygon, Point
    from shapely.strtree import STRtree
    rows = json.load(open(CACHE)) if os.path.exists(CACHE) else fetch()
    d = json.load(open(os.path.join(MAP, 'buildings.json'), encoding='utf-8'))
    polys = [Polygon([(b[0][k] * MX, b[0][k + 1] * MY) for k in range(0, len(b[0]), 2)]).buffer(0) for b in d['b']]
    tree = STRtree(polys)
    found = {}
    for name, cat, tax, lng, lat, conf in rows:
        g = group(cat, tax)
        if not g or conf < .3:
            continue
        p = Point(lng * MX, lat * MY)
        hits = [j for j in tree.query(p.buffer(15)) if polys[j].distance(p) <= 15]
        if not hits:
            continue
        j = min(hits, key=lambda j: polys[j].distance(p))
        s = found.setdefault(j, [])
        if g not in s and len(s) < 3:
            s.append(g)
    out = {str(j): ''.join(s) for j, s in found.items()}
    json.dump({'about': 'Groups of places in each building (build_places.py, Overture Maps places). f food c cafe s shop h health e education l lodging b bank w worship g government v services a auto', 'p': out},
              open(os.path.join(MAP, 'places.json'), 'w'), separators=(',', ':'))
    import collections
    print('%d places read, %d buildings with at least one' % (len(rows), len(out)), dict(collections.Counter(c for v in out.values() for c in v)))


if __name__ == '__main__':
    main()
