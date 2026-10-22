"""SmartSumbong engine: the heavy work the database hands out (since 22 Oct 2026, Ace: the portal's features and
labs run as engine functions). One job so far:

    POST /read    {"url": "<a signed link to one ID photo>"}   ->   {"type", "name", "number", "ms"}
    GET  /health  -> {"ok": true}

The database asks (engine_tick, 0137), with the shared secret in x-engine-secret. The engine holds no database
or Cloudinary credential: it reads only the photo the database signed a link for, and only from the barangay's
own Cloudinary ID folder. It keeps nothing: the photo and the text live in memory for one request, and the log
has times and sizes, never names or numbers. PaddleOCR's PP-OCR models (Apache-2.0) through RapidOCR
(Apache-2.0) on ONNX Runtime (MIT), one photo at a time, one thread: about 220 MB at its peak.
"""
import hmac
import json
import os
import re
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from reader import read_card, top_down

SECRET = os.environ.get('ENGINE_SECRET', '')
PORT = int(os.environ.get('PORT', '8080'))
# a signed link (s--xxxxxxxx--), one transformation, an ID photo with a UUID name: nothing else is fetched
PHOTO = re.compile(r'^https://res\.cloudinary\.com/nwb2kryl/image/authenticated/s--[A-Za-z0-9_-]{8}--/'
                   r'[a-z0-9_,]+/v[0-9]+/ids/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|jpeg|png|webp)$')
MAX_PHOTO = 8 * 1024 * 1024

_ocr = None
_one_at_a_time = threading.Lock()


def ocr():
    global _ocr
    if _ocr is None:
        from rapidocr import RapidOCR
        # Measured (22 Oct 2026): RapidOCR's defaults enlarge the photo to find text and peaked at 482 MB on a
        # 1600 px photo. Shrinking instead (longest side 736 for finding text), one line at a time, on a 1024 px
        # photo: about 220 MB at peak, 80 MB idle, 0.4 s a card, and as accurate (tools/ocr_lab).
        _ocr = RapidOCR(params={'EngineConfig.onnxruntime.intra_op_num_threads': 1,
                                'EngineConfig.onnxruntime.inter_op_num_threads': 1,
                                'Det.limit_type': 'max', 'Det.limit_side_len': 736, 'Rec.rec_batch_num': 1})
    return _ocr


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


_fetch = urllib.request.build_opener(_NoRedirect)


def fetch(url):
    with _fetch.open(urllib.request.Request(url, headers={'User-Agent': 'smartsumbong-engine'}), timeout=20) as r:
        data = r.read(MAX_PHOTO + 1)
    if len(data) > MAX_PHOTO:
        raise ValueError('photo too large')
    return data


def read_photo(data):
    import cv2
    import numpy as np
    img = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError('not an image')
    with _one_at_a_time:
        out = ocr()(img)
    return read_card(top_down(out.txts, out.boxes))


class Handler(BaseHTTPRequestHandler):
    server_version = 'engine'
    sys_version = ''

    def log_message(self, fmt, *args):
        pass   # no request log: addresses would carry the signed links

    def answer(self, code, body):
        raw = json.dumps(body).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(raw)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        if self.path == '/health':
            return self.answer(200, {'ok': True})
        self.answer(404, {'error': 'not found'})

    def do_POST(self):
        if self.path != '/read':
            return self.answer(404, {'error': 'not found'})
        if not SECRET or not hmac.compare_digest(self.headers.get('x-engine-secret', ''), SECRET):
            return self.answer(403, {'error': 'forbidden'})
        try:
            n = int(self.headers.get('Content-Length') or 0)
            if n <= 0 or n > 4096:
                raise ValueError
            url = json.loads(self.rfile.read(n)).get('url', '')
        except (ValueError, AttributeError):
            return self.answer(400, {'error': 'bad request'})
        if not isinstance(url, str) or not PHOTO.match(url):
            return self.answer(400, {'error': 'not an ID photo link'})
        t0 = time.perf_counter()
        try:
            data = fetch(url)
        except Exception:
            return self.answer(502, {'error': 'photo could not be fetched'})
        try:
            card = read_photo(data)
        except ValueError:
            return self.answer(422, {'error': 'not a readable image'})
        ms = round((time.perf_counter() - t0) * 1000)
        print(f'read one ID photo: {len(data) // 1024} KB in {ms} ms', flush=True)
        self.answer(200, {**card, 'ms': ms})


if __name__ == '__main__':
    if not SECRET:
        print('ENGINE_SECRET is not set: every read is refused', flush=True)
    if os.environ.get('ENGINE_WARM', '1') == '1':
        threading.Thread(target=ocr, daemon=True).start()   # load the models before the first job
    ThreadingHTTPServer(('0.0.0.0', PORT), Handler).serve_forever()
