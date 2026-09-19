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
		_visual.position.y = 0.0
	if not on:
		return
	_bob = create_tween().set_loops()
	_bob.set_trans(Tween.TRANS_SINE)
	_bob.tween_property(_visual, "position:y", 0.06, 0.45)
	_bob.tween_property(_visual, "position:y", 0.0, 0.45)
