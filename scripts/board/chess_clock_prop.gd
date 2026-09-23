class_name ChessClockProp
extends Node3D

## Decorative tournament clock on the table. The controller feeds it live
## times; the button on the running side is pressed down.

var _left: Label3D
var _right: Label3D
var _btn_left: MeshInstance3D
var _btn_right: MeshInstance3D
var _lamp_left: MeshInstance3D
var _lamp_right: MeshInstance3D
var _lamp_on: StandardMaterial3D
var _lamp_off: StandardMaterial3D


func _ready() -> void:
	MaterialLibrary.ensure()
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.7, 0.62, 0.62)
	body.mesh = bm
	body.position.y = 0.31
	body.rotation_degrees.x = -8.0
	body.material_override = MaterialLibrary.table_wood
	add_child(body)
	var face := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(1.5, 0.38, 0.02)
	face.mesh = fm
	face.material_override = MaterialLibrary.clock_face
	face.position = Vector3(0, 0.02, 0.31)
	body.add_child(face)
	var divider := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.02, 0.4, 0.03)
	divider.mesh = dm
	divider.material_override = MaterialLibrary.brass_mat
	divider.position = Vector3(0, 0.02, 0.315)
	body.add_child(divider)
	_left = _digits(body, Vector3(-0.37, 0.03, 0.325))
	_right = _digits(body, Vector3(0.37, 0.03, 0.325))
	_btn_left = _button(body, -0.45)
	_btn_right = _button(body, 0.45)
	_lamp_on = StandardMaterial3D.new()
	_lamp_on.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp_on.albedo_color = Color(1.0, 0.45, 0.2)
	_lamp_on.emission_enabled = true
	_lamp_on.emission = Color(1.0, 0.45, 0.2)
	_lamp_on.emission_energy_multiplier = 3.0
	_lamp_off = StandardMaterial3D.new()
	_lamp_off.albedo_color = Color(0.12, 0.05, 0.03)
	_lamp_left = _lamp(body, -0.72)
	_lamp_right = _lamp(body, 0.72)
	set_times(600.0, 600.0, -1, false)


## left = White's time, right = Black's time. running: 0 white, 1 black, -1 none.
func set_times(white_s: float, black_s: float, running: int, enabled: bool) -> void:
	if _left == null:
		return
	_left.text = _fmt(white_s) if enabled else "– –"
	_right.text = _fmt(black_s) if enabled else "– –"
	_btn_left.position.y = 0.325 if running == ChessTypes.WHITE else 0.35
	_btn_right.position.y = 0.325 if running == ChessTypes.BLACK else 0.35
	_lamp_left.material_override = _lamp_on if running == ChessTypes.WHITE and enabled else _lamp_off
	_lamp_right.material_override = _lamp_on if running == ChessTypes.BLACK and enabled else _lamp_off


func _fmt(t: float) -> String:
	var s := int(ceil(maxf(t, 0.0)))
	if s >= 3600:
		return "%d:%02d:%02d" % [int(s / 3600.0), int(s / 60.0) % 60, s % 60]
	return "%d:%02d" % [int(s / 60.0), s % 60]


func _digits(parent: Node3D, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.font = ThemeFactory.font("clock")
	l.font_size = 96
	l.pixel_size = 0.0022
	l.modulate = Color(1.0, 0.72, 0.36)
	l.outline_size = 0
	l.shaded = false
	l.position = pos
	l.text = "10:00"
	parent.add_child(l)
	return l


func _button(parent: Node3D, x: float) -> MeshInstance3D:
	var b := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.1
	cm.bottom_radius = 0.12
	cm.height = 0.09
	cm.radial_segments = 24
	b.mesh = cm
	b.material_override = MaterialLibrary.brass_mat
	b.position = Vector3(x, 0.35, 0.0)
	parent.add_child(b)
	return b


func _lamp(parent: Node3D, x: float) -> MeshInstance3D:
	var l := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.025
	sm.height = 0.05
	l.mesh = sm
	l.position = Vector3(x, 0.17, 0.32)
	parent.add_child(l)
	return l
