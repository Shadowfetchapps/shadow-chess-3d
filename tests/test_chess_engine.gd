class_name TestChessEngine
extends RefCounted

var _passed := 0
var _failed := 0
var _errors: PackedStringArray = PackedStringArray()


func run_all() -> bool:
	_passed = 0
	_failed = 0
	_errors.clear()
	_test_start_position()
	_test_pawn_legal_illegal()
	_test_knight()
	_test_bishop()
	_test_rook()
	_test_queen()
	_test_king()
	_test_captures()
	_test_check()
	_test_checkmate()
	_test_stalemate()
	_test_castling()
	_test_castling_restrictions()
	_test_en_passant()
	_test_en_passant_exposes_king()
	_test_promotion()
	_test_pins()
	_test_discovered_and_double_check()
	_test_king_safety()
	_test_undo_redo()
	_test_fen_roundtrip()
	_test_san_and_history()
	_test_perft_start()
	_test_illegal_rejected()
	_test_perft_cpw()
	_test_zobrist()
	_test_repetition()
	_test_fifty_move()
	_test_insufficient_material()
	_test_timeout_rule()
	_test_fen_validation()
	_test_from_fen_failure_keeps_position()
	_test_captured_by()
	_test_material_diff()
	_test_numbered_san_black_first()
	_test_result_strings()
	print("\n==============================")
	print("Shadow Chess 3D  —  %d passed, %d failed" % [_passed, _failed])
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


func _e() -> ChessEngine:
	return ChessEngine.new()


func _has(engine: ChessEngine, uci: String) -> bool:
	for m in engine.generate_legal_moves():
		if m.to_uci() == uci:
			return true
	return false


func _count_from(engine: ChessEngine, from_alg: String) -> int:
	var sq := ChessTypes.parse_square(from_alg)
	return engine.generate_legal_from(sq).size()


func _test_start_position() -> void:
	print("start position")
	var e := _e()
	_ok("start fen", e.to_fen().begins_with("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq"))
	_ok("20 legal at start", e.generate_legal_moves().size() == 20, str(e.generate_legal_moves().size()))
	_ok("white to move", e.side_to_move == ChessTypes.WHITE)
	_ok("not in check", not e.in_check())


func _test_pawn_legal_illegal() -> void:
	print("pawns")
	var e := _e()
	_ok("e2e4 legal", _has(e, "e2e4"))
	_ok("e2e3 legal", _has(e, "e2e3"))
	_ok("e2e5 illegal", not _has(e, "e2e5"))
	_ok("e2d3 illegal", not _has(e, "e2d3"))
	_ok("e2e2 illegal", not _has(e, "e2e2"))
	e.play(ChessTypes.parse_square("e2"), ChessTypes.parse_square("e4"))
	e.play(ChessTypes.parse_square("e7"), ChessTypes.parse_square("e5"))
	_ok("blocked e4e5", not _has(e, "e4e5"))
	e.from_fen("8/8/8/3p4/4P3/8/8/4K1k1 w - - 0 1")
	_ok("pawn capture d5", _has(e, "e4d5"))
	_ok("pawn no reverse", not _has(e, "e4e3"))


func _test_knight() -> void:
	print("knight")
	var e := _e()
	_ok("b1c3", _has(e, "b1c3"))
	_ok("b1a3", _has(e, "b1a3"))
	_ok("b1b3 illegal", not _has(e, "b1b3"))
	_ok("b1d2 illegal (own pawn)", not _has(e, "b1d2"))
	e.from_fen("8/8/8/4N3/8/8/8/4K1k1 w - - 0 1")
	_ok("central knight 8 moves", _count_from(e, "e5") == 8, str(_count_from(e, "e5")))


func _test_bishop() -> void:
	print("bishop")
	var e := _e()
	_ok("c1 blocked", _count_from(e, "c1") == 0)
	e.from_fen("6k1/8/8/8/3B4/8/8/4K3 w - - 0 1")
	_ok("open bishop 13", _count_from(e, "d4") == 13, str(_count_from(e, "d4")))


func _test_rook() -> void:
	print("rook")
	var e := _e()
	_ok("a1 blocked", _count_from(e, "a1") == 0)
	e.from_fen("8/8/8/8/3R4/8/8/4K1k1 w - - 0 1")
	_ok("open rook 14", _count_from(e, "d4") == 14, str(_count_from(e, "d4")))


func _test_queen() -> void:
	print("queen")
	var e := _e()
	_ok("d1 blocked", _count_from(e, "d1") == 0)
	e.from_fen("6k1/8/8/8/3Q4/8/8/4K3 w - - 0 1")
	_ok("open queen 27", _count_from(e, "d4") == 27, str(_count_from(e, "d4")))


func _test_king() -> void:
	print("king")
	var e := _e()
	_ok("e1 no walk into own", not _has(e, "e1e2"))
	e.from_fen("8/8/8/8/8/8/8/4K2k w - - 0 1")
	_ok("lonely king 5", _count_from(e, "e1") == 5, str(_count_from(e, "e1")))
	e.from_fen("8/8/8/8/8/4k3/8/4K3 w - - 0 1")
	_ok("kings oppose, e2 illegal", not _has(e, "e1e2"))


func _test_captures() -> void:
	print("captures")
	var e := _e()
	e.from_fen("8/8/8/3p4/4P3/8/8/4K1k1 w - - 0 1")
	var m := e.play(ChessTypes.parse_square("e4"), ChessTypes.parse_square("d5"))
	_ok("captured pawn", m != null and m.is_capture())
	_ok("square empty of black pawn", e.piece_at(ChessTypes.parse_square("d5")) != 0)
	_ok("white pawn now on d5", ChessTypes.ptype(e.piece_at(ChessTypes.parse_square("d5"))) == ChessTypes.PAWN)


func _test_check() -> void:
	print("check")
	var e := _e()
	e.from_fen("4k3/8/8/8/8/8/8/4K2R w K - 0 1")
	e.play(ChessTypes.parse_square("h1"), ChessTypes.parse_square("h8"))
	_ok("black in check", e.in_check())
	_ok("san has plus", e.history[0].san.ends_with("+"))


func _test_checkmate() -> void:
	print("checkmate")
	var e := _e()
	# Fool's mate
	e.reset()
	e.play(ChessTypes.parse_square("f2"), ChessTypes.parse_square("f3"))
	e.play(ChessTypes.parse_square("e7"), ChessTypes.parse_square("e5"))
	e.play(ChessTypes.parse_square("g2"), ChessTypes.parse_square("g4"))
	e.play(ChessTypes.parse_square("d8"), ChessTypes.parse_square("h4"))
	_ok("fool's mate", e.result == ChessEngine.Result.CHECKMATE, e.result_text())
	_ok("black won", e.result_side == ChessTypes.BLACK)
	_ok("san mate mark", e.history[e.history.size() - 1].san.ends_with("#"))
	# Scholar-ish back rank
	e.from_fen("6k1/5ppp/8/8/8/8/8/4R2K w - - 0 1")
	e.play(ChessTypes.parse_square("e1"), ChessTypes.parse_square("e8"))
	_ok("back-rank mate", e.result == ChessEngine.Result.CHECKMATE)


func _test_stalemate() -> void:
	print("stalemate")
	var e := _e()
	e.from_fen("k7/8/1Q6/8/8/8/8/K7 b - - 0 1")
	_ok("stalemate detected", e.generate_legal_moves().is_empty() and not e.in_check())
	e._refresh_result()
	_ok("stalemate result", e.result == ChessEngine.Result.STALEMATE, e.result_text())


func _test_castling() -> void:
	print("castling")
	var e := _e()
	e.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	_ok("white O-O", _has(e, "e1g1"))
	_ok("white O-O-O", _has(e, "e1c1"))
	var m := e.play(ChessTypes.parse_square("e1"), ChessTypes.parse_square("g1"))
	_ok("castle flag", m != null and m.is_castle_kingside())
	_ok("king on g1", ChessTypes.ptype(e.piece_at(6)) == ChessTypes.KING)
	_ok("rook on f1", ChessTypes.ptype(e.piece_at(5)) == ChessTypes.ROOK)
	_ok("san O-O", m.san.begins_with("O-O"))
	e.from_fen("r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1")
	_ok("black O-O", _has(e, "e8g8"))
	_ok("black O-O-O", _has(e, "e8c8"))
	e.play(ChessTypes.parse_square("e8"), ChessTypes.parse_square("c8"))
	_ok("black king c8", ChessTypes.ptype(e.piece_at(58)) == ChessTypes.KING)
	_ok("black rook d8", ChessTypes.ptype(e.piece_at(59)) == ChessTypes.ROOK)


func _test_castling_restrictions() -> void:
	print("castling restrictions")
	var e := _e()
	e.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	e.play(ChessTypes.parse_square("e1"), ChessTypes.parse_square("e2"))
	e.play(ChessTypes.parse_square("e8"), ChessTypes.parse_square("e7"))
	e.play(ChessTypes.parse_square("e2"), ChessTypes.parse_square("e1"))
	e.play(ChessTypes.parse_square("e7"), ChessTypes.parse_square("e8"))
	_ok("no castle after king move", not _has(e, "e1g1") and not _has(e, "e1c1"))
	e.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	e.play(ChessTypes.parse_square("h1"), ChessTypes.parse_square("h2"))
	e.play(ChessTypes.parse_square("h8"), ChessTypes.parse_square("h7"))
	e.play(ChessTypes.parse_square("h2"), ChessTypes.parse_square("h1"))
	e.play(ChessTypes.parse_square("h7"), ChessTypes.parse_square("h8"))
	_ok("no O-O after rook move", not _has(e, "e1g1"))
	_ok("O-O-O still ok", _has(e, "e1c1"))
	e.from_fen("r3k2r/8/8/8/8/5r2/8/R3K2R w KQkq - 0 1")
	_ok("cannot castle through check", not _has(e, "e1g1"))
	_ok("queenside still legal", _has(e, "e1c1"))
	e.from_fen("r3k2r/8/8/8/8/4r3/8/R3K2R w KQkq - 0 1")
	_ok("cannot castle out of check", not _has(e, "e1g1") and not _has(e, "e1c1"))
	e.from_fen("r3k2r/8/8/8/8/8/8/R3K3 w Qkq - 0 1")
	_ok("missing rook no O-O", not _has(e, "e1g1"))


func _test_en_passant() -> void:
	print("en passant")
	var e := _e()
	e.reset()
	e.play(ChessTypes.parse_square("e2"), ChessTypes.parse_square("e4"))
	e.play(ChessTypes.parse_square("a7"), ChessTypes.parse_square("a6"))
	e.play(ChessTypes.parse_square("e4"), ChessTypes.parse_square("e5"))
	e.play(ChessTypes.parse_square("d7"), ChessTypes.parse_square("d5"))
	_ok("ep square d6", e.ep_square == ChessTypes.parse_square("d6"), ChessTypes.algebraic(e.ep_square))
	_ok("e5d6 ep legal", _has(e, "e5d6"))
	var m := e.play(ChessTypes.parse_square("e5"), ChessTypes.parse_square("d6"))
	_ok("ep flag", m != null and m.is_en_passant())
	_ok("captured pawn gone", e.piece_at(ChessTypes.parse_square("d5")) == 0)
	_ok("white pawn on d6", ChessTypes.ptype(e.piece_at(ChessTypes.parse_square("d6"))) == ChessTypes.PAWN)
	e.from_fen("rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3")
	_ok("fen ep legal", _has(e, "e5d6"))


func _test_en_passant_exposes_king() -> void:
	print("en passant exposing king")
	var e := _e()
	e.from_fen("8/8/8/K1pP3r/8/8/8/4k3 w - c6 0 1")
	_ok("ep capture illegal when it exposes king", not _has(e, "d5c6"))
	_ok("pawn push still legal", _has(e, "d5d6"))


func _test_promotion() -> void:
	print("promotion")
	var e := _e()
	e.from_fen("8/P7/8/8/8/8/8/K6k w - - 0 1")
	_ok("promo queen", _has(e, "a7a8q"))
	_ok("promo rook", _has(e, "a7a8r"))
	_ok("promo bishop", _has(e, "a7a8b"))
	_ok("promo knight", _has(e, "a7a8n"))
	var m := e.play(ChessTypes.parse_square("a7"), ChessTypes.parse_square("a8"), ChessTypes.KNIGHT)
	_ok("became knight", m != null and ChessTypes.ptype(e.piece_at(ChessTypes.parse_square("a8"))) == ChessTypes.KNIGHT)
	_ok("san promo", m.san.contains("=N"))
	e.from_fen("8/P7/8/8/8/8/8/K6k w - - 0 1")
	e.play(ChessTypes.parse_square("a7"), ChessTypes.parse_square("a8"), ChessTypes.QUEEN)
	_ok("default/explicit queen", ChessTypes.ptype(e.piece_at(ChessTypes.parse_square("a8"))) == ChessTypes.QUEEN)


func _test_pins() -> void:
	print("pins")
	var e := _e()
	e.from_fen("4k3/8/8/8/4n3/8/8/4R1K1 b - - 0 1")
	_ok("pinned knight has no legal moves", _count_from(e, "e4") == 0)
	e.from_fen("4k3/8/8/8/4r3/8/8/4R1K1 b - - 0 1")
	_ok("pinned rook can slide on pin", _has(e, "e4e2"))
	_ok("pinned rook cannot leave file", not _has(e, "e4a4"))


func _test_discovered_and_double_check() -> void:
	print("discovered / double check")
	var e := _e()
	e.from_fen("6k1/8/8/3N4/8/8/B7/7K w - - 0 1")
	_ok("discovered check available", _has(e, "d5c3") or _has(e, "d5e3"))
	e.play(ChessTypes.parse_square("d5"), ChessTypes.parse_square("c3"))
	_ok("discovered puts king in check", e.in_check())
	e.from_fen("6k1/8/8/3N4/8/8/B7/7K w - - 0 1")
	e.play(ChessTypes.parse_square("d5"), ChessTypes.parse_square("f6"))
	_ok("double check", e.in_check())
	# only king moves are legal in double check
	var legal := e.generate_legal_moves()
	var only_king := true
	for m in legal:
		if m.piece != ChessTypes.KING:
			only_king = false
	_ok("double check only king moves", only_king and legal.size() > 0, str(legal.size()))


func _test_king_safety() -> void:
	print("king safety")
	var e := _e()
	e.from_fen("4k3/8/8/8/8/8/8/4K2r w - - 0 1")
	_ok("king can step to e2", _has(e, "e1e2"))
	_ok("king cannot step to f1 (checked by rook)", not _has(e, "e1f1"))
	_ok("king cannot capture distant rook", not _has(e, "e1h1"))
	e.from_fen("4k3/4q3/8/8/8/8/8/4K3 w - - 0 1")
	_ok("cannot move onto queen ray", not _has(e, "e1e2"))
	_ok("can step off the file", _has(e, "e1d1") or _has(e, "e1f1"))


func _test_undo_redo() -> void:
	print("undo / redo")
	var e := _e()
	e.play(ChessTypes.parse_square("e2"), ChessTypes.parse_square("e4"))
	e.play(ChessTypes.parse_square("e7"), ChessTypes.parse_square("e5"))
	var fen := e.to_fen()
	e.undo()
	_ok("undo side", e.side_to_move == ChessTypes.BLACK)
	e.undo()
	_ok("back to start", e.to_fen().begins_with("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w"))
	e.redo()
	e.redo()
	_ok("redo restores", e.to_fen() == fen)


func _test_fen_roundtrip() -> void:
	print("fen")
	var e := _e()
	var samples := [
		ChessTypes.START_FEN,
		"r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
		"8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
		"4k3/8/8/8/3Pp3/8/8/4K3 b - d3 0 1",
	]
	for fen in samples:
		_ok("parse " + fen.substr(0, 20), e.from_fen(fen))
		var out := e.to_fen()
		_ok("roundtrip prefix", out.split(" ")[0] == fen.split(" ")[0], out)


func _test_san_and_history() -> void:
	print("san / history")
	var e := _e()
	e.play(ChessTypes.parse_square("e2"), ChessTypes.parse_square("e4"))
	e.play(ChessTypes.parse_square("e7"), ChessTypes.parse_square("e5"))
	e.play(ChessTypes.parse_square("g1"), ChessTypes.parse_square("f3"))
	_ok("san e4", e.history[0].san.begins_with("e4"))
	_ok("san Nf3", e.history[2].san.begins_with("Nf3"))
	_ok("numbered", e.numbered_san().contains("1.") and e.numbered_san().contains("Nf3"))
	var pgn := Pgn.export_game(e, {"White": "A", "Black": "B"})
	_ok("pgn headers", pgn.contains("[White \"A\"]") and pgn.contains("1. e4"))


func _test_perft_start() -> void:
	print("perft")
	var e := _e()
	_ok("perft 1 = 20", e.perft(1) == 20, str(e.perft(1)))
	_ok("perft 2 = 400", e.perft(2) == 400, str(e.perft(2)))
	var p3 := e.perft(3)
	_ok("perft 3 = 8902", p3 == 8902, str(p3))
	e.from_fen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
	_ok("kiwipete perft 1 = 48", e.perft(1) == 48, str(e.perft(1)))
	var k2 := e.perft(2)
	_ok("kiwipete perft 2 = 2039", k2 == 2039, str(k2))


func _test_illegal_rejected() -> void:
	print("illegal rejection")
	var e := _e()
	_ok("play e2e5 fails", e.play(ChessTypes.parse_square("e2"), ChessTypes.parse_square("e5")) == null)
	_ok("play opponent piece fails", e.play(ChessTypes.parse_square("e7"), ChessTypes.parse_square("e5")) == null)
	_ok("history empty", e.history.is_empty())


func _test_perft_cpw() -> void:
	print("perft (CPW positions 3-5)")
	var e := _e()
	e.from_fen("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1")
	var p3 := e.perft(4)
	_ok("pos3 perft 4 = 43238", p3 == 43238, str(p3))
	e.from_fen("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1")
	var p4 := e.perft(3)
	_ok("pos4 perft 3 = 9467", p4 == 9467, str(p4))
	e.from_fen("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8")
	var p5 := e.perft(3)
	_ok("pos5 perft 3 = 62379", p5 == 62379, str(p5))
	_ok("perft leaves position intact", e.to_fen() == "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8")


func _play(e: ChessEngine, ucis: String) -> bool:
	for u in ucis.split(" ", false):
		if e.play_uci(u) == null:
			return false
	return true


func _fresh_hash(e: ChessEngine) -> int:
	return ChessZobrist.compute(e.squares, e.side_to_move, e.castling, e.ep_square)


func _test_zobrist() -> void:
	print("zobrist")
	var e := _e()
	var start := e.hash_key
	_ok("start hash nonzero", start != 0)
	_ok("start hash matches recompute", start == _fresh_hash(e))
	var e2 := _e()
	_ok("hash deterministic across engines", e2.hash_key == start)
	for m in e.generate_legal_moves():
		e.make_raw(m)
		var inner_ok := e.hash_key == _fresh_hash(e)
		e.unmake_raw(m)
		if not inner_ok or e.hash_key != start:
			_ok("make/unmake hash " + m.to_uci(), false)
			return
	_ok("make/unmake restores hash for all start moves", e.hash_key == start)
	var a := _e()
	var b := _e()
	_play(a, "g1f3 g8f6 b1c3 b8c6")
	_play(b, "b1c3 b8c6 g1f3 g8f6")
	_ok("transposition gives equal hash", a.hash_key == b.hash_key)
	_ok("transposition hash matches recompute", a.hash_key == _fresh_hash(a))
	a.undo()
	a.undo()
	var mid := a.hash_key
	a.redo()
	a.redo()
	_ok("undo/redo hash", a.hash_key == b.hash_key and mid == _fresh_hash(_clone_back(a, 2)))
	var c := _e()
	_play(c, "e2e4")
	var d := _e()
	d.from_fen("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1")
	_ok("non-capturable ep not hashed", c.hash_key == d.hash_key)
	var f1 := _e()
	f1.from_fen("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
	var f2 := _e()
	f2.from_fen("4k3/8/8/3pP3/8/8/8/4K3 w - - 0 1")
	_ok("capturable ep changes hash", f1.hash_key != f2.hash_key)
	var cast1 := _e()
	cast1.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	var cast2 := _e()
	cast2.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w Kkq - 0 1")
	_ok("castling rights change hash", cast1.hash_key != cast2.hash_key)
	var g := _e()
	_play(g, "e2e4 d7d5 e4e5 f7f5")
	_ok("hash after ep-enabling push", g.hash_key == _fresh_hash(g))
	g.play_uci("e5f6")
	_ok("hash after ep capture", g.hash_key == _fresh_hash(g))
	var cl := g.clone()
	_ok("clone keeps hash", cl.hash_key == g.hash_key)


func _clone_back(e: ChessEngine, n: int) -> ChessEngine:
	var c := e.clone()
	for i in n:
		c.undo()
	return c


func _test_repetition() -> void:
	print("threefold repetition")
	var e := _e()
	_play(e, "g1f3 g8f6 f3g1 f6g8")
	_ok("twofold count", e.repetition_count() == 2, str(e.repetition_count()))
	_ok("no draw after twofold", e.result == ChessEngine.Result.NONE)
	_play(e, "g1f3 g8f6 f3g1")
	_ok("still playing before third occurrence", e.result == ChessEngine.Result.NONE)
	e.play_uci("f6g8")
	_ok("threefold count", e.repetition_count() == 3, str(e.repetition_count()))
	_ok("threefold draw", e.result == ChessEngine.Result.DRAW_REPETITION, e.result_text())
	_ok("threefold reason", e.result_reason() == "Threefold repetition")
	_ok("threefold token", e.result_token() == "1/2-1/2")
	_ok("no moves after draw", e.play_uci("e2e4") == null)
	e.undo()
	_ok("undo clears repetition draw", e.result == ChessEngine.Result.NONE and e.repetition_count() == 2, str(e.repetition_count()))
	var p := _e()
	p.from_fen("4k3/8/8/8/8/8/4P3/R3K3 w Q - 0 1")
	_play(p, "a1a2 e8d8 a2a1 d8e8 a1a2 e8d8 a2a1 d8e8")
	_ok("lost castling right breaks repetition", p.result == ChessEngine.Result.NONE, str(p.repetition_count()))
	_play(p, "a1a2 e8d8 a2a1 d8e8")
	_ok("repetition after rights settle", p.result == ChessEngine.Result.DRAW_REPETITION, p.result_text())


func _test_fifty_move() -> void:
	print("fifty-move rule")
	var e := _e()
	e.from_fen("7k/8/8/8/8/8/8/R3K3 w - - 99 70")
	e.play_uci("a1a2")
	_ok("draw at halfmove 100", e.result == ChessEngine.Result.DRAW_50, e.result_text())
	_ok("fifty reason", e.result_reason() == "Fifty-move rule")
	e.from_fen("6k1/5ppp/8/8/8/8/8/3R2K1 w - - 99 80")
	e.play_uci("d1d8")
	_ok("checkmate beats fifty-move", e.result == ChessEngine.Result.CHECKMATE, e.result_text())
	e.from_fen("7k/8/8/8/8/8/P7/R3K3 w - - 99 70")
	e.play_uci("a2a3")
	_ok("pawn move resets clock", e.result == ChessEngine.Result.NONE and e.halfmove == 0)


func _test_insufficient_material() -> void:
	print("insufficient material")
	var draws := {
		"K v K": "8/8/4k3/8/8/8/8/4K3 w - - 0 1",
		"KB v K": "8/8/4k3/8/8/8/8/2B1K3 w - - 0 1",
		"KN v K": "8/8/4k3/8/8/8/8/1N2K3 b - - 0 1",
		"KB v KB same colour": "5b2/8/4k3/8/8/8/8/2B1K3 w - - 0 1",
		"KBB v KB all dark": "8/8/4k3/6b1/8/4B3/8/2B1K3 w - - 0 1",
	}
	for name in draws:
		var e := _e()
		_ok("load " + name, e.from_fen(draws[name]), e.last_fen_error)
		_ok("draw: " + name, e.result == ChessEngine.Result.DRAW_MATERIAL, e.result_text())
	var alive := {
		"KB v KB opposite colours": "2b5/8/4k3/8/8/8/8/2B1K3 w - - 0 1",
		"KNN v K": "8/8/4k3/8/8/8/8/1N2KN2 w - - 0 1",
		"KN v KN": "1n6/8/4k3/8/8/8/8/1N2K3 w - - 0 1",
		"KBN v K": "8/8/4k3/8/8/8/8/1NB1K3 w - - 0 1",
		"KN v KB": "2b5/8/4k3/8/8/8/8/1N2K3 w - - 0 1",
		"KP v K": "8/8/4k3/8/8/8/P7/4K3 w - - 0 1",
		"KR v K": "8/8/4k3/8/8/8/8/R3K3 w - - 0 1",
	}
	for name in alive:
		var e := _e()
		e.from_fen(alive[name])
		_ok("not a draw: " + name, e.result == ChessEngine.Result.NONE, e.result_text())
	var c := _e()
	c.from_fen("8/8/4k3/8/8/2n5/3B4/4K3 w - - 0 1")
	c.play_uci("d2c3")
	_ok("capture into KB v K draws", c.result == ChessEngine.Result.DRAW_MATERIAL, c.result_text())


func _test_timeout_rule() -> void:
	print("timeout vs insufficient material")
	var e := _e()
	e.from_fen("8/8/4k3/8/8/8/8/1n2K2R w - - 0 1")
	e.flag_timeout(ChessTypes.WHITE)
	_ok("K+N cannot win on time", e.result == ChessEngine.Result.DRAW_TIMEOUT_MATERIAL, e.result_text())
	_ok("timeout draw token", e.result_token() == "1/2-1/2")
	_ok("timeout draw reason", e.result_reason() == "Timeout vs insufficient material")
	_ok("timeout draw text", e.result_text() == "Draw — White ran out of time, but Black cannot checkmate", e.result_text())
	_ok("timeout draw keeps flagger", e.timed_out_side == ChessTypes.WHITE and e.result_side == -1)
	_ok("no undo after flag draw", not e.can_undo())
	e.from_fen("8/8/4k3/8/8/8/8/4K2R b - - 0 1")
	e.flag_timeout(ChessTypes.WHITE)
	_ok("lone king cannot win on time", e.result == ChessEngine.Result.DRAW_TIMEOUT_MATERIAL)
	e.from_fen("8/8/4k3/8/8/8/8/r3K3 w - - 0 1")
	e.flag_timeout(ChessTypes.WHITE)
	_ok("rook wins on time", e.result == ChessEngine.Result.TIMEOUT and e.result_side == ChessTypes.BLACK)
	_ok("time forfeit token", e.result_token() == "0-1" and e.result_reason() == "Time forfeit")
	e.from_fen("8/8/4k3/8/3nn3/8/8/4K3 w - - 0 1")
	e.flag_timeout(ChessTypes.WHITE)
	_ok("two knights count as mating material", e.result == ChessEngine.Result.TIMEOUT)
	e.from_fen("8/8/4k3/8/8/p7/8/4K3 w - - 0 1")
	e.flag_timeout(ChessTypes.WHITE)
	_ok("pawn counts as mating material", e.result == ChessEngine.Result.TIMEOUT)


func _test_fen_validation() -> void:
	print("fen validation")
	var bad := {
		"empty": "",
		"too few fields": "8/8/8/8/8/8/8/8 w",
		"too many fields": ChessTypes.START_FEN + " extra",
		"seven ranks": "rnbqkbnr/pppppppp/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
		"short rank": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBN w KQkq - 0 1",
		"long rank": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNRR w KQkq - 0 1",
		"bad char": "rnbqkbnr/ppppxppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
		"digit nine": "rnbqkbnr/pppppppp/9/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
		"bad side": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq - 0 1",
		"bad castling": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KXkq - 0 1",
		"no kings": "8/8/8/8/8/8/8/8 w - - 0 1",
		"two white kings": "4k3/8/8/8/8/8/8/3KK3 w - - 0 1",
		"no black king": "8/8/8/8/8/8/8/4K3 w - - 0 1",
		"pawn on rank 8": "P3k3/8/8/8/8/8/8/4K3 w - - 0 1",
		"pawn on rank 1": "4k3/8/8/8/8/8/8/p3K3 w - - 0 1",
		"side not to move in check": "4k3/8/8/8/8/8/8/4RK2 w - - 0 1",
		"ep square without pawn": "4k3/8/8/8/8/8/8/4K3 w - e6 0 1",
		"ep on wrong rank": "4k3/8/8/3pP3/8/8/8/4K3 w - d5 0 1",
		"ep for wrong side": "4k3/8/8/8/3Pp3/8/8/4K3 w - d3 0 1",
		"bad halfmove": "4k3/8/8/8/8/8/8/4K3 w - - x 1",
		"negative fullmove": "4k3/8/8/8/8/8/8/4K3 w - - 0 -3",
	}
	for name in bad:
		var err := ChessEngine.validate_fen(bad[name])
		_ok("reject " + name, not err.is_empty(), bad[name])
	var good := [
		ChessTypes.START_FEN,
		"4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1",
		"4k3/8/8/8/3Pp3/8/8/4K3 b - d3 0 1",
		"4k3/8/8/8/8/8/8/4K3 w - -",
		"4k3/8/8/8/8/8/8/4K3  b  -  -  12  40 ",
		"4k3/8/8/8/8/8/8/4K2r w - - 0 1",
	]
	for fen in good:
		_ok("accept " + fen.substr(0, 30), ChessEngine.validate_fen(fen).is_empty(), ChessEngine.validate_fen(fen))
	var e := _e()
	_ok("error text is readable", ChessEngine.validate_fen("4k3/8/8/8/8/8/8/3KK3 w - - 0 1").contains("king"))
	_ok("mismatched castling accepted", e.from_fen("4k3/8/8/8/8/8/8/4K3 w KQkq - 0 1"))
	_ok("mismatched castling sanitized", e.castling == 0 and e.to_fen().split(" ")[2] == "-", e.to_fen())
	e.from_fen("r3k3/8/8/8/8/8/8/4K2R w KQkq - 0 1")
	_ok("partial castling sanitized", e.to_fen().split(" ")[2] == "Kq", e.to_fen())
	_ok("start_fen normalized", e.start_fen == e.to_fen())


func _test_from_fen_failure_keeps_position() -> void:
	print("from_fen failure keeps position")
	var e := _e()
	_play(e, "e2e4 e7e5 g1f3")
	var fen := e.to_fen()
	var key := e.hash_key
	_ok("invalid fen rejected", not e.from_fen("this is not a fen"))
	_ok("error recorded", not e.last_fen_error.is_empty())
	_ok("position unchanged", e.to_fen() == fen and e.hash_key == key)
	_ok("history unchanged", e.history.size() == 3)
	_ok("rejects king-in-check fen", not e.from_fen("4k3/8/8/8/8/8/8/4RK2 w - - 0 1"))
	_ok("still unchanged", e.to_fen() == fen)
	_ok("can keep playing", e.play_uci("b8c6") != null)
	_ok("valid fen clears error", e.from_fen(ChessTypes.START_FEN) and e.last_fen_error.is_empty())


func _test_captured_by() -> void:
	print("captured_by")
	var e := _e()
	e.from_fen("3rk3/2P5/8/8/8/8/8/4K3 w - - 0 1")
	_ok("fen start has no captures", e.captured_by(ChessTypes.WHITE).is_empty() and e.captured_by(ChessTypes.BLACK).is_empty())
	e.play_uci("c7d8q")
	e.play_uci("e8d8")
	_ok("white captured rook", e.captured_by(ChessTypes.WHITE) == [ChessTypes.ROOK], str(e.captured_by(ChessTypes.WHITE)))
	_ok("black captured promoted queen", e.captured_by(ChessTypes.BLACK) == [ChessTypes.QUEEN], str(e.captured_by(ChessTypes.BLACK)))
	var g := _e()
	_play(g, "e2e4 d7d5 e4d5 d8d5 b1c3 d5a2 a1a2 c8g4 f2f3 g4f3 g1f3")
	var w := g.captured_by(ChessTypes.WHITE)
	var b := g.captured_by(ChessTypes.BLACK)
	_ok("white captures sorted", w == [ChessTypes.QUEEN, ChessTypes.BISHOP, ChessTypes.PAWN], str(w))
	_ok("black captures sorted", b == [ChessTypes.PAWN, ChessTypes.PAWN, ChessTypes.PAWN], str(b))
	g.undo()
	_ok("undo updates captures", g.captured_by(ChessTypes.WHITE) == [ChessTypes.QUEEN, ChessTypes.PAWN], str(g.captured_by(ChessTypes.WHITE)))


func _test_material_diff() -> void:
	print("material_diff")
	var e := _e()
	_ok("start is level", e.material_diff() == 0)
	e.from_fen("3rk3/2P5/8/8/8/8/8/4K3 w - - 0 1")
	_ok("pawn vs rook", e.material_diff() == -4, str(e.material_diff()))
	e.play_uci("c7d8q")
	_ok("after promotion capture", e.material_diff() == 9, str(e.material_diff()))
	e.play_uci("e8d8")
	_ok("bare kings", e.material_diff() == 0)


func _test_numbered_san_black_first() -> void:
	print("numbered san (black first)")
	var e := _e()
	e.from_fen("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 12")
	_play(e, "g8f6 f1d3 e7e5")
	_ok("black-first numbering", e.numbered_san() == "12... Nf6 13. Bd3 e5", e.numbered_san())
	_ok("ply 0 is black move 12", e.move_number_for_ply(0) == 12 and not e.is_white_ply(0))
	_ok("ply 1 is white move 13", e.move_number_for_ply(1) == 13 and e.is_white_ply(1))
	_ok("ply 2 is black move 13", e.move_number_for_ply(2) == 13 and not e.is_white_ply(2))
	var w := _e()
	w.from_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 7")
	_play(w, "d2d4 d7d5")
	_ok("white-first later numbering", w.numbered_san() == "7. d4 d5", w.numbered_san())
	var s := _e()
	_play(s, "e2e4 e7e5")
	_ok("standard numbering", s.numbered_san() == "1. e4 e5", s.numbered_san())
	_ok("start_fen tracked", e.start_fen.ends_with("b KQkq - 0 12"), e.start_fen)


func _test_result_strings() -> void:
	print("result strings")
	var e := _e()
	_ok("in progress token", e.result_token() == "*" and e.result_reason() == "")
	_play(e, "f2f3 e7e5 g2g4 d8h4")
	_ok("mate token", e.result_token() == "0-1" and e.result_reason() == "Checkmate")
	e.reset()
	e.resign(ChessTypes.BLACK)
	_ok("resign token", e.result_token() == "1-0" and e.result_reason() == "Resignation")
	e.reset()
	e.agree_draw()
	_ok("agreement token", e.result_token() == "1/2-1/2" and e.result_reason() == "Agreement")
	e.from_fen("k7/8/1Q6/8/8/8/8/K7 b - - 0 1")
	_ok("stalemate from fen", e.result == ChessEngine.Result.STALEMATE and e.result_reason() == "Stalemate" and e.result_token() == "1/2-1/2")
