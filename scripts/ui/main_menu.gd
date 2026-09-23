extends Node

## Title screen: the living salon backdrop with the menu column on the left.

const COLUMN_W := 440.0

var backdrop: MenuBackdrop
var ui: Control
var _column: VBoxContainer
var _new_game: NewGameDialog
var _load: LoadDialog
var _puzzles: PuzzleBrowser


func _ready() -> void:
	SettingsStore.apply_display()
	backdrop = MenuBackdrop.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.theme = ThemeFactory.make()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	_build()
	backdrop.set_insets(COLUMN_W + 120.0, 0.0)
	AudioManager.play_music(3.0)
	var screen := ""
	if GameSession.has_meta("menu_screen"):
		screen = str(GameSession.get_meta("menu_screen"))
		GameSession.remove_meta("menu_screen")
	if screen == "puzzles":
		_puzzles.open()
	if OS.get_cmdline_user_args().has("--visual-qa"):
		var qa_script := load("res://tools/visual_qa_runner.gd")
		if qa_script:
			var qa: Node = qa_script.new()
			qa.name = "VisualQA"
			get_tree().root.add_child.call_deferred(qa)


func _build() -> void:
	var shade := TextureRect.new()
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = COLUMN_W + 360.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(0.02, 0.017, 0.013, 0.96), Color(0.02, 0.017, 0.013, 0.82), Color(0.02, 0.017, 0.013, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(shade)

	_column = UIKit.vbox(6)
	_column.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_column.offset_left = 76
	_column.offset_right = 76 + COLUMN_W
	_column.offset_top = 76
	_column.offset_bottom = -44
	ui.add_child(_column)

	_column.add_child(UIKit.label("SHADOWFETCH  ·  PRIVATE SALON", "Kicker"))
	var title := UIKit.label("Shadow Chess", "HeaderXL")
	_column.add_child(title)
	var rule := ColorRect.new()
	rule.color = ThemeFactory.GOLD
	rule.custom_minimum_size = Vector2(72, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_column.add_child(rule)
	_column.add_child(UIKit.gap(4))
	_column.add_child(UIKit.label("A dark salon. Clear rules. Gold on black.", "Muted"))
	var profile := UIKit.hbox(8)
	profile.add_child(UIKit.icon_rect("user", 14, ThemeFactory.GOLD))
	var t := ProfileStore.totals()
	profile.add_child(UIKit.label("%s  ·  rating %s  ·  %d games vs Shadow  ·  %d puzzles" % [SettingsStore.player_name, ProfileStore.rating_label(), t["games"], ProfileStore.puzzles_solved.size()], "Caption"))
	_column.add_child(profile)
	_column.add_child(UIKit.gap(26))

	var buttons: Array[Button] = []
	if SaveManager.has_autosave():
		var data := SaveManager.load_game(SaveManager.autosave_path())
		var b := _menu_button("Continue", "play", func():
			GameSession.reset_defaults()
			GameSession.load_path = SaveManager.autosave_path()
			_go_game()
		)
		buttons.append(b)
		var mode := str(data.get("mode", "local"))
		var desc := "vs Shadow · %s" % str(data.get("ai_level", "")).capitalize() if mode == "ai" else ("Analysis" if mode == "analysis" else "Two players")
		var moves: Array = data.get("moves_uci", [])
		b.tooltip_text = "%s · move %d" % [desc, int(ceil(moves.size() / 2.0))]
		_column.add_child(b)
		var sub := UIKit.label("     %s  ·  move %d" % [desc, int(ceil(moves.size() / 2.0))], "Faint")
		_column.add_child(sub)
	_new_game = NewGameDialog.new()
	_load = LoadDialog.new()
	_puzzles = PuzzleBrowser.new()
	for spec in [
		["New game", "board", func(): _new_game.open()],
		["Puzzles", "target", func(): _puzzles.open()],
		["Analysis board", "eye", func(): GameSession.configure_analysis(); _go_game()],
		["Load game", "folder", func(): _load.open()],
		["Statistics", "chart", func(): _open(StatsPanel.new())],
		["Settings", "settings", func(): _open(SettingsPanel.new())],
		["Quit", "close", func(): get_tree().quit()],
	]:
		var mb := _menu_button(spec[0], spec[1], spec[2])
		buttons.append(mb)
		_column.add_child(mb)
	_column.add_child(UIKit.spacer(false))
	var ver := str(ProjectSettings.get_setting("application/config/version", ""))
	_column.add_child(UIKit.label("Version %s  ·  Linux  ·  F11 fullscreen" % ver, "Faint"))

	var credit := UIKit.label("On the board: the Opera Game — Morphy vs Duke Karl & Count Isouard, Paris 1858", "Faint")
	credit.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	credit.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	credit.grow_vertical = Control.GROW_DIRECTION_BEGIN
	credit.offset_right = -28
	credit.offset_bottom = -22
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.add_child(credit)

	for m in [_new_game, _load, _puzzles]:
		ui.add_child(m)
	if not buttons.is_empty():
		buttons[0].call_deferred("grab_focus")
	var i := 0
	for c in _column.get_children():
		if c is Control:
			UIKit.fade_in(c, 0.4, 0.05 + i * 0.035)
			i += 1


func _menu_button(text: String, icon: String, cb: Callable) -> Button:
	var b := UIKit.button(text, cb, "MainMenuButton", icon)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_constant_override("icon_max_width", 20)
	b.icon = IconLibrary.get_icon(icon, 20)
	b.size_flags_horizontal = Control.SIZE_FILL
	return b


func _open(m: Modal) -> void:
	ui.add_child(m)
	m.closed.connect(m.queue_free)
	m.open()


func _go_game() -> void:
	get_tree().change_scene_to_file("res://scenes/main/game.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		SettingsStore.window_mode = "windowed" if SettingsStore.window_mode != "windowed" else "borderless"
		SettingsStore.apply_display()
		SettingsStore.save_settings()
		get_viewport().set_input_as_handled()
