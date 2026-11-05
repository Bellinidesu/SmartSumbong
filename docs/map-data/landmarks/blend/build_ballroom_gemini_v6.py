# v6 = v5 plus pitched roofs, turrets, rooftop plant and a pilaster facade (section 9, from the spec Ace pasted, placed against the data). v5 = Gemini's v4 plus the roof read off the Esri satellite (ballroom_roof.json from tools/roof_zones_ballroom.py): tile-roof, solar-field and flat/glass zones as thin plain caps on the roof, in the building's metres, already clipped to the footprint
import bpy
import bmesh
import math
from mathutils import Vector

# Gemini's fourth version (glass foyer panel on the real wall, nodes 17 -> 18), as pasted, with two changes of ours:
#  1. the roof overhang used (-dir.y, dir.x) as its outward normal; the ring is counter-clockwise so that points INTO the building and the 4 m canopy shrank inward: now (dir.y, -dir.x)
#  2. the export tail at the end (outward normals, then the map's exporter)

# ==========================================
# 1. INPUT DATA (OSM GROUND TRUTH METRICS)
# ==========================================

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
    [24.631101111466872, 26.9969124763624],  # Ballroom Wall Anchor
    [38.44, 39.51]                            # West Wing Wall Anchor
]

BUILDING_WALL_HEIGHT = 33.5
ROOF_SLAB_THICKNESS = 2.5
WEST_WING_HEIGHT = 35.2

BRIDGE_WIDTH = 5.0
BRIDGE_HEIGHT = 4.5
BRIDGE_FLOOR_Z = 6.0


# ==========================================
# 2. HELPER UTILITIES & MATERIALS
# ==========================================

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


# ==========================================
# 3. BUILD MAIN BALLROOM BUILDING
# ==========================================

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


# ==========================================
# 4. LEVEL ROOF & 4M SLOPED OVERHANG
# ==========================================

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

    norm1 = Vector((dir1.y, -dir1.x))      # ours: outward for a counter-clockwise ring (Gemini had (-dir.y, dir.x), which points inward)
    norm2 = Vector((dir2.y, -dir2.x))

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


# ==========================================
# 5. GLASS FOYER PANEL (EDGE NODES 17 -> 18)
# ==========================================

mesh_glass = bpy.data.meshes.new("Marriott_Glass_Facade_Mesh")
obj_glass = bpy.data.objects.new("Marriott_Glass_Facade", mesh_glass)
bpy.context.collection.objects.link(obj_glass)

bm_glass = bmesh.new()

# Nodes 17 to 18: [23.26, 28.51] -> [4.66, 46.51] (25.9m real wall facing West Wing / Resort Drive)
node17 = Vector(BUILDING_RING[17])
node18 = Vector(BUILDING_RING[18])

edge_vec = node18 - node17
edge_len = edge_vec.length
edge_dir = edge_vec.normalized()

# Counter-clockwise polygon: Outward normal facing street is (edge_dir.y, -edge_dir.x)
outward_norm = Vector((edge_dir.y, -edge_dir.x))

# Cover middle 60% of this wall segment (15.54m glass span)
panel_start = node17 + edge_dir * (edge_len * 0.2)
panel_end   = node17 + edge_dir * (edge_len * 0.8)

z_min = 4.0   # 4m ground clearance
z_max = 24.0  # 20m high glass curtain wall

v_g1 = bm_glass.verts.new((panel_start.x, panel_start.y, z_min))
v_g2 = bm_glass.verts.new((panel_end.x, panel_end.y, z_min))
v_g3 = bm_glass.verts.new((panel_end.x, panel_end.y, z_max))
v_g4 = bm_glass.verts.new((panel_start.x, panel_start.y, z_max))

face_glass = bm_glass.faces.new([v_g1, v_g2, v_g3, v_g4])

# Extrude 0.6m outwards along the corrected outward normal
res_glass = bmesh.ops.extrude_face_region(bm_glass, geom=[face_glass])
for elem in res_glass['geom']:
    if isinstance(elem, bmesh.types.BMVert):
        elem.co += Vector((outward_norm.x, outward_norm.y, 0.0)) * 0.6   # ours: the normal is 2D, the vertex 3D

bmesh.ops.recalc_face_normals(bm_glass, faces=bm_glass.faces)
bm_glass.to_mesh(mesh_glass)
bm_glass.free()

obj_glass.data.materials.append(mat_glass)


# ==========================================
# 6. MARRIOTT WEST WING
# ==========================================

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


# ==========================================
# 7. ANCHORED TRUSS SKYBRIDGE
# ==========================================

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
print(f"Skybridge Span Length: {bridge_length:.3f} m")
print(f"Glass Foyer Panel: Anchored on edge 17-18, extruded outward along (edge_dir.y, -edge_dir.x)")
print("=" * 60)



# ==========================================
# 8. ROOF ZONES FROM THE SATELLITE (ours)
# ==========================================
import json, os
_here = os.path.dirname(os.path.abspath(__file__)) if '__file__' in dir() else os.getcwd()
ROOF = json.load(open(os.path.join(_here, 'ballroom_roof.json')))
mat_tile = create_flat_material('plain.tile', 'B5603C')
mat_solar = create_flat_material('plain.solar', '2B3A55')
mat_flat = create_flat_material('plain.flat', 'B9C2C4')
ROOF_TOP = BUILDING_WALL_HEIGHT + ROOF_SLAB_THICKNESS
for key, mat_, dz in (('sky', mat_flat, 0.06),):          # v6: the tile roof and the solar fields are the pitched surfaces of section 9
    for k, zone in enumerate(ROOF[key]):
        me = bpy.data.meshes.new('roof_%s_%d' % (key, k))
        ob = bpy.data.objects.new('roof_%s_%d' % (key, k), me)
        bpy.context.collection.objects.link(ob)
        bmz = bmesh.new()
        pts = zone['ring']
        vs = [bmz.verts.new((x, y, ROOF_TOP + dz)) for x, y in pts]
        try:
            f = bmz.faces.new(vs)
            if f.normal.z < 0:
                f.normal_flip()
        except ValueError:
            pass
        bmz.to_mesh(me)
        bmz.free()
        ob.data.materials.append(mat_)
print('roof zones: %d tile, %d solar, %d flat' % (len(ROOF['tile']), len(ROOF['solar']), len(ROOF['sky'])))



# ==========================================
# 9. PITCHED ROOFS, TURRETS, ROOFTOP PLANT, PILASTER FACADE (ours)
# ==========================================
def _inpoly(x, y, ring):
    c = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi:
            c = not c
        j = i
    return c

def _dring(x, y, ring):
    best = 1e9
    for i in range(len(ring)):
        ax, ay = ring[i]
        bx, by = ring[(i + 1) % len(ring)]
        dx, dy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy + 1e-12)))
        d = math.hypot(x - ax - t * dx, y - ay - t * dy)
        if d < best:
            best = d
    return best

def _area(ring):
    return abs(sum(ring[i][0] * ring[(i + 1) % len(ring)][1] - ring[(i + 1) % len(ring)][0] * ring[i][1] for i in range(len(ring)))) / 2

TILE = [(z['ring'], 6.5 if _area(z['ring']) > 2500 else 5.0, 0.32 if _area(z['ring']) > 2500 else 0.55) for z in ROOF['tile']]   # outline, ridge height, rise per metre in from the eaves (the long central hip is gentle, the end pavilions steeper)
def roof_h(x, y):
    h = 0.0
    for ring, cap, pitch in TILE:
        if _inpoly(x, y, ring):
            h = max(h, min(_dring(x, y, ring) * pitch, cap))
    return h

def surface(name, ring, zfn, mat_, maxedge=3.0):
    """A polygon cut into small triangles and lifted by zfn(x, y): a roof that rises from its eaves to a ridge."""
    me = bpy.data.meshes.new(name)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    bm = bmesh.new()
    try:
        f = bm.faces.new([bm.verts.new((x, y, 0.0)) for x, y in ring])
    except ValueError:
        bm.free()
        return
    bmesh.ops.triangulate(bm, faces=[f])
    for _ in range(10):
        long_ = [e for e in bm.edges if e.calc_length() > maxedge]
        if not long_:
            break
        bmesh.ops.subdivide_edges(bm, edges=long_, cuts=1, use_grid_fill=False)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
    for v in bm.verts:
        v.co.z = zfn(v.co.x, v.co.y)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if bm.faces and sum(f.normal.z for f in bm.faces) < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    ob.data.materials.append(mat_)

def solid(name, verts, faces, mat_):
    me = bpy.data.meshes.new(name)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    bm = bmesh.new()
    vs = [bm.verts.new(v) for v in verts]
    for f in faces:
        try:
            bm.faces.new([vs[i] for i in f])
        except ValueError:
            pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob.data.materials.append(mat_)

def obox(name, cx, cy, z0, z1, ux, uy, hw, hd, mat_):
    """A box standing on z0 up to z1, hw each side along (ux, uy), hd each side across it."""
    vx, vy = -uy, ux
    c = [(cx + ux * hw * sx + vx * hd * sy, cy + uy * hw * sx + vy * hd * sy) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    verts = [(x, y, z0) for x, y in c] + [(x, y, z1) for x, y in c]
    solid(name, verts, [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], mat_)

ROOF_TOP = BUILDING_WALL_HEIGHT + ROOF_SLAB_THICKNESS
# 9a. the roofs: the tile roof as pitched surfaces (hips round a ridge), the solar fields laid on the slope
for k, (ring_, cap_, pitch_) in enumerate(TILE):
    surface('roof_tile_%d' % k, ring_, lambda x, y: ROOF_TOP + 0.14 + roof_h(x, y), mat_tile)
for k, z_ in enumerate(ROOF['solar']):
    surface('roof_solar_%d' % k, z_['ring'], lambda x, y: ROOF_TOP + 0.5 + roof_h(x, y), mat_solar, 3.0)

# 9b. the two turrets (octagonal, a pyramid cap): the south end's round bulge is nodes 3-6, a circle about (41, -71.5) of radius 7 (the spec put it on node 2); the north-west end's notched corner is nodes 22-25
def turret(name, cx, cy, r, cap):
    ring8 = [(cx + r * math.cos(math.radians(22.5 + 45 * i)), cy + r * math.sin(math.radians(22.5 + 45 * i))) for i in range(8)]
    z0, z1 = BUILDING_WALL_HEIGHT, ROOF_TOP + 3.0
    verts = [(x, y, z0) for x, y in ring8] + [(x, y, z1) for x, y in ring8]
    solid(name + '_drum', verts, [tuple(range(7, -1, -1))] + [tuple(range(8, 16))] + [(i, (i + 1) % 8, 8 + (i + 1) % 8, 8 + i) for i in range(8)], mat_stone)
    for i in range(0, 8, 2):                                         # alternate faces glazed
        ax, ay = ring8[i]
        bx, by = ring8[(i + 1) % 8]
        mx, my = (ax + bx) / 2, (ay + by) / 2
        nx, ny = mx - cx, my - cy
        nl = math.hypot(nx, ny)
        nx, ny = nx / nl * 0.08, ny / nl * 0.08
        lz0, lz1 = ROOF_TOP - 1.0, z1 - 0.8
        solid(name + '_gl%d' % i, [(ax * .75 + bx * .25 + nx, ay * .75 + by * .25 + ny, lz0), (ax * .25 + bx * .75 + nx, ay * .25 + by * .75 + ny, lz0), (ax * .25 + bx * .75 + nx, ay * .25 + by * .75 + ny, lz1), (ax * .75 + bx * .25 + nx, ay * .75 + by * .25 + ny, lz1)], [(0, 1, 2, 3), (3, 2, 1, 0)], mat_glass)
    rr = [(cx + (r + .5) * math.cos(math.radians(22.5 + 45 * i)), cy + (r + .5) * math.sin(math.radians(22.5 + 45 * i))) for i in range(8)]
    solid(name + '_cap', [(x, y, z1) for x, y in rr] + [(cx, cy, z1 + cap)], [(i, (i + 1) % 8, 8) for i in range(8)] + [tuple(range(7, -1, -1))], mat_tile)

turret('turret_south', 41.0, -71.5, 6.5, 6.0)
nw = [BUILDING_RING[i] for i in (22, 23, 24, 25)]
turret('turret_northwest', sum(p[0] for p in nw) / 4, sum(p[1] for p in nw) / 4, 5.5, 5.5)

# 9c. rooftop plant: two banks between the roofs and the parapet on the Resort Drive side, a chiller row on top of each; skipped where one would stand on the tile roof
n_bank = 0
for i in (16, 19):
    p0, p1 = Vector(BUILDING_RING[i]), Vector(BUILDING_RING[i + 1])
    d_ = (p1 - p0).normalized()
    inward = Vector((-d_.y, d_.x))                                   # the ring is counter-clockwise: left of the edge is inside
    mid = (p0 + p1) / 2 + inward * 6.5
    corners = [mid + d_ * sx * 10 + inward * sy * 2 for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    if any(_inpoly(c.x, c.y, r_) for c in corners for r_, _c, _p in TILE):
        print('rooftop plant skipped on edge %d: it would stand on the tile roof' % i)
        continue
    obox('hvac_bank_%d' % i, mid.x, mid.y, ROOF_TOP, ROOF_TOP + 3.0, d_.x, d_.y, 10.0, 2.0, mat_steel)
    for k in range(4):
        c = mid + d_ * (-7.5 + 5.0 * k)
        obox('chiller_%d_%d' % (i, k), c.x, c.y, ROOF_TOP + 3.0, ROOF_TOP + 3.8, d_.x, d_.y, 0.9, 0.9, mat_steel)
    n_bank += 1

# 9d. the Resort Drive wall, nodes 15 to 20 (the road side, north-east: the spec called it western): a glazed skin and a stone pilaster every 6 m, 1.2 m wide and 0.8 m out along the outward normal (dir.y, -dir.x)
n_pil = 0
for i in range(15, 20):
    p0, p1 = Vector(BUILDING_RING[i]), Vector(BUILDING_RING[i + 1])
    L_ = (p1 - p0).length
    d_ = (p1 - p0).normalized()
    out = Vector((d_.y, -d_.x))
    solid('glass_skin_%d' % i, [(p0.x + out.x * .08, p0.y + out.y * .08, 3.0), (p1.x + out.x * .08, p1.y + out.y * .08, 3.0), (p1.x + out.x * .08, p1.y + out.y * .08, BUILDING_WALL_HEIGHT - 1.5), (p0.x + out.x * .08, p0.y + out.y * .08, BUILDING_WALL_HEIGHT - 1.5)], [(0, 1, 2, 3), (3, 2, 1, 0)], mat_glass)
    for k in range(int((L_ - 1.2) // 6.0) + 1):
        c = p0 + d_ * (1.5 + 6.0 * k) + out * 0.4
        if (c - p0).length > L_ - 0.6:
            break
        obox('pilaster_%d_%d' % (i, k), c.x, c.y, 0.0, BUILDING_WALL_HEIGHT, d_.x, d_.y, 0.6, 0.4, mat_stone)
        n_pil += 1

_nv = sum(len(o.data.vertices) for o in bpy.context.scene.objects if o.type == 'MESH')
_bad = [o.name for o in bpy.context.scene.objects if o.type == 'MESH' and any(not all(math.isfinite(c) for c in v.co) for v in o.data.vertices)]
print('section 9: %d tile surfaces, %d solar, 2 turrets, %d plant banks, %d pilasters; %d vertices in all; non-finite: %s' % (len(TILE), len(ROOF['solar']), n_bank, n_pil, _nv, _bad or 'none'))

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
