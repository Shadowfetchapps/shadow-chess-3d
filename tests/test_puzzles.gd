class_name TestPuzzles
extends RefCounted

var _passed := 0
var _failed := 0
var _errors: PackedStringArray = PackedStringArray()


func run_all() -> bool:
	_passed = 0
	_failed = 0
	_errors.clear()
	var t0 := Time.get_ticks_msec()
	ShadowTables.ensure_tables()
	_test_collection()
	_test_every_puzzle()
	_test_solver_api()
	print("\n==============================")
	print("Shadow Chess puzzles  —  %d passed, %d failed  (%d ms)" % [_passed, _failed, Time.get_ticks_msec() - t0])
	for e in _errors:
		print("  FAIL  ", e)
	print("==============================\n")
	return _failed == 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("  ok    ", name)
	else:
		_failed += 1
		var msg := name if detail.is_empty() else "%s — %s" % [name, detail]
		_errors.append(msg)
		print("  FAIL  ", msg)


func _test_collection() -> void:
	print("puzzle collection")
	var all := ChessPuzzles.load_all()
	_ok("at least 36 puzzles", all.size() >= 36, str(all.size()))
	var by_depth := {1: 0, 2: 0, 3: 0}
	var sides := {}
	var ids := {}
	var dup := false
	var fields := true
	for p in all:
		by_depth[p.depth] = int(by_depth.get(p.depth, 0)) + 1
		sides["%d%s" % [p.depth, p.side]] = true
		if ids.has(p.id):
			dup = true
		ids[p.id] = true
		if str(p.title).is_empty() or str(p.theme).is_empty() or p.goal != "mate" or p.difficulty < 1 or p.difficulty > 5:
			fields = false
	_ok("12 mate-in-1", by_depth[1] >= 12, str(by_depth))
	_ok("16 mate-in-2", by_depth[2] >= 16, str(by_depth))
	_ok("8 mate-in-3", by_depth[3] >= 8, str(by_depth))
	_ok("both colours at every depth", sides.size() == 6, str(sides.keys()))
	_ok("unique ids", not dup)
	_ok("titles, themes, goal and difficulty set", fields)


func _test_every_puzzle() -> void:
	print("puzzle verification")
	for p in ChessPuzzles.load_all():
		var t := Time.get_ticks_msec()
		var err := ChessPuzzles.verify(p)
		_ok("%s %s (%d ms)" % [p.id, p.title, Time.get_ticks_msec() - t], err.is_empty(), err)


func _test_solver_api() -> void:
	print("puzzle solver api")
	var e := ChessEngine.new()
	e.from_fen("r1b2k1r/ppp1bppp/8/1B1Q4/5q2/2P5/PPP2PPP/R3R1K1 w - - 1 1")
	_ok("key move solves", ChessPuzzles.is_solving_move(e, "d5d8", 2))
	_ok("wrong move does not solve", not ChessPuzzles.is_solving_move(e, "d5d7", 2))
	_ok("not a mate in 1", not ChessPuzzles.is_solving_move(e, "d5d8", 1))
	_ok("illegal move does not solve", not ChessPuzzles.is_solving_move(e, "d5d1", 2))
	e.play_uci("d5d8")
	_ok("only defence found", ChessPuzzles.best_defense(e, 1) == "e7d8")
	e.play_uci("e7d8")
	_ok("mating move solves in 1", ChessPuzzles.is_solving_move(e, "e1e8", 1))
	var alt := ChessEngine.new()
	alt.from_fen("6k1/5ppp/8/8/8/8/5PPP/R2R2K1 w - - 0 1")
	_ok("alternative mate accepted (Ra8)", ChessPuzzles.is_solving_move(alt, "a1a8", 1))
	_ok("alternative mate accepted (Rd8)", ChessPuzzles.is_solving_move(alt, "d1d8", 1))
	var d := ChessEngine.new()
	d.from_fen("6k1/5p1p/6p1/8/8/8/5PPP/3QR1K1 b - - 0 1")
	var reply := ChessPuzzles.best_defense(d, 2, "g8g7")
	_ok("best_defense returns a legal move", d.find_uci(reply) != null, reply)
	var p := ChessPuzzles.load_all()
	if not p.is_empty():
		var first: Dictionary = p[0]
		var pe := ChessEngine.new()
		pe.from_fen(first.fen)
		_ok("listed first move solves " + str(first.id), ChessPuzzles.is_solving_move(pe, first.solution[0], first.depth))
