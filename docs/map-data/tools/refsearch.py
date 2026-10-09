#!/usr/bin/env python3
"""
Reference search, the engine's way of looking up what a landmark really looks like. For a name (and the place it stands) it asks every open source we have
access to and lays what it finds out as one board: photos from Openverse and Wikimedia Commons, street-level images from Mapillary (the nearest ones that
face the building), 3D models from Sketchfab (looked at for proportion only, never copied), each with its source, licence and author. Duplicates are dropped,
the best are ranked first. Nothing found here is shipped; a reference that is used is picked, and its credit goes in landmarks/REFS.md.

    python docs/map-data/tools/refsearch.py "Newport Mall"
    python docs/map-data/tools/refsearch.py "Plaza 66" --sources openverse,commons,mapillary --n 30
    python docs/map-data/tools/refsearch.py "Plaza 66" --pick commons:File_Plaza_66.jpg      mark a reference as used (credited)
    python docs/map-data/tools/refsearch.py "Newport Mall" --add C:/pics/mall1.jpg --credit "Google Images, resortsworld.com"   put a picture you found yourself on the board
    python docs/map-data/tools/refsearch.py "Newport Mall" --page https://example.com/some-article    every large picture of a web page you found, credited to it
    python docs/map-data/tools/refsearch.py --index-mapillary                                  (re)build the zone's street-view index
"""
import hashlib, html, io, json, math, os, re, sys, urllib.parse

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as K

INDEX = os.path.join(K.LM, 'refs-index.json')
INBOX = os.path.join(K.CACHE, 'inbox')        # pictures put here by hand: looked at, never committed or shipped
CREDITS = os.path.join(K.LM, 'REFS.md')
HERE_TERMS = ('manila', 'pasay', 'philippine', 'filipino', 'resorts world', 'newport city', 'newport boulevard', 'naia', 'villamor', 'metro manila', 'ninoy aquino', 'pasay city', 'barangay 183', 'kalayaan', 'sheraton manila', 'okura manila', 'marriott manila')
ELSEWHERE = ('isle of wight', ', iw', 'rhode island', 'wales', 'kentucky', 'england', 'new jersey', 'oregon', 'california', 'virginia', 'tennessee', 'vermont', 'cardiff', 'gwent', 'hampshire', 'shropshire', 'pembrokeshire', 'newport news', 'jersey city', 'shanghai', 'china', 'hong kong', 'beijing', 'singapore', 'london', 'new york', 'tokyo', 'bangkok', 'jakarta', 'seoul', 'taipei', 'kuala lumpur')
LIC_W = {'cc0': 1.0, 'pdm': 1.0, 'by': .8, 'by-sa': .6, 'by-nc': .35, 'by-nd': .3, 'by-nc-sa': .3, 'by-nc-nd': .25}


def _lic_key(label):
    s = (label or '').lower().replace('cc ', '').replace('-', ' ').strip()
    for k, w in (('cc0', 'cc0'), ('public domain', 'pdm'), ('pdm', 'pdm'), ('by nc nd', 'by-nc-nd'), ('by nc sa', 'by-nc-sa'), ('by nc', 'by-nc'), ('by nd', 'by-nd'), ('by sa', 'by-sa'), ('by', 'by')):
        if k in s:
            return w
    return 'by-nc-nd'


def context_of(text):
    """+1 if the text places the picture here, -1 if it places it elsewhere, 0 if it does not say."""
    t = (text or '').lower()
    if any(w in t for w in HERE_TERMS):
        return 1
    if any(w in t for w in ELSEWHERE):
        return -1
    return 0


def _entry(src, id_, title, author, lic, url, thumb, w=0, h=0, geo=None, extra=None):
    extra = dict(extra or {})
    extra.setdefault('ctx', context_of(' '.join([title or '', url or '', extra.get('where', '')])))
    return dict(src=src, id=str(id_), title=html.unescape(re.sub(r'<[^>]+>', '', title or '')).strip(), author=html.unescape(re.sub(r'<[^>]+>', '', author or '')).strip(), license=lic or '', url=url, thumb=thumb, w=w, h=h, geo=geo, **extra)


# ------------------------------------------------------------------ sources
def openverse(q, n):
    cid, sec = K.env('OPENVERSE_CLIENT_ID'), K.env('OPENVERSE_CLIENT_SECRET')
    if not cid:
        return []
    tok = K.get_json('https://api.openverse.org/v1/auth_tokens/token/', data=urllib.parse.urlencode({'grant_type': 'client_credentials', 'client_id': cid, 'client_secret': sec}).encode())['access_token']
    r = K.get_json('https://api.openverse.org/v1/images/?%s' % urllib.parse.urlencode({'q': q, 'page_size': min(n, 40), 'mature': 'false'}), {'Authorization': 'Bearer ' + tok})
    return [_entry('openverse', i['id'], i.get('title'), i.get('creator'), ('CC %s %s' % (i.get('license', '').upper(), i.get('license_version', ''))).strip(), i.get('foreign_landing_url'), i.get('thumbnail') or i.get('url'), i.get('width') or 0, i.get('height') or 0, extra={'where': ' '.join(t.get('name', '') for t in (i.get('tags') or []))}) for i in r.get('results', [])]


def commons(q, n, near=None):
    api = 'https://commons.wikimedia.org/w/api.php?'
    props = {'prop': 'imageinfo|categories', 'iiprop': 'url|size|extmetadata', 'iiurlwidth': 480, 'cllimit': 'max', 'format': 'json'}
    out = []

    def pages(js, geo=None):
        for p in (js.get('query', {}).get('pages', {}) or {}).values():
            ii = (p.get('imageinfo') or [{}])[0]
            if not ii:
                continue
            md = ii.get('extmetadata', {})
            where = ' '.join(c['title'] for c in p.get('categories', [])) + ' ' + (md.get('ImageDescription', {}).get('value') or '')
            out.append(_entry('commons', p['title'].replace('File:', '').replace(' ', '_'), md.get('ObjectName', {}).get('value') or p['title'], md.get('Artist', {}).get('value'), md.get('LicenseShortName', {}).get('value'),
                              ii.get('descriptionurl'), ii.get('thumburl') or ii.get('url'), ii.get('width', 0), ii.get('height', 0), geo, {'where': where}))
    pages(K.get_json(api + urllib.parse.urlencode(dict(props, action='query', generator='search', gsrsearch=q + ' filetype:bitmap', gsrnamespace=6, gsrlimit=min(n, 30)))))
    # the categories that are named for it (Category:Resorts World Manila) and the pictures in them
    try:
        cats = K.get_json(api + urllib.parse.urlencode({'action': 'query', 'list': 'search', 'srsearch': q, 'srnamespace': 14, 'srlimit': 3, 'format': 'json'})).get('query', {}).get('search', [])
        for c in cats[:2]:
            mem = K.get_json(api + urllib.parse.urlencode({'action': 'query', 'list': 'categorymembers', 'cmtitle': c['title'], 'cmtype': 'file', 'cmlimit': min(n, 40), 'format': 'json'})).get('query', {}).get('categorymembers', [])
            titles = [m['title'] for m in mem]
            if titles:
                before = len(out)
                pages(K.get_json(api + urllib.parse.urlencode(dict(props, action='query', titles='|'.join(titles[:40])))))
                for e in out[before:]:
                    e['where'] = (e.get('where', '') + ' ' + c['title'])
                    e['ctx'] = max(e.get('ctx', 0), context_of(e['where']))
                    e['cat'] = c['title']
    except Exception as ex:
        print('  commons categories: %s' % str(ex)[:60])
    if near:
        g = K.get_json(api + urllib.parse.urlencode({'action': 'query', 'list': 'geosearch', 'gscoord': '%f|%f' % (near[1], near[0]), 'gsradius': 400, 'gsnamespace': 6, 'gslimit': min(n, 30), 'format': 'json'}))
        titles = [x['title'] for x in g.get('query', {}).get('geosearch', [])]
        dist = {x['title']: x.get('dist') for x in g.get('query', {}).get('geosearch', [])}
        if titles:
            before = len(out)
            pages(K.get_json(api + urllib.parse.urlencode(dict(props, action='query', titles='|'.join(titles[:40])))))
            for e in out[before:]:
                e['geo'] = dist.get('File:' + e['id'].replace('_', ' '))
    return out


def google(q, n):
    """Google Programmable Search, image search over the whole web (the official API: 100 queries a day free; the key and the search engine id are in .env).
    Results are other people's pictures: they are looked at for reference, never copied or shipped, and each carries the page it came from."""
    key, cx = K.env('GOOGLE_CSE_KEY'), K.env('GOOGLE_CSE_CX')
    if not key or not cx:
        return []
    out = []
    for start in range(1, min(n, 30) + 1, 10):
        try:
            r = K.get_json('https://www.googleapis.com/customsearch/v1?%s' % urllib.parse.urlencode({'key': key, 'cx': cx, 'q': q, 'searchType': 'image', 'num': 10, 'start': start, 'safe': 'active', 'imgSize': 'large'}))
        except Exception as ex:
            print('  google: %s (Google has closed the Custom Search JSON API to new projects: use the finder, engine.py finder)' % str(ex)[:60])
            break
        for i in r.get('items', []):
            im = i.get('image', {})
            out.append(_entry('google', i['link'], i.get('title'), i.get('displayLink'), 'unknown (via Google; looked at only)', im.get('contextLink') or i['link'], im.get('thumbnailLink') or i['link'], im.get('width', 0), im.get('height', 0),
                              extra={'where': (i.get('snippet') or '') + ' ' + (im.get('contextLink') or '')}))
    return out


def flickr(q, n, near=None):
    """Flickr's own search (free non-commercial API key, FLICKR_KEY in .env): photos taken within 250 m of the building, any licence (looked at, linked to, credited), and by text."""
    key = K.env('FLICKR_KEY')
    if not key:
        return []
    out = []
    base = {'method': 'flickr.photos.search', 'api_key': key, 'format': 'json', 'nojsoncallback': 1, 'per_page': min(n, 60), 'extras': 'url_m,url_l,owner_name,license,tags,geo,description', 'sort': 'relevance', 'safe_search': 1, 'content_types': 0, 'media': 'photos'}
    runs = [dict(base, text=q)]
    if near:
        runs.append(dict(base, lat=near[1], lon=near[0], radius=0.25, radius_units='km', text=q.split(' ')[0]))
        runs.append(dict(base, lat=near[1], lon=near[0], radius=0.15, radius_units='km'))
    LIC = {'0': 'All rights reserved', '1': 'CC BY-NC-SA 2.0', '2': 'CC BY-NC 2.0', '3': 'CC BY-NC-ND 2.0', '4': 'CC BY 2.0', '5': 'CC BY-SA 2.0', '6': 'CC BY-ND 2.0', '7': 'No known copyright', '9': 'CC0', '10': 'Public domain'}
    for r in runs:
        try:
            js = K.get_json('https://www.flickr.com/services/rest/?' + urllib.parse.urlencode(r))
        except Exception as ex:
            print('  flickr: %s' % str(ex)[:70])
            continue
        for p in js.get('photos', {}).get('photo', []):
            u = p.get('url_l') or p.get('url_m')
            if not u:
                continue
            lic = LIC.get(str(p.get('license')), 'unknown')
            geo = None
            if near and p.get('latitude'):
                geo = round(math.hypot((float(p['longitude']) - near[0]) * K.MX, (float(p['latitude']) - near[1]) * K.MY))
            out.append(_entry('flickr', p['id'], p.get('title'), p.get('ownername'), lic + ('; looked at only' if lic.startswith('All') else ''), 'https://www.flickr.com/photos/%s/%s' % (p.get('owner'), p['id']), p.get('url_m') or u,
                              int(p.get('width_l') or p.get('width_m') or 0), int(p.get('height_l') or p.get('height_m') or 0), geo,
                              {'where': ' '.join([p.get('tags') or '', (p.get('description') or {}).get('_content', '')]) + (' manila' if geo is not None and geo < 250 else '')}))
    return out


def brave(q, n):
    """Brave Search, image search on an independent index (its official API; the key is BRAVE_SEARCH_KEY in .env). Other people's pictures: looked at only."""
    key = K.env('BRAVE_SEARCH_KEY')
    if not key:
        return []
    out = []
    r = K.get_json('https://api.search.brave.com/res/v1/images/search?%s' % urllib.parse.urlencode({'q': q, 'count': min(n, 50), 'safesearch': 'strict', 'country': 'ph', 'search_lang': 'en'}), {'X-Subscription-Token': key, 'Accept': 'application/json'})
    for i in r.get('results', []):
        pr = i.get('properties', {})
        th = (i.get('thumbnail') or {}).get('src') or pr.get('url')
        if not th:
            continue
        out.append(_entry('brave', pr.get('url') or i.get('url'), i.get('title'), i.get('source'), 'unknown (via Brave; looked at only)', i.get('url'), th, pr.get('width', 0), pr.get('height', 0), extra={'where': ' '.join([i.get('title') or '', i.get('url') or '', i.get('source') or ''])}))
    return out


def inbox_entries(name):
    """The pictures put on the board by hand (--add): they come first."""
    d = os.path.join(INBOX, re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-'))
    out = []
    if os.path.isdir(d):
        meta = json.load(open(os.path.join(d, 'meta.json'))) if os.path.exists(os.path.join(d, 'meta.json')) else {}
        for f in sorted(os.listdir(d)):
            if f.lower().endswith(('.jpg', '.jpeg', '.png', '.webp')):
                e = _entry('user', f, f, meta.get(f, {}).get('credit') or 'put here by hand', 'user-supplied (looked at only)', meta.get(f, {}).get('source') or 'file', None, extra={'ctx': 1})
                e['file'] = os.path.join(d, f)
                e['score'] = 9.0
                out.append(e)
    return out


def add(name, src, credit=None):
    """Put a picture (a file or a web address) in the inbox of a landmark; it will lead its board."""
    d = os.path.join(INBOX, re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-'))
    os.makedirs(d, exist_ok=True)
    data = K.get(src) if re.match(r'https?://', src) else open(src, 'rb').read()
    return add_bytes(name, data, src if src.startswith('http') else 'a file you gave', credit)


def add_bytes(name, data, source, credit=None):
    d = os.path.join(INBOX, re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-'))
    os.makedirs(d, exist_ok=True)
    base = hashlib.md5(data[:4096] + str(len(data)).encode()).hexdigest()[:10] + '.jpg'
    im = Image.open(io.BytesIO(data)).convert('RGB')
    if min(im.size) < 120:
        raise ValueError('too small to be a reference (%dx%d)' % im.size)
    im.save(os.path.join(d, base), quality=92)
    mp = os.path.join(d, 'meta.json')
    meta = json.load(open(mp)) if os.path.exists(mp) else {}
    meta[base] = {'source': source, 'credit': credit or ''}
    json.dump(meta, open(mp, 'w'), indent=1)
    print('added', os.path.join(d, base))
    return base


def grab_page(name, url, limit=12):
    """Every large picture on a web page (its social-share image and the big <img>s) goes to the landmark's inbox, credited to the page. For a page you found yourself:
    a hotel's own site, an article, a Wikipedia page."""
    html_ = K.get(url).decode('utf-8', 'ignore')
    base = url
    cands = []
    for m in re.finditer(r'<meta[^>]+(?:property|name)=["\'](?:og:image|twitter:image)["\'][^>]*content=["\']([^"\']+)', html_, re.I):
        cands.append(m.group(1))
    for m in re.finditer(r'<img[^>]+>', html_, re.I):
        tag = m.group(0)
        src = re.search(r'(?:data-src|src)=["\']([^"\']+)', tag, re.I)
        ss = re.search(r'srcset=["\']([^"\']+)', tag, re.I)
        w = re.search(r'width=["\']?(\d+)', tag, re.I)
        if ss:
            best = max((p.strip().split(' ') for p in ss.group(1).split(',') if p.strip()), key=lambda p: int(re.sub(r'\D', '', p[1]) or 0) if len(p) > 1 else 0)
            cands.append(best[0])
        elif src and (not w or int(w.group(1)) >= 300):
            cands.append(src.group(1))
    got, seen = 0, set()
    for c in cands:
        u = urllib.parse.urljoin(base, html.unescape(c))
        if u in seen or not re.search(r'\.(jpe?g|png|webp)(\?|$)|upload\.wikimedia|images?/|cdn', u, re.I) or re.search(r'logo|icon|sprite|avatar|pixel|\.svg', u, re.I):
            continue
        seen.add(u)
        try:
            add_bytes(name, K.get(u), url, 'web page ' + urllib.parse.urlparse(url).netloc)
            got += 1
        except Exception:
            continue
        if got >= limit:
            break
    print('%d pictures from %s' % (got, url))


def sketchfab(q, n):
    tok = K.env('SKETCHFAB_TOKEN')
    if not tok:
        return []
    r = K.get_json('https://api.sketchfab.com/v3/search?%s' % urllib.parse.urlencode({'type': 'models', 'q': q, 'count': min(n, 24)}), {'Authorization': 'Token ' + tok})
    out = []
    for m in r.get('results', []):
        th = sorted(m['thumbnails']['images'], key=lambda i: abs(i['width'] - 480))[0]['url'] if m.get('thumbnails', {}).get('images') else None
        out.append(_entry('sketchfab', m['uid'], m.get('name'), (m.get('user') or {}).get('displayName'), (m.get('license') or {}).get('label') or 'unknown', m.get('viewerUrl'), th, extra={'model': True, 'faces': m.get('faceCount')}))
    return out


def mapillary(name, near, n):
    """The street-level images nearest the building that look towards it (from the zone index: no network call)."""
    imgs = K.mly_index()
    if not imgs or not near:
        return []
    out = []
    for i in imgs:
        g = i.get('computed_geometry')
        if not g or i.get('is_pano') or not i.get('thumb_1024_url'):
            continue
        lng, lat = g['coordinates']
        dx, dy = (near[0] - lng) * K.MX, (near[1] - lat) * K.MY
        d = math.hypot(dx, dy)
        if d < 10 or d > 90:
            continue
        brg = (math.degrees(math.atan2(dx, dy)) + 360) % 360
        off = abs((i.get('compass_angle', 0) - brg + 180) % 360 - 180)
        if off > 40:
            continue
        out.append((d + off * .5, i, d))
    out.sort(key=lambda t: t[0])
    return [_entry('mapillary', i['id'], '%s from %d m' % (name, d), 'Mapillary contributors', 'CC BY-SA 4.0', 'https://www.mapillary.com/app/?pKey=%s' % i['id'], i['thumb_1024_url'], geo=round(d), extra={'ctx': 1, 'bearing': round(i.get('compass_angle', 0)), 'dist': round(d)}) for _, i, d in out[:n]]


def index_mapillary():
    """Every image Mapillary has in the zone, in small boxes (the Graph API caps a box); written to the cache."""
    tok = K.env('MAPILLARY_TOKEN')
    z = K.ZONE
    step = .0016
    got = {}
    lng = z[0]
    while lng < z[2]:
        lat = z[1]
        while lat < z[3]:
            box = '%f,%f,%f,%f' % (lng, lat, lng + step, lat + step)
            u = 'https://graph.mapillary.com/images?access_token=%s&bbox=%s&limit=2000&fields=id,compass_angle,captured_at,computed_geometry,is_pano,camera_type,thumb_1024_url' % (tok, box)
            for i in K.get_json(u).get('data', []):
                got[i['id']] = i
            lat += step
        lng += step
        print('  %.0f%%' % (100 * (lng - z[0]) / (z[2] - z[0])), end='\r')
    os.makedirs(K.CACHE, exist_ok=True)
    json.dump(list(got.values()), open(os.path.join(K.CACHE, 'mly_zone.json'), 'w'))
    print('indexed %d images' % len(got))


# ------------------------------------------------------------------ ranking, de-duplication, board
def dhash(im):
    g = im.convert('L').resize((9, 8), Image.LANCZOS)
    px = list(g.get_flattened_data() if hasattr(g, 'get_flattened_data') else g.getdata())
    return sum(1 << k for k, (a, b) in enumerate((px[r * 9 + c], px[r * 9 + c + 1]) for r in range(8) for c in range(8)) if a > b)


def fetch_thumb(e):
    os.makedirs(K.REFS, exist_ok=True)
    p = os.path.join(K.REFS, '%s_%s.jpg' % (e['src'], hashlib.md5(e['id'].encode()).hexdigest()[:12]))
    if not os.path.exists(p):
        try:
            Image.open(io.BytesIO(K.get(e['thumb']))).convert('RGB').save(p, quality=85)
        except Exception:
            return None
    return p


def score(e, q):
    words = [w for w in re.findall(r'[a-z0-9]+', q.lower()) if len(w) > 1]
    t = (e['title'] + ' ' + e['url']).lower()
    rel = sum(1 for w in words if w in t) / max(1, len(words))
    lic = LIC_W.get(_lic_key(e['license']), .25)
    geo = max(0.0, 1 - (e['geo'] or 400) / 400) if e.get('geo') is not None and e['src'] != 'mapillary' else (max(0.0, 1 - e['geo'] / 90) * .6 if e['src'] == 'mapillary' and e.get('geo') else 0)
    size = min(1.0, min(e['w'] or 600, e['h'] or 600) / 900) * .3
    return rel * 3 + lic + geo + size + (1.6 if e.get('ctx', 0) > 0 else (-2.5 if e.get('ctx', 0) < 0 else 0))


def relevant(e, name, loose=False):
    """A picture is kept when it says it was taken here (or is a street-level frame, which is here by construction) and is about this building; --loose also keeps those that do not say where."""
    if e['src'] == 'mapillary':
        return True
    words = [w for w in re.findall(r'[a-z0-9]+', name.lower()) if len(w) > 1]
    t = (e['title'] + ' ' + e['url']).lower()
    rel = sum(1 for w in words if w in t) / max(1, len(words))
    near = e.get('geo') is not None and e['geo'] <= 150
    ok_ctx = e.get('ctx', 0) > 0 or ((loose or e['src'] in ('google', 'brave')) and e.get('ctx', 0) == 0)
    return ok_ctx and (rel >= .5 or (near and rel > 0))


def search(name, sources=('openverse', 'commons', 'mapillary', 'sketchfab'), n=24, near=None, queries=None, loose=False):
    if near is None:
        bi, b = K.building_named(name)
        near = (b[4], b[5]) if b else None
    qs = queries or [name + ' Pasay', name, name + ' exterior Manila', name + ' facade']
    res = []
    for q in qs:
        for s in sources:
            try:
                if s == 'openverse':
                    res += openverse(q, n)
                elif s == 'commons':
                    res += commons(q, n, near)
                elif s == 'sketchfab':
                    res += sketchfab(q, n)
                elif s == 'google':
                    res += google(q, n)
                elif s == 'brave':
                    res += brave(q, n)
                elif s == 'flickr':
                    res += flickr(q, n, near)
            except Exception as ex:
                print('  %s (%s): %s' % (s, q, str(ex)[:80]))
        if 'mapillary' in sources and q == qs[-1]:
            res += mapillary(name, near, n * 5)
    # drop what is the same picture twice, keep the best-ranked of each
    res.sort(key=lambda e: -score(e, name))
    # rank first, then fetch only the thumbnails that can still make the board (eight at a time)
    uniq, seen = [], set()
    for e in res:
        k = (e['src'], e['id'])
        if k in seen or not relevant(e, name, loose):
            continue
        seen.add(k)
        uniq.append(e)
    uniq = uniq[:n * 6]
    import concurrent.futures as cf
    with cf.ThreadPoolExecutor(8) as ex:
        files = list(ex.map(fetch_thumb, uniq))
    out, hashes = [], []
    for e in inbox_entries(name):
        out.append(e)
        hashes.append(dhash(Image.open(e['file'])))
    for e, p in zip(uniq, files):
        if not p:
            continue
        e['file'] = p
        try:
            h = dhash(Image.open(p))
        except Exception:
            continue
        if any(bin(h ^ x).count('1') <= 5 for x in hashes):
            continue
        hashes.append(h)
        e['score'] = round(score(e, name), 2)
        out.append(e)
    # a picture placed elsewhere is not shown at all; ones that do not say where come after the ones that do
    out = [e for e in out if relevant(e, name, loose)]
    for e in out:                      # a street frame that shows the building in good light beats one taken from under a flyover
        if e['src'] == 'mapillary':
            e['score'] = round(e['score'] + frame_quality(e['file']), 2)
    out.sort(key=lambda e: -e['score'])
    out = diversify(out)
    out.sort(key=lambda e: -e['score'])
    return out[:n]


def frame_quality(path):
    """0 to 2.5: how bright and how colourful a street frame is, and how much of it is not a dark roof or a bonnet."""
    try:
        import numpy as np
        a = np.asarray(Image.open(path).convert('RGB').resize((96, 72)), dtype=np.float32)
    except Exception:
        return 0.0
    lum = a.mean(-1)
    colour = (a.max(-1) - a.min(-1)).mean() / 255
    top = lum[:int(72 * .45)].mean()           # the upper part of a frame under a flyover is black
    return float(min(1.0, lum.mean() / 110) * 1.0 + min(1.0, colour * 6) * 0.8 + min(1.0, top / 90) * 0.7)


def diversify(entries):
    """Street-level frames come in dozens a few metres apart: keep one for each way of looking at the building (about 30 degrees of bearing, about 15 m of distance)."""
    seen, out = set(), []
    for e in entries:
        if e['src'] == 'mapillary':
            k = (e.get('bearing', 0) // 30, e.get('dist', 0) // 15)
            if k in seen:
                continue
            seen.add(k)
        out.append(e)
    return out


def board(name, entries, out=None, cols=5):
    W, H, CAP = 300, 210, 44
    rows = max(1, math.ceil(len(entries) / cols))
    S = Image.new('RGB', (cols * W, rows * (H + CAP) + 36), (16, 19, 34))
    d = ImageDraw.Draw(S)
    try:
        f, f2 = ImageFont.truetype('C:/Windows/Fonts/segoeuib.ttf', 15), ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf', 12)
    except Exception:
        f = f2 = ImageFont.load_default()
    d.text((10, 8), 'References for %s: %d found' % (name, len(entries)), fill=(240, 240, 250), font=f)
    for k, e in enumerate(entries):
        x, y = (k % cols) * W, 36 + (k // cols) * (H + CAP)
        im = Image.open(e['file']).convert('RGB')
        im.thumbnail((W - 6, H - 4))
        S.paste(im, (x + 3 + (W - 6 - im.width) // 2, y + 2 + (H - 4 - im.height) // 2))
        tag = {'openverse': 'OV', 'commons': 'WC', 'mapillary': 'MLY', 'sketchfab': '3D', 'google': 'G', 'brave': 'BR', 'flickr': 'FL', 'user': 'ME'}[e['src']]
        d.rectangle([x + 3, y + 2, x + 3 + 38, y + 20], fill=(232, 120, 12))
        d.text((x + 8, y + 3), tag, fill=(20, 14, 0), font=f2)
        d.text((x + 6, y + H), (e['title'] or '')[:44], fill=(230, 232, 245), font=f2)
        d.text((x + 6, y + H + 16), ('%s · %s · #%d' % ((e['license'] or '?')[:22], (e['author'] or '')[:20], k + 1)), fill=(150, 156, 190), font=f2)
    p = out or os.path.join(K.CACHE, 'board_%s.jpg' % re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-'))
    S.save(p, quality=88)
    return p


def remember(name, entries):
    db = json.load(open(INDEX, encoding='utf-8')) if os.path.exists(INDEX) else {}
    keep = {(e['src'], e['id']): e for e in db.get(name, []) if e.get('picked')}
    rows = []
    for e in entries:
        r = {k: e[k] for k in ('src', 'id', 'title', 'author', 'license', 'url', 'score', 'cat') if k in e}
        if (e['src'], e['id']) in keep:
            r['picked'] = True
        rows.append(r)
    for (s, i), e in keep.items():
        if not any(r['src'] == s and r['id'] == i for r in rows):
            rows.append(e)
    db[name] = rows
    json.dump(db, open(INDEX, 'w', encoding='utf-8'), indent=1, ensure_ascii=False)


def pick(name, ref):
    db = json.load(open(INDEX, encoding='utf-8'))
    src, _, id_ = ref.partition(':')
    for e in db.get(name, []):
        if e['src'] == src and e['id'] == id_:
            e['picked'] = True
            break
    else:
        raise SystemExit('not in the index: %s (search first)' % ref)
    json.dump(db, open(INDEX, 'w', encoding='utf-8'), indent=1, ensure_ascii=False)
    lines = ['# References used', '', 'What each landmark was drawn after. Pictures and models are looked at, never copied or shipped; this file credits them.', '']
    for nm, es in sorted(db.items()):
        used = [e for e in es if e.get('picked')]
        if used:
            lines.append('## %s' % nm)
            lines += ['- %s: "%s" by %s, %s (%s)' % (e['src'], e['title'], e['author'] or 'unknown', e['license'], e['url']) for e in used]
            lines.append('')
    open(CREDITS, 'w', encoding='utf-8').write('\n'.join(lines))
    print('credited in', CREDITS)


def main():
    a = sys.argv[1:]
    if '--index-mapillary' in a:
        return index_mapillary()
    name = next((x for x in a if not x.startswith('--') and (a.index(x) == 0)), None)
    if not name:
        raise SystemExit(__doc__)
    opt = lambda k, d=None: a[a.index(k) + 1] if k in a else d
    if '--pick' in a:
        return pick(name, opt('--pick'))
    if '--page' in a:
        return grab_page(name, opt('--page'))
    if '--add' in a:
        return add(name, opt('--add'), opt('--credit'))
    src = tuple((opt('--sources') or ('openverse,commons,mapillary,sketchfab' + (',google' if K.env('GOOGLE_CSE_KEY') else '') + (',brave' if K.env('BRAVE_SEARCH_KEY') else '') + (',flickr' if K.env('FLICKR_KEY') else ''))).split(','))
    near = tuple(float(x) for x in opt('--near').split(',')) if opt('--near') else None
    es = search(name, src, int(opt('--n', 24)), near, loose='--loose' in a)
    remember(name, es)
    for k, e in enumerate(es, 1):
        print('%2d. [%s] %s | %s | %s | %s' % (k, e['src'], e['title'][:50], e['license'], e['author'][:24], e['url']))
    print('board:', board(name, es, opt('--out')))


if __name__ == '__main__':
    main()
