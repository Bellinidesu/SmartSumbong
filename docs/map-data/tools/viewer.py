#!/usr/bin/env python3
"""
The landmark viewer: an interactive 3D view of every landmark model, to look at, scrutinise against the references, and pass or send back.

    python docs/map-data/tools/viewer.py           serves http://127.0.0.1:8770 and opens it (Brave or Chrome)

In the page: pick a landmark on the left; drag to turn it, wheel to zoom, right-drag (or Shift-drag) to move; Day / Night; the real footprint outline and a metre grid; the plain
buildings of the open data round it (so it is judged in its place); the references beside it (street views, photographs, your own screenshots: click one to enlarge, arrows to
step). Approve or Send back (with a note): approvals are kept in landmarks/approvals.json and stamped into the built models, and the map draws a sheet model only when it is approved
(?models=1; ?models=all shows the drafts too). Rebuild runs models.py; Bake light runs the light and wash steps (a changed model shows flat light until it is baked).

Keys: N night, F footprint, G grid, C context, R auto-turn, 1 to 4 front / side / back / top, A approve, X send back, [ and ] previous / next landmark.
"""
import http.server, json, os, re, subprocess, sys, threading, time, urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'landmarks'))
import common as K

PORT = int(os.environ.get('VIEWER_PORT', 8770))
APPROVALS = os.path.join(K.LM, 'approvals.json')
META = os.path.join(K.MAPDIR, 'landmarks3d.json')
JOB = {'running': False, 'name': '', 'log': '', 'rc': None, 'at': 0}


def slug(n):
    return re.sub(r'[^a-z0-9]+', '-', (n or '').lower()).strip('-')


def load_approvals():
    try:
        return json.load(open(APPROVALS, encoding='utf-8'))
    except Exception:
        return {}


def models():
    meta = json.load(open(META, encoding='utf-8'))
    ap = load_approvals()
    out = []
    for m in meta['models']:
        if m.get('furniture'):
            continue
        a = ap.get(m['name']) or {}
        out.append(dict(name=m['name'], template=m['template'], sheet=bool(m.get('sheet')), height=m.get('height'), verts=m['v'], tris=m['i'] // 3, replaces=m['replaces'],
                        status=a.get('status') or ('approved' if not m.get('sheet') else 'pending'), note=a.get('note', ''), at=a.get('at', '')))
    out.sort(key=lambda r: (not r['sheet'], r['status'] == 'approved', r['name']))
    return out


def set_status(name, status, note):
    ap = load_approvals()
    ap[name] = dict(status=status, note=note, at=time.strftime('%Y-%m-%d %H:%M'))
    json.dump(ap, open(APPROVALS, 'w', encoding='utf-8'), indent=1, ensure_ascii=False)
    meta = json.load(open(META, encoding='utf-8'))          # the built models carry it: no rebuild is needed for the map to follow
    for m in meta['models']:
        if m['name'] == name and m.get('sheet'):
            m['approved'] = status == 'approved'
    json.dump(meta, open(META, 'w', encoding='utf-8'), separators=(',', ':'))


def context(name, radius=150.0):
    """The plain buildings of the open data round a landmark, extruded, in the model's own frame, and the outline of its real footprint."""
    from meshlib import Mesh
    import numpy as np
    meta = json.load(open(META, encoding='utf-8'))
    md = next((m for m in meta['models'] if m['name'] == name), None)
    if not md:
        return {}
    b, info = K.buildings()
    lng0, lat0 = md['lng'], md['lat']
    loc = lambda q: [((q[0][i] - lng0) * K.MX, (q[0][i + 1] - lat0) * K.MY) for i in range(0, len(q[0]), 2)]
    foot = loc(b[md['replaces']]) if 0 <= md['replaces'] < len(b) else []
    m = Mesh()
    n = 0
    for i, q in enumerate(b):
        if i == md['replaces']:
            continue
        x, y = (q[4] - lng0) * K.MX, (q[5] - lat0) * K.MY
        if abs(x) > radius or abs(y) > radius:
            continue
        ring = loc(q)
        if len(ring) < 3:
            continue
        try:
            m.prism(ring, 0, float(q[1]), 'plain', (214, 210, 202), 'plain', (226, 223, 216), top=True, cell=40)
            n += 1
        except Exception:
            continue
    P, N, U, M_, C, Ix = m.arrays()
    return dict(footprint=foot, buildings=n, p=[round(float(v), 2) for v in np.asarray(P).ravel()], n=[round(float(v), 2) for v in np.asarray(N).ravel()], i=[int(v) for v in np.asarray(Ix).ravel()])


def refs(name):
    out = []
    d = os.path.join(K.CACHE, 'inbox', slug(name))
    if os.path.isdir(d):
        meta = json.load(open(os.path.join(d, 'meta.json'))) if os.path.exists(os.path.join(d, 'meta.json')) else {}
        for f in sorted(os.listdir(d)):
            if f.lower().endswith(('.jpg', '.jpeg', '.png', '.webp')):
                out.append(dict(url='/ref/inbox/%s/%s' % (slug(name), f), src='yours', title=f, credit=(meta.get(f) or {}).get('credit', '')))
    try:
        import hashlib
        db = json.load(open(os.path.join(K.LM, 'refs-index.json'), encoding='utf-8')).get(name, [])
        for e in sorted(db, key=lambda e: -e.get('score', 0)):
            f = os.path.join(K.REFS, '%s_%s.jpg' % (e['src'], hashlib.md5(e['id'].encode()).hexdigest()[:12]))
            if os.path.exists(f):
                out.append(dict(url='/ref/refs/' + os.path.basename(f), src=e['src'], title=e.get('title', ''), credit='%s, %s' % (e.get('author', ''), e.get('license', ''))))
    except Exception:
        pass
    return out


def run_job(label, args, env=None):
    if JOB['running']:
        return False
    JOB.update(running=True, name=label, log='', rc=None, at=time.time())

    def go():
        try:
            p = subprocess.Popen([sys.executable, os.path.join(HERE, 'make_city.py')] + args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace', env=dict(os.environ, PYTHONIOENCODING='utf-8', **(env or {})))
            for line in p.stdout:
                JOB['log'] = (JOB['log'] + line)[-4000:]
            JOB['rc'] = p.wait()
        except Exception as e:
            JOB['log'] += str(e)
            JOB['rc'] = 1
        JOB['running'] = False
    threading.Thread(target=go, daemon=True).start()
    return True


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body, ctype='application/json', extra=None):
        b = body if isinstance(body, bytes) else body.encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', ctype if 'charset' in ctype or ctype.startswith('image') else ctype + '; charset=utf-8')
        self.send_header('Content-Length', str(len(b)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(b)

    def file(self, path):
        if not os.path.isfile(path):
            return self.send(404, '{}')
        ext = os.path.splitext(path)[1].lower()
        ct = {'.js': 'text/javascript', '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.gz': 'application/gzip', '.html': 'text/html', '.css': 'text/css'}.get(ext, 'application/octet-stream')
        self.send(200, open(path, 'rb').read(), ct)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        p, q = u.path, urllib.parse.parse_qs(u.query)
        try:
            if p in ('/', '/viewer.html'):
                return self.file(os.path.join(HERE, 'viewer', 'viewer.html'))
            if p == '/api/models':
                return self.send(200, json.dumps(models()))
            if p == '/api/context':
                return self.send(200, json.dumps(context(q['name'][0], float(q.get('r', [150])[0]))))
            if p == '/api/refs':
                return self.send(200, json.dumps(refs(q['name'][0])))
            if p == '/api/job':
                return self.send(200, json.dumps(dict(JOB, secs=int(time.time() - JOB['at']) if JOB['at'] else 0)))
            if p.startswith('/ref/inbox/'):
                parts = p[len('/ref/inbox/'):].split('/')
                return self.file(os.path.join(K.CACHE, 'inbox', os.path.basename(parts[0]), os.path.basename(parts[1])))
            if p.startswith('/ref/refs/'):
                return self.file(os.path.join(K.REFS, os.path.basename(p)))
            return self.file(os.path.join(K.ADMIN, p.lstrip('/').replace('/', os.sep)))
        except Exception as e:
            return self.send(500, json.dumps({'error': str(e)[:200]}))

    def do_POST(self):
        p = urllib.parse.urlparse(self.path).path
        try:
            d = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))).decode('utf-8') or '{}')
            if p == '/api/approve':
                set_status(d['name'], d['status'], d.get('note', ''))
                return self.send(200, json.dumps({'ok': True}))
            if p == '/api/rebuild':
                return self.send(200, json.dumps({'started': run_job('rebuild the models', ['--only', 'models'])}))
            if p == '/api/light':
                return self.send(200, json.dumps({'started': run_job('bake the light and the washes', ['--only', 'light,wash'])}))
            return self.send(404, '{}')
        except Exception as e:
            return self.send(400, json.dumps({'error': str(e)[:200]}))


def main():
    srv = http.server.ThreadingHTTPServer(('127.0.0.1', PORT), H)
    url = 'http://127.0.0.1:%d/' % PORT
    print('landmark viewer on', url, '(Ctrl+C to stop)')
    if '--no-open' not in sys.argv:
        for exe in ('C:/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe', 'C:/Program Files/Google/Chrome/Application/chrome.exe'):
            if os.path.exists(exe):
                subprocess.Popen([exe, url])
                break
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
