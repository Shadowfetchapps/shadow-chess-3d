class_name ChessEngine
extends RefCounted

enum Result {
	NONE,
	CHECKMATE,
	STALEMATE,
	DRAW_50,
	DRAW_MATERIAL,
	DRAW_AGREED,
	RESIGNATION,
	TIMEOUT,
}

var squares: PackedInt32Array = PackedInt32Array()
var side_to_move: int = ChessTypes.WHITE
var castling: int = ChessTypes.WK | ChessTypes.WQ | ChessTypes.BK | ChessTypes.BQ
var ep_square: int = -1
var halfmove: int = 0
var fullmove: int = 1
var history: Array[ChessMove] = []
var redo_stack: Array[ChessMove] = []
var result: Result = Result.NONE
var result_side: int = -1
var resigned_side: int = -1
var timed_out_side: int = -1

const _ROOK_HOME: Array[int] = [0, 7, 56, 63]
const _ROOK_MASK: Array[int] = [ChessTypes.WQ, ChessTypes.WK, ChessTypes.BQ, ChessTypes.BK]


func _init() -> void:
	squares.resize(64)
	reset()


func reset() -> void:
	from_fen(ChessTypes.START_FEN)


func clear() -> void:
	for i in 64:
		squares[i] = 0
	side_to_move = ChessTypes.WHITE
	castling = 0
	ep_square = -1
	halfmove = 0
	fullmove = 1
	history.clear()
	redo_stack.clear()
	result = Result.NONE
	result_side = -1
	resigned_side = -1
	timed_out_side = -1


func clone() -> ChessEngine:
	var e := ChessEngine.new()
	e.squares = squares.duplicate()
	e.side_to_move = side_to_move
	e.castling = castling
	e.ep_square = ep_square
	e.halfmove = halfmove
	e.fullmove = fullmove
	e.result = result
	e.result_side = result_side
	e.resigned_side = resigned_side
	e.timed_out_side = timed_out_side
	e.history.clear()
	for m in history:
		e.history.append(m.duplicate_move())
	e.redo_stack.clear()
	for m in redo_stack:
		e.redo_stack.append(m.duplicate_move())
	return e


func piece_at(sq: int) -> int:
	if sq < 0 or sq > 63:
		return 0
	return squares[sq]


func find_king(side: int) -> int:
	var want := ChessTypes.pack(ChessTypes.KING, side)
	for i in 64:
		if squares[i] == want:
			return i
	return -1


func in_check(side: int = -1) -> bool:
	if side < 0:
		side = side_to_move
	var k := find_king(side)
	if k < 0:
		return false
	return is_square_attacked(k, ChessTypes.opp(side))


func is_square_attacked(sq: int, by_side: int) -> bool:
	var f := ChessTypes.file_of(sq)
	var r := ChessTypes.rank_of(sq)
	var pawn_rank := r - 1 if by_side == ChessTypes.WHITE else r + 1
	if pawn_rank >= 0 and pawn_rank < 8:
		for df: int in [-1, 1]:
			var pf: int = f + df
			if pf >= 0 and pf < 8:
				var p := squares[ChessTypes.sq(pf, pawn_rank)]
				if ChessTypes.ptype(p) == ChessTypes.PAWN and ChessTypes.pcolor(p) == by_side:
					return true
	for d: Vector2i in ChessTypes.KNIGHT_DELTAS:
		var nf: int = f + d.x
		var nr: int = r + d.y
		if ChessTypes.in_board(nf, nr):
			var p := squares[ChessTypes.sq(nf, nr)]
			if ChessTypes.ptype(p) == ChessTypes.KNIGHT and ChessTypes.pcolor(p) == by_side:
				return true
	for d: Vector2i in ChessTypes.KING_DELTAS:
		var kf: int = f + d.x
		var kr: int = r + d.y
		if ChessTypes.in_board(kf, kr):
			var p := squares[ChessTypes.sq(kf, kr)]
			if ChessTypes.ptype(p) == ChessTypes.KING and ChessTypes.pcolor(p) == by_side:
				return true
	if _slider_attacks(f, r, ChessTypes.BISHOP_DIRS, by_side, true):
		return true
	if _slider_attacks(f, r, ChessTypes.ROOK_DIRS, by_side, false):
		return true
	return false


func _slider_attacks(f: int, r: int, dirs: Array[Vector2i], by_side: int, diagonal: bool) -> bool:
	for d: Vector2i in dirs:
		var nf: int = f + d.x
		var nr: int = r + d.y
		while ChessTypes.in_board(nf, nr):
			var p := squares[ChessTypes.sq(nf, nr)]
			if p != 0:
				if ChessTypes.pcolor(p) == by_side:
					var t := ChessTypes.ptype(p)
					if t == ChessTypes.QUEEN or (diagonal and t == ChessTypes.BISHOP) or (not diagonal and t == ChessTypes.ROOK):
						return true
				break
			nf += d.x
			nr += d.y
	return false


func generate_legal_moves() -> Array[ChessMove]:
	var legal: Array[ChessMove] = []
	for m in _generate_pseudo():
		_make(m)
		if not in_check(ChessTypes.opp(side_to_move)):
			legal.append(m)
		_unmake(m)
	return legal


func generate_legal_from(from_sq: int) -> Array[ChessMove]:
	var out: Array[ChessMove] = []
	for m in generate_legal_moves():
		if m.from_sq == from_sq:
			out.append(m)
	return out


func find_move(from_sq: int, to_sq: int, promo: int = 0) -> ChessMove:
	for m in generate_legal_moves():
		if m.matches(from_sq, to_sq, promo):
			if promo != 0 and m.is_promotion() and m.promotion != promo:
				continue
			if promo == 0 and m.is_promotion() and m.promotion != ChessTypes.QUEEN:
				continue
			return m
	return null


func is_legal(from_sq: int, to_sq: int, promo: int = 0) -> bool:
	return find_move(from_sq, to_sq, promo) != null


func play(from_sq: int, to_sq: int, promo: int = 0) -> ChessMove:
	var m := find_move(from_sq, to_sq, promo)
	if m == null:
		return null
	return apply_move(m)


func apply_move(m: ChessMove, clear_redo: bool = true) -> ChessMove:
	if result != Result.NONE:
		return null
	m.san = San.encode(self, m)
	_make(m)
	if clear_redo:
		redo_stack.clear()
	history.append(m)
	_refresh_result()
	if result == Result.CHECKMATE:
		m.san += "#"
	elif in_check():
		m.san += "+"
	m.uci = m.to_uci()
	return m


func undo() -> ChessMove:
	if history.is_empty():
		return null
	var m: ChessMove = history.pop_back()
	_unmake(m)
	redo_stack.append(m)
	result = Result.NONE
	result_side = -1
	resigned_side = -1
	timed_out_side = -1
	return m


func redo() -> ChessMove:
	if redo_stack.is_empty():
		return null
	var m: ChessMove = redo_stack.pop_back()
	return apply_move(m, false)


func can_undo() -> bool:
	return not history.is_empty() and result != Result.RESIGNATION and result != Result.TIMEOUT


func can_redo() -> bool:
	return not redo_stack.is_empty() and result == Result.NONE


func resign(side: int) -> void:
	result = Result.RESIGNATION
	resigned_side = side
	result_side = ChessTypes.opp(side)


func flag_timeout(side: int) -> void:
	result = Result.TIMEOUT
	timed_out_side = side
	result_side = ChessTypes.opp(side)


func agree_draw() -> void:
	result = Result.DRAW_AGREED
	result_side = -1


func game_over() -> bool:
	return result != Result.NONE


func result_text() -> String:
	match result:
		Result.CHECKMATE:
			return "%s wins by checkmate" % ChessTypes.side_name(result_side)
		Result.STALEMATE:
			return "Draw by stalemate"
		Result.DRAW_50:
			return "Draw by fifty-move rule"
		Result.DRAW_MATERIAL:
			return "Draw by insufficient material"
		Result.DRAW_AGREED:
			return "Draw by agreement"
		Result.RESIGNATION:
			return "%s resigns — %s wins" % [ChessTypes.side_name(resigned_side), ChessTypes.side_name(result_side)]
		Result.TIMEOUT:
			return "%s flagged — %s wins" % [ChessTypes.side_name(timed_out_side), ChessTypes.side_name(result_side)]
		_:
			if in_check():
				return "%s is in check" % ChessTypes.side_name(side_to_move)
			return "In progress"


func _refresh_result() -> void:
	var legal := generate_legal_moves()
	if legal.is_empty():
		if in_check():
			result = Result.CHECKMATE
			result_side = ChessTypes.opp(side_to_move)
		else:
			result = Result.STALEMATE
			result_side = -1
		return
	if _insufficient_material():
		result = Result.DRAW_MATERIAL
		result_side = -1
		return
	if halfmove >= 100:
		result = Result.DRAW_50
		result_side = -1
		return
	result = Result.NONE
	result_side = -1


func _insufficient_material() -> bool:
	var white_minors: Array[int] = []
	var black_minors: Array[int] = []
	var white_bishop_dark := 0
	var black_bishop_dark := 0
	for i in 64:
		var p := squares[i]
		if p == 0:
			continue
		var t := ChessTypes.ptype(p)
		var c := ChessTypes.pcolor(p)
		if t == ChessTypes.PAWN or t == ChessTypes.ROOK or t == ChessTypes.QUEEN:
			return false
		if t == ChessTypes.KNIGHT or t == ChessTypes.BISHOP:
			if c == ChessTypes.WHITE:
				white_minors.append(t)
				if t == ChessTypes.BISHOP:
					white_bishop_dark += (ChessTypes.file_of(i) + ChessTypes.rank_of(i)) & 1
			else:
				black_minors.append(t)
				if t == ChessTypes.BISHOP:
					black_bishop_dark += (ChessTypes.file_of(i) + ChessTypes.rank_of(i)) & 1
	if white_minors.is_empty() and black_minors.is_empty():
		return true
	if white_minors.size() == 1 and black_minors.is_empty():
		return true
	if black_minors.size() == 1 and white_minors.is_empty():
		return true
	return false


func _generate_pseudo() -> Array[ChessMove]:
	var moves: Array[ChessMove] = []
	for sq in 64:
		var p := squares[sq]
		if p == 0 or ChessTypes.pcolor(p) != side_to_move:
			continue
		match ChessTypes.ptype(p):
			ChessTypes.PAWN:
				_gen_pawn(sq, moves)
			ChessTypes.KNIGHT:
				_gen_leaper(sq, ChessTypes.KNIGHT, ChessTypes.KNIGHT_DELTAS, moves)
			ChessTypes.BISHOP:
				_gen_slider(sq, ChessTypes.BISHOP, ChessTypes.BISHOP_DIRS, moves)
			ChessTypes.ROOK:
				_gen_slider(sq, ChessTypes.ROOK, ChessTypes.ROOK_DIRS, moves)
			ChessTypes.QUEEN:
				_gen_slider(sq, ChessTypes.QUEEN, ChessTypes.BISHOP_DIRS, moves)
				_gen_slider(sq, ChessTypes.QUEEN, ChessTypes.ROOK_DIRS, moves)
			ChessTypes.KING:
				_gen_leaper(sq, ChessTypes.KING, ChessTypes.KING_DELTAS, moves)
				_gen_castling(sq, moves)
	return moves


func _gen_pawn(sq: int, moves: Array[ChessMove]) -> void:
	var f := ChessTypes.file_of(sq)
	var r := ChessTypes.rank_of(sq)
	var dir := 1 if side_to_move == ChessTypes.WHITE else -1
	var start_rank := 1 if side_to_move == ChessTypes.WHITE else 6
	var promo_rank := 7 if side_to_move == ChessTypes.WHITE else 0
	var nr := r + dir
	if nr < 0 or nr > 7:
		return
	var fwd := ChessTypes.sq(f, nr)
	if squares[fwd] == 0:
		if nr == promo_rank:
			_add_promos(sq, fwd, 0, fwd, moves)
		else:
			moves.append(_build(sq, fwd, ChessTypes.PAWN, 0, 0, 0, -1))
			if r == start_rank:
				var nr2 := r + dir * 2
				var fwd2 := ChessTypes.sq(f, nr2)
				if squares[fwd2] == 0:
					moves.append(_build(sq, fwd2, ChessTypes.PAWN, 0, ChessTypes.FLAG_DOUBLE, 0, -1))
	for df: int in [-1, 1]:
		var cf: int = f + df
		if not ChessTypes.in_board(cf, nr):
			continue
		var to := ChessTypes.sq(cf, nr)
		var dest := squares[to]
		if dest != 0 and ChessTypes.pcolor(dest) != side_to_move and ChessTypes.ptype(dest) != ChessTypes.KING:
			if nr == promo_rank:
				_add_promos(sq, to, dest, to, moves)
			else:
				moves.append(_build(sq, to, ChessTypes.PAWN, dest, ChessTypes.FLAG_CAPTURE, 0, to))
		elif to == ep_square and ep_square >= 0:
			var cap_sq := ChessTypes.sq(cf, r)
			var cap := squares[cap_sq]
			if ChessTypes.ptype(cap) == ChessTypes.PAWN and ChessTypes.pcolor(cap) != side_to_move:
				moves.append(_build(sq, to, ChessTypes.PAWN, cap, ChessTypes.FLAG_CAPTURE | ChessTypes.FLAG_EP, 0, cap_sq))


func _add_promos(from_sq: int, to_sq: int, captured: int, cap_sq: int, moves: Array[ChessMove]) -> void:
	var flags := ChessTypes.FLAG_PROMO
	if captured != 0:
		flags |= ChessTypes.FLAG_CAPTURE
	for t: int in [ChessTypes.QUEEN, ChessTypes.ROOK, ChessTypes.BISHOP, ChessTypes.KNIGHT]:
		moves.append(_build(from_sq, to_sq, ChessTypes.PAWN, captured, flags, t, cap_sq if captured != 0 else -1))


func _gen_leaper(sq: int, piece: int, deltas: Array[Vector2i], moves: Array[ChessMove]) -> void:
	var f := ChessTypes.file_of(sq)
	var r := ChessTypes.rank_of(sq)
	for d: Vector2i in deltas:
		var nf: int = f + d.x
		var nr: int = r + d.y
		if not ChessTypes.in_board(nf, nr):
			continue
		var to := ChessTypes.sq(nf, nr)
		var dest := squares[to]
		if dest == 0:
			moves.append(_build(sq, to, piece, 0, 0, 0, -1))
		elif ChessTypes.pcolor(dest) != side_to_move and ChessTypes.ptype(dest) != ChessTypes.KING:
			moves.append(_build(sq, to, piece, dest, ChessTypes.FLAG_CAPTURE, 0, to))


func _gen_slider(sq: int, piece: int, dirs: Array[Vector2i], moves: Array[ChessMove]) -> void:
	var f := ChessTypes.file_of(sq)
	var r := ChessTypes.rank_of(sq)
	for d: Vector2i in dirs:
		var nf: int = f + d.x
		var nr: int = r + d.y
		while ChessTypes.in_board(nf, nr):
			var to := ChessTypes.sq(nf, nr)
			var dest := squares[to]
			if dest == 0:
				moves.append(_build(sq, to, piece, 0, 0, 0, -1))
			else:
				if ChessTypes.pcolor(dest) != side_to_move and ChessTypes.ptype(dest) != ChessTypes.KING:
					moves.append(_build(sq, to, piece, dest, ChessTypes.FLAG_CAPTURE, 0, to))
				break
			nf += d.x
			nr += d.y


func _gen_castling(sq: int, moves: Array[ChessMove]) -> void:
	if in_check(side_to_move):
		return
	if side_to_move == ChessTypes.WHITE and sq != 4:
		return
	if side_to_move == ChessTypes.BLACK and sq != 60:
		return
	var enemy := ChessTypes.opp(side_to_move)
	if side_to_move == ChessTypes.WHITE:
		if (castling & ChessTypes.WK) != 0 and squares[5] == 0 and squares[6] == 0 and ChessTypes.ptype(squares[7]) == ChessTypes.ROOK and ChessTypes.pcolor(squares[7]) == ChessTypes.WHITE:
			if not is_square_attacked(5, enemy) and not is_square_attacked(6, enemy):
				moves.append(_build(4, 6, ChessTypes.KING, 0, ChessTypes.FLAG_CASTLE_K, 0, -1))
		if (castling & ChessTypes.WQ) != 0 and squares[3] == 0 and squares[2] == 0 and squares[1] == 0 and ChessTypes.ptype(squares[0]) == ChessTypes.ROOK and ChessTypes.pcolor(squares[0]) == ChessTypes.WHITE:
			if not is_square_attacked(3, enemy) and not is_square_attacked(2, enemy):
				moves.append(_build(4, 2, ChessTypes.KING, 0, ChessTypes.FLAG_CASTLE_Q, 0, -1))
	else:
		if (castling & ChessTypes.BK) != 0 and squares[61] == 0 and squares[62] == 0 and ChessTypes.ptype(squares[63]) == ChessTypes.ROOK and ChessTypes.pcolor(squares[63]) == ChessTypes.BLACK:
			if not is_square_attacked(61, enemy) and not is_square_attacked(62, enemy):
				moves.append(_build(60, 62, ChessTypes.KING, 0, ChessTypes.FLAG_CASTLE_K, 0, -1))
		if (castling & ChessTypes.BQ) != 0 and squares[59] == 0 and squares[58] == 0 and squares[57] == 0 and ChessTypes.ptype(squares[56]) == ChessTypes.ROOK and ChessTypes.pcolor(squares[56]) == ChessTypes.BLACK:
			if not is_square_attacked(59, enemy) and not is_square_attacked(58, enemy):
				moves.append(_build(60, 58, ChessTypes.KING, 0, ChessTypes.FLAG_CASTLE_Q, 0, -1))


func _build(from_sq: int, to_sq: int, piece: int, captured: int, flags: int, promo: int, cap_sq: int) -> ChessMove:
	var m := ChessMove.new()
	m.from_sq = from_sq
	m.to_sq = to_sq
	m.piece = piece
	m.captured = captured
	m.captured_sq = cap_sq
	m.promotion = promo
	m.flags = flags
	return m


func _make(m: ChessMove) -> void:
	m.prev_castling = castling
	m.prev_ep = ep_square
	m.prev_halfmove = halfmove
	var moving := squares[m.from_sq]
	squares[m.from_sq] = 0
	if m.is_en_passant():
		squares[m.captured_sq] = 0
		squares[m.to_sq] = moving
	else:
		squares[m.to_sq] = moving
	if m.is_promotion():
		squares[m.to_sq] = ChessTypes.pack(m.promotion, side_to_move)
	if m.is_castle():
		if m.to_sq == m.from_sq + 2:
			squares[m.from_sq + 1] = squares[m.from_sq + 3]
			squares[m.from_sq + 3] = 0
		else:
			squares[m.from_sq - 1] = squares[m.from_sq - 4]
			squares[m.from_sq - 4] = 0
	_update_castling_rights(m)
	if m.is_double_pawn():
		ep_square = int((m.from_sq + m.to_sq) / 2.0)
	else:
		ep_square = -1
	if ChessTypes.ptype(moving) == ChessTypes.PAWN or m.captured != 0:
		halfmove = 0
	else:
		halfmove += 1
	if side_to_move == ChessTypes.BLACK:
		fullmove += 1
	side_to_move = ChessTypes.opp(side_to_move)


func _unmake(m: ChessMove) -> void:
	side_to_move = ChessTypes.opp(side_to_move)
	if side_to_move == ChessTypes.BLACK:
		fullmove -= 1
	castling = m.prev_castling
	ep_square = m.prev_ep
	halfmove = m.prev_halfmove
	var moving := ChessTypes.pack(m.piece, side_to_move)
	if m.is_castle():
		if m.to_sq == m.from_sq + 2:
			squares[m.from_sq + 3] = squares[m.from_sq + 1]
			squares[m.from_sq + 1] = 0
		else:
			squares[m.from_sq - 4] = squares[m.from_sq - 1]
			squares[m.from_sq - 1] = 0
	squares[m.from_sq] = moving
	squares[m.to_sq] = 0
	if m.is_en_passant():
		squares[m.captured_sq] = m.captured
	elif m.captured != 0:
		squares[m.to_sq] = m.captured


func _update_castling_rights(m: ChessMove) -> void:
	if m.piece == ChessTypes.KING:
		if side_to_move == ChessTypes.WHITE:
			castling &= ~(ChessTypes.WK | ChessTypes.WQ)
		else:
			castling &= ~(ChessTypes.BK | ChessTypes.BQ)
	_clear_rook_right(m.from_sq)
	_clear_rook_right(m.to_sq)
	if m.captured_sq >= 0:
		_clear_rook_right(m.captured_sq)


func _clear_rook_right(sq: int) -> void:
	for i in _ROOK_HOME.size():
		if _ROOK_HOME[i] == sq:
			castling &= ~_ROOK_MASK[i]
			return


func to_fen() -> String:
	return Fen.dump(self)


func from_fen(fen: String) -> bool:
	if not Fen.parse(self, fen):
		return false
	_refresh_result()
	return true


func make_raw(m: ChessMove) -> void:
	_make(m)


func unmake_raw(m: ChessMove) -> void:
	_unmake(m)


func perft(depth: int) -> int:
	if depth <= 0:
		return 1
	var n := 0
	for m in generate_legal_moves():
		_make(m)
		n += perft(depth - 1)
		_unmake(m)
	return n


func san_history() -> PackedStringArray:
	var out := PackedStringArray()
	for m in history:
		out.append(m.san if not m.san.is_empty() else m.to_uci())
	return out


func numbered_san() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for i in history.size():
		if i % 2 == 0:
			parts.append("%d." % (i / 2 + 1))
		parts.append(history[i].san if not history[i].san.is_empty() else history[i].to_uci())
	return " ".join(parts)
