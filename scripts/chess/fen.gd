class_name Fen
extends RefCounted


static func dump(engine: ChessEngine) -> String:
	var rows: PackedStringArray = PackedStringArray()
	for rank in range(7, -1, -1):
		var empty := 0
		var row := ""
		for file in 8:
			var p := engine.squares[ChessTypes.sq(file, rank)]
			if p == 0:
				empty += 1
			else:
				if empty > 0:
					row += str(empty)
					empty = 0
				row += ChessTypes.piece_char(p)
		if empty > 0:
			row += str(empty)
		rows.append(row)
	var board := "/".join(rows)
	var stm := "w" if engine.side_to_move == ChessTypes.WHITE else "b"
	var ep := ChessTypes.algebraic(engine.ep_square) if engine.ep_square >= 0 else "-"
	return "%s %s %s %s %d %d" % [board, stm, castling_string(engine.castling), ep, engine.halfmove, engine.fullmove]


static func castling_string(rights: int) -> String:
	var cr := ""
	if rights & ChessTypes.WK:
		cr += "K"
	if rights & ChessTypes.WQ:
		cr += "Q"
	if rights & ChessTypes.BK:
		cr += "k"
	if rights & ChessTypes.BQ:
		cr += "q"
	return "-" if cr.is_empty() else cr


## Parses a FEN into a Dictionary without touching any engine.
## Keys: ok, error, squares, side, castling (sanitized), ep, halfmove, fullmove.
static func decode(fen: String) -> Dictionary:
	var out := {"ok": false, "error": ""}
	var parts := fen.strip_edges().split(" ", false)
	if parts.size() < 4 or parts.size() > 6:
		out.error = "FEN needs 4 to 6 space-separated fields (found %d)" % parts.size()
		return out
	var squares := PackedInt32Array()
	squares.resize(64)
	var ranks := parts[0].split("/")
	if ranks.size() != 8:
		out.error = "Board must have 8 ranks separated by '/' (found %d)" % ranks.size()
		return out
	for i in 8:
		var rank := 7 - i
		var file := 0
		for j in ranks[i].length():
			var ch := ranks[i].substr(j, 1)
			if ch >= "1" and ch <= "8":
				file += int(ch)
			else:
				var packed := _parse_piece(ch)
				if packed < 0:
					out.error = "Unexpected character '%s' on rank %d" % [ch, rank + 1]
					return out
				if file > 7:
					out.error = "Rank %d has more than 8 squares" % (rank + 1)
					return out
				squares[ChessTypes.sq(file, rank)] = packed
				file += 1
			if file > 8:
				out.error = "Rank %d has more than 8 squares" % (rank + 1)
				return out
		if file != 8:
			out.error = "Rank %d has %d squares instead of 8" % [rank + 1, file]
			return out
	var side := -1
	match parts[1]:
		"w":
			side = ChessTypes.WHITE
		"b":
			side = ChessTypes.BLACK
		_:
			out.error = "Side to move must be 'w' or 'b' (found '%s')" % parts[1]
			return out
	var castling := 0
	if parts[2] != "-":
		for j in parts[2].length():
			match parts[2].substr(j, 1):
				"K":
					castling |= ChessTypes.WK
				"Q":
					castling |= ChessTypes.WQ
				"k":
					castling |= ChessTypes.BK
				"q":
					castling |= ChessTypes.BQ
				_:
					out.error = "Bad castling field '%s'" % parts[2]
					return out
	var ep := -1
	if parts[3] != "-":
		ep = ChessTypes.parse_square(parts[3])
		if ep < 0 or parts[3].length() != 2:
			out.error = "Bad en-passant square '%s'" % parts[3]
			return out
	var halfmove := 0
	var fullmove := 1
	if parts.size() > 4:
		if not parts[4].is_valid_int() or int(parts[4]) < 0:
			out.error = "Halfmove clock must be a non-negative number (found '%s')" % parts[4]
			return out
		halfmove = int(parts[4])
	if parts.size() > 5:
		if not parts[5].is_valid_int() or int(parts[5]) < 0:
			out.error = "Fullmove number must be a positive number (found '%s')" % parts[5]
			return out
		fullmove = maxi(1, int(parts[5]))
	var err := _check_position(squares, side, ep)
	if not err.is_empty():
		out.error = err
		return out
	out.ok = true
	out.squares = squares
	out.side = side
	out.castling = sanitize_castling(squares, castling)
	out.ep = ep
	out.halfmove = halfmove
	out.fullmove = fullmove
	return out


static func validate(fen: String) -> String:
	return str(decode(fen).error)


static func sanitize_castling(squares: PackedInt32Array, rights: int) -> int:
	var wk := ChessTypes.pack(ChessTypes.KING, ChessTypes.WHITE)
	var bk := ChessTypes.pack(ChessTypes.KING, ChessTypes.BLACK)
	var wr := ChessTypes.pack(ChessTypes.ROOK, ChessTypes.WHITE)
	var br := ChessTypes.pack(ChessTypes.ROOK, ChessTypes.BLACK)
	if squares[4] != wk:
		rights &= ~(ChessTypes.WK | ChessTypes.WQ)
	if squares[60] != bk:
		rights &= ~(ChessTypes.BK | ChessTypes.BQ)
	if squares[7] != wr:
		rights &= ~ChessTypes.WK
	if squares[0] != wr:
		rights &= ~ChessTypes.WQ
	if squares[63] != br:
		rights &= ~ChessTypes.BK
	if squares[56] != br:
		rights &= ~ChessTypes.BQ
	return rights


static func _check_position(squares: PackedInt32Array, side: int, ep: int) -> String:
	var kings: Array[int] = [0, 0]
	var king_sq: Array[int] = [-1, -1]
	var pieces: Array[int] = [0, 0]
	var pawns: Array[int] = [0, 0]
	for s in 64:
		var p := squares[s]
		if p == 0:
			continue
		var c := ChessTypes.pcolor(p)
		var t := ChessTypes.ptype(p)
		pieces[c] += 1
		if t == ChessTypes.KING:
			kings[c] += 1
			king_sq[c] = s
		elif t == ChessTypes.PAWN:
			pawns[c] += 1
			var r := ChessTypes.rank_of(s)
			if r == 0 or r == 7:
				return "Pawn on %s: pawns cannot stand on the first or last rank" % ChessTypes.algebraic(s)
	for c in 2:
		if kings[c] != 1:
			return "%s must have exactly one king (found %d)" % [ChessTypes.side_name(c), kings[c]]
		if pieces[c] > 16:
			return "%s has more than 16 pieces" % ChessTypes.side_name(c)
		if pawns[c] > 8:
			return "%s has more than 8 pawns" % ChessTypes.side_name(c)
	var other := ChessTypes.opp(side)
	if ChessEngine.square_attacked(squares, king_sq[other], side):
		return "%s is in check but it is %s's move" % [ChessTypes.side_name(other), ChessTypes.side_name(side)]
	if ep >= 0:
		var want_rank := 5 if side == ChessTypes.WHITE else 2
		var dir := 8 if side == ChessTypes.WHITE else -8
		var pawn := ChessTypes.pack(ChessTypes.PAWN, other)
		if ChessTypes.rank_of(ep) != want_rank or squares[ep] != 0 or squares[ep + dir] != 0 or squares[ep - dir] != pawn:
			return "Impossible en-passant square %s" % ChessTypes.algebraic(ep)
	return ""


static func parse(engine: ChessEngine, fen: String) -> bool:
	var d := decode(fen)
	if not d.ok:
		return false
	engine.clear()
	var sq: PackedInt32Array = d.squares
	for i in 64:
		engine.squares[i] = sq[i]
	engine.side_to_move = d.side
	engine.castling = d.castling
	engine.ep_square = d.ep
	engine.halfmove = d.halfmove
	engine.fullmove = d.fullmove
	engine.result = ChessEngine.Result.NONE
	return true


static func _parse_piece(ch: String) -> int:
	var upper := ch.to_upper()
	var type := ChessTypes.NONE
	match upper:
		"P":
			type = ChessTypes.PAWN
		"N":
			type = ChessTypes.KNIGHT
		"B":
			type = ChessTypes.BISHOP
		"R":
			type = ChessTypes.ROOK
		"Q":
			type = ChessTypes.QUEEN
		"K":
			type = ChessTypes.KING
		_:
			return -1
	var color := ChessTypes.WHITE if ch == upper else ChessTypes.BLACK
	return ChessTypes.pack(type, color)
