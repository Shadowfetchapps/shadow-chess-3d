extends Control

var _res: OptionButton
var _full: CheckButton
var _vsync: CheckButton
var _quality: OptionButton
var _msaa: OptionButton
var _sens: HSlider
var _anim: HSlider
var _sfx: HSlider
var _music: HSlider
var _sfx_on: CheckButton
var _legal: CheckButton
var _orient: OptionButton
var _ai: OptionButton


func _ready() -> void:
	theme = ThemeFactory.make()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.045, 0.055)
	add_child(bg)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 640)
	panel.offset_left = -280
	panel.offset_right = 280
	panel.offset_top = -320
	panel.offset_bottom = 320
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	v.add_child(title)
	_quality = _opt(["Low", "Medium", "High"], ["low", "medium", "high"], SettingsStore.graphics_quality)
	v.add_child(_row("Graphics", _quality))
	_res = OptionButton.new()
	for r in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		_res.add_item("%d × %d" % [r.x, r.y])
		_res.set_item_metadata(_res.item_count - 1, r)
		if r == SettingsStore.resolution:
			_res.select(_res.item_count - 1)
	v.add_child(_row("Resolution", _res))
	_full = CheckButton.new()
	_full.button_pressed = SettingsStore.fullscreen
	v.add_child(_row("Fullscreen", _full))
	_vsync = CheckButton.new()
	_vsync.button_pressed = SettingsStore.vsync
	v.add_child(_row("VSync", _vsync))
	_msaa = _opt(["Off", "2×", "4×", "8×"], [0, 2, 4, 8], SettingsStore.msaa)
	v.add_child(_row("MSAA", _msaa))
	_sens = _slider(0.3, 2.5, SettingsStore.camera_sensitivity)
	v.add_child(_row("Camera sensitivity", _sens))
	_anim = _slider(0.4, 2.0, SettingsStore.animation_speed)
	v.add_child(_row("Animation speed", _anim))
	_sfx = _slider(0.0, 1.0, SettingsStore.sound_volume)
	v.add_child(_row("Sound volume", _sfx))
	_music = _slider(0.0, 1.0, SettingsStore.music_volume)
	v.add_child(_row("Music volume", _music))
	_sfx_on = CheckButton.new()
	_sfx_on.button_pressed = SettingsStore.sfx_enabled
	v.add_child(_row("Enable SFX", _sfx_on))
	_legal = CheckButton.new()
	_legal.button_pressed = SettingsStore.show_legal_moves
	v.add_child(_row("Show legal moves", _legal))
	_orient = _opt(["White", "Black", "Auto"], ["white", "black", "auto"], SettingsStore.board_orientation)
	v.add_child(_row("Board orientation", _orient))
	_ai = _opt(["Easy", "Medium", "Hard", "Master"], ["easy", "medium", "hard", "master"], SettingsStore.ai_difficulty)
	v.add_child(_row("AI difficulty", _ai))
	var row := HBoxContainer.new()
	var apply_btn := Button.new()
	apply_btn.text = "Apply"
	apply_btn.pressed.connect(_apply)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func():
		_apply()
		get_tree().change_scene_to_file("res://scenes/menus/main_menu.tscn")
	)
	row.add_child(apply_btn)
	row.add_child(back)
	v.add_child(row)


func _row(text: String, w: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 200
	h.add_child(l)
	w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(w)
	return h


func _opt(labels: Array, values: Array, current: Variant) -> OptionButton:
	var o := OptionButton.new()
	for i in labels.size():
		o.add_item(str(labels[i]))
		o.set_item_metadata(i, values[i])
		if values[i] == current:
			o.select(i)
	return o


func _slider(a: float, b: float, val: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = a
	s.max_value = b
	s.step = 0.05
	s.value = val
	return s


func _apply() -> void:
	SettingsStore.graphics_quality = str(_quality.get_selected_metadata())
	if _res.selected >= 0:
		SettingsStore.resolution = _res.get_selected_metadata()
	SettingsStore.fullscreen = _full.button_pressed
	SettingsStore.vsync = _vsync.button_pressed
	SettingsStore.msaa = int(_msaa.get_selected_metadata())
	SettingsStore.camera_sensitivity = _sens.value
	SettingsStore.animation_speed = _anim.value
	SettingsStore.sound_volume = _sfx.value
	SettingsStore.music_volume = _music.value
	SettingsStore.sfx_enabled = _sfx_on.button_pressed
	SettingsStore.show_legal_moves = _legal.button_pressed
	SettingsStore.board_orientation = str(_orient.get_selected_metadata())
	SettingsStore.ai_difficulty = str(_ai.get_selected_metadata())
	SettingsStore.save_settings()
	SettingsStore.apply_display()
	SettingsStore.apply_audio()
	AudioManager.play("ui")
