extends Control

var _setup: PanelContainer
var _load: PanelContainer
var _mode: OptionButton
var _clock: OptionButton
var _color: OptionButton
var _diff: OptionButton
var _preview: Node3D


func _ready() -> void:
	theme = ThemeFactory.make()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_backdrop()
	_build_ui()
	SettingsStore.apply_display()
	SettingsStore.apply_audio()
	if OS.get_cmdline_user_args().has("--visual-qa"):
		var qa_script := load("res://tools/visual_qa_runner.gd")
		if qa_script:
			var qa: Node = qa_script.new()
			qa.name = "VisualQA"
			get_tree().root.add_child.call_deferred(qa)


func _build_backdrop() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.018, 0.016, 0.014)
	add_child(bg)
	var vp_wrap := SubViewportContainer.new()
	vp_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp_wrap.stretch = true
	vp_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_2X
	vp_wrap.add_child(vp)
	add_child(vp_wrap)
	var world := Node3D.new()
	vp.add_child(world)
	var env := WorldEnvironment.new()
	var look := WorldLook.make_environment()
	look.ssr_enabled = false
	env.environment = look
	world.add_child(env)
	WorldLook.add_lights(world)
	SalonBuilder.build(world)
	var board := BoardView.new()
	world.add_child(board)
	var pieces := Node3D.new()
	world.add_child(pieces)
	var eng := ChessEngine.new()
	for sq in 64:
		var p := eng.piece_at(sq)
		if p == 0:
			continue
		var pv := PieceView.new()
		pv.setup(ChessTypes.ptype(p), ChessTypes.pcolor(p), sq)
		pv.position = board.square_to_world(sq)
		pieces.add_child(pv)
	var cam := Camera3D.new()
	cam.fov = 34
	world.add_child(cam)
	_preview = world
	var tw := create_tween().set_loops()
	tw.tween_method(func(a: float):
		if not is_instance_valid(cam):
			return
		cam.position = Vector3(sin(a) * 10.2, 6.6, cos(a) * 10.2)
		cam.look_at(Vector3(0, 0.22, 0))
	, 0.55, 0.55 + TAU, 52.0)


func _build_ui() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 520
	shade.color = Color(0.03, 0.025, 0.018, 0.84)
	add_child(shade)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	box.offset_left = 56
	box.offset_right = 470
	box.offset_top = 80
	box.offset_bottom = -80
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	var kicker := Label.new()
	kicker.text = "SHADOWFETCH  ·  PRIVATE SALON"
	kicker.add_theme_color_override("font_color", ThemeFactory.accent())
	kicker.add_theme_font_size_override("font_size", 12)
	box.add_child(kicker)
	var title := Label.new()
	title.text = "Shadow Chess"
	var df: FontFile = load("res://assets/fonts/InterDisplay-SemiBold.ttf")
	if df:
		title.add_theme_font_override("font", df)
	title.add_theme_font_size_override("font_size", 48)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "3D"
	sub.add_theme_font_size_override("font_size", 28)
	sub.add_theme_color_override("font_color", ThemeFactory.muted())
	box.add_child(sub)
	var blurb := Label.new()
	blurb.text = "A dark salon. Clear rules. Gold on black."
	blurb.add_theme_color_override("font_color", ThemeFactory.muted())
	box.add_child(blurb)
	box.add_child(Control.new())
	box.add_child(_menu_btn("Play", _show_setup))
	box.add_child(_menu_btn("Local Multiplayer", _start_local))
	box.add_child(_menu_btn("AI Game", _start_ai))
	box.add_child(_menu_btn("Load Game", _show_load))
	box.add_child(_menu_btn("Settings", func(): get_tree().change_scene_to_file("res://scenes/menus/settings_menu.tscn")))
	box.add_child(_menu_btn("Quit", func(): get_tree().quit()))
	var ver := Label.new()
	ver.text = "2.0.0  ·  Linux"
	ver.add_theme_font_size_override("font_size", 12)
	ver.add_theme_color_override("font_color", Color(0.50, 0.44, 0.34))
	ver.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	box.add_child(ver)
	_setup = _build_setup()
	add_child(_setup)
	_load = _build_load()
	add_child(_load)


func _menu_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func():
		AudioManager.play("ui")
		cb.call()
	)
	return b


func _build_setup() -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = Vector2(420, 360)
	p.offset_left = -210
	p.offset_right = 210
	p.offset_top = -200
	p.offset_bottom = 200
	p.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var t := Label.new()
	t.text = "New game"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 22)
	v.add_child(t)
	_mode = OptionButton.new()
	_mode.add_item("Local two-player", 0)
	_mode.add_item("Versus AI", 1)
	v.add_child(_labeled("Mode", _mode))
	_clock = OptionButton.new()
	_clock.add_item("Casual (no clock)", 0)
	_clock.add_item("5 minutes", 300)
	_clock.add_item("10 minutes", 600)
	_clock.add_item("15 minutes", 900)
	_clock.select(2)
	v.add_child(_labeled("Clock", _clock))
	_color = OptionButton.new()
	_color.add_item("Play White", 0)
	_color.add_item("Play Black", 1)
	v.add_child(_labeled("Your color", _color))
	_diff = OptionButton.new()
	_diff.add_item("Easy", 0)
	_diff.add_item("Medium", 1)
	_diff.add_item("Hard", 2)
	_diff.add_item("Master", 3)
	_diff.select(1)
	v.add_child(_labeled("AI difficulty", _diff))
	var row := HBoxContainer.new()
	row.add_child(_menu_btn("Start", _start_setup))
	row.add_child(_menu_btn("Cancel", func(): _setup.visible = false))
	v.add_child(row)
	return p


func _build_load() -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = Vector2(520, 420)
	p.offset_left = -260
	p.offset_right = 260
	p.offset_top = -220
	p.offset_bottom = 220
	p.visible = false
	var v := VBoxContainer.new()
	v.name = "V"
	p.add_child(v)
	var t := Label.new()
	t.text = "Load game"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var list := ItemList.new()
	list.name = "List"
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(list)
	var row := HBoxContainer.new()
	row.add_child(_menu_btn("Open", _open_selected))
	row.add_child(_menu_btn("Close", func(): _load.visible = false))
	v.add_child(row)
	return p


func _labeled(text: String, node: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 130
	h.add_child(l)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(node)
	return h


func _show_setup() -> void:
	_setup.visible = true
	_load.visible = false


func _show_load() -> void:
	_setup.visible = false
	_load.visible = true
	var list := _load.get_node("V/List") as ItemList
	list.clear()
	for s in SaveManager.list_saves():
		list.add_item("%s   %s   %s" % [s.get("saved_at", ""), s.get("mode", ""), s.get("name", "")])
		list.set_item_metadata(list.item_count - 1, s.get("path", ""))


func _open_selected() -> void:
	var list := _load.get_node("V/List") as ItemList
	var items := list.get_selected_items()
	if items.is_empty():
		return
	GameSession.reset_defaults()
	GameSession.load_path = str(list.get_item_metadata(items[0]))
	get_tree().change_scene_to_file("res://scenes/main/game.tscn")


func _start_local() -> void:
	GameSession.configure_local(true)
	get_tree().change_scene_to_file("res://scenes/main/game.tscn")


func _start_ai() -> void:
	GameSession.configure_ai(true)
	get_tree().change_scene_to_file("res://scenes/main/game.tscn")


func _start_setup() -> void:
	var clock_id := _clock.get_item_id(_clock.selected)
	SettingsStore.clock_seconds = clock_id
	if _diff.selected >= 0:
		SettingsStore.ai_difficulty = ["easy", "medium", "hard", "master"][_diff.selected]
	if _mode.selected == 1:
		GameSession.configure_ai(_color.selected == 0)
	else:
		GameSession.configure_local(clock_id > 0)
	GameSession.clock_seconds = clock_id
	SettingsStore.save_settings()
	get_tree().change_scene_to_file("res://scenes/main/game.tscn")
