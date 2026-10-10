"""The Barangay 183 Hall in Blender:  blender --background --python build_hall.py -- <out.npz> [<out.blend>]
From Ace's Street View shots 266 to 273 (cameras read off their address bars) and the OpenStreetMap footprint. Made with what Blender is for: windows cut into the wall (boolean) with the glass
set back in the recess, real 3D lettering from a font (extruded text, not a picture), a curved front roof (a cylinder segment), bevelled edges, a corrugated awning (an array of ribs),
louvre fins on the number panel, a pink turret. Origin: the footprint's anchor; the whole building is turned onto the way the cameras show it faces."""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler

OUT = sys.argv[sys.argv.index('--') + 1] if '--' in sys.argv else 'hall.npz'
BLEND = sys.argv[sys.argv.index('--') + 2] if len(sys.argv) > sys.argv.index('--') + 2 else None
HERE = os.path.dirname(os.path.abspath(__file__))
RING = json.load(open(os.path.join(HERE, 'hall_ring.json')))
FONT = 'C:/Windows/Fonts/arialbd.ttf'

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene


def mat(name, hexcol):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    c = [int(hexcol[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    m.diffuse_color = (c[0], c[1], c[2], 1.0)
    return m


M = dict(pink=mat('plain.pink', 'EDA9A6'), pink2=mat('plain.pink2', 'DE8F90'), roofc=mat('plain.roofc', 'C9B9B4'), green=mat('plain.green', '6FAE5C'), dgreen=mat('plain.dgreen', '3E7A3A'),
         dark=mat('plain.dark', '2F2A28'), glass=mat('plain.glass', '3F5A7A'), blue=mat('plain.blue', '3F8FA0'), cream=mat('plain.cream', 'F3E9DC'), grey=mat('plain.grey', 'B4B8C0'),
         awn=mat('plain.awn', '5E9B52'), steel=mat('plain.steel', 'C9CDD2'), tank=mat('plain.tank', 'D8DCE0'), letter=mat('plain.letter', 'D7545A'), letter2=mat('plain.letter2', '5FA050'))


def add(ob, material):
    sc.collection.objects.link(ob)
    if material:
        ob.data.materials.append(material)
    return ob


def bevel(ob, w=.07, seg=1):
    md = ob.modifiers.new('bev', 'BEVEL')
    md.width = w
    md.segments = seg
    md.limit_method = 'ANGLE'
    md.angle_limit = math.radians(40)
    return ob


def box(x0, x1, y0, y1, z0, z1, material, rot=0.0, bev=0.0):
    me = bpy.data.meshes.new('b')
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new('b', me)
    ob.scale = (x1 - x0, y1 - y0, z1 - z0)
    ob.location = ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
    ob.rotation_euler = Euler((0, 0, rot))
    add(ob, material)
    if bev:
        bevel(ob, bev)
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


def cyl(x, y, z0, z1, r, material, v=24):
    me = bpy.data.meshes.new('c')
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=v, radius1=r, radius2=r, depth=z1 - z0)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new('c', me)
    ob.location = (x, y, (z0 + z1) / 2)
    return add(ob, material)


def cutter(boxes, name='_cut'):
    """One object holding many boxes (x0, x1, y0, y1, z0, z1), to subtract from a wall in one boolean."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    for (x0, x1, y0, y1, z0, z1) in boxes:
        r = bmesh.ops.create_cube(bm, size=1.0)
        vs = r['verts']
        bmesh.ops.scale(bm, vec=(x1 - x0, y1 - y0, z1 - z0), verts=vs)
        bmesh.ops.translate(bm, vec=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), verts=vs)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    sc.collection.objects.link(ob)
    ob.hide_render = True
    return ob


def subtract(host, cut):
    md = host.modifiers.new('cut', 'BOOLEAN')
    md.operation = 'DIFFERENCE'
    md.object = cut
    md.solver = 'EXACT'


def text(body, x, y, z, width, height, material, rot=0.0, depth=.12, align='CENTER'):
    """Real 3D lettering standing on the front (facing -y): a font, extruded; scaled to the given width."""
    c = bpy.data.curves.new('t', 'FONT')
    c.body = body
    c.font = bpy.data.fonts.load(FONT)
    c.extrude = depth
    c.size = height
    c.align_x = align
    c.resolution_u = 3
    ob = bpy.data.objects.new('t', c)
    sc.collection.objects.link(ob)
    ob.data.materials.append(material)
    bpy.context.view_layer.update()
    w0 = max(ob.dimensions.x, .01)
    ob.scale = (width / w0, 1, 1)
    ob.rotation_euler = Euler((math.pi / 2, 0, rot))
    ob.location = (x, y, z)
    return ob


# ------------------------------------------------------------------ the mass
H1, H2, H3 = 3.8, 7.6, 11.4
FY = -2.25                                                          # the front wall's line
ground = prism(RING, 0, H1, M['pink'])
upper = prism(RING, H1, H3, M['pink'])
bevel(upper, .08)

cuts, panes = [], []
for x in (-6.9, -3.3, .3, 3.9):
    for (zz, hh) in ((H1 + 1.5, 1.7), (H2 + 1.2, 2.0)):
        cuts.append((x - 1.15, x + 1.15, FY - 1.0, FY + .55, zz, zz + hh))
        panes.append((x - 1.15, x + 1.15, zz, zz + hh))
subtract(upper, cutter(cuts))
for (xa, xb, za, zb) in panes:
    box(xa + .05, xb - .05, FY + .5, FY + .6, za + .05, zb - .05, M['glass'])
    for j in range(1, 4):
        xx = xa + (xb - xa) * j / 4
        box(xx - .03, xx + .03, FY + .38, FY + .5, za + .05, zb - .05, M['dgreen'])
    for (a, b, c, d) in ((xa, xb, za, za + .1), (xa, xb, zb - .1, zb), (xa, xa + .1, za, zb), (xb - .1, xb, za, zb)):
        box(a, b, FY + .2, FY + .55, c, d, M['dgreen'])
subtract(ground, cutter([(-4.7, 3.7, FY - 1.0, FY + 1.6, .25, H1 - .3)]))
box(-4.5, 3.5, FY + .9, FY + 1.0, .3, H1 - .35, M['dark'])

for x in (-7.5, -5.0, 4.1, 6.7, -1.0):
    box(x - .32, x + .32, FY - .38, FY, 0, H3 - .2, M['green'], bev=.05)
for z in (H1 + .85, H2 + .85):
    box(-8.0, 7.4, FY - .25, FY, z, z + .5, M['green'], bev=.04)
for k in range(32):                                                   # the corrugated awning: ribs on a slanted sheet
    xr = -8.1 + k * 0.5
    r = box(xr, xr + .14, FY - 2.4, FY + .05, H1 - .05, H1 + .16, M['awn'])
    r.rotation_euler = Euler((math.radians(-9), 0, 0))
    r.location.y = FY - 1.15
    r.location.z = H1 + .3
    s = box(xr + .14, xr + .5, FY - 2.4, FY + .05, H1 - .05, H1 + .06, M['awn'])
    s.rotation_euler = Euler((math.radians(-9), 0, 0))
    s.location.y = FY - 1.15
    s.location.z = H1 + .26
for x in (-7.9, -4.0, 0.0, 4.0, 7.2):
    box(x - .06, x + .06, FY - 2.25, FY - 2.15, 0, H1 - .25, M['dgreen'])

# ------------------------------------------------------------------ the top: a curved roof over the front, the flat roof, the lettering
R = 3.2
arc = cyl(0, 0, -10, 10, R, M['green'], 32)
arc.rotation_euler = Euler((0, math.pi / 2, 0))
arc.scale = (.62, 1.0, 1.0)
arc.location = (-.4, FY + 1.1, H3 + .2)
lower = box(-12, 12, -8, 8, H3 - 5, H3 + .2, M['green'])
lower.hide_render = True
lower.name = '_lower'
subtract(arc, lower)
prism([(.1, 9.2), (-9.2, -.2), (-7.7, -1.8), (6.9, -2.2), (9.3, .2)], H3, H3 + .3, M['roofc'])
box(-8.6, 7.8, FY - .3, FY + .25, H3 - 1.5, H3 - .05, M['cream'])
text('BARANGAY 183', -.4, FY - .33, H3 - 1.25, 11.5, .95, M['letter'])
box(-.2, 7.4, FY - .3, FY - .22, H2 + .3, H3 - 1.7, M['cream'])
for k in range(8):
    z = H2 + .4 + k * .26
    box(-.2, 1.7, FY - .36, FY - .26, z, z + .1, M['letter2'])
    box(5.4, 7.4, FY - .36, FY - .26, z, z + .1, M['letter2'])
text('183', 3.6, FY - .38, H2 + .55, 3.2, 2.1, M['letter2'], depth=.1)

cyl(8.5, -2.4, H1, H2 + 1.8, 1.55, M['pink2'], 28)
cyl(8.5, -2.4, H2 + 1.8, H2 + 2.2, 1.78, M['blue'], 28)
cyl(8.5, -2.4, H1 + 1.2, H1 + 1.5, 1.7, M['green'], 28)

# ------------------------------------------------------------------ rear and sides
for z in (H1 + 1.5, H2 + 1.1):
    for k in range(5):
        t = (k + .5) / 5
        px, py = 9.3 + (0.1 - 9.3) * t, .2 + (9.4 - .2) * t
        box(px - .5, px + .5, py - .12, py + .12, z, z + 1.1, M['dark'], math.radians(-45))
for x in (1.9, 3.5, 5.1, 6.7):
    box(x - .4, x + .4, -.3, .05, H2 + 1.1, H2 + 2.0, M['dark'])
box(-3.2, 3.0, 5.6, 9.0, H3 + .3, H3 + 3.4, M['pink2'], bev=.06)
box(-3.4, 3.2, 5.4, 9.2, H3 + 3.4, H3 + 3.7, M['green'])
cyl(2.6, 4.2, H3 + .3, H3 + 2.6, 1.1, M['tank'], 20)
cyl(-2.4, 3.6, H3 + .3, H3 + 2.1, .9, M['tank'], 20)
for rr in (.6, 1.4, 2.2):
    cyl(2.6, 4.2, H3 + .3 + rr, H3 + .3 + rr + .08, 1.14, M['steel'], 20)

for x in range(-9, 11):
    box(x - .04, x + .04, FY - 3.7, FY - 3.58, 0, 1.9, M['dgreen'])
box(-9.4, 10.2, FY - 3.7, FY - 3.58, 1.75, 1.88, M['dgreen'])
box(-9.4, 10.2, FY - 3.7, FY - 3.58, .2, .3, M['dgreen'])

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
