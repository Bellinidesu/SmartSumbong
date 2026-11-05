#!/usr/bin/env python3
"""
The measuring board: the unwrapped street-view faces of a landmark at a known scale (10 pixels a metre), with a ruler: a line every floor (3.4 m, a heavier one every
5th) and a tick every metre along the wall, numbered every 5 m, and the colours of the picture as swatches. For reading a facade by eye with numbers on it: how wide is
a bay, how tall a floor, where the window sits in it, how deep the podium is, what the real colours are.

    python docs/map-data/tools/measure.py "Horizon Centre"            writes tools/mly-cache/measure_<slug>.jpg (every face it can read)
    python docs/map-data/tools/measure.py "Horizon Centre" --floor 3.8
"""
import os, re, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as K
import faces
import suggest


def board(name, floor_h=3.4, max_faces=3):
    fs = faces.rectified_faces(name, max_faces, ppm=10.0, max_px=620)
    if not fs:
        return None
    try:
        f = ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf', 12)
    except Exception:
        f = ImageFont.load_default()
    tiles = []
    for ln, i, im, pid, h, ppm in fs:
        im = im.convert('RGB')
        sc = 10.0 / ppm
        im = im.resize((int(im.width * sc), int(im.height * sc)), Image.LANCZOS)
        W, Hh = im.size
        pad = 34
        t = Image.new('RGB', (W + pad, Hh + pad + 52), (16, 19, 34))
        t.paste(im, (pad, 18))
        d = ImageDraw.Draw(t)
        # floors (from the ground)
        k = 0
        while True:
            y = 18 + Hh - k * floor_h * 10
            if y < 18:
                break
            d.line([(pad, y), (pad + W, y)], fill=(255, 154, 46) if k % 5 == 0 else (255, 154, 46, 90), width=2 if k % 5 == 0 else 1)
            d.text((2, y - 7), '%d' % k, fill=(255, 190, 110), font=f)
            k += 1
        # metres along the wall
        for m in range(0, int(W / 10) + 1):
            x = pad + m * 10
            d.line([(x, 18 + Hh), (x, 18 + Hh + (10 if m % 5 == 0 else 5))], fill=(220, 224, 245), width=1)
            if m % 5 == 0:
                d.text((x - 6, 18 + Hh + 11), '%d' % m, fill=(220, 224, 245), font=f)
        d.text((pad, 2), '%s, face %d, %.0f m long, wall 0 to %.0f m high (orange = floors of %.1f m)' % (name, i, ln, h, floor_h), fill=(200, 205, 235), font=f)
        # the colours of the picture
        pal = suggest.palette(im)
        x = pad
        for c, s in pal[:6]:
            d.rectangle([x, Hh + 18 + 30, x + 40, Hh + 18 + 48], fill=c)
            d.text((x, Hh + 18 + 49 - 14), '%d%%' % round(s * 100), fill=(0, 0, 0) if sum(c) > 380 else (255, 255, 255), font=f)
            x += 44
        tiles.append(t)
    Wt = sum(t.width for t in tiles) + 8 * len(tiles)
    S = Image.new('RGB', (Wt, max(t.height for t in tiles)), (16, 19, 34))
    x = 0
    for t in tiles:
        S.paste(t, (x, 0))
        x += t.width + 8
    p = os.path.join(K.CACHE, 'measure_%s.jpg' % re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-'))
    S.save(p, quality=90)
    return p


if __name__ == '__main__':
    a = sys.argv[1:]
    name = next((x for x in a if not x.startswith('--')), None)
    if not name:
        raise SystemExit(__doc__)
    fl = float(a[a.index('--floor') + 1]) if '--floor' in a else 3.4
    print(board(name, fl))
