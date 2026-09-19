class_name SaveManager
extends RefCounted


static func save_game(engine: ChessEngine, extra: Dictionary = {}) -> String:
	SettingsStore.ensure_dirs()
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("T", "-")
	var path := SettingsStore.saves_dir().path_join("game-%s.json" % stamp)
	var payload := {
		"version": 1,
		"saved_at": Time.get_datetime_string_from_system(),
		"fen": engine.to_fen(),
		"history_san": Array(engine.san_history()),
		"history_uci": engine.history.map(func(m): return m.to_uci()),
		"mode": extra.get("mode", "local"),
		"ai_side": extra.get("ai_side", 1),
		"ai_difficulty": extra.get("ai_difficulty", SettingsStore.ai_difficulty),
		"clock": extra.get("clock", {}),
		"settings": SettingsStore.to_dict(),
		"white_name": extra.get("white_name", "White"),
		"black_name": extra.get("black_name", "Black"),
		"pgn": Pgn.export_game(engine, {
			"White": extra.get("white_name", "White"),
			"Black": extra.get("black_name", "Black"),
		}),
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(payload, "\t"))
	return path


static func load_game(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


static func list_saves() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	SettingsStore.ensure_dirs()
	var dir := DirAccess.open(SettingsStore.saves_dir())
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json"):
			var path := SettingsStore.saves_dir().path_join(name)
			var data := load_game(path)
			out.append({
				"path": path,
				"name": name,
				"saved_at": str(data.get("saved_at", "")),
				"fen": str(data.get("fen", "")),
				"mode": str(data.get("mode", "local")),
			})
		name = dir.get_next()
	out.sort_custom(func(a, b): return str(a.get("saved_at", "")) > str(b.get("saved_at", "")))
	return out


static func apply_to_engine(engine: ChessEngine, data: Dictionary) -> bool:
	var fen := str(data.get("fen", ""))
	if fen.is_empty():
		return false
	if not engine.from_fen(fen):
		return false
	# Rebuild history from UCI so undo still works through the saved line.
	var ucis: Array = data.get("history_uci", [])
	var sans: Array = data.get("history_san", [])
	if ucis.is_empty():
		return true
	engine.reset()
	for i in ucis.size():
		var u := str(ucis[i])
		if u.length() < 4:
			return false
		var promo := 0
		if u.length() >= 5:
			match u.substr(4, 1):
				"q":
					promo = ChessTypes.QUEEN
				"r":
					promo = ChessTypes.ROOK
				"b":
					promo = ChessTypes.BISHOP
				"n":
					promo = ChessTypes.KNIGHT
		var m := engine.play(ChessTypes.parse_square(u.substr(0, 2)), ChessTypes.parse_square(u.substr(2, 2)), promo)
		if m == null:
			return false
		if i < sans.size() and str(sans[i]) != "":
			m.san = str(sans[i])
	return true
