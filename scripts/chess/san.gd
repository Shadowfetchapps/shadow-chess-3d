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
	var amb := "" if move.piece == ChessTypes.KING else _disambiguate(engine, move)
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


## Strips check/mate marks, annotation glyphs and "e.p." from a SAN token.
static func clean(text: String) -> String:
	var s := text.strip_edges().replace("e.p.", "").replace("ep", "").strip_edges()
	while not s.is_empty() and "+#!?".contains(s[s.length() - 1]):
		s = s.substr(0, s.length() - 1)
	return s


## Parses a SAN (or long algebraic) move for the side to move. Does not apply it.
## Returns null when the text is not a legal move or is ambiguous.
static func parse(engine: ChessEngine, text: String) -> ChessMove:
	var s := clean(text).replace("0", "O")
	if s.is_empty():
		return null
	var legal := engine.generate_legal_moves()
	var plain := s.replace("-", "")
	if plain == "OO" or plain == "OOO":
		for m in legal:
			if (plain == "OO" and m.is_castle_kingside()) or (plain == "OOO" and m.is_castle_queenside()):
				return m
		return null
	s = s.replace("x", "").replace(":", "").replace("-", "")
	var promo := 0
	var eq := s.find("=")
	if eq < 0:
		eq = s.find("/")
	if eq >= 0:
		promo = _letter_type(s.substr(eq + 1, 1).to_upper())
		if promo == 0 or promo == ChessTypes.KING or promo == ChessTypes.PAWN:
			return null
		s = s.substr(0, eq)
	elif s.length() >= 3 and "QRBNqrbn".contains(s[s.length() - 1]) and "18".contains(s[s.length() - 2]):
		promo = _letter_type(s[s.length() - 1].to_upper())
		s = s.substr(0, s.length() - 1)
	s = s.replace("(", "").replace(")", "")
	var piece := ChessTypes.PAWN
	if not s.is_empty() and "NBRQKP".contains(s[0]):
		piece = _letter_type(s[0])
		s = s.substr(1)
	if s.length() < 2 or s.length() > 4:
		return null
	var to_sq := ChessTypes.parse_square(s.substr(s.length() - 2, 2))
	if to_sq < 0:
		return null
	var from_file := -1
	var from_rank := -1
	var dis := s.substr(0, s.length() - 2)
	for i in dis.length():
		var ch := dis[i]
		if ch >= "a" and ch <= "h":
			from_file = ch.unicode_at(0) - 97
		elif ch >= "1" and ch <= "8":
			from_rank = ch.unicode_at(0) - 49
		else:
			return null
	var matches: Array[ChessMove] = []
	for m in legal:
		if m.to_sq != to_sq or m.piece != piece:
			continue
		if m.is_promotion():
			if m.promotion != (promo if promo != 0 else ChessTypes.QUEEN):
				continue
		elif promo != 0:
			continue
		if from_file >= 0 and ChessTypes.file_of(m.from_sq) != from_file:
			continue
		if from_rank >= 0 and ChessTypes.rank_of(m.from_sq) != from_rank:
			continue
		matches.append(m)
	if matches.size() > 1 and piece == ChessTypes.PAWN and from_file < 0:
		var pushes: Array[ChessMove] = []
		for m in matches:
			if not m.is_capture():
				pushes.append(m)
		matches = pushes
	if matches.size() == 1:
		return matches[0]
	return null


static func parse_and_play(engine: ChessEngine, san: String) -> ChessMove:
	var m := parse(engine, san)
	if m == null:
		return null
	return engine.apply_move(m)


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
