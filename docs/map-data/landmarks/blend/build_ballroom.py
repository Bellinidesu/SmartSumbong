"""The Marriott Grand Ballroom building (OpenStreetMap way 310487805) in Blender:  blender --background --python build_ballroom.py -- <out.npz> [<out.blend>]
Brief from Gemini (via Ace), checked against the open data: the OSM outer polygon is the footprint (28 nodes, 212 x 63 m, 10,439 m2, height 36 m: not the ~110 x 70 m the brief says), extruded;
an angled roof canopy with a 4 m overhang tilted 5 degrees; an enclosed truss skybridge from the Ballroom to the Marriott West Wing building across the gap between them (the brief's 26 m / 5 m /
4.5 m is used for its width, height and truss, its position is the nearest points of the two OSM polygons: nothing in the open data places a skybridge, so it is a draft to check against
Street View). Origin: the polygon's middle (way310487805.json)."""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Vector

OUT = sys.argv[sys.argv.index('--') + 1] if '--' in sys.argv else 'ballroom.npz'
BLEND = sys.argv[sys.argv.index('--') + 2] if len(sys.argv) > sys.argv.index('--') + 2 else None
HERE = os.path.dirname(os.path.abspath(__file__))
D = json.load(open(os.path.join(HERE, 'way310487805.json')))
RING = [tuple(p) for p in D['ring']]
HEIGHT = float(D['tags'].get('height', 36))
OTHER = D.get('west_wing')               # the West Wing's ring in the same frame

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene


def mat(name, hexcol):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    c = [int(hexcol[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    m.diffuse_color = (c[0], c[1], c[2], 1.0)
    return m


M = dict(stone=mat('plain.stone', 'DCC9A8'), roof=mat('plain.roof', 'A9ADB4'), glass=mat('plain.glass', '7F98B0'), steel=mat('plain.steel', 'C9CDD2'), wing=mat('plain.wing', 'D9A590'))


def add(ob, m):
    sc.collection.objects.link(ob)
    ob.data.materials.append(m)
    return ob


def prism(ring, z0, z1, material):
    me = bpy.data.meshes.new('p')
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, z0)) for x, y in ring]
    f = bm.faces.new(vs)
    if f.normal.z < 0:
        f.normal_flip()
    r = bmesh.ops.extrude_face_region(bm, geom=[f])
    top = [v for v in r['geom'] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0, 0, z1 - z0), verts=top)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    return add(bpy.data.objects.new('p', me), material)


def box(cx, cy, cz, lx, ly, lz, yaw, material):
    me = bpy.data.meshes.new('b')
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new('b', me)
    ob.scale = (lx, ly, lz)
    ob.location = (cx, cy, cz)
    ob.rotation_euler = Euler((0, 0, yaw))
    return add(ob, material)


# 1. the building: the OSM polygon, extruded to its height
prism(RING, 0, HEIGHT - 2.5, M['stone'])

# 2. the roof: the same polygon grown by the overhang, as a slab tilted 5 degrees about its long axis (higher on the back, so the overhang reads as an angled canopy), 2.5 m thick
DV = D['derived']                          # the roof outline, the long axis, the centroid and the bridge ends are worked out outside Blender (it has no shapely)
roof = prism([tuple(p) for p in DV['roof']], 0, 2.5, M['roof'])
ang = DV['axis']
c = Vector((DV['centroid'][0], DV['centroid'][1], 0))
roof.location = (0, 0, HEIGHT - 2.5)
# tilt about the long axis through the centroid: rotate the object's frame
roof.rotation_euler = Euler((0, 0, 0))
bpy.context.view_layer.update()
tilt = math.radians(5.0)
axis = Vector((math.cos(ang), math.sin(ang), 0))
import mathutils
R = mathutils.Matrix.Rotation(tilt, 4, axis)
T = mathutils.Matrix.Translation((c.x, c.y, 0))
roof.matrix_world = T @ R @ T.inverted() @ roof.matrix_world

# 3. the skybridge: an enclosed truss box between the nearest points of this building and the West Wing
if OTHER:
    a = Vector((DV['bridge'][0][0], DV['bridge'][0][1], 0))
    b = Vector((DV['bridge'][1][0], DV['bridge'][1][1], 0))
    gap = (b - a).length
    d = Vector((b.x - a.x, b.y - a.y, 0))
    ln = d.length
    yaw = math.atan2(d.y, d.x)
    mid = ((a.x + b.x) / 2, (a.y + b.y) / 2)
    z0 = 6.0
    box(mid[0], mid[1], z0 + 2.25, ln + 1.0, 5.0, 4.5, yaw, M['steel'])                     # the enclosed tube
    box(mid[0], mid[1], z0 + 2.4, ln + 1.1, 5.1, 1.6, yaw, M['glass'])                      # its band of glazing
    for k in range(int(ln // 4) + 1):                                                      # truss frames every 4 m
        t = k * 4.0 / max(ln, 1)
        px, py = a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t
        box(px, py, z0 + 2.25, .25, 5.2, 4.7, yaw, M['steel'])
    prism([tuple(p) for p in OTHER], 0, 35.0, M['wing'])
    print('skybridge: gap %.1f m between the two buildings' % gap)

root = bpy.data.objects.new('ballroom', None)
sc.collection.objects.link(root)
for ob in list(sc.objects):
    if ob is not root:
        ob.parent = root
if BLEND:
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
sys.argv = [sys.argv[0], '--', OUT]
exec(open(os.path.join(HERE, 'export_model.py'), encoding='utf-8').read())
