class_name San
extends RefCounted


static func encode(engine: ChessEngine, move: ChessMove) -> String:
	if move.is_castle_kingside():
		return "O-O"
	if move.is_castle_queenside():
		return "O-O-O"
	var dest := ChessTypes.algebraic(move.to_sq)
	var promo := ""
	if move.is_promotion():
		promo = "=%s" % ChessTypes.PIECE_LETTERS[move.promotion]
	if move.piece == ChessTypes.PAWN:
		if move.is_capture():
			return "%sx%s%s" % [ChessTypes.FILE_NAMES[ChessTypes.file_of(move.from_sq)], dest, promo]
		return dest + promo
	var letter := ChessTypes.PIECE_LETTERS[move.piece]
	var amb := _disambiguate(engine, move)
	var cap := "x" if move.is_capture() else ""
	return "%s%s%s%s%s" % [letter, amb, cap, dest, promo]


static func _disambiguate(engine: ChessEngine, move: ChessMove) -> String:
	var same_file := false
	var same_rank := false
	var others := false
	for other in engine.generate_legal_moves():
		if other == move:
			continue
		if other.piece != move.piece or other.to_sq != move.to_sq:
			continue
		if other.from_sq == move.from_sq and other.promotion == move.promotion:
			continue
		others = true
		if ChessTypes.file_of(other.from_sq) == ChessTypes.file_of(move.from_sq):
			same_file = true
		if ChessTypes.rank_of(other.from_sq) == ChessTypes.rank_of(move.from_sq):
			same_rank = true
	if not others:
		return ""
	if not same_file:
		return ChessTypes.FILE_NAMES[ChessTypes.file_of(move.from_sq)]
	if not same_rank:
		return str(ChessTypes.rank_of(move.from_sq) + 1)
	return ChessTypes.algebraic(move.from_sq)


static func parse_and_play(engine: ChessEngine, san: String) -> ChessMove:
	var cleaned := san.strip_edges().trim_suffix("+").trim_suffix("#").replace("x", "")
	if cleaned == "O-O" or cleaned == "0-0":
		for m in engine.generate_legal_moves():
			if m.is_castle_kingside():
				return engine.apply_move(m)
		return null
	if cleaned == "O-O-O" or cleaned == "0-0-0":
		for m in engine.generate_legal_moves():
			if m.is_castle_queenside():
				return engine.apply_move(m)
		return null
	var promo := 0
	var eq := cleaned.find("=")
	if eq >= 0:
		var pch := cleaned.substr(eq + 1, 1).to_upper()
		promo = _letter_type(pch)
		cleaned = cleaned.substr(0, eq)
	var dest: String
	var prefix: String
	if cleaned.length() >= 2:
		dest = cleaned.substr(cleaned.length() - 2, 2)
		prefix = cleaned.substr(0, cleaned.length() - 2)
	else:
		return null
	var to_sq := ChessTypes.parse_square(dest)
	if to_sq < 0:
		return null
	var piece := ChessTypes.PAWN
	var from_file := -1
	var from_rank := -1
	if prefix.length() > 0:
		var i := 0
		var first := prefix.substr(0, 1)
		if first in ["N", "B", "R", "Q", "K"]:
			piece = _letter_type(first)
			i = 1
		while i < prefix.length():
			var ch := prefix.substr(i, 1)
			if ch >= "a" and ch <= "h":
				from_file = ch.unicode_at(0) - 97
			elif ch >= "1" and ch <= "8":
				from_rank = int(ch) - 1
			i += 1
	var matches: Array[ChessMove] = []
	for m in engine.generate_legal_moves():
		if m.to_sq != to_sq or m.piece != piece:
			continue
		if promo != 0 and m.promotion != promo:
			continue
		if from_file >= 0 and ChessTypes.file_of(m.from_sq) != from_file:
			continue
		if from_rank >= 0 and ChessTypes.rank_of(m.from_sq) != from_rank:
			continue
		matches.append(m)
	if matches.size() == 1:
		return engine.apply_move(matches[0])
	return null


static func _letter_type(ch: String) -> int:
	match ch:
		"N":
			return ChessTypes.KNIGHT
		"B":
			return ChessTypes.BISHOP
		"R":
			return ChessTypes.ROOK
		"Q":
			return ChessTypes.QUEEN
		"K":
			return ChessTypes.KING
		"P":
			return ChessTypes.PAWN
		_:
			return 0
