"""Open-licence parts (Kenney's kits, CC0) as ornaments on our own buildings, inside Blender:   exec(open('parts.py').read())  then   part('castle', 'tower-hexagon-roof', x, y, z, yaw=0, size=(w, d, h))
A part is imported from the kit's OBJ, scaled to the size asked for (any of w, d, h left None keeps the proportion), stood on z, and its colours (Kenney paints a small palette picture, read at each face's UV)
are flattened to the nearest of OUR plain materials, so nothing of the kit's own colouring or texture reaches the map: it is shape only, in the map's own colours.
The kits live in tools/mly-cache/parts (not committed; CC0 means no credit is needed, the credits page names them anyway)."""
import math
import os

import bpy
from mathutils import Matrix, Vector

_HERE = os.path.dirname(os.path.abspath(__file__)) if '__file__' in dir() else os.getcwd()
PARTS = os.path.normpath(os.path.join(_HERE, '..', '..', 'tools', 'mly-cache', 'parts'))
# our plain palette: name, hex (these are the materials the exporter turns into atlas tiles)
PALETTE = {'stone': 'DCC9A8', 'tile': 'B5603C', 'steel': 'C9CDD2', 'glass': '7F98B0', 'wood': '8A6A4A', 'flag': 'C0392B', 'dark': '4A4A52', 'leaf': '5E8C4A'}
_mat = {}


def _hex(h):
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def plain(name):
    if name not in _mat:
        m = bpy.data.materials.get('plain.' + name) or bpy.data.materials.new('plain.' + name)
        c = _hex(PALETTE[name])
        m.diffuse_color = (c[0], c[1], c[2], 1.0)
        _mat[name] = m
    return _mat[name]


def _nearest(rgb):
    """The palette entry closest to a colour (linear-ish distance, grey and brown told apart by hue weight)."""
    best, bd = 'stone', 9
    for k, h in PALETTE.items():
        c = _hex(h)
        d = sum((rgb[i] - c[i]) ** 2 * w for i, w in enumerate((.9, 1.2, 1.0)))
        if d < bd:
            best, bd = k, d
    return best


def _image_of(ob):
    for ms in ob.material_slots:
        m = ms.material
        if m and m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == 'TEX_IMAGE' and n.image:
                    return n.image
    return None


def part(kit, name, x=0.0, y=0.0, z=0.0, yaw=0.0, size=(None, None, None), recolour=None, tag=None):
    """Import PARTS/<kit>/Models/OBJ format/<name>.obj, fit it to `size` (metres: width x, depth y, height z), stand it on z at (x, y), turned yaw radians. recolour: {palette name: palette name} swaps."""
    path = os.path.join(PARTS, kit, 'Models', 'OBJ format', name + '.obj')
    before = set(bpy.data.objects)
    bpy.ops.wm.obj_import(filepath=path, forward_axis='NEGATIVE_Z', up_axis='Y')
    new = [o for o in bpy.data.objects if o not in before and o.type == 'MESH']
    if not new:
        raise RuntimeError('no mesh in ' + path)
    # one object, in its own frame
    for o in new:
        o.select_set(True)
    bpy.context.view_layer.objects.active = new[0]
    if len(new) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)   # the importer turns the kit's Y-up into Z-up on the object: bake it into the mesh
    me = ob.data
    img = _image_of(ob)
    px = list(img.pixels) if img else None
    W, H = (img.size if img else (0, 0))
    uv = me.uv_layers.active.data if me.uv_layers.active else None
    # flatten the colours: per face, the palette picture at the face's middle UV, the nearest of our materials
    for k in PALETTE:
        pass
    me.materials.clear()
    slot = {}
    for poly in me.polygons:
        if px and uv:
            u = sum(uv[li].uv[0] for li in poly.loop_indices) / poly.loop_total
            v = sum(uv[li].uv[1] for li in poly.loop_indices) / poly.loop_total
            ix, iy = min(W - 1, max(0, int(u * W))), min(H - 1, max(0, int(v * H)))
            o = (iy * W + ix) * 4
            c = tuple(px[o + i] for i in range(3))
            # the image is sRGB: our palette is compared in the same space
            nm = _nearest(c)
        else:
            nm = 'stone'
        if recolour and nm in recolour:
            nm = recolour[nm]
        if nm not in slot:
            me.materials.append(plain(nm))
            slot[nm] = len(me.materials) - 1
        poly.material_index = slot[nm]
    # size: Kenney's Y is up in the file; after import with up Y it is Z here
    bb = [Vector(c) for c in ob.bound_box]
    w0 = max(v.x for v in bb) - min(v.x for v in bb)
    d0 = max(v.y for v in bb) - min(v.y for v in bb)
    h0 = max(v.z for v in bb) - min(v.z for v in bb)
    sx = (size[0] / w0) if size[0] else None
    sy = (size[1] / d0) if size[1] else None
    sz = (size[2] / h0) if size[2] else None
    known = [s for s in (sx, sy, sz) if s]
    mean = sum(known) / len(known) if known else 1.0
    sx, sy, sz = sx or mean, sy or mean, sz or mean
    zmin = min(v.z for v in bb)
    cx = (max(v.x for v in bb) + min(v.x for v in bb)) / 2
    cy = (max(v.y for v in bb) + min(v.y for v in bb)) / 2
    ob.data.transform(Matrix.Translation((-cx, -cy, -zmin)))
    ob.data.transform(Matrix.Diagonal((sx, sy, sz, 1.0)))
    ob.data.transform(Matrix.Rotation(yaw, 4, 'Z'))
    ob.location = (x, y, z)
    ob.rotation_euler = (0, 0, 0)
    ob.scale = (1, 1, 1)
    ob.name = (tag or name) + '_part'
    return ob


def dims(kit, name):
    """A part's own size in the kit's units: for planning."""
    path = os.path.join(PARTS, kit, 'Models', 'OBJ format', name + '.obj')
    before = set(bpy.data.objects)
    bpy.ops.wm.obj_import(filepath=path, forward_axis='NEGATIVE_Z', up_axis='Y')
    new = [o for o in bpy.data.objects if o not in before]
    bb = [new[0].matrix_world @ Vector(c) for c in new[0].bound_box]
    out = tuple(round(max(getattr(v, a) for v in bb) - min(getattr(v, a) for v in bb), 2) for a in 'xyz')
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    return out
