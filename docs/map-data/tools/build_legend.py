"""admin/assets/map/legend.json from docs/map-data/legend.py.   python docs/map-data/tools/build_legend.py"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
import legend
out = os.path.join(HERE, '..', '..', '..', 'admin', 'assets', 'map', 'legend.json')
json.dump({'groups': [dict(k=k, name=n, day=d, night=nt, sign=sg, glow=gl) for k, n, d, nt, sg, gl in legend.GROUPS], 'landmarkGlow': legend.LANDMARK_GLOW}, open(out, 'w'), separators=(',', ':'))
print('legend.json:', len(legend.GROUPS), 'groups')
