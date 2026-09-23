class_name NewGameDialog
extends Modal

## Set up a game: opponent, colour, Shadow's strength, time control, and an
## optional custom starting position. Remembers the last choices.

var _mode := "ai"
var _color := "white"
var _level := "club"
var _clock := "10+0"
var _start := "standard"
var _ai_section: VBoxContainer
var _fen_edit: LineEdit
var _fen_error: Label
var _level_buttons: Array[Button] = []


func _init() -> void:
	super("New game", 760, true, 560)
	var last := SettingsStore.last_new_game
	_mode = str(last.get("mode", "ai"))
	_color = str(last.get("color", "white"))
	_level = str(last.get("level", SettingsStore.ai_level))
	_clock = str(last.get("clock", SettingsStore.clock_preset))

	body.add_child(UIKit.label("OPPONENT", "Kicker"))
	body.add_child(UIKit.chips([["Play Shadow", "ai"], ["Two players, one board", "local"]], _mode, func(v):
		_mode = v
		_ai_section.visible = v == "ai"
	, 180))

	_ai_section = UIKit.vbox(10)
	_ai_section.add_child(UIKit.gap(2))
	_ai_section.add_child(UIKit.label("YOUR PIECES", "Kicker"))
	_ai_section.add_child(UIKit.chips([["White", "white"], ["Black", "black"], ["Random", "random"]], _color, func(v): _color = v, 110))
	_ai_section.add_child(UIKit.gap(2))
	_ai_section.add_child(UIKit.label("SHADOW'S STRENGTH", "Kicker"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var group := ButtonGroup.new()
	var record: Dictionary = ProfileStore.levels
	for l in ChessAI.levels():
		var id := str(l.get("id"))
		var b := Button.new()
		b.theme_type_variation = "ChipButton"
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = id == _level
		b.custom_minimum_size = Vector2(228, 82)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var v := UIKit.vbox(2)
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 14
		v.offset_top = 10
		v.offset_right = -10
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var head := UIKit.hbox(8)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(UIKit.label(str(l.get("name")), "Subheader"))
		var elo := UIKit.label(str(l.get("elo", "")), "Gold")
		elo.add_theme_font_size_override("font_size", 13)
		head.add_child(elo)
		v.add_child(head)
		var blurb := UIKit.label(str(l.get("blurb", "")), "Caption", true)
		blurb.add_theme_font_size_override("font_size", 12)
		v.add_child(blurb)
		var rec: Dictionary = record.get(id, {})
		if not rec.is_empty():
			var r := UIKit.label("W %d  D %d  L %d" % [int(rec.get("w", 0)), int(rec.get("d", 0)), int(rec.get("l", 0))], "Faint")
			v.add_child(r)
		for c in v.get_children():
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		b.mouse_entered.connect(func(): AudioManager.play("ui_hover"))
		b.toggled.connect(func(on: bool):
			if on:
				AudioManager.play("ui_click")
				_level = id
		)
		grid.add_child(b)
		_level_buttons.append(b)
	_ai_section.add_child(grid)
	_ai_section.visible = _mode == "ai"
	body.add_child(_ai_section)

	body.add_child(UIKit.gap(2))
	body.add_child(UIKit.label("TIME CONTROL", "Kicker"))
	body.add_child(UIKit.chips([["No clock", "none"], ["1 + 0", "1+0", "Bullet"], ["3 + 2", "3+2", "Blitz"], ["5 + 0", "5+0", "Blitz"], ["10 + 0", "10+0", "Rapid"], ["15 + 10", "15+10", "Rapid"], ["30 + 0", "30+0", "Classical"]], _clock, func(v): _clock = v, 84))

	body.add_child(UIKit.gap(2))
	body.add_child(UIKit.label("STARTING POSITION", "Kicker"))
	body.add_child(UIKit.chips([["Standard", "standard"], ["From FEN", "fen"]], _start, func(v):
		_start = v
		_fen_edit.visible = v == "fen"
		_fen_error.visible = false
	, 110))
	_fen_edit = LineEdit.new()
	_fen_edit.placeholder_text = "Paste a FEN, e.g. r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3"
	_fen_edit.visible = false
	body.add_child(_fen_edit)
	_fen_error = UIKit.label("", "Caption", true)
	_fen_error.add_theme_color_override("font_color", ThemeFactory.DANGER)
	_fen_error.visible = false
	body.add_child(_fen_error)

	add_footer_button(UIKit.button("Cancel", close, "GhostButton"))
	add_footer_button(UIKit.button("Start game", _start_game, "PrimaryButton", "play"))


func _start_game() -> void:
	var fen := ""
	if _start == "fen":
		fen = _fen_edit.text.strip_edges()
		var probe := ChessEngine.new()
		var err := probe.validate_fen(fen)
		if err != "":
			_fen_error.text = err
			_fen_error.visible = true
			AudioManager.play("illegal")
			return
	SettingsStore.last_new_game = {"mode": _mode, "color": _color, "level": _level, "clock": _clock}
	SettingsStore.ai_level = _level if _mode == "ai" else SettingsStore.ai_level
	SettingsStore.clock_preset = _clock
	SettingsStore.save_settings()
	if _mode == "ai":
		var white := _color == "white" or (_color == "random" and randi() % 2 == 0)
		GameSession.configure_ai(white, _level, _clock)
	else:
		GameSession.configure_local(_clock != "none", _clock)
	GameSession.pending_fen = fen
	SaveManager.clear_autosave()
	get_tree().change_scene_to_file("res://scenes/main/game.tscn")
