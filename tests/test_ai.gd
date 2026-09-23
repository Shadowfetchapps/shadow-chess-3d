class_name TestAI
extends RefCounted

const MIDDLEGAME := "r1bq1rk1/pp1nbppp/2p1pn2/3p2B1/2PP4/2NBPN2/PP3PPP/R2QK2R w KQ - 0 8"
const MIDDLEGAME_B := "r2q1rk1/pb1nbppp/1p2pn2/2pp4/2PP4/1PN1PN2/PB2BPPP/R2Q1RK1 b - - 3 10"

var _passed := 0
var _failed := 0
var _errors: PackedStringArray = PackedStringArray()


## Coroutine: await it. Runs the synchronous checks, then the WorkerThreadPool ones.
func run(tree: SceneTree) -> bool:
	_passed = 0
	_failed = 0
	_errors.clear()
	var t0 := Time.get_ticks_msec()
	ChessAI.warmup()
	_test_levels()
	_test_board_perft()
	_test_board_matches_engine()
	_test_book()
	_test_each_level_legal()
	_test_mate_in_one()
	_test_mate_in_two()
	_test_no_queen_hang()
	_test_analysis_deterministic()
	_test_job_edge_cases()
	await _test_worker(tree)
	await _test_cancel(tree)
	await _test_parallel_jobs(tree)
	print("\n==============================")
	print("Shadow Chess AI  —  %d passed, %d failed  (%d ms)" % [_passed, _failed, Time.get_ticks_msec() - t0])
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


func _is_legal(fen: String, uci: String) -> bool:
	var e := ChessEngine.new()
	e.from_fen(fen)
	return e.find_uci(uci) != null


func _job(fen: String, level: String, time_ms: int = -1, depth: int = -1, book: bool = false) -> ChessAI.SearchJob:
	var j := ChessAI.SearchJob.new()
	j.start_fen = fen
	j.level = level
	j.time_ms = time_ms
	j.max_depth = depth
	j.use_book = book
	return j


func _test_levels() -> void:
	print("ai levels")
	var ids: Array[String] = []
	var fields_ok := true
	for l in ChessAI.levels():
		ids.append(str(l.id))
		for k in ["id", "name", "elo", "blurb"]:
			if not l.has(k):
				fields_ok = false
	_ok("level ids in order", ids == ["beginner", "casual", "club", "advanced", "expert", "master"], str(ids))
	_ok("level fields", fields_ok)
	var elos: Array[int] = []
	for l in ChessAI.levels():
		elos.append(int(l.elo))
	var rising := true
	for i in range(1, elos.size()):
		rising = rising and elos[i] > elos[i - 1]
	_ok("elo rises with level", rising, str(elos))
	_ok("legacy easy", ChessAI.level_id_from_legacy("easy") == "casual")
	_ok("legacy medium", ChessAI.level_id_from_legacy("medium") == "club")
	_ok("legacy hard", ChessAI.level_id_from_legacy("hard") == "advanced")
	_ok("legacy master", ChessAI.level_id_from_legacy("master") == "master")
	_ok("legacy unknown", ChessAI.level_id_from_legacy("grandmaster") == "club")
	_ok("new ids pass through", ChessAI.level_id_from_legacy("expert") == "expert")


func _test_board_perft() -> void:
	print("shadow board perft")
	var b := ShadowBoard.new()
	var cases := [
		[ChessTypes.START_FEN, 3, 8902],
		["r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", 3, 97862],
		["8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", 4, 43238],
		["r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", 3, 9467],
		["rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", 3, 62379],
	]
	for c in cases:
		b.set_fen(c[0])
		var key := b.key
		var n := b.perft(c[1])
		_ok("board perft %s d%d = %d" % [str(c[0]).substr(0, 12), c[1], c[2]], n == c[2], str(n))
		_ok("board intact after perft", b.key == key and b.fen() == ChessEngine.new().to_fen() if c[0] == ChessTypes.START_FEN else b.key == key)


func _test_board_matches_engine() -> void:
	print("shadow board vs engine")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var b := ShadowBoard.new()
	var key_ok := true
	var moves_ok := true
	var check_ok := true
	var fen_ok := true
	for game in 8:
		var e := ChessEngine.new()
		b.set_fen(ChessTypes.START_FEN)
		for ply in 80:
			var legal := b.legal_moves()
			var elegal := e.generate_legal_moves()
			if legal.size() != elegal.size():
				moves_ok = false
			if legal.is_empty():
				break
			if b.key != e.hash_key:
				key_ok = false
			var bf := b.fen().split(" ")
			var ef := e.to_fen().split(" ")
			if bf[0] != ef[0] or bf[1] != ef[1] or bf[2] != ef[2] or bf[4] != ef[4]:
				fen_ok = false
			for m in legal:
				b.make(m)
				if b.gives_check(m) != b.in_check():
					check_ok = false
				b.unmake()
			var pick := legal[rng.randi_range(0, legal.size() - 1)]
			var u := ShadowBoard.move_to_uci(pick)
			b.make(pick)
			e.make_raw(e.find_uci(u))
	_ok("same legal move counts", moves_ok)
	_ok("same zobrist keys", key_ok)
	_ok("same board, side, castling and clock", fen_ok)
	_ok("fast gives_check agrees with attack test", check_ok)


func _test_book() -> void:
	print("opening book")
	_ok("book loaded", ShadowTables.book_lines >= 80, str(ShadowTables.book_lines))
	_ok("book loader found no illegal moves", ShadowTables.book_errors.is_empty(), str(ShadowTables.book_errors))
	var text := FileAccess.get_file_as_string(ShadowTables.BOOK_PATH)
	var lines := 0
	var bad := PackedStringArray()
	var named := 0
	var prev_comment := false
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty():
			continue
		if line.begins_with("#"):
			prev_comment = true
			continue
		if prev_comment:
			named += 1
		prev_comment = false
		lines += 1
		var e := ChessEngine.new()
		var toks := line.split(" ", false)
		if toks.size() < 6 or toks.size() > 14:
			bad.append("%s (length %d)" % [line.substr(0, 20), toks.size()])
			continue
		for t in toks:
			if e.play_uci(t) == null:
				bad.append("%s: %s" % [line.substr(0, 30), t])
				break
	_ok("every book line replays legally (%d lines)" % lines, bad.is_empty() and lines >= 80, str(bad))
	_ok("every book line is named", named == lines, "%d/%d" % [named, lines])
	var firsts := {}
	for s in 40:
		var j := _job(ChessTypes.START_FEN, "club", -1, -1, true)
		j.rng_seed = s
		j.run()
		if not j.from_book or not _is_legal(ChessTypes.START_FEN, j.best_uci):
			firsts["bad"] = true
		firsts[j.best_uci] = true
	_ok("club plays legal book moves from start", not firsts.has("bad"))
	_ok("book choice varies", firsts.size() >= 2, str(firsts.keys()))
	var nb := _job(ChessTypes.START_FEN, "beginner", -1, -1, true)
	nb.run()
	_ok("beginner does not use book", not nb.from_book and _is_legal(ChessTypes.START_FEN, nb.best_uci))
	var an := _job(ChessTypes.START_FEN, "analysis", 300, 3, true)
	an.run()
	_ok("analysis ignores book", not an.from_book and an.depth >= 1)
	var deep := _job(ChessTypes.START_FEN, "club", -1, -1, true)
	deep.moves_uci = PackedStringArray(["e2e4", "c7c5", "g1f3", "d7d6", "d2d4", "c5d4", "f3d4", "g8f6", "b1c3"])
	deep.rng_seed = 3
	deep.run()
	var e := ChessEngine.new()
	for u in deep.moves_uci:
		e.play_uci(u)
	_ok("book follows game history (Najdorf)", deep.from_book and e.find_uci(deep.best_uci) != null, deep.best_uci)


func _test_each_level_legal() -> void:
	print("every level returns a legal move")
	for l in ChessAI.levels():
		for fen in [ChessTypes.START_FEN, MIDDLEGAME, MIDDLEGAME_B]:
			var e := ChessEngine.new()
			e.from_fen(fen)
			var t := Time.get_ticks_msec()
			var m := ChessAI.choose(e, l.id)
			var dt := Time.get_ticks_msec() - t
			var legal := m != null and e.find_uci(m.to_uci()) != null
			_ok("%s legal from %s (%d ms)" % [l.id, fen.substr(0, 12), dt], legal)
	var g := ChessEngine.new()
	for u in ["e2e4", "e7e5", "g1f3", "b8c6"]:
		g.play_uci(u)
	var gm := ChessAI.choose(g, "medium")
	_ok("legacy level name accepted mid-game", gm != null and g.find_uci(gm.to_uci()) != null)
	_ok("choose leaves engine untouched", g.history.size() == 4)


func _test_mate_in_one() -> void:
	print("mate in one")
	var fens := ["6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1", "3r2k1/8/8/8/8/8/5PPP/6K1 b - - 0 1",
		"r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5Q2/PPPP1PPP/RNB1K1NR w KQkq - 4 4"]
	for level in ["club", "advanced", "expert", "master"]:
		for fen in fens:
			var e := ChessEngine.new()
			e.from_fen(fen)
			var m := ChessAI.choose(e, level)
			var mated := false
			if m != null:
				e.apply_move(m)
				mated = e.result == ChessEngine.Result.CHECKMATE
			_ok("%s mates in 1 (%s)" % [level, fen.substr(0, 10)], mated, m.to_uci() if m else "null")


func _test_mate_in_two() -> void:
	print("mate in two")
	var fens := ["r1b2k1r/ppp1bppp/8/1B1Q4/5q2/2P5/PPP2PPP/R3R1K1 w - - 1 1",
		"r3r1k1/ppp2ppp/2p5/5Q2/1b1q4/8/PPP1BPPP/R1B2K1R b - - 1 1"]
	for level in ["expert", "master"]:
		for fen in fens:
			var e := ChessEngine.new()
			e.from_fen(fen)
			var j := _job(fen, level)
			j.run()
			var solves := ChessPuzzles.is_solving_move(e, j.best_uci, 2)
			_ok("%s finds mate in 2 (%s)" % [level, j.best_uci], solves and j.mate_in == 2, "mate_in=%d" % j.mate_in)


func _queen_hanging(e: ChessEngine, side: int) -> bool:
	var q := -1
	for s in 64:
		if e.squares[s] == ChessTypes.pack(ChessTypes.QUEEN, side):
			q = s
	if q < 0:
		return true
	for m in e.generate_legal_moves():
		if m.to_sq != q:
			continue
		if m.piece != ChessTypes.QUEEN and m.piece != ChessTypes.KING:
			return true
		if not e.is_square_attacked(q, side):
			return true
	return false


func _test_no_queen_hang() -> void:
	print("master keeps its queen")
	var cases := [
		"rnb1kb1r/pppp1ppp/5n2/4p3/3Q4/8/PPP1PPPP/RNB1KBNR w KQkq - 0 4",
		"r1b1kbnr/pppp1ppp/2n5/4q3/3P4/2N2N2/PPP1BPPP/R1BQK2R b KQkq - 0 5",
		"rnbqkb1r/ppp2ppp/4pn2/3p4/2PP4/2N1P3/PP3PPP/R1BQKBNR w KQkq - 0 4",
	]
	for fen in cases:
		var e := ChessEngine.new()
		e.from_fen(fen)
		var side := e.side_to_move
		var j := _job(fen, "master", 1500)
		j.run()
		var m := e.play_uci(j.best_uci)
		_ok("master safe move %s (%s)" % [j.best_uci, fen.substr(0, 14)], m != null and not _queen_hanging(e, side), "score %d" % j.score_cp)


func _test_analysis_deterministic() -> void:
	print("analysis determinism")
	var a := _job(MIDDLEGAME, "analysis", 60000, 5)
	a.run()
	var b := _job(MIDDLEGAME, "analysis", 60000, 5)
	b.run()
	_ok("analysis depth reached", a.depth == 5 and b.depth == 5, "%d/%d" % [a.depth, b.depth])
	_ok("analysis deterministic move", a.best_uci == b.best_uci and a.score_cp == b.score_cp, "%s %d vs %s %d" % [a.best_uci, a.score_cp, b.best_uci, b.score_cp])
	_ok("analysis deterministic tree", a.nodes == b.nodes and a.pv == b.pv, "%d vs %d" % [a.nodes, b.nodes])
	_ok("analysis pv starts with best", a.pv.size() >= 1 and a.pv[0] == a.best_uci)
	_ok("white-relative score", a.score_white_cp == a.score_cp)
	print("        depth 5: %d nodes, %d nps, %d ms" % [a.nodes, a.nps, a.elapsed_ms])
	var bj := _job(MIDDLEGAME_B, "analysis", 60000, 4)
	bj.run()
	_ok("black to move: white-relative score flips", bj.score_white_cp == -bj.score_cp)


func _test_job_edge_cases() -> void:
	print("search job edge cases")
	var mated := _job("rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3", "master")
	mated.run()
	_ok("checkmated side has no move", mated.best_uci == "" and mated.score_cp < -20000)
	var stale := _job("k7/8/1Q6/8/8/8/8/K7 b - - 0 1", "master")
	stale.run()
	_ok("stalemate has no move", stale.best_uci == "" and stale.score_cp == 0)
	var only := _job("k7/8/8/4b3/8/8/8/K6r w - - 0 1", "master")
	only.run()
	_ok("single legal move returned quickly", only.best_uci == "a1a2" and only.elapsed_ms < 1000, "%s %d ms" % [only.best_uci, only.elapsed_ms])
	var bad := _job(ChessTypes.START_FEN, "club")
	bad.moves_uci = PackedStringArray(["e2e4", "e2e4"])
	bad.run()
	_ok("illegal history reported", not bad.error.is_empty() and bad.best_uci == "")
	var e := ChessEngine.new()
	for u in ["d2d4", "g8f6", "c2c4", "e7e6", "b1c3", "f8b4"]:
		e.play_uci(u)
	var hist := _job(e.start_fen, "advanced", 400)
	hist.moves_uci = e.uci_history()
	hist.use_book = false
	hist.run()
	_ok("job replays history to the engine position", hist.position_key == e.hash_key)
	_ok("history job returns legal move", e.find_uci(hist.best_uci) != null, hist.best_uci)
	var draw := _job("7k/8/8/8/8/8/1q6/K7 w - - 0 1", "analysis", 500, 4)
	draw.run()
	_ok("king can take undefended queen", draw.best_uci == "a1b2", draw.best_uci)
	var beg: Dictionary = {}
	for s in 12:
		var bj := _job(MIDDLEGAME, "beginner")
		bj.rng_seed = s
		bj.run()
		beg[bj.best_uci] = true
		if not _is_legal(MIDDLEGAME, bj.best_uci):
			beg["illegal"] = true
	_ok("beginner varies its moves", beg.size() >= 3 and not beg.has("illegal"), str(beg.keys()))


func _test_worker(tree: SceneTree) -> void:
	print("worker thread search")
	var job := _job(MIDDLEGAME, "master", 1200)
	var t0 := Time.get_ticks_msec()
	var id := WorkerThreadPool.add_task(job.run, true, "shadow-chess-test")
	var pumps := 0
	while not WorkerThreadPool.is_task_completed(id):
		await tree.process_frame
		pumps += 1
		if Time.get_ticks_msec() - t0 > 10000:
			break
	WorkerThreadPool.wait_for_task_completion(id)
	var dt := Time.get_ticks_msec() - t0
	_ok("worker job finished", job.best_uci.length() >= 4, job.best_uci)
	_ok("worker move legal", _is_legal(MIDDLEGAME, job.best_uci))
	_ok("main loop kept pumping (%d frames)" % pumps, pumps >= 3)
	_ok("respected time budget (%d ms)" % dt, dt < 2500)
	print("        master worker: depth %d, %d nodes, %d nps" % [job.depth, job.nodes, job.nps])


func _test_cancel(tree: SceneTree) -> void:
	print("cancellation")
	var job := _job(MIDDLEGAME, "master", 30000)
	var id := WorkerThreadPool.add_task(job.run, true, "shadow-chess-cancel")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400:
		await tree.process_frame
	job.cancelled = true
	var tc := Time.get_ticks_msec()
	while not WorkerThreadPool.is_task_completed(id):
		await tree.process_frame
		if Time.get_ticks_msec() - tc > 5000:
			break
	WorkerThreadPool.wait_for_task_completion(id)
	var dt := Time.get_ticks_msec() - tc
	_ok("cancel stops search within 200 ms (%d ms)" % dt, dt <= 200)
	_ok("cancelled job still has a legal move", _is_legal(MIDDLEGAME, job.best_uci), job.best_uci)


func _test_parallel_jobs(tree: SceneTree) -> void:
	print("parallel jobs")
	var a := _job(MIDDLEGAME, "analysis", 60000, 4)
	var b := _job(MIDDLEGAME, "analysis", 60000, 4)
	var c := _job(MIDDLEGAME_B, "expert", 600)
	var ids := [WorkerThreadPool.add_task(a.run), WorkerThreadPool.add_task(b.run), WorkerThreadPool.add_task(c.run)]
	var t0 := Time.get_ticks_msec()
	var done := false
	while not done and Time.get_ticks_msec() - t0 < 30000:
		done = true
		for id in ids:
			if not WorkerThreadPool.is_task_completed(id):
				done = false
		if not done:
			await tree.process_frame
	for id in ids:
		WorkerThreadPool.wait_for_task_completion(id)
	_ok("concurrent jobs agree", a.best_uci == b.best_uci and a.nodes == b.nodes and a.score_cp == b.score_cp)
	_ok("concurrent jobs legal", _is_legal(MIDDLEGAME, a.best_uci) and _is_legal(MIDDLEGAME_B, c.best_uci))
