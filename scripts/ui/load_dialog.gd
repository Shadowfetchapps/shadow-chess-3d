class_name LoadDialog
extends Modal

## Saved games with open/delete, plus PGN import from a file.

var _list: VBoxContainer
var _file_dialog: FileDialog


func _init() -> void:
	super("Load game", 640, true, 440)
	_list = UIKit.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_list)
	add_footer_button(UIKit.button("Open saves folder", func(): OS.shell_open(SettingsStore.saves_dir()), "GhostButton", "folder"))
	footer.add_child(UIKit.spacer())
	add_footer_button(UIKit.button("Import PGN file…", _import_pgn, "", "upload"))
	add_footer_button(UIKit.button("Close", close, "GhostButton"))


func open() -> void:
	_populate()
	super.open()


func _populate() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var saves := SaveManager.list_saves()
	if saves.is_empty():
		var empty := UIKit.vbox(6)
		empty.alignment = BoxContainer.ALIGNMENT_CENTER
		empty.custom_minimum_size.y = 220
		var icon := UIKit.icon_rect("save", 36, ThemeFactory.FAINT)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		empty.add_child(icon)
		var l := UIKit.label("No saved games yet.", "Muted")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_child(l)
		var l2 := UIKit.label("Use Save game from the in-game menu, or import a PGN.", "Caption")
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_child(l2)
		_list.add_child(empty)
		return
	for s in saves:
		_list.add_child(_row(s))


func _row(s: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	var h := UIKit.hbox(12)
	card.add_child(h)
	var mode := str(s.get("mode", "local"))
	h.add_child(UIKit.icon_rect({"ai": "moon", "analysis": "eye"}.get(mode, "users"), 22))
	var v := UIKit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := str(s.get("title", "%s vs %s" % [s.get("white_name", "White"), s.get("black_name", "Black")]))
	if mode == "ai":
		title += "  ·  %s" % str(s.get("ai_level", "")).capitalize()
	v.add_child(UIKit.label(title, "Subheader"))
	var when := str(s.get("saved_at", "")).replace("T", "  ")
	v.add_child(UIKit.label("%s  ·  %s" % [when, SaveManager.summary(s)], "Caption"))
	h.add_child(v)
	var path := str(s.get("path", ""))
	var open_btn := UIKit.button("Open", func(): _open(path), "PrimaryButton")
	open_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(open_btn)
	var del := UIKit.icon_button("trash", "Delete this save", func(): _delete(path), 16)
	del.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(del)
	return card


func _open(path: String) -> void:
	GameSession.reset_defaults()
	GameSession.load_path = path
	get_tree().change_scene_to_file("res://scenes/main/game.tscn")


func _delete(path: String) -> void:
	var d := ConfirmDialog.new("Delete save", "Delete %s? This cannot be undone." % path.get_file(), "Delete", func():
		SaveManager.delete_save(path)
		_populate()
	, true)
	get_parent().add_child(d)
	d.open()


func _import_pgn() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.use_native_dialog = true
		_file_dialog.filters = PackedStringArray(["*.pgn ; PGN chess game"])
		_file_dialog.title = "Import PGN"
		_file_dialog.file_selected.connect(func(path: String):
			var f := FileAccess.open(path, FileAccess.READ)
			if f == null:
				return
			var text := f.get_as_text()
			f.close()
			var probe := Pgn.import_game(text)
			if not bool(probe.get("ok", false)):
				set_subtitle("Could not read that PGN: %s" % str(probe.get("error", "")))
				return
			GameSession.configure_analysis("", text)
			get_tree().change_scene_to_file("res://scenes/main/game.tscn")
		)
		add_child(_file_dialog)
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	_file_dialog.current_dir = docs if docs != "" else OS.get_environment("HOME")
	_file_dialog.popup_centered_ratio(0.6)
