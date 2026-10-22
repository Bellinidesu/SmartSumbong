"""Can an open-source OCR read Philippine ID cards well enough for SmartSumbong's ID checks (0126)?

Draws invented ID cards (made-up names and numbers, no real person, no real card image) in the four layouts the app
recognises, roughs each up like a phone photo (tilt, perspective, blur, JPEG, glare, dim light), reads it with
Tesseract (Apache-2.0) and scores what the app needs: the card's type, the name on it, and the ID number.

    py -3.12 bench.py --tessdata DIR [--n 15] [--save]
Needs tesseract on PATH, its eng (and fil) data in DIR, and Pillow + pytesseract (requirements.txt)."""
import argparse, io, os, random, re
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageFont
import pytesseract

SURN = ['DELA CRUZ', 'SANTOS', 'REYES', 'GARCIA', 'MENDOZA', 'BAUTISTA', 'AQUINO', 'VILLANUEVA', 'CASTILLO', 'RAMOS', 'NAVARRO', 'TORRES']
GIVEN = ['MARIA CLARA', 'JUAN PAOLO', 'ANA LIZA', 'JOSE MARI', 'KRISTINE JOY', 'MARK ANTHONY', 'ROSALIE', 'JOHN CARLO', 'MA. TERESA', 'RICHARD']
MID = ['LOPEZ', 'CRUZ', 'DIAZ', 'FLORES', 'GOMEZ', 'PEREZ', 'TAN', 'LIM']

def font(size, bold=False):
    for f in (['arialbd.ttf', 'Arial Bold.ttf'] if bold else ['arial.ttf', 'Arial.ttf']):
        try:
            return ImageFont.truetype('C:/Windows/Fonts/' + f, size)
        except OSError:
            continue
    return ImageFont.load_default()

def card(kind, rnd):
    """One invented card: the image, and what it says."""
    s, g, m = rnd.choice(SURN), rnd.choice(GIVEN), rnd.choice(MID)
    W, H = 1012, 638                                         # CR80 card at 300 dpi
    bg = {'philsys': (236, 242, 250), 'drivers_license': (240, 247, 236), 'postal_id': (250, 244, 232), 'barangay_id': (246, 240, 250)}[kind]
    im = Image.new('RGB', (W, H), bg)
    d = ImageDraw.Draw(im)
    d.rectangle([28, 150, 268, 470], fill=(200, 205, 215))  # where the photo goes (a grey box, no face)
    T = lambda xy, t, sz, b=False, c=(20, 25, 45): d.text(xy, t, font=font(sz, b), fill=c)
    if kind == 'philsys':
        num = '-'.join(str(rnd.randint(1000, 9999)) for _ in range(4))
        T((300, 26), 'REPUBLIKA NG PILIPINAS', 26, True); T((300, 58), 'Republic of the Philippines', 20)
        T((300, 86), 'PAMBANSANG PAGKAKAKILANLAN', 30, True); T((300, 120), 'Philippine Identification Card', 20)
        T((300, 170), num, 34, True)
        T((300, 230), 'Apelyido / Last Name', 16, c=(90, 95, 110)); T((300, 250), s, 30, True)
        T((300, 300), 'Mga Pangalan / Given Names', 16, c=(90, 95, 110)); T((300, 320), g, 30, True)
        T((300, 370), 'Gitnang Apelyido / Middle Name', 16, c=(90, 95, 110)); T((300, 390), m, 30, True)
        T((300, 440), 'Petsa ng Kapanganakan / Date of Birth', 16, c=(90, 95, 110)); T((300, 460), 'JANUARY 15, 1990', 26, True)
    elif kind == 'drivers_license':
        num = rnd.choice('ABCDEFGHJKLMN') + '%02d-%02d-%06d' % (rnd.randint(1, 99), rnd.randint(1, 99), rnd.randint(1, 999999))
        T((300, 26), 'REPUBLIC OF THE PHILIPPINES', 24, True); T((300, 56), 'DEPARTMENT OF TRANSPORTATION', 22, True)
        T((300, 84), 'LAND TRANSPORTATION OFFICE', 26, True); T((300, 116), "DRIVER'S LICENSE", 26, True)
        T((300, 170), 'Last Name, First Name, Middle Name', 16, c=(90, 95, 110)); T((300, 192), f'{s}, {g} {m}', 28, True)
        T((300, 250), 'License No.', 16, c=(90, 95, 110)); T((300, 270), num, 32, True)
        T((300, 330), 'Expiration Date', 16, c=(90, 95, 110)); T((300, 350), '2030/01/15', 26, True)
    elif kind == 'postal_id':
        num = 'PRN ' + ''.join(str(rnd.randint(0, 9)) for _ in range(12))
        T((300, 26), 'PHILIPPINE POSTAL CORPORATION', 26, True); T((300, 62), 'POSTAL IDENTITY CARD', 30, True)
        T((300, 120), num, 30, True)
        T((300, 180), 'Given Name(s)', 16, c=(90, 95, 110)); T((300, 200), g, 30, True)
        T((300, 250), 'Surname', 16, c=(90, 95, 110)); T((300, 270), s, 30, True)
        T((300, 320), 'Middle Name', 16, c=(90, 95, 110)); T((300, 340), m, 30, True)
    else:
        num = 'B183-%04d-%05d' % (rnd.randint(2020, 2026), rnd.randint(1, 99999))
        T((300, 26), 'REPUBLIKA NG PILIPINAS', 24, True); T((300, 56), 'LUNGSOD NG PASAY', 22, True)
        T((300, 84), 'BARANGAY 183, ZONE 20', 26, True); T((300, 118), 'BARANGAY ID', 30, True)
        T((300, 180), 'Name', 16, c=(90, 95, 110)); T((300, 200), f'{g} {m[0]}. {s}', 30, True)
        T((300, 260), 'ID No.', 16, c=(90, 95, 110)); T((300, 280), num, 30, True)
    return im, {'kind': kind, 'surname': s, 'given': g, 'number': num}

def photo(im, rnd, level):
    """The card as a phone would see it: on a table, tilted, a little out of focus, compressed, unevenly lit."""
    W, H = im.size
    if level == 0:
        return im
    table = Image.new('RGB', (int(W * 1.25), int(H * 1.35)), (rnd.randint(90, 160),) * 3)
    table.paste(im, ((table.width - W) // 2, (table.height - H) // 2))
    im = table.rotate(rnd.uniform(-4, 4) * level, resample=Image.BICUBIC, expand=False, fillcolor=(120, 120, 120))
    w, h = im.size; k = 0.035 * level
    quad = [rnd.uniform(0, k) * w, rnd.uniform(0, k) * h, rnd.uniform(0, k) * w, h - rnd.uniform(0, k) * h,
            w - rnd.uniform(0, k) * w, h - rnd.uniform(0, k) * h, w - rnd.uniform(0, k) * w, rnd.uniform(0, k) * h]
    im = im.transform((w, h), Image.QUAD, quad, resample=Image.BICUBIC)
    im = im.resize((int(w * (0.9 - 0.12 * level)), int(h * (0.9 - 0.12 * level))), Image.BILINEAR)
    im = im.filter(ImageFilter.GaussianBlur(0.5 + 0.55 * level))
    im = ImageEnhance.Brightness(im).enhance(rnd.uniform(1 - 0.18 * level, 1.05))
    glare = Image.new('L', im.size, 0); gd = ImageDraw.Draw(glare)
    cx, cy, r = rnd.randint(0, im.width), rnd.randint(0, im.height), int(im.width * 0.25)
    gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=int(70 * level)); glare = glare.filter(ImageFilter.GaussianBlur(r // 2))
    im = Image.composite(Image.new('RGB', im.size, (255, 255, 255)), im, glare)
    b = io.BytesIO(); im.save(b, 'JPEG', quality=int(85 - 15 * level)); b.seek(0)
    return Image.open(b).convert('RGB')

KIND_WORDS = {'philsys': ['PAMBANSANG PAGKAKAKILANLAN', 'PHILIPPINE IDENTIFICATION CARD'],
              'drivers_license': ['LAND TRANSPORTATION OFFICE', "DRIVER'S LICENSE", 'DRIVERS LICENSE'],
              'postal_id': ['POSTAL ID', 'PHLPOST', 'PHILIPPINE POSTAL'],
              'barangay_id': ['BARANGAY ID', 'BARANGAY IDENTIFICATION']}

def norm(t): return re.sub(r'[^A-Z0-9]', '', t.upper())

def score(text, truth):
    up = text.upper()
    kind = next((k for k, ws in KIND_WORDS.items() if any(w in up for w in ws)), None)
    flat = norm(text)
    name_ok = norm(truth['surname']) in flat and norm(truth['given'].split()[0]) in flat
    digits = re.sub(r'[^0-9A-Z]', '', truth['number'].upper())
    num_ok = digits in flat or digits[-10:] in flat
    return kind == truth['kind'], name_ok, num_ok

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--tessdata', required=True); ap.add_argument('--n', type=int, default=15); ap.add_argument('--save')
    ap.add_argument('--lang', default='eng')
    a = ap.parse_args()
    os.environ['TESSDATA_PREFIX'] = a.tessdata
    cfg = '--psm 6'
    rnd = random.Random(183)
    print(f'Tesseract {pytesseract.get_tesseract_version()}  lang {a.lang}  ({a.n} invented cards per type per level)')
    for level, label in ((0, 'clean scan'), (1, 'good phone photo'), (2, 'poor phone photo')):
        tot = {'type': 0, 'name': 0, 'number': 0, 'all': 0}; n = 0
        for kind in KIND_WORDS:
            for i in range(a.n):
                im, truth = card(kind, rnd)
                ph = photo(im, rnd, level)
                if a.save and i == 0: ph.save(f'{a.save}/{kind}-{level}.jpg')
                t = pytesseract.image_to_string(ph.convert('L'), lang=a.lang, config=cfg)
                k, nm, nu = score(t, truth)
                tot['type'] += k; tot['name'] += nm; tot['number'] += nu; tot['all'] += (k and nm and nu); n += 1
        print(f'  {label:17s} type {tot["type"]:3d}/{n}  name {tot["name"]:3d}/{n}  number {tot["number"]:3d}/{n}  all three {tot["all"]:3d}/{n}')

if __name__ == '__main__':
    main()
