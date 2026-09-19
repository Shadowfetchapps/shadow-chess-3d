class_name PieceMeshBuilder
extends RefCounted


static func ivory() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.93, 0.89, 0.80)
	m.metallic = 0.18
	m.roughness = 0.36
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.rim_enabled = true
	m.rim = 0.18
	m.rim_tint = 0.4
	m.clearcoat_enabled = true
	m.clearcoat = 0.15
	m.clearcoat_roughness = 0.35
	return m


static func ebony() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.10, 0.11, 0.135)
	m.metallic = 0.28
	m.roughness = 0.42
	m.rim_enabled = true
	m.rim = 0.22
	m.rim_tint = 0.15
	m.clearcoat_enabled = true
	m.clearcoat = 0.1
	return m


static func material_for(color: int) -> StandardMaterial3D:
	return ivory() if color == ChessTypes.WHITE else ebony()


static func build(type: int, color: int) -> Node3D:
	var root := Node3D.new()
	var mat := material_for(color)
	match type:
		ChessTypes.PAWN:
			_pawn(root, mat)
		ChessTypes.KNIGHT:
			_knight(root, mat)
		ChessTypes.BISHOP:
			_bishop(root, mat)
		ChessTypes.ROOK:
			_rook(root, mat)
		ChessTypes.QUEEN:
			_queen(root, mat)
		ChessTypes.KING:
			_king(root, mat)
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
	root.add_child(body)
	return root


static func _add_cyl(parent: Node3D, mat: Material, r_top: float, r_bot: float, h: float, y: float, radial := 18) -> void:
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
	mesh.radial_segments = 16
	mesh.rings = 10
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


static func _base(parent: Node3D, mat: Material, scale := 1.0) -> void:
	_add_cyl(parent, mat, 0.20 * scale, 0.22 * scale, 0.07, 0.035)
	_add_cyl(parent, mat, 0.16 * scale, 0.18 * scale, 0.05, 0.085)


static func _pawn(parent: Node3D, mat: Material) -> void:
	_base(parent, mat, 0.92)
	_add_cyl(parent, mat, 0.07, 0.11, 0.22, 0.22)
	_add_cyl(parent, mat, 0.12, 0.12, 0.04, 0.34)
	_add_sphere(parent, mat, 0.125, 0.48)


static func _knight(parent: Node3D, mat: Material) -> void:
	_base(parent, mat, 1.0)
	_add_cyl(parent, mat, 0.10, 0.14, 0.16, 0.18)
	_add_box(parent, mat, Vector3(0.18, 0.28, 0.22), Vector3(0.02, 0.38, 0.02), Vector3(12, 0, -8))
	_add_box(parent, mat, Vector3(0.16, 0.16, 0.26), Vector3(0.06, 0.54, 0.08), Vector3(18, 12, 0))
	_add_box(parent, mat, Vector3(0.10, 0.08, 0.16), Vector3(0.12, 0.50, 0.20), Vector3(8, 0, 0))
	_add_box(parent, mat, Vector3(0.05, 0.10, 0.06), Vector3(0.02, 0.66, 0.12), Vector3(10, 0, -15))
	_add_box(parent, mat, Vector3(0.05, 0.10, 0.06), Vector3(0.08, 0.66, 0.04), Vector3(10, 0, 12))
	_add_box(parent, mat, Vector3(0.04, 0.18, 0.10), Vector3(-0.06, 0.50, -0.02), Vector3(20, 0, 0))


static func _bishop(parent: Node3D, mat: Material) -> void:
	_base(parent, mat, 0.95)
	_add_cyl(parent, mat, 0.07, 0.11, 0.28, 0.26)
	_add_cyl(parent, mat, 0.13, 0.13, 0.04, 0.42)
	_add_sphere(parent, mat, 0.13, 0.58)
	var mitre := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.01
	cone.bottom_radius = 0.11
	cone.height = 0.22
	mitre.mesh = cone
	mitre.material_override = mat
	mitre.position.y = 0.78
	parent.add_child(mitre)
	_add_sphere(parent, mat, 0.035, 0.92)


static func _rook(parent: Node3D, mat: Material) -> void:
	_base(parent, mat, 1.05)
	_add_cyl(parent, mat, 0.14, 0.16, 0.36, 0.28, 12)
	_add_cyl(parent, mat, 0.18, 0.18, 0.08, 0.50, 12)
	for i in 4:
		var a := i * TAU / 4.0
		_add_box(parent, mat, Vector3(0.07, 0.10, 0.07), Vector3(cos(a) * 0.13, 0.58, sin(a) * 0.13))


static func _queen(parent: Node3D, mat: Material) -> void:
	_base(parent, mat, 1.05)
	_add_cyl(parent, mat, 0.08, 0.13, 0.38, 0.30)
	_add_cyl(parent, mat, 0.15, 0.15, 0.05, 0.50)
	_add_sphere(parent, mat, 0.14, 0.64)
	for i in 6:
		var a := i * TAU / 6.0
		_add_sphere(parent, mat, 0.035, 0.80, cos(a) * 0.11, sin(a) * 0.11)
	_add_sphere(parent, mat, 0.04, 0.90)


static func _king(parent: Node3D, mat: Material) -> void:
	_base(parent, mat, 1.08)
	_add_cyl(parent, mat, 0.085, 0.135, 0.42, 0.32)
	_add_cyl(parent, mat, 0.16, 0.16, 0.05, 0.54)
	_add_sphere(parent, mat, 0.145, 0.70)
	_add_box(parent, mat, Vector3(0.05, 0.20, 0.05), Vector3(0, 0.96, 0))
	_add_box(parent, mat, Vector3(0.14, 0.05, 0.05), Vector3(0, 0.96, 0))
