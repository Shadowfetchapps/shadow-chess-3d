class_name SettingsPanel
extends Modal

## Tabbed settings dialog. Every control applies immediately; the file is
## written shortly after the last change.

const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]

var _tabs: TabBar
var _pages: Array[Control] = []
var _save_timer: Timer


func _init() -> void:
	super("Settings", 700, false)
	set_subtitle("Changes apply immediately.")
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.3
	_save_timer.timeout.connect(_flush)
	add_child(_save_timer)
	_tabs = TabBar.new()
	for t in ["Game", "Board", "Display", "Audio", "Controls"]:
		_tabs.add_tab(t)
	_tabs.tab_changed.connect(_show_page)
	body.add_child(_tabs)
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(0, 430)
	body.add_child(stack)
	for builder in [_game_page, _board_page, _display_page, _audio_page, _controls_page]:
		var scroll := ScrollContainer.new()
		scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var page := UIKit.vbox(14)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(page)
		builder.call(page)
		stack.add_child(scroll)
		_pages.append(scroll)
	_show_page(0)
	add_footer_button(UIKit.button("Reset to defaults", _reset, "GhostButton", "restart"))
	footer.add_child(UIKit.spacer())
	add_footer_button(UIKit.button("Done", close, "PrimaryButton"))
	closed.connect(_flush)


func _show_page(i: int) -> void:
	for p in _pages.size():
		_pages[p].visible = p == i


func _apply_setting(key: String, value: Variant, display: bool = false) -> void:
	SettingsStore.set(key, value)
	if display:
		SettingsStore.apply_display()
	SettingsStore.apply_audio()
	_save_timer.start()


func _flush() -> void:
	if not _save_timer.is_stopped():
		_save_timer.stop()
	SettingsStore.save_settings()


func _reset() -> void:
	SettingsStore.reset_defaults()
	close()


func _section(page: VBoxContainer, title: String) -> void:
	if page.get_child_count() > 0:
		page.add_child(UIKit.gap(4))
	page.add_child(UIKit.label(title.to_upper(), "Kicker"))


func _game_page(page: VBoxContainer) -> void:
	_section(page, "Player")
	var name_edit := LineEdit.new()
	name_edit.text = SettingsStore.player_name
	name_edit.max_length = 24
	name_edit.placeholder_text = "You"
	name_edit.text_changed.connect(func(t: String): _apply_setting("player_name", t.strip_edges() if t.strip_edges() != "" else "You"))
	page.add_child(UIKit.row("Your name", name_edit))
	var ids: Array = []
	var names: Array = []
	for l in ChessAI.levels():
		ids.append(str(l.get("id")))
		names.append("%s  ·  %s" % [l.get("name"), l.get("elo", "")])
	page.add_child(UIKit.row("Default Shadow level", UIKit.option(names, ids, SettingsStore.ai_level, func(v): _apply_setting("ai_level", v))))
	var tc_labels := ["No clock", "1 + 0 bullet", "3 + 2 blitz", "5 + 0 blitz", "10 + 0 rapid", "15 + 10 rapid", "30 + 0 classical"]
	page.add_child(UIKit.row("Default time control", UIKit.option(tc_labels, SettingsStore.CLOCK_PRESETS, SettingsStore.clock_preset, func(v): _apply_setting("clock_preset", v))))
	_section(page, "Play")
	page.add_child(UIKit.toggle("Always promote to a queen", SettingsStore.auto_queen, func(v): _apply_setting("auto_queen", v)))
	page.add_child(UIKit.toggle("Show Shadow's evaluation bar", SettingsStore.show_eval_bar, func(v): _apply_setting("show_eval_bar", v)))
	page.add_child(UIKit.row("Animation speed", UIKit.slider(0.4, 2.5, 0.05, SettingsStore.animation_speed, func(v): _apply_setting("animation_speed", v))))


func _board_page(page: VBoxContainer) -> void:
	_section(page, "Board")
	var boards: Array = []
	for id in SettingsStore.BOARD_THEMES:
		var t: Dictionary = MaterialLibrary.BOARD_THEMES[id]
		boards.append([t["name"], id, t["blurb"]])
	page.add_child(UIKit.chips(boards, SettingsStore.board_theme, func(v): _apply_setting("board_theme", v)))
	_section(page, "Pieces")
	var sets: Array = []
	for id in SettingsStore.PIECE_STYLES:
		sets.append([MaterialLibrary.PIECE_STYLES[id]["name"], id])
	page.add_child(UIKit.chips(sets, SettingsStore.piece_style, func(v): _apply_setting("piece_style", v)))
	_section(page, "Guides")
	page.add_child(UIKit.toggle("Show legal moves", SettingsStore.show_legal_moves, func(v): _apply_setting("show_legal_moves", v)))
	page.add_child(UIKit.toggle("Highlight the last move", SettingsStore.highlight_last_move, func(v): _apply_setting("highlight_last_move", v)))
	page.add_child(UIKit.toggle("Show coordinates", SettingsStore.show_coordinates, func(v): _apply_setting("show_coordinates", v)))
	page.add_child(UIKit.toggle("High-contrast highlights", SettingsStore.high_contrast, func(v): _apply_setting("high_contrast", v)))


func _display_page(page: VBoxContainer) -> void:
	_section(page, "Window")
	page.add_child(UIKit.chips([["Windowed", "windowed"], ["Borderless", "borderless"], ["Fullscreen", "fullscreen"]], SettingsStore.window_mode, func(v): _apply_setting("window_mode", v, true)))
	var res_labels: Array = []
	for r in RESOLUTIONS:
		res_labels.append("%d × %d" % [r.x, r.y])
	page.add_child(UIKit.row("Window size", UIKit.option(res_labels, RESOLUTIONS, SettingsStore.resolution, func(v): _apply_setting("resolution", v, true))))
	page.add_child(UIKit.toggle("Vertical sync", SettingsStore.vsync, func(v): _apply_setting("vsync", v, true)))
	page.add_child(UIKit.row("Frame limit", UIKit.option(["Unlimited", "60 fps", "120 fps", "144 fps", "240 fps"], [0, 60, 120, 144, 240], SettingsStore.fps_limit, func(v): _apply_setting("fps_limit", v, true))))
	_section(page, "Graphics")
	page.add_child(UIKit.chips([["Low", "low", "No shadows or post effects. For older GPUs."], ["Medium", "medium", "Shadows, bloom, and fog."], ["High", "high", "Adds ambient occlusion, reflections, and depth of field."], ["Ultra", "ultra", "Adds indirect light, volumetric light shafts, and TAA."]], SettingsStore.graphics_quality, func(v): _apply_setting("graphics_quality", v, true)))
	page.add_child(UIKit.row("Anti-aliasing (MSAA)", UIKit.option(["Off", "2×", "4×", "8×"], [0, 2, 4, 8], SettingsStore.msaa, func(v): _apply_setting("msaa", v, true))))
	page.add_child(UIKit.row("3D render scale", UIKit.slider(0.5, 1.0, 0.05, SettingsStore.render_scale, func(v): _apply_setting("render_scale", v, true))))
	page.add_child(UIKit.row("Interface scale", UIKit.slider(0.8, 1.5, 0.05, SettingsStore.ui_scale, func(v): _apply_setting("ui_scale", v, true))))


func _audio_page(page: VBoxContainer) -> void:
	_section(page, "Volume")
	page.add_child(UIKit.row("Master", UIKit.slider(0.0, 1.0, 0.01, SettingsStore.master_volume, func(v): _apply_setting("master_volume", v))))
	page.add_child(UIKit.row("Music", UIKit.slider(0.0, 1.0, 0.01, SettingsStore.music_volume, func(v): _apply_setting("music_volume", v))))
	page.add_child(UIKit.row("Pieces and effects", UIKit.slider(0.0, 1.0, 0.01, SettingsStore.sfx_volume, func(v): _apply_setting("sfx_volume", v))))
	page.add_child(UIKit.row("Interface", UIKit.slider(0.0, 1.0, 0.01, SettingsStore.ui_volume, func(v): _apply_setting("ui_volume", v))))
	_section(page, "Switches")
	page.add_child(UIKit.toggle("Play music", SettingsStore.music_enabled, func(v): _apply_setting("music_enabled", v)))
	page.add_child(UIKit.toggle("Play sound effects", SettingsStore.sfx_enabled, func(v): _apply_setting("sfx_enabled", v)))


func _controls_page(page: VBoxContainer) -> void:
	_section(page, "Camera")
	page.add_child(UIKit.row("Orbit sensitivity", UIKit.slider(0.2, 3.0, 0.05, SettingsStore.camera_sensitivity, func(v): _apply_setting("camera_sensitivity", v))))
	page.add_child(UIKit.toggle("Invert vertical orbit", SettingsStore.invert_orbit, func(v): _apply_setting("invert_orbit", v)))
	page.add_child(UIKit.row("Starting view", UIKit.option(["Player's chair", "Top-down"], ["player", "top"], SettingsStore.camera_view, func(v): _apply_setting("camera_view", v))))
	_section(page, "Comfort")
	page.add_child(UIKit.toggle("Reduce motion", SettingsStore.reduce_motion, func(v): _apply_setting("reduce_motion", v)))
	_section(page, "Shortcuts")
	page.add_child(HelpOverlay.shortcut_grid())
