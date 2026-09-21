class_name OrbitCamera
extends Node3D

@export var target := Vector3(0.0, 0.22, 0.0)
@export var distance := 11.2
@export var min_distance := 6.8
@export var max_distance := 17.5
@export var yaw_deg := 0.0
@export var pitch_deg := 42.0
@export var min_pitch := 22.0
@export var max_pitch := 80.0

var _orbiting := false
var _panning := false
var _pan_offset := Vector3.ZERO
var camera: Camera3D


func _ready() -> void:
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 40.0
	camera.near = 0.08
	camera.far = 90.0
	add_child(camera)
	_apply()


func apply_quality() -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	var sens := SettingsStore.camera_sensitivity
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = clampf(distance - 0.55 * sens, min_distance, max_distance)
			_apply()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = clampf(distance + 0.55 * sens, min_distance, max_distance)
			_apply()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			yaw_deg -= mm.relative.x * 0.28 * sens
			pitch_deg = clampf(pitch_deg + mm.relative.y * 0.22 * sens, min_pitch, max_pitch)
			_apply()
		elif _panning:
			_pan_offset -= Vector3(mm.relative.x, -mm.relative.y, 0.0) * 0.008 * distance * sens
			_apply()
	if event.is_action_pressed("reset_camera"):
		reset_view(absf(yaw_deg) < 90.0)


func reset_view(white_side: bool = true) -> void:
	_pan_offset = Vector3.ZERO
	distance = 11.2
	pitch_deg = 42.0
	yaw_deg = 0.0 if white_side else 180.0
	_apply()


func face_side(white_side: bool) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "yaw_deg", 0.0 if white_side else 180.0, 0.50)
	tw.parallel().tween_method(func(_v): _apply(), 0, 1, 0.50)


func _apply() -> void:
	global_position = target + _pan_offset
	rotation_degrees = Vector3(0, yaw_deg, 0)
	if camera == null:
		return
	var pitch := deg_to_rad(pitch_deg)
	camera.position = Vector3(0.0, sin(pitch) * distance, cos(pitch) * distance)
	camera.look_at(target + _pan_offset, Vector3.UP)
