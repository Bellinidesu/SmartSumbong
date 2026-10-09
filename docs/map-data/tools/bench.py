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
        import faces
        return [im for ln, i, im, pid, h, ppm in faces.rectified_faces(name, 2)]
    except Exception as e:
        print('  (no street-view reference: %s)' % e)
        return []


def refs_row(name, n=5):
    """The best references the last search found for this landmark (thumbnails from the cache), and the palette of the real walls beside the model's."""
    sys.path.insert(0, HERE)
    ims, chips = [], None
    try:
        import json as _j
        import hashlib, refsearch, common as K
        db = _j.load(open(refsearch.INDEX, encoding='utf-8')) if os.path.exists(refsearch.INDEX) else {}
        es = sorted(db.get(name, []), key=lambda e: (not e.get('picked'), -e.get('score', 0)))[:n]
        for e in es:
            p = os.path.join(K.REFS, '%s_%s.jpg' % (e['src'], hashlib.md5(e['id'].encode()).hexdigest()[:12]))
            if os.path.exists(p):
                ims.append((Image.open(p).convert('RGB'), e))
    except Exception as e:
        print('  (no reference row: %s)' % e)
    try:
        import suggest, engine
        sg = suggest.analyse(name, 2)
        ours = engine.wall_colour(name)
        real = tuple(int(sg['wall'].lstrip('#')[i:i + 2], 16) for i in (0, 2, 4)) if sg.get('wall') else None
        chips = dict(real=[tuple(int(c.lstrip('#')[i:i + 2], 16) for i in (0, 2, 4)) for c, w in sg.get('palette', [])], ours=ours, de=engine.delta_e(real, ours) if real and ours else None)
    except BaseException as e:
        print('  (no palette comparison: %s)' % str(e)[:60])
    return ims, chips


def sheet(name, out, ref, rrow=None, chips=None):
    W, H = 360, 260
    extra = (210 if ref else 0) + (215 if rrow else 0) + (44 if chips else 0)
    S = Image.new('RGB', (W * 4, H * 2 + extra + 34), (16, 19, 34))
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
    y = 34 + H * 2 + (210 if ref else 0)
    if rrow:
        d.text((10, y + 4), 'references found (refsearch.py): source, licence, author', fill=(160, 166, 200), font=f)
        x = 8
        for im, e in rrow:
            t = im.copy()
            t.thumbnail((270, 150))
            S.paste(t, (x, y + 26))
            d.text((x, y + 26 + 152), '%s | %s' % (e['src'], (e.get('license') or '?')[:18]), fill=(200, 205, 235), font=f)
            x += 276
        y += 215
    if chips:
        d.text((10, y + 4), 'real walls', fill=(160, 166, 200), font=f)
        x = 100
        for c in chips['real'][:6]:
            d.rectangle([x, y + 4, x + 30, y + 26], fill=tuple(c))
            x += 34
        if chips.get('ours'):
            d.text((x + 24, y + 4), 'model wall', fill=(160, 166, 200), font=f)
            d.rectangle([x + 112, y + 4, x + 146, y + 26], fill=tuple(chips['ours']))
            if chips.get('de') is not None:
                d.text((x + 160, y + 4), 'colour distance dE %.0f (%s)' % (chips['de'], 'close' if chips['de'] < 12 else 'near' if chips['de'] < 24 else 'far'), fill=(240, 240, 250), font=f)
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
    rrow, chips = refs_row(name)
    print('sheet:', sheet(name, out, reference(name), rrow, chips))


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
