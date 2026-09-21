class_name SalonBuilder
extends RefCounted


static func build(parent: Node3D) -> Node3D:
	MaterialLibrary.ensure()
	var root := Node3D.new()
	root.name = "Salon"
	parent.add_child(root)
	_floor(root)
	_walls(root)
	_columns(root)
	_drapes(root)
	_pedestal(root)
	_lamps(root)
	_branding(root)
	var wall_fill := OmniLight3D.new()
	wall_fill.position = Vector3(0, 3.4, -10.5)
	wall_fill.light_color = Color(1.0, 0.82, 0.52)
	wall_fill.light_energy = 1.6
	wall_fill.omni_range = 10.0
	root.add_child(wall_fill)
	return root


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, segs := 24) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bot
	mesh.height = h
	mesh.radial_segments = segs
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _floor(parent: Node3D) -> void:
	_box(parent, Vector3(32, 0.16, 32), Vector3(0, -1.42, 0), MaterialLibrary.wood_floor)
	var rug := _box(parent, Vector3(14.5, 0.02, 14.5), Vector3(0, -1.33, 0), MaterialLibrary.felt_mat)
	rug.material_override = MaterialLibrary.felt_mat


static func _walls(parent: Node3D) -> void:
	_box(parent, Vector3(32, 8.2, 0.22), Vector3(0, 2.6, -15.4), MaterialLibrary.wall_mat)
	_box(parent, Vector3(0.22, 8.2, 30), Vector3(-15.6, 2.6, 0), MaterialLibrary.wall_mat)
	_box(parent, Vector3(0.22, 8.2, 30), Vector3(15.6, 2.6, 0), MaterialLibrary.wall_mat)
	_box(parent, Vector3(4.0, 0.12, 32), Vector3(-14.0, 9.4, 0), MaterialLibrary.wall_mat)
	_box(parent, Vector3(4.0, 0.12, 32), Vector3(14.0, 9.4, 0), MaterialLibrary.wall_mat)
	_box(parent, Vector3(24, 0.12, 4.0), Vector3(0, 9.4, -14.0), MaterialLibrary.wall_mat)
	_box(parent, Vector3(24, 0.12, 4.0), Vector3(0, 9.4, 14.0), MaterialLibrary.wall_mat)
	_box(parent, Vector3(22.0, 0.04, 0.04), Vector3(0, 9.32, -12.05), MaterialLibrary.brass_mat)
	_box(parent, Vector3(18.0, 0.04, 0.04), Vector3(0, 6.2, -15.26), MaterialLibrary.brass_mat)
	_box(parent, Vector3(0.04, 6.4, 0.04), Vector3(-8.8, 3.4, -15.26), MaterialLibrary.brass_mat)
	_box(parent, Vector3(0.04, 6.4, 0.04), Vector3(8.8, 3.4, -15.26), MaterialLibrary.brass_mat)


static func _columns(parent: Node3D) -> void:
	for xz in [Vector2(-7.6, -7.6), Vector2(7.6, -7.6), Vector2(-7.6, 7.6), Vector2(7.6, 7.6)]:
		_cyl(parent, 0.28, 0.32, 4.4, Vector3(xz.x, 0.78, xz.y), MaterialLibrary.column_mat, 20)
		_cyl(parent, 0.40, 0.40, 0.10, Vector3(xz.x, -1.18, xz.y), MaterialLibrary.brass_mat, 16)
		_cyl(parent, 0.38, 0.34, 0.12, Vector3(xz.x, 3.02, xz.y), MaterialLibrary.brass_mat, 16)
		_cyl(parent, 0.22, 0.22, 0.06, Vector3(xz.x, 3.14, xz.y), MaterialLibrary.gold_mat, 16)


static func _drapes(parent: Node3D) -> void:
	_box(parent, Vector3(10.4, 5.2, 0.06), Vector3(0, 3.1, -15.22), MaterialLibrary.drape_mat)
	_box(parent, Vector3(10.6, 0.04, 0.05), Vector3(0, 5.72, -15.16), MaterialLibrary.brass_mat)
	_box(parent, Vector3(10.6, 0.04, 0.05), Vector3(0, 0.52, -15.16), MaterialLibrary.brass_mat)


static func _pedestal(parent: Node3D) -> void:
	_cyl(parent, 1.15, 1.35, 1.05, Vector3(0, -0.78, 0), MaterialLibrary.wood_frame, 28)
	_cyl(parent, 3.15, 3.35, 0.16, Vector3(0, -0.28, 0), MaterialLibrary.wood_frame, 28)
	_box(parent, Vector3(10.4, 0.18, 10.4), Vector3(0, -0.16, 0), MaterialLibrary.wood_frame)
	for x in [-4.7, 4.7]:
		for z in [-4.7, 4.7]:
			_cyl(parent, 0.07, 0.07, 0.22, Vector3(x, -0.02, z), MaterialLibrary.brass_mat, 12)


static func _lamps(parent: Node3D) -> void:
	for xz in [Vector2(-5.8, -5.8), Vector2(5.8, -5.8), Vector2(-5.8, 5.8), Vector2(5.8, 5.8)]:
		_cyl(parent, 0.05, 0.07, 0.55, Vector3(xz.x, 0.28, xz.y), MaterialLibrary.brass_mat, 12)
		_cyl(parent, 0.16, 0.12, 0.18, Vector3(xz.x, 0.62, xz.y), MaterialLibrary.lamp_glass, 14)
		_cyl(parent, 0.10, 0.10, 0.03, Vector3(xz.x, 0.74, xz.y), MaterialLibrary.brass_mat, 12)
		var glow := OmniLight3D.new()
		glow.position = Vector3(xz.x, 0.68, xz.y)
		glow.light_color = Color(1.0, 0.78, 0.46)
		glow.light_energy = 1.35
		glow.omni_range = 6.0
		parent.add_child(glow)


static func _branding(parent: Node3D) -> void:
	_gold_text(parent, "SHADOWFETCH", Vector3(0, 3.55, -15.10), 0.22)
	_gold_text(parent, "SHADOW CHESS", Vector3(0, 2.95, -15.10), 0.12)
	_gold_text(parent, "PRIVATE SALON", Vector3(0, 2.52, -15.10), 0.055)


static func _gold_text(parent: Node3D, text: String, pos: Vector3, size: float) -> void:
	var mi := MeshInstance3D.new()
	var tm := TextMesh.new()
	tm.text = text
	tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tm.font_size = 12
	tm.depth = 0.012
	tm.pixel_size = size / 10.0
	mi.mesh = tm
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.92, 0.76, 0.40)
	mat.emission_enabled = true
	mat.emission = Color(0.90, 0.72, 0.34)
	mat.emission_energy_multiplier = 0.55
	mi.material_override = mat
	parent.add_child(mi)
