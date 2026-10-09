#!/usr/bin/env python3
"""
One command for the whole City view build, in the order the pieces need each other. Every step is a script that already stands alone; this runs them,
times them, stops at the first failure, and can start from any step (so a change to the models only reruns the model steps).

  python docs/map-data/tools/make_city.py --list
  python docs/map-data/tools/make_city.py                       everything
  python docs/map-data/tools/make_city.py --from styles         from the street-view reading onward
  python docs/map-data/tools/make_city.py --only models,light   just those steps
  python docs/map-data/tools/make_city.py --skip gpu            everything but the GPU ground bake (slow)

Needs: Python 3.10+, numpy scipy shapely rasterio pillow overturemaps; Node + Brave/Chrome for the GPU steps; MAPILLARY_TOKEN in .env for 'styles'.
"""
import os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
DM = os.path.normpath(os.path.join(HERE, '..'))
LM = os.path.join(DM, 'landmarks')

# name, working dir, command, what it makes
STEPS = [
    ('detail',   DM, ['build_city_detail.py'],                    'crossings, areas, lamps, mapped trees (OpenStreetMap)'),
    ('buildings', DM, ['build_buildings.py'],                     'footprints, heights, names (OpenStreetMap + Overture + facts.py)'),
    ('trees',    DM, ['build_trees_chm.py'],                      'measured trees from the canopy height map'),
    ('plain',    DM, ['plain.py', '--apply'],                     'trees and lamps out of the airfield side and Villamor Air Base (they go back to plain colours)'),
    ('shadows',  DM, ['bake_shadows.py'],                         'the first (CPU) shadow and glow pictures'),
    ('faces',    DM, ['bake_detail.py'],                          'per-wall tones in five height bands'),
    ('gpu',      DM, ['bake_gpu.py'],                             'GPU path-traced ground pictures, day and night'),
    ('styles',   HERE, ['stylise.py', '--min-h', '8'],            'what the real walls look like, from 360 street views (a few numbers per building)'),
    ('models',   LM, ['models.py'],                               'the landmark models (a flag, off in the map by default: ?models=1; bake with SS_MODELS=1)'),
    ('light',    LM, ['bake_models.py'],                          'path-traced light baked into every model vertex'),
    ('wash',     LM, ['wash.py'],                                 'the night wash of each landmark (the colour that climbs its walls), from its sheet'),
]


def main():
    a = sys.argv[1:]
    names = [s[0] for s in STEPS]
    if '--list' in a:
        for n, wd, cmd, what in STEPS:
            print('%-10s %s' % (n, what))
        return
    chosen = list(names)
    if '--from' in a:
        chosen = names[names.index(a[a.index('--from') + 1]):]
    if '--only' in a:
        chosen = [n for n in a[a.index('--only') + 1].split(',') if n in names]
    if '--skip' in a:
        chosen = [n for n in chosen if n not in a[a.index('--skip') + 1].split(',')]
    t0 = time.time()
    for n, wd, cmd, what in STEPS:
        if n not in chosen:
            continue
        t = time.time()
        print('\n=== %s: %s' % (n, what), flush=True)
        r = subprocess.run([sys.executable] + cmd, cwd=wd, env=dict(os.environ, PYTHONIOENCODING='utf-8'))
        if r.returncode:
            raise SystemExit('step "%s" failed (%d); fix it and rerun with --from %s' % (n, r.returncode, n))
        print('--- %s done in %.0f s' % (n, time.time() - t), flush=True)
    print('\nall done in %.1f min' % ((time.time() - t0) / 60))


main()
