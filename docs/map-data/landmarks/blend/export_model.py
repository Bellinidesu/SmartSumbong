"""
Run inside Blender:   blender --background <file.blend> --python export_model.py -- <out.npz>
(or, without a .blend, after a build script has made the scene in the same session.)

Writes what the map needs of a model made in Blender, in metres, Z up, origin at the building's anchor: for every triangle corner a position, a normal and a colour, and a material
name for the triangle. Colours are the materials' base colours (flat, as everywhere on this map); a material name starts with a tile name of the map (plain, glass, louvre, roofdeck,
sheet, tile, glow0..3, sign:TEXT) so that the importer knows how to light it. Nothing else is read: no textures, no node trees.
"""
import sys

import bpy
import numpy as np

out = sys.argv[sys.argv.index('--') + 1] if '--' in sys.argv else 'model.npz'
dg = bpy.context.evaluated_depsgraph_get()
P, N, C, M, UV, names = [], [], [], [], [], []
mat_index = {}
for ob in bpy.context.scene.objects:
    if ob.type not in ('MESH', 'FONT', 'CURVE') or ob.hide_render or ob.name.startswith('_'):
        continue
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    me.calc_loop_triangles()
    try:
        me.calc_normals_split()
    except Exception:
        pass
    uvl = me.uv_layers.active
    mw = ob.matrix_world
    nm = mw.to_3x3().inverted().transposed()
    mats = [s.material for s in ob.material_slots]
    for t in me.loop_triangles:
        mat = mats[t.material_index] if t.material_index < len(mats) else None
        key = mat.name if mat else 'plain'
        if key not in mat_index:
            mat_index[key] = len(mat_index)
            names.append(key)
        col = tuple(mat.diffuse_color[:3]) if mat else (.8, .8, .8)
        for li, vi in zip(t.loops, t.vertices):
            co = mw @ me.vertices[vi].co
            n = (nm @ (me.corner_normals[li].vector if hasattr(me, 'corner_normals') else me.vertices[vi].normal)).normalized() if True else None
            P.append((co.x, co.y, co.z))
            N.append((n.x, n.y, n.z))
            C.append(col)
            M.append(mat_index[key])
            UV.append(tuple(uvl.data[li].uv) if uvl else (0.0, 0.0))
    ev.to_mesh_clear()
P = np.asarray(P, dtype=np.float32)
np.savez_compressed(out, p=P, n=np.asarray(N, dtype=np.float32), c=np.round(np.asarray(C) * 255).astype(np.uint8), m=np.asarray(M, dtype=np.uint16), uv=np.asarray(UV, dtype=np.float32), names=np.asarray(names))
print('exported', len(P) // 3, 'triangles,', len(names), 'materials ->', out)
