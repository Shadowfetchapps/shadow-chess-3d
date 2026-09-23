class_name Pgn
extends RefCounted

const STR_TAGS: Array[String] = ["Event", "Site", "Date", "Round", "White", "Black", "Result"]
const RESULT_TOKENS: Array[String] = ["1-0", "0-1", "1/2-1/2", "*"]
const LINE_WIDTH := 80


static func export_game(engine: ChessEngine, headers: Dictionary = {}) -> String:
	var h := {
		"Event": "Shadow Chess 3D",
		"Site": "Local",
		"Date": Time.get_date_string_from_system().replace("-", "."),
		"Round": "-",
		"White": "Player",
		"Black": "Player",
		"Result": engine.result_token(),
	}
	for k in headers:
		if STR_TAGS.has(str(k)):
			h[str(k)] = str(headers[k])
	var result := str(h["Result"])
	var lines: PackedStringArray = PackedStringArray()
	for key in STR_TAGS:
		lines.append(_tag(key, str(h[key])))
	var skip: Array[String] = STR_TAGS.duplicate()
	skip.append_array(["SetUp", "FEN", "PlyCount", "Termination"])
	if engine.start_fen != ChessTypes.START_FEN:
		lines.append(_tag("SetUp", "1"))
		lines.append(_tag("FEN", engine.start_fen))
	for k in headers:
		if skip.has(str(k)):
			continue
		lines.append(_tag(str(k), str(headers[k])))
	lines.append(_tag("PlyCount", str(headers.get("PlyCount", engine.history.size()))))
	lines.append(_tag("Termination", str(headers.get("Termination", _termination(engine)))))
	lines.append("")
	lines.append_array(_wrap(_movetext_tokens(engine, result)))
	lines.append("")
	return "\n".join(lines)


static func _tag(key: String, value: String) -> String:
	var v := value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", " ").replace("\r", "")
	return "[%s \"%s\"]" % [key, v]


static func _termination(engine: ChessEngine) -> String:
	match engine.result:
		ChessEngine.Result.NONE:
			return "unterminated"
		ChessEngine.Result.TIMEOUT, ChessEngine.Result.DRAW_TIMEOUT_MATERIAL:
			return "time forfeit"
		_:
			return "normal"


static func _movetext_tokens(engine: ChessEngine, result: String) -> PackedStringArray:
	var out := PackedStringArray()
	for i in engine.history.size():
		if engine.is_white_ply(i):
			out.append("%d." % engine.move_number_for_ply(i))
		elif i == 0:
			out.append("%d..." % engine.move_number_for_ply(i))
		var m := engine.history[i]
		out.append(m.san if not m.san.is_empty() else m.to_uci())
	out.append(result)
	return out


static func _wrap(tokens: PackedStringArray) -> PackedStringArray:
	var lines := PackedStringArray()
	var line := ""
	for t in tokens:
		if line.is_empty():
			line = t
		elif line.length() + 1 + t.length() > LINE_WIDTH:
			lines.append(line)
			line = t
		else:
			line += " " + t
	if not line.is_empty():
		lines.append(line)
	return lines


static func import_supported() -> bool:
	return true


## Imports the first game of a PGN text. Returns
## { ok, error, headers, engine (history replayed, undo works), result }.
static func import_game(text: String) -> Dictionary:
	var out := {"ok": false, "error": "", "headers": {}, "engine": null, "result": "*"}
	var src := text.replace(char(0xFEFF), "").replace("\r\n", "\n").replace("\r", "\n")
	var headers := {}
	var moves := PackedStringArray()
	var result := ""
	var n := src.length()
	var i := 0
	var in_moves := false
	var line_start := true
	while i < n:
		var c := src[i]
		if c == "\n":
			line_start = true
			i += 1
			continue
		if c == " " or c == "\t":
			i += 1
			continue
		if line_start and c == "%":
			i = _skip_line(src, i)
			continue
		line_start = false
		if c == "[":
			if in_moves:
				break
			var close := _tag_end(src, i)
			if close < 0:
				out.error = "Unterminated tag pair starting at character %d" % i
				return out
			var pair := _parse_tag(src.substr(i + 1, close - i - 1))
			if pair.is_empty():
				out.error = "Malformed tag pair: %s" % src.substr(i, close - i + 1)
				return out
			headers[pair[0]] = pair[1]
			i = close + 1
			continue
		if c == "{":
			var end := src.find("}", i + 1)
			if end < 0:
				out.error = "Unterminated comment starting at character %d" % i
				return out
			i = end + 1
			continue
		if c == ";":
			i = _skip_line(src, i)
			continue
		if c == "(":
			var end_v := _skip_variation(src, i)
			if end_v < 0:
				out.error = "Unterminated variation starting at character %d" % i
				return out
			i = end_v
			continue
		if c == ")":
			out.error = "Unexpected ')' at character %d" % i
			return out
		var j := i
		while j < n and not " \t\n{}();[".contains(src[j]):
			j += 1
		var tok := src.substr(i, j - i)
		i = j
		in_moves = true
		if RESULT_TOKENS.has(tok):
			result = tok
			break
		if tok.begins_with("$"):
			continue
		var san := _strip_move_number(tok)
		if san.is_empty() or _is_glyph(san) or san == "e.p.":
			continue
		moves.append(san)
	var engine := ChessEngine.new()
	var fen := str(headers.get("FEN", ""))
	if not fen.is_empty():
		if not engine.from_fen(fen):
			out.error = "Invalid FEN tag: %s" % engine.last_fen_error
			out.headers = headers
			return out
	elif str(headers.get("SetUp", "0")) == "1":
		out.error = "SetUp is 1 but no FEN tag was given"
		out.headers = headers
		return out
	if moves.is_empty() and headers.is_empty() and result.is_empty():
		out.error = "No PGN game found"
		return out
	for k in moves.size():
		var tok := moves[k]
		if tok == "--" or tok == "Z0":
			out.error = "Null move '%s' at ply %d is not supported" % [tok, k + 1]
			return _fail(out, headers, engine)
		if engine.game_over():
			engine.result = ChessEngine.Result.NONE
			engine.result_side = -1
		var m := San.parse(engine, tok)
		if m == null:
			var label := "%d%s" % [engine.move_number_for_ply(k), "." if engine.is_white_ply(k) else "..."]
			out.error = "Illegal or ambiguous move '%s' at ply %d (%s)" % [tok, k + 1, label]
			return _fail(out, headers, engine)
		engine.apply_move(m)
	if result.is_empty():
		result = str(headers.get("Result", "*"))
		if not RESULT_TOKENS.has(result):
			result = "*"
	out.ok = true
	out.headers = headers
	out.engine = engine
	out.result = result
	return out


static func _fail(out: Dictionary, headers: Dictionary, engine: ChessEngine) -> Dictionary:
	out.headers = headers
	out.engine = engine
	return out


static func _skip_line(src: String, i: int) -> int:
	var end := src.find("\n", i)
	return src.length() if end < 0 else end


static func _tag_end(src: String, start: int) -> int:
	var i := start + 1
	var quoted := false
	while i < src.length():
		var c := src[i]
		if quoted:
			if c == "\\":
				i += 2
				continue
			if c == "\"":
				quoted = false
		elif c == "\"":
			quoted = true
		elif c == "]":
			return i
		elif c == "\n":
			return -1
		i += 1
	return -1


static func _parse_tag(body: String) -> Array:
	var s := body.strip_edges()
	var sp := s.find(" ")
	if sp <= 0:
		sp = s.find("\t")
	if sp <= 0:
		return []
	var key := s.substr(0, sp)
	var rest := s.substr(sp + 1).strip_edges()
	if rest.length() < 2 or not rest.begins_with("\"") or not rest.ends_with("\""):
		return []
	var inner := rest.substr(1, rest.length() - 2)
	var value := ""
	var k := 0
	while k < inner.length():
		var c := inner[k]
		if c == "\\" and k + 1 < inner.length():
			value += inner[k + 1]
			k += 2
			continue
		value += c
		k += 1
	return [key, value]


static func _skip_variation(src: String, start: int) -> int:
	var depth := 0
	var i := start
	while i < src.length():
		var c := src[i]
		if c == "{":
			var end := src.find("}", i + 1)
			if end < 0:
				return -1
			i = end + 1
			continue
		if c == ";":
			i = _skip_line(src, i)
			continue
		if c == "(":
			depth += 1
		elif c == ")":
			depth -= 1
			if depth == 0:
				return i + 1
		i += 1
	return -1


static func _strip_move_number(tok: String) -> String:
	var k := 0
	while k < tok.length() and tok[k] >= "0" and tok[k] <= "9":
		k += 1
	if k == tok.length():
		return ""
	if k == 0 or tok[k] != ".":
		return tok
	while k < tok.length() and tok[k] == ".":
		k += 1
	return tok.substr(k)


static func _is_glyph(tok: String) -> bool:
	for c in tok:
		if not "!?+#=-/".contains(c):
			return false
	return tok != "--"
