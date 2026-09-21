class_name PieceView
extends Node3D

var square: int = -1
var piece_type: int = 0
var piece_color: int = 0
var _visual: Node3D
var _bob: Tween


func setup(type: int, color: int, sq: int) -> void:
	piece_type = type
	piece_color = color
	square = sq
	_visual = PieceMeshBuilder.build(type, color)
	add_child(_visual)
	if color == ChessTypes.BLACK:
		_visual.rotation.y = PI


func set_selected(on: bool) -> void:
	if _bob:
		_bob.kill()
		_bob = null
		if is_instance_valid(_visual):
			_visual.position.y = 0.0
	if not on or not is_instance_valid(_visual):
		return
	_bob = create_tween().set_loops()
	_bob.set_trans(Tween.TRANS_SINE)
	_bob.tween_property(_visual, "position:y", 0.055, 0.36)
	_bob.tween_property(_visual, "position:y", 0.0, 0.36)


func play_land() -> void:
	if _bob:
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector3(1.07, 0.90, 1.07), 0.045)
	tw.tween_property(self, "scale", Vector3.ONE, 0.10)


func pulse_check() -> void:
	if _bob:
		return
	if not is_instance_valid(_visual):
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_visual, "position:y", 0.10, 0.07)
	tw.tween_property(_visual, "position:y", 0.0, 0.14)
