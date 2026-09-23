class_name SalonBuilder
extends RefCounted

## The private salon around the board: a leather-topped walnut table with a
## brass edge, herringbone floor and rug, damask walls with wainscot, velvet
## drapes with gold branding, brass floor lamps, and a working chess clock.
## Table top is y = 0 (the board frame rests on it).

const TABLE_HALF := 7.0
const FLOOR_Y := -3.2


static func build(parent: Node3D, with_clock: bool = true) -> Node3D:
	MaterialLibrary.ensure()
	var root := Node3D.new()
	root.name = "Salon"
	parent.add_child(root)
	_table(root)
	_room(root)
	_drapes_and_branding(root)
	_lamps(root)
	if with_clock:
		var clock := ChessClockProp.new()
		clock.name = "ChessClock"
		clock.position = Vector3(-6.25, 0.0, -1.6)
		clock.rotation_degrees = Vector3(0, 62, 0)
		root.add_child(clock)
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


static func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, segs := 32) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bot
	mesh.height = h
	mesh.radial_segments = segs
	mesh.rings = 1
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _table(parent: Node3D) -> void:
	var t := TABLE_HALF * 2.0
	_box(parent, Vector3(t, 0.34, t), Vector3(0, -0.17, 0), MaterialLibrary.table_wood)
	_box(parent, Vector3(t - 1.1, 0.012, t - 1.1), Vector3(0, 0.001, 0), MaterialLibrary.leather_mat)
	# Brass edge banding and a routed lip.
	for s in [-1.0, 1.0]:
		_box(parent, Vector3(t + 0.04, 0.05, 0.05), Vector3(0, -0.02, s * (TABLE_HALF + 0.005)), MaterialLibrary.brass_mat)
		_box(parent, Vector3(0.05, 0.05, t + 0.04), Vector3(s * (TABLE_HALF + 0.005), -0.02, 0), MaterialLibrary.brass_mat)
		_box(parent, Vector3(t - 1.06, 0.018, 0.03), Vector3(0, 0.006, s * (TABLE_HALF - 0.55)), MaterialLibrary.brass_mat)
		_box(parent, Vector3(0.03, 0.018, t - 1.06), Vector3(s * (TABLE_HALF - 0.55), 0.006, 0), MaterialLibrary.brass_mat)
	# Apron and a heavy turned pedestal.
	_box(parent, Vector3(t - 0.8, 0.5, t - 0.8), Vector3(0, -0.58, 0), MaterialLibrary.table_wood)
	_cyl(parent, 1.4, 1.1, 1.4, Vector3(0, -1.5, 0), MaterialLibrary.table_wood, 48)
	_cyl(parent, 0.9, 1.3, 0.3, Vector3(0, -2.3, 0), MaterialLibrary.table_wood, 48)
	_cyl(parent, 3.2, 3.4, 0.35, Vector3(0, FLOOR_Y + 0.2, 0), MaterialLibrary.table_wood, 64)
	_cyl(parent, 1.42, 1.42, 0.06, Vector3(0, -0.82, 0), MaterialLibrary.brass_mat, 48)


static func _room(parent: Node3D) -> void:
	var floor := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(70, 70)
	floor.mesh = fp
	floor.material_override = MaterialLibrary.floor_mat
	floor.position.y = FLOOR_Y
	parent.add_child(floor)
	var rug := MeshInstance3D.new()
	var rp := PlaneMesh.new()
	rp.size = Vector2(22, 16)
	rug.mesh = rp
	rug.material_override = MaterialLibrary.rug_mat
	rug.position.y = FLOOR_Y + 0.01
	parent.add_child(rug)
	# Tall walls and no ceiling: the framed camera can rise well above the
	# table, and the open top reads as darkness above the lamps.
	var h := 34.0
	var cy := FLOOR_Y + h * 0.5
	var walls := [
		[Vector3(44, h, 0.3), Vector3(0, cy, -19.0)],
		[Vector3(44, h, 0.3), Vector3(0, cy, 22.0)],
		[Vector3(0.3, h, 44), Vector3(-21.0, cy, 0)],
		[Vector3(0.3, h, 44), Vector3(21.0, cy, 0)],
	]
	for w in walls:
		_box(parent, w[0], w[1], MaterialLibrary.wall_mat)
		var size: Vector3 = w[0]
		var pos: Vector3 = w[1]
		var inward := -pos.normalized() * 0.2
		var wains := Vector3(size.x if size.x > 1 else 0.12, 2.6, size.z if size.z > 1 else 0.12)
		_box(parent, wains, Vector3(pos.x, FLOOR_Y + 1.3, pos.z) + Vector3(inward.x, 0, inward.z), MaterialLibrary.table_wood)
		var rail := Vector3(size.x if size.x > 1 else 0.16, 0.08, size.z if size.z > 1 else 0.16)
		_box(parent, rail, Vector3(pos.x, FLOOR_Y + 2.62, pos.z) + Vector3(inward.x, 0, inward.z) * 1.2, MaterialLibrary.brass_mat)
		_box(parent, rail, Vector3(pos.x, FLOOR_Y + 12.4, pos.z) + Vector3(inward.x, 0, inward.z) * 1.2, MaterialLibrary.brass_mat)
	for x in [-11.0, 11.0]:
		_cyl(parent, 0.45, 0.5, 12.6, Vector3(x, FLOOR_Y + 6.3, -18.4), MaterialLibrary.column_mat, 32)
		_cyl(parent, 0.7, 0.7, 0.3, Vector3(x, FLOOR_Y + 0.15, -18.4), MaterialLibrary.brass_mat, 32)
		_cyl(parent, 0.62, 0.5, 0.3, Vector3(x, FLOOR_Y + 12.45, -18.4), MaterialLibrary.brass_mat, 32)


static func _drapes_and_branding(parent: Node3D) -> void:
	# Pleated velvet: a row of slim cylinders reads as folds under the lamps.
	for i in 36:
		var x := -8.75 + i * 0.5
		var fold := _cyl(parent, 0.3, 0.32, 9.0, Vector3(x, FLOOR_Y + 5.0, -18.55 + (0.08 if i % 2 == 0 else 0.0)), MaterialLibrary.drape_mat, 12)
		fold.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(parent, Vector3(18.6, 0.14, 0.2), Vector3(0, FLOOR_Y + 9.6, -18.3), MaterialLibrary.brass_mat)
	var plaque := _box(parent, Vector3(9.0, 2.2, 0.12), Vector3(0, 4.3, -18.1), MaterialLibrary.table_wood)
	plaque.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(parent, Vector3(9.2, 0.05, 0.14), Vector3(0, 5.42, -18.05), MaterialLibrary.brass_mat)
	_box(parent, Vector3(9.2, 0.05, 0.14), Vector3(0, 3.18, -18.05), MaterialLibrary.brass_mat)
	_gold_text(parent, "SHADOWFETCH", Vector3(0, 4.62, -18.02), 0.30, "display")
	_gold_text(parent, "PRIVATE SALON  ·  SHADOW CHESS", Vector3(0, 3.78, -18.02), 0.085, "semibold")


static func _gold_text(parent: Node3D, text: String, pos: Vector3, size: float, font_kind: String) -> void:
	var mi := MeshInstance3D.new()
	var tm := TextMesh.new()
	tm.text = text
	tm.font = ThemeFactory.font(font_kind)
	tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tm.font_size = 32
	tm.depth = 0.03
	tm.pixel_size = size / 26.0
	mi.mesh = tm
	mi.position = pos
	mi.material_override = MaterialLibrary.gold_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _lamps(parent: Node3D) -> void:
	# Floor lamps stand back in the room corners so they frame the table
	# without their poles crossing the playing view.
	for xz in [Vector2(-14.5, -12.5), Vector2(14.5, -12.5), Vector2(-15.5, 13.0), Vector2(15.5, 13.0)]:
		var base_y := FLOOR_Y
		_cyl(parent, 0.5, 0.6, 0.12, Vector3(xz.x, base_y + 0.06, xz.y), MaterialLibrary.brass_mat, 32)
		_cyl(parent, 0.05, 0.06, 4.2, Vector3(xz.x, base_y + 2.2, xz.y), MaterialLibrary.brass_mat, 16)
		var shade := _cyl(parent, 0.42, 0.78, 0.9, Vector3(xz.x, base_y + 4.4, xz.y), MaterialLibrary.lamp_glass, 40)
		shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_cyl(parent, 0.8, 0.8, 0.04, Vector3(xz.x, base_y + 3.96, xz.y), MaterialLibrary.brass_mat, 40)
		var glow := OmniLight3D.new()
		glow.name = "LampLight"
		glow.position = Vector3(xz.x, base_y + 4.3, xz.y)
		glow.light_color = Color(1.0, 0.72, 0.42)
		glow.light_energy = 2.2
		glow.omni_range = 11.0
		glow.omni_attenuation = 1.4
		glow.shadow_enabled = false
		glow.light_volumetric_fog_energy = 0.6
		parent.add_child(glow)
