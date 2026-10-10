"""The Barangay 183 Hall in Blender:  blender --background --python build_hall.py -- <out.npz> [<out.blend>]
From Ace's Street View shots (positions and headings read off their address bars) and the OpenStreetMap footprint: a three-storey pink block on a wedge-shaped corner plot, the front facing
south onto the junction of Manlunas and Mata Streets; an open ground floor under a green corrugated awning, green pilasters and horizontal green bands, a blue-grey glazed top floor, the name
in lettering on the parapet, a blue-teal turret on the right of the front, the rear stair block with its small ventilation windows and the water tank on the roof. Origin: the footprint's anchor."""
import json
import math
import os
import sys

import bpy
import bmesh
from mathutils import Euler

OUT = sys.argv[sys.argv.index('--') + 1] if '--' in sys.argv else 'hall.npz'
BLEND = sys.argv[sys.argv.index('--') + 2] if len(sys.argv) > sys.argv.index('--') + 2 else None
HERE = os.path.dirname(os.path.abspath(__file__))
RING = json.load(open(os.path.join(HERE, 'hall_ring.json')))

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene


def mat(name, hexcol):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    c = [int(hexcol[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    m.diffuse_color = (c[0], c[1], c[2], 1.0)
    return m


M = dict(pink=mat('plain.pink', 'EBA7A4'), pink2=mat('plain.pink2', 'DE8F90'), green=mat('plain.green', '6FAE5C'), dgreen=mat('plain.dgreen', '3E7A3A'), dark=mat('plain.dark', '3A3330'),
         glass=mat('plain.glass', '4E6C8E'), blue=mat('plain.blue', '3F8FA0'), cream=mat('plain.cream', 'F3E9DC'), grey=mat('plain.grey', 'B9BDC8'), red=mat('plain.red', 'C9544A'),
         awn=mat('plain.awn', '5E9B52'), steel=mat('plain.steel', 'C9CDD2'), tank=mat('plain.tank', 'D8DCE0'))


def add(ob, material):
    sc.collection.objects.link(ob)
    if material:
        ob.data.materials.append(material)
    return ob


def box(x0, x1, y0, y1, z0, z1, material, rot=0.0):
    me = bpy.data.meshes.new('b')
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new('b', me)
    ob.scale = (x1 - x0, y1 - y0, z1 - z0)
    ob.location = ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
    ob.rotation_euler = Euler((0, 0, rot))
    return add(ob, material)


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


def cyl(x, y, z0, z1, r, material, v=20):
    me = bpy.data.meshes.new('c')
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=v, radius1=r, radius2=r, depth=z1 - z0)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new('c', me)
    ob.location = (x, y, (z0 + z1) / 2)
    return add(ob, material)


def sign(text, x, y, z, w, h, nx, ny):
    sm = mat('sign:' + text, 'FFFFFF')
    px, py = -ny, nx
    a = (x - px * w / 2, y - py * w / 2, z)
    b = (x + px * w / 2, y + py * w / 2, z)
    me = bpy.data.meshes.new('s')
    me.from_pydata([a, b, (b[0], b[1], z + h), (a[0], a[1], z + h)], [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new(name='uv')
    for poly in me.polygons:
        for li, vi in zip(poly.loop_indices, poly.vertices):
            uv.data[li].uv = [(0, 0), (1, 0), (1, 1), (0, 1)][vi]
    add(bpy.data.objects.new('s', me), sm)


# ---- the mass: a ground floor (a little inside the plot), two upper floors flush with it
H1, H2, H3 = 3.8, 7.6, 11.4
ground = prism(RING, 0, H1, M['pink'])
upper = prism(RING, H1, H3, M['pink'])
box(-9.4, 9.6, -2.4, -1.5, H3, H3 + .55, M['dgreen'])                                   # the parapet cap along the front
prism([(0.1, 9.4), (-9.4, -.2), (-7.9, -2.0), (7.1, -2.4), (9.5, .2)], H3, H3 + .35, M['dgreen'])
# the roof: a low parapet round it, the water tank
cyl(2.6, 5.0, H3, H3 + 2.2, 1.1, M['tank'], 16)
cyl(-2.4, 4.4, H3, H3 + 1.8, .9, M['tank'], 16)

# ---- the front (south): y about -2.2 at x -7.7 .. 6.9. Open bay in the middle of the ground floor, green awning, pilasters, bands
FY = -2.25
box(-4.6, 3.6, FY - .12, FY + .02, .2, H1 - .2, M['dark'])                              # the open bay: a dark opening
for x in (-7.4, -4.9, 3.9, 6.6):
    box(x - .3, x + .3, FY - .35, FY, 0, H3, M['green'])                                  # green pilasters the full height
for x in (-1.0,):
    box(x - .22, x + .22, FY - .3, FY, 0, H1, M['green'])
awn = box(-8.0, 7.2, FY - 2.2, FY - .05, H1 - .1, H1 + .12, M['awn'], 0.0)              # the corrugated awning, tilted down to the street
awn.rotation_euler = Euler((math.radians(-7), 0, 0))
awn.location.y = FY - 1.1
for z in (H1 + .9, H2 + .9):                                                              # horizontal green bands on the upper floors
    box(-8.0, 7.2, FY - .22, FY, z, z + .5, M['green'])
for k, x in enumerate((-6.6, -3.0, .6, 4.2)):                                             # the glazed upper floors: dark blue panes in the green frames
    for (zz, hh) in ((H1 + 1.6, 1.5), (H2 + 1.2, 1.9)):
        box(x - 1.2, x + 1.2, FY - .1, FY, zz, zz + hh, M['glass'])
box(-8.0, 7.2, FY - .2, FY, H3 - .7, H3, M['cream'])                                      # the lettering band
sign('BARANGAY 183', -.4, FY - .22, H3 - .65, 12.0, 1.4, 0, -1)
sign('183', 4.6, FY - .24, H2 + 2.2, 3.4, 2.6, 0, -1)

# ---- the blue-teal turret on the right of the front, and its cap
cyl(8.4, -2.3, H1, H2 + 1.6, 1.5, M['pink2'], 20)
cyl(8.4, -2.3, H2 + 1.6, H2 + 2.0, 1.7, M['blue'], 20)

# ---- the sides and rear: small square windows with ventilation fans on the east side, the stair block at the north apex
for x in (2.0, 3.6, 5.2, 6.8, 8.4):
    box(x - .4, x + .4, -.25, .1, H2 + 1.1, H2 + 2.0, M['dark'])
for z in (H1 + 1.5, H2 + 1.1):
    for k in range(5):
        t = (k + .5) / 5
        px, py = 9.3 + (0.1 - 9.3) * t, .2 + (9.4 - .2) * t
        box(px - .5, px + .5, py - .1, py + .1, z, z + 1.1, M['dark'], math.radians(-45))
stair = box(-3.2, 3.0, 5.6, 9.0, H3, H3 + 3.2, M['pink2'])
box(-3.4, 3.2, 5.4, 9.2, H3 + 3.2, H3 + 3.5, M['green'])

# ---- the green fence along the front of the plot, the steps
for x in range(-9, 10):
    box(x - .04, x + .04, FY - 3.6, FY - 3.5, 0, 1.8, M['dgreen'])
box(-9.6, 9.8, FY - 3.6, FY - 3.5, 1.6, 1.7, M['dgreen'])
box(-9.6, 9.8, FY - 3.6, FY - 3.5, 0.2, 0.3, M['dgreen'])

# the plot's front faces about south-south-west (compass 200 degrees), read from the camera positions of shots 270 and 271; the OSM footprint is rough, so the whole building is turned onto it
root = bpy.data.objects.new('hall', None)
sc.collection.objects.link(root)
root.rotation_euler = Euler((0, 0, math.radians(-20)))
root.location = (-3.2, 4.6, 0)
for ob in list(sc.objects):
    if ob is not root:
        ob.parent = root
if BLEND:
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
sys.argv = [sys.argv[0], '--', OUT]
exec(open(os.path.join(HERE, 'export_model.py'), encoding='utf-8').read())
