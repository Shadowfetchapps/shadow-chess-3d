class_name Pgn
extends RefCounted


static func export_game(engine: ChessEngine, headers: Dictionary = {}) -> String:
	var h := {
		"Event": "Shadow Chess 3D",
		"Site": "Local",
		"Date": Time.get_date_string_from_system().replace("-", "."),
		"Round": "-",
		"White": str(headers.get("White", "Player")),
		"Black": str(headers.get("Black", "Player")),
		"Result": _result_token(engine),
	}
	for k in headers:
		h[k] = headers[k]
	var lines: PackedStringArray = PackedStringArray()
	for key in ["Event", "Site", "Date", "Round", "White", "Black", "Result"]:
		lines.append("[%s \"%s\"]" % [key, h[key]])
	for key in h.keys():
		if key in ["Event", "Site", "Date", "Round", "White", "Black", "Result"]:
			continue
		lines.append("[%s \"%s\"]" % [key, h[key]])
	lines.append("")
	var body := engine.numbered_san()
	if body.is_empty():
		body = _result_token(engine)
	else:
		body += " " + _result_token(engine)
	lines.append(body)
	lines.append("")
	return "\n".join(lines)


static func _result_token(engine: ChessEngine) -> String:
	match engine.result:
		ChessEngine.Result.CHECKMATE, ChessEngine.Result.RESIGNATION, ChessEngine.Result.TIMEOUT:
			return "1-0" if engine.result_side == ChessTypes.WHITE else "0-1"
		ChessEngine.Result.STALEMATE, ChessEngine.Result.DRAW_50, ChessEngine.Result.DRAW_MATERIAL, ChessEngine.Result.DRAW_AGREED:
			return "1/2-1/2"
		_:
			return "*"


## Structure reserved for a future PGN importer (tokeniser + SAN replay).
static func import_supported() -> bool:
	return false
