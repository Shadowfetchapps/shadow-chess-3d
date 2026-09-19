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
	var cr := ""
	if engine.castling & ChessTypes.WK:
		cr += "K"
	if engine.castling & ChessTypes.WQ:
		cr += "Q"
	if engine.castling & ChessTypes.BK:
		cr += "k"
	if engine.castling & ChessTypes.BQ:
		cr += "q"
	if cr.is_empty():
		cr = "-"
	var ep := ChessTypes.algebraic(engine.ep_square) if engine.ep_square >= 0 else "-"
	return "%s %s %s %s %d %d" % [board, stm, cr, ep, engine.halfmove, engine.fullmove]


static func parse(engine: ChessEngine, fen: String) -> bool:
	var parts := fen.strip_edges().split(" ")
	if parts.size() < 4:
		return false
	engine.clear()
	var ranks := parts[0].split("/")
	if ranks.size() != 8:
		return false
	for i in 8:
		var rank := 7 - i
		var file := 0
		for j in ranks[i].length():
			var ch := ranks[i].substr(j, 1)
			if ch >= "1" and ch <= "8":
				file += int(ch)
			else:
				var packed := _parse_piece(ch)
				if packed < 0 or file > 7:
					return false
				engine.squares[ChessTypes.sq(file, rank)] = packed
				file += 1
		if file != 8:
			return false
	engine.side_to_move = ChessTypes.WHITE if parts[1] == "w" else ChessTypes.BLACK
	engine.castling = 0
	if parts[2] != "-":
		for j in parts[2].length():
			var ch := parts[2].substr(j, 1)
			match ch:
				"K":
					engine.castling |= ChessTypes.WK
				"Q":
					engine.castling |= ChessTypes.WQ
				"k":
					engine.castling |= ChessTypes.BK
				"q":
					engine.castling |= ChessTypes.BQ
	engine.ep_square = -1 if parts[3] == "-" else ChessTypes.parse_square(parts[3])
	engine.halfmove = int(parts[4]) if parts.size() > 4 else 0
	engine.fullmove = int(parts[5]) if parts.size() > 5 else 1
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
