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
	e.from_fen("8/8/8/8/8/8/4k3/4K3 w - - 0 1")
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
