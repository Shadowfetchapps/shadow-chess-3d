class_name BoardView
extends Node3D

## The playing board: base slab, 64 tiles, moulded frame, coordinates, and the
## pooled highlight marks. Geometry comes from res://assets/models when
## present (square_tile / board_frame / board_base), otherwise primitives.
## World layout: the frame rests on the table at y = 0; tile tops are at
## TOP_Y, which is where pieces stand.

const LIFT := 0.12
const TILE_H := 0.07
const TOP_Y := LIFT + TILE_H
const MODEL_DIR := "res://assets/models/"
const TRAY_X := 5.3

var _tiles: Array[MeshInstance3D] = []
var _fill: Array[MeshInstance3D] = []
var _marker: Array[MeshInstance3D] = []
var _hover: MeshInstance3D
var _check: MeshInstance3D
var _arrows: Node3D
var _coords: Array[Label3D] = []
var _hover_sq := -1
var _check_tween: Tween
var _white_bottom := true
var _frame_mi: MeshInstance3D


func _ready() -> void:
	MaterialLibrary.ensure()
	_build_base()
	_build_tiles()
	_build_frame()
	_build_trays()
	_build_coords()
	_build_marks()
	apply_settings()


# --- Coordinates ------------------------------------------------------------------

func square_to_world(sq: int) -> Vector3:
	var f := ChessTypes.file_of(sq)
	var r := ChessTypes.rank_of(sq)
	return Vector3(f - 3.5, TOP_Y, 3.5 - r)


func world_to_square(pos: Vector3) -> int:
	var f := int(floor(pos.x + 4.0))
	var r := int(floor(4.0 - pos.z))
	if ChessTypes.in_board(f, r):
		return ChessTypes.sq(f, r)
	return -1


## Slot for the index-th piece captured BY `capturer` (placed on its right).
func tray_slot(capturer: int, index: int) -> Vector3:
	var col := index % 2
	var row := int(index / 2.0)
	var side := 1.0 if capturer == ChessTypes.WHITE else -1.0
	var x := side * (TRAY_X - 0.22 + col * 0.44)
	var z := side * (3.55 - row * 0.5)
	return Vector3(x, 0.035, z)


func set_white_bottom(white_bottom: bool) -> void:
	_white_bottom = white_bottom
	var rot := 0.0 if white_bottom else 180.0
	for l in _coords:
		l.rotation_degrees = Vector3(-90, rot, 0)


func apply_settings() -> void:
	var show := SettingsStore.show_coordinates
	var c := MaterialLibrary.coord_color()
	for l in _coords:
		l.visible = show
		l.modulate = Color(c.r, c.g, c.b, 0.9)


# --- Marks --------------------------------------------------------------------------

func clear_highlights() -> void:
	for i in 64:
		_fill[i].visible = false
		_marker[i].visible = false
	_check.visible = false
	if _check_tween:
		_check_tween.kill()
		_check_tween = null


func show_highlight(sq: int, kind: String) -> void:
	if sq < 0 or sq > 63:
		return
	match kind:
		"select":
			_show_fill(sq, MaterialLibrary.mark_select)
		"last":
			if SettingsStore.highlight_last_move:
				_show_fill(sq, MaterialLibrary.mark_last)
		"premove", "hint_from":
			_show_fill(sq, MaterialLibrary.mark_premove)
		"legal":
			var m := _marker[sq]
			m.material_override = MaterialLibrary.mark_legal
			m.scale = Vector3(0.42, 1, 0.42)
			m.visible = true
		"capture":
			var c := _marker[sq]
			c.material_override = MaterialLibrary.mark_capture
			c.scale = Vector3(0.98, 1, 0.98)
			c.visible = true
		"check":
			_show_check(sq)


func show_hover(sq: int) -> void:
	if sq == _hover_sq:
		return
	_hover_sq = sq
	if sq < 0:
		_hover.visible = false
		return
	var p := square_to_world(sq)
	_hover.position = Vector3(p.x, TOP_Y + 0.006, p.z)
	_hover.visible = true


func clear_hover() -> void:
	show_hover(-1)


func _show_fill(sq: int, mat: Material) -> void:
	_fill[sq].material_override = mat
	_fill[sq].visible = true


func _show_check(sq: int) -> void:
	var p := square_to_world(sq)
	_check.position = Vector3(p.x, TOP_Y + 0.005, p.z)
	_check.visible = true
	if _check_tween:
		_check_tween.kill()
	_check.scale = Vector3(1.5, 1, 1.5)
	if SettingsStore.reduce_motion:
		return
	_check_tween = create_tween().set_loops()
	_check_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_check_tween.tween_property(_check, "scale", Vector3(1.75, 1, 1.75), 0.55)
	_check_tween.tween_property(_check, "scale", Vector3(1.45, 1, 1.45), 0.55)


## Draws a flat arrow between squares. Knight moves bend like an L.
func show_arrow(from_sq: int, to_sq: int, mat: Material = null, clear_first: bool = true) -> void:
	if clear_first:
		clear_arrows()
	if from_sq < 0 or to_sq < 0:
		return
	var a := square_to_world(from_sq)
	var b := square_to_world(to_sq)
	var pts: Array[Vector3] = [a]
	var df := absi(ChessTypes.file_of(to_sq) - ChessTypes.file_of(from_sq))
	var dr := absi(ChessTypes.rank_of(to_sq) - ChessTypes.rank_of(from_sq))
	if (df == 1 and dr == 2) or (df == 2 and dr == 1):
		if dr == 2:
			pts.append(Vector3(a.x, a.y, b.z))
		else:
			pts.append(Vector3(b.x, a.y, a.z))
	pts.append(b)
	var mi := MeshInstance3D.new()
	mi.mesh = _arrow_mesh(pts, 0.15, 0.44, 0.40)
	mi.material_override = mat if mat else MaterialLibrary.mark_hint
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.012
	_arrows.add_child(mi)
	if not SettingsStore.reduce_motion:
		mi.transparency = 1.0
		var tw := create_tween()
		tw.tween_property(mi, "transparency", 0.0, 0.25)


func clear_arrows() -> void:
	for c in _arrows.get_children():
		c.queue_free()


func _arrow_mesh(pts: Array[Vector3], shaft_w: float, head_w: float, head_len: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var start_trim := 0.28
	var n := pts.size()
	for i in n - 1:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var dir := (p1 - p0).normalized()
		if i == 0:
			p0 += dir * start_trim
		if i == n - 2:
			p1 -= dir * head_len
		elif n > 2:
			p1 += dir * shaft_w * 0.5
		var side := dir.cross(Vector3.UP).normalized() * shaft_w * 0.5
		_quad(st, p0 - side, p0 + side, p1 + side, p1 - side)
	var tip := pts[n - 1]
	var last_dir := (tip - pts[n - 2]).normalized()
	var base := tip - last_dir * head_len
	var hs := last_dir.cross(Vector3.UP).normalized() * head_w * 0.5
	st.add_vertex(Vector3(base.x - hs.x, TOP_Y, base.z - hs.z))
	st.add_vertex(Vector3(tip.x - last_dir.x * 0.12, TOP_Y, tip.z - last_dir.z * 0.12))
	st.add_vertex(Vector3(base.x + hs.x, TOP_Y, base.z + hs.z))
	return st.commit()


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		st.add_vertex(Vector3(v.x, TOP_Y, v.z))


# --- Construction ---------------------------------------------------------------

func _model(name: String) -> Mesh:
	var p := MODEL_DIR + name + ".obj"
	return load(p) as Mesh if ResourceLoader.exists(p) else null


func _build_base() -> void:
	var mi := MeshInstance3D.new()
	var mesh := _model("board_base")
	if mesh == null:
		var box := BoxMesh.new()
		box.size = Vector3(8.02, 0.1, 8.02)
		mesh = box
		mi.position.y = LIFT - 0.05
	else:
		mi.position.y = LIFT
	mi.mesh = mesh
	mi.material_override = MaterialLibrary.base_mat
	add_child(mi)


func _build_tiles() -> void:
	var tile := _model("square_tile")
	var authored := tile != null
	if not authored:
		var box := BoxMesh.new()
		box.size = Vector3(0.985, TILE_H, 0.985)
		tile = box
	var rng := RandomNumberGenerator.new()
	rng.seed = 64
	for r in 8:
		for f in 8:
			var sq := ChessTypes.sq(f, r)
			var mi := MeshInstance3D.new()
			mi.mesh = tile
			var light := (f + r) % 2 == 1
			var variant := rng.randi_range(0, MaterialLibrary.SQUARE_VARIANTS - 1)
			mi.material_override = MaterialLibrary.light_square(variant) if light else MaterialLibrary.dark_square(variant)
			mi.position = Vector3(f - 3.5, LIFT + (0.0 if authored else TILE_H * 0.5), 3.5 - r)
			# Alternate grain direction like a real inlaid board.
			mi.rotation.y = (PI * 0.5 if (f + r) % 2 == 0 else 0.0) + (PI if rng.randf() < 0.5 else 0.0)
			add_child(mi)
			_tiles.append(mi)
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			body.set_meta("square", sq)
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(1.0, 0.1, 1.0)
			col.shape = shape
			body.add_child(col)
			body.position = Vector3(f - 3.5, TOP_Y - 0.05, 3.5 - r)
			add_child(body)


func _build_frame() -> void:
	var mesh := _model("board_frame")
	if mesh:
		_frame_mi = MeshInstance3D.new()
		_frame_mi.mesh = mesh
		_frame_mi.position.y = LIFT
		for i in mesh.get_surface_count():
			var role := PieceMeshBuilder.surface_role(mesh, i)
			_frame_mi.set_surface_override_material(i, MaterialLibrary.inlay_mat if role == "trim" else MaterialLibrary.frame_mat)
		add_child(_frame_mi)
		return
	var w := 0.6
	var h := 0.22
	for side in 4:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		var horizontal := side < 2
		box.size = Vector3(8.0 + w * 2.0, h, w) if horizontal else Vector3(w, h, 8.0)
		mi.mesh = box
		mi.material_override = MaterialLibrary.frame_mat
		var off := 4.0 + w * 0.5
		match side:
			0: mi.position = Vector3(0, h * 0.5, off)
			1: mi.position = Vector3(0, h * 0.5, -off)
			2: mi.position = Vector3(off, h * 0.5, 0)
			3: mi.position = Vector3(-off, h * 0.5, 0)
		add_child(mi)
	var inlay := MeshInstance3D.new()
	var ib := BoxMesh.new()
	ib.size = Vector3(8.12, 0.01, 8.12)
	inlay.mesh = ib
	inlay.material_override = MaterialLibrary.inlay_mat
	inlay.position.y = TOP_Y - 0.02
	add_child(inlay)


func _build_trays() -> void:
	for side in [-1.0, 1.0]:
		var tray := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.0, 0.03, 8.1)
		tray.mesh = box
		tray.material_override = MaterialLibrary.felt_mat
		tray.position = Vector3(side * TRAY_X, 0.015, 0)
		add_child(tray)
		for edge in [-0.52, 0.52]:
			var rail := MeshInstance3D.new()
			var rb := BoxMesh.new()
			rb.size = Vector3(0.04, 0.05, 8.1)
			rail.mesh = rb
			rail.material_override = MaterialLibrary.brass_mat
			rail.position = Vector3(side * TRAY_X + edge, 0.025, 0)
			add_child(rail)


func _build_coords() -> void:
	var font := ThemeFactory.font("display_medium")
	var y := LIFT + 0.105
	for f in 8:
		for z in [4.3, -4.3]:
			_coord(ChessTypes.FILE_NAMES[f], Vector3(f - 3.5, y, z), font)
	for r in 8:
		for x in [-4.3, 4.3]:
			_coord(str(r + 1), Vector3(x, y, 3.5 - r), font)


func _coord(text: String, pos: Vector3, font: Font) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = 72
	l.pixel_size = 0.0028
	l.outline_size = 0
	l.position = pos
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.double_sided = false
	l.shaded = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	_coords.append(l)


func _build_marks() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	var disc := PlaneMesh.new()
	disc.size = Vector2(1.0, 1.0)
	for r in 8:
		for f in 8:
			var origin := Vector3(f - 3.5, TOP_Y, 3.5 - r)
			var fill := MeshInstance3D.new()
			fill.mesh = plane
			fill.scale = Vector3(0.985, 1, 0.985)
			fill.position = origin + Vector3(0, 0.003, 0)
			fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fill.visible = false
			add_child(fill)
			_fill.append(fill)
			var marker := MeshInstance3D.new()
			marker.mesh = disc
			marker.position = origin + Vector3(0, 0.008, 0)
			marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			marker.visible = false
			add_child(marker)
			_marker.append(marker)
	_hover = MeshInstance3D.new()
	_hover.mesh = plane
	_hover.material_override = MaterialLibrary.mark_hover
	_hover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hover.visible = false
	add_child(_hover)
	_check = MeshInstance3D.new()
	_check.mesh = plane
	_check.material_override = MaterialLibrary.mark_check
	_check.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_check.visible = false
	add_child(_check)
	_arrows = Node3D.new()
	_arrows.name = "Arrows"
	add_child(_arrows)
