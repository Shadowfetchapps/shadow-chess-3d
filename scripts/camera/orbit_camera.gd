class_name OrbitCamera
extends Node3D

@export var target := Vector3(0.0, 0.25, 0.0)
@export var distance := 11.5
@export var min_distance := 7.0
@export var max_distance := 18.0
@export var yaw_deg := 0.0
@export var pitch_deg := 52.0
@export var min_pitch := 22.0
@export var max_pitch := 82.0

var _orbiting := false
var _panning := false
var _pan_offset := Vector3.ZERO
var camera: Camera3D


func _ready() -> void:
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 38.0
	camera.near = 0.08
	camera.far = 80.0
	add_child(camera)
	_apply()


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
			var right := camera.global_transform.basis.x
			var up := Vector3.UP
			_pan_offset -= (right * mm.relative.x + up * mm.relative.y) * 0.008 * distance * sens
			_apply()
	if event.is_action_pressed("reset_camera"):
		reset_view()


func reset_view(white_side: bool = true) -> void:
	_pan_offset = Vector3.ZERO
	distance = 11.5
	pitch_deg = 52.0
	yaw_deg = 0.0 if white_side else 180.0
	_apply()


func face_side(white_side: bool) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "yaw_deg", 0.0 if white_side else 180.0, 0.55)
	tw.parallel().tween_method(func(_v): _apply(), 0, 1, 0.55)


func _apply() -> void:
	var pitch := deg_to_rad(pitch_deg)
	var yaw := deg_to_rad(yaw_deg)
	var offset := Vector3(
		sin(yaw) * cos(pitch),
		sin(pitch),
		cos(yaw) * cos(pitch)
	) * distance
	if camera:
		camera.global_position = target + _pan_offset + offset
		camera.look_at(target + _pan_offset, Vector3.UP)
