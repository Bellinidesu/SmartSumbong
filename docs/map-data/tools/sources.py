#!/usr/bin/env python3
"""
What the owners, the builders and the open databases say about a place, found by following the links the map data itself carries: every OpenStreetMap object in
the area that names a website, an image, a Commons category, a Wikipedia article or a Wikidata item; and for each Wikidata item its picture, its official site, its
architect, its floors, its height, the year it opened. One report, and the pictures that belong to a named landmark go to its reference inbox.

    python docs/map-data/tools/sources.py "Newport City"                       the report for the area around that building or landmark (600 m)
    python docs/map-data/tools/sources.py --bbox 121.014,14.516,121.0225,14.523
    python docs/map-data/tools/sources.py "Newport City" --grab                also take the large pictures of every official page it finds (credited to each page)
"""
import json, os, re, sys, urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as K
import refsearch

OUT = os.path.join(K.LM, 'sources-report.json')
PROPS = {'P18': 'image', 'P856': 'official website', 'P84': 'architect', 'P1101': 'floors', 'P2048': 'height (m)', 'P571': 'opened', 'P137': 'operator', 'P127': 'owner', 'P631': 'structural engineer', 'P193': 'main building contractor', 'P1435': 'heritage', 'P149': 'architectural style', 'P2043': 'length'}


def overpass(bbox):
    s, w, n, e = bbox[1], bbox[0], bbox[3], bbox[2]
    q = '''[out:json][timeout:120];(
      nwr["website"](%(b)s);nwr["contact:website"](%(b)s);nwr["image"](%(b)s);nwr["wikimedia_commons"](%(b)s);nwr["wikipedia"](%(b)s);nwr["wikidata"](%(b)s);nwr["mapillary"](%(b)s);nwr["operator:website"](%(b)s);
    );out tags center;''' % {'b': '%f,%f,%f,%f' % (s, w, n, e)}
    import time
    from urllib.request import Request, urlopen
    for h in ('overpass.openstreetmap.fr', 'overpass-api.de', 'z.overpass-api.de'):
        try:
            r = urlopen(Request('https://%s/api/interpreter' % h, data=urllib.parse.urlencode({'data': q}).encode(), headers=K.UA), timeout=150)
            return json.loads(r.read().decode('utf-8'))['elements']
        except Exception as ex:
            print('  %s: %s' % (h, str(ex)[:60]))
    return []


def wikidata(ids):
    out = {}
    ids = sorted(set(ids))
    for i in range(0, len(ids), 40):
        chunk = ids[i:i + 40]
        js = K.get_json('https://www.wikidata.org/w/api.php?' + urllib.parse.urlencode({'action': 'wbgetentities', 'ids': '|'.join(chunk), 'props': 'claims|labels|descriptions', 'languages': 'en', 'format': 'json'}))
        for q, ent in js.get('entities', {}).items():
            facts = {}
            for p, label in PROPS.items():
                for c in ent.get('claims', {}).get(p, [])[:3]:
                    v = c.get('mainsnak', {}).get('datavalue', {}).get('value')
                    if v is None:
                        continue
                    if isinstance(v, dict) and 'id' in v:
                        facts.setdefault(label, []).append(('item', v['id']))
                    elif isinstance(v, dict) and 'amount' in v:
                        facts.setdefault(label, []).append(('n', v['amount'].lstrip('+')))
                    elif isinstance(v, dict) and 'time' in v:
                        facts.setdefault(label, []).append(('n', v['time'][1:5]))
                    else:
                        facts.setdefault(label, []).append(('s', v))
            out[q] = dict(label=(ent.get('labels', {}).get('en') or {}).get('value'), desc=(ent.get('descriptions', {}).get('en') or {}).get('value'), facts=facts)
    # item ids in the facts (an architect, an operator) are named in a second look
    need = {v for e in out.values() for vs in e['facts'].values() for t, v in vs if t == 'item' and v not in out}
    names = {}
    need = sorted(need)
    for i in range(0, len(need), 40):
        js = K.get_json('https://www.wikidata.org/w/api.php?' + urllib.parse.urlencode({'action': 'wbgetentities', 'ids': '|'.join(need[i:i + 40]), 'props': 'labels', 'languages': 'en', 'format': 'json'}))
        for q, ent in js.get('entities', {}).items():
            names[q] = (ent.get('labels', {}).get('en') or {}).get('value') or q
    for e in out.values():
        for k, vs in e['facts'].items():
            e['facts'][k] = [names.get(v, v) if t == 'item' else v for t, v in vs]
    return out


def commons_url(fn):
    fn = fn.replace(' ', '_')
    return 'https://commons.wikimedia.org/wiki/Special:FilePath/%s?width=1200' % urllib.parse.quote(fn)


def main():
    a = sys.argv[1:]
    if '--bbox' in a:
        bbox = tuple(float(x) for x in a[a.index('--bbox') + 1].split(','))
        title = 'bbox'
    else:
        name = next((x for x in a if not x.startswith('--')), None)
        if not name:
            raise SystemExit(__doc__)
        bi, b = K.building_named(name)
        if not b:
            raise SystemExit('no building called %s' % name)
        r = 600
        bbox = (b[4] - r / K.MX, b[5] - r / K.MY, b[4] + r / K.MX, b[5] + r / K.MY)
        title = name
    els = overpass(bbox)
    print('%d OpenStreetMap objects with a link in %s' % (len(els), title))
    qids = [e['tags']['wikidata'] for e in els if re.fullmatch(r'Q\d+', e['tags'].get('wikidata', ''))]
    wd = wikidata(qids) if qids else {}
    rep = []
    for e in els:
        t = e['tags']
        nm = t.get('name') or t.get('brand') or t.get('operator') or '(unnamed)'
        sites = [t[k] for k in ('website', 'contact:website', 'operator:website') if t.get(k)]
        row = dict(name=nm, osm='%s/%s' % (e['type'], e['id']), sites=sites, commons=t.get('wikimedia_commons'), image=t.get('image'), wikipedia=t.get('wikipedia'), wikidata=t.get('wikidata'), mapillary=t.get('mapillary'),
                   lat=(e.get('center') or e).get('lat'), lon=(e.get('center') or e).get('lon'))
        if row['wikidata'] in wd:
            row['wd'] = wd[row['wikidata']]
        rep.append(row)
    rep.sort(key=lambda r: (not ('wd' in r), not r['commons'], r['name']))
    json.dump(rep, open(OUT, 'w', encoding='utf-8'), indent=1, ensure_ascii=False)
    for r in rep:
        line = '%-38s' % r['name'][:38]
        if r.get('wd'):
            f = r['wd']['facts']
            line += ' | wikidata: ' + '; '.join('%s %s' % (k, ', '.join(map(str, v))) for k, v in f.items() if k != 'image')
        if r['sites']:
            line += ' | ' + ' '.join(r['sites'])[:80]
        if r['commons']:
            line += ' | commons: ' + r['commons'][:50]
        if r['wikidata'] or r['sites'] or r['commons'] or r['wikipedia']:
            print(line)
    print('report:', OUT)
    if '--grab' in a:
        done = set()
        only = a[a.index('--only') + 1] if '--only' in a else None
        for r in rep:
            if r['name'] == '(unnamed)' or (only and not re.search(only, r['name'], re.I)):
                continue
            for u in r['sites'][:1]:
                if u in done or not u.startswith('http'):
                    continue
                done.add(u)
                try:
                    refsearch.grab_page(r['name'], u, 8)
                except Exception as ex:
                    print('  %s: %s' % (u[:60], str(ex)[:50]))
            for f in ([r['commons']] if r['commons'] and r['commons'].startswith('File:') else []) + list(r.get('wd', {}).get('facts', {}).get('image') or []):
                try:
                    refsearch.add(r['name'], commons_url(f.replace('File:', '')), 'Wikimedia Commons: %s' % f)
                except Exception as ex:
                    print('  %s: %s' % (f[:50], str(ex)[:50]))


if __name__ == '__main__':
    main()
