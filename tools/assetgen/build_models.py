"""Procedural 3D models for Shadow Chess 3D and Shadow Checkers.

Reproducible Blender pipeline: every mesh is generated from code (lathed 2D
profiles, a signed-distance-field sculpt for the chess knight, swept board
mouldings). No external assets, no network, deterministic output.

Run headless with Blender 5.2+ from the repository root:

    blender -b --factory-startup --python tools/assetgen/build_models.py
    blender -b --factory-startup --python tools/assetgen/build_models.py -- \
        --preview /tmp/previews            # also render contact sheets
    blender -b --factory-startup --python tools/assetgen/build_models.py -- \
        --only knight --preview /tmp/p     # iterate on a single model

Options (after "--"):
    --game chess|checkers  which set to build. Default: detected from the
                           repository this script lives in (project.godot).
    --out DIR              output directory (default <repo>/assets/models)
    --only a,b,...         build only these model names (file stems)
    --preview DIR          render preview PNGs of the written OBJs into DIR
    --no-build             skip building; only render previews

The very same file lives in both repositories (ShadowChess3D and
ShadowCheckers); keep the copies identical.

Conventions of the written OBJ files (Godot space):
    * 1.0 unit = one board square, +Y up, origin at the centre of the base
      of the piece with the base bottom at y = 0.
    * The chess knight's snout points to -Z.
    * Material groups (usemtl): `body` first, then `trim` (gold accents).
      A matching .mtl is written but the games override the materials.
    * Normals (smooth, split at crisp edges) and UVs are exported.

Internally we model in Blender's native Z-up space, where the knight's snout
points to +Y, and the OBJ exporter converts with forward=-Z, up=Y:
    Godot (x, y, z) = Blender (x, z, -y).
"""

import math
import os
import sys
import time

import bmesh
import bpy
import mathutils
import numpy as np
from mathutils import Matrix, Vector

TAU = math.tau
BODY, TRIM = 0, 1           # material slot indices
SHARP_ANGLE = 35.0          # degrees: "smooth by angle" threshold


# ---------------------------------------------------------------------------
# Small math helpers
# ---------------------------------------------------------------------------

def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def cubic_bezier(p0, p1, p2, p3, t):
    u = 1.0 - t
    return (u * u * u * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t * t * t * p3[0],
            u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1])


def catmull_rom_closed(points, n_per=10, alpha=0.5):
    """Centripetal Catmull-Rom spline through `points` (closed loop)."""
    P = np.asarray(points, dtype=np.float64)
    n = len(P)
    out = []
    for i in range(n):
        p0, p1, p2, p3 = P[(i - 1) % n], P[i], P[(i + 1) % n], P[(i + 2) % n]

        def tj(ti, pi, pj):
            return ti + max(np.linalg.norm(pj - pi), 1e-9) ** alpha
        t0 = 0.0
        t1 = tj(t0, p0, p1)
        t2 = tj(t1, p1, p2)
        t3 = tj(t2, p2, p3)
        ts = np.linspace(t1, t2, n_per, endpoint=False)[:, None]
        a1 = (t1 - ts) / (t1 - t0) * p0 + (ts - t0) / (t1 - t0) * p1
        a2 = (t2 - ts) / (t2 - t1) * p1 + (ts - t1) / (t2 - t1) * p2
        a3 = (t3 - ts) / (t3 - t2) * p2 + (ts - t2) / (t3 - t2) * p3
        b1 = (t2 - ts) / (t2 - t0) * a1 + (ts - t0) / (t2 - t0) * a2
        b2 = (t3 - ts) / (t3 - t1) * a2 + (ts - t1) / (t3 - t1) * a3
        out.append((t2 - ts) / (t2 - t1) * b1 + (ts - t1) / (t2 - t1) * b2)
    return np.concatenate(out, axis=0)


# ---------------------------------------------------------------------------
# 2D profile authoring (for lathed / swept geometry)
# ---------------------------------------------------------------------------

class Profile:
    """A 2D polyline in (r, z) (or (d, y) for sweeps) built from segments.

    Key points may carry a fillet radius `f` (rounded afterwards, sampled as a
    quadratic arc) or `crease=True` (always rendered as a crisp edge).
    `tag` labels the points added from now on (e.g. the ring resolution to use
    for them); `built_tags` holds the per-point tags after build().
    """

    def __init__(self, r=0.0, z=0.0, tag=None):
        self.pts = [(float(r), float(z))]
        self.fil = [0.0]
        self.crease = [True]
        self.tag = tag
        self.tags = [tag]
        self.built_tags = []

    @property
    def cur(self):
        return self.pts[-1]

    def _add(self, r, z, f=0.0, crease=False):
        pr, pz = self.pts[-1]
        if abs(pr - r) < 1e-7 and abs(pz - z) < 1e-7:
            # coincident: merge attributes into the existing point
            self.fil[-1] = max(self.fil[-1], f)
            self.crease[-1] = self.crease[-1] or crease
            return
        self.pts.append((float(r), float(z)))
        self.fil.append(float(f))
        self.crease.append(bool(crease))
        self.tags.append(self.tag)

    def to(self, r, z, f=0.0, crease=False):
        """Straight segment to (r, z)."""
        self._add(r, z, f, crease)
        return self

    def bez(self, c1, c2, end, n=10, f=0.0, crease=False):
        """Cubic bezier from the current point via control points c1, c2."""
        p0 = self.cur
        for i in range(1, n):
            self._add(*cubic_bezier(p0, c1, c2, end, i / n))
        self._add(end[0], end[1], f, crease)
        return self

    def arc(self, center, a1_deg, n=12, f=0.0, crease=False):
        """Circular arc around `center` from the current point to angle a1."""
        cr, cz = center
        pr, pz = self.cur
        rad = math.hypot(pr - cr, pz - cz)
        a0 = math.atan2(pz - cz, pr - cr)
        a1 = math.radians(a1_deg)
        for i in range(1, n + 1):
            a = a0 + (a1 - a0) * i / n
            last = i == n
            self._add(cr + rad * math.cos(a), cz + rad * math.sin(a),
                      f if last else 0.0, crease if last else False)
        return self

    def build(self, closed=False):
        """Resolve fillets. Returns (points, crease_flags)."""
        pts, fil, cr = self.pts, self.fil, self.crease
        n = len(pts)
        out, flags = [], []
        tags = self.built_tags = []
        for i in range(n):
            p1 = Vector(pts[i])
            has_nb = closed or (0 < i < n - 1)
            if fil[i] <= 0 or not has_nb:
                out.append(tuple(p1))
                flags.append(cr[i])
                tags.append(self.tags[i])
                continue
            p0 = Vector(pts[(i - 1) % n])
            p2 = Vector(pts[(i + 1) % n])
            d1 = p1 - p0
            d2 = p2 - p1
            l1, l2 = d1.length, d2.length
            d1.normalize()
            d2.normalize()
            turn = math.acos(max(-1.0, min(1.0, d1.dot(d2))))
            if turn < math.radians(20.0):      # nearly tangent: no fillet needed
                out.append(tuple(p1))
                flags.append(cr[i])
                tags.append(self.tags[i])
                continue
            t = fil[i] * math.tan(turn / 2.0)
            t = min(t, 0.45 * l1, 0.45 * l2)
            a = p1 - d1 * t
            b = p1 + d2 * t
            # micro fillets (<= 2.5 mm) become a single chamfer segment
            segs = 1 if fil[i] <= 0.0025 else max(2, int(math.ceil(math.degrees(turn) / 30.0)))
            for k in range(segs + 1):
                u = k / segs
                q = a * (1 - u) ** 2 + p1 * 2 * u * (1 - u) + b * u * u
                out.append((q.x, q.y))
                flags.append(False)
                tags.append(self.tags[i])
        return out, flags


def circle_profile(rc, zc, rho, n=10):
    """Closed CCW circle in (r, z) — cross-section of a torus bead."""
    return [(rc + rho * math.cos(TAU * i / n - math.pi / 2),
             zc + rho * math.sin(TAU * i / n - math.pi / 2)) for i in range(n)]


def band_profile(r_in, r_out, z0, z1, fr=0.0025):
    """Closed CCW rounded-rectangle section for a gold band ring."""
    P = Profile(r_in, z0)
    P.to(r_out, z0, f=fr).to(r_out, z1, f=fr).to(r_in, z1)
    pts, flags = P.build(closed=False)
    # the r_in corners are hidden inside the body: keep them simple
    return pts, [True] + flags[1:-1] + [True]


# ---------------------------------------------------------------------------
# BMesh construction helpers
# ---------------------------------------------------------------------------

def turn_angles(pts, closed):
    """Turn angle (deg) of a 2D polyline at every vertex."""
    n = len(pts)
    ang = [0.0] * n
    for i in range(n):
        if not closed and (i == 0 or i == n - 1):
            continue
        p0, p1, p2 = Vector(pts[(i - 1) % n]), Vector(pts[i]), Vector(pts[(i + 1) % n])
        d1, d2 = p1 - p0, p2 - p1
        if d1.length < 1e-9 or d2.length < 1e-9:
            continue
        ang[i] = math.degrees(d1.angle(d2))
    return ang


def _bridge(A, B):
    """Faces joining vertex ring A (profile i) to ring B (profile i+1).

    Rings may have different vertex counts if one is a multiple of the other.
    A ring of length 1 is an axis pole. Returns [(verts, uvs_u)] with face
    winding such that a profile running CCW in (r, z) gives outward normals.
    """
    na, nb = len(A), len(B)
    faces = []
    if na == 1 and nb == 1:
        return faces
    if na == 1:
        for j in range(nb):
            faces.append(((A[0], B[(j + 1) % nb], B[j]),
                          ((j + 0.5) / nb, (j + 1) / nb, j / nb)))
        return faces
    if nb == 1:
        for j in range(na):
            faces.append(((A[j], A[(j + 1) % na], B[0]),
                          (j / na, (j + 1) / na, (j + 0.5) / na)))
        return faces
    if na == nb:
        for j in range(na):
            j2 = (j + 1) % na
            faces.append(((A[j], A[j2], B[j2], B[j]),
                          (j / na, (j + 1) / na, (j + 1) / nb, j / nb)))
        return faces
    if nb % na == 0:
        k = nb // na
        for j in range(na):
            j2 = (j + 1) % na
            base = j * k
            half = k // 2
            for t in range(half):
                faces.append(((A[j], B[(base + t + 1) % nb], B[base + t]),
                              (j / na, (base + t + 1) / nb, (base + t) / nb)))
            faces.append(((A[j], A[j2], B[(base + half) % nb]),
                          (j / na, (j + 1) / na, (base + half) / nb)))
            for t in range(half, k):
                faces.append(((A[j2], B[(base + t + 1) % nb], B[(base + t) % nb]),
                              ((j + 1) / na, (base + t + 1) / nb, (base + t) / nb)))
        return faces
    if na % nb == 0:
        # mirror of the case above: build B->A and flip winding
        rev = _bridge(B, A)
        return [(tuple(reversed(v)), tuple(reversed(u))) for v, u in rev]
    raise ValueError("ring sizes %d/%d are not multiples" % (na, nb))


def lathe(pts, crease=None, segs=64, closed=False, ring_segs=None,
          radial_fn=None, mat=BODY, phase=0.0):
    """Revolve a (r, z) profile around the Z axis into a closed bmesh.

    pts       : profile points. Open profiles must start and end on the axis
                (r == 0); closed profiles (rings) must be CCW.
    crease    : per-point crisp-edge flags (plus automatic > SHARP_ANGLE).
    ring_segs : optional per-point radial segment counts (multiples).
    radial_fn : optional f(i, angle) -> dr, radial offset (e.g. reeding).
    """
    n = len(pts)
    crease = crease or [False] * n
    ring_segs = ring_segs or [segs] * n
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    # arc length for V
    s = [0.0]
    for i in range(1, n):
        s.append(s[-1] + math.dist(pts[i], pts[i - 1]))
    rings = []
    for i, (r, z) in enumerate(pts):
        if r <= 1e-7:
            rings.append([bm.verts.new((0.0, 0.0, z))])
            continue
        m = ring_segs[i]
        ring = []
        for j in range(m):
            a = phase + TAU * j / m
            rr = r + (radial_fn(i, a) if radial_fn else 0.0)
            ring.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), z)))
        rings.append(ring)
    ring_of = {}
    for i, ring in enumerate(rings):
        for v in ring:
            ring_of[v] = i
    pairs = [(i, i + 1) for i in range(n - 1)]
    if closed:
        pairs.append((n - 1, 0))
    s_close = s[-1] + math.dist(pts[-1], pts[0])
    for (ia, ib) in pairs:
        for verts, us in _bridge(rings[ia], rings[ib]):
            f = bm.faces.new(verts)
            f.material_index = mat
            f.smooth = True
            for loop, u in zip(f.loops, us):
                ri = ring_of[loop.vert]
                v = s_close if (ri == 0 and ia == n - 1) else s[ri]
                loop[uvl].uv = (u, v)
    # crisp ring edges
    ang = turn_angles(pts, closed)
    for i, ring in enumerate(rings):
        if len(ring) < 2:
            continue
        if crease[i] or ang[i] > SHARP_ANGLE:
            for j in range(len(ring)):
                e = bm.edges.get((ring[j], ring[(j + 1) % len(ring)]))
                if e:
                    e.smooth = False
    bm.normal_update()
    return bm


def sweep_square(pts, half, crease=None, mat=BODY, uv_len=None):
    """Sweep a closed (d, h) profile around a square of half-size `half`.

    A profile point (d, h) becomes the square loop of half-size half + d at
    height h (Blender Z). Used for mitred board frames. Faces are mapped
    with U along the side and V along the profile arc length.
    """
    n = len(pts)
    crease = crease or [False] * n
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    s = [0.0]
    for i in range(1, n):
        s.append(s[-1] + math.dist(pts[i], pts[i - 1]))
    s_close = s[-1] + math.dist(pts[-1], pts[0])
    corners = [(1, 1), (-1, 1), (-1, -1), (1, -1)]      # CCW seen from +Z
    rings = []
    for (d, h) in pts:
        k = half + d
        rings.append([bm.verts.new((cx * k, cy * k, h)) for cx, cy in corners])
    L = uv_len or 2 * (half + max(p[0] for p in pts))
    for i in range(n):
        i2 = (i + 1) % n
        A, B = rings[i], rings[i2]
        va, vb = s[i], (s[i2] if i2 else s_close)
        for j in range(4):
            j2 = (j + 1) % 4
            f = bm.faces.new((A[j], A[j2], B[j2], B[j]))
            f.material_index = mat
            f.smooth = True
            horizontal_x = j in (0, 2)   # side runs along X
            for loop in f.loops:
                co = loop.vert.co
                u = (co.x if horizontal_x else co.y) / L + 0.5
                v = va if loop.vert in A else vb
                loop[uvl].uv = (u, v)
    ang = turn_angles(pts, True)
    for i, ring in enumerate(rings):
        if crease[i] or ang[i] > SHARP_ANGLE:
            for j in range(4):
                e = bm.edges.get((ring[j], ring[(j + 1) % 4]))
                if e:
                    e.smooth = False
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mark_sharp(bm, SHARP_ANGLE)          # mitres
    return bm


def mark_sharp(bm, angle_deg):
    """'Smooth by angle': mark edges whose dihedral angle exceeds angle_deg
    as sharp (never clears sharpness set explicitly by a generator)."""
    lim = math.radians(angle_deg)
    for e in bm.edges:
        if len(e.link_faces) != 2 or e.calc_face_angle(0.0) > lim:
            e.smooth = False


def bm_transform(bm, mat):
    bmesh.ops.transform(bm, matrix=mat, verts=bm.verts)


def bm_append(dst, src, mat=None):
    """Append all geometry of src into dst (UVs, smooth/sharp, materials)."""
    uv_d = dst.loops.layers.uv.verify()
    uv_s = src.loops.layers.uv.active
    vmap = {v: dst.verts.new(v.co) for v in src.verts}
    for f in src.faces:
        nf = dst.faces.new([vmap[v] for v in f.verts])
        nf.material_index = f.material_index if mat is None else mat
        nf.smooth = f.smooth
        if uv_s is not None:
            for ln, lo in zip(nf.loops, f.loops):
                ln[uv_d].uv = lo[uv_s].uv
    for e in src.edges:
        if not e.smooth:
            ne = dst.edges.get((vmap[e.verts[0]], vmap[e.verts[1]]))
            if ne:
                ne.smooth = False
    return dst


def box_bm(sx, sy, sz, center=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bm_transform(bm, Matrix.Translation(center) @ Matrix.Diagonal((sx, sy, sz, 1.0)))
    return bm


def cylinder_bm(radius, depth, segs=32):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs,
                          radius1=radius, radius2=radius, depth=depth)
    return bm


def uv_sphere_bm(radius, center, segs=24, rings=12, mat=TRIM):
    """UV sphere built with the lathe (so it gets UVs and smooth normals)."""
    cz = center[2]
    pts = [(radius * math.sin(math.pi * i / rings), cz - radius * math.cos(math.pi * i / rings))
           for i in range(rings + 1)]
    pts[0] = (0.0, pts[0][1])
    pts[-1] = (0.0, pts[-1][1])
    bm = lathe(pts, segs=segs, mat=mat)
    bm_transform(bm, Matrix.Translation((center[0], center[1], 0.0)))
    return bm


def triangulate_ngons(bm):
    """Deterministically triangulate n-gons (> 4 verts).

    Some operators (bevel, booleans) create n-gons whose first loop varies
    between runs; ear clipping depends on it. Rebuild each n-gon starting at
    its lowest-index vertex first, so the output is byte-for-byte stable."""
    bm.verts.index_update()
    uvl = bm.loops.layers.uv.active
    new = []
    for f in [f for f in bm.faces if len(f.verts) > 4]:
        loops = list(f.loops)
        k = min(range(len(loops)), key=lambda i: loops[i].vert.index)
        loops = loops[k:] + loops[:k]
        verts = [l.vert for l in loops]
        uvs = [l[uvl].uv.copy() for l in loops] if uvl else None
        mat, smooth = f.material_index, f.smooth
        bm.faces.remove(f)
        nf = bm.faces.new(verts)
        nf.normal_update()             # triangulate projects along the normal
        nf.material_index = mat
        nf.smooth = smooth
        if uvs:
            for l, uv in zip(nf.loops, uvs):
                l[uvl].uv = uv
        new.append(nf)
    if new:
        bmesh.ops.triangulate(bm, faces=new, quad_method='FIXED', ngon_method='EAR_CLIP')


def offset_polygon(pts, d):
    """Offset a CCW polygon inward by d with mitred corners."""
    n = len(pts)
    out = []
    for i in range(n):
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % n])
        e1 = (p1 - p0).normalized()
        e2 = (p2 - p1).normalized()
        n1 = Vector((-e1.y, e1.x))                 # left normal = inward (CCW)
        n2 = Vector((-e2.y, e2.x))
        out.append(p1 + (n1 + n2) * (d / (1.0 + n1.dot(n2))))
    return out


def extrude_outline(outline, depth, bevel=0.0, bevel_segs=2, mat=TRIM):
    """Extrude a closed 2D outline (x, z) along Y (centred on y = 0) with a
    rounded bevel of radius `bevel` on the front and back edges.

    Built directly from mitred offset outlines (quarter-round profile), so the
    topology and the cap triangulation are exact and deterministic."""
    pts = [Vector(p) for p in outline]
    area = sum(pts[i - 1].x * pts[i].y - pts[i].x * pts[i - 1].y for i in range(len(pts)))
    if area < 0:
        pts.reverse()                                # make it CCW
    h = depth / 2.0
    prof = []                                        # (inset, y) rings
    if bevel > 0:
        for k in range(bevel_segs + 1):
            phi = (math.pi / 2) * k / bevel_segs
            prof.append((bevel * (1 - math.sin(phi)), -h + bevel * (1 - math.cos(phi))))
        for k in range(bevel_segs, -1, -1):
            phi = (math.pi / 2) * k / bevel_segs
            prof.append((bevel * (1 - math.sin(phi)), h - bevel * (1 - math.cos(phi))))
    else:
        prof = [(0.0, -h), (0.0, h)]
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    rings = []
    for inset, y in prof:
        ring2d = offset_polygon(pts, inset) if inset > 0 else pts
        rings.append([bm.verts.new((q.x, y, q.y)) for q in ring2d])
    n = len(pts)
    for a_ring, b_ring in zip(rings[:-1], rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a_ring[i], a_ring[j], b_ring[j], b_ring[i]))
    # caps: triangulate the (exact) inset outline once, reuse for both ends
    tris = mathutils.geometry.tessellate_polygon([[Vector((v.co.x, v.co.z, 0.0)) for v in rings[0]]])
    for t in tris:
        bm.faces.new([rings[0][i] for i in t])
        bm.faces.new([rings[-1][i] for i in reversed(t)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.material_index = mat
        f.smooth = True
        for loop in f.loops:
            loop[uvl].uv = (loop.vert.co.x + 0.5, loop.vert.co.z)
    mark_sharp(bm, SHARP_ANGLE)
    return bm


# ---------------------------------------------------------------------------
# Blender object / modifier helpers
# ---------------------------------------------------------------------------

_MATS = {}


def materials():
    """The two shared material data-blocks: body (ivory) and trim (gold)."""
    if not _MATS:
        for name, col, metal, rough in (("body", (0.86, 0.80, 0.68, 1.0), 0.0, 0.35),
                                        ("trim", (0.83, 0.64, 0.29, 1.0), 1.0, 0.25)):
            m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
            m.diffuse_color = col
            m.metallic = metal
            m.roughness = rough
            # the OBJ/MTL exporter reads the Principled BSDF node
            bsdf = m.node_tree.nodes.get("Principled BSDF") if m.node_tree else None
            if bsdf:
                bsdf.inputs["Base Color"].default_value = col
                bsdf.inputs["Metallic"].default_value = metal
                bsdf.inputs["Roughness"].default_value = rough
            _MATS[name] = m
    return _MATS["body"], _MATS["trim"]


def bm_to_object(bm, name):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    body, trim = materials()
    me.materials.append(body)
    me.materials.append(trim)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def object_to_bm(obj, evaluated=True):
    dg = bpy.context.evaluated_depsgraph_get()
    src = obj.evaluated_get(dg) if evaluated else obj
    me = bpy.data.meshes.new_from_object(src, preserve_all_data_layers=True, depsgraph=dg)
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    return bm


def delete_object(obj):
    me = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if me and me.users == 0:
        bpy.data.meshes.remove(me)


def boolean(bm, cutters, operation='DIFFERENCE', solver='MANIFOLD'):
    """Apply boolean ops of `cutters` (list of bmesh) to `bm`; returns new bmesh.

    The result keeps the body material on every face (cut faces included).
    """
    target = bm_to_object(bm, "_bool_target")
    cut_objs = []
    for i, c in enumerate(cutters):
        o = bm_to_object(c, "_cutter%d" % i)
        o.hide_render = True
        cut_objs.append(o)
        mod = target.modifiers.new("b%d" % i, 'BOOLEAN')
        mod.operation = operation
        mod.solver = solver
        mod.object = o
    out = object_to_bm(target)
    if len(out.faces) == 0 and solver != 'EXACT':
        out.free()
        for o in cut_objs:
            delete_object(o)
        delete_object(target)
        return boolean(bm, cutters, operation, 'EXACT')
    delete_object(target)
    for o in cut_objs:
        delete_object(o)
    return out


def decimate(bm, target_tris, symmetric_x=False):
    """Quadric (collapse) decimation to ~target_tris. Symmetric mode is off by
    default: in Blender 5.2 it produced fold-over (flipped) faces."""
    tris = sum(len(f.verts) - 2 for f in bm.faces)
    if tris <= target_tris:
        return bm
    obj = bm_to_object(bm, "_decimate")
    mod = obj.modifiers.new("dec", 'DECIMATE')
    mod.decimate_type = 'COLLAPSE'
    mod.ratio = target_tris / tris
    mod.use_symmetry = symmetric_x
    mod.symmetry_axis = 'X'
    mod.use_collapse_triangulate = True
    out = object_to_bm(obj)
    delete_object(obj)
    return out


# ---------------------------------------------------------------------------
# Final assembly, validation and export
# ---------------------------------------------------------------------------

def assemble(body, trims=()):
    """Merge body + trim meshes into one bmesh, body faces first."""
    out = bmesh.new()
    out.loops.layers.uv.new("UVMap")
    bm_append(out, body, mat=BODY)
    for t in trims:
        bm_append(out, t, mat=TRIM)
    return out


def finalize(bm):
    """Clean-up common to every model before export."""
    # (no vertex welding here: generators never emit duplicates, and welding
    #  the tiny slivers a boolean junction produces would break manifoldness)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    # Godot fans n-gons: triangulate anything above a quad (booleans make n-gons)
    triangulate_ngons(bm)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.smooth = True
    mark_sharp(bm, SHARP_ANGLE)
    # keep faces sorted by material so `body` is written before `trim`
    bm.faces.sort(key=lambda f: f.material_index)
    bm.normal_update()
    return bm


def mesh_report(bm):
    """Sanity numbers: non-manifold edges, signed volume per material
    (positive = outward normals) and 'flipped' faces (facing away from every
    edge neighbour, e.g. from a bad triangulation)."""
    bm.normal_update()
    nm = sum(1 for e in bm.edges if not e.is_manifold)
    vol = [0.0, 0.0]
    for f in bm.faces:
        vs = [v.co for v in f.verts]
        for i in range(1, len(vs) - 1):
            vol[min(f.material_index, 1)] += vs[0].dot(vs[i].cross(vs[i + 1])) / 6.0
    flipped = 0
    for f in bm.faces:
        nbs = [g for e in f.edges for g in e.link_faces if g is not f]
        if nbs and all(f.normal.dot(g.normal) < -0.5 for g in nbs):
            flipped += 1
    return nm, vol, flipped


def area_weighted_normals(bm):
    """Per-corner normals: the area-weighted mean of the face normals in each
    smooth fan around a vertex (fans are split at sharp edges).

    Keeps big flat/cylindrical faces flat next to tiny fillets (no shading
    gradients along a stem). Same idea as Blender's Weighted Normal modifier,
    but deterministic (the modifier's tie-breaking between equal-area faces
    is not). Returns the normals in mesh loop order."""
    bm.normal_update()
    area = {f: f.calc_area() for f in bm.faces}
    corner = {}
    for v in bm.verts:
        loops = list(v.link_loops)
        parent = {l: l for l in loops}

        def find(x):
            while parent[x] is not x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x
        by_edge = {}
        for l in loops:
            for e in (l.edge, l.link_loop_prev.edge):
                if e.smooth:
                    by_edge.setdefault(e, []).append(l)
        for ls in by_edge.values():
            for other in ls[1:]:
                ra, rb = find(ls[0]), find(other)
                if ra is not rb:
                    parent[rb] = ra
        fans = {}
        for l in loops:
            fans.setdefault(find(l), []).append(l)
        for fan in fans.values():
            n = Vector((0.0, 0.0, 0.0))
            for l in fan:
                n += l.face.normal * area[l.face]
            if n.length < 1e-12:
                n = fan[0].face.normal.copy()
            n.normalize()
            for l in fan:
                corner[l] = n
    return [tuple(corner[l]) for f in bm.faces for l in f.loops]


def export_model(bm, path):
    """Write `bm` as OBJ (+MTL). Returns a stats dict parsed from the file."""
    name = os.path.splitext(os.path.basename(path))[0]
    finalize(bm)
    nm, vol, flipped = mesh_report(bm)
    normals = area_weighted_normals(bm)
    obj = bm_to_object(bm, name)
    obj.data.normals_split_custom_set(normals)
    for o in bpy.context.scene.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.wm.obj_export(
        filepath=path, check_existing=False,
        export_selected_objects=True, apply_modifiers=True,
        export_eval_mode='DAG_EVAL_VIEWPORT',
        forward_axis='NEGATIVE_Z', up_axis='Y', global_scale=1.0,
        export_uv=True, export_normals=True, export_colors=False,
        export_materials=True, export_pbr_extensions=False, path_mode='STRIP',
        export_triangulated_mesh=False, export_object_groups=False,
        export_material_groups=False, export_vertex_groups=False,
        export_smooth_groups=False)
    delete_object(obj)
    st = parse_obj(path)
    st["non_manifold"] = nm
    st["volume"] = vol
    st["flipped"] = flipped
    return st


def parse_obj(path):
    """Minimal OBJ parser used to verify what was actually written."""
    vs, groups, tris = [], [], 0
    per_group = {}
    cur = None
    nvn = nvt = 0
    with open(path) as fh:
        for line in fh:
            if line.startswith("v "):
                vs.append(tuple(float(x) for x in line.split()[1:4]))
            elif line.startswith("vn "):
                nvn += 1
            elif line.startswith("vt "):
                nvt += 1
            elif line.startswith("usemtl"):
                cur = line.split()[1]
                if not groups or groups[-1] != cur:
                    groups.append(cur)
            elif line.startswith("f "):
                idx = [int(tok.split("/")[0]) - 1 for tok in line.split()[1:]]
                t = len(idx) - 2
                tris += t
                per_group[cur] = per_group.get(cur, 0) + t
    V = np.array(vs)
    return {"path": path, "tris": tris, "verts": len(vs), "normals": nvn, "uvs": nvt,
            "groups": groups, "group_tris": per_group,
            "min": V.min(axis=0), "max": V.max(axis=0), "V": V}


# ---------------------------------------------------------------------------
# Chess pieces — lathed Staunton-inspired profiles
# ---------------------------------------------------------------------------
# All dimensions in board squares, Blender space (Z up). Each builder returns
# (body_bmesh, [trim_bmesh, ...]).

SEG = 64          # radial segments for chess lathes


def base_profile(P, R):
    """Weighted base: felt-pad chamfer, plinth, ovolo cushion, bead seat.

    Leaves the profile at the bead seat; returns the (r, z) centre and the
    minor radius of the gold bead ring that sits on the seat."""
    s = R / 0.25
    P.to(R - 0.020 * s, 0.0, crease=True)               # underside (felt pad)
    P.to(R - 0.005 * s, 0.011 * s, crease=True)          # felt-pad chamfer
    P.to(R, 0.016 * s, f=0.0025)
    P.to(R, 0.034 * s, f=0.0025)                         # plinth band
    P.to(R - 0.011 * s, 0.040 * s, crease=True)          # crisp step
    # ovolo (convex quarter-round cushion)
    P.bez((R - 0.004 * s, 0.050 * s), (R - 0.008 * s, 0.079 * s),
          (R - 0.042 * s, 0.084 * s), n=6, crease=True)
    P.to(R - 0.052 * s, 0.086 * s, f=0.002 * s)          # bead seat
    rho = 0.0068 * s
    return (R - 0.058 * s, 0.086 * s + rho * 0.8), rho


def collar(P, z0, r_out, t, r_top, lip=0.008, slope=0.12):
    """Crisp disc collar between z0 and z0+t (from the current stem point).

    The top face rises slightly toward the axis (`slope`) so it never reads
    as a mirror-flat disc. Returns the gold band ring wrapped around the rim."""
    P.to(r_out - lip, z0, crease=True)
    P.to(r_out, z0 + 0.35 * lip, f=0.002)
    P.to(r_out, z0 + t - 0.35 * lip, f=0.002)
    P.to(r_out - lip, z0 + t, crease=True)
    P.to(r_top, z0 + t + slope * (r_out - lip - r_top), f=0.004)
    hb = min(0.0065, t / 2 - 0.35 * lip - 0.0025)
    zc = z0 + t / 2
    pts, fl = band_profile(r_out - 0.008, r_out + 0.0035, zc - hb, zc + hb, fr=0.002)
    return lathe(pts, fl, segs=SEG, closed=True, mat=TRIM)


def small_disc(P, r_neck, z0, r_out, t, r_next):
    """A thin crisp disc (secondary collar) from the current point."""
    P.to(r_neck, z0, f=0.0025)
    P.to(r_out, z0 + 0.002, f=0.002)
    P.to(r_out, z0 + t, f=0.002)
    P.to(r_next, z0 + t + 0.004, f=0.0025)


def bead_ring(center, rho, segs=SEG, n=6):
    pts = circle_profile(center[0], center[1], rho, n=n)
    return lathe(pts, segs=segs, closed=True, mat=TRIM)


def chess_pawn():
    R = 0.22
    P = Profile(0, 0)
    bead_c, rho = base_profile(P, R)
    P.bez((0.125, 0.090), (0.094, 0.110), (0.090, 0.135), n=5, f=0.004)
    # tapered stem (slightly concave)
    P.bez((0.084, 0.200), (0.062, 0.262), (0.057, 0.298), n=6, f=0.004)
    band = collar(P, 0.298, 0.106, 0.032, 0.054)
    # short neck flaring into the head sphere
    zc, rh = 0.640 - 0.121, 0.121
    a0 = -math.degrees(math.acos(0.050 / rh))
    P.bez((0.051, 0.350), (0.050, 0.380), (0.050, zc + rh * math.sin(math.radians(a0))),
          n=4, f=0.012)
    P.arc((0.0, zc), 90.0, n=14)
    pts, fl = P.build()
    body = lathe(pts, fl, segs=SEG)
    return body, [bead_ring(bead_c, rho), band]


def chess_rook():
    R = 0.25
    P = Profile(0, 0)
    bead_c, rho = base_profile(P, R)
    P.bez((0.150, 0.092), (0.152, 0.110), (0.150, 0.135), n=5, f=0.004)
    # sturdy tower, gently tapering
    P.bez((0.146, 0.260), (0.132, 0.420), (0.128, 0.478), n=6, f=0.003)
    band = collar(P, 0.478, 0.152, 0.034, 0.132)
    # flared turret
    P.bez((0.136, 0.540), (0.172, 0.560), (0.176, 0.600), n=8, f=0.003)
    P.to(0.176, 0.740, f=0.004)
    P.to(0.132, 0.740, f=0.003)                 # rim top
    P.to(0.132, 0.668, f=0.006)                 # inner wall (hollow)
    P.to(0.0, 0.668)                            # floor
    pts, fl = P.build()
    body = lathe(pts, fl, segs=SEG)
    # 5 crenellation notches
    cutters = []
    for k in range(5):
        a = TAU * k / 5 + TAU / 20
        c = box_bm(0.20, 0.066, 0.14, center=(0.20, 0.0, 0.742 + 0.07 - 0.066))
        bm_transform(c, Matrix.Rotation(a, 4, 'Z'))
        cutters.append(c)
    body = boolean(body, cutters)
    return body, [bead_ring(bead_c, rho), band]


def chess_bishop():
    R = 0.25
    P = Profile(0, 0)
    bead_c, rho = base_profile(P, R)
    P.bez((0.140, 0.090), (0.104, 0.110), (0.100, 0.138), n=5, f=0.004)
    P.bez((0.092, 0.260), (0.058, 0.400), (0.053, 0.468), n=6, f=0.004)
    band = collar(P, 0.468, 0.108, 0.030, 0.060)
    small_disc(P, 0.060, 0.504, 0.082, 0.012, 0.052)
    # mitre (teardrop)
    P.bez((0.082, 0.526), (0.107, 0.578), (0.107, 0.645), n=7)
    P.bez((0.107, 0.728), (0.052, 0.812), (0.016, 0.868), n=9)
    P.to(0.011, 0.884, f=0.003)
    P.to(0.0, 0.890)
    pts, fl = P.build()
    body = lathe(pts, fl, segs=SEG)
    # diagonal slit: a thin slab entering from the -Y side (Godot +Z)
    slab = box_bm(0.40, 0.40, 0.021, center=(0.0, -0.20 + 0.030, 0.0))
    bm_transform(slab, Matrix.Translation((0.0, 0.0, 0.708)) @ Matrix.Rotation(math.radians(-42), 4, 'Y'))
    body = boolean(body, [slab])
    ball = uv_sphere_bm(0.029, (0.0, 0.0, 0.940 - 0.029), segs=24, rings=12)
    return body, [bead_ring(bead_c, rho), band, ball]


def chess_queen():
    R = 0.27
    P = Profile(0, 0)
    bead_c, rho = base_profile(P, R)
    P.bez((0.150, 0.098), (0.116, 0.118), (0.112, 0.150), n=5, f=0.004)
    P.bez((0.100, 0.320), (0.062, 0.480), (0.057, 0.560), n=4, f=0.004)
    band = collar(P, 0.560, 0.120, 0.034, 0.068)
    small_disc(P, 0.068, 0.603, 0.100, 0.013, 0.062)
    # crown: trumpet flare ending in a rolled lip
    P.bez((0.064, 0.700), (0.080, 0.830), (0.126, 0.895), n=7)
    P.bez((0.134, 0.906), (0.138, 0.918), (0.137, 0.928), n=2)
    rim_z = 0.940
    P.to(0.137, rim_z, f=0.0025)
    P.to(0.110, rim_z + 0.002, f=0.0025)
    P.bez((0.100, 0.915), (0.075, 0.905), (0.052, 0.912), n=3)            # inner bowl
    P.bez((0.038, 0.918), (0.030, 0.940), (0.030, 0.962), n=3)           # finial neck
    zc, rb = 1.060 - 0.044, 0.044
    P.to(0.030, zc - math.sqrt(rb * rb - 0.030 ** 2), f=0.005)
    P.arc((0.0, zc), 90.0, n=8)
    pts, fl = P.build()
    body = lathe(pts, fl, segs=SEG)
    # 8 round-bottomed notches leave 8 coronet points
    cutters = []
    for k in range(8):
        a = TAU * (k + 0.5) / 8
        c = cylinder_bm(0.023, 0.14, segs=20)
        bm_transform(c, Matrix.Rotation(a, 4, 'Z') @ Matrix.Translation((0.14, 0, rim_z + 0.004))
                     @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
        cutters.append(c)
    body = boolean(body, cutters)
    balls = []
    for k in range(8):
        a = TAU * k / 8
        r = 0.1235
        balls.append(uv_sphere_bm(0.0165, (r * math.cos(a), r * math.sin(a), rim_z + 0.011),
                                  segs=10, rings=5))
    return body, [bead_ring(bead_c, rho), band] + balls


def cross_outline(h, span, bar, flare=0.010, arm_z=0.62):
    """Latin cross outline in (x, z), base at z=0, slightly flared arm ends."""
    b = bar / 2
    zc = h * arm_z                      # centre of the transverse arm
    hs = span / 2
    f = flare
    return [
        (-b, 0.0), (b, 0.0),                         # foot
        (b, zc - b), (hs, zc - b - f), (hs, zc + b + f), (b, zc + b),   # right arm
        (b + f, h), (-b - f, h),                     # top (flared)
        (-b, zc + b), (-hs, zc + b + f), (-hs, zc - b - f), (-b, zc - b),  # left arm
    ]


def chess_king():
    R = 0.28
    P = Profile(0, 0)
    bead_c, rho = base_profile(P, R)
    P.bez((0.155, 0.100), (0.122, 0.122), (0.118, 0.156), n=5, f=0.004)
    P.bez((0.106, 0.340), (0.066, 0.540), (0.061, 0.620), n=5, f=0.004)
    band = collar(P, 0.620, 0.127, 0.036, 0.072)
    small_disc(P, 0.072, 0.665, 0.106, 0.015, 0.066)
    # crown: trumpet flare into a crisp band, closed by a dome
    P.bez((0.068, 0.780), (0.090, 0.880), (0.128, 0.925), n=7)
    P.to(0.137, 0.930, f=0.002)
    P.to(0.137, 0.955, f=0.0025)                 # band
    P.to(0.122, 0.959, f=0.0025)
    P.bez((0.114, 0.994), (0.072, 1.024), (0.032, 1.028), n=6, f=0.004)  # dome
    zc, rb = 1.046, 0.028                        # knob the cross stands on
    P.to(0.022, zc - math.sqrt(rb * rb - 0.022 ** 2), f=0.004)
    P.arc((0.0, zc), 90.0, n=6)
    pts, fl = P.build()
    body = lathe(pts, fl, segs=SEG)
    # beveled cross (trim), arms along X so both players read it
    h = 0.166
    ol = cross_outline(h, 0.132, 0.042, flare=0.008)
    cross = extrude_outline(ol, 0.036, bevel=0.006, bevel_segs=3)
    bm_transform(cross, Matrix.Translation((0.0, 0.0, 1.200 - h)))
    return body, [bead_ring(bead_c, rho), band, cross]


# ---------------------------------------------------------------------------
# Chess knight — SDF sculpt meshed with OpenVDB, unioned with a lathed base
# ---------------------------------------------------------------------------
# Side silhouette of the head + neck in (y, z); +y is the snout direction.
KNIGHT_SILHOUETTE = [
    # bottom (hidden inside the collar)
    (-0.150, 0.150), (0.100, 0.150),
    # chest / front of neck
    (0.124, 0.205), (0.134, 0.265), (0.128, 0.325), (0.108, 0.378),
    # throat (concave)
    (0.080, 0.420), (0.068, 0.452),
    # under the jaw
    (0.082, 0.480), (0.118, 0.488), (0.152, 0.482),
    # chin and lower lip
    (0.184, 0.478), (0.210, 0.486), (0.228, 0.501),
    # mouth / muzzle front
    (0.240, 0.522), (0.247, 0.550), (0.243, 0.578),
    # nose
    (0.228, 0.604), (0.202, 0.630),
    # face / nose bridge
    (0.162, 0.672), (0.126, 0.712),
    # forehead
    (0.090, 0.750), (0.052, 0.780),
    # poll (top of the head)
    (0.012, 0.798), (-0.028, 0.790),
    # back of the neck (the mane is added on top of this)
    (-0.060, 0.755), (-0.092, 0.698), (-0.120, 0.620), (-0.140, 0.530),
    (-0.152, 0.430), (-0.156, 0.330), (-0.153, 0.240), (-0.148, 0.185),
]

# Mane spine: follows the back of the neck, slightly inside the silhouette.
KNIGHT_MANE = [(-0.010, 0.792), (-0.050, 0.765), (-0.085, 0.712), (-0.113, 0.640),
               (-0.133, 0.555), (-0.145, 0.460), (-0.150, 0.365), (-0.149, 0.275),
               (-0.145, 0.205)]


def open_catmull_rom(points, n_per=10):
    """Open centripetal Catmull-Rom through `points` (end points duplicated)."""
    P = [tuple(points[0])] + [tuple(p) for p in points] + [tuple(points[-1])]
    P[0] = (2 * P[1][0] - P[2][0], 2 * P[1][1] - P[2][1])
    P[-1] = (2 * P[-2][0] - P[-3][0], 2 * P[-2][1] - P[-3][1])
    full = catmull_rom_closed(P, n_per=n_per)
    # keep only the segments between the real points (plus the last point)
    return full[n_per:len(points) * n_per + 1]


def polyline_coords(poly, Y, Z):
    """Arc-length parameter of the closest point on an open polyline and the
    distance to it, for every (y, z) sample."""
    py, pz = Y.ravel(), Z.ravel()
    best = np.full(py.shape, np.inf)
    tpar = np.zeros(py.shape)
    acc = 0.0
    for i in range(len(poly) - 1):
        ay, az = poly[i]
        by, bz = poly[i + 1]
        ey, ez = by - ay, bz - az
        ln = math.hypot(ey, ez)
        t = np.clip(((py - ay) * ey + (pz - az) * ez) / (ln * ln), 0.0, 1.0)
        dy, dz = py - ay - ey * t, pz - az - ez * t
        d = dy * dy + dz * dz
        m = d < best
        best[m] = d[m]
        tpar[m] = acc + t[m] * ln
        acc += ln
    return tpar.reshape(Y.shape), np.sqrt(best).reshape(Y.shape)


def polygon_sdf(poly, Y, Z):
    """Signed distance to a closed polygon in (y, z) (negative inside)."""
    py, pz = Y.ravel(), Z.ravel()
    d2 = np.full(py.shape, np.inf)
    inside = np.zeros(py.shape, dtype=bool)
    n = len(poly)
    for i in range(n):
        ay, az = poly[i]
        by, bz = poly[(i + 1) % n]
        ey, ez = by - ay, bz - az
        wy, wz = py - ay, pz - az
        t = np.clip((wy * ey + wz * ez) / (ey * ey + ez * ez), 0.0, 1.0)
        dy, dz = wy - ey * t, wz - ez * t
        np.minimum(d2, dy * dy + dz * dz, out=d2)
        cond = ((az > pz) != (bz > pz)) & (py < ey * (pz - az) / (ez if ez != 0 else 1e-30) + ay)
        inside ^= cond
    d = np.sqrt(d2)
    d[inside] *= -1.0
    return d.reshape(Y.shape)


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def _rot(ax, ay, az):
    """Rotation matrix from XYZ Euler angles in degrees."""
    return np.array(Matrix.Rotation(math.radians(az), 3, 'Z') @
                    Matrix.Rotation(math.radians(ay), 3, 'Y') @
                    Matrix.Rotation(math.radians(ax), 3, 'X'))


def sd_ellipsoid(X, Y, Z, c, radii, rot=None):
    px, py, pz = X - c[0], Y - c[1], Z - c[2]
    if rot is not None:
        R = rot.T      # world -> local
        px, py, pz = (R[0, 0] * px + R[0, 1] * py + R[0, 2] * pz,
                      R[1, 0] * px + R[1, 1] * py + R[1, 2] * pz,
                      R[2, 0] * px + R[2, 1] * py + R[2, 2] * pz)
    rx, ry, rz = radii
    k0 = np.sqrt((px / rx) ** 2 + (py / ry) ** 2 + (pz / rz) ** 2)
    k1 = np.sqrt((px / rx ** 2) ** 2 + (py / ry ** 2) ** 2 + (pz / rz ** 2) ** 2)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def sd_sphere(X, Y, Z, c, r):
    return np.sqrt((X - c[0]) ** 2 + (Y - c[1]) ** 2 + (Z - c[2]) ** 2) - r


def sd_round_cone(X, Y, Z, a, b, r1, r2):
    """Cone with spherical caps of radius r1 at a and r2 at b (iq)."""
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    ba = b - a
    l2 = ba.dot(ba)
    rr = r1 - r2
    a2 = l2 - rr * rr
    il2 = 1.0 / l2
    px, py, pz = X - a[0], Y - a[1], Z - a[2]
    y = px * ba[0] + py * ba[1] + pz * ba[2]
    z = y - l2
    qx, qy, qz = px * l2 - ba[0] * y, py * l2 - ba[1] * y, pz * l2 - ba[2] * y
    x2 = qx * qx + qy * qy + qz * qz
    y2 = y * y * l2
    z2 = z * z * l2
    k = np.sign(rr) * rr * rr * x2
    res = (np.sqrt(x2 * a2 * il2) + y * rr) * il2 - r1
    res = np.where(np.sign(z) * a2 * z2 > k, np.sqrt(x2 + z2) * il2 - r2, res)
    res = np.where(np.sign(y) * a2 * y2 < k, np.sqrt(x2 + y2) * il2 - r1, res)
    return res


class SDFGrid:
    """Dense sampling grid for an SDF sculpt, with sub-box feature updates."""

    def __init__(self, lo, hi, vox):
        self.vox = vox
        self.lo = np.asarray(lo, float)
        nx = int(math.ceil((hi[0] - lo[0]) / vox)) + 1
        ny = int(math.ceil((hi[1] - lo[1]) / vox)) + 1
        nz = int(math.ceil((hi[2] - lo[2]) / vox)) + 1
        if nx % 2 == 0:
            nx += 1                   # odd count: x = 0 is a sample plane
        self.lo[0] = -(nx - 1) / 2 * vox
        self.xs = self.lo[0] + np.arange(nx) * vox
        self.ys = self.lo[1] + np.arange(ny) * vox
        self.zs = self.lo[2] + np.arange(nz) * vox
        self.shape = (nx, ny, nz)

    def sub(self, bmin, bmax):
        """Index slices + coordinate arrays of a sub-box."""
        sl = []
        co = []
        for ax, (a, b) in enumerate(zip(bmin, bmax)):
            arr = (self.xs, self.ys, self.zs)[ax]
            i0 = max(0, int(np.searchsorted(arr, a)) - 1)
            i1 = min(len(arr), int(np.searchsorted(arr, b)) + 1)
            sl.append(slice(i0, i1))
            co.append(arr[i0:i1])
        X = co[0][:, None, None]
        Y = co[1][None, :, None]
        Z = co[2][None, None, :]
        return tuple(sl), X, Y, Z


def knight_head_sdf(vox=0.0025):
    """Sculpt the knight's head + neck as a signed distance field."""
    g = SDFGrid((-0.115, -0.205, 0.140), (0.115, 0.270, 0.885), vox)
    # --- 2D silhouette, variable-width rounded extrusion -------------------
    sil = catmull_rom_closed(KNIGHT_SILHOUETTE, n_per=12)
    Y2, Z2 = np.meshgrid(g.ys, g.zs, indexing='ij')
    d2 = polygon_sdf(sil, Y2, Z2)
    # half-width: broad chest, slimmer neck, head tapering to the muzzle
    w_neck = lerp(0.094, 0.071, smoothstep(0.20, 0.50, Z2))
    w_head = lerp(0.074, 0.049, smoothstep(0.05, 0.245, Y2))
    head = smoothstep(0.44, 0.56, Z2) * smoothstep(-0.06, 0.06, Y2)
    w = lerp(w_neck, w_head, head)
    w *= lerp(1.0, 0.86, smoothstep(0.74, 0.80, Z2))       # narrower poll
    rr = np.minimum(lerp(0.050, 0.034, head), w - 0.008)       # edge rounding
    X = g.xs[:, None, None]
    a = (d2 + rr)[None, :, :]
    b = np.abs(X) - (w - rr)[None, :, :]
    f = (np.minimum(np.maximum(a, b), 0.0) +
         np.sqrt(np.maximum(a, 0.0) ** 2 + np.maximum(b, 0.0) ** 2) - rr[None, :, :])
    f = f.astype(np.float32)

    def feature(bmin, bmax, fn, op, k):
        # features are mirrored (evaluated on |x|): cover both sides
        xm = max(abs(bmin[0]), abs(bmax[0]))
        sl, Xs, Ys, Zs = g.sub((-xm, bmin[1], bmin[2]), (xm, bmax[1], bmax[2]))
        f[sl] = op(f[sl], fn(np.abs(Xs), Ys, Zs), k).astype(np.float32)

    def add(bmin, bmax, fn, k):
        feature(bmin, bmax, fn, smin, k)

    def cut(bmin, bmax, fn, k):
        feature(bmin, bmax, lambda X, Y, Z: -fn(X, Y, Z), smax, k)

    # --- mane: a ridge along the back of the neck, carved into chevron locks --
    spine = open_catmull_rom(KNIGHT_MANE, n_per=10)
    t2, dn2 = polyline_coords(spine, Y2, Z2)       # arc length / distance (2D)
    L = float(np.sum(np.linalg.norm(np.diff(spine, axis=0), axis=1)))
    u2 = t2 / L
    taper2 = (0.35 + 0.65 * smoothstep(0.0, 0.12, u2)) * (1.0 - 0.30 * smoothstep(0.55, 1.0, u2))
    n_locks = 12.0

    def mane(X, Y, Z, sl):
        t = t2[sl[1], sl[2]][None]
        dn = dn2[sl[1], sl[2]][None]
        tp = taper2[sl[1], sl[2]][None]
        phase = (t + 0.85 * X) / (L / n_locks)      # chevrons: grooves slant down/out
        notch = (0.5 + 0.5 * np.cos(TAU * phase)) ** 4
        sc = tp * (1.0 - 0.20 * notch)
        ax, ad = 0.050 * sc, 0.033 * sc
        return (np.sqrt((X / ax) ** 2 + (dn / ad) ** 2) - 1.0) * np.minimum(ax, ad)
    sl, Xs, Ys, Zs = g.sub((-0.07, -0.21, 0.16), (0.07, 0.03, 0.83))
    f[sl] = smin(f[sl], mane(np.abs(Xs), Ys, Zs, sl), 0.008).astype(np.float32)

    # --- ears: leaf-shaped (round cones flattened sideways), splayed outward,
    #     hollowed on the front face ------------------------------------------
    def ear(X, Y, Z, a, b, r1, r2, flat=0.70):
        cx = 0.5 * (a[0] + b[0])
        return sd_round_cone(cx + (X - cx) / flat, Y, Z, a, b, r1, r2) * flat
    add((0.0, -0.05, 0.72), (0.10, 0.07, 0.89),
        lambda X, Y, Z: ear(X, Y, Z, (0.036, 0.016, 0.780), (0.049, -0.004, 0.848), 0.033, 0.0115),
        0.012)
    cut((0.0, -0.03, 0.75), (0.10, 0.08, 0.89),
        lambda X, Y, Z: ear(X, Y, Z, (0.038, 0.036, 0.792), (0.049, 0.010, 0.846), 0.016, 0.005),
        0.003)
    # forelock between the ears
    add((0.0, 0.0, 0.74), (0.05, 0.09, 0.82),
        lambda X, Y, Z: sd_ellipsoid(X, Y, Z, (0.0, 0.044, 0.780), (0.024, 0.034, 0.015),
                                     _rot(-38, 0, 0)), 0.010)

    # --- cheeks (round jaw) ---------------------------------------------------
    add((0.0, -0.05, 0.47), (0.10, 0.15, 0.68),
        lambda X, Y, Z: sd_ellipsoid(X, Y, Z, (0.036, 0.050, 0.572), (0.048, 0.078, 0.068),
                                     _rot(-40, 0, 0)), 0.022)
    # --- eyes: brow ridge, socket, eyeball ------------------------------------
    add((0.02, 0.04, 0.68), (0.10, 0.13, 0.75),
        lambda X, Y, Z: sd_ellipsoid(X, Y, Z, (0.058, 0.086, 0.716), (0.022, 0.030, 0.013),
                                     _rot(-30, 0, 0)), 0.010)
    cut((0.03, 0.04, 0.66), (0.13, 0.13, 0.75),
        lambda X, Y, Z: sd_sphere(X, Y, Z, (0.094, 0.084, 0.702), 0.027), 0.004)
    add((0.03, 0.05, 0.67), (0.10, 0.12, 0.74),
        lambda X, Y, Z: sd_sphere(X, Y, Z, (0.064, 0.085, 0.702), 0.0145), 0.002)
    # --- nostrils ---------------------------------------------------------------
    add((0.0, 0.18, 0.54), (0.08, 0.27, 0.63),
        lambda X, Y, Z: sd_ellipsoid(X, Y, Z, (0.032, 0.222, 0.586), (0.020, 0.022, 0.026),
                                     _rot(-30, 0, 0)), 0.010)
    cut((0.0, 0.20, 0.55), (0.07, 0.27, 0.62),
        lambda X, Y, Z: sd_ellipsoid(X, Y, Z, (0.040, 0.238, 0.590), (0.0065, 0.010, 0.019),
                                     _rot(-28, 0, 30)), 0.003)
    # --- mouth line: groove engraved only within a few mm of the surface --------
    sl, Xs, Ys, Zs = g.sub((-0.08, 0.15, 0.48), (0.08, 0.27, 0.56))
    zl = 0.523 + 0.10 * (Ys - 0.240)
    slab = np.maximum(np.abs(Zs - zl) - 0.0052 * smoothstep(0.180, 0.215, Ys), 0.180 - Ys)
    slab = np.maximum(slab, 0.024 - np.abs(Xs))          # sides only
    groove = np.maximum(slab, -(f[sl] + 0.0045))
    f[sl] = smax(f[sl], -groove, 0.0045).astype(np.float32)

    # bottom: clip inside the collar
    Z = g.zs[None, None, :]
    f = np.maximum(f, (0.165 - Z).astype(np.float32))
    return g, f


def sdf_to_bmesh(g, f, adaptivity=0.0):
    import openvdb as vdb
    grid = vdb.FloatGrid(float(g.vox * 4))
    grid.copyFromArray(np.ascontiguousarray(f, dtype=np.float32))
    pts, tris, quads = grid.convertToPolygons(0.0, adaptivity)
    pts = pts.astype(np.float64) * g.vox + g.lo[None, :]
    me = bpy.data.meshes.new("_sdf")
    faces = [tuple(q) for q in quads.tolist()] + [tuple(t) for t in tris.tolist()]
    me.from_pydata(pts.tolist(), [], faces)
    me.validate()
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def cylindrical_uv(bm, yc=0.0):
    """Cylindrical projection around the vertical axis (seam at the back)."""
    uvl = bm.loops.layers.uv.verify()
    for f in bm.faces:
        us = []
        for loop in f.loops:
            co = loop.vert.co
            us.append(math.atan2(co.x, co.y - yc) / TAU + 0.5)
        if max(us) - min(us) > 0.5:
            us = [u + 1.0 if u < 0.5 else u for u in us]
        for loop, u in zip(f.loops, us):
            loop[uvl].uv = (u, loop.vert.co.z)


def chess_knight():
    R = 0.25
    top = 0.190                      # collar top the neck rests on
    P = Profile(0, 0)
    bead_c, rho = base_profile(P, R)
    P.bez((0.150, 0.090), (0.140, 0.102), (0.138, 0.120), n=6, f=0.004)
    P.to(0.132, 0.150, f=0.004)
    band = collar(P, 0.150, 0.180, 0.040, 0.0, slope=0.0)
    pts, fl = P.build()
    pts[-1] = (0.0, pts[-1][1])
    base = lathe(pts, fl, segs=SEG)
    # head
    t0 = time.time()
    g, f = knight_head_sdf()
    head = sdf_to_bmesh(g, f)
    raw = len(head.faces)
    head = decimate(head, 13500)
    # exact height: stretch the head so the ear tips reach 0.86
    zmax = max(v.co.z for v in head.verts)
    k = (0.860 - top) / (zmax - top)
    for v in head.verts:
        v.co.z = top + (v.co.z - top) * k
    for fc in head.faces:
        fc.smooth = True
        fc.material_index = BODY
    cylindrical_uv(head, yc=0.03)
    print("  knight head: %d raw faces -> %d tris (%.1fs)" %
          (raw, sum(len(fc.verts) - 2 for fc in head.faces), time.time() - t0))
    body = boolean(base, [head], operation='UNION')
    return body, [bead_ring(bead_c, rho), band]


# ---------------------------------------------------------------------------
# Boards (shared by both games)
# ---------------------------------------------------------------------------

def square_tile():
    """1x1 playing square, 0.07 thick with a 0.01 rounded top edge."""
    t, b = 0.07, 0.01
    bm = box_bm(1.0, 1.0, t, center=(0, 0, t / 2))
    top = [e for e in bm.edges if all(abs(v.co.z - t) < 1e-6 for v in e.verts)]
    bmesh.ops.bevel(bm, geom=top, offset=b, offset_type='OFFSET', segments=2,
                    profile=0.5, affect='EDGES', clamp_overlap=True)
    uvl = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        f.smooth = True
        n = f.normal
        for loop in f.loops:
            co = loop.vert.co
            if n.z > 0.3:                       # top + bevel: planar, 0..1
                loop[uvl].uv = (co.x + 0.5, co.y + 0.5)
            elif abs(n.x) > abs(n.y):           # sides
                loop[uvl].uv = (co.y + 0.5, co.z)
            else:
                loop[uvl].uv = (co.x + 0.5, co.z)
    mark_sharp(bm, SHARP_ANGLE)
    return bm, []


def board_base():
    """8x8 slab under the squares (top at 0, 0.10 thick)."""
    bm = box_bm(8.0, 8.0, 0.10, center=(0, 0, -0.05))
    uvl = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        for loop in f.loops:
            co = loop.vert.co
            loop[uvl].uv = (co.x / 8 + 0.5, co.y / 8 + 0.5) if abs(f.normal.z) > 0.5 else \
                (co.x / 8 + co.y / 8 + 0.5, co.z)
    mark_sharp(bm, SHARP_ANGLE)
    return bm, []


FRAME_W = 0.60
FRAME_TOP = 0.10
FRAME_BOTTOM = -0.12


def frame_profile_ogee():
    """Chess frame section (d outward from the play area, h height): flat
    top, a small step then an ogee (cyma) moulding down to a plinth."""
    W, T, B = FRAME_W, FRAME_TOP, FRAME_BOTTOM
    P = Profile(0.0, B)                       # inner wall bottom
    P.to(0.0, T - 0.006, crease=True)
    P.to(0.006, T, crease=True)               # tiny chamfer at the inner lip
    P.to(0.300, T, f=0.004)                   # flat top
    P.to(0.312, T - 0.010, f=0.003)           # small step down
    P.to(0.330, T - 0.012, f=0.003)
    # ogee: convex then concave
    P.bez((0.380, T - 0.012), (0.405, T - 0.050), (0.440, T - 0.068), n=12)
    P.bez((0.475, T - 0.086), (0.520, T - 0.092), (0.540, T - 0.120), n=12, f=0.004)
    P.to(0.548, T - 0.126, crease=True)       # fillet step
    P.to(W - 0.012, T - 0.126, f=0.004)
    # bead + vertical plinth
    P.bez((W + 0.002, T - 0.128), (W + 0.002, T - 0.160), (W - 0.004, T - 0.168), n=8, crease=True)
    P.to(W, T - 0.172, f=0.003)
    P.to(W, B + 0.008, f=0.003)
    P.to(W - 0.008, B, crease=True)
    return P


def frame_profile_bullnose():
    """Checkers frame section: bold rounded bullnose with a cove below."""
    W, T, B = FRAME_W, FRAME_TOP, FRAME_BOTTOM
    P = Profile(0.0, B)
    P.to(0.0, T - 0.008, crease=True)
    P.to(0.008, T, crease=True)
    P.to(0.360, T, f=0.004)
    # bullnose: big half-round over the outer edge
    rn = 0.080
    P.to(W - rn, T, f=0.0)
    P.arc((W - rn, T - rn), 0.0, n=14)
    P.arc((W - rn, T - rn), -90.0, n=12, crease=True)
    # cove under the nose then plinth
    P.to(W - 0.050, T - 2 * rn, f=0.002)
    P.bez((W - 0.050, T - 2 * rn - 0.02), (W - 0.010, T - 2 * rn - 0.03),
          (W, T - 2 * rn - 0.035), n=8, crease=True)
    P.to(W, B + 0.008, f=0.003)
    P.to(W - 0.008, B, crease=True)
    return P


def board_frame(style):
    P = frame_profile_ogee() if style == "ogee" else frame_profile_bullnose()
    pts, fl = P.build(closed=True)
    body = sweep_square(pts, 4.0, fl)
    trims = []
    # gold inlay stripe on the frame top, just outside the play area
    d0, d1 = 0.060, 0.095
    inlay = [(d0, FRAME_TOP - 0.008), (d1, FRAME_TOP - 0.008),
             (d1, FRAME_TOP + 0.0018), (d0, FRAME_TOP + 0.0018)]
    trims.append(sweep_square(inlay, 4.0, [True] * 4, mat=TRIM))
    # corner rosettes
    for cx, cy in ((1, 1), (-1, 1), (-1, -1), (1, -1)):
        c = 4.0 + 0.200
        trims.append(rosette((cx * c, cy * c, FRAME_TOP)))
    return body, trims


def rosette(center, radius=0.075, petals=8, segs=64):
    """Low gold rosette: scalloped dome with a central boss."""
    x0, y0, z0 = center
    P = Profile(0.0, z0 - 0.006)
    P.to(radius, z0 - 0.006, crease=True)
    P.to(radius, z0 + 0.002, f=0.002)
    P.bez((radius * 0.9, z0 + 0.007), (radius * 0.55, z0 + 0.008), (radius * 0.40, z0 + 0.007), n=6)
    P.to(radius * 0.36, z0 + 0.0065, crease=True)
    P.bez((radius * 0.30, z0 + 0.012), (radius * 0.12, z0 + 0.016), (0.0, z0 + 0.016), n=6)
    pts, fl = P.build()
    petal = lambda i, a: 0.0 if pts[i][0] < radius * 0.38 else \
        -pts[i][0] * 0.16 * (1.0 - abs(math.cos(petals * a / 2.0)) ** 0.7)
    bm = lathe(pts, fl, segs=segs, radial_fn=petal, mat=TRIM)
    bm_transform(bm, Matrix.Translation((x0, y0, 0.0)))
    return bm


# ---------------------------------------------------------------------------
# Checkers pieces — reeded discs
# ---------------------------------------------------------------------------
# The disc lathe uses three ring resolutions (they must divide each other
# where they meet): the reeded rim, the visible top, and the low-importance
# underside / seam between the king's two discs.
CK_R = 0.38          # man radius (diameter 0.76)
CK_H = 0.15          # man height
REEDS = 60
RES = {"rim": REEDS * 4,      # 240: four samples per reed
       "fade": REEDS * 4,     # 240: reeds running out on the top rounding
       "top": REEDS * 2,      # 120: top rounding + top face (+ gold ring)
       "low": REEDS * 4 // 3}  # 80: underside, lower roundings
REED_AMP = {"rim": 1.0, "fade": 0.45}
REED_DEPTH = 0.0045
RB, RT = 0.022, 0.026          # bottom / top edge rounding radii


def reed_offset(a):
    """Convex reeds with crisp valleys: 0 on the ridge, -1 in the valley."""
    p = (a * REEDS / TAU + 0.5) % 1.0          # a ridge sits on every axis
    return math.sqrt(max(0.0, 1.0 - (2.0 * p - 1.0) ** 2)) - 1.0


def groove(P, rc, w=0.012, d=0.003, n=4):
    """Shallow circular groove centred at radius rc (profile runs inward)."""
    zt = P.cur[1]
    rad = (w * w / 4 + d * d) / (2 * d)
    cz = zt + rad - d
    P.to(rc + w / 2, zt, crease=True)
    a1 = math.degrees(math.atan2(zt - cz, -w / 2))
    P.arc((rc, cz), a1 if a1 < 0 else a1 - 360.0, n=n, crease=True)


def disc_profile(P, z0, R, H, bottom="felt", top="decor", king_top=False):
    """Append one checkers disc (base z0, radius R, height H) to profile P.

    bottom: "felt" (flat underside from the axis) or "seam" (rests on the
            disc below; continues from the lower disc's top rounding)
    top:    "decor" (grooves, gold-ring seat, recessed centre; closes on the
            axis) or "seam" (stops after the top rounding)
    Returns a dict with the gold ring radii and recess floor height."""
    k = R / CK_R
    P.tag = "low"
    P.to(R - RB, z0, crease=(bottom == "felt"))
    P.arc((R - RB, z0 + RB), 0.0, n=3)
    P.tag = "rim"
    P.tags[-1] = "rim"                              # both rim rings are reeded
    P.crease[-1] = False
    P.to(R, z0 + H - RT)                            # reeded side
    P.tag = "low" if top == "seam" else "top"
    P.arc((R - RT, z0 + H - RT), 90.0, n=3)
    P.tags[-3] = "fade"                              # first ring of the rounding
    info = {}
    if top == "seam":
        return info
    zt = z0 + H
    groove(P, 0.305 * k)                           # outer groove
    info["ring"] = (0.250 * k, 0.2585 * k)         # gold ring (hidden seat)
    rc = 0.185 * k if king_top else 0.170 * k
    if not king_top:
        groove(P, 0.2145 * k)                      # inner groove
    P.to(rc, zt, crease=True)                      # recessed centre
    P.bez((rc - 0.004, zt), (rc - 0.004, zt - 0.005), (rc - 0.010, zt - 0.005), n=3, crease=True)
    P.to(0.0, zt - 0.005)
    info["centre_z"] = zt - 0.005
    return info


def lathe_disc(P):
    """Lathe a disc profile, reeding the rim-tagged rings."""
    pts, fl = P.build()
    tags = P.built_tags
    ring_segs = [RES[t or "low"] for t in tags]

    def radial(i, a):
        amp = REED_AMP.get(tags[i], 0.0)
        return amp * REED_DEPTH * reed_offset(a) if amp else 0.0
    return lathe(pts, fl, ring_segs=ring_segs, radial_fn=radial, mat=BODY)


def gold_inlay_ring(r0, r1, z_top, depth=0.0075):
    """Flat gold ring set into the top face, 1.5 mm proud (no coplanar faces)."""
    pts = [(r0, z_top - depth), (r1, z_top - depth), (r1, z_top + 0.0015), (r0, z_top + 0.0015)]
    return lathe(pts, [True] * 4, segs=RES["top"], closed=True, mat=TRIM)


def checkers_man():
    P = Profile(0.0, 0.0, tag="low")
    info = disc_profile(P, 0.0, CK_R, CK_H)
    body = lathe_disc(P)
    return body, [gold_inlay_ring(*info["ring"], CK_H)]


def crown_outline():
    """Stylised 5-point coronet outline (x, y), ~0.30 wide, band at the bottom."""
    w = 0.150
    yb0, yb1 = -0.092, -0.040          # band
    pts = [(-w + 0.012, yb0), (w - 0.012, yb0), (w, yb0 + 0.012), (w, yb1)]
    # points: outer, inner, centre, inner, outer with V valleys between
    tips = [(0.132, 0.070), (0.068, 0.046), (0.0, 0.090), (-0.068, 0.046), (-0.132, 0.070)]
    valleys = [(0.100, -0.004), (0.034, 0.002), (-0.034, 0.002), (-0.100, -0.004)]
    pts.append((w - 0.004, yb1 + 0.006))
    seq = [tips[0], valleys[0], tips[1], valleys[1], tips[2], valleys[2], tips[3], valleys[3], tips[4]]
    pts += seq
    pts.append((-w + 0.004, yb1 + 0.006))
    pts += [(-w, yb1), (-w, yb0 + 0.012)]
    return pts, tips


def crown_emblem(z_floor, height=0.012):
    """Gold low-relief coronet lying on the top face (its 'up' is +Y, i.e.
    Godot -Z: it reads upright to a camera on the +Z side of the board)."""
    ol, tips = crown_outline()
    t = height + 0.004                      # 4 mm embedded in the floor
    em = extrude_outline(ol, t, bevel=0.0025, bevel_segs=2, mat=TRIM)
    # the outline is extruded along Y around (x, z): lay it flat (z -> y)
    bm_transform(em, Matrix.Translation((0, 0, z_floor + t / 2 - 0.004)) @
                 Matrix.Rotation(-math.pi / 2, 4, 'X'))
    parts = [em]
    for (x, y) in tips:
        parts.append(uv_sphere_bm(0.013, (x, y, z_floor + height - 0.004), segs=8, rings=4))
    for x in (-0.085, 0.0, 0.085):          # three jewels on the band
        parts.append(uv_sphere_bm(0.011, (x, -0.066, z_floor + height - 0.003), segs=8, rings=4))
    return parts


def checkers_king():
    """Two stacked men as a single lathe (no hidden faces between them): the
    lower disc's top rounding runs into a seam groove and the upper, 0.97x
    wide disc; gold crown emblem inlaid in the recessed centre."""
    P = Profile(0.0, 0.0, tag="low")
    disc_profile(P, 0.0, CK_R, CK_H, top="seam")
    info = disc_profile(P, CK_H, CK_R * 0.97, CK_H, bottom="seam", king_top=True)
    body = lathe_disc(P)
    ring = gold_inlay_ring(*info["ring"], 2 * CK_H)
    return body, [ring] + crown_emblem(info["centre_z"])


# ---------------------------------------------------------------------------
# Model registry
# ---------------------------------------------------------------------------

CHESS_MODELS = {
    "pawn": chess_pawn, "knight": chess_knight, "bishop": chess_bishop,
    "rook": chess_rook, "queen": chess_queen, "king": chess_king,
    "square_tile": square_tile, "board_frame": lambda: board_frame("ogee"),
    "board_base": board_base,
}
CHECKERS_MODELS = {
    "man": checkers_man, "king": checkers_king,
    "square_tile": square_tile, "board_frame": lambda: board_frame("bullnose"),
    "board_base": board_base,
}


# ---------------------------------------------------------------------------
# Preview rendering (EEVEE contact sheets of the written OBJ files)
# ---------------------------------------------------------------------------

def _principled(name, color, rough, metal=0.0, coat=0.0, sss=0.0):
    m = bpy.data.materials.new(name)
    if m.node_tree is None:          # Blender < 5 needs this; 5.x always has nodes
        m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = coat
    if sss and "Subsurface Weight" in bsdf.inputs:
        bsdf.inputs["Subsurface Weight"].default_value = sss
        bsdf.inputs["Subsurface Radius"].default_value = (0.02, 0.015, 0.01)
    return m


def _clear_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.lights, bpy.data.cameras):
        for d in list(coll):
            if d.users == 0:
                coll.remove(d)


def _look_at(obj, target):
    d = Vector(target) - obj.location
    obj.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()


def _import_obj(path, loc, mats, rot_z=0.0):
    before = set(bpy.data.objects)
    bpy.ops.wm.obj_import(filepath=path, forward_axis='NEGATIVE_Z', up_axis='Y')
    obj = [o for o in bpy.data.objects if o not in before][0]
    # bake the importer's axis conversion into the mesh, then place it
    obj.data.transform(obj.matrix_basis)
    obj.matrix_basis = Matrix.Identity(4)
    obj.location = loc
    obj.rotation_euler = (0, 0, rot_z)
    for slot in obj.material_slots:
        key = "trim" if slot.material and slot.material.name.startswith("trim") else "body"
        slot.material = mats[key]
    return obj


def _setup_render(res=(1600, 900), samples=64):
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = 'PNG'
    try:
        sc.eevee.taa_render_samples = samples
        sc.eevee.use_shadows = True
    except AttributeError:
        pass
    try:
        sc.view_settings.view_transform = 'AgX'
        sc.view_settings.look = 'AgX - Medium High Contrast'
    except TypeError:
        pass
    world = bpy.data.worlds.new("preview_world")
    if world.node_tree is None:
        world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.045, 0.047, 0.055, 1.0)
    bg.inputs["Strength"].default_value = 1.0
    sc.world = world


def _add_light(kind, loc, target, energy, size=1.0, color=(1, 1, 1)):
    ld = bpy.data.lights.new("L", kind)
    ld.energy = energy
    ld.color = color
    if kind == 'AREA':
        ld.size = size
    o = bpy.data.objects.new("L", ld)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    _look_at(o, target)
    return o


def _add_floor(mat, size=40.0, z=0.0):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, z))
    fl = bpy.context.active_object
    fl.data.materials.append(mat)
    return fl


def _camera(loc, target, lens=85.0, ortho=None):
    cd = bpy.data.cameras.new("C")
    cd.lens = lens
    if ortho:
        cd.type = 'ORTHO'
        cd.ortho_scale = ortho
    o = bpy.data.objects.new("C", cd)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    _look_at(o, target)
    bpy.context.scene.camera = o
    return o


def _render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("  preview:", path)


def _studio(center=(0, 0, 0.4), scale=1.0):
    cx, cy, cz = center
    _add_light('AREA', (cx - 3 * scale, cy - 4 * scale, cz + 4 * scale), center, 420 * scale ** 2, 3.0 * scale,
               (1.0, 0.96, 0.9))
    _add_light('AREA', (cx + 4 * scale, cy - 2.5 * scale, cz + 1.5 * scale), center, 110 * scale ** 2, 3.0 * scale,
               (0.85, 0.92, 1.0))
    _add_light('AREA', (cx + 1 * scale, cy + 4 * scale, cz + 3 * scale), center, 320 * scale ** 2, 2.0 * scale)


def preview_chess(model_dir, out_dir):
    ivory = _principled("ivory", (0.74, 0.64, 0.48, 1), 0.34, coat=0.3, sss=0.05)
    ebony = _principled("ebony", (0.035, 0.028, 0.025, 1), 0.30, coat=0.4)
    gold = _principled("gold", (0.92, 0.70, 0.36, 1), 0.22, metal=1.0)
    floor = _principled("floor", (0.10, 0.10, 0.11, 1), 0.6)
    light = {"body": ivory, "trim": gold}
    dark = {"body": ebony, "trim": gold}
    order = ["pawn", "rook", "knight", "bishop", "queen", "king"]

    # 1) contact sheet: all six, side view, light set
    _clear_scene()
    _setup_render()
    _add_floor(floor)
    for i, name in enumerate(order):
        # rotate the knight so its profile faces the camera
        rz = -math.pi / 2 if name == "knight" else 0.0
        _import_obj(os.path.join(model_dir, name + ".obj"), ((i - 2.5) * 0.72, 0, 0), light, rz)
    _studio((0, 0, 0.5), 1.4)
    _camera((0, -9.5, 2.2), (0, 0, 0.52), lens=62)
    _render(os.path.join(out_dir, "chess_contact_sheet.png"))

    # 2) same, dark set from a 45 deg elevated game-like camera
    _clear_scene()
    _setup_render()
    _add_floor(floor)
    for i, name in enumerate(order):
        rz = -math.pi / 2 if name == "knight" else 0.0
        _import_obj(os.path.join(model_dir, name + ".obj"), ((i - 2.5) * 0.72, 0, 0), dark, rz)
    _studio((0, 0, 0.5), 1.4)
    _camera((0, -6.8, 6.8), (0, 0, 0.35), lens=62)
    _render(os.path.join(out_dir, "chess_contact_sheet_45deg_dark.png"))

    # 3) close-up of the heads of the tall pieces (slit, coronet, cross)
    _clear_scene()
    _setup_render()
    _add_floor(floor)
    for i, name in enumerate(["rook", "bishop", "queen", "king"]):
        _import_obj(os.path.join(model_dir, name + ".obj"), ((i - 1.5) * 0.62, 0, 0), light, 0.0)
    _studio((0, 0, 0.6), 1.2)
    _camera((0.9, -4.2, 2.1), (0, 0, 0.78), lens=85)
    _render(os.path.join(out_dir, "chess_heads_closeup.png"))

    # 4) knight close-ups
    # (after import the snout points to +Y in Blender)
    for tag, cam, mats, rz in (("front34", (1.75, 2.1, 1.35), light, 0.0),
                               ("back34", (-1.8, -1.95, 1.45), light, 0.0),
                               ("side", (2.9, 0.0, 0.62), light, 0.0),
                               ("front", (0.0, 2.9, 0.85), light, 0.0),
                               ("front34_dark", (1.75, 2.1, 1.35), dark, 0.0)):
        _clear_scene()
        _setup_render((1600, 900))
        _add_floor(floor)
        # the OBJ snout is -Z (Godot) == +Y in Blender after import
        _import_obj(os.path.join(model_dir, "knight.obj"), (0, 0, 0), mats, rz)
        _studio((0, 0, 0.45), 0.6)
        _camera(cam, (0, 0.02, 0.46), lens=70)
        _render(os.path.join(out_dir, "knight_%s.png" % tag))

    # 5) board with pieces
    _clear_scene()
    _setup_render()
    board_preview(model_dir, ivory, ebony, gold)
    for f, name in enumerate(["rook", "knight", "bishop", "queen", "king", "bishop", "knight", "rook"]):
        x = f - 3.5
        _import_obj(os.path.join(model_dir, name + ".obj"), (x, -3.5, 0.07), light, 0.0)
        _import_obj(os.path.join(model_dir, "pawn.obj"), (x, -2.5, 0.07), light, 0.0)
        _import_obj(os.path.join(model_dir, name + ".obj"), (x, 3.5, 0.07), dark, math.pi)
        _import_obj(os.path.join(model_dir, "pawn.obj"), (x, 2.5, 0.07), dark, math.pi)
    _studio((0, 0, 0.0), 4.0)
    _camera((0, -11.5, 9.0), (0, -0.4, 0.0), lens=40)
    _render(os.path.join(out_dir, "chess_board.png"))
    _camera((5.9, -6.3, 1.25), (3.9, -3.9, 0.0), lens=50)
    _render(os.path.join(out_dir, "chess_board_corner.png"))


def board_preview(model_dir, light_mat, dark_mat, gold):
    wood = _principled("wood", (0.20, 0.09, 0.04, 1), 0.40, coat=0.2)
    sq_l = _principled("sq_l", (0.72, 0.60, 0.42, 1), 0.45, coat=0.1)
    sq_d = _principled("sq_d", (0.16, 0.08, 0.05, 1), 0.45, coat=0.1)
    floor = _principled("floor", (0.08, 0.08, 0.09, 1), 0.7)
    _add_floor(floor, 80, -0.12)
    _import_obj(os.path.join(model_dir, "board_frame.obj"), (0, 0, 0), {"body": wood, "trim": gold})
    _import_obj(os.path.join(model_dir, "board_base.obj"), (0, 0, 0), {"body": wood, "trim": gold})
    for i in range(8):
        for j in range(8):
            m = sq_d if (i + j) % 2 == 0 else sq_l
            _import_obj(os.path.join(model_dir, "square_tile.obj"), (i - 3.5, j - 3.5, 0), {"body": m, "trim": m})


def preview_checkers(model_dir, out_dir):
    cream = _principled("cream", (0.74, 0.64, 0.48, 1), 0.38, coat=0.1)
    crimson = _principled("crimson", (0.30, 0.025, 0.02, 1), 0.36, coat=0.1)
    ebony = _principled("ebony", (0.035, 0.028, 0.025, 1), 0.36, coat=0.15)
    gold = _principled("gold", (0.92, 0.70, 0.36, 1), 0.22, metal=1.0)
    floor = _principled("floor", (0.10, 0.10, 0.11, 1), 0.6)
    for tag, cam, tgt in (("", (0, -4.6, 3.4), (0, 0, 0.08)),
                          ("_side", (0, -5.5, 0.6), (0, 0, 0.12))):
        _clear_scene()
        _setup_render()
        _add_floor(floor)
        sets = [("man", cream), ("king", cream), ("man", crimson), ("king", ebony)]
        for i, (name, m) in enumerate(sets):
            _import_obj(os.path.join(model_dir, name + ".obj"), ((i - 1.5) * 0.95, 0, 0),
                        {"body": m, "trim": gold})
        _studio((0, 0, 0.1), 1.0)
        _camera(cam, tgt, lens=70)
        _render(os.path.join(out_dir, "checkers_contact_sheet%s.png" % tag))
    # close-up of the king top
    _clear_scene()
    _setup_render()
    _add_floor(floor)
    _import_obj(os.path.join(model_dir, "king.obj"), (0, 0, 0), {"body": crimson, "trim": gold})
    _studio((0, 0, 0.1), 0.6)
    _camera((0.0, -1.1, 1.4), (0, 0, 0.2), lens=70)
    _render(os.path.join(out_dir, "checkers_king_closeup.png"))
    # board
    _clear_scene()
    _setup_render()
    board_preview(model_dir, cream, crimson, gold)
    for i in range(8):
        for j in range(3):
            if (i + j) % 2 == 0:            # dark squares (see board_preview)
                _import_obj(os.path.join(model_dir, "man.obj"), (i - 3.5, j - 3.5, 0.07),
                            {"body": cream, "trim": gold})
            jj = 7 - j
            if (i + jj) % 2 == 0:
                _import_obj(os.path.join(model_dir, "king.obj" if jj == 7 and i == 0 else "man.obj"),
                            (i - 3.5, jj - 3.5, 0.07), {"body": crimson, "trim": gold})
    _studio((0, 0, 0.0), 4.0)
    _camera((0, -11.5, 9.0), (0, -0.4, 0.0), lens=40)
    _render(os.path.join(out_dir, "checkers_board.png"))
    _camera((5.9, -6.3, 1.25), (3.9, -3.9, 0.0), lens=50)
    _render(os.path.join(out_dir, "checkers_board_corner.png"))


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def detect_repo():
    here = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
    root = os.path.abspath(os.path.join(here, "..", ".."))
    game = "chess"
    try:
        with open(os.path.join(root, "project.godot")) as fh:
            if "Checkers" in fh.read():
                game = "checkers"
    except OSError:
        pass
    return root, game


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    root, game = detect_repo()
    opts = {"game": game, "out": os.path.join(root, "assets", "models"),
            "only": None, "preview": None, "build": True}
    it = iter(argv)
    for a in it:
        if a == "--game":
            opts["game"] = next(it)
        elif a == "--out":
            opts["out"] = os.path.abspath(next(it))
        elif a == "--only":
            opts["only"] = set(next(it).split(","))
        elif a == "--preview":
            opts["preview"] = os.path.abspath(next(it))
        elif a == "--no-build":
            opts["build"] = False
        else:
            raise SystemExit("unknown option: %s" % a)
    return opts


def check_model(name, st, game):
    """Validation of a written OBJ; returns a list of problems (empty = ok)."""
    problems = []
    groups = st["groups"]
    if groups not in (["body", "trim"], ["body"]):
        problems.append("groups %s" % groups)
    if st["non_manifold"]:
        problems.append("%d non-manifold edges" % st["non_manifold"])
    if st["volume"][0] <= 0 or st["volume"][1] < 0:
        problems.append("inverted normals (volume %s)" % st["volume"])
    if st["flipped"]:
        problems.append("%d flipped faces" % st["flipped"])
    if not st["normals"] or not st["uvs"]:
        problems.append("missing normals/uvs")
    if st["min"][1] < -1e-4 and not name.startswith("board_"):
        problems.append("geometry below y=0")
    if name == "knight" and game == "chess":
        V = st["V"]
        head = V[V[:, 1] > 0.30]
        if not -head[:, 2].min() > head[:, 2].max():
            problems.append("snout does not point to -Z")
    return problems


def print_summary(rows, game):
    print()
    print("%-16s %6s %6s  %-10s %-24s %-24s %s" % (
        "file", "tris", "(trim)", "groups", "min x,y,z", "max x,y,z", "checks"))
    for name, st in rows:
        mn, mx = st["min"], st["max"]
        problems = check_model(name, st, game)
        print("%-16s %6d %6d  %-10s %-24s %-24s %s" % (
            name + ".obj", st["tris"], st["group_tris"].get("trim", 0), ",".join(st["groups"]),
            "%.3f,%.3f,%.3f" % tuple(mn), "%.3f,%.3f,%.3f" % tuple(mx),
            "ok" if not problems else "FAIL: " + "; ".join(problems)))
        if name == "knight" and game == "chess":
            V = st["V"]
            head = V[V[:, 1] > 0.30]
            print("%-16s head z-range %.3f .. %.3f (snout toward -Z)" % ("", head[:, 2].min(),
                                                                          head[:, 2].max()))
    print("checks: usemtl order body[,trim]; 0 non-manifold edges; positive signed volume "
          "(outward normals); no flipped faces; normals+UVs present; knight snout toward -Z")


def main():
    opts = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    models = CHESS_MODELS if opts["game"] == "chess" else CHECKERS_MODELS
    os.makedirs(opts["out"], exist_ok=True)
    rows = []
    if opts["build"]:
        for name, fn in models.items():
            if opts["only"] and name not in opts["only"]:
                continue
            t0 = time.time()
            print("building %s ..." % name)
            body, trims = fn()
            bm = assemble(body, trims)
            st = export_model(bm, os.path.join(opts["out"], name + ".obj"))
            st["time"] = time.time() - t0
            rows.append((name, st))
            body.free()
            for t in trims:
                t.free()
            bm.free()
        print_summary(rows, opts["game"])
    if opts["preview"]:
        os.makedirs(opts["preview"], exist_ok=True)
        if opts["game"] == "chess":
            preview_chess(opts["out"], opts["preview"])
        else:
            preview_checkers(opts["out"], opts["preview"])


if __name__ == "__main__":
    main()
