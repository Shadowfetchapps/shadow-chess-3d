class_name BoardView
extends Node3D

signal square_clicked(sq: int)

const SQUARE := 1.0
const ORIGIN_Y := 0.0

var _wash: Array[MeshInstance3D] = []
var _marker: Array[MeshInstance3D] = []
var _hover: Array[MeshInstance3D] = []
var _disc_mesh: CylinderMesh
var _ring_mesh: TorusMesh
var _hover_sq: int = -1
var _check_sq: int = -1
var _check_pulse: Tween


func _ready() -> void:
	MaterialLibrary.ensure()
	_build_shared_meshes()
	_build_frame()
	_build_squares()
	_build_coords()
	_build_marks()


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
	for i in 64:
		_wash[i].visible = false
		_marker[i].visible = false
	if _check_pulse:
		_check_pulse.kill()
		_check_pulse = null
	_check_sq = -1


func clear_hover() -> void:
	if _hover_sq >= 0:
		_hover[_hover_sq].visible = false
		_hover_sq = -1


func show_hover(sq: int) -> void:
	if sq == _hover_sq:
		return
	clear_hover()
	if sq < 0 or sq > 63:
		return
	_hover_sq = sq
	_hover[sq].visible = true


func show_highlight(sq: int, kind: String) -> void:
	if sq < 0 or sq > 63:
		return
	match kind:
		"select":
			_wash[sq].visible = true
			_wash[sq].material_override = MaterialLibrary.select_mat
		"legal":
			_marker[sq].visible = true
			_marker[sq].mesh = _disc_mesh
			_marker[sq].material_override = MaterialLibrary.legal_mat
			_marker[sq].position.y = 0.212
			_marker[sq].scale = Vector3.ONE
		"capture":
			_marker[sq].visible = true
			_marker[sq].mesh = _ring_mesh
			_marker[sq].material_override = MaterialLibrary.capture_mat
			_marker[sq].position.y = 0.214
			_marker[sq].scale = Vector3(1, 0.22, 1)
		"check":
			_wash[sq].visible = true
			_wash[sq].material_override = MaterialLibrary.check_mat
			_pulse_check(sq)
		_:
			_wash[sq].visible = true
			_wash[sq].material_override = MaterialLibrary.last_mat


func _pulse_check(sq: int) -> void:
	_check_sq = sq
	if _check_pulse:
		_check_pulse.kill()
	var h := _wash[sq]
	h.scale = Vector3.ONE
	_check_pulse = create_tween().set_loops()
	_check_pulse.set_trans(Tween.TRANS_SINE)
	_check_pulse.tween_property(h, "scale", Vector3(1.04, 1.0, 1.04), 0.38)
	_check_pulse.tween_property(h, "scale", Vector3(0.96, 1.0, 0.96), 0.38)


func _build_shared_meshes() -> void:
	_disc_mesh = CylinderMesh.new()
	_disc_mesh.top_radius = 0.13
	_disc_mesh.bottom_radius = 0.13
	_disc_mesh.height = 0.018
	_disc_mesh.radial_segments = 20
	_disc_mesh.rings = 1
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.28
	_ring_mesh.outer_radius = 0.36
	_ring_mesh.rings = 20
	_ring_mesh.ring_segments = 8


func _build_frame() -> void:
	var frame := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(8.85, 0.24, 8.85)
	frame.mesh = box
	frame.material_override = MaterialLibrary.wood_frame
	frame.position.y = 0.04
	add_child(frame)
	var inlay := MeshInstance3D.new()
	var ib := BoxMesh.new()
	ib.size = Vector3(8.18, 0.04, 8.18)
	inlay.mesh = ib
	inlay.material_override = MaterialLibrary.gold_mat
	inlay.position.y = 0.145
	add_child(inlay)
	var felt := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(8.06, 0.03, 8.06)
	felt.mesh = fb
	felt.material_override = MaterialLibrary.felt_mat
	felt.position.y = 0.155
	add_child(felt)
	for x in [-4.28, 4.28]:
		for z in [-4.28, 4.28]:
			var cap := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.09
			cyl.bottom_radius = 0.09
			cyl.height = 0.08
			cyl.radial_segments = 14
			cap.mesh = cyl
			cap.material_override = MaterialLibrary.brass_mat
			cap.position = Vector3(x, 0.20, z)
			add_child(cap)


func _build_squares() -> void:
	for r in 8:
		for f in 8:
			var sq := ChessTypes.sq(f, r)
			var mi := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.97, 0.075, 0.97)
			mi.mesh = mesh
			var light := (f + r) % 2 == 1
			mi.material_override = MaterialLibrary.light_sq if light else MaterialLibrary.dark_sq
			mi.position = Vector3(f - 3.5, 0.168, 3.5 - r)
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
	for f in 8:
		_coord(ChessTypes.FILE_NAMES[f], Vector3(f - 3.5, 0.20, 4.38))
		_coord(ChessTypes.FILE_NAMES[f], Vector3(f - 3.5, 0.20, -4.38))
	for r in 8:
		_coord(str(r + 1), Vector3(-4.38, 0.20, 3.5 - r))
		_coord(str(r + 1), Vector3(4.38, 0.20, 3.5 - r))


func _coord(text: String, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var tm := TextMesh.new()
	tm.text = text
	tm.font_size = 8
	tm.depth = 0.004
	tm.pixel_size = 0.012
	tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mi.mesh = tm
	mi.position = pos
	mi.rotation_degrees = Vector3(-90, 0, 0)
	mi.material_override = MaterialLibrary.gold_mat
	add_child(mi)


func _build_marks() -> void:
	_wash.resize(64)
	_marker.resize(64)
	_hover.resize(64)
	var wash_mesh := BoxMesh.new()
	wash_mesh.size = Vector3(0.96, 0.012, 0.96)
	var hover_mesh := BoxMesh.new()
	hover_mesh.size = Vector3(0.99, 0.008, 0.99)
	for r in 8:
		for f in 8:
			var sq := ChessTypes.sq(f, r)
			var origin := Vector3(f - 3.5, 0.208, 3.5 - r)
			var wash := MeshInstance3D.new()
			wash.mesh = wash_mesh
			wash.material_override = MaterialLibrary.last_mat
			wash.position = origin
			wash.visible = false
			add_child(wash)
			_wash[sq] = wash
			var marker := MeshInstance3D.new()
			marker.mesh = _disc_mesh
			marker.material_override = MaterialLibrary.legal_mat
			marker.position = Vector3(origin.x, 0.212, origin.z)
			marker.visible = false
			add_child(marker)
			_marker[sq] = marker
			var hover := MeshInstance3D.new()
			hover.mesh = hover_mesh
			hover.material_override = MaterialLibrary.hover_mat
			hover.position = Vector3(origin.x, 0.206, origin.z)
			hover.visible = false
			add_child(hover)
			_hover[sq] = hover
