"""blender --background <file.blend> --python render.py -- <out_prefix> [yaw_deg pitch_deg dist target_u target_v target_z] ...   Workbench renders (flat material colours, soft light), one PNG a view."""
import math
import sys

import bpy
from mathutils import Euler, Vector

a = sys.argv[sys.argv.index('--') + 1:]
prefix = a[0]
views = [tuple(float(x) for x in a[i:i + 6]) for i in range(1, len(a), 6)] or [(-35, 28, 150, 0, 0, 8), (145, 28, 150, 0, 0, 8), (35, 18, 70, 36, 0, 8), (0, 89, 150, 0, 0, 0)]
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.render.resolution_x, sc.render.resolution_y = 900, 600
sh = sc.display.shading
sh.light = 'STUDIO'
sh.color_type = 'MATERIAL'
sh.show_cavity = True
sc.world = bpy.data.worlds.new('w') if not sc.world else sc.world
sc.world.color = (.80, .88, .96)
ground = bpy.data.objects.new('_ground', bpy.data.meshes.new('g'))
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam'))
sc.collection.objects.link(cam)
sc.camera = cam
root = bpy.data.objects.get('shrine')
th = root.rotation_euler.z if root else 0
for i, (yaw, pitch, dist, tu, tv, tz) in enumerate(views):
    c, s = math.cos(th), math.sin(th)
    t = Vector((tu * c - tv * s, tu * s + tv * c, tz))
    y, p = math.radians(yaw), math.radians(pitch)
    eye = t + Vector((math.sin(y) * math.cos(p), -math.cos(y) * math.cos(p), math.sin(p))) * dist
    cam.location = eye
    cam.rotation_euler = (t - eye).to_track_quat('-Z', 'Y').to_euler()
    cam.data.lens = 35
    sc.render.filepath = '%s_%d.png' % (prefix, i)
    bpy.ops.render.render(write_still=True)
print('rendered', len(views))
