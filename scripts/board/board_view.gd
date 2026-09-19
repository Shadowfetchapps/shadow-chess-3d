class_name BoardView
extends Node3D

signal square_clicked(sq: int)

const SQUARE := 1.0
const ORIGIN_Y := 0.0

var highlights: Array[MeshInstance3D] = []
var _light_mat: StandardMaterial3D
var _dark_mat: StandardMaterial3D
var _select_mat: StandardMaterial3D
var _legal_mat: StandardMaterial3D
var _capture_mat: StandardMaterial3D
var _check_mat: StandardMaterial3D
var _last_mat: StandardMaterial3D


func _ready() -> void:
	_build_materials()
	_build_table()
	_build_frame()
	_build_squares()
	_build_coords()
	_build_highlights()


func square_to_world(sq: int) -> Vector3:
	var f := ChessTypes.file_of(sq)
	var r := ChessTypes.rank_of(sq)
	return Vector3(f - 3.5, 0.195, 3.5 - r)


func world_to_square(pos: Vector3) -> int:
	var f := int(floor(pos.x + 4.0))
	var r := int(floor(4.0 - pos.z))
	if ChessTypes.in_board(f, r):
		return ChessTypes.sq(f, r)
	return -1


func clear_highlights() -> void:
	for h in highlights:
		h.visible = false


func show_highlight(sq: int, kind: String) -> void:
	if sq < 0 or sq > 63:
		return
	var h := highlights[sq]
	h.visible = true
	match kind:
		"select":
			h.material_override = _select_mat
		"legal":
			h.material_override = _legal_mat
		"capture":
			h.material_override = _capture_mat
		"check":
			h.material_override = _check_mat
		_:
			h.material_override = _last_mat


func _build_materials() -> void:
	_light_mat = StandardMaterial3D.new()
	_light_mat.albedo_color = Color(0.78, 0.74, 0.66)
	_light_mat.roughness = 0.55
	_light_mat.metallic = 0.04
	_dark_mat = StandardMaterial3D.new()
	_dark_mat.albedo_color = Color(0.16, 0.20, 0.26)
	_dark_mat.roughness = 0.62
	_dark_mat.metallic = 0.08
	_select_mat = _emit(Color(0.40, 0.85, 0.95, 0.55))
	_legal_mat = _emit(Color(0.35, 0.70, 0.85, 0.38))
	_capture_mat = _emit(Color(0.92, 0.38, 0.32, 0.50))
	_check_mat = _emit(Color(0.95, 0.25, 0.28, 0.58))
	_last_mat = _emit(Color(0.95, 0.78, 0.35, 0.32))


func _emit(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(c.r, c.g, c.b)
	m.emission_energy_multiplier = 0.7
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _build_table() -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(18, 0.12, 18)
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.07, 0.08, 0.10)
	mat.roughness = 0.85
	mi.material_override = mat
	mi.position.y = -0.12
	add_child(mi)


func _build_frame() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.10, 0.12)
	mat.metallic = 0.35
	mat.roughness = 0.4
	var frame := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(8.7, 0.22, 8.7)
	frame.mesh = box
	frame.material_override = mat
	frame.position.y = 0.05
	add_child(frame)
	var inner := MeshInstance3D.new()
	var ib := BoxMesh.new()
	ib.size = Vector3(8.05, 0.08, 8.05)
	inner.mesh = ib
	var felt := StandardMaterial3D.new()
	felt.albedo_color = Color(0.08, 0.12, 0.14)
	inner.material_override = felt
	inner.position.y = 0.14
	add_child(inner)


func _build_squares() -> void:
	for r in 8:
		for f in 8:
			var sq := ChessTypes.sq(f, r)
			var mi := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.98, 0.07, 0.98)
			mi.mesh = mesh
			mi.material_override = _light_mat if (f + r) % 2 == 1 else _dark_mat
			mi.position = Vector3(f - 3.5, 0.16, 3.5 - r)
			add_child(mi)
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			body.set_meta("square", sq)
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(1.0, 0.12, 1.0)
			col.shape = shape
			body.add_child(col)
			body.position = mi.position
			add_child(body)


func _build_coords() -> void:
	var font := ThemeDB.fallback_font
	for f in 8:
		_label(ChessTypes.FILE_NAMES[f], Vector3(f - 3.5, 0.22, 4.32), font)
		_label(ChessTypes.FILE_NAMES[f], Vector3(f - 3.5, 0.22, -4.32), font)
	for r in 8:
		_label(str(r + 1), Vector3(-4.32, 0.22, 3.5 - r), font)
		_label(str(r + 1), Vector3(4.32, 0.22, 3.5 - r), font)


func _label(text: String, pos: Vector3, font: Font) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = 28
	l.modulate = Color(0.55, 0.72, 0.80, 0.7)
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.position = pos
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.pixel_size = 0.012
	add_child(l)


func _build_highlights() -> void:
	highlights.resize(64)
	for r in 8:
		for f in 8:
			var sq := ChessTypes.sq(f, r)
			var mi := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.96, 0.02, 0.96)
			mi.mesh = mesh
			mi.material_override = _legal_mat
			mi.position = Vector3(f - 3.5, 0.205, 3.5 - r)
			mi.visible = false
			add_child(mi)
			highlights[sq] = mi
