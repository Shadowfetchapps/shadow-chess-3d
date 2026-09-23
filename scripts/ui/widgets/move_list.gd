class_name MoveList
extends PanelContainer

## Two-column scoresheet. Clicking a move reviews that position.

signal ply_selected(ply: int)

var _scroll: ScrollContainer
var _grid: GridContainer
var _empty: Label
var _buttons: Array[Button] = []
var _sans: PackedStringArray = PackedStringArray()
var _first_white := true
var _first_number := 1
var _current := -1


func _init() -> void:
	theme_type_variation = "Inset"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := UIKit.vbox(0)
	add_child(v)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 2)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)
	_empty = UIKit.label("No moves yet.", "Caption")
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_child(_empty)


func set_moves(sans: PackedStringArray, first_is_white: bool, first_number: int) -> void:
	var same_start := first_is_white == _first_white and first_number == _first_number
	var prefix_ok := same_start and sans.size() >= _sans.size()
	if prefix_ok:
		for i in _sans.size():
			if _sans[i] != sans[i]:
				prefix_ok = false
				break
	if not prefix_ok:
		_clear()
	_first_white = first_is_white
	_first_number = first_number
	for i in range(_buttons.size(), sans.size()):
		_append(i, sans[i])
	_sans = sans.duplicate()
	_empty.visible = sans.is_empty()
	_scroll.visible = not sans.is_empty()


func set_current(ply: int) -> void:
	_current = ply
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(i == ply - 1)
	if ply - 1 >= 0 and ply - 1 < _buttons.size():
		var b := _buttons[ply - 1]
		_scroll.call_deferred("ensure_control_visible", b)


func _clear() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_buttons.clear()
	_sans = PackedStringArray()


func _append(i: int, san: String) -> void:
	var offset := 0 if _first_white else 1
	var slot := i + offset
	if slot % 2 == 0 or i == 0:
		var num := UIKit.label("%d." % (_first_number + int(slot / 2.0)), "Faint")
		num.add_theme_font_override("font", ThemeFactory.font("tabular"))
		num.add_theme_font_size_override("font_size", 13)
		num.custom_minimum_size.x = 34
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_grid.add_child(num)
		if slot % 2 == 1:
			var pad := Control.new()
			pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_grid.add_child(pad)
	var b := Button.new()
	b.theme_type_variation = "MoveButton"
	b.text = san
	b.toggle_mode = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var ply := i + 1
	b.pressed.connect(func():
		AudioManager.play("ui_click")
		ply_selected.emit(ply)
		set_current(_current)
	)
	_grid.add_child(b)
	_buttons.append(b)
