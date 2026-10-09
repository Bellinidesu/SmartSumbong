"""
The facade atlas of the landmark models: one picture of 4 x 4 tiles for the day (a multiplier on the albedo colour of each
surface: 1 for wall, darker for glass) and one for the night (which windows are lit, painted as light). Drawn here in the
barangay's plain style: flat colours, no photographs. Every tile repeats, so each is painted so that its edges meet.
"""
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

CELL = 128      # pixels a tile takes in the atlas
INNER = 112     # the tile itself; the rest of the cell repeats it, so a mip level never blends in a neighbour
SS = 4          # drawn this much bigger, then reduced

GLASS = (.30, .38, .50)
GLASS_LIT = (1.0, .80, .48)


def _canvas():
    return Image.new('RGB', (INNER * SS, INNER * SS), (255, 255, 255))


def _g(c, k=1.0):
    return tuple(int(max(0, min(255, round(v * k * 255)))) for v in c)


def _rect(d, x0, y0, x1, y1, fill):
    d.rectangle([x0 * SS * INNER, y0 * SS * INNER, x1 * SS * INNER, y1 * SS * INNER], fill=fill)


def tile_plain(lit=False):
    im = _canvas()
    return im if not lit else Image.new('RGB', im.size, (0, 0, 0))


def _pane(rnd, jit):
    """One pane of glass: its own brightness, and now and then a pane that holds a bright piece of sky."""
    k = 1 + jit * (rnd.random() * 2 - 1)
    if rnd.random() < .10:
        return _g((.44, .55, .70), k)
    return _g(GLASS, k)


def _reveal(d, x0, y0, x1, y1):
    """The shadow a window sits in: a pane is set back in its wall, so its top and its sunny-side edge are darker."""
    _rect(d, x0, y0, x1, y0 + (y1 - y0) * .16, _g((.18, .26, .38)))
    _rect(d, x0, y0, x0 + (x1 - x0) * .10, y1, _g((.20, .28, .40)))


def tile_windows(lit, seed=11, p=.55, jit=.10, lc=GLASS_LIT):
    """Two bays of punched windows over one storey (6.4 m x 3.4 m)."""
    im = Image.new('RGB', (INNER * SS, INNER * SS), (0, 0, 0) if lit else (255, 255, 255))
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    dr = random.Random(seed + 1000)
    for bay in range(2):
        x0, x1 = (bay * .5 + .17), (bay * .5 + .33)
        if lit:
            if rnd.random() < p:
                _rect(d, x0, .30, x1, .74, _g(lc, .70 + .3 * rnd.random()))
        else:
            _rect(d, x0 - .018, .28, x1 + .018, .76, _g((.92, .92, .92)))
            _rect(d, x0, .30, x1, .74, _pane(dr, jit))
            _reveal(d, x0, .30, x1, .74)
            _rect(d, x0 - .03, .74, x1 + .03, .79, _g((.86, .86, .86)))
            _rect(d, (x0 + x1) / 2 - .006, .30, (x0 + x1) / 2 + .006, .74, _g((.92, .92, .92)))
    return im

def tile_ribbon(lit, seed=7, p=.6, jit=.10, lc=GLASS_LIT):
    """A continuous band of glass with mullions (6 m x 3.4 m)."""
    im = Image.new('RGB', (INNER * SS, INNER * SS), (0, 0, 0) if lit else (255, 255, 255))
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    dr = random.Random(seed + 1000)
    n = 4
    for i in range(n):
        x0, x1 = i / n + .012, (i + 1) / n - .012
        if lit:
            if rnd.random() < p:
                _rect(d, x0, .30, x1, .72, _g(lc, .65 + .3 * rnd.random()))
        else:
            _rect(d, x0, .30, x1, .72, _pane(dr, jit))
    if not lit:
        _rect(d, 0, .72, 1, .76, _g((.9, .9, .9)))
        _rect(d, 0, .26, 1, .30, _g((.9, .9, .9)))
    return im

def tile_glass(lit, seed=5, p=.4, jit=.14, lc=GLASS_LIT):
    """A curtain wall (3.2 m x 3.4 m): two panes a storey, vision glass over a spandrel panel, thin mullions."""
    im = Image.new('RGB', (INNER * SS, INNER * SS), (0, 0, 0) if lit else _g((.80, .82, .86)))
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    dr = random.Random(seed + 1000)
    for i in range(2):
        x0, x1 = i / 2 + .022, (i + 1) / 2 - .022
        if lit:
            if rnd.random() < p:
                _rect(d, x0, .10, x1, .70, _g(lc, .45 + .4 * rnd.random()))
        else:
            k = 1 + jit * (dr.random() * 2 - 1)
            _rect(d, x0, .10, x1, .70, _g((.44, .58, .76) if dr.random() < .12 else (.27, .39, .53), k))
            _rect(d, x0, .72, x1, .94, _g((.46, .50, .56), 1 + .05 * (dr.random() * 2 - 1)))
    return im

def tile_sheet(lit):
    """Corrugated roof sheet (2.4 m): ribs."""
    if lit:
        return Image.new('RGB', (INNER * SS, INNER * SS), (0, 0, 0))
    im = _canvas()
    d = ImageDraw.Draw(im)
    n = 8
    for i in range(n):
        _rect(d, i / n, 0, i / n + .32 / n, 1, _g((.82, .82, .82)))
        _rect(d, i / n + .32 / n, 0, i / n + .5 / n, 1, _g((1, 1, 1)))
        _rect(d, i / n + .5 / n, 0, i / n + .72 / n, 1, _g((.93, .93, .93)))
    return im


def tile_tile(lit):
    """Roof tiles (2.4 m): rows with a shadow line each."""
    if lit:
        return Image.new('RGB', (INNER * SS, INNER * SS), (0, 0, 0))
    im = _canvas()
    d = ImageDraw.Draw(im)
    rows = 6
    for r in range(rows):
        _rect(d, 0, r / rows, 1, r / rows + .16 / rows, _g((.78, .78, .78)))
        for c in range(6):
            off = .5 / 6 if r % 2 else 0
            _rect(d, c / 6 + off, r / rows, c / 6 + off + .025, (r + 1) / rows, _g((.9, .9, .9)))
    return im


def tile_arches(lit):
    """Tall arched openings in a plain wall (7 m x 7 m): the shrine's arches, two to a tile."""
    im = Image.new('RGB', (INNER * SS, INNER * SS), (0, 0, 0) if lit else (255, 255, 255))
    d = ImageDraw.Draw(im)
    S = SS * INNER
    for k in range(2):
        cx, w = (k * .5 + .25) * S, .17 * S
        top, bottom = .22 * S, .86 * S
        arch = [cx - w, bottom, cx - w, top + w, cx + w, top + w, cx + w, bottom]
        if lit:
            d.rectangle([cx - w * .8, top + w, cx + w * .8, bottom - .05 * S], fill=_g((1.0, .72, .38), .85))
            d.pieslice([cx - w * .8, top + .12 * w, cx + w * .8, top + 1.88 * w], 180, 360, fill=_g((1.0, .72, .38), .85))
        else:
            d.rectangle([cx - w - .02 * S, top + w, cx + w + .02 * S, bottom], fill=_g((.86, .86, .86)))
            d.pieslice([cx - w - .02 * S, top - .02 * S, cx + w + .02 * S, top + 2 * w + .02 * S], 180, 360, fill=_g((.86, .86, .86)))
            d.rectangle([cx - w, top + w, cx + w, bottom - .03 * S], fill=_g((.34, .30, .30)))
            d.pieslice([cx - w, top, cx + w, top + 2 * w], 180, 360, fill=_g((.34, .30, .30)))
            d.rectangle([cx - .004 * S, top + .1 * S, cx + .004 * S, bottom - .03 * S], fill=_g((.7, .62, .55)))
    return im


def tile_louvre(lit):
    if lit:
        return Image.new('RGB', (INNER * SS, INNER * SS), (0, 0, 0))
    im = _canvas()
    d = ImageDraw.Draw(im)
    n = 10
    for i in range(n):
        _rect(d, 0, i / n, 1, i / n + .55 / n, _g((.62, .64, .68)))
        _rect(d, 0, i / n + .55 / n, 1, (i + 1) / n, _g((.92, .92, .92)))
    return im


def tile_sign(lit):
    im = Image.new('RGB', (INNER * SS, INNER * SS), (255, 255, 255) if not lit else (255, 255, 255))
    d = ImageDraw.Draw(im)
    if not lit:
        _rect(d, 0, 0, 1, .12, _g((.88, .88, .88)))
        _rect(d, 0, .88, 1, 1, _g((.88, .88, .88)))
    return im


def tile_panel(lit):
    if lit:
        return Image.new('RGB', (INNER * SS, INNER * SS), (0, 0, 0))
    im = _canvas()
    d = ImageDraw.Draw(im)
    for i in range(2):
        _rect(d, i / 2 - .006, 0, i / 2 + .006, 1, _g((.82, .82, .82)))
    for j in range(2):
        _rect(d, 0, j / 2 - .006, 1, j / 2 + .006, _g((.9, .9, .9)))
    return im


def tile_column(lit):
    if lit:
        return Image.new('RGB', (INNER * SS, INNER * SS), (0, 0, 0))
    im = _canvas()
    d = ImageDraw.Draw(im)
    for i in range(8):
        _rect(d, i / 8, 0, i / 8 + .12 / 8 * 2, 1, _g((.92, .92, .92)))
    return im


def tile_shop(lit):
    """A shopfront (6 m x 4.2 m): a big window, a door, and a sign band above."""
    im = Image.new('RGB', (INNER * SS, INNER * SS), (0, 0, 0) if lit else (255, 255, 255))
    d = ImageDraw.Draw(im)
    if lit:
        _rect(d, .08, .12, .62, .58, _g((1.0, .88, .66), .9))
        _rect(d, .68, .12, .92, .62, _g((1.0, .88, .66), .7))
    else:
        _rect(d, .06, .10, .64, .60, _g((.9, .9, .9)))
        _rect(d, .08, .12, .62, .58, _g((.28, .38, .48)))
        _rect(d, .66, .10, .94, .64, _g((.9, .9, .9)))
        _rect(d, .68, .12, .92, .62, _g((.24, .33, .42)))
        _rect(d, 0, .70, 1, .94, _g((1, 1, 1)))
        _rect(d, 0, .94, 1, 1, _g((.82, .82, .82)))
    return im


def tile_slots(lit, seed=21, p=.55, jit=.10, lc=GLASS_LIT):
    """Tall slot windows, three to a tile (6 m x 3.4 m)."""
    im = Image.new('RGB', (INNER * SS, INNER * SS), (0, 0, 0) if lit else (255, 255, 255))
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    dr = random.Random(seed + 1000)
    for i in range(3):
        x0, x1 = i / 3 + .09, i / 3 + .24
        if lit:
            if rnd.random() < p:
                _rect(d, x0, .14, x1, .84, _g(lc, .70 + .3 * rnd.random()))
        else:
            _rect(d, x0 - .015, .12, x1 + .015, .86, _g((.9, .9, .9)))
            _rect(d, x0, .14, x1, .84, _pane(dr, jit))
            _reveal(d, x0, .14, x1, .84)
    return im

def tile_strip(lit, seed=33, p=.6, jit=.10, lc=GLASS_LIT):
    """Pairs of wide windows in a strip with a solid spandrel under each (6 m x 3.4 m)."""
    im = Image.new('RGB', (INNER * SS, INNER * SS), (0, 0, 0) if lit else (255, 255, 255))
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    dr = random.Random(seed + 1000)
    for i in range(2):
        x0, x1 = i / 2 + .06, i / 2 + .44
        if lit:
            if rnd.random() < p:
                _rect(d, x0, .26, x1, .66, _g(lc, .70 + .3 * rnd.random()))
        else:
            _rect(d, x0, .24, x1, .68, _pane(dr, jit))
            _reveal(d, x0, .24, x1, .68)
            _rect(d, x0, .68, x1, .96, _g((.92, .92, .92)))
            _rect(d, x0 + .19 - .006, .24, x0 + .19 + .006, .68, _g((.92, .92, .92)))
    return im

def tile_brick(lit):
    if lit:
        return Image.new('RGB', (INNER * SS, INNER * SS), (0, 0, 0))
    im = _canvas()
    d = ImageDraw.Draw(im)
    for r in range(8):
        _rect(d, 0, r / 8, 1, r / 8 + .05 / 8, _g((.9, .9, .9)))
    return im


def tile_roofdeck(lit):
    """A flat roof (6 m): membrane panels with seams, patches of wear, a vent or two."""
    if lit:
        return Image.new('RGB', (INNER * SS, INNER * SS), (0, 0, 0))
    im = Image.new('RGB', (INNER * SS, INNER * SS), _g((.93, .93, .93)))
    d = ImageDraw.Draw(im)
    rnd = random.Random(4)
    for k in range(4):
        _rect(d, k / 4 - .004, 0, k / 4 + .004, 1, _g((.82, .83, .85)))
    for r in range(3):
        _rect(d, 0, r / 3 - .004, 1, r / 3 + .004, _g((.86, .86, .88)))
    for _ in range(7):
        x, y = rnd.random() * .8, rnd.random() * .8
        _rect(d, x, y, x + .06 + rnd.random() * .14, y + .05 + rnd.random() * .1, _g((.86 + rnd.random() * .06,) * 3))
    for (x, y) in ((.2, .3), (.7, .72)):
        _rect(d, x, y, x + .07, y + .07, _g((.62, .64, .68)))
        _rect(d, x + .012, y + .012, x + .058, y + .058, _g((.78, .8, .84)))
    return im


# Four looks for each glazed family so that neighbours do not repeat one another: a seed (which panes), the share of panes lit at night
# (a hotel at ten at night, an office at three in the morning), and how much the panes differ by day.
FAMILIES = {'windows': (1, tile_windows), 'ribbon': (2, tile_ribbon), 'glass': (3, tile_glass), 'slots': (12, tile_slots), 'strip': (13, tile_strip)}
VARIANTS = [(101, .30, .12, (1.0, .80, .48)), (202, .78, .09, (1.0, .86, .55)), (303, .12, .14, (.80, .90, 1.0))]
VARIANT_BASE = 64


def variant_ids():
    """{'windows1': 64, ...}: the material names and tiles of the variants."""
    out = {}
    k = VARIANT_BASE
    for fam in FAMILIES:
        for v in range(len(VARIANTS)):
            out['%s%d' % (fam, v + 1)] = k
            k += 1
    return out


GLOW_BASE = 80
GLOWS = [(.62, .46, 1.0), (.30, .86, .92), (1.0, .82, .50), (.46, .62, 1.0)]     # violet, teal, amber, blue


def tile_glow(lit, c):
    if lit:
        return Image.new('RGB', (INNER * SS, INNER * SS), _g(c, .95))
    return Image.new('RGB', (INNER * SS, INNER * SS), _g((.9, .9, .92)))


def tile_apron(lit):
    """Apron concrete (15 m): four slabs a tile with their joints, each a touch different, and a few tyre and fuel stains."""
    if lit:
        return Image.new('RGB', (INNER * SS, INNER * SS), (0, 0, 0))
    im = Image.new('RGB', (INNER * SS, INNER * SS), (255, 255, 255))
    d = ImageDraw.Draw(im)
    rnd = random.Random(83)
    for i in range(2):
        for j in range(2):
            _rect(d, i / 2, j / 2, (i + 1) / 2, (j + 1) / 2, _g((1, 1, 1), .90 + .10 * rnd.random()))
    for _ in range(6):
        x, y = rnd.random() * .85, rnd.random() * .85
        _rect(d, x, y, x + .04 + rnd.random() * .10, y + .02 + rnd.random() * .04, _g((.72, .72, .72)))
    for k in range(2):
        _rect(d, k / 2 - .006, 0, k / 2 + .006, 1, _g((.55, .56, .60)))
        _rect(d, 0, k / 2 - .006, 1, k / 2 + .006, _g((.55, .56, .60)))
    return im


TILES = [tile_plain, tile_windows, tile_ribbon, tile_glass, tile_sheet, tile_tile, tile_arches, tile_louvre, tile_sign, tile_panel, tile_column, tile_shop, tile_slots, tile_strip, tile_brick, tile_roofdeck]

# one sign for every named building: its name on a band, in the band's colour (drawn in the tile itself, not tinted by the vertex colour)
SIGNS = {}
SIGN_BG = [(0x3A, 0x4C, 0x86), (0x2F, 0xA6, 0xAB), (0xC9, 0x54, 0x4A), (0x4C, 0x9A, 0x6A), (0xE0, 0x7B, 0x2E), (0x3F, 0x67, 0xB0), (0x5E, 0x66, 0x7E)]


def sign_id(text):
    """The material of the sign for this text (registering it): 16 and up."""
    text = text.strip()
    if text not in SIGNS:
        if len(SIGNS) >= 48:
            return None
        SIGNS[text] = 16 + len(SIGNS)
    return SIGNS[text]


def tile_sign_text(text, lit):
    W, H = 960, 128
    bg = SIGN_BG[sum(map(ord, text)) % len(SIGN_BG)]
    im = Image.new('RGB', (W, H), (0, 0, 0) if lit else (255, 255, 255))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([6, 6, W - 7, H - 7], radius=18, fill=(int(bg[0] * .9), int(bg[1] * .9), int(bg[2] * .9)) if lit else bg)
    size = 84
    font = None
    for fp in ('C:/Windows/Fonts/segoeuib.ttf', 'C:/Windows/Fonts/arialbd.ttf'):
        try:
            font = ImageFont.truetype(fp, size)
            break
        except Exception:
            pass
    if font is None:
        font = ImageFont.load_default()
    label = text.upper()
    while d.textlength(label, font=font) > W - 70 and size > 30:
        size -= 4
        font = ImageFont.truetype(font.path, size) if hasattr(font, 'path') else font
    tw = d.textlength(label, font=font)
    d.text(((W - tw) / 2, H / 2 - size * .58), label, font=font, fill=(255, 255, 255) if not lit else (255, 244, 220))
    return im.resize((INNER * SS, INNER * SS), Image.LANCZOS)


def periodic(im):
    """A cell: the tile in its middle, and the tile again all round it."""
    im = im.resize((INNER, INNER), Image.LANCZOS)
    big = Image.new('RGB', (INNER * 3, INNER * 3))
    for i in range(3):
        for j in range(3):
            big.paste(im, (i * INNER, j * INNER))
    o = INNER - (CELL - INNER) // 2
    return big.crop((o, o, o + CELL, o + CELL))


GRID = 16


def build(outdir):
    A = Image.new('RGBA', (CELL * GRID, CELL * GRID), (255, 255, 255, 255))
    E = Image.new('RGBA', (CELL * GRID, CELL * GRID), (0, 0, 0, 255))
    rects = [None] * 84
    pad = (CELL - INNER) / 2 / (CELL * GRID)
    def put(k, day, night):
        col, row = k % GRID, k // GRID
        A.paste(periodic(day).convert('RGBA'), (col * CELL, row * CELL))
        E.paste(periodic(night).convert('RGBA'), (col * CELL, row * CELL))
        rects[k] = [col / GRID + pad, row / GRID + pad, INNER / (CELL * GRID), INNER / (CELL * GRID)]
    for k, fn in enumerate(TILES):
        put(k, fn(False), fn(True))
    for k in range(len(TILES), 16):
        put(k, tile_plain(False), tile_plain(True))
    for text, k in SIGNS.items():
        put(k, tile_sign_text(text, False), tile_sign_text(text, True))
    for k, c in enumerate(GLOWS):
        put(GLOW_BASE + k, tile_glow(False, c), tile_glow(True, c))
    put(83, tile_apron(False), tile_apron(True))
    ids = variant_ids()
    for fam, (base, fn) in FAMILIES.items():
        for v, (seed, p, jit, lc) in enumerate(VARIANTS):
            put(ids['%s%d' % (fam, v + 1)], fn(False, seed, p, jit, lc), fn(True, seed, p, jit, lc))
    return A, E, rects
