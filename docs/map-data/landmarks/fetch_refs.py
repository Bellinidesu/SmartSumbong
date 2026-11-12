#!/usr/bin/env python3
"""
Collects reference photos of the landmarks, to study when modelling them. Nothing here is shipped or copied into a model:
the photos stay in refs/ (ignored by git), I read them for proportions, roofs and colours, and the models are drawn by
models.py in the barangay's own style.

Sources, both free to use as reference:
  * Wikimedia Commons: files with a free licence (CC or public domain); the licence and author of each are kept in refs/index.json;
  * Mapillary: street-level photos near each landmark (CC BY-SA), through the token in .env (MAPILLARY_TOKEN, never printed).

Run:  python docs/map-data/landmarks/fetch_refs.py
"""
import json, math, os, re, sys, time, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
REFS = os.path.join(HERE, 'refs')
UA = {'User-Agent': 'SmartSumbong-reference/1.0 (barangay portal; contact acelediac@gmail.com)'}
LM = os.path.join(ROOT, 'admin', 'assets', 'map', 'landmarks.geojson')

# what to ask Commons for, by landmark (others are only searched by their own name)
COMMONS = {
    'NAIA Terminal 3': ['Ninoy Aquino International Airport Terminal 3 exterior', 'NAIA Terminal 3 facade'],
    'NAIA Centennial Terminal 2': ['NAIA Terminal 2 exterior', 'Ninoy Aquino International Airport Terminal 2'],
    'Newport Mall': ['Newport Mall Resorts World Manila', 'Newport City Mall Pasay'],
    'Shrine of St. Thérèse of the Child Jesus': ['Shrine of St. Therese of the Child Jesus Villamor'],
    'Our Lady of Loreto Chapel': ['Villamor Air Base chapel', 'Our Lady of Loreto chapel Villamor'],
    'Philippines State College of Aeronautics': ['Philippine State College of Aeronautics'],
    'Villamor Air Base': ['Villamor Air Base'],
    'Bureau of Immigration One-Stop Shop': ['NAIA Terminal 3 exterior'],
    'Air Force General Hospital': ['Air Force General Hospital Villamor'],
    'Church of God - Marriott Manila': ['Manila Marriott Hotel Newport'],
}


def get_json(url):
    return json.load(urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=40))


def slug(n):
    return re.sub(r'[^a-z0-9]+', '-', n.lower()).strip('-')[:40]


def commons(name, queries, dest, index):
    got = 0
    for q in queries:
        try:
            d = get_json('https://commons.wikimedia.org/w/api.php?' + urllib.parse.urlencode(
                {'action': 'query', 'generator': 'search', 'gsrsearch': q, 'gsrnamespace': 6, 'gsrlimit': 10, 'prop': 'imageinfo',
                 'iiprop': 'url|extmetadata|mime', 'iiurlwidth': 1100, 'format': 'json'}))
        except Exception as e:
            print('  commons error', name, e)
            continue
        for p in (d.get('query', {}).get('pages', {}) or {}).values():
            ii = (p.get('imageinfo') or [{}])[0]
            if not ii.get('mime', '').startswith('image/jpeg'):
                continue
            md = ii.get('extmetadata', {})
            lic = (md.get('LicenseShortName', {}).get('value') or '')
            if not re.search(r'CC|Public domain|PD', lic, re.I):
                continue
            url = ii.get('thumburl') or ii.get('url')
            fn = os.path.join(dest, 'commons-%d.jpg' % got)
            try:
                data = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()
                open(fn, 'wb').write(data)
            except Exception as e:
                continue
            index.append({'file': os.path.basename(fn), 'source': 'Wikimedia Commons', 'title': p.get('title'), 'licence': lic,
                          'author': re.sub('<[^>]+>', '', md.get('Artist', {}).get('value', '') or '')[:80], 'page': ii.get('descriptionurl')})
            got += 1
            if got >= 5:
                return got
            time.sleep(.5)
        time.sleep(.5)
    return got


def mapillary(name, lng, lat, dest, index, token):
    d = .0006
    url = 'https://graph.mapillary.com/images?' + urllib.parse.urlencode({
        'access_token': token, 'bbox': '%f,%f,%f,%f' % (lng - d, lat - d, lng + d, lat + d), 'limit': 200,
        'fields': 'id,thumb_1024_url,compass_angle,captured_at,computed_geometry,is_pano'})
    try:
        items = get_json(url).get('data', [])
    except Exception as e:
        print('  mapillary error', name, e)
        return 0
    def dist(i):
        c = (i.get('computed_geometry') or {}).get('coordinates')
        return 1e9 if not c else math.hypot((c[0] - lng) * 107500, (c[1] - lat) * 110574)
    items = [i for i in items if i.get('thumb_1024_url') and not i.get('is_pano') and 8 < dist(i) < 70]
    items.sort(key=dist)
    chosen, angles = [], []
    for i in items:
        a = i.get('compass_angle') or 0
        if all(min(abs(a - b) % 360, 360 - abs(a - b) % 360) > 35 for b in angles):
            chosen.append(i)
            angles.append(a)
        if len(chosen) >= 5:
            break
    for k, i in enumerate(chosen):
        fn = os.path.join(dest, 'mapillary-%d.jpg' % k)
        try:
            open(fn, 'wb').write(urllib.request.urlopen(urllib.request.Request(i['thumb_1024_url'], headers=UA), timeout=60).read())
        except Exception:
            continue
        index.append({'file': os.path.basename(fn), 'source': 'Mapillary', 'licence': 'CC BY-SA 4.0', 'image': i['id'], 'distance_m': round(dist(i)), 'compass': i.get('compass_angle')})
        time.sleep(.3)
    return len(chosen)


def main():
    token = ''
    for envp in (os.path.join(ROOT, '.env'),):
        if os.path.exists(envp):
            for line in open(envp, encoding='utf-8'):
                if line.startswith('MAPILLARY_TOKEN='):
                    token = line.split('=', 1)[1].strip().strip('"\'')
    feats = json.load(open(LM, encoding='utf-8'))['features']
    seen = set()
    summary = {}
    for f in feats:
        name = f['properties']['name']
        if name in seen:
            continue
        seen.add(name)
        lng, lat = f['geometry']['coordinates']
        dest = os.path.join(REFS, slug(name))
        os.makedirs(dest, exist_ok=True)
        index = []
        c = commons(name, COMMONS.get(name, []), dest, index) if name in COMMONS else 0
        m = mapillary(name, lng, lat, dest, index, token) if token else 0
        json.dump({'name': name, 'lng': lng, 'lat': lat, 'photos': index}, open(os.path.join(dest, 'index.json'), 'w', encoding='utf-8'), indent=1, ensure_ascii=False)
        summary[name] = (c, m)
        print('%-45s commons %d  mapillary %d' % (name, c, m))
    print('photos in', REFS)


main()
