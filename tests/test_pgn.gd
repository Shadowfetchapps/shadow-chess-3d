class_name TestPgn
extends RefCounted

var _passed := 0
var _failed := 0
var _errors: PackedStringArray = PackedStringArray()


func run_all() -> bool:
	_passed = 0
	_failed = 0
	_errors.clear()
	_test_san_parse_basic()
	_test_san_parse_edge_cases()
	_test_export_headers()
	_test_export_wrapping()
	_test_roundtrip()
	_test_roundtrip_black_first()
	_test_import_annotated()
	_test_import_errors()
	print("\n==============================")
	print("Shadow Chess SAN/PGN  —  %d passed, %d failed" % [_passed, _failed])
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


func _uci(e: ChessEngine, san: String) -> String:
	var m := San.parse(e, san)
	return "" if m == null else m.to_uci()


func _test_san_parse_basic() -> void:
	print("san parse")
	var e := ChessEngine.new()
	_ok("e4", _uci(e, "e4") == "e2e4")
	_ok("Nf3", _uci(e, "Nf3") == "g1f3")
	_ok("Nf3+ tolerated", _uci(e, "Nf3+") == "g1f3")
	for glyph in ["!", "?", "!!", "??", "!?", "?!", "#", "+!"]:
		_ok("glyph " + glyph, _uci(e, "e4" + glyph) == "e2e4")
	_ok("illegal e5", San.parse(e, "e5") == null)
	_ok("garbage", San.parse(e, "Zz9") == null)
	_ok("empty", San.parse(e, "") == null)
	_ok("null move", San.parse(e, "--") == null)
	_ok("long algebraic e2e4", _uci(e, "e2e4") == "e2e4")
	_ok("long algebraic e2-e4", _uci(e, "e2-e4") == "e2e4")
	_ok("parse does not apply", e.history.is_empty())
	var played := San.parse_and_play(e, "d4")
	_ok("parse_and_play", played != null and e.history.size() == 1 and played.san == "d4")


func _test_san_parse_edge_cases() -> void:
	print("san parse edge cases")
	var e := ChessEngine.new()
	e.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	_ok("O-O", _uci(e, "O-O") == "e1g1")
	_ok("0-0", _uci(e, "0-0") == "e1g1")
	_ok("O-O-O", _uci(e, "O-O-O") == "e1c1")
	_ok("0-0-0+", _uci(e, "0-0-0+") == "e1c1")
	e.from_fen("r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1")
	_ok("black O-O", _uci(e, "O-O") == "e8g8")
	e.from_fen("4k3/8/8/8/8/8/8/R3K3 w - - 0 1")
	_ok("O-O without rights", San.parse(e, "O-O") == null)
	e.from_fen("8/4P3/8/8/8/8/k7/4K3 w - - 0 1")
	_ok("e8=Q", _uci(e, "e8=Q") == "e7e8q")
	_ok("e8Q", _uci(e, "e8Q") == "e7e8q")
	_ok("e8=N+", _uci(e, "e8=N+") == "e7e8n")
	_ok("e8n", _uci(e, "e8n") == "e7e8n")
	_ok("e8=R", _uci(e, "e8=R") == "e7e8r")
	_ok("bare e8 defaults to queen", _uci(e, "e8") == "e7e8q")
	_ok("e8=K rejected", San.parse(e, "e8=K") == null)
	e.from_fen("1r2k3/2P5/8/8/8/8/8/4K3 w - - 0 1")
	_ok("cxb8=Q#?", _uci(e, "cxb8=Q") == "c7b8q")
	e.from_fen("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
	_ok("exd6", _uci(e, "exd6") == "e5d6")
	_ok("exd6 e.p.", _uci(e, "exd6 e.p.") == "e5d6")
	_ok("exd6e.p.", _uci(e, "exd6e.p.") == "e5d6")
	_ok("exd6ep", _uci(e, "exd6ep") == "e5d6")
	_ok("ed6", _uci(e, "ed6") == "e5d6")
	e.from_fen("4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1")
	_ok("Nbd2", _uci(e, "Nbd2") == "b1d2")
	_ok("Nfd2", _uci(e, "Nfd2") == "f1d2")
	_ok("ambiguous Nd2", San.parse(e, "Nd2") == null)
	e.from_fen("7k/8/8/8/8/4R3/8/K3R3 w - - 0 1")
	_ok("R1e2", _uci(e, "R1e2") == "e1e2")
	_ok("R3e2", _uci(e, "R3e2") == "e3e2")
	_ok("ambiguous Re2", San.parse(e, "Re2") == null)
	e.from_fen("8/8/1k6/8/4Q2Q/8/8/K6Q w - - 0 1")
	_ok("Qh4e1", _uci(e, "Qh4e1") == "h4e1")
	_ok("Qh4xe1-style", _uci(e, "Qh4-e1") == "h4e1")
	_ok("Qhe1 still ambiguous", San.parse(e, "Qhe1") == null)
	_ok("Q4e1 still ambiguous", San.parse(e, "Q4e1") == null)
	_ok("Qee1", _uci(e, "Qee1") == "e4e1")
	e.from_fen("r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3")
	_ok("Bb5 (not pawn b-file)", _uci(e, "Bb5") == "f1b5")
	e.from_fen("4k3/8/8/8/8/2p5/1P6/4K3 w - - 0 1")
	_ok("bxc3 (pawn b-file)", _uci(e, "bxc3") == "b2c3")
	_ok("b3 push", _uci(e, "b3") == "b2b3")


func _long_game() -> ChessEngine:
	var e := ChessEngine.new()
	var ply := 0
	while ply < 120 and not e.game_over():
		var legal := e.generate_legal_moves()
		e.apply_move(legal[(ply * 7 + 3) % legal.size()])
		ply += 1
	return e


func _test_export_headers() -> void:
	print("pgn export headers")
	var e := ChessEngine.new()
	for u in ["e2e4", "e7e5", "g1f3"]:
		e.play_uci(u)
	var pgn := Pgn.export_game(e, {"White": "Bob \"The Rook\" \\ Jr", "Black": "Shadow", "TimeControl": "300+2", "Event": "Test Cup"})
	var lines := pgn.split("\n")
	var order: Array[String] = ["Event", "Site", "Date", "Round", "White", "Black", "Result"]
	var ok := true
	for i in order.size():
		if not lines[i].begins_with("[" + order[i] + " "):
			ok = false
	_ok("seven tag roster order", ok, pgn)
	_ok("event override", lines[0] == "[Event \"Test Cup\"]", lines[0])
	_ok("escaped quotes and backslash", pgn.contains("[White \"Bob \\\"The Rook\\\" \\\\ Jr\"]"), lines[4])
	_ok("result tag in progress", pgn.contains("[Result \"*\"]"))
	_ok("time control passed through", pgn.contains("[TimeControl \"300+2\"]"))
	_ok("ply count", pgn.contains("[PlyCount \"3\"]"))
	_ok("termination", pgn.contains("[Termination \"unterminated\"]"))
	_ok("no SetUp for standard start", not pgn.contains("SetUp"))
	_ok("movetext", pgn.contains("\n1. e4 e5 2. Nf3 *"), pgn)
	var m := ChessEngine.new()
	for u in ["f2f3", "e7e5", "g2g4", "d8h4"]:
		m.play_uci(u)
	var mp := Pgn.export_game(m)
	_ok("mate result tag", mp.contains("[Result \"0-1\"]") and mp.contains("Qh4# 0-1"), mp)
	_ok("termination normal", mp.contains("[Termination \"normal\"]"))
	var t := ChessEngine.new()
	t.play_uci("e2e4")
	t.flag_timeout(ChessTypes.BLACK)
	var tp := Pgn.export_game(t)
	_ok("time forfeit termination", tp.contains("[Termination \"time forfeit\"]") and tp.contains("[Result \"1-0\"]"))


func _test_export_wrapping() -> void:
	print("pgn wrapping")
	var e := _long_game()
	var pgn := Pgn.export_game(e)
	var body := pgn.split("\n\n")[1]
	var widest := 0
	for line in body.split("\n"):
		widest = maxi(widest, line.length())
	_ok("movetext wrapped at 80 columns", widest <= 80 and body.split("\n").size() > 3, str(widest))
	_ok("ends with result token", body.strip_edges().ends_with(e.result_token()))


func _test_roundtrip() -> void:
	print("pgn roundtrip")
	var e := _long_game()
	var pgn := Pgn.export_game(e, {"White": "A", "Black": "B"})
	var r := Pgn.import_game(pgn)
	_ok("import ok", r.ok, r.error)
	if not r.ok:
		return
	var g: ChessEngine = r.engine
	_ok("same final fen", g.to_fen() == e.to_fen(), g.to_fen())
	_ok("same san list", g.san_history() == e.san_history())
	_ok("headers read", r.headers.get("White", "") == "A" and r.headers.get("Black", "") == "B")
	_ok("result token", r.result == e.result_token(), r.result)
	var n := g.history.size()
	g.undo()
	_ok("undo works after import", g.history.size() == n - 1)


func _test_roundtrip_black_first() -> void:
	print("pgn roundtrip from black-to-move FEN")
	var e := ChessEngine.new()
	var fen := "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 3 12"
	e.from_fen(fen)
	for u in ["g8f6", "f1c4", "f8c5", "e1g1", "e8g8", "d2d3"]:
		e.play_uci(u)
	var pgn := Pgn.export_game(e)
	_ok("SetUp tag", pgn.contains("[SetUp \"1\"]"))
	_ok("FEN tag", pgn.contains("[FEN \"%s\"]" % fen), pgn)
	_ok("black-first numbering", pgn.contains("12... Nf6 13. Bc4 Bc5 14. O-O O-O 15. d3 *"), pgn)
	var setup_i := pgn.find("[SetUp")
	var fen_i := pgn.find("[FEN")
	_ok("SetUp before FEN, after roster", setup_i > pgn.find("[Result") and setup_i < fen_i)
	var r := Pgn.import_game(pgn)
	_ok("import ok", r.ok, r.error)
	if not r.ok:
		return
	var g: ChessEngine = r.engine
	_ok("start fen restored", g.start_fen == fen, g.start_fen)
	_ok("same final fen", g.to_fen() == e.to_fen(), g.to_fen())
	_ok("same san list", g.san_history() == e.san_history())
	_ok("same numbering", g.numbered_san() == e.numbered_san(), g.numbered_san())


func _test_import_annotated() -> void:
	print("pgn import with annotations")
	var text := char(0xFEFF) + "[Event \"Annotated \\\"test\\\"\"]\r\n[Site \"?\"]\r\n[Date \"2026.09.23\"]\r\n[Round \"1\"]\r\n"
	text += "[White \"W\"]\r\n[Black \"B\"]\r\n[Result \"1-0\"]\r\n\r\n"
	text += "% escape line ignored\r\n"
	text += "{Opening comment} 1. e4 $1 e5!? 2.Nf3 {A (tricky) comment} Nc6 3. Bc4 ; rest of line comment\r\n"
	text += "(3. Bb5 a6 (3... Nf6 4. O-O {deep} Nxe4) 4. Ba4 Nf6) 3... Bc5 4. c3 $14 Nf6 5. d4 exd4\r\n"
	text += "6. cxd4 Bb4+ 7. Nc3 Nxe4 8. O-O! Bxc3 9. d5 Bf6 10. Re1 Ne7 11. Rxe4 d6 12. Bg5 Bxg5\r\n"
	text += "13. Nxg5 h6? 14. Bb5+ Bd7 15. Qe2 Bxb5 16. Qxb5+ Qd7 17. Qxb7 O-O 18. Qxa8 Rxa8 1-0\r\n\r\n"
	text += "[Event \"Second game\"]\n\n1. d4 d5 *\n"
	var r := Pgn.import_game(text)
	_ok("annotated import ok", r.ok, r.error)
	if not r.ok:
		return
	var g: ChessEngine = r.engine
	_ok("escaped header value", r.headers.get("Event", "") == "Annotated \"test\"", str(r.headers.get("Event", "")))
	_ok("first game only", g.history.size() == 36, str(g.history.size()))
	_ok("result token", r.result == "1-0")
	_ok("variations skipped", g.san_history()[4] == "Bc4" and g.san_history()[5] == "Bc5", str(g.san_history()))
	_ok("castling parsed", g.san_history()[14] == "O-O")
	_ok("last move", g.san_history()[35] == "Rxa8")
	var bare := Pgn.import_game("1.e4 c5 2.Nf3 d6 3.d4 cxd4 4.Nxd4 Nf6 5.Nc3 a6")
	_ok("tagless movetext", bare.ok and (bare.engine as ChessEngine).history.size() == 10, bare.error)
	_ok("tagless result defaults to *", bare.result == "*")
	var rep := Pgn.import_game("1. Nf3 Nf6 2. Ng1 Ng8 3. Nf3 Nf6 4. Ng1 Ng8 5. e4 e5 *")
	_ok("moves after an unclaimed threefold still import", rep.ok and (rep.engine as ChessEngine).history.size() == 10, rep.error)
	var numbered := Pgn.import_game("[FEN \"4k3/8/8/8/8/8/4P3/4K3 b - - 0 40\"]\n\n40... Kd7 41. e4 Ke6 42.Kf2 *")
	_ok("FEN without SetUp + black-first numbers", numbered.ok and (numbered.engine as ChessEngine).history.size() == 4, numbered.error)


func _test_import_errors() -> void:
	print("pgn import errors")
	_ok("import supported", Pgn.import_supported())
	var r := Pgn.import_game("[Event \"x\"]\n\n1. e4 e5 2. Nc3 Nf6 3. Qh5 Ke7 4. Bc4 Kxe4 *")
	_ok("illegal move rejected", not r.ok)
	_ok("error names token and ply", str(r.error).contains("Kxe4") and str(r.error).contains("ply 8"), r.error)
	var bad_fen := Pgn.import_game("[SetUp \"1\"]\n[FEN \"8/8/8/8/8/8/8/8 w - - 0 1\"]\n\n*")
	_ok("bad FEN tag rejected", not bad_fen.ok and str(bad_fen.error).contains("FEN"), bad_fen.error)
	var unterminated := Pgn.import_game("1. e4 {never closed")
	_ok("unterminated comment", not unterminated.ok, unterminated.error)
	var unbalanced := Pgn.import_game("1. e4 (1. d4 d5 2. c4")
	_ok("unterminated variation", not unbalanced.ok, unbalanced.error)
	var empty := Pgn.import_game("   \n  ")
	_ok("empty text", not empty.ok, empty.error)
	var amb := Pgn.import_game("[FEN \"4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1\"]\n\n1. Nd2 *")
	_ok("ambiguous move rejected", not amb.ok and str(amb.error).contains("Nd2"), amb.error)
