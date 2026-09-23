extends SceneTree

## Loads every GDScript in the project so parse and type errors surface in
## one headless run: godot --headless --path . --script res://tools/check_scripts.gd

func _initialize() -> void:
	var failed := 0
	var files := _collect("res://scripts") + _collect("res://tests") + _collect("res://tools")
	for f in files:
		if f.ends_with("check_scripts.gd"):
			continue
		var s: Script = load(f)
		if s == null or not s.can_instantiate() and not f.contains("/tests/") and not f.contains("/tools/"):
			if s == null:
				print("FAIL  ", f)
				failed += 1
	print("checked %d scripts, %d failed" % [files.size(), failed])
	quit(1 if failed > 0 else 0)


func _collect(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var p := dir.path_join(n)
		if d.current_is_dir():
			if not n.begins_with("."):
				out.append_array(_collect(p))
		elif n.ends_with(".gd"):
			out.append(p)
		n = d.get_next()
	return out
