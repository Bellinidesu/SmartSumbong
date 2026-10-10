import bpy
import bmesh
import math
from mathutils import Vector

# Gemini's third version (geom= and recalc_face_normals): rebuilt from the first by the same edits, then run with our export tail.
# Script written by Gemini from the brief in gemini_brief_ballroom.txt (pasted by Ace), unchanged apart from this header and the export tail at the end.

BUILDING_RING = [
    [-95.46, 60.93], [-17.34, -17.68], [35.07, -70.43], [35.7, -74.54],
    [39.15, -77.96], [42.62, -78.77], [46.6, -77.84], [53.09, -71.48],
    [55.54, -73.31], [64.16, -65.24], [57.76, -58.14], [64.16, -51.28],
    [49.87, -36.65], [56.28, -28.85], [53.43, -17.02], [46.69, -0.98],
    [42.38, 7.41], [23.26, 28.51], [4.66, 46.51], [-9.32, 58.11],
    [-42.69, 74.97], [-69.01, 87.08], [-78.27, 79.25], [-83.81, 84.79],
    [-93.9, 76.22], [-89.37, 70.91], [-95.79, 64.56], [-95.46, 60.93]
]

WEST_WING_RING = [
    [59.45, 58.86], [38.44, 39.51], [76.48, -1.51], [97.6, 17.84]
]

BRIDGE_ENDS = [
    [24.631101111466872, 26.9969124763624],
    [38.44, 39.51]
]

BUILDING_WALL_HEIGHT = 33.5
ROOF_SLAB_THICKNESS = 2.5
WEST_WING_HEIGHT = 35.2

BRIDGE_WIDTH = 5.0
BRIDGE_HEIGHT = 4.5
BRIDGE_FLOOR_Z = 6.0


def hex_to_rgba(hex_str, alpha=1.0):
    r = int(hex_str[0:2], 16) / 255.0
    g = int(hex_str[2:4], 16) / 255.0
    b = int(hex_str[4:6], 16) / 255.0
    return (r, g, b, alpha)


def create_flat_material(name, hex_color):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = False
    mat.diffuse_color = hex_to_rgba(hex_color)
    return mat


bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

mat_stone = create_flat_material('plain.stone', 'DCC9A8')
mat_roof = create_flat_material('plain.roof', 'A9ADB4')
mat_glass = create_flat_material('plain.glass', '7F98B0')
mat_steel = create_flat_material('plain.steel', 'C9CDD2')
mat_wing = create_flat_material('plain.wing', 'D9A590')

mesh_bldg = bpy.data.meshes.new("Marriott_Grand_Ballroom_Mesh")
obj_bldg = bpy.data.objects.new("Marriott_Grand_Ballroom", mesh_bldg)
bpy.context.collection.objects.link(obj_bldg)

bm_bldg = bmesh.new()
unique_ring = BUILDING_RING[:-1] if BUILDING_RING[0] == BUILDING_RING[-1] else BUILDING_RING
v_floor = [bm_bldg.verts.new((p[0], p[1], 0.0)) for p in unique_ring]
face_base = bm_bldg.faces.new(v_floor)
res = bmesh.ops.extrude_face_region(bm_bldg, geom=[face_base])
for elem in res['geom']:
    if isinstance(elem, bmesh.types.BMVert):
        elem.co.z += BUILDING_WALL_HEIGHT
bmesh.ops.recalc_face_normals(bm_bldg, faces=bm_bldg.faces)
bm_bldg.to_mesh(mesh_bldg)
bm_bldg.free()
obj_bldg.data.materials.append(mat_stone)

mesh_roof = bpy.data.meshes.new("Marriott_Roof_Mesh")
obj_roof = bpy.data.objects.new("Marriott_Roof_Slab", mesh_roof)
bpy.context.collection.objects.link(obj_roof)

bm_roof = bmesh.new()
v_roof_base = [bm_roof.verts.new((p[0], p[1], BUILDING_WALL_HEIGHT)) for p in unique_ring]
face_roof = bm_roof.faces.new(v_roof_base)
res_roof = bmesh.ops.extrude_face_region(bm_roof, geom=[face_roof])
for elem in res_roof['geom']:
    if isinstance(elem, bmesh.types.BMVert):
        elem.co.z += ROOF_SLAB_THICKNESS

n_nodes = len(unique_ring)
v_top_nodes = [v for v in bm_roof.verts if abs(v.co.z - (BUILDING_WALL_HEIGHT + ROOF_SLAB_THICKNESS)) < 0.001]
sorted_top_verts = []
for p in unique_ring:
    for v in v_top_nodes:
        if (Vector((p[0], p[1])) - Vector((v.co.x, v.co.y))).length < 0.001:
            sorted_top_verts.append(v)
            break

overhang_outer_verts = []
for i in range(n_nodes):
    prev_p = Vector(unique_ring[(i - 1) % n_nodes])
    curr_p = Vector(unique_ring[i])
    next_p = Vector(unique_ring[(i + 1) % n_nodes])
    dir1 = (curr_p - prev_p).normalized()
    dir2 = (next_p - curr_p).normalized()
    norm1 = Vector((-dir1.y, dir1.x))
    norm2 = Vector((-dir2.y, dir2.x))
    avg_norm = (norm1 + norm2).normalized()
    dot = norm1.dot(avg_norm)
    scale = 1.0 / max(dot, 0.2)
    scale = min(scale, 2.5)
    offset_vec = avg_norm * (4.0 * scale)
    out_x = curr_p.x + offset_vec.x
    out_y = curr_p.y + offset_vec.y
    out_z = (BUILDING_WALL_HEIGHT + ROOF_SLAB_THICKNESS) - 0.35
    v_out = bm_roof.verts.new((out_x, out_y, out_z))
    overhang_outer_verts.append(v_out)

for i in range(n_nodes):
    v1 = sorted_top_verts[i]
    v2 = sorted_top_verts[(i + 1) % n_nodes]
    v3 = overhang_outer_verts[(i + 1) % n_nodes]
    v4 = overhang_outer_verts[i]
    bm_roof.faces.new([v1, v2, v3, v4])

bmesh.ops.recalc_face_normals(bm_roof, faces=bm_roof.faces)
bm_roof.to_mesh(mesh_roof)
bm_roof.free()
obj_roof.data.materials.append(mat_roof)

mesh_wing = bpy.data.meshes.new("Marriott_West_Wing_Mesh")
obj_wing = bpy.data.objects.new("Marriott_West_Wing", mesh_wing)
bpy.context.collection.objects.link(obj_wing)

bm_wing = bmesh.new()
v_wing_base = [bm_wing.verts.new((p[0], p[1], 0.0)) for p in WEST_WING_RING]
face_wing = bm_wing.faces.new(v_wing_base)
res_wing = bmesh.ops.extrude_face_region(bm_wing, geom=[face_wing])
for elem in res_wing['geom']:
    if isinstance(elem, bmesh.types.BMVert):
        elem.co.z += WEST_WING_HEIGHT
bmesh.ops.recalc_face_normals(bm_wing, faces=bm_wing.faces)
bm_wing.to_mesh(mesh_wing)
bm_wing.free()
obj_wing.data.materials.append(mat_wing)

pt_A = Vector((BRIDGE_ENDS[0][0], BRIDGE_ENDS[0][1], BRIDGE_FLOOR_Z))
pt_B = Vector((BRIDGE_ENDS[1][0], BRIDGE_ENDS[1][1], BRIDGE_FLOOR_Z))
vec_bridge = pt_B - pt_A
bridge_length = vec_bridge.length
dir_bridge = vec_bridge.normalized()
perp_bridge = Vector((-dir_bridge.y, dir_bridge.x, 0.0)).normalized()
half_w = BRIDGE_WIDTH / 2.0

mesh_bridge = bpy.data.meshes.new("Resort_Drive_Skybridge_Mesh")
obj_bridge = bpy.data.objects.new("Resort_Drive_Skybridge", mesh_bridge)
bpy.context.collection.objects.link(obj_bridge)

bm_bridge = bmesh.new()
vA_bl = bm_bridge.verts.new(pt_A - perp_bridge * half_w)
vA_br = bm_bridge.verts.new(pt_A + perp_bridge * half_w)
vA_tl = bm_bridge.verts.new(pt_A - perp_bridge * half_w + Vector((0, 0, BRIDGE_HEIGHT)))
vA_tr = bm_bridge.verts.new(pt_A + perp_bridge * half_w + Vector((0, 0, BRIDGE_HEIGHT)))
vB_bl = bm_bridge.verts.new(pt_B - perp_bridge * half_w)
vB_br = bm_bridge.verts.new(pt_B + perp_bridge * half_w)
vB_tl = bm_bridge.verts.new(pt_B - perp_bridge * half_w + Vector((0, 0, BRIDGE_HEIGHT)))
vB_tr = bm_bridge.verts.new(pt_B + perp_bridge * half_w + Vector((0, 0, BRIDGE_HEIGHT)))
bm_bridge.faces.new([vA_bl, vA_br, vB_br, vB_bl])
bm_bridge.faces.new([vA_tl, vA_tr, vB_tr, vB_tl])
bm_bridge.faces.new([vA_bl, vA_tl, vB_tl, vB_bl])
bm_bridge.faces.new([vA_br, vA_tr, vB_tr, vB_br])
bmesh.ops.recalc_face_normals(bm_bridge, faces=bm_bridge.faces)
bm_bridge.to_mesh(mesh_bridge)
bm_bridge.free()
obj_bridge.data.materials.append(mat_steel)

print("=" * 60)
print("SUCCESS: Marriott Grand Ballroom & Skybridge Model Built.")
print(f"Skybridge Calculated Span Length : {bridge_length:.3f} m")
print(f"End A Floor Elevation (Ballroom) : {pt_A.z:.2f} m (Roof Top: {pt_A.z + BRIDGE_HEIGHT:.2f} m)")
print(f"End B Floor Elevation (West Wing): {pt_B.z:.2f} m (Roof Top: {pt_B.z + BRIDGE_HEIGHT:.2f} m)")
print("=" * 60)

# ---- the export tail (ours, not Gemini's): outward normals, then the map's exporter
import os, sys
for ob in bpy.context.scene.objects:
    if ob.type == 'MESH':
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(ob.data)
        bm.free()
HERE = os.path.dirname(os.path.abspath(__file__)) if '__file__' in dir() else os.getcwd()
OUT = sys.argv[sys.argv.index('--') + 1] if '--' in sys.argv else 'ballroom_gemini.npz'
BL = sys.argv[sys.argv.index('--') + 2] if len(sys.argv) > sys.argv.index('--') + 2 else None
if BL:
    bpy.ops.wm.save_as_mainfile(filepath=BL)
sys.argv = [sys.argv[0], '--', OUT]
exec(open(os.path.join(HERE, 'export_model.py'), encoding='utf-8').read())
