#!/usr/bin/env python3
"""
The reference match: look at a model from where each photograph was taken, and put the two side by side (and blended), so that what is wrong shows at once.

    python docs/map-data/tools/match.py shrine                     renders from every camera in landmarks/refcams/shrine.json, writes tools/match-out/shrine/pairs.jpg and one pair a shot
    python docs/map-data/tools/match.py shrine 1 4 10              only those shots
    python docs/map-data/tools/match.py shrine --build             rebuild the Blender model first (blend/build_<name>.py)

A camera file lists, for each photograph: its file in the landmark's reference inbox, where it was taken (lat, lng), the way it looked (heading, tilt) and its field of view, read off the address
bar of the screenshot. The photographs are only looked at (private reference, never shipped); nothing is read from their pixels except by eye.
"""
import json, math, os, subprocess, sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import common as K

BLENDER = next((p for p in ('C:/Program Files/Blender Foundation/Blender 4.5/blender.exe', 'C:/Program Files/Blender Foundation/Blender 4.2/blender.exe') if os.path.exists(p)), 'blender')
BL = os.path.join(K.LM, 'blend')
OUT = os.path.join(HERE, 'match-out')


def neighbours(anchor, skip_near=30.0, radius=260.0):
    b, info = K.buildings()
    out = []
    for q in b:
        x, y = (q[4] - anchor[0]) * K.MX, (q[5] - anchor[1]) * K.MY
        if math.hypot(x, y) > radius or math.hypot(x, y) < 1.0 and False:
            continue
        ring = [((q[0][i] - anchor[0]) * K.MX, (q[0][i + 1] - anchor[1]) * K.MY) for i in range(0, len(q[0]), 2)]
        if abs(x) < skip_near and abs(y) < skip_near:
            continue                      # the landmark's own footprint
        out.append(dict(ring=ring, h=float(q[1])))
    return out


def main():
    a = [x for x in sys.argv[1:] if not x.startswith('--')]
    if not a:
        raise SystemExit(__doc__)
    name = a[0]
    only = {int(x) for x in a[1:]}
    camf = os.path.join(K.LM, 'refcams', name + '.json')
    cams = json.load(open(camf, encoding='utf-8'))
    if '--build' in sys.argv:
        subprocess.run([BLENDER, '--background', '--python', os.path.join(BL, 'build_%s.py' % name), '--', os.path.join(BL, 'work', name + '.npz'), os.path.join(BL, 'work', name + '.blend')], check=True, stdout=subprocess.DEVNULL)
    blend = os.path.join(BL, 'work', name + '.blend')
    out = os.path.join(OUT, name)
    os.makedirs(out, exist_ok=True)
    nbf = os.path.join(out, 'neighbours.json')
    json.dump(neighbours(cams['anchor']), open(nbf, 'w'))
    if only:
        cams = dict(cams, cams=[c for c in cams['cams'] if c['n'] in only])
        camf = os.path.join(out, 'cams_subset.json')
        json.dump(cams, open(camf, 'w', encoding='utf-8'))
    subprocess.run([BLENDER, '--background', blend, '--python', os.path.join(BL, 'match_render.py'), '--', camf, nbf, os.path.join(out, 'render')], check=True, stdout=subprocess.DEVNULL)
    inbox = os.path.join(K.CACHE, 'inbox', K.slug(cams['landmark']) if hasattr(K, 'slug') else __import__('re').sub(r'[^a-z0-9]+', '-', cams['landmark'].lower()).strip('-'))
    try:
        f = ImageFont.truetype('C:/Windows/Fonts/segoeuib.ttf', 20)
    except Exception:
        f = ImageFont.load_default()
    pairs = []
    for c in cams['cams']:
        ref = Image.open(os.path.join(inbox, c['file'])).convert('RGB')
        W, H = ref.size
        ref = ref.crop((int(W * .21), int(H * .105), W, int(H * .88)))          # the street-view pane of the screenshot
        ren = Image.open(os.path.join(out, 'render', '%02d.png' % c['n'])).convert('RGB')
        w = 640
        ref = ref.resize((w, int(w * ref.height / ref.width)))
        ren = ren.resize((w, ref.height))
        bl = Image.blend(ref, ren, .5)
        pair = Image.new('RGB', (w * 3, ref.height))
        pair.paste(ref, (0, 0)); pair.paste(ren, (w, 0)); pair.paste(bl, (2 * w, 0))
        d = ImageDraw.Draw(pair)
        d.rectangle([0, 0, 330, 30], fill=(15, 18, 36))
        d.text((8, 4), 'shot %d  heading %.0f  tilt %.0f  fov %.0f' % (c['n'], c['heading'], c['tilt'], c['fov']), fill=(255, 190, 110), font=f)
        pair.save(os.path.join(out, 'pair_%02d.jpg' % c['n']), quality=88)
        pairs.append(pair)
    for k in range(0, len(pairs), 4):
        chunk = pairs[k:k + 4]
        S = Image.new('RGB', (chunk[0].width, sum(p.height for p in chunk)))
        y = 0
        for p in chunk:
            S.paste(p, (0, y)); y += p.height
        S.save(os.path.join(out, 'pairs_%d.jpg' % (k // 4 + 1)), quality=86)
    print('pairs written to', out)


main()
