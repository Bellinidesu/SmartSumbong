"""Shared by the map tools: keys from .env, the street-view index, where caches live, a polite HTTP get."""
import json, math, os, sys, time, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
ADMIN = os.path.join(ROOT, 'admin')
MAPDIR = os.path.join(ADMIN, 'assets', 'map')
LM = os.path.join(HERE, '..', 'landmarks')
CACHE = os.path.join(HERE, 'mly-cache')            # every cache here is git-ignored
REFS = os.path.join(CACHE, 'refs')
UA = {'User-Agent': 'SmartSumbong/1.0 (barangay portal map tools; acelediac@gmail.com)'}
MX, MY = 111320 * math.cos(math.radians(14.525)), 110574
ZONE = (121.0105, 14.5120, 121.0240, 14.5262)


def env(key, default=None):
    try:
        for l in open(os.path.join(ROOT, '.env'), encoding='utf-8'):
            if l.startswith(key + '='):
                return l.split('=', 1)[1].strip().strip('"\'')
    except OSError:
        pass
    return os.environ.get(key, default)


def get(url, headers=None, data=None, timeout=40, tries=3):
    h = dict(UA)
    h.update(headers or {})
    last = None
    for k in range(tries):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=h, data=data), timeout=timeout).read()
        except Exception as e:
            last = e
            time.sleep(1.2 * (k + 1))
    raise last


def get_json(url, headers=None, data=None, timeout=40):
    return json.loads(get(url, headers, data, timeout).decode('utf-8'))


def mly_index_path():
    for p in (os.path.join(CACHE, 'mly_zone.json'), os.path.join(os.environ.get('LOCALAPPDATA', ''), 'Temp', 'ic', 'src', 'mly_zone.json')):
        if os.path.exists(p):
            return p
    return os.path.join(CACHE, 'mly_zone.json')


def mly_index():
    """The Mapillary images of the zone (id, compass angle, position, camera type, a thumbnail url): built once by refsearch.py --index-mapillary."""
    p = mly_index_path()
    return json.load(open(p, encoding='utf-8')) if os.path.exists(p) else []


def buildings():
    d = json.load(open(os.path.join(MAPDIR, 'buildings.json'), encoding='utf-8'))
    return d['b'], d.get('info', {})


def building_named(name):
    b, info = buildings()
    for k, v in info.items():
        if v[0] == name:
            return int(k), b[int(k)]
    low = name.lower()
    for k, v in info.items():
        if low in v[0].lower():
            return int(k), b[int(k)]
    return None, None
