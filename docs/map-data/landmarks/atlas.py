"""
The facade atlas of the landmark models: one picture of 4 x 4 tiles for the day (a multiplier on the albedo colour of each
surface: 1 for wall, darker for glass) and one for the night (which windows are lit, painted as light). Drawn here in the
barangay's plain style: flat colours, no photographs. Every tile repeats, so each is painted so that its edges meet.
"""
import random

from PIL import Image, ImageDraw, ImageFilter

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


def tile_windows(lit):
    """Two bays of punched windows over one storey (6.4 m x 3.4 m)."""
    im = Image.new('RGB', (INNER * SS, INNER * SS), (0, 0, 0) if lit else (255, 255, 255))
    d = ImageDraw.Draw(im)
    rnd = random.Random(11)
    for bay in range(2):
        x0, x1 = (bay * .5 + .17), (bay * .5 + .33)
        # a window: frame, glass, sill
        if lit:
            if rnd.random() < .55:
                _rect(d, x0, .30, x1, .74, _g(GLASS_LIT, .9))
        else:
            _rect(d, x0 - .018, .28, x1 + .018, .76, _g((.92, .92, .92)))
            _rect(d, x0, .30, x1, .74, _g(GLASS))
            _rect(d, x0 - .03, .74, x1 + .03, .79, _g((.86, .86, .86)))
            _rect(d, (x0 + x1) / 2 - .006, .30, (x0 + x1) / 2 + .006, .74, _g((.92, .92, .92)))
    return im


def tile_ribbon(lit):
    """A continuous band of glass with mullions (6 m x 3.4 m)."""
    im = Image.new('RGB', (INNER * SS, INNER * SS), (0, 0, 0) if lit else (255, 255, 255))
    d = ImageDraw.Draw(im)
    rnd = random.Random(7)
    n = 4
    for i in range(n):
        x0, x1 = i / n + .012, (i + 1) / n - .012
        if lit:
            if rnd.random() < .6:
                _rect(d, x0, .30, x1, .72, _g(GLASS_LIT, .85))
        else:
            _rect(d, x0, .30, x1, .72, _g(GLASS))
    if not lit:
        _rect(d, 0, .72, 1, .76, _g((.9, .9, .9)))
        _rect(d, 0, .26, 1, .30, _g((.9, .9, .9)))
    return im


def tile_glass(lit):
    """A curtain wall: a grid of glass panels (3.2 m x 3.4 m)."""
    im = Image.new('RGB', (INNER * SS, INNER * SS), (0, 0, 0) if lit else _g((.78, .80, .84)))
    d = ImageDraw.Draw(im)
    rnd = random.Random(5)
    for i in range(2):
        for j in range(3):
            x0, x1, y0, y1 = i / 2 + .03, (i + 1) / 2 - .03, j / 3 + .03, (j + 1) / 3 - .03
            if lit:
                if rnd.random() < .4:
                    _rect(d, x0, y0, x1, y1, _g((.82, .88, 1.0), .6))
            else:
                _rect(d, x0, y0, x1, y1, _g((.28, .40, .54)))
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


TILES = [tile_plain, tile_windows, tile_ribbon, tile_glass, tile_sheet, tile_tile, tile_arches, tile_louvre, tile_sign, tile_panel, tile_column, tile_shop]


def periodic(im):
    """A cell: the tile in its middle, and the tile again all round it."""
    im = im.resize((INNER, INNER), Image.LANCZOS)
    big = Image.new('RGB', (INNER * 3, INNER * 3))
    for i in range(3):
        for j in range(3):
            big.paste(im, (i * INNER, j * INNER))
    o = INNER - (CELL - INNER) // 2
    return big.crop((o, o, o + CELL, o + CELL))


def build(outdir):
    A = Image.new('RGBA', (CELL * 4, CELL * 4), (255, 255, 255, 255))
    E = Image.new('RGBA', (CELL * 4, CELL * 4), (0, 0, 0, 255))
    rects = []
    for k, fn in enumerate(TILES):
        col, row = k % 4, k // 4
        A.paste(periodic(fn(False)).convert('RGBA'), (col * CELL, row * CELL))
        e = periodic(fn(True)).convert('RGBA')
        E.paste(e, (col * CELL, row * CELL))
        pad = (CELL - INNER) / 2 / (CELL * 4)
        rects.append([col / 4 + pad, row / 4 + pad, INNER / (CELL * 4), INNER / (CELL * 4)])
    return A, E, rects
