"""blender --background <model.blend> --python match_render.py -- <cams.json> <neighbours.json> <outdir>

Looks at the model from where each photograph was taken: a camera at the photograph's position, heading, tilt and field of view (read off the Street View address bar), the plain buildings of
the open data round it as grey boxes (so that what stands in front of the building in the photograph stands in front of it here), Workbench flat colours. One PNG a photograph.
"""
import json
import math
import os
import sys

import bpy
import bmesh
from mathutils import Euler, Vector

cams_f, nb_f, outdir = sys.argv[sys.argv.index('--') + 1:][:3]
cams = json.load(open(cams_f, encoding='utf-8'))
nb = json.load(open(nb_f, encoding='utf-8'))
os.makedirs(outdir, exist_ok=True)
MX, MY = 111320 * math.cos(math.radians(14.525)), 110574
A = cams['anchor']
sc = bpy.context.scene

grey = bpy.data.materials.new('nb')
grey.diffuse_color = (.78, .76, .73, 1)
for k, b in enumerate(nb):
    me = bpy.data.meshes.new('nb%d' % k)
    bm = bmesh.new()
    pts = [bm.verts.new((x, y, 0)) for x, y in b['ring']]
    try:
        f = bm.faces.new(pts)
        r = bmesh.ops.extrude_face_region(bm, geom=[f])
        vs = [v for v in r['geom'] if isinstance(v, bmesh.types.BMVert)]
        bmesh.ops.translate(bm, vec=(0, 0, b['h']), verts=vs)
    except Exception:
        bm.free()
        continue
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new('nb%d' % k, me)
    sc.collection.objects.link(ob)
    ob.data.materials.append(grey)
    ob.name = 'nb%d' % k
gm = bpy.data.meshes.new('ground')
gm.from_pydata([(-400, -400, -.05), (400, -400, -.05), (400, 400, -.05), (-400, 400, -.05)], [], [(0, 1, 2, 3)])
g = bpy.data.objects.new('ground', gm)
sc.collection.objects.link(g)
gmat = bpy.data.materials.new('gr')
gmat.diffuse_color = (.74, .73, .70, 1)
g.data.materials.append(gmat)

sc.render.engine = 'BLENDER_WORKBENCH'
sc.render.resolution_x, sc.render.resolution_y = 1280, 720
sh = sc.display.shading
sh.light = 'STUDIO'
sh.color_type = 'MATERIAL'
sh.show_cavity = False
sc.world = sc.world or bpy.data.worlds.new('w')
sc.world.color = (.62, .78, .95)
camd = bpy.data.cameras.new('c')
cam = bpy.data.objects.new('c', camd)
sc.collection.objects.link(cam)
sc.camera = cam
camd.sensor_fit = 'VERTICAL'
camd.clip_start, camd.clip_end = .2, 2000
for c in cams['cams']:
    x, y = (c['lng'] - A[0]) * MX, (c['lat'] - A[1]) * MY
    cam.location = (x, y, c.get('height', 2.5))
    h = math.radians(c['heading'])
    pitch = math.radians(c['tilt'] - 90)
    # a camera looking down -Z with Y up; turn it to look along the compass heading (clockwise from north), then tilt up by pitch
    d = Vector((math.sin(h) * math.cos(pitch), math.cos(h) * math.cos(pitch), math.sin(pitch)))
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    camd.angle_y = math.radians(c['fov'])
    sc.render.filepath = os.path.join(outdir, '%02d.png' % c['n'])
    bpy.ops.render.render(write_still=True)
print('matched', len(cams['cams']))
