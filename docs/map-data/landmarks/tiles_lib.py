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


KINDS = dict(loggia=loggia, curtain=curtain, band=band, stucco=stucco, board=board, terrazzo=terrazzo, stone=stone, timber=timber, shopfront=shopfront)


def register(slug, name, spec):
    """Register one tile of a sheet with the atlas and the mesh library; returns the material name."""
    import meshlib
    kind = spec['kind']
    fn = KINDS[kind]
    kw = {k: v for k, v in spec.items() if k not in ('kind', 'm', 'fit', 'graded')}
    full = '%s/%s' % (slug, name)
    tid = atlas.register_custom(full, lambda: fn(False, **kw), lambda: fn(True, **kw))
    meshlib.register_material(full, tid, tuple(spec.get('m', (6.4, 3.4))), bool(spec.get('fit', False)), bool(spec.get('graded', False)))
    return full
