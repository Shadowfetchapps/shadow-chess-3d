extends CanvasLayer

var controller: GameController
var _status: Label
var _clock_w: Label
var _clock_b: Label
var _history: RichTextLabel
var _cap_w: Label
var _cap_b: Label
var _pause: PanelContainer
var _end: PanelContainer
var _promo: PanelContainer
var _fen_box: LineEdit
var _thinking: Label


func _ready() -> void:
	layer = 10
	controller = get_parent().get_node("World") as GameController
	_build()
	controller.state_changed.connect(_refresh)
	controller.promotion_required.connect(_show_promo)
	controller.game_ended.connect(_show_end)
	_refresh()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = ThemeFactory.make()
	add_child(root)
	root.add_child(_top_bar())
	root.add_child(_side_panel())
	root.add_child(_bottom_bar())
	_thinking = Label.new()
	_thinking.text = "Shadow is thinking…"
	_thinking.visible = false
	_thinking.add_theme_color_override("font_color", ThemeFactory.accent())
	_thinking.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_thinking.offset_top = 72
	_thinking.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_thinking)
	_pause = _make_pause()
	root.add_child(_pause)
	_end = _make_end()
	root.add_child(_end)
	_promo = _make_promo()
	root.add_child(_promo)


func _top_bar() -> PanelContainer:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 16
	bar.offset_right = -16
	bar.offset_top = 12
	bar.offset_bottom = 64
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	var title := Label.new()
	title.text = "SHADOW CHESS"
	var df: FontFile = load("res://assets/fonts/InterDisplay-SemiBold.ttf")
	if df:
		title.add_theme_font_override("font", df)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", ThemeFactory.accent())
	row.add_child(title)
	var edition := Label.new()
	edition.text = "3D"
	edition.add_theme_font_size_override("font_size", 14)
	edition.add_theme_color_override("font_color", ThemeFactory.muted())
	row.add_child(edition)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_status)
	row.add_child(_btn("Undo", controller.undo))
	row.add_child(_btn("Redo", controller.redo))
	row.add_child(_btn("Flip", controller.flip_board))
	row.add_child(_btn("Pause", _toggle_pause))
	return bar


func _side_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -320
	panel.offset_right = -16
	panel.offset_top = 80
	panel.offset_bottom = -90
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(_heading("Clocks"))
	var clocks := HBoxContainer.new()
	_clock_w = _clock_label("W  10:00")
	_clock_b = _clock_label("B  10:00")
	clocks.add_child(_clock_w)
	clocks.add_child(_clock_b)
	v.add_child(clocks)
	v.add_child(_heading("Captured"))
	_cap_w = Label.new()
	_cap_b = Label.new()
	_cap_w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cap_b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_cap_w)
	v.add_child(_cap_b)
	v.add_child(_heading("Move history"))
	_history = RichTextLabel.new()
	_history.bbcode_enabled = true
	_history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history.scroll_following = true
	_history.fit_content = false
	v.add_child(_history)
	v.add_child(_heading("FEN"))
	_fen_box = LineEdit.new()
	_fen_box.editable = true
	v.add_child(_fen_box)
	var fen_row := HBoxContainer.new()
	fen_row.add_child(_btn("Copy FEN", func(): DisplayServer.clipboard_set(controller.export_fen())))
	fen_row.add_child(_btn("Load FEN", _load_fen))
	fen_row.add_child(_btn("PGN", func(): DisplayServer.clipboard_set(controller.export_pgn())))
	v.add_child(fen_row)
	return panel


func _bottom_bar() -> PanelContainer:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 16
	bar.offset_right = -336
	bar.offset_top = -78
	bar.offset_bottom = -16
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	row.add_child(_btn("Save", func(): _toast_save(controller.save_now())))
	row.add_child(_btn("Restart", controller.restart))
	row.add_child(_btn("Resign", controller.resign))
	row.add_child(_btn("Menu", _to_menu))
	var hint := Label.new()
	hint.text = "LMB select/move   RMB orbit   Wheel zoom   MMB pan   H reset   F flip   Ctrl+Z undo"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", ThemeFactory.muted())
	row.add_child(hint)
	return bar


func _make_pause() -> PanelContainer:
	var p := _modal("Paused")
	var v: VBoxContainer = p.get_node("V")
	v.add_child(_btn("Resume", _toggle_pause))
	v.add_child(_btn("Settings", _open_settings))
	v.add_child(_btn("Resign", func(): _toggle_pause(); controller.resign()))
	v.add_child(_btn("Main menu", _to_menu))
	p.visible = false
	return p


func _make_end() -> PanelContainer:
	var p := _modal("Game over")
	var v: VBoxContainer = p.get_node("V")
	var msg := Label.new()
	msg.name = "Msg"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(msg)
	v.add_child(_btn("New game", func(): p.visible = false; controller.restart()))
	v.add_child(_btn("Save", func(): controller.save_now()))
	v.add_child(_btn("Main menu", _to_menu))
	p.visible = false
	return p


func _make_promo() -> PanelContainer:
	var p := _modal("Promote to")
	var v: VBoxContainer = p.get_node("V")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_add_promo_button(row, p, "Queen", ChessTypes.QUEEN)
	_add_promo_button(row, p, "Rook", ChessTypes.ROOK)
	_add_promo_button(row, p, "Bishop", ChessTypes.BISHOP)
	_add_promo_button(row, p, "Knight", ChessTypes.KNIGHT)
	v.add_child(row)
	p.visible = false
	return p


func _modal(title: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = Vector2(360, 80)
	p.offset_left = -200
	p.offset_right = 200
	p.offset_top = -140
	p.offset_bottom = 140
	var v := VBoxContainer.new()
	v.name = "V"
	v.add_theme_constant_override("separation", 12)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var df: FontFile = load("res://assets/fonts/InterDisplay-SemiBold.ttf")
	if df:
		t.add_theme_font_override("font", df)
	t.add_theme_font_size_override("font_size", 22)
	v.add_child(t)
	p.add_child(v)
	return p


func _add_promo_button(row: HBoxContainer, dialog: PanelContainer, label: String, type: int) -> void:
	row.add_child(_btn(label, func():
		dialog.visible = false
		controller.complete_promotion(type)
	))


func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func():
		AudioManager.play("ui")
		cb.call()
	)
	return b


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", ThemeFactory.accent())
	return l


func _clock_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 22)
	return l


func _refresh() -> void:
	if controller == null:
		return
	var e := controller.engine
	_status.text = e.result_text() if e.game_over() else "%s to move%s" % [
		ChessTypes.side_name(e.side_to_move),
		"  ·  check" if e.in_check() else "",
	]
	_clock_w.text = "White  %s" % _fmt(controller.white_clock)
	_clock_b.text = "Black  %s" % _fmt(controller.black_clock)
	if not controller.clock_enabled:
		_clock_w.text = "White  ∞"
		_clock_b.text = "Black  ∞"
	_history.text = _history_bb(e)
	_cap_w.text = "White took  " + _captured(e, ChessTypes.BLACK)
	_cap_b.text = "Black took  " + _captured(e, ChessTypes.WHITE)
	_fen_box.text = e.to_fen()
	_thinking.visible = controller.is_thinking()
	controller.paused = _pause.visible
	var check := e.in_check() and not e.game_over()
	_status.add_theme_color_override("font_color", ThemeFactory.danger() if check else ThemeFactory.cream())
	var w_turn := e.side_to_move == ChessTypes.WHITE and not e.game_over()
	_clock_w.add_theme_color_override("font_color", ThemeFactory.accent() if w_turn else ThemeFactory.cream())
	_clock_b.add_theme_color_override("font_color", ThemeFactory.accent() if not w_turn else ThemeFactory.cream())


func _history_bb(e: ChessEngine) -> String:
	if e.history.is_empty():
		return "[color=#b3a88e]No moves yet[/color]"
	var parts: PackedStringArray = PackedStringArray()
	for i in e.history.size():
		if i % 2 == 0:
			parts.append("[color=#d6b45c]%d.[/color]" % (int(i / 2.0) + 1))
		parts.append(e.history[i].san)
	return " ".join(parts)


func _captured(e: ChessEngine, color: int) -> String:
	var start := {ChessTypes.PAWN: 8, ChessTypes.KNIGHT: 2, ChessTypes.BISHOP: 2, ChessTypes.ROOK: 2, ChessTypes.QUEEN: 1}
	var now := {ChessTypes.PAWN: 0, ChessTypes.KNIGHT: 0, ChessTypes.BISHOP: 0, ChessTypes.ROOK: 0, ChessTypes.QUEEN: 0}
	for sq in 64:
		var p := e.piece_at(sq)
		if p != 0 and ChessTypes.pcolor(p) == color:
			var t := ChessTypes.ptype(p)
			if now.has(t):
				now[t] += 1
	var glyphs := {ChessTypes.PAWN: "♟", ChessTypes.KNIGHT: "♞", ChessTypes.BISHOP: "♝", ChessTypes.ROOK: "♜", ChessTypes.QUEEN: "♛"}
	var s := ""
	for t in [ChessTypes.QUEEN, ChessTypes.ROOK, ChessTypes.BISHOP, ChessTypes.KNIGHT, ChessTypes.PAWN]:
		var n: int = int(start[t]) - int(now[t])
		for i in n:
			s += glyphs[t]
	return s if s != "" else "—"


func _fmt(t: float) -> String:
	var s := int(ceil(t))
	return "%d:%02d" % [int(s / 60.0), s % 60]


func _toggle_pause() -> void:
	_pause.visible = not _pause.visible
	controller.paused = _pause.visible
	_end.visible = false


func _show_promo(_f: int, _t: int) -> void:
	_promo.visible = true


func _show_end(text: String) -> void:
	_end.visible = true
	var msg := _end.get_node("V/Msg") as Label
	if msg:
		msg.text = text


func _load_fen() -> void:
	if controller.engine.from_fen(_fen_box.text.strip_edges()):
		controller.last_from = -1
		controller.last_to = -1
		controller.rebuild_pieces()
		controller._deselect()
		controller.state_changed.emit()


func _toast_save(path: String) -> void:
	_status.text = "Saved  " + path.get_file() if path != "" else "Save failed"


func _open_settings() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/settings_menu.tscn")


func _to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game"):
		_toggle_pause()
