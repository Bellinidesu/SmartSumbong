#!/usr/bin/env python3
"""
The reference finder: Google's own image search (the Programmable Search widget, so no scraping and no API quota), on a page of ours, with a + on every picture.
Press + and the picture goes to the board of the landmark named at the top: saved here on this computer (never committed, never shipped), credited to the page it
came from, and from then on it leads that landmark's reference board and feeds the colour suggestions.

    python docs/map-data/tools/finder.py            serves http://127.0.0.1:8765 and opens it in Brave (or Chrome)
    engine.py finder                                the same

Needs GOOGLE_CSE_CX in .env (the Search engine ID of a Programmable Search Engine with image search on).
"""
import http.server, json, os, re, subprocess, sys, threading, time, urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import common as K
import refsearch

PORT = int(os.environ.get('FINDER_PORT', 8765))


def names():
    b, info = K.buildings()
    seen, out = set(), []
    sheets = {os.path.splitext(f)[0] for f in os.listdir(os.path.join(K.LM, 'sheets')) if f.endswith('.json')}
    for k, (nm, cls) in info.items():
        if nm and nm not in seen:
            seen.add(nm)
            bb = b[int(k)]
            out.append((-(bb[6] * bb[7] + (1e6 if re.sub(r'[^a-z0-9]+', '-', nm.lower()).strip('-') in sheets else 0)), nm))
    out.sort()
    return [n for _, n in out[:600]]


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body, ctype='application/json'):
        b = body if isinstance(body, bytes) else body.encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', ctype + '; charset=utf-8')
        self.send_header('Content-Length', str(len(b)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        p = urllib.parse.urlparse(self.path).path
        if p == '/':
            html = open(os.path.join(HERE, 'finder', 'finder.html'), encoding='utf-8').read().replace('__CX__', K.env('GOOGLE_CSE_CX', ''))
            return self.send(200, html, 'text/html')
        if p == '/names':
            return self.send(200, json.dumps(names()))
        self.send(404, '{}')

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        if path == '/upload':
            try:
                import base64
                d = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))).decode('utf-8'))
                refsearch.add_bytes(d['name'].strip(), base64.b64decode(d['data'].split(',')[-1]), 'a picture you pasted', d.get('credit') or 'screenshot')
                return self.send(200, json.dumps({'ok': True}))
            except Exception as e:
                return self.send(400, json.dumps({'error': str(e)[:120]}))
        if path != '/add':
            return self.send(404, '{}')
        try:
            d = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))).decode('utf-8'))
            name, url, thumb, credit = d['name'].strip(), d.get('url') or '', d.get('thumb') or '', d.get('credit') or 'Google Images'
            if not name:
                raise ValueError('no landmark name')
            try:
                refsearch.add(name, url, credit)            # the picture itself; a site that refuses is answered with the thumbnail Google shows
            except Exception:
                if not thumb:
                    raise
                refsearch.add(name, thumb, credit + ' (thumbnail)')
            self.send(200, json.dumps({'ok': True}))
        except Exception as e:
            self.send(400, json.dumps({'error': str(e)[:120]}))


def main():
    if not K.env('GOOGLE_CSE_CX'):
        raise SystemExit('GOOGLE_CSE_CX is not in .env')
    srv = http.server.ThreadingHTTPServer(('127.0.0.1', PORT), H)
    url = 'http://127.0.0.1:%d/' % PORT
    print('reference finder on', url, '(Ctrl+C to stop)')
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
