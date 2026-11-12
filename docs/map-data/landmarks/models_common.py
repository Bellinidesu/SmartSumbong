"""Shared by models.py and zone.py: the palette and the way a building faces."""
import math

from shapely.geometry import Point

from meshlib import rgb

C = dict(
    cream=rgb('F1E6D2'), white=rgb('F4F1EA'), peach=rgb('EBC2A8'), terra=rgb('CC8A66'), sand=rgb('E3CFA6'), rose=rgb('E6B7B0'),
    blue=rgb('4C79C4'), navy=rgb('3A4C86'), teal=rgb('2FA6AB'), green=rgb('4C9A6A'), grey=rgb('B8BDC8'), slate=rgb('7C849A'),
    red=rgb('C9544A'), orange=rgb('F08C3A'), yellow=rgb('F2C14E'), glass=rgb('B9C9DA'), dome=rgb('3F6FB5'), roofblue=rgb('3F67B0'),
    rooftile=rgb('B9654F'), roofgrey=rgb('7F8794'), sheetwhite=rgb('EDEDED'),
)


def front_of(ctx):
    """(unit vector out of the front, half the length behind it, half the length across, the unit vector along the front)."""
    others = ctx.get('others', [])
    th, L, W = ctx['th'], ctx['L'], ctx['W']
    c, s_ = math.cos(th), math.sin(th)
    best = None
    for k, (dx, dy, half, across, along) in enumerate(((c, s_, L / 2, W / 2, (-s_, c)), (-c, -s_, L / 2, W / 2, (s_, -c)),
                                                         (-s_, c, W / 2, L / 2, (c, s_)), (s_, -c, W / 2, L / 2, (-c, -s_)))):
        mid = Point(ctx['cx'] + dx * (half + 1), ctx['cy'] + dy * (half + 1))
        free = min([mid.distance(o) for o in others] + [80.0])
        score = free + (6 if k < 2 else 0)
        if best is None or score > best[0]:
            best = (score, (dx, dy), half, across, along)
    _, d, half, across, along = best
    return d, half, across, along
