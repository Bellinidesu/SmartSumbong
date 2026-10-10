"""
The Shrine of St. Therese, modelled in Blender from a script:   blender --background --python build_shrine.py -- <out.npz> [<out.blend>]

The plan is the one read off the satellite view rotated to the building's axis (u along it, v across it, metres), the same numbers as sheets/shrine-of-st-therese.json; here the shapes
are Blender's own: real semicircular vaults from a cylinder cut in half, arches and niches cut out of walls with booleans (so they are recesses, not stickers), a mirror and an array
for the buttress ribs, a dome from a UV sphere with ribs. Materials are flat colours named after the map's tiles.
"""
import math
import sys

import bpy
import bmesh
from mathutils import Euler, Matrix, Vector

TH = math.radians(43.4)           # the building's axis, from east counter-clockwise
OUT = sys.argv[sys.argv.index('--') + 1] if '--' in sys.argv else 'shrine.npz'
BLEND = sys.argv[sys.argv.index('--') + 2] if len(sys.argv) > sys.argv.index('--') + 2 else None

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
root = bpy.data.objects.new('shrine', None)
scene.collection.objects.link(root)
root.rotation_euler = Euler((0, 0, TH))          # everything below is in (u, v, z); this turns it onto the map's east / north


def mat(name, hexcol):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    c = [int(hexcol[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    m.diffuse_color = (c[0], c[1], c[2], 1.0)
    return m


M = dict(
    wall=mat('plain.wall', 'D98B66'), vault=mat('plain.vault', 'E8D9B8'), roof=mat('plain.roof', 'E9DCC2'), rib=mat('plain.rib', 'F0E4C8'), dome=mat('plain.dome', 'A8503F'),
    dome2=mat('plain.dome2', '9A4637'), drum=mat('plain.drum', 'EAD9C0'), arch1=mat('plain.arch1', 'E9987A'), arch2=mat('plain.arch2', 'F6C9AE'), glass=mat('plain.glass', '33466F'),
    glow=mat('plain.glow', 'E8B965'), cream=mat('plain.cream', 'F3EBDD'), recess=mat('plain.recess', '5A4636'), bronze=mat('plain.bronze', '966C42'), solar=mat('plain.solar', '2E3A66'),
    green=mat('plain.green', '4F8A47'), dark=mat('plain.dark', '3B3F3A'), cross=mat('plain.cross', 'F2C14E'), ring_d=mat('plain.ring_d', '6A6670'), ring_p=mat('plain.ring_p', 'D9D4CC'),
    deck=mat('plain.deck', 'C9A98A'), terracotta=mat('plain.terracotta', 'C58660'), trunk=mat('plain.trunk', '7A5C3E'), leaf=mat('plain.leaf', '4C8A3F'), steel=mat('plain.steel', 'C9CDD2'),
)


def link(ob, material=None):
    scene.collection.objects.link(ob)
    ob.parent = root
    if material is not None:
        ob.data.materials.append(material)
    return ob


def box(name, u0, u1, v0, v1, z0, z1, material):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.scale = (u1 - u0, v1 - v0, z1 - z0)
    ob.location = ((u0 + u1) / 2, (v0 + v1) / 2, (z0 + z1) / 2)
    return link(ob, material)


def cylinder(name, x, y, z0, z1, r, material, verts=24, axis='z'):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=verts, radius1=r, radius2=r, depth=z1 - z0)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.location = (x, y, (z0 + z1) / 2)
    return link(ob, material)


def boolean(target, cutter, op='DIFFERENCE'):
    md = target.modifiers.new('cut', 'BOOLEAN')
    md.operation = op
    md.object = cutter
    md.solver = 'EXACT'
    cutter.hide_render = True
    cutter.display_type = 'WIRE'
    cutter.name = '_' + cutter.name           # the exporter skips objects whose name starts with an underscore


def barrel(name, axis, a0, a1, c0, c1, wall, vault_m, wall_m):
    """A semicircular barrel vault on straight walls: the straight walls are a box, the vault half a cylinder lying along `axis`."""
    W = c1 - c0
    R = W / 2
    L = a1 - a0
    if axis == 'u':
        b = box(name + '_walls', a0, a1, c0, c1, 0, wall, wall_m)
        cyl = cylinder(name + '_vault', 0, 0, -L / 2, L / 2, R, vault_m, 32)
        cyl.rotation_euler = Euler((0, math.pi / 2, 0))
        cyl.location = ((a0 + a1) / 2, (c0 + c1) / 2, wall)
    else:
        b = box(name + '_walls', c0, c1, a0, a1, 0, wall, wall_m)
        cyl = cylinder(name + '_vault', 0, 0, -L / 2, L / 2, R, vault_m, 32)
        cyl.rotation_euler = Euler((math.pi / 2, 0, 0))
        cyl.location = ((c0 + c1) / 2, (a0 + a1) / 2, wall)
    # only the upper half stands above the walls: cut the lower half off with a box
    lower = box('_lower', -500, 500, -500, 500, wall - R - 1, wall, vault_m)
    boolean(cyl, lower)
    return b, cyl


def arch_cutter(name, cx, cy, z, w, h, depth, facing, material=None):
    """The solid of an arched opening (a box with a half cylinder on top), to be subtracted from a wall. facing: the way the opening looks (0 +u, 90 +v, 180 -u, 270 -v), degrees."""
    R = w / 2
    leg = max(.2, h - R)
    body = box(name + '_leg', -w / 2, w / 2, -depth / 2, depth / 2, 0, leg, material or M['recess'])
    top = cylinder(name + '_top', 0, 0, -depth / 2, depth / 2, R, material or M['recess'], 24)
    top.rotation_euler = Euler((math.pi / 2, 0, 0))
    top.location = (0, 0, leg)
    holder = bpy.data.objects.new(name, None)
    scene.collection.objects.link(holder)
    holder.parent = root
    for ob in (body, top):
        ob.parent = holder
    holder.location = (cx, cy, z)
    holder.rotation_euler = Euler((0, 0, math.radians(facing) - math.pi / 2))
    return holder


# ------------------------------------------------------------------ the plan (u, v, metres), as in the sheet
nave = barrel('nave', 'u', -16, 36, -14.8, 4.4, 7.5, M['vault'], M['wall'])
sw = barrel('swarm', 'u', -51, -35, -14.8, 4.4, 7.5, M['vault'], M['wall'])
nw = barrel('nwarm', 'v', 5, 27, -33, -15.4, 7.5, M['vault'], M['wall'])
se = barrel('searm', 'v', -32.5, -15, -32.5, -14.4, 7.5, M['vault'], M['wall'])

# the buttress ribs along the nave, both sides
for k in range(8):
    u = -16 + 52 * k / 7
    for v in (-14.8 - .35, 4.4 + .35):
        box('rib', u - .35, u + .35, v - .35, v + .35, 0, 11.0, M['rib'])

# the big dome on its drum over the crossing
cx, cy = -26, -5.6
cylinder('drum', cx, cy, 12.5, 15.5, 9.8, M['drum'], 24)
bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=10, radius=9.8, location=(cx, cy, 15.85))
dome = bpy.context.active_object
dome.scale = (1, 1, 7.0 / 9.8)
bpy.context.scene.collection.objects.unlink(dome) if dome.name in bpy.context.scene.collection.objects else None
link(dome, M['dome'])
cut = box('_below', cx - 20, cx + 20, cy - 20, cy + 20, 0, 15.85, M['dome'])
boolean(dome, cut)

# the front towers with their drums and domes
for (u0, u1, v0, v1, cu, cv) in ((26, 36, 6, 16, 31, 11), (26.5, 36.5, -22, -12, 31.5, -17)):
    box('tower', u0, u1, v0, v1, 0, 10.0, M['wall'])
    cylinder('tdrum', cu, cv, 10.0, 13.4, 4.4, M['drum'], 16)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=4.4, location=(cu, cv, 13.75))
    d = bpy.context.active_object
    d.scale = (1, 1, 3.2 / 4.4)
    scene.collection.objects.unlink(d)
    link(d, M['dome'])
    boolean(d, box('_below2', cu - 6, cu + 6, cv - 6, cv + 6, 0, 13.75, M['dome']))

# the statue niches: a recess cut into the outer wall of each tower, with the bronze saint standing in it
for (u, v, facing) in ((31, 16, 90), (31.5, -22, 270)):
    tower = [o for o in root.children if o.name.startswith('tower')]
    cutter = arch_cutter('niche', u, v, 6.6, 2.3, 3.8, 1.6, facing)
    for t in tower:
        boolean(t, cutter) if False else None
    # (the cut itself is applied below to the tower nearest the niche)
    near = min(tower, key=lambda o: (o.location.x - u) ** 2 + (o.location.y - v) ** 2)
    md = near.modifiers.new('niche', 'BOOLEAN')
    md.operation = 'DIFFERENCE'
    md.object = cutter.children[0]
    md.solver = 'EXACT'
    md2 = near.modifiers.new('niche2', 'BOOLEAN')
    md2.operation = 'DIFFERENCE'
    md2.object = cutter.children[1]
    md2.solver = 'EXACT'
    for ch in cutter.children:
        ch.hide_render = True
        ch.name = '_' + ch.name
    th = math.radians(facing)
    sx, sy = u - math.cos(th) * .3, v - math.sin(th) * .3
    box('saint', sx - .3, sx + .3, sy - .2, sy + .2, 6.6, 9.0, M['bronze'])

# the flat roofs, the solar strips, the porch
box('aisle_nw', -10, 33, 4.4, 15, 0, 9.0, M['wall'])
box('aisle_se', -13, 26, -24, -14.8, 0, 9.0, M['wall'])
for (u0, u1, v0, v1, z) in ((-9, 29, 6, 14, 9.0), (-13, 26, -23, -15.6, 9.0)):
    box('solar', u0, u1, v0, v1, z + .6, z + .75, M['solar'])
box('porch_slab', 36, 44.5, -22, 16, 5.6, 6.5, M['deck'])
for v in (-21, -9, 7, 15):
    cylinder('column', 43.6, v, 0, 5.6, .6, M['wall'], 16)

# the pediment: stepped arches
for k in range(4):
    R = 9.5 - k * .9
    cyl = cylinder('pedi', 0, 0, 0, .65, R, M['arch1'] if k % 2 == 0 else M['arch2'], 40)
    cyl.rotation_euler = Euler((0, math.pi / 2, 0))
    cyl.location = (36 + k * .6, -5.2, 11.0)
    boolean(cyl, box('_pb%d' % k, 30, 50, -30, 30, 0, 11.0, M['arch1']))

# the hedges, the rings, the palms: left to the next pass in this file (the sheet has them)

bpy.ops.object.select_all(action='DESELECT')
if BLEND:
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
sys.argv = [sys.argv[0], '--', OUT]
exec(open(__file__.replace('build_shrine.py', 'export_model.py'), encoding='utf-8').read())
