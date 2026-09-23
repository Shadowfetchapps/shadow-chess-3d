class_name PuzzleBrowser
extends Modal

## Grid of built-in checkmate puzzles grouped by length, with progress.

var _content: VBoxContainer
var _progress: ProgressBar
var _progress_label: Label


func _init() -> void:
	super("Puzzles", 820, true, 520)
	set_subtitle("Every puzzle is a forced checkmate, verified by the test suite. Any move that keeps the mate counts.")
	var head := UIKit.hbox(12)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 8)
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress.show_percentage = false
	head.add_child(_progress)
	_progress_label = UIKit.label("", "Gold")
	head.add_child(_progress_label)
	body.add_child(head)
	_content = UIKit.vbox(12)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_content)
	add_footer_button(UIKit.button("Close", close, "GhostButton"))


func open() -> void:
	_populate()
	super.open()


func _populate() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	var all := ChessPuzzles.load_all()
	var solved := 0
	for p in all:
		if ProfileStore.is_puzzle_solved(str(p.get("id", ""))):
			solved += 1
	_progress.max_value = maxi(all.size(), 1)
	_progress.value = solved
	_progress_label.text = "%d / %d solved" % [solved, all.size()]
	for depth in [1, 2, 3]:
		var group: Array = []
		for i in all.size():
			if int(all[i].get("depth", 1)) == depth:
				group.append(i)
		if group.is_empty():
			continue
		_content.add_child(UIKit.label("MATE IN %d" % depth, "Kicker"))
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		for i in group:
			grid.add_child(_tile(all[i], i))
		_content.add_child(grid)


func _tile(p: Dictionary, index: int) -> Button:
	var b := Button.new()
	b.theme_type_variation = "ChipButton"
	b.custom_minimum_size = Vector2(180, 78)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var solved := ProfileStore.is_puzzle_solved(str(p.get("id", "")))
	var v := UIKit.vbox(3)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_top = 9
	v.offset_right = -10
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := UIKit.hbox(6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var num := UIKit.label("#%d" % (index + 1), "Faint")
	top.add_child(num)
	top.add_child(UIKit.spacer())
	if solved:
		top.add_child(UIKit.icon_rect("check", 14, ThemeFactory.SUCCESS))
	var side := "White" if str(p.get("fen", "")).split(" ").size() > 1 and str(p.get("fen", "")).split(" ")[1] == "w" else "Black"
	var diff := int(p.get("difficulty", 1))
	top.add_child(UIKit.label("★".repeat(diff), "Gold"))
	v.add_child(top)
	var t := UIKit.label(str(p.get("title", "Puzzle")), "Subheader")
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(t)
	v.add_child(UIKit.label("%s to move" % side, "Caption"))
	for c in v.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	b.mouse_entered.connect(func(): AudioManager.play("ui_hover"))
	b.pressed.connect(func():
		AudioManager.play("ui_click")
		GameSession.configure_puzzle(p, index)
		get_tree().change_scene_to_file("res://scenes/main/game.tscn")
	)
	return b
