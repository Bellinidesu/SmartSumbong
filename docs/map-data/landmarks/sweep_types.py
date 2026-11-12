#!/usr/bin/env python3
"""
What every building of the barangay is, from the open data: OpenStreetMap's amenity, shop, tourism, office, leisure and building tags (nodes and ways) are matched to the building footprints
of the map (a point inside a footprint, a way's middle inside one, or the nearest footprint within 15 m), and each building gets a type: gas, worship, school, health, safety, civic, shop, mall,
hotel, parking, hangar, warehouse. Fuel stations drawn as an area with no building under them are kept as extra sites. Written to landmarks/poi-types.json (building index -> type) with a report
of what was found and what is left plain.

    python docs/map-data/landmarks/sweep_types.py
"""
import collections, json, math, os, sys

from shapely.geometry import Point, Polygon
from shapely.strtree import STRtree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..'))
import infra
from boundary import Boundary

MAP = os.path.normpath(os.path.join(HERE, '..', '..', '..', 'admin', 'assets', 'map'))
MX, MY = infra.MX, infra.MY

AMENITY = {'fuel': 'gas', 'place_of_worship': 'worship', 'school': 'school', 'college': 'school', 'kindergarten': 'school', 'university': 'school', 'hospital': 'health', 'clinic': 'health',
           'doctors': 'health', 'dentist': 'health', 'pharmacy': 'health', 'fire_station': 'safety', 'police': 'safety', 'townhall': 'civic', 'community_centre': 'civic', 'courthouse': 'civic',
           'social_facility': 'civic', 'library': 'civic', 'marketplace': 'shop', 'bank': 'shop', 'fast_food': 'shop', 'restaurant': 'shop', 'cafe': 'shop', 'parking': 'parking', 'bus_station': 'civic'}
SHOP = {'supermarket': 'mall', 'mall': 'mall', 'department_store': 'mall', 'convenience': 'shop'}
BUILDING = {'church': 'worship', 'chapel': 'worship', 'cathedral': 'worship', 'mosque': 'worship', 'school': 'school', 'kindergarten': 'school', 'college': 'school', 'university': 'school',
            'hospital': 'health', 'hotel': 'hotel', 'retail': 'mall', 'supermarket': 'mall', 'commercial': 'office', 'office': 'office', 'parking': 'parking', 'garage': 'parking', 'garages': 'parking',
            'warehouse': 'warehouse', 'industrial': 'warehouse', 'hangar': 'hangar', 'government': 'civic', 'public': 'civic', 'civic': 'civic', 'fire_station': 'safety', 'police': 'safety',
            'apartments': 'condo', 'residential': 'condo', 'dormitory': 'condo', 'terminal': 'terminal', 'transportation': 'terminal'}
RANK = ['gas', 'worship', 'school', 'health', 'safety', 'civic', 'hotel', 'mall', 'terminal', 'hangar', 'warehouse', 'parking', 'office', 'condo', 'shop']


def kind_of(t):
    k = []
    if t.get('amenity') in AMENITY:
        k.append(AMENITY[t['amenity']])
    if t.get('shop'):
        k.append(SHOP.get(t['shop'], 'shop'))
    if t.get('tourism') in ('hotel', 'motel', 'hostel', 'guest_house', 'apartment'):
        k.append('hotel')
    if t.get('office') == 'government':
        k.append('civic')
    if t.get('building') in BUILDING:
        k.append(BUILDING[t['building']])
    if t.get('aeroway') in ('hangar', 'terminal'):
        k.append('hangar' if t['aeroway'] == 'hangar' else 'terminal')
    return min(k, key=RANK.index) if k else None


def main():
    B = Boundary()
    bdoc = json.load(open(os.path.join(MAP, 'buildings.json'), encoding='utf-8'))
    bld, info = bdoc['b'], bdoc.get('info', {})
    polys = [Polygon([(q[0][i] * MX, q[0][i + 1] * MY) for i in range(0, len(q[0]), 2)]).buffer(0) for q in bld]
    tree = STRtree(polys)
    bb = '%s,%s,%s,%s' % infra.BBOX
    q = ('[out:json][timeout:150];(nwr["amenity"](%s);nwr["shop"](%s);nwr["tourism"~"hotel|motel|hostel|guest_house|apartment"](%s);nwr["office"="government"](%s);'
         'nwr["building"~"^(church|chapel|cathedral|mosque|school|kindergarten|college|university|hospital|hotel|retail|supermarket|warehouse|industrial|hangar|government|public|civic|fire_station|police|parking|garage|garages|terminal|transportation|dormitory)$"](%s););out center tags geom;') % ((bb,) * 5)
    els = infra.overpass('sweep', q)
    types = collections.defaultdict(list)
    extra = []
    seen = collections.Counter()
    for e in els:
        t = e.get('tags', {})
        k = kind_of(t)
        if not k:
            continue
        if e['type'] == 'node':
            lng, lat = e['lon'], e['lat']
        else:
            c = e.get('center') or {}
            g_ = e.get('geometry') or []
            bd = e.get('bounds')
            if c.get('lon') is not None:
                lng, lat = c['lon'], c['lat']
            elif g_:
                lng, lat = sum(p['lon'] for p in g_) / len(g_), sum(p['lat'] for p in g_) / len(g_)
            elif bd:
                lng, lat = (bd['minlon'] + bd['maxlon']) / 2, (bd['minlat'] + bd['maxlat']) / 2
            else:
                lng, lat = None, None
        if lng is None or not B.inside(lng, lat):
            continue
        pt = Point(lng * MX, lat * MY)
        hit = [i for i in tree.query(pt) if polys[i].contains(pt)]
        if not hit:
            near = sorted(((polys[i].distance(pt), i) for i in tree.query(pt.buffer(15))), key=lambda z: z[0])
            if near and near[0][0] < 15 and e['type'] == 'node':
                hit = [near[0][1]]
        seen[k] += 1
        if hit:
            i = min(hit, key=lambda j: polys[j].area)
            types[i].append((k, t.get('name') or ''))
        elif k == 'gas' and e['type'] == 'way' and len(e.get('geometry', [])) > 3:
            extra.append(dict(type='gas', name=t.get('name') or 'Gas station', ring=[[g['lon'], g['lat']] for g in e['geometry']]))
        elif k == 'gas':
            extra.append(dict(type='gas', name=t.get('name') or 'Gas station', at=[lng, lat]))
    out = {}
    for i, ks in types.items():
        out[str(i)] = min((k for k, _ in ks), key=RANK.index)
    # buildings the map already knows by class (buildings.json info) but that OSM tags did not reach
    for k_, v in info.items():
        c = (v[1] or '').lower()
        if k_ not in out and c in BUILDING:
            out[k_] = BUILDING[c]
    json.dump(dict(types=out, extra=extra), open(os.path.join(HERE, 'poi-types.json'), 'w', encoding='utf-8'), indent=1)
    cnt = collections.Counter(out.values())
    print('typed buildings: %d of %d  %s' % (len(out), len(bld), dict(cnt)))
    print('open data objects by type:', dict(seen))
    print('fuel sites with no building under them:', len(extra))


if __name__ == '__main__':
    main()
