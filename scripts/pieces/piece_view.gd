class_name PieceView
extends Node3D

## One chess piece on the board: mesh, contact shadow, and small motion cues
## (hover lift, selection float, landing squash, check jolt, drag lift).

const SELECT_LIFT := 0.09
const HOVER_LIFT := 0.035

static var _blob_mesh: PlaneMesh

var square: int = -1
var piece_type: int = 0
var piece_color: int = 0
var in_tray := false
var _visual: Node3D
var _blob: MeshInstance3D
var _motion: Tween
var _loop: Tween
var _selected := false
var _hovered := false
var _dragging := false


func setup(type: int, color: int, sq: int) -> void:
	piece_type = type
	piece_color = color
	square = sq
	_visual = PieceMeshBuilder.build(type, color)
	add_child(_visual)
	if color == ChessTypes.BLACK:
		_visual.rotation.y = PI
	if _blob_mesh == null:
		_blob_mesh = PlaneMesh.new()
		_blob_mesh.size = Vector2(1.0, 1.0)
	_blob = MeshInstance3D.new()
	_blob.mesh = _blob_mesh
	_blob.material_override = MaterialLibrary.contact_shadow
	_blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var r := PieceMeshBuilder.radius_of(type) * 2.6
	_blob.scale = Vector3(r, 1.0, r)
	_blob.position.y = 0.004
	add_child(_blob)


func visual() -> Node3D:
	return _visual


func set_selected(on: bool) -> void:
	_selected = on
	_restart_motion()


func set_hovered(on: bool) -> void:
	if _hovered == on:
		return
	_hovered = on
	if not _selected and not _dragging:
		_restart_motion()


func set_dragging(on: bool) -> void:
	_dragging = on
	_kill()
	if not is_instance_valid(_visual):
		return
	if on:
		_visual.position.y = 0.0
		_blob.visible = false
	else:
		_blob.visible = true
		_restart_motion()


func set_tray(on: bool) -> void:
	in_tray = on
	_selected = false
	_hovered = false
	_kill()
	if is_instance_valid(_visual):
		_visual.position.y = 0.0


func kill_motion() -> void:
	_kill()
	if is_instance_valid(_visual):
		_visual.position.y = 0.0
		_visual.scale = Vector3.ONE


func play_land(strength: float = 1.0) -> void:
	if SettingsStore.reduce_motion or not is_instance_valid(_visual):
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var s := 0.06 * strength
	tw.tween_property(_visual, "scale", Vector3(1.0 + s, 1.0 - s * 1.5, 1.0 + s), 0.05)
	tw.tween_property(_visual, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_BACK)


func pulse_check() -> void:
	if SettingsStore.reduce_motion or _selected or not is_instance_valid(_visual):
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_visual, "rotation:z", 0.09, 0.06)
	tw.tween_property(_visual, "rotation:z", -0.07, 0.08)
	tw.tween_property(_visual, "rotation:z", 0.04, 0.07)
	tw.tween_property(_visual, "rotation:z", 0.0, 0.09)


func pop_in() -> void:
	if not is_instance_valid(_visual):
		return
	_visual.scale = Vector3(0.6, 1.25, 0.6)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_visual, "scale", Vector3.ONE, 0.28)


func _kill() -> void:
	if _motion:
		_motion.kill()
		_motion = null
	if _loop:
		_loop.kill()
		_loop = null


func _restart_motion() -> void:
	_kill()
	if not is_instance_valid(_visual) or in_tray:
		return
	var lift := 0.0
	if _selected:
		lift = SELECT_LIFT
	elif _hovered:
		lift = HOVER_LIFT
	_motion = create_tween()
	_motion.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_motion.tween_property(_visual, "position:y", lift, 0.14)
	if _selected and not SettingsStore.reduce_motion:
		_loop = create_tween().set_loops()
		_loop.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_loop.tween_interval(0.14)
		_loop.tween_property(_visual, "position:y", lift + 0.025, 0.7)
		_loop.tween_property(_visual, "position:y", lift - 0.01, 0.7)
