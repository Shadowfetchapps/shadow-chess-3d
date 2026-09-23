class_name PromotionPicker
extends Modal

## Promotion choice with rendered piece icons. Keys Q, R, B, N pick directly.

signal chosen(type: int)
signal cancelled

var _color := ChessTypes.WHITE
var _row: HBoxContainer
var _picked := false


func _init() -> void:
	super("Promote pawn", 520)
	set_subtitle("Choose the new piece.  Q  R  B  N")
	_row = UIKit.hbox(12)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(_row)
	closed.connect(func():
		if not _picked:
			cancelled.emit()
	)


func present(color: int) -> void:
	_color = color
	_picked = false
	for c in _row.get_children():
		c.queue_free()
	for t in [ChessTypes.QUEEN, ChessTypes.ROOK, ChessTypes.BISHOP, ChessTypes.KNIGHT]:
		_row.add_child(_choice(t))
	open()


func _choice(type: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(104, 128)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var v := UIKit.vbox(4)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := PieceIcons.get_icon(type, _color)
	if tex:
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.custom_minimum_size = Vector2(84, 84)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(r)
	var l := UIKit.label(ChessTypes.piece_name(type), "Caption")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	b.add_child(v)
	b.mouse_entered.connect(func(): AudioManager.play("ui_hover"))
	b.pressed.connect(func(): _pick(type))
	return b


func _pick(type: int) -> void:
	_picked = true
	AudioManager.play("ui_click")
	close()
	chosen.emit(type)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not (event as InputEventKey).pressed:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_Q:
			_pick(ChessTypes.QUEEN)
		KEY_R:
			_pick(ChessTypes.ROOK)
		KEY_B:
			_pick(ChessTypes.BISHOP)
		KEY_N:
			_pick(ChessTypes.KNIGHT)
		_:
			return
	get_viewport().set_input_as_handled()
