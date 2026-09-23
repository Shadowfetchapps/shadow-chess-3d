class_name PieceMeshBuilder
extends RefCounted

## Builds piece visuals. Authored meshes come from res://assets/models/*.obj
## (tools/assetgen/build_models.py, Blender). Each OBJ has a `body` surface and
## an optional `trim` surface; materials are assigned from MaterialLibrary so a
## theme change restyles every piece. If a model is missing, a primitive
## stand-in is assembled so the game still runs.

const MODEL_DIR := "res://assets/models/"
const NAMES := {
	ChessTypes.PAWN: "pawn", ChessTypes.KNIGHT: "knight", ChessTypes.BISHOP: "bishop",
	ChessTypes.ROOK: "rook", ChessTypes.QUEEN: "queen", ChessTypes.KING: "king",
}
const FALLBACK_HEIGHT := {
	ChessTypes.PAWN: 0.64, ChessTypes.KNIGHT: 0.86, ChessTypes.BISHOP: 0.94,
	ChessTypes.ROOK: 0.74, ChessTypes.QUEEN: 1.06, ChessTypes.KING: 1.2,
}

static var _meshes: Dictionary = {}
static var _prototypes: Dictionary = {}


static func has_model(type: int) -> bool:
	return mesh_for(type) != null


## Authored mesh for a piece type, or null when the OBJ is not present.
static func mesh_for(type: int) -> Mesh:
	if _meshes.has(type):
		return _meshes[type]
	var path: String = MODEL_DIR + str(NAMES.get(type, "pawn")) + ".obj"
	var mesh: Mesh = null
	if ResourceLoader.exists(path):
		mesh = load(path) as Mesh
	_meshes[type] = mesh
	return mesh


static func height_of(type: int) -> float:
	var m := mesh_for(type)
	if m:
		return m.get_aabb().end.y
	return float(FALLBACK_HEIGHT.get(type, 0.8))


static func radius_of(type: int) -> float:
	var m := mesh_for(type)
	if m:
		var aabb := m.get_aabb()
		return maxf(aabb.size.x, aabb.size.z) * 0.5
	return 0.24


## Surface index -> "body" / "trim" using surface names, material names, or order.
static func surface_role(mesh: Mesh, idx: int) -> String:
	var name := ""
	if mesh is ArrayMesh:
		name = (mesh as ArrayMesh).surface_get_name(idx).to_lower()
	if name.is_empty():
		var mat := mesh.surface_get_material(idx)
		if mat:
			name = mat.resource_name.to_lower()
	if "trim" in name or "gold" in name:
		return "trim"
	if "body" in name:
		return "body"
	return "body" if idx == 0 else "trim"


static func build(type: int, color: int) -> Node3D:
	MaterialLibrary.ensure()
	var visual: Node3D
	var mesh := mesh_for(type)
	if mesh:
		visual = Node3D.new()
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = mesh
		apply_materials(mi, color)
		visual.add_child(mi)
	else:
		var key := "%d_%d" % [type, color]
		if not _prototypes.has(key):
			_prototypes[key] = _construct(type, color)
		visual = (_prototypes[key] as Node3D).duplicate()
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = maxf(radius_of(type) * 0.85, 0.2)
	cyl.height = height_of(type)
	col.shape = cyl
	col.position.y = cyl.height * 0.5
	body.add_child(col)
	visual.add_child(body)
	return visual


static func apply_materials(mi: MeshInstance3D, color: int) -> void:
	var mesh := mi.mesh
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		var role := surface_role(mesh, i)
		mi.set_surface_override_material(i, MaterialLibrary.piece_trim(color) if role == "trim" else MaterialLibrary.piece_body(color))


# --- Primitive stand-ins --------------------------------------------------------

static func _construct(type: int, color: int) -> Node3D:
	var root := Node3D.new()
	var mat := MaterialLibrary.piece_body(color)
	var gold := MaterialLibrary.piece_trim(color)
	match type:
		ChessTypes.PAWN:
			_base(root, mat, gold, 0.90)
			_add_cyl(root, mat, 0.068, 0.108, 0.22, 0.23)
			_add_cyl(root, gold, 0.118, 0.118, 0.018, 0.348, 20)
			_add_sphere(root, mat, 0.122, 0.49)
		ChessTypes.KNIGHT:
			_base(root, mat, gold, 1.0)
			_add_cyl(root, mat, 0.095, 0.138, 0.15, 0.20)
			_add_box(root, mat, Vector3(0.16, 0.30, 0.20), Vector3(0.00, 0.40, -0.02), Vector3(16, 0, 0))
			_add_box(root, mat, Vector3(0.14, 0.18, 0.26), Vector3(0.0, 0.58, -0.10), Vector3(28, 0, 0))
			_add_box(root, mat, Vector3(0.05, 0.12, 0.05), Vector3(-0.04, 0.72, -0.08), Vector3(8, 0, -12))
			_add_box(root, mat, Vector3(0.05, 0.12, 0.05), Vector3(0.04, 0.72, -0.08), Vector3(8, 0, 12))
		ChessTypes.BISHOP:
			_base(root, mat, gold, 0.95)
			_add_cyl(root, mat, 0.068, 0.112, 0.30, 0.27)
			_add_cyl(root, gold, 0.128, 0.128, 0.016, 0.43, 20)
			_add_sphere(root, mat, 0.128, 0.58)
			_add_cyl(root, mat, 0.008, 0.108, 0.24, 0.80)
			_add_sphere(root, gold, 0.032, 0.94)
		ChessTypes.ROOK:
			_base(root, mat, gold, 1.06)
			_add_cyl(root, mat, 0.132, 0.158, 0.36, 0.30, 24)
			_add_cyl(root, mat, 0.178, 0.178, 0.075, 0.52, 24)
			for i in 4:
				var a := i * TAU / 4.0
				_add_box(root, mat, Vector3(0.072, 0.11, 0.072), Vector3(cos(a) * 0.132, 0.62, sin(a) * 0.132))
		ChessTypes.QUEEN:
			_base(root, mat, gold, 1.06)
			_add_cyl(root, mat, 0.078, 0.132, 0.40, 0.32)
			_add_cyl(root, gold, 0.148, 0.148, 0.018, 0.53, 22)
			_add_sphere(root, mat, 0.138, 0.67)
			for i in 8:
				var a := i * TAU / 8.0
				_add_sphere(root, gold, 0.028, 0.86, cos(a) * 0.112, sin(a) * 0.112)
			_add_sphere(root, gold, 0.038, 0.96)
		ChessTypes.KING:
			_base(root, mat, gold, 1.10)
			_add_cyl(root, mat, 0.082, 0.136, 0.44, 0.34)
			_add_cyl(root, gold, 0.158, 0.158, 0.018, 0.56, 22)
			_add_sphere(root, mat, 0.142, 0.72)
			_add_box(root, gold, Vector3(0.048, 0.22, 0.048), Vector3(0, 1.00, 0))
			_add_box(root, gold, Vector3(0.15, 0.048, 0.048), Vector3(0, 1.00, 0))
	return root


static func _base(parent: Node3D, mat: Material, gold: Material, s: float) -> void:
	_add_cyl(parent, mat, 0.205 * s, 0.228 * s, 0.065, 0.032, 28)
	_add_cyl(parent, gold, 0.198 * s, 0.198 * s, 0.012, 0.068, 24)
	_add_cyl(parent, mat, 0.162 * s, 0.188 * s, 0.048, 0.092, 26)


static func _add_cyl(parent: Node3D, mat: Material, r_top: float, r_bot: float, h: float, y: float, radial := 28) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bot
	mesh.height = h
	mesh.radial_segments = radial
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = mat
	mi.position.y = y
	parent.add_child(mi)


static func _add_sphere(parent: Node3D, mat: Material, r: float, y: float, x := 0.0, z := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 22
	mesh.rings = 12
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(x, y, z)
	parent.add_child(mi)


static func _add_box(parent: Node3D, mat: Material, size: Vector3, pos: Vector3, deg := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = deg
	parent.add_child(mi)
