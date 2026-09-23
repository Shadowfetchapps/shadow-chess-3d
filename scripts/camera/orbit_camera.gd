class_name OrbitCamera
extends Node3D

## Damped orbit camera. Goal values (yaw/pitch/distance/pan) are set by input
## or code and the rig eases toward them every frame. The board is framed in
## the part of the screen not covered by HUD panels (lateral h/v offset), so
## it stays centred in the free space at any window size.

signal view_changed

const PLAYER_PITCH := 52.0
const TOP_PITCH := 89.0
const BOARD_HALF := 4.62
const TRAY_HALF := 5.9

var target := Vector3(0.0, 0.25, 0.0)
var yaw := 0.0
var pitch := PLAYER_PITCH
var distance := 14.0
var pan := Vector3.ZERO
var min_pitch := 16.0
var max_pitch := 89.0
var interactive := true
var auto_orbit_speed := 0.0
var inset_left := 0.0
var inset_right := 0.0
var inset_top := 0.0
var inset_bottom := 0.0
var camera: Camera3D
var attributes: CameraAttributesPractical
var top_view := false
var white_side := true

var _yaw := 0.0
var _pitch := PLAYER_PITCH
var _distance := 14.0
var _pan := Vector3.ZERO
var _orbiting := false
var _panning := false
var _user_zoom := 1.0
var _smoothing := 9.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 34.0
	camera.near = 0.1
	camera.far = 120.0
	attributes = WorldLook.make_camera_attributes()
	camera.attributes = attributes
	add_child(camera)
	distance = frame_distance()
	_snap()
	get_viewport().size_changed.connect(_on_resize)


func set_insets(left: float, right: float, top: float = 0.0, bottom: float = 0.0) -> void:
	inset_left = left
	inset_right = right
	inset_top = top
	inset_bottom = bottom
	distance = frame_distance() * _user_zoom


func frame_distance() -> float:
	var vp := get_viewport()
	var size := vp.get_visible_rect().size if vp else Vector2(1600, 900)
	var free_w := maxf(size.x - inset_left - inset_right, size.x * 0.4)
	var free_h := maxf(size.y - inset_top - inset_bottom, size.y * 0.5)
	var tan_v := tan(deg_to_rad(camera.fov if camera else 34.0) * 0.5)
	var p := deg_to_rad(pitch)
	var half_depth := BOARD_HALF * sin(p) + 1.0 * cos(p)
	var need_v := half_depth / (tan_v * (free_h / size.y) * 0.92)
	var tan_h_free := tan_v * (free_w / size.y)
	var need_h := TRAY_HALF / (tan_h_free * 0.94)
	return maxf(need_v, need_h) + BOARD_HALF * cos(p) * 0.35


func reset_view(white: bool = true, instant: bool = false) -> void:
	white_side = white
	top_view = SettingsStore.camera_view == "top"
	pan = Vector3.ZERO
	_user_zoom = 1.0
	yaw = 0.0 if white else 180.0
	pitch = TOP_PITCH if top_view else PLAYER_PITCH
	distance = frame_distance()
	if instant:
		_snap()
	view_changed.emit()


func face_side(white: bool) -> void:
	white_side = white
	var goal := 0.0 if white else 180.0
	# Take the short way round from wherever the user has orbited to.
	var diff := fposmod(goal - yaw + 180.0, 360.0) - 180.0
	yaw += diff
	view_changed.emit()


func set_top_view(on: bool) -> void:
	top_view = on
	pitch = TOP_PITCH if on else PLAYER_PITCH
	distance = frame_distance() * _user_zoom
	view_changed.emit()


func toggle_top_view() -> void:
	set_top_view(not top_view)


func is_white_bottom() -> bool:
	var y := fposmod(_yaw, 360.0)
	return y < 90.0 or y > 270.0


func _snap() -> void:
	_yaw = yaw
	_pitch = pitch
	_distance = distance
	_pan = pan
	_apply()


func _on_resize() -> void:
	distance = frame_distance() * _user_zoom


func _process(delta: float) -> void:
	if auto_orbit_speed != 0.0:
		yaw += auto_orbit_speed * delta
	if interactive:
		var turn := 0.0
		if Input.is_action_pressed("orbit_left"):
			turn += 1.0
		if Input.is_action_pressed("orbit_right"):
			turn -= 1.0
		if turn != 0.0:
			yaw += turn * 90.0 * delta * SettingsStore.camera_sensitivity
		var zoom := 0.0
		if Input.is_action_pressed("zoom_in"):
			zoom -= 1.0
		if Input.is_action_pressed("zoom_out"):
			zoom += 1.0
		if zoom != 0.0:
			_zoom_by(1.0 + zoom * delta * 1.2)
	var k := 1.0 - exp(-delta * (_smoothing if not SettingsStore.reduce_motion else 30.0))
	var was_bottom := is_white_bottom()
	_yaw = lerpf(_yaw, yaw, k)
	_pitch = lerpf(_pitch, pitch, k)
	_distance = lerpf(_distance, distance, k)
	_pan = _pan.lerp(pan, k)
	_apply()
	if was_bottom != is_white_bottom():
		view_changed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not interactive:
		return
	var sens := SettingsStore.camera_sensitivity
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_by(0.92)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_by(1.08)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			var inv := -1.0 if SettingsStore.invert_orbit else 1.0
			yaw -= mm.relative.x * 0.3 * sens
			pitch = clampf(pitch + mm.relative.y * 0.25 * sens * inv, min_pitch, max_pitch)
			top_view = pitch > 80.0
		elif _panning:
			var basis := Basis(Vector3.UP, deg_to_rad(_yaw))
			var right := basis.x
			var fwd := -basis.z
			pan -= right * mm.relative.x * 0.0022 * _distance * sens
			pan += fwd * mm.relative.y * 0.0022 * _distance * sens
			pan = pan.limit_length(4.5)
			pan.y = 0.0
	elif event is InputEventMagnifyGesture:
		_zoom_by(1.0 / (event as InputEventMagnifyGesture).factor)
	if event.is_action_pressed("reset_camera"):
		reset_view(white_side)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("top_view"):
		toggle_top_view()
		get_viewport().set_input_as_handled()


func _zoom_by(f: float) -> void:
	_user_zoom = clampf(_user_zoom * f, 0.55, 1.45)
	distance = frame_distance() * _user_zoom


func _apply() -> void:
	global_position = target + _pan
	rotation_degrees = Vector3(0, _yaw, 0)
	if camera == null:
		return
	var p := deg_to_rad(_pitch)
	camera.position = Vector3(0.0, sin(p) * _distance, cos(p) * _distance)
	camera.look_at(global_position, Vector3.UP if _pitch < 88.5 else Vector3(0, 0, -1).rotated(Vector3.UP, deg_to_rad(_yaw)))
	var vp := get_viewport()
	if vp:
		var size := vp.get_visible_rect().size
		var world_per_px := 2.0 * _distance * tan(deg_to_rad(camera.fov) * 0.5) / maxf(size.y, 1.0)
		camera.h_offset = (inset_right - inset_left) * 0.5 * world_per_px
		camera.v_offset = (inset_top - inset_bottom) * 0.5 * world_per_px
	if attributes:
		attributes.dof_blur_far_distance = _distance + 8.0
