class_name PieceMeshBuilder
extends RefCounted

static var _prototypes: Dictionary = {}


static func ivory() -> StandardMaterial3D:
	MaterialLibrary.ensure()
	return MaterialLibrary.ivory_mat


static func ebony() -> StandardMaterial3D:
	MaterialLibrary.ensure()
	return MaterialLibrary.ebony_mat


static func material_for(color: int) -> StandardMaterial3D:
	return MaterialLibrary.piece_body(color)


static func build(type: int, color: int) -> Node3D:
	MaterialLibrary.ensure()
	var key := "%d_%d" % [type, color]
	if not _prototypes.has(key):
		_prototypes[key] = _construct(type, color)
	var visual: Node3D = (_prototypes[key] as Node3D).duplicate()
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.22
	cyl.height = 0.85
	col.shape = cyl
	col.position.y = 0.42
	body.add_child(col)
	visual.add_child(body)
	return visual


static func _construct(type: int, color: int) -> Node3D:
	var root := Node3D.new()
	var mat := material_for(color)
	var gold: StandardMaterial3D = MaterialLibrary.gold_trim_mat
	match type:
		ChessTypes.PAWN:
			_pawn(root, mat, gold)
		ChessTypes.KNIGHT:
			_knight(root, mat, gold)
		ChessTypes.BISHOP:
			_bishop(root, mat, gold)
		ChessTypes.ROOK:
			_rook(root, mat, gold)
		ChessTypes.QUEEN:
			_queen(root, mat, gold)
		ChessTypes.KING:
			_king(root, mat, gold)
	return root


static func _add_cyl(parent: Node3D, mat: Material, r_top: float, r_bot: float, h: float, y: float, radial := 28) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bot
	mesh.height = h
	mesh.radial_segments = radial
	mesh.rings = 2
	mi.mesh = mesh
	mi.material_override = mat
	mi.position.y = y
	parent.add_child(mi)
	return mi


static func _add_sphere(parent: Node3D, mat: Material, r: float, y: float, x := 0.0, z := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 22
	mesh.rings = 14
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(x, y, z)
	parent.add_child(mi)
	return mi


static func _add_box(parent: Node3D, mat: Material, size: Vector3, pos: Vector3, deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = deg
	parent.add_child(mi)
	return mi


static func _collar(parent: Node3D, gold: Material, y: float, r: float) -> void:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = r * 0.82
	torus.outer_radius = r
	torus.rings = 18
	torus.ring_segments = 10
	mi.mesh = torus
	mi.material_override = gold
	mi.position.y = y
	mi.scale = Vector3(1, 0.28, 1)
	parent.add_child(mi)


static func _base(parent: Node3D, mat: Material, gold: Material, scale := 1.0) -> void:
	_add_cyl(parent, mat, 0.205 * scale, 0.228 * scale, 0.065, 0.032, 28)
	_add_cyl(parent, gold, 0.198 * scale, 0.198 * scale, 0.012, 0.068, 24)
	_add_cyl(parent, mat, 0.162 * scale, 0.188 * scale, 0.048, 0.092, 26)
	_collar(parent, gold, 0.118, 0.168 * scale)


static func _pawn(parent: Node3D, mat: Material, gold: Material) -> void:
	_base(parent, mat, gold, 0.90)
	_add_cyl(parent, mat, 0.068, 0.108, 0.22, 0.23)
	_add_cyl(parent, gold, 0.118, 0.118, 0.018, 0.348, 20)
	_add_sphere(parent, mat, 0.122, 0.49)
	_add_sphere(parent, gold, 0.022, 0.61)


static func _knight(parent: Node3D, mat: Material, gold: Material) -> void:
	_base(parent, mat, gold, 1.0)
	_add_cyl(parent, mat, 0.095, 0.138, 0.15, 0.20)
	_collar(parent, gold, 0.28, 0.122)
	_add_box(parent, mat, Vector3(0.16, 0.30, 0.20), Vector3(0.00, 0.40, -0.02), Vector3(16, 0, -6))
	_add_box(parent, mat, Vector3(0.14, 0.18, 0.24), Vector3(0.02, 0.58, -0.10), Vector3(28, 8, 0))
	_add_box(parent, mat, Vector3(0.10, 0.10, 0.18), Vector3(0.06, 0.56, -0.24), Vector3(12, 0, 0))
	_add_box(parent, mat, Vector3(0.055, 0.12, 0.055), Vector3(-0.02, 0.72, -0.12), Vector3(8, 0, -12))
	_add_box(parent, mat, Vector3(0.055, 0.12, 0.055), Vector3(0.06, 0.72, -0.04), Vector3(8, 0, 10))
	_add_box(parent, mat, Vector3(0.04, 0.16, 0.09), Vector3(-0.07, 0.50, 0.02), Vector3(18, 0, 0))
	_add_sphere(parent, gold, 0.016, 0.60, 0.08, -0.22)
	_add_sphere(parent, gold, 0.016, 0.60, -0.02, -0.22)


static func _bishop(parent: Node3D, mat: Material, gold: Material) -> void:
	_base(parent, mat, gold, 0.95)
	_add_cyl(parent, mat, 0.068, 0.112, 0.30, 0.27)
	_add_cyl(parent, gold, 0.128, 0.128, 0.016, 0.43, 20)
	_add_sphere(parent, mat, 0.128, 0.58)
	var mitre := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.008
	cone.bottom_radius = 0.108
	cone.height = 0.24
	cone.radial_segments = 24
	mitre.mesh = cone
	mitre.material_override = mat
	mitre.position.y = 0.80
	parent.add_child(mitre)
	_add_box(parent, gold, Vector3(0.012, 0.16, 0.04), Vector3(0.04, 0.62, 0.0), Vector3(0, 0, 18))
	_add_sphere(parent, gold, 0.032, 0.94)


static func _rook(parent: Node3D, mat: Material, gold: Material) -> void:
	_base(parent, mat, gold, 1.06)
	_add_cyl(parent, mat, 0.132, 0.158, 0.36, 0.30, 16)
	_collar(parent, gold, 0.48, 0.16)
	_add_cyl(parent, mat, 0.178, 0.178, 0.075, 0.52, 16)
	_add_cyl(parent, gold, 0.182, 0.182, 0.014, 0.565, 16)
	for i in 4:
		var a := i * TAU / 4.0
		_add_box(parent, mat, Vector3(0.072, 0.11, 0.072), Vector3(cos(a) * 0.132, 0.62, sin(a) * 0.132))
		_add_box(parent, gold, Vector3(0.074, 0.016, 0.074), Vector3(cos(a) * 0.132, 0.678, sin(a) * 0.132))


static func _queen(parent: Node3D, mat: Material, gold: Material) -> void:
	_base(parent, mat, gold, 1.06)
	_add_cyl(parent, mat, 0.078, 0.132, 0.40, 0.32)
	_add_cyl(parent, gold, 0.148, 0.148, 0.018, 0.53, 22)
	_add_sphere(parent, mat, 0.138, 0.67)
	_collar(parent, gold, 0.80, 0.118)
	for i in 8:
		var a := i * TAU / 8.0
		_add_sphere(parent, gold, 0.028, 0.86, cos(a) * 0.112, sin(a) * 0.112)
	_add_sphere(parent, gold, 0.038, 0.96)


static func _king(parent: Node3D, mat: Material, gold: Material) -> void:
	_base(parent, mat, gold, 1.10)
	_add_cyl(parent, mat, 0.082, 0.136, 0.44, 0.34)
	_add_cyl(parent, gold, 0.158, 0.158, 0.018, 0.56, 22)
	_add_sphere(parent, mat, 0.142, 0.72)
	_collar(parent, gold, 0.86, 0.122)
	_add_box(parent, gold, Vector3(0.048, 0.22, 0.048), Vector3(0, 1.00, 0))
	_add_box(parent, gold, Vector3(0.15, 0.048, 0.048), Vector3(0, 1.00, 0))
	_add_cyl(parent, gold, 0.018, 0.018, 0.04, 1.12, 10)
