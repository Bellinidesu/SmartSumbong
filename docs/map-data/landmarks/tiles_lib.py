"""
The surfaces a landmark sheet can ask for (landmarks/sheets/*.json, "tiles"). Each kind draws one tile for the day (a multiplier on the albedo colour: 1 is
the wall's own colour, less is darker) and the same tile for the night (which panes are lit), flat colours as everywhere on this map, and every tile repeats,
so its edges meet. The eight materials of the identity plan: glass (graded by the vertices), stucco, board-marked concrete, terrazzo, stone cladding, timber
louvres, brick and tile are the existing atlas tiles or kinds here; the glazed kinds are cut to whole bays and storeys by the mesh.

Weathering is drawn, not computed: streaks that run down from sills and slab edges, grime at the foot of a tile, a sun-faded top. Nothing here uses the path tracer.
"""
import random

import numpy as np
from PIL import Image, ImageDraw

import atlas
from atlas import INNER, SS, _g, _rect

WARM = (1.0, .80, .48)
COOL = (.80, .90, 1.0)
LIT = {'warm': WARM, 'bright': (1.0, .86, .55), 'cool': COOL}


def _canvas(lit, day=1.0):
    return Image.new('RGB', (INNER * SS, INNER * SS), (0, 0, 0) if lit else _g((day, day, day)))


def weather(im, seed, k=1.0, streaks=14, grime=.10):
    """Streaks running down the tile (they wrap round, so the tile still repeats) and grime at its foot."""
    if k <= 0:
        return im
    a = np.asarray(im, dtype=np.float32) / 255.0
    H, W = a.shape[:2]
    rnd = random.Random(seed)
    m = np.ones((H, W), dtype=np.float32)
    ys = np.arange(H)[:, None] / H
    for _ in range(streaks):
        x = rnd.random()
        w = (.004 + rnd.random() * .012)
        y0 = rnd.random()
        ln = .15 + rnd.random() * .5
        d = ((ys - y0) % 1.0)
        fall = np.where(d < ln, np.maximum(1 - d / ln, 0) ** 1.4, 0.0)
        xs = np.arange(W)[None, :] / W
        dx = np.minimum(np.abs(xs - x), 1 - np.abs(xs - x))
        m *= 1 - k * (.05 + .08 * rnd.random()) * fall * np.exp(-(dx / w) ** 2)
    foot = np.clip((ys - (1 - grime)) / grime, 0, 1)
    m *= 1 - k * .06 * foot
    a = a * m[..., None]
    return Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8))


def _pane(rnd, jit, sky=.10):
    k = 1 + jit * (rnd.random() * 2 - 1)
    return (.44, .55, .72) if rnd.random() < sky else (.28, .40, .54), k


# ------------------------------------------------------------------ kinds
def loggia(lit, seed=3, p=.5, bays=2, wear=1.0, lc='warm', **kw):
    """A storey of recessed balconies, each between two pilasters: a slab edge below, a balustrade, a window set back in the shade."""
    im = _canvas(lit, .95)
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    dr = random.Random(seed + 1000)
    col = LIT.get(lc, WARM)
    for b in range(bays):
        x0, w = b / bays, 1.0 / bays
        ox0, ox1 = x0 + w * .17, x0 + w * .83
        if lit:
            if rnd.random() < p:
                _rect(d, x0 + w * .31, .27, x0 + w * .69, .62, _g(col, .70 + .3 * rnd.random()))
            continue
        _rect(d, x0 + w * .0, 0, x0 + w * .09, 1, _g((1, 1, 1)))                 # pilasters, a touch lighter than the wall
        _rect(d, x0 + w * .91, 0, x0 + w, 1, _g((1, 1, 1)))
        _rect(d, ox0, .10, ox1, .90, _g((.64, .64, .66)))                           # the recess
        _rect(d, ox0, .10, ox1, .22, _g((.40, .41, .45)))                           # the shade under the slab above
        _rect(d, ox0, .10, ox0 + w * .05, .90, _g((.50, .50, .54)))                 # and in the side reveal
        c, k = _pane(dr, .10)
        _rect(d, x0 + w * .30, .26, x0 + w * .70, .64, _g((.93, .93, .93)))        # the window frame
        _rect(d, x0 + w * .32, .28, x0 + w * .68, .62, _g(c, k))
        _rect(d, x0 + w * .49, .28, x0 + w * .51, .62, _g((.93, .93, .93)))
        _rect(d, ox0, .62, ox1, .90, _g((.80, .80, .82)))                           # the balustrade: a solid apron with a rail
        _rect(d, ox0 - w * .02, .60, ox1 + w * .02, .65, _g((1, 1, 1)))
        for j in range(1, 8):
            _rect(d, ox0 + (ox1 - ox0) * j / 8 - .004, .66, ox0 + (ox1 - ox0) * j / 8 + .004, .88, _g((.93, .93, .93)))
    if not lit:
        _rect(d, 0, .90, 1, 1.0, _g((1, 1, 1)))                                     # the slab edge
        _rect(d, 0, .90, 1, .915, _g((.78, .78, .8)))
        im = weather(im, seed, wear)
    return im


def curtain(lit, seed=5, p=.4, bays=4, jit=.12, lc='cool', wear=.3, **kw):
    """A curtain wall: mullions, vision glass over a spandrel panel, panes that differ a little, one now and then holding sky."""
    im = _canvas(lit, .82)
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    dr = random.Random(seed + 1000)
    col = LIT.get(lc, COOL)
    for b in range(bays):
        x0, w = b / bays + .012, 1.0 / bays - .024
        if lit:
            if rnd.random() < p:
                _rect(d, x0, .08, x0 + w, .72, _g(col, .45 + .4 * rnd.random()))
        else:
            c, k = _pane(dr, jit, .14)
            _rect(d, x0, .08, x0 + w, .72, _g(c, k))
            _rect(d, x0, .75, x0 + w, .96, _g((.46, .50, .56), 1 + .05 * (dr.random() * 2 - 1)))
    return im if lit else weather(im, seed, wear, 6)


def band(lit, seed=9, p=.3, n=6, lc='warm', wear=.6, **kw):
    """A plain band under the cornice with a row of small square windows."""
    im = _canvas(lit, .96)
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    dr = random.Random(seed + 1000)
    col = LIT.get(lc, WARM)
    for i in range(n):
        x0, w = i / n + .30 / n, .40 / n
        if lit:
            if rnd.random() < p:
                _rect(d, x0, .30, x0 + w, .68, _g(col, .8))
        else:
            c, k = _pane(dr, .1)
            _rect(d, x0 - .004, .28, x0 + w + .004, .70, _g((.93, .93, .93)))
            _rect(d, x0, .30, x0 + w, .68, _g(c, k))
    if not lit:
        _rect(d, 0, 0, 1, .05, _g((.80, .80, .82)))
        im = weather(im, seed, wear, 8)
    return im


def stucco(lit, seed=11, wear=1.0, reveal=True, **kw):
    """Plain painted wall with a reveal line at the storey and the stains of years of rain."""
    im = _canvas(lit, .96)
    if lit:
        return im
    d = ImageDraw.Draw(im)
    if reveal:
        _rect(d, 0, 0, 1, .012, _g((.80, .80, .82)))
    return weather(im, seed, wear, 18)


def board(lit, seed=13, wear=.8, **kw):
    """Board-marked concrete: horizontal boards, a different grey each."""
    im = _canvas(lit, .9)
    if lit:
        return im
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    n = 10
    for i in range(n):
        _rect(d, 0, i / n, 1, (i + 1) / n, _g((1, 1, 1), .86 + .12 * rnd.random()))
        _rect(d, 0, i / n, 1, i / n + .01, _g((.7, .7, .72)))
    return weather(im, seed, wear, 10)


def terrazzo(lit, seed=15, **kw):
    """A polished podium: a pale ground with chips."""
    im = _canvas(lit, .92)
    if lit:
        return im
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    for _ in range(220):
        x, y = rnd.random(), rnd.random()
        s = .006 + rnd.random() * .012
        g = .70 + .3 * rnd.random()
        _rect(d, x, y, x + s, y + s, _g((g, g, g * .97)))
    return im


def stone(lit, seed=17, wear=.6, rows=4, **kw):
    """Cut stone cladding: courses of blocks with fine joints."""
    im = _canvas(lit, .95)
    if lit:
        return im
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    for r in range(rows):
        y0, y1 = r / rows, (r + 1) / rows
        n = 3 + (r % 2)
        for i in range(n):
            x0 = i / n + (.5 / n if r % 2 else 0)
            _rect(d, x0, y0, x0 + 1 / n, y1, _g((1, 1, 1), .88 + .12 * rnd.random()))
            _rect(d, x0, y0, x0 + .008, y1, _g((.66, .66, .68)))
        _rect(d, 0, y0, 1, y0 + .012, _g((.66, .66, .68)))
    return weather(im, seed, wear, 8)


def timber(lit, seed=19, slats=12, **kw):
    """Vertical timber louvres: slats with a shadow gap between."""
    im = _canvas(lit, .9)
    if lit:
        return im
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    for i in range(slats):
        x0 = i / slats
        _rect(d, x0, 0, x0 + .62 / slats, 1, _g((1, 1, 1), .84 + .16 * rnd.random()))
        _rect(d, x0 + .62 / slats, 0, (i + 1) / slats, 1, _g((.38, .36, .34)))
    return im


def shopfront(lit, seed=21, p=.7, bays=2, lc='warm', wear=.8, **kw):
    """A ground floor: glazed shop windows between piers, a fascia above for the sign."""
    im = _canvas(lit, .96)
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    col = LIT.get(lc, WARM)
    for b in range(bays):
        x0, w = b / bays, 1.0 / bays
        if lit:
            if rnd.random() < p:
                _rect(d, x0 + w * .12, .30, x0 + w * .88, .86, _g(col, .85))
        else:
            _rect(d, x0 + w * .08, .26, x0 + w * .92, .90, _g((.92, .92, .92)))
            _rect(d, x0 + w * .12, .30, x0 + w * .88, .86, _g((.30, .40, .50)))
            _rect(d, x0 + w * .50 - .004, .30, x0 + w * .50 + .004, .86, _g((.92, .92, .92)))
    if not lit:
        _rect(d, 0, .02, 1, .20, _g((.90, .90, .92)))                               # the fascia
        _rect(d, 0, .20, 1, .23, _g((.70, .70, .74)))
        im = weather(im, seed, wear, 8, .14)
    return im


def brickbay(lit, seed=23, p=.5, bays=2, lc='warm', wear=.9, **kw):
    """Brick-faced storey: courses of brick, a tall window in each bay with a pale surround, a lintel above it and a sill below."""
    im = _canvas(lit, .93)
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    dr = random.Random(seed + 1000)
    col = LIT.get(lc, WARM)
    for b in range(bays):
        x0, w = b / bays, 1.0 / bays
        wx0, wx1 = x0 + w * .24, x0 + w * .76
        if lit:
            if rnd.random() < p:
                _rect(d, wx0 + w * .03, .20, wx1 - w * .03, .76, _g(col, .75 + .25 * rnd.random()))
            continue
    if not lit:
        n = 14
        for r in range(n):
            _rect(d, 0, r / n, 1, r / n + .012, _g((.80, .78, .78)))          # brick courses
        for b in range(bays):
            x0, w = b / bays, 1.0 / bays
            wx0, wx1 = x0 + w * .24, x0 + w * .76
            _rect(d, wx0 - w * .05, .14, wx1 + w * .05, .82, _g((1, 1, 1)))                                  # the pale surround
            _rect(d, wx0 - w * .08, .10, wx1 + w * .08, .16, _g((1, 1, 1)))                                  # the lintel
            _rect(d, wx0 - w * .07, .80, wx1 + w * .07, .86, _g((.96, .96, .96)))                            # the sill
            _rect(d, wx0, .18, wx1, .78, _g((.62, .62, .64)))                                                # the reveal
            c, k = _pane(dr, .10)
            _rect(d, wx0 + w * .03, .20, wx1 - w * .03, .76, _g(c, k))
            _rect(d, (wx0 + wx1) / 2 - .004, .20, (wx0 + wx1) / 2 + .004, .76, _g((.95, .95, .95)))
            _rect(d, wx0 + w * .03, .47, wx1 - w * .03, .50, _g((.95, .95, .95)))
        im = weather(im, seed, wear, 14)
    return im


def arcade(lit, seed=29, p=.8, bays=2, lc='bright', wear=.7, **kw):
    """A ground floor of arched, glazed openings between pale piers, a string course above."""
    im = _canvas(lit, .96)
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    S = INNER * SS
    col = LIT.get(lc, WARM)
    for b in range(bays):
        x0, w = b / bays, 1.0 / bays
        cx, hw = (x0 + w / 2) * S, w * .30 * S
        top, bot = .10 * S, .92 * S
        if lit:
            if rnd.random() < p:
                d.rectangle([cx - hw, top + hw, cx + hw, bot], fill=_g(col, .85))
                d.pieslice([cx - hw, top, cx + hw, top + 2 * hw], 180, 360, fill=_g(col, .85))
            continue
        d.rectangle([cx - hw - .02 * S, top + hw, cx + hw + .02 * S, bot], fill=_g((.90, .90, .92)))
        d.pieslice([cx - hw - .02 * S, top - .02 * S, cx + hw + .02 * S, top + 2 * hw + .02 * S], 180, 360, fill=_g((.90, .90, .92)))
        d.rectangle([cx - hw, top + hw, cx + hw, bot], fill=_g((.30, .42, .50)))
        d.pieslice([cx - hw, top, cx + hw, top + 2 * hw], 180, 360, fill=_g((.30, .42, .50)))
        d.rectangle([cx - .004 * S, top + .08 * S, cx + .004 * S, bot], fill=_g((.92, .92, .94)))
        d.rectangle([cx - hw, .52 * S, cx + hw, .535 * S], fill=_g((.92, .92, .94)))
    if not lit:
        _rect(d, 0, 0, 1, .035, _g((.80, .80, .82)))
        im = weather(im, seed, wear, 8, .12)
    return im


def _hexmul(c, ref):
    """A painted colour (hex) as a multiplier on the wall's albedo (ref, hex): the tile is multiplied by the vertex colour, so a colour lighter than the wall cannot be had; the sheet
    therefore takes the lightest painted colour as its wall and everything else as a share of it."""
    c = tuple(int(c[i:i + 2], 16) / 255 for i in (0, 2, 4))
    r = tuple(int(ref[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return tuple(min(1.0, a / max(b, .05)) for a, b in zip(c, r))


def photo(lit, ref='FFFFFF', seed=1, bays=3, floors=3, bay_w=4.0, floor_h=3.4, win=(.14, .96, .06, .72), glass='6FA9B0', glass_hi='9FD4D6', spandrel='D9DDDD', pier='EDEDEA',
          mull_x=0, mull_y=0, mull='E6E8E8', sky=.12, jit=.08, p=.45, lc='warm', wear=.3, blinds=.18, strip=False, **kw):
    """A facade as measured off the street view (measure.py): bays across and floors up in one tile, each cell a pier, a window (its glass, its mullions, its blind or curtain) and a
    spandrel; the glass differs a little from window to window and now and then holds the sky; at night some windows are lit (a whole pane, or half of it). Every number is a measurement."""
    im = _canvas(lit, 1.0)
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    S = INNER * SS
    g0, g1 = _hexmul(glass, ref), _hexmul(glass_hi, ref)
    sp, pc, mc = _hexmul(spandrel, ref), _hexmul(pier, ref), _hexmul(mull, ref)
    col = LIT.get(lc, WARM)
    cw, ch = S / bays, S / floors
    x0f, x1f, y0f, y1f = win
    for f in range(floors):
        on = rnd.random() < min(1.0, p * 1.5)                               # a floor that is occupied lights most of its rooms; an empty one none
        for b in range(bays):
            X, Y = b * cw, f * ch
            wx0, wx1, wy0, wy1 = X + x0f * cw, X + x1f * cw, Y + y0f * ch, Y + y1f * ch
            if lit:
                if on and rnd.random() < .72:
                    half = rnd.random() < .3
                    warm = tuple(a * (.88 + .12 * rnd.random()) for a in col)
                    d.rectangle([wx0, wy0, (wx0 + wx1) / 2 if half else wx1, wy1], fill=_g(warm, .55 + .45 * rnd.random()))
                elif rnd.random() < .08:
                    d.rectangle([wx0, wy0, wx1, wy1], fill=_g((.30, .42, .62), .35))       # a screen or a night light left on, cold
                continue
            d.rectangle([X, Y, X + cw, Y + ch], fill=_g(sp))                       # the wall between the windows
            d.rectangle([X, Y, X + x0f * cw, Y + ch], fill=_g(pc))                 # the pier
            hi = rnd.random() < sky
            k = 1 + jit * (rnd.random() * 2 - 1)
            gc = tuple(a * (1 - t) + c * t for a, c, t in zip(g0, g1, [.85 if hi else rnd.random() * .35] * 3))
            d.rectangle([wx0, wy0, wx1, wy1], fill=_g(gc, k))
            if rnd.random() < blinds:                                              # a blind or a curtain drawn over part of the window
                bh = (wy1 - wy0) * (.25 + .5 * rnd.random())
                d.rectangle([wx0, wy0, wx1, wy0 + bh], fill=_g((.93, .91, .86), 1))
            for j in range(1, mull_x + 1):
                x = wx0 + (wx1 - wx0) * j / (mull_x + 1)
                d.rectangle([x - .004 * S, wy0, x + .004 * S, wy1], fill=_g(mc))
            for j in range(1, mull_y + 1):
                y = wy0 + (wy1 - wy0) * j / (mull_y + 1)
                d.rectangle([wx0, y - .004 * S, wx1, y + .004 * S], fill=_g(mc))
            d.rectangle([wx0, wy0, wx1, wy0 + .006 * S], fill=_g(mc, .9))          # the head of the window
            d.rectangle([wx0 - .004 * S, wy1, wx1 + .004 * S, wy1 + .012 * S], fill=_g(mc))   # the sill
    if lit:
        return im
    return weather(im, seed, wear, 6, .08)


def ivy(lit, seed=7, ref='FFFFFF', leaf='557C42', leaf2='7FA05A', wall='C9805F', bloom='D94F8E', gaps=.18, blooms=.012, **kw):
    """A wall hidden under climbing plant (absolute colours, the vertex colour is white): leaves of two greens, a little of the wall showing through, scattered pink bloom, a hedge band at the foot."""
    if lit:
        return Image.new('RGB', (INNER * SS, INNER * SS), (0, 0, 0))
    S = INNER * SS
    rnd = random.Random(seed)
    A = _hexmul(leaf, 'FFFFFF'), _hexmul(leaf2, 'FFFFFF'), _hexmul(wall, 'FFFFFF'), _hexmul(bloom, 'FFFFFF')
    im = Image.new('RGB', (S, S), _g(A[0], .9))
    d = ImageDraw.Draw(im)
    for _ in range(int(900 * (1 - gaps))):
        x, y, r = rnd.random() * S, rnd.random() * S * .86, (.012 + rnd.random() * .02) * S
        c = A[1] if rnd.random() < .5 else A[0]
        d.ellipse([x - r, y - r * .8, x + r, y + r * .8], fill=_g(c, .75 + .3 * rnd.random()))
        d.ellipse([x - r + S, y - r * .8, x + r + S, y + r * .8], fill=_g(c, .8)) if x < r else None
    for _ in range(int(120 * gaps * 4)):
        x, y, r = rnd.random() * S, rnd.random() * S * .86, (.01 + rnd.random() * .016) * S
        d.ellipse([x - r, y - r, x + r, y + r], fill=_g(A[2], .85))
    for _ in range(int(blooms * 5000)):
        x, y, r = rnd.random() * S, rnd.random() * S * .8, (.004 + rnd.random() * .006) * S
        d.ellipse([x - r, y - r, x + r, y + r], fill=_g(A[3], .95))
    d.rectangle([0, S * .88, S, S], fill=_g(A[0], .62))                       # the hedge at its foot
    for _ in range(160):
        x, y = rnd.random() * S, S * (.86 + rnd.random() * .14)
        r = (.012 + rnd.random() * .012) * S
        d.ellipse([x - r, y - r, x + r, y + r], fill=_g(A[1], .55 + .3 * rnd.random()))
    return im


KINDS = dict(ivy=ivy, photo=photo, brickbay=brickbay, arcade=arcade, loggia=loggia, curtain=curtain, band=band, stucco=stucco, board=board, terrazzo=terrazzo, stone=stone, timber=timber, shopfront=shopfront)


def register(slug, name, spec, ref='FFFFFF'):
    """Register one tile of a sheet with the atlas and the mesh library; returns the material name."""
    import meshlib
    kind = spec['kind']
    fn = KINDS[kind]
    kw = {k: v for k, v in spec.items() if k not in ('kind', 'm', 'fit', 'graded')}
    if kind in ('photo', 'ivy'):
        kw['ref'] = ref
        kw.setdefault('bay_w', spec['m'][0] / kw.get('bays', 3))
    full = '%s/%s' % (slug, name)
    tid = atlas.register_custom(full, lambda: fn(False, **kw), lambda: fn(True, **kw), keep_day=(kind == 'ivy'))
    meshlib.register_material(full, tid, tuple(spec.get('m', (6.4, 3.4))), bool(spec.get('fit', False)), bool(spec.get('graded', False)))
    return full
