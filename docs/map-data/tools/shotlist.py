#!/usr/bin/env python3
"""
The shot list: for a landmark, a page of Google Maps links, each opening Street View at a spot round the building and facing it (Google's own URL scheme: map_action=pano), plus an
aerial link at several headings. You click one, take a screenshot (Win+Shift+S), paste it into the finder (engine.py finder), and tick it off. The spots are on the open streets round the
footprint: the front (the face with the most open ground), each long side, each corner, and set-back views that show the roofline.

    python docs/map-data/tools/shotlist.py "Barangay 183 Hall"            writes tools/shotlist-out/<slug>.html and opens it
Nothing is fetched from Google; the links are built here. Where Street View has no picture at a spot Google moves you to the nearest one.
"""
import html, json, math, os, re, sys, subprocess

import numpy as np
from shapely.geometry import Point, Polygon, LineString

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as K

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'shotlist-out')


def link_pano(lat, lng, heading, pitch=8, fov=75):
    return 'https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=%.6f,%.6f&heading=%d&pitch=%d&fov=%d' % (lat, lng, heading % 360, pitch, fov)


def link_map(lat, lng):
    return 'https://www.google.com/maps/@%.6f,%.6f,60m/data=!3m1!1e3' % (lat, lng)


def spots(name):
    bi, b = K.building_named(name)
    if b is None:
        raise SystemExit('no building called ' + name)
    bld, info = K.buildings()
    o = (b[4], b[5])
    ring = [((b[0][i] - o[0]) * K.MX, (b[0][i + 1] - o[1]) * K.MY) for i in range(0, len(b[0]), 2)]
    poly = Polygon(ring).buffer(0)
    others = [Polygon([((q[0][k] - o[0]) * K.MX, (q[0][k + 1] - o[1]) * K.MY) for k in range(0, len(q[0]), 2)]).buffer(0) for q in bld if q is not b and abs(q[4] - b[4]) < .0014 and abs(q[5] - b[5]) < .0014]
    free = lambda p: all(not ot.contains(p) and ot.distance(p) > 2 for ot in others) and not poly.contains(p)
    out = []
    c = poly.centroid
    maxr = max(Point(p).distance(c) for p in ring)
    # eight bearings, and for each the nearest free spot at a stand-off that frames the building
    for k in range(8):
        ang = math.radians(k * 45)
        for r in (maxr + 14, maxr + 24, maxr + 36, maxr + 50):
            p = Point(c.x + math.sin(ang) * r, c.y + math.cos(ang) * r)
            if free(p):
                brg = (math.degrees(ang) + 180) % 360
                lat, lng = o[1] + p.y / K.MY, o[0] + p.x / K.MX
                out.append(dict(label=['north', 'north-east', 'east', 'south-east', 'south', 'south-west', 'west', 'north-west'][k], dist=int(r), lat=lat, lng=lng, heading=brg, why='the building seen from the %s' % ['north', 'north-east', 'east', 'south-east', 'south', 'south-west', 'west', 'north-west'][k]))
                break
    # a close view of each face longer than 8 m, from just outside it
    n = len(ring)
    for i in range(n):
        a_, b_ = ring[i], ring[(i + 1) % n]
        ln = math.hypot(b_[0] - a_[0], b_[1] - a_[1])
        if ln < 8:
            continue
        mid = ((a_[0] + b_[0]) / 2, (a_[1] + b_[1]) / 2)
        nx, ny = (b_[1] - a_[1]) / ln, -(b_[0] - a_[0]) / ln
        for d in (9, 14, 20):
            p = Point(mid[0] + nx * d, mid[1] + ny * d)
            if free(p):
                brg = (math.degrees(math.atan2(-nx, -ny)) + 360) % 360
                out.append(dict(label='face %d (%.0f m long)' % (i + 1, ln), dist=d, lat=o[1] + p.y / K.MY, lng=o[0] + p.x / K.MX, heading=brg, why='a close view of this wall'))
                break
    return o, out


def main():
    a = [x for x in sys.argv[1:] if not x.startswith('--')]
    if not a:
        raise SystemExit(__doc__)
    name = a[0]
    o, sp = spots(name)
    os.makedirs(OUT, exist_ok=True)
    slug = re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')
    rows = []
    for k, s in enumerate(sp, 1):
        rows.append('<li><label><input type="checkbox"> <b>%d. %s</b> <small>%d m out</small></label> <a href="%s" target="_blank">Street View</a> <span>%s</span></li>' % (k, html.escape(s['label']), s['dist'], html.escape(link_pano(s['lat'], s['lng'], s['heading'])), html.escape(s['why'])))
    aer = ' '.join('<a href="%s" target="_blank">aerial</a>' % html.escape(link_map(o[1], o[0])) for _ in range(1))
    page = '''<!doctype html><meta charset="utf-8"><title>Shot list: %(n)s</title>
<style>body{font:15px/1.5 "Segoe UI",system-ui,sans-serif;background:#0f1224;color:#eceaf7;max-width:760px;margin:24px auto;padding:0 16px}h1{font-size:1.3rem}ul{list-style:none;padding:0;display:grid;gap:8px}
li{background:#171b33;border:1px solid #2b3050;border-radius:8px;padding:10px 12px;display:flex;gap:12px;align-items:center;flex-wrap:wrap}li a{background:#ff9a2e;color:#1b1200;padding:3px 10px;border-radius:99px;text-decoration:none;font-weight:600}
small,span{color:#9ba0c4}input{accent-color:#3fd0c9}.tip{color:#9ba0c4}</style>
<h1>Shot list: %(n)s</h1>
<p class="tip">Open a link, turn and zoom until the building fills the view, screenshot (Win+Shift+S), then paste into the finder (engine.py finder) under "%(n)s". Take the aerial view too: %(aer)s, tilted, from two sides.
If Street View has nothing at a spot, skip it. Tick each one when done.</p><ul>%(rows)s</ul>''' % dict(n=html.escape(name), rows='\n'.join(rows), aer=aer)
    p = os.path.join(OUT, slug + '.html')
    open(p, 'w', encoding='utf-8').write(page)
    print(len(sp), 'spots ->', p)
    if '--no-open' not in sys.argv:
        for exe in ('C:/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe', 'C:/Program Files/Google/Chrome/Application/chrome.exe'):
            if os.path.exists(exe):
                subprocess.Popen([exe, p])
                break


if __name__ == '__main__':
    main()
