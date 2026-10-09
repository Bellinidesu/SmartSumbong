#!/usr/bin/env python3
"""
Recolours admin/assets/map/style-dark.json and style-light.json into Bellinist night and Bellinist day.

Apple Maps' night map is a blue-violet one (navy water, teal greens, lavender buildings) and its day map is
white with bright greens and a clear blue; ours keeps the barangay's graphite and orange and borrows the
temperature of those. Only colours change: layers, widths, filters and fonts stay as they are, so the map the
page draws (and the three-dimensional layers added over it by assets/js/sd-city.js) keep working.

Run:  python docs/map-data/build_bellinist_styles.py
"""
import json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
MAP = os.path.normpath(os.path.join(HERE, '..', '..', 'admin', 'assets', 'map'))

GREENS = ['park', 'landcover_wood', 'land_grass', 'land_golf', 'land_pitch', 'land_cemetery', 'land_military']
MINOR = ['highway_path', 'highway_minor', 'highway_major_subtle', 'highway_motorway_subtle', 'railway_transit', 'railway_service', 'railway']
AIR = ['aeroway-taxiway', 'aeroway-runway-casing', 'aeroway-area', 'aeroway-runway', 'road_area_pier', 'road_pier']

NIGHT = dict(
    bg='#191D2B', res='#1D2132', green='#1B4A3B', wood='#173F32', grass='#1A4637', golf='#1F5242', pitch='#1D5040', cemetery='#1C4538', military='#1B3D35',
    sand='#3F3F55', water='#14275C', bld='#262B42', bldo='#303656', air='#222639',
    minor='#394060', majc='#262B44', majo='#454D70', motc='#2A2F4A', moto='#565F8C', rail='#343A58',
    lab='#E7EAF8', labsoft='#AEB4D2', halo='#12152A',
)
DAY = dict(
    bg='#F6F4F0', res='#F1EFEA', green='#BFE6A8', wood='#A8D98E', grass='#CBEBB2', golf='#BCE5A2', pitch='#C4EBAF', cemetery='#CDE9BA', military='#D5E8C6',
    sand='#F3E8C4', water='#8CCBF2', bld='#EAE7E2', bldo='#DDD9D2', air='#F1EFEA',
    minor='#FFFFFF', majc='#E0DCD3', majo='#FFFFFF', motc='#D2CEC4', moto='#FFFFFF', rail='#D8D4CC',
    lab='#33394A', labsoft='#6B7285', halo='#FFFFFF',
)


def paint(l, k, v):
    if k in l.get('paint', {}):
        l['paint'][k] = v


def recolour(style, c):
    for l in style['layers']:
        i, t = l['id'], l['type']
        if i == 'background':
            paint(l, 'background-color', c['bg'])
        elif i in ('landuse_residential', 'landcover_ice_shelf', 'landcover_glacier'):
            paint(l, 'fill-color', c['res'])
        elif i == 'park':
            paint(l, 'fill-color', c['green'])
        elif i == 'landcover_wood':
            paint(l, 'fill-color', c['wood'])
        elif i == 'land_grass':
            paint(l, 'fill-color', c['grass'])
        elif i == 'land_golf':
            paint(l, 'fill-color', c['golf'])
        elif i == 'land_pitch':
            paint(l, 'fill-color', c['pitch'])
        elif i == 'land_cemetery':
            paint(l, 'fill-color', c['cemetery'])
        elif i == 'land_military':
            paint(l, 'fill-color', c['military'])
        elif i == 'land_sand':
            paint(l, 'fill-color', c['sand'])
        elif i == 'water':
            paint(l, 'fill-color', c['water'])
        elif i == 'waterway':
            paint(l, 'line-color', c['water'])
        elif i == 'building':
            paint(l, 'fill-color', c['bld']); paint(l, 'fill-outline-color', c['bldo'])
        elif i in AIR:
            paint(l, 'fill-color', c['air']); paint(l, 'line-color', c['air'])
        elif i in MINOR:
            paint(l, 'line-color', c['rail'] if i.startswith('railway') else c['minor'])
        elif i.endswith('dashline'):
            paint(l, 'line-color', c['bg'])
        elif i in ('highway_major_casing', 'tunnel_motorway_casing'):
            paint(l, 'line-color', c['majc'])
        elif i == 'highway_major_inner':
            paint(l, 'line-color', c['majo'])
        elif i in ('highway_motorway_casing', 'highway_motorway_bridge_casing'):
            paint(l, 'line-color', c['motc'])
        elif i in ('highway_motorway_inner', 'highway_motorway_bridge_inner', 'tunnel_motorway_inner'):
            paint(l, 'line-color', c['moto'])
        elif t == 'symbol' and 'text-color' in l.get('paint', {}):
            soft = i in ('highway-name-path', 'highway-name-minor', 'waterway_line_label', 'water_name_point_label', 'water_name_line_label')
            l['paint']['text-color'] = c['labsoft'] if soft else c['lab']
            l['paint']['text-halo-color'] = c['halo']
    return style


for name, pal, title in (('dark', NIGHT, 'Bellinist night'), ('light', DAY, 'Bellinist day')):
    path = os.path.join(MAP, 'style-%s.json' % name)
    with open(path, encoding='utf-8') as f:
        style = json.load(f)
    style = recolour(style, pal)
    style['name'] = title
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(style, f, separators=(',', ':'), ensure_ascii=False)
    print('wrote', path)
