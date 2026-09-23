extends CanvasLayer

## In-game HUD: brand and status, player cards with clocks and captures,
## scoresheet with review controls, actions, evaluation bar, puzzle panel,
## and the overlays (pause, settings, help, promotion, result).

const PANEL_W := 372
const MARGIN := 16

var controller: GameController
var root: Control
var _icons: PieceIcons
var _toasts: ToastLayer

var _mode_label: Label
var _pill: PanelContainer
var _pill_icon: TextureRect
var _pill_label: Label
var _pill_dots := 0.0
var _card_top: PlayerCard
var _card_bottom: PlayerCard
var _moves: MoveList
var _nav: Array[Button] = []
var _live_btn: Button
var _move_entry: LineEdit
var _pv: Label
var _eval_bar: EvalBar
var _eval_caption: Label
var _hint_label: Label
var _act_undo: Button
var _act_redo: Button
var _act_hint: Button
var _act_draw: Button
var _act_resign: Button
var _puzzle_box: VBoxContainer
var _puzzle_title: Label
var _puzzle_goal: Label
var _puzzle_meta: Label
var _puzzle_feedback: Label
var _puzzle_next: Button
var _standard_box: VBoxContainer

var _pause: Modal
var _help: HelpOverlay
var _promo: PromotionPicker
var _end: EndCard
var _paste: Modal
var _paste_edit: TextEdit
var _file_dialog: FileDialog


func _ready() -> void:
	layer = 10
	controller = get_parent().get_node("World") as GameController
	_build()
	controller.state_changed.connect(_refresh)
	controller.promotion_requested.connect(func(_f, _t, color): _promo.present(color))
	controller.game_finished.connect(_on_game_finished)
	controller.thinking_changed.connect(func(_on): _refresh())
	controller.eval_updated.connect(_on_eval)
	controller.hint_shown.connect(func(t): _toasts.show_toast(t, "hint", 3.2))
	controller.view_changed.connect(func(_p, _l): _refresh())
	controller.toast.connect(func(t, k): _toasts.show_toast(t, k))
	controller.puzzle_event.connect(_on_puzzle_event)
	controller.clock_low.connect(func(side):
		if controller._is_human(side):
			_toasts.show_toast("Ten seconds left", "error", 1.6)
	)
	controller.move_played.connect(func(_m): _fade_hint())
	get_viewport().size_changed.connect(_update_insets)
	_update_insets()
	_icons.render()
	_refresh()


func _build() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = ThemeFactory.make()
	add_child(root)
	_icons = PieceIcons.new()
	_icons.icons_ready.connect(_refresh)
	add_child(_icons)

	# Brand, top left.
	var brand := UIKit.vbox(2)
	brand.position = Vector2(28, 20)
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := UIKit.label("SHADOW CHESS", "Kicker")
	title.add_theme_font_size_override("font_size", 14)
	brand.add_child(title)
	_mode_label = UIKit.label("", "Caption")
	brand.add_child(_mode_label)
	root.add_child(brand)

	# Status pill, top centre of the free area.
	_pill = PanelContainer.new()
	_pill.theme_type_variation = "Pill"
	_pill.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pill.offset_top = 18
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pr := UIKit.hbox(10)
	_pill_icon = UIKit.icon_rect("clock", 16)
	pr.add_child(_pill_icon)
	_pill_label = UIKit.label("", "Subheader")
	pr.add_child(_pill_label)
	_pill.add_child(pr)
	root.add_child(_pill)

	# Evaluation bar, left edge.
	var eval_wrap := UIKit.vbox(6)
	eval_wrap.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	eval_wrap.offset_left = 24
	eval_wrap.offset_right = 24 + 28
	eval_wrap.offset_top = 150
	eval_wrap.offset_bottom = -150
	eval_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eval_bar = EvalBar.new()
	_eval_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	eval_wrap.add_child(_eval_bar)
	_eval_caption = UIKit.label("", "Faint")
	_eval_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eval_wrap.add_child(_eval_caption)
	eval_wrap.name = "EvalWrap"
	root.add_child(eval_wrap)

	# Controls hint, bottom left; fades after the first move.
	_hint_label = UIKit.label("Click or drag to move  ·  Right-drag to orbit  ·  Wheel to zoom  ·  F1 help", "Faint")
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint_label.offset_left = 28
	_hint_label.offset_top = -40
	_hint_label.offset_bottom = -20
	_hint_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_hint_label)

	root.add_child(_side_panel())

	_toasts = ToastLayer.new()
	root.add_child(_toasts)
	_pause = _make_pause()
	root.add_child(_pause)
	_help = HelpOverlay.new()
	root.add_child(_help)
	_promo = PromotionPicker.new()
	_promo.chosen.connect(func(t): controller.complete_promotion(t))
	_promo.cancelled.connect(func(): controller.cancel_promotion())
	root.add_child(_promo)
	_end = EndCard.new()
	_end.rematch_requested.connect(func(swap): controller.restart(swap))
	_end.review_requested.connect(func(): controller.set_view_ply(0))
	_end.export_requested.connect(_export_pgn_file)
	_end.menu_requested.connect(_to_menu)
	root.add_child(_end)
	_paste = _make_paste()
	root.add_child(_paste)


func _side_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -(PANEL_W + MARGIN)
	panel.offset_right = -MARGIN
	panel.offset_top = MARGIN
	panel.offset_bottom = -MARGIN
	var v := UIKit.vbox(12)
	panel.add_child(v)

	var head := UIKit.hbox(6)
	var head_title := UIKit.label(GameSession.mode_label().to_upper(), "Kicker")
	head_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_title.clip_text = true
	head.add_child(head_title)
	head.add_child(UIKit.icon_button("help", "Controls and rules (F1)", func(): _help.open(), 17))
	head.add_child(UIKit.icon_button("settings", "Settings", _open_settings, 17))
	head.add_child(UIKit.icon_button("menu", "Game menu (Esc)", _toggle_pause, 17))
	v.add_child(head)

	_standard_box = UIKit.vbox(12)
	_card_top = PlayerCard.new()
	_standard_box.add_child(_card_top)
	v.add_child(_standard_box)

	_puzzle_box = UIKit.vbox(6)
	var pc := PanelContainer.new()
	pc.theme_type_variation = "CardActive"
	var pv := UIKit.vbox(6)
	pc.add_child(pv)
	_puzzle_title = UIKit.label("", "Header")
	_puzzle_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.add_child(_puzzle_title)
	_puzzle_goal = UIKit.label("", "Gold")
	pv.add_child(_puzzle_goal)
	_puzzle_meta = UIKit.label("", "Caption")
	pv.add_child(_puzzle_meta)
	_puzzle_feedback = UIKit.label("Find the forced mate.", "Muted", true)
	pv.add_child(_puzzle_feedback)
	_puzzle_box.add_child(pc)
	v.add_child(_puzzle_box)

	_moves = MoveList.new()
	_moves.ply_selected.connect(func(p): controller.set_view_ply(p))
	v.add_child(_moves)

	var nav := UIKit.hbox(6)
	for spec in [["first", "First position (Home)", func(): controller.set_view_ply(0)],
			["chevron_left", "Previous move (←)", func(): controller.step_view(-1)],
			["chevron_right", "Next move (→)", func(): controller.step_view(1)],
			["last", "Latest position (End)", func(): controller.set_view_ply(controller.engine.history.size())]]:
		var b := UIKit.icon_button(spec[0], spec[1], spec[2], 16)
		nav.add_child(b)
		_nav.append(b)
	nav.add_child(UIKit.spacer())
	_live_btn = UIKit.button("Back to game", func(): controller.set_view_ply(controller.engine.history.size()), "GhostButton", "arrow_right")
	nav.add_child(_live_btn)
	v.add_child(nav)

	_move_entry = LineEdit.new()
	_move_entry.placeholder_text = "Type a move — Nf3, O-O, e2e4…"
	_move_entry.clear_button_enabled = true
	_move_entry.tooltip_text = "Enter a move in algebraic (SAN) or coordinate (UCI) notation and press Enter."
	_move_entry.text_submitted.connect(func(t: String):
		if controller.play_text(t):
			_move_entry.clear()
		_move_entry.release_focus()
	)
	v.add_child(_move_entry)

	_pv = UIKit.label("", "Caption", true)
	_pv.visible = false
	v.add_child(_pv)

	_card_bottom = PlayerCard.new()
	v.add_child(_card_bottom)

	var actions := UIKit.hbox(6)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_act_undo = UIKit.icon_button("undo", "Take back (Ctrl+Z)", func(): controller.undo())
	_act_redo = UIKit.icon_button("redo", "Replay (Ctrl+Y)", func(): controller.redo())
	_act_hint = UIKit.icon_button("hint", "Hint (H)", func(): controller.request_hint())
	var flip := UIKit.icon_button("flip", "Flip board (F)", func(): controller.flip_board())
	var top := UIKit.icon_button("grid", "Top-down view (T)", func(): controller.camera_rig.toggle_top_view())
	_act_draw = UIKit.icon_button("draw", "Offer a draw", _offer_draw)
	_act_resign = UIKit.icon_button("flag", "Resign", _resign)
	for b in [_act_undo, _act_redo, _act_hint, flip, top, _act_draw, _act_resign]:
		actions.add_child(b)
	var puzzle_actions := UIKit.hbox(8)
	puzzle_actions.add_child(UIKit.button("Retry", func(): controller.restart_puzzle(), "", "restart"))
	_puzzle_next = UIKit.button("Next puzzle", _next_puzzle, "PrimaryButton", "arrow_right")
	puzzle_actions.add_child(_puzzle_next)
	puzzle_actions.name = "PuzzleActions"
	var all_btn := UIKit.icon_button("target", "All puzzles", func(): _to_menu("puzzles"))
	puzzle_actions.add_child(all_btn)
	v.add_child(actions)
	v.add_child(puzzle_actions)

	var puzzle := GameSession.mode == GameSession.Mode.PUZZLE
	_puzzle_box.visible = puzzle
	puzzle_actions.visible = puzzle
	_standard_box.visible = not puzzle
	_card_bottom.visible = not puzzle
	for b in [_act_undo, _act_redo, _act_draw, _act_resign, top]:
		b.visible = not puzzle
	if GameSession.mode == GameSession.Mode.ANALYSIS:
		_act_draw.visible = false
		_act_resign.visible = false
	return panel


func _make_pause() -> Modal:
	var m := Modal.new("Paused", 420)
	var items := [
		["Resume", _toggle_pause, "PrimaryButton", "play"],
		["Save game", func(): controller.save_now(), "", "save"],
		["Save PGN file…", _export_pgn_file, "", "download"],
		["Copy PGN", func(): DisplayServer.clipboard_set(controller.export_pgn()); _toasts.show_toast("PGN copied", "success"), "", "copy"],
		["Copy FEN", func(): DisplayServer.clipboard_set(controller.export_fen()); _toasts.show_toast("FEN copied", "success"), "", "copy"],
	]
	if GameSession.mode in [GameSession.Mode.ANALYSIS, GameSession.Mode.LOCAL]:
		items.append(["Load FEN or PGN…", func(): _pause.close(); _paste.open(), "", "upload"])
	items.append(["Settings", func(): _open_settings(), "", "settings"])
	items.append(["Controls and rules", func(): _help.open(), "", "help"])
	items.append(["Main menu", func(): _to_menu(), "GhostButton", "menu"])
	items.append(["Quit to desktop", func(): get_tree().quit(), "GhostButton", "close"])
	for it in items:
		var b := UIKit.button(it[0], it[1], it[2], it[3])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 42
		m.body.add_child(b)
	m.closed.connect(func(): controller.set_paused(false); AudioManager.duck_music(false))
	return m


func _make_paste() -> Modal:
	var m := Modal.new("Load a position", 560)
	m.set_subtitle("Paste a FEN string or a full PGN game.")
	_paste_edit = TextEdit.new()
	_paste_edit.custom_minimum_size = Vector2(0, 200)
	_paste_edit.placeholder_text = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
	_paste_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	m.body.add_child(_paste_edit)
	m.add_footer_button(UIKit.button("Paste from clipboard", func(): _paste_edit.text = DisplayServer.clipboard_get(), "GhostButton", "copy"))
	m.add_footer_button(UIKit.button("Load", func():
		var text := _paste_edit.text.strip_edges()
		var ok := controller.load_pgn(text) if (text.contains("[") or text.contains("1.")) else controller.load_fen(text)
		if ok:
			m.close()
			_toasts.show_toast("Position loaded", "success")
	, "PrimaryButton", "upload"))
	return m


# --- Refresh ----------------------------------------------------------------------

func _process(delta: float) -> void:
	if controller == null:
		return
	var bottom := controller.bottom_side()
	var top := ChessTypes.opp(bottom)
	_card_top.set_clock(controller.clocks[top], controller.clock_enabled)
	_card_bottom.set_clock(controller.clocks[bottom], controller.clock_enabled)
	if controller.is_thinking() or controller.is_puzzle_busy():
		_pill_dots += delta * 2.5
		_pill_label.text = controller.status_text() + ".".repeat(int(_pill_dots) % 4)


func _refresh() -> void:
	if controller == null or _card_top == null:
		return
	var pos := controller.view_position()
	var bottom := controller.bottom_side()
	var top := ChessTypes.opp(bottom)
	_mode_label.text = "%s  ·  %s" % [GameSession.mode_label(), GameSession.time_control_label()]
	_setup_card(_card_top, top, pos)
	_setup_card(_card_bottom, bottom, pos)

	var status := controller.status_text()
	_pill_label.text = status
	var col := ThemeFactory.CREAM
	var icon := "clock"
	if controller.engine.game_over() and controller.is_live():
		col = ThemeFactory.GOLD_BRIGHT
		icon = "trophy"
	elif not controller.is_live():
		col = ThemeFactory.INFO
		icon = "eye"
	elif controller.in_check_now():
		col = ThemeFactory.DANGER
		icon = "info"
	elif controller.is_thinking():
		icon = "moon"
		col = ThemeFactory.GOLD
	_pill_label.add_theme_color_override("font_color", col)
	_pill_icon.texture = IconLibrary.get_icon(icon, 16, col)

	var e := controller.engine
	var sans := e.san_history()
	var first_white := ChessTypes.WHITE == _start_side(e)
	_moves.set_moves(sans, first_white, _start_number(e))
	_moves.set_current(controller.view_ply)
	var live := controller.is_live()
	_nav[0].disabled = controller.view_ply == 0
	_nav[1].disabled = controller.view_ply == 0
	_nav[2].disabled = live
	_nav[3].disabled = live
	_live_btn.visible = not live

	_act_undo.disabled = not controller.can_undo()
	_act_redo.disabled = not controller.can_redo()
	_act_hint.disabled = not controller.can_interact()
	_act_draw.disabled = e.game_over() or e.history.size() < 2
	_act_resign.disabled = e.game_over() or e.history.size() < 1

	var wants_eval := controller.eval_wanted()
	var eval_wrap := root.get_node("EvalWrap") as Control
	if eval_wrap.visible != wants_eval:
		eval_wrap.visible = wants_eval
		_update_insets()
	_eval_bar.white_bottom = bottom == ChessTypes.WHITE
	_eval_bar.queue_redraw()
	_pv.visible = wants_eval and str(controller.last_eval.get("pv", "")) != "" and GameSession.mode != GameSession.Mode.PUZZLE

	if GameSession.mode == GameSession.Mode.PUZZLE:
		var info := controller.puzzle_info()
		_puzzle_title.text = info["title"]
		_puzzle_goal.text = "%s to move — mate in %d" % [ChessTypes.side_name(ChessTypes.opp(GameSession.ai_side)), info["depth"]]
		var stars := "★".repeat(int(info["difficulty"])) + "☆".repeat(maxi(0, 5 - int(info["difficulty"])))
		_puzzle_meta.text = "%s  ·  %s  ·  solved %d" % [str(info["theme"]).capitalize(), stars, ProfileStore.puzzles_solved.size()]
		_puzzle_next.disabled = false


func _setup_card(card: PlayerCard, side: int, pos: ChessEngine) -> void:
	var ai := controller.is_ai_side(side)
	var sub := ChessTypes.side_name(side)
	if ai:
		sub = "%s  ·  %s" % [_level_name(GameSession.ai_level), _level_elo(GameSession.ai_level)]
	elif GameSession.mode == GameSession.Mode.AI:
		sub = "%s  ·  rating %s" % [ChessTypes.side_name(side), ProfileStore.rating_label()]
	card.setup(side, controller.side_name(side), sub, ai)
	var live_turn := not controller.engine.game_over() and pos.side_to_move == side
	card.set_active(live_turn)
	card.set_thinking(ai and controller.is_thinking())
	var diff := pos.material_diff()
	card.set_captured(pos.captured_by(side), diff if side == ChessTypes.WHITE else -diff)


func _on_eval(white_cp: int, mate_white: int, depth: int, pv: String) -> void:
	_eval_bar.set_eval(white_cp, mate_white)
	_eval_caption.text = "d%d" % depth if depth > 0 else ""
	_pv.text = "Shadow's line:  " + pv if pv != "" else ""
	_pv.visible = pv != "" and controller.eval_wanted()


func _on_game_finished(info: Dictionary) -> void:
	if GameSession.mode == GameSession.Mode.PUZZLE:
		return
	await get_tree().create_timer(1.1).timeout
	if is_instance_valid(_end) and controller.engine.game_over():
		_end.present(info, GameSession.mode == GameSession.Mode.AI)


func _on_puzzle_event(kind: String, text: String) -> void:
	_puzzle_feedback.text = text
	var c := ThemeFactory.MUTED
	match kind:
		"solved":
			c = ThemeFactory.SUCCESS
			_toasts.show_toast(text, "success", 3.0)
		"wrong":
			c = ThemeFactory.DANGER
		"correct":
			c = ThemeFactory.GOLD
	_puzzle_feedback.add_theme_color_override("font_color", c)
	_refresh()


func _update_insets() -> void:
	var left := 72.0 if root.get_node("EvalWrap").visible else 20.0
	controller.camera_rig.set_insets(left, PANEL_W + MARGIN * 2, 56.0, 12.0)
	# Centre the status pill over the free area rather than the whole window.
	_pill.offset_left = -(PANEL_W + MARGIN * 2) * 0.5 + (left - 20.0) * 0.5
	_pill.offset_right = _pill.offset_left


func _fade_hint() -> void:
	if _hint_label.modulate.a < 0.99:
		return
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(_hint_label, "modulate:a", 0.0, 1.2)


# --- Actions --------------------------------------------------------------------------

func _toggle_pause() -> void:
	if _pause.visible:
		_pause.close()
	else:
		controller.set_paused(true)
		AudioManager.duck_music(true)
		_pause.open()


func _open_settings() -> void:
	var s := SettingsPanel.new()
	root.add_child(s)
	s.closed.connect(s.queue_free)
	s.open()


func _offer_draw() -> void:
	var text := "Offer Shadow a draw? Shadow accepts only when it sees no winning chances." if GameSession.mode == GameSession.Mode.AI else "Agree to a draw and end the game?"
	var d := ConfirmDialog.new("Offer a draw", text, "Offer draw", func(): controller.offer_draw())
	root.add_child(d)
	d.open()


func _resign() -> void:
	var d := ConfirmDialog.new("Resign", "Resign this game? It counts as a loss.", "Resign", func(): controller.resign(), true)
	root.add_child(d)
	d.open()


func _next_puzzle() -> void:
	var all := ChessPuzzles.load_all()
	if all.is_empty():
		return
	var idx := (GameSession.puzzle_index + 1) % all.size()
	for i in all.size():
		var cand := (GameSession.puzzle_index + 1 + i) % all.size()
		if not ProfileStore.is_puzzle_solved(str(all[cand].get("id", ""))):
			idx = cand
			break
	GameSession.configure_puzzle(all[idx], idx)
	get_tree().reload_current_scene()


func _export_pgn_file() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.use_native_dialog = true
		_file_dialog.filters = PackedStringArray(["*.pgn ; PGN chess game"])
		_file_dialog.title = "Save PGN"
		_file_dialog.file_selected.connect(func(path: String):
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f:
				f.store_string(controller.export_pgn())
				f.close()
				_toasts.show_toast("Saved %s" % path.get_file(), "success")
			else:
				_toasts.show_toast("Could not write %s" % path, "error")
		)
		add_child(_file_dialog)
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	_file_dialog.current_dir = docs if docs != "" else OS.get_environment("HOME")
	_file_dialog.current_file = "shadow-chess-%s.pgn" % Time.get_date_string_from_system()
	_file_dialog.popup_centered_ratio(0.6)


func _to_menu(screen: String = "") -> void:
	GameSession.set_meta("menu_screen", screen)
	get_tree().change_scene_to_file("res://scenes/menus/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("show_help"):
		_help.open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_fullscreen"):
		SettingsStore.window_mode = "windowed" if SettingsStore.window_mode != "windowed" else "borderless"
		SettingsStore.apply_display()
		SettingsStore.save_settings()
		get_viewport().set_input_as_handled()


# --- Helpers ----------------------------------------------------------------------------

func _start_side(e: ChessEngine) -> int:
	var parts := e.start_fen.split(" ")
	return ChessTypes.BLACK if parts.size() > 1 and parts[1] == "b" else ChessTypes.WHITE


func _start_number(e: ChessEngine) -> int:
	var parts := e.start_fen.split(" ")
	return maxi(int(parts[5]), 1) if parts.size() > 5 else 1


func _level_name(id: String) -> String:
	for l in ChessAI.levels():
		if str(l.get("id")) == id:
			return str(l.get("name"))
	return id.capitalize()


func _level_elo(id: String) -> String:
	for l in ChessAI.levels():
		if str(l.get("id")) == id:
			return str(l.get("elo", ""))
	return ""
