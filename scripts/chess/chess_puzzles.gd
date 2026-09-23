class_name ChessPuzzles
extends RefCounted

## Mate puzzles (data/puzzles.json) plus an exact forced-mate solver that runs
## on the Shadow 0x88 board. Checks are tried first; the defender always
## considers every legal reply.

const PATH := "res://data/puzzles.json"


static func load_all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return out
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Array):
		return out
	for item in data:
		if not (item is Dictionary):
			continue
		var p: Dictionary = item
		var sol: Array[String] = []
		for u in p.get("solution", []):
			sol.append(str(u))
		out.append({
			"id": str(p.get("id", "")),
			"title": str(p.get("title", "")),
			"fen": str(p.get("fen", "")),
			"goal": str(p.get("goal", "mate")),
			"depth": int(p.get("depth", 1)),
			"side": str(p.get("side", "w")),
			"solution": sol,
			"theme": str(p.get("theme", "")),
			"difficulty": int(p.get("difficulty", 1)),
		})
	return out


## True if playing `uci` (side to move = attacker) still forces mate within
## `moves_left` attacker moves, counting this one. Accepts alternative solutions.
static func is_solving_move(engine: ChessEngine, uci: String, moves_left: int) -> bool:
	if moves_left < 1:
		return false
	var b := _board_from(engine)
	if b == null:
		return false
	var m := b.parse_uci(uci)
	if m == 0:
		return false
	var checked := b.in_check()
	b.make(m)
	if not b.legal_after(m, checked):
		return false
	return _all_replies_mated(b, moves_left, b.gives_check(m), {})


## Defender (side to move) reply that postpones mate the longest; ties prefer `preferred`.
## `moves_left` is the number of attacker moves remaining after this reply.
static func best_defense(engine: ChessEngine, moves_left: int, preferred: String = "") -> String:
	var b := _board_from(engine)
	if b == null:
		return ""
	var cache := {}
	var best := ""
	var best_len := -1
	for r in b.legal_moves():
		b.make(r)
		var n := mate_length(b, maxi(moves_left, 0), cache)
		b.unmake()
		var u := ShadowBoard.move_to_uci(r)
		if n > best_len or (n == best_len and u == preferred):
			best_len = n
			best = u
	return best


## Smallest k <= max_n such that the side to move mates in k; max_n + 1 if none.
static func mate_length(b: ShadowBoard, max_n: int, cache: Dictionary = {}) -> int:
	for k in range(1, max_n + 1):
		if can_mate(b, k, cache):
			return k
	return max_n + 1


## Side to move can force checkmate within n of its own moves.
static func can_mate(b: ShadowBoard, n: int, cache: Dictionary = {}) -> bool:
	if n < 1:
		return false
	var ck := b.key ^ (n * 0x2545F4914F6CDD1D)
	if cache.has(ck):
		return cache[ck]
	var checked := b.in_check()
	var start := b.mtop
	var end := b.gen(start, false, checked)
	b.mtop = end
	var found := false
	for want_check in [true, false]:
		if not want_check and n == 1:
			break
		for i in range(start, end):
			var m := b.mv[i]
			b.make(m)
			if not b.legal_after(m, checked):
				b.unmake()
				continue
			var gives := b.gives_check(m)
			if gives != want_check:
				b.unmake()
				continue
			var ok := _all_replies_mated(b, n, gives, cache)
			b.unmake()
			if ok:
				found = true
				break
		if found:
			break
	b.mtop = start
	cache[ck] = found
	return found


## Defender to move after an attacker move; true if every reply still loses
## to mate within n - 1 further attacker moves (or it is already checkmate).
static func _all_replies_mated(b: ShadowBoard, n: int, in_check: bool, cache: Dictionary) -> bool:
	var start := b.mtop
	var end := b.gen(start, false, in_check)
	b.mtop = end
	var any_legal := false
	var ok := true
	for i in range(start, end):
		var r := b.mv[i]
		b.make(r)
		if not b.legal_after(r, in_check):
			b.unmake()
			continue
		any_legal = true
		var mated := n > 1 and can_mate(b, n - 1, cache)
		b.unmake()
		if not mated:
			ok = false
			break
	b.mtop = start
	if not any_legal:
		return in_check
	return ok


static func _board_from(engine: ChessEngine) -> ShadowBoard:
	var b := ShadowBoard.new()
	if not b.set_fen(engine.to_fen()):
		return null
	return b


## Full consistency check of one puzzle. Returns "" when valid.
static func verify(p: Dictionary) -> String:
	var fen := str(p.get("fen", ""))
	var err := ChessEngine.validate_fen(fen)
	if not err.is_empty():
		return "bad FEN: " + err
	var depth := int(p.get("depth", 0))
	var sol: Array = p.get("solution", [])
	if depth < 1:
		return "depth must be >= 1"
	if sol.size() != depth * 2 - 1:
		return "solution has %d plies, expected %d" % [sol.size(), depth * 2 - 1]
	var e := ChessEngine.new()
	e.from_fen(fen)
	var side := "w" if e.side_to_move == ChessTypes.WHITE else "b"
	if str(p.get("side", "")) != side:
		return "side field '%s' does not match FEN side '%s'" % [p.get("side", ""), side]
	if not is_solving_move(e, str(sol[0]), depth):
		return "first move %s does not force mate in %d" % [sol[0], depth]
	if depth > 1:
		var b := _board_from(e)
		if can_mate(b, depth - 1, {}):
			return "position already has a mate in %d" % (depth - 1)
	for i in sol.size():
		var u := str(sol[i])
		if i % 2 == 1:
			var left := depth - ((i + 1) >> 1)
			var want := best_defense(e, left, u)
			if want != u:
				return "ply %d: defender reply %s is not the most stubborn (%s lasts longer)" % [i + 1, u, want]
		if e.play_uci(u) == null:
			return "ply %d: illegal move %s" % [i + 1, u]
	if e.result != ChessEngine.Result.CHECKMATE:
		return "solution does not end in checkmate"
	return ""
