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

# ================================================================ the rest of the Street View shots, in the same plan
def mesh_obj(name, verts, faces, material, uvs=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    if uvs:
        uv = me.uv_layers.new(name='uv')
        for poly in me.polygons:
            for li, vi in zip(poly.loop_indices, poly.vertices):
                uv.data[li].uv = uvs[vi]
    ob = bpy.data.objects.new(name, me)
    return link(ob, material)


def cut(host, holder):
    """Subtract an arch cutter (a holder with a leg and a top) from a wall."""
    for ch in list(holder.children):
        md = host.modifiers.new('cut', 'BOOLEAN')
        md.operation = 'DIFFERENCE'
        md.object = ch
        md.solver = 'EXACT'
        ch.hide_render = True
        ch.name = '_' + ch.name


def facing_vec(f):
    return math.cos(math.radians(f)), math.sin(math.radians(f))


def stepped(u, v, facing, width, z, wall_h, k=4, glass=True, cross=False):
    """Concentric stepped arches standing on a wall end, each a little proud of the one behind and lighter at the edge; a framed stained-glass arch with two small side arches."""
    nx, ny = facing_vec(facing)
    px, py = -ny, nx
    for i in range(k):
        R = width / 2 - i * .9
        cy_ = cylinder('step', 0, 0, 0, .6, R, M['arch1'] if i % 2 == 0 else M['arch2'], 40)
        cy_.rotation_euler = Euler((math.pi / 2, 0, math.radians(facing) - math.pi / 2))
        cy_.location = (u + nx * (.3 + i * .6), v + ny * (.3 + i * .6), z + wall_h)
        boolean(cy_, box('_sb%d' % i, -60, 60, -60, 60, z + wall_h - 40, z + wall_h, M['arch1']))
        lg = box('step_leg', -R, R, -.3, .3, z, z + wall_h, M['arch1'] if i % 2 == 0 else M['arch2'])
        lg.location = (u + nx * (.3 + i * .6), v + ny * (.3 + i * .6), z + wall_h / 2)
        lg.scale = (2 * R, .6, wall_h)
        lg.rotation_euler = Euler((0, 0, math.radians(facing) - math.pi / 2))
    if not glass:
        return
    off = k * .6 + .1
    for (du, w, h, base) in ((0, width * .34, wall_h * .5 + width * .17, 1.0), (-width * .31, width * .13 * 2, wall_h * .22 + width * .13, 1.0), (width * .31, width * .13 * 2, wall_h * .22 + width * .13, 1.0)):
        for (m_, grow, d) in ((M['cream'], .3, 0.0), (M['glass'], 0.0, .14)):
            h_ = h + grow * (.7 if w < 4 else 1)
            ww = w + grow
            Rr = ww / 2
            leg = max(.2, h_ - Rr)
            cx, cy = u + nx * (off + d) + px * du, v + ny * (off + d) + py * du
            b = box('gw', -ww / 2, ww / 2, -.07, .07, 0, leg, m_)
            b.location = (cx, cy, z + base + leg / 2 - grow * .3)
            b.scale = (ww, .14, leg)
            b.rotation_euler = Euler((0, 0, math.radians(facing) - math.pi / 2))
            t = cylinder('gwt', 0, 0, -.07, .07, Rr, m_, 20)
            t.rotation_euler = Euler((math.pi / 2, 0, math.radians(facing) - math.pi / 2))
            t.location = (cx, cy, z + base + leg - grow * .3)
    if cross:
        top = z + wall_h + width / 2
        box('cross_v', u - .15, u + .15, v - .15, v + .15, top, top + 3.2, M['cross'])
        box('cross_h', u - .15, u + .15, v - 1.0, v + 1.0, top + 2.0, top + 2.4, M['cross'])


def niche(u, v, facing, z, w, h, host, statue=True, recess='recess', balcony=False):
    nx, ny = facing_vec(facing)
    holder = arch_cutter('niche', u, v, z, w, h, 1.6, facing)
    cut(host, holder)
    # a cream frame proud of the wall round the opening
    R = w / 2 + .22
    leg = max(.3, h - w / 2)
    fr = box('frame', -R, R, -.08, .08, 0, leg, M['cream'])
    fr.location = (u + nx * .05, v + ny * .05, z - .1 + leg / 2)
    fr.scale = (2 * R, .16, leg + .1)
    fr.rotation_euler = Euler((0, 0, math.radians(facing) - math.pi / 2))
    ft = cylinder('frame_t', 0, 0, -.08, .08, R, M['cream'], 20)
    ft.rotation_euler = Euler((math.pi / 2, 0, math.radians(facing) - math.pi / 2))
    ft.location = (u + nx * .05, v + ny * .05, z + leg - .1)
    if statue:
        box('saint', u - nx * .3 - .3, u - nx * .3 + .3, v - ny * .3 - .22, v - ny * .3 + .22, z + .2, z + 2.7, M['bronze'])
    else:
        gl_ = box('niche_glass', u - nx * .5 - .3, u - nx * .5 + .3, v - ny * .5 - .3, v - ny * .5 + .3, z + .2, z + h - .3, M[recess] if recess in M else M['glass'])
    if balcony:
        b = box('balcony', u + nx * .5 - (w + .8) / 2, u + nx * .5 + (w + .8) / 2, v + ny * .5 - .5, v + ny * .5 + .5, z - 1.2, z - 1.02, M['cream'])
        b.rotation_euler = Euler((0, 0, 0))


def palm(u, v, z, h):
    cylinder('palm_trunk', u, v, z, z + h, .17, M['trunk'], 6)
    for k in range(9):
        a = 2 * math.pi * k / 9 + u * 1.7 + v * 2.3
        L = 2.6 * (.85 + .3 * ((k * 37) % 7) / 7)
        ca, sa = math.cos(a), math.sin(a)
        tip = (u + ca * L, v + sa * L, z + h - .9)
        mid = (u + ca * L * .55, v + sa * L * .55, z + h + .25)
        wl = (-sa * .42, ca * .42)
        mesh_obj('frond', [(u, v, z + h), (mid[0] + wl[0], mid[1] + wl[1], mid[2]), tip, (mid[0] - wl[0], mid[1] - wl[1], mid[2])], [(0, 1, 2, 3)], M['leaf'])


def sign(text, u, v, facing, z, w, h):
    nx, ny = facing_vec(facing)
    px, py = -ny, nx
    sm = mat('sign:' + text, 'FFFFFF')
    a = (u - px * w / 2, v - py * w / 2, z)
    b = (u + px * w / 2, v + py * w / 2, z)
    verts = [a, b, (b[0], b[1], z + h), (a[0], a[1], z + h)]
    mesh_obj('sign', verts, [(0, 1, 2, 3)], sm, uvs=[(0, 0), (1, 0), (1, 1), (0, 1)])


def louvres(u, v, facing, z, w, h, dark='3A4048', slat='DADDE0'):
    nx, ny = facing_vec(facing)
    th = math.radians(facing)
    dm, sm = mat('plain.l_dark_' + dark, dark), mat('plain.l_slat_' + slat, slat)
    pb = box('louvre_back', 0, 0, 0, 0, 0, 0, dm)
    pb.scale = (.1, w, h)
    pb.location = (u + nx * .06, v + ny * .06, z + h / 2)
    pb.rotation_euler = Euler((0, 0, th))
    n = max(3, int(h / .32))
    for k in range(n):
        sl = box('slat', 0, 0, 0, 0, 0, 0, sm)
        sl.scale = (.08, w - .2, .12)
        sl.location = (u + nx * .14, v + ny * .14, z + .1 + k * (h - .2) / n)
        sl.rotation_euler = Euler((0, 0, th))


def hedge(u0, v0, u1, v1, h, w=1.4):
    ln = math.hypot(u1 - u0, v1 - v0)
    b = box('hedge', 0, 0, 0, 0, 0, 0, M['green'])
    b.scale = (ln, w, h)
    b.location = ((u0 + u1) / 2, (v0 + v1) / 2, h / 2)
    b.rotation_euler = Euler((0, 0, math.atan2(v1 - v0, u1 - u0)))


def rings(u, v, r0, r1, n, z=.1):
    for i in range(n, 0, -1):
        R = r0 + (r1 - r0) * i / n
        cylinder('ring', u, v, z, z + .02 * (n - i + 1), R, M['ring_d'] if i % 2 == 0 else M['ring_p'], 40)


# ---- the porch: a colonnade, a dark ground floor with the glazed shop front, the fascia and its lettering, palms on its roof
box('porch_back', 36, 38, -22, 16, 0, 5.6, M['dark'])
box('shop_glass', 38, 39.2, -9, 7, 0, 4.6, M['cream'])
box('porch_parapet', 36, 44.5, -22, 16, 6.5, 7.0, M['green'])
box('fascia', 44.4, 44.8, -22, 16, 4.6, 5.6, M['wall'])
sign('MILITARY ORDINARIATE OF THE PHILIPPINES', 44.85, -1, 0, 4.7, 22, 1.2)
sign('SHRINE OF ST. THERESE', 36.8, -5.2, 0, 7.3, 11, 1.3)
for k, vv in enumerate((-20, -16, -12, 9, 13)):
    palm(41.5 + (k % 2) * .8, vv, 6.5, 5.5 + (k % 3) * .8)

# ---- the pediment's saint on its plinth, and the cross
box('plinth', 35.4, 36.4, -5.8, -4.6, 20.3, 21.2, M['cream'])
box('saint_top', 35.6, 36.2, -5.5, -4.9, 21.2, 24.0, M['arch2'])
box('cross_v', 35.85, 36.15, -5.35, -5.05, 24.0, 26.0, M['cross'])
box('cross_h', 35.85, 36.15, -5.9, -4.5, 25.2, 25.5, M['cross'])

# ---- the stepped arch on the end of every arm, with its stained glass
stepped(-51, -5.2, 180, 19.2, 0, 7.5)
stepped(-24.2, 27, 90, 17.6, 0, 7.5)
stepped(-23.2, -32.5, 270, 18.1, 0, 7.5)

# ---- the niches: the statue niche in each front tower (cut), the small stained-glass ones, the arched windows of the corner blocks
towers = [o for o in root.children if o.name.startswith('tower')]
t_nw = min(towers, key=lambda o: (o.location.x - 31) ** 2 + (o.location.y - 11) ** 2)
t_se = min(towers, key=lambda o: (o.location.x - 31.5) ** 2 + (o.location.y + 17) ** 2)
# (the first two statue niches were already cut above; the small stained-glass niches on the tower fronts)
niche(36, 11, 0, 6.8, 1.6, 2.6, t_nw, statue=False, recess='glass')
niche(36.5, -17, 0, 6.8, 1.6, 2.6, t_se, statue=False, recess='glass')

# ---- the dome drums: eight framed arched windows each, a lantern and a cross on the big dome and each small one
for (cx_, cy_, R, z0, dh) in ((-26, -5.6, 9.8, 12.5, 3.0), (31, 11, 4.4, 10.0, 3.4), (31.5, -17, 4.4, 10.0, 3.4)):
    for k in range(8):
        a = 2 * math.pi * k / 8
        w_ = min(1.3, R * .26)
        for (mm, off, hh, ww) in ((M['cream'], .04, dh * .6, w_), (M['glass'], .09, dh * .46, w_ * .7)):
            b = box('dw', 0, 0, 0, 0, 0, 0, mm)
            b.scale = (.1, ww, hh)
            b.location = (cx_ + math.cos(a) * (R + off), cy_ + math.sin(a) * (R + off), z0 + dh * .2 + hh / 2 + (0 if mm is M['cream'] else dh * .06))
            b.rotation_euler = Euler((0, 0, a))
big = (-26, -5.6, 12.5 + 3.0 + .35 + 7.0)
for (cx_, cy_, ztop, lr) in ((-26, -5.6, big[2], 1.2), (31, 11, 10 + 3.4 + 3.2, .6), (31.5, -17, 10 + 3.4 + 3.2, .6)):
    cylinder('lantern', cx_, cy_, ztop - .1, ztop + lr * 3, lr, M['drum'], 10)
    box('lc_v', cx_ - .07, cx_ + .07, cy_ - .07, cy_ + .07, ztop + lr * 3, ztop + lr * 3 + 2.0, M['cross'])
    box('lc_h', cx_ - .07, cx_ + .07, cy_ - .5, cy_ + .5, ztop + lr * 3 + 1.2, ztop + lr * 3 + 1.35, M['cross'])

# ---- the trellis annexes along both long sides: a two-storey terracotta block with a hedge in front, arched windows cut behind a wire mesh, planters on the roof
annex_nw = box('annex_nw', -10, 36, 15, 29, 0, 7.5, M['wall'])
annex_se = box('annex_se', 7, 30, -34, -24, 0, 7.5, M['wall'])
for (host, u0, u1, v, facing) in ((annex_nw, -10, 36, 29, 90), (annex_se, 7, 30, -34, 270)):
    n = int((u1 - u0) // 4)
    for k in range(n):
        uu = u0 + (u1 - u0) * (k + .5) / n
        cut(host, arch_cutter('win', uu, v, 2.2, 2.4, 3.8, 1.6, facing))
    for k in range(n + 1):
        uu = u0 + (u1 - u0) * k / n
        nx_, ny_ = facing_vec(facing)
        box('post', uu - .25, uu + .25, v + ny_ * .25 - .25, v + ny_ * .25 + .25, 0, 7.3, M['wall'])
    mesh = box('mesh', u0, u1, v + (facing == 90) * .05 - (facing == 270) * .05 - .04, v + (facing == 90) * .05 - (facing == 270) * .05 + .04, 2.6, 6.6, M['green'])
    va, vb = (15.3, 28.7) if facing == 90 else (-33.7, -24.3)
    for (a0, a1, b0, b1) in ((u0 + .3, u1 - .3, va, va + .6), (u0 + .3, u1 - .3, vb - .6, vb), (u0 + .3, u0 + .9, va, vb), (u1 - .9, u1 - .3, va, vb)):
        box('planter', a0, a1, b0, b1, 7.5, 8.05, M['dark'])
box('solar', -9, 29, 17, 28, 8.1, 8.25, M['solar'])
box('aisle_roof_se', 7, 30, -34, -24, 7.5, 7.7, M['terracotta'])
hedge(-12, 30.2, 37, 30.2, 3.0)
hedge(7, -35.2, 31, -35.2, 3.0)

# ---- the low corner blocks at the south-west end, their arched windows and louvres
blk_nw = box('corner_nw', -51, -34, 7.5, 25, 0, 6.0, M['wall'])
blk_se = box('corner_se', -51, -32, -33, -15, 0, 6.0, M['wall'])
box('corner_nw_roof', -51, -34, 7.5, 25, 6.0, 6.2, M['terracotta'])
box('corner_se_roof', -51, -32, -33, -15, 6.0, 6.2, M['terracotta'])
niche(-33, 25, 90, 0.6, 3.6, 4.6, blk_nw, statue=False, recess='glass')
niche(-35, -33, 270, 0.6, 3.6, 4.6, blk_se, statue=False, recess='glass')
louvres(-44, -33.1, 270, 1.0, 4.2, 3.2)
louvres(-44, 25.1, 90, 1.0, 4.2, 3.2)
louvres(20, -34.1, 270, 1.0, 2.2, 4.2, '3F5F8F', '7FA0CF')
louvres(30, 29.1, 90, 1.0, 2.2, 4.2, '3F5F8F', '7FA0CF')

# ---- the billboard on its steel frame, the paving rings on both ramps
bb = box('billboard', 0, 0, 0, 0, 0, 0, mat('plain.bill', 'D9B592'))
bb.scale = (14, .25, 8)
bb.location = (15, -33.2, 7.7 + 1.0 + 4)
for k in range(4):
    box('bb_brace', 15 - 7 + (k + .5) * 3.5 - .05, 15 - 7 + (k + .5) * 3.5 + .05, -33.0, -32.8, 8.7, 16.7, M['steel'])
for vv in (-6.5, 6.5):
    box('bb_leg', 15 + vv - .1, 15 + vv + .1, -33.5, -33.3, 7.5, 8.9, M['steel'])
rings(43, 21, 2.5, 12, 6)
rings(44, -24, 2.5, 12, 6)

bpy.ops.object.select_all(action='DESELECT')
if BLEND:
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
sys.argv = [sys.argv[0], '--', OUT]
exec(open(__file__.replace('build_shrine.py', 'export_model.py'), encoding='utf-8').read())
