#!/usr/bin/env python3
"""
The landmark bench: one landmark on its own, lit with the baked light, from four sides, by day and by night, next to what the real building looks like from
the street. A contact sheet in one image, so a change to a landmark's sheet can be judged at a glance, with the sheet saved on every run.

    python docs/map-data/tools/bench.py "Plaza 66"                 photograph what is built
    python docs/map-data/tools/bench.py "Plaza 66" --rebuild       rebuild the models first (models.py, about 15 s; the baked light stays as it was)
    python docs/map-data/tools/bench.py "Plaza 66" --watch         rebuild and photograph again whenever the landmark's sheet is saved

Output: docs/map-data/tools/bench/out/<slug>/sheet.jpg (and the single frames). Needs Node and Brave or Chrome (the GPU does the drawing).
"""
import http.server, json, math, os, re, subprocess, sys, threading, time, urllib.parse

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
ADMIN = os.path.join(ROOT, 'admin')
BENCH = os.path.join(HERE, 'bench')
LM = os.path.join(HERE, '..', 'landmarks')
VIEWS = [(0, 'south'), (90, 'east'), (180, 'north'), (270, 'west')]


class Handler(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        p = urllib.parse.urlparse(path).path
        if p in ('/', '/bench.html'):
            return os.path.join(BENCH, 'bench.html')
        return os.path.join(ADMIN, p.lstrip('/').replace('/', os.sep))

    def log_message(self, *a):
        pass

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()


def serve():
    srv = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, srv.server_address[1]


def slug_of(name):
    return re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')


def shoot(name, port, out):
    urls = []
    for night in (0, 1):
        for az, _ in VIEWS:
            urls.append('http://127.0.0.1:%d/?name=%s&az=%d&pitch=26&night=%d' % (port, urllib.parse.quote(name), az, night))
    subprocess.run(['node', os.path.join(BENCH, 'shoot.mjs'), out] + urls, check=True)


def reference(name):
    """Two unwrapped street-view faces of the real building (Mapillary 360 panoramas), if the building is found and seen."""
    sys.path.insert(0, HERE)
    try:
        import mly_rectify as R
        from shapely.geometry import LineString, Polygon
        imgs = [i for i in json.load(open(os.path.join(os.environ.get('LOCALAPPDATA', ''), 'Temp', 'ic', 'src', 'mly_zone.json'))) if i.get('is_pano') and i.get('computed_geometry')]
    except Exception as e:
        print('  (no street-view reference: %s)' % e)
        return []
    d = json.load(open(os.path.join(ADMIN, 'assets', 'map', 'buildings.json')))
    bld, info = d['b'], d.get('info', {})
    bi = next((int(k) for k, v in info.items() if v[0] == name), None)
    if bi is None:
        return []
    b = bld[bi]
    MX, MY = R.MX, R.MY
    o = (b[4], b[5])
    ring = [((b[0][i] - o[0]) * MX, (b[0][i + 1] - o[1]) * MY) for i in range(0, len(b[0]), 2)]
    others = [Polygon([((q[0][k] - o[0]) * MX, (q[0][k + 1] - o[1]) * MY) for k in range(0, len(q[0]), 2)]).buffer(0) for q in bld if q is not b and abs(q[4] - b[4]) < .0012 and abs(q[5] - b[5]) < .0012]
    faces = []
    n = len(ring)
    for i in range(n):
        a_, b_ = ring[i], ring[(i + 1) % n]
        ln = math.hypot(b_[0] - a_[0], b_[1] - a_[1])
        if ln < 10:
            continue
        mid = ((a_[0] + b_[0]) / 2, (a_[1] + b_[1]) / 2)
        ux, uy = (b_[0] - a_[0]) / ln, (b_[1] - a_[1]) / ln
        nx, ny = uy, -ux
        for dd, im in R.nearest_panos(imgs, (o[0] + mid[0] / MX, o[1] + mid[1] / MY), o, rmin=10, rmax=90, limit=40):
            lg, lt = im['computed_geometry']['coordinates']
            cx, cy = (lg - o[0]) * MX, (lt - o[1]) * MY
            vx, vy = cx - mid[0], cy - mid[1]
            D = math.hypot(vx, vy)
            if (vx * nx + vy * ny) / D < .6 or any(q.intersects(LineString([(mid[0] + nx * .6, mid[1] + ny * .6), (cx, cy)])) for q in others):
                continue
            faces.append((ln, i, im))
            break
    faces.sort(key=lambda t: -t[0])
    ims = []
    for ln, i, im in faces[:2]:
        pano, meta = R.fetch(im['id'])
        arr, dist, ang = R.rectify(pano, meta, ring[i], ring[(i + 1) % n], min(b[1], 45), o, ppm=7, max_px=420)
        ims.append(Image.fromarray(arr))
    return ims


def sheet(name, out, ref):
    W, H = 360, 260
    S = Image.new('RGB', (W * 4, H * 2 + (210 if ref else 0) + 34), (16, 19, 34))
    d = ImageDraw.Draw(S)
    try:
        f = ImageFont.truetype('C:/Windows/Fonts/segoeuib.ttf', 15)
    except Exception:
        f = ImageFont.load_default()
    for k in range(8):
        im = Image.open(os.path.join(out, '%02d.png' % k)).convert('RGB').resize((W, H), Image.LANCZOS)
        S.paste(im, ((k % 4) * W, 34 + (k // 4) * H))
        d.text(((k % 4) * W + 8, 34 + (k // 4) * H + 6), '%s, %s' % (VIEWS[k % 4][1], 'night' if k >= 4 else 'day'), fill=(30, 30, 40) if k < 4 else (200, 205, 235), font=f)
    d.text((10, 8), name, fill=(240, 240, 250), font=f)
    if ref:
        x = 0
        d.text((10, 34 + H * 2 + 4), 'what the street sees (Mapillary, unwrapped)', fill=(160, 166, 200), font=f)
        for im in ref:
            h = 180
            im = im.resize((int(im.width * h / im.height), h))
            S.paste(im, (x + 8, 34 + H * 2 + 26))
            x += im.width + 12
    p = os.path.join(out, 'sheet.jpg')
    S.save(p, quality=88)
    return p


def run(name, rebuild=False):
    out = os.path.join(BENCH, 'out', slug_of(name))
    os.makedirs(out, exist_ok=True)
    if rebuild:
        t = time.time()
        subprocess.run([sys.executable, os.path.join(HERE, 'make_city.py'), '--only', 'models'], check=True, stdout=subprocess.DEVNULL)
        print('rebuilt the models in %.0f s' % (time.time() - t))
    srv, port = serve()
    try:
        shoot(name, port, out)
    finally:
        srv.shutdown()
    print('sheet:', sheet(name, out, reference(name)))


def main():
    a = [x for x in sys.argv[1:] if not x.startswith('--')]
    if not a:
        raise SystemExit(__doc__)
    name = a[0]
    if '--watch' in sys.argv:
        f = os.path.join(LM, 'sheets', slug_of(name) + '.json')
        last = 0
        while True:
            m = os.path.getmtime(f) if os.path.exists(f) else 0
            if m != last:
                last = m
                run(name, True)
            time.sleep(1.5)
    run(name, '--rebuild' in sys.argv)


main()
