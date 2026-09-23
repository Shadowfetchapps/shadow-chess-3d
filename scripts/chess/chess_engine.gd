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
	DRAW_REPETITION,
	DRAW_TIMEOUT_MATERIAL,
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
var hash_key: int = 0
var start_fen: String = ChessTypes.START_FEN
var last_fen_error: String = ""

var _keys: PackedInt64Array = PackedInt64Array()
var _kings: PackedInt32Array = PackedInt32Array([-1, -1])
var _start_side: int = ChessTypes.WHITE
var _start_fullmove: int = 1
var _zp: PackedInt64Array
var _zc: PackedInt64Array
var _ze: PackedInt64Array
var _zs: int = 0

const _ROOK_HOME: Array[int] = [0, 7, 56, 63]
const _ROOK_MASK: Array[int] = [ChessTypes.WQ, ChessTypes.WK, ChessTypes.BQ, ChessTypes.BK]
const _VALUE: Array[int] = [0, 1, 3, 3, 5, 9, 0]
const _KN_DF: Array[int] = [1, 2, -1, -2, 1, 2, -1, -2]
const _KN_DR: Array[int] = [2, 1, 2, 1, -2, -1, -2, -1]
const _KG_DF: Array[int] = [1, -1, 0, 0, 1, 1, -1, -1]
const _KG_DR: Array[int] = [0, 0, 1, -1, 1, -1, 1, -1]


func _init() -> void:
	squares.resize(64)
	ChessZobrist.ensure()
	_zp = ChessZobrist.piece_keys
	_zc = ChessZobrist.castle_keys
	_ze = ChessZobrist.ep_keys
	_zs = ChessZobrist.side_key
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
	_kings[0] = -1
	_kings[1] = -1
	hash_key = _compute_hash()
	_keys = PackedInt64Array([hash_key])


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
	e.hash_key = hash_key
	e.start_fen = start_fen
	e._keys = _keys.duplicate()
	e._kings = _kings.duplicate()
	e._start_side = _start_side
	e._start_fullmove = _start_fullmove
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
	var k := _kings[side]
	if k >= 0 and squares[k] == want:
		return k
	for i in 64:
		if squares[i] == want:
			_kings[side] = i
			return i
	_kings[side] = -1
	return -1


func in_check(side: int = -1) -> bool:
	if side < 0:
		side = side_to_move
	var k := find_king(side)
	if k < 0:
		return false
	return square_attacked(squares, k, ChessTypes.opp(side))


func is_square_attacked(sq: int, by_side: int) -> bool:
	return square_attacked(squares, sq, by_side)


static func square_attacked(b: PackedInt32Array, sq: int, by_side: int) -> bool:
	var f := sq & 7
	var r := sq >> 3
	var col := by_side << 4
	var pawn := ChessTypes.PAWN | col
	if by_side == ChessTypes.WHITE:
		if r > 0:
			if f > 0 and b[sq - 9] == pawn:
				return true
			if f < 7 and b[sq - 7] == pawn:
				return true
	elif r < 7:
		if f > 0 and b[sq + 7] == pawn:
			return true
		if f < 7 and b[sq + 9] == pawn:
			return true
	var knight := ChessTypes.KNIGHT | col
	var king := ChessTypes.KING | col
	for i in 8:
		var nf := f + _KN_DF[i]
		var nr := r + _KN_DR[i]
		if nf >= 0 and nf < 8 and nr >= 0 and nr < 8 and b[(nr << 3) | nf] == knight:
			return true
		nf = f + _KG_DF[i]
		nr = r + _KG_DR[i]
		if nf >= 0 and nf < 8 and nr >= 0 and nr < 8 and b[(nr << 3) | nf] == king:
			return true
	var queen := ChessTypes.QUEEN | col
	var rook := ChessTypes.ROOK | col
	var bishop := ChessTypes.BISHOP | col
	for i in 8:
		var df := _KG_DF[i]
		var dr := _KG_DR[i]
		var slider := rook if i < 4 else bishop
		var nf := f + df
		var nr := r + dr
		while nf >= 0 and nf < 8 and nr >= 0 and nr < 8:
			var p := b[(nr << 3) | nf]
			if p != 0:
				if p == queen or p == slider:
					return true
				break
			nf += df
			nr += dr
	return false


func generate_legal_moves() -> Array[ChessMove]:
	var legal: Array[ChessMove] = []
	var us := side_to_move
	var ksq := find_king(us)
	var checked := ksq >= 0 and square_attacked(squares, ksq, ChessTypes.opp(us))
	var kf := ksq & 7
	var kr := ksq >> 3
	for m in _generate_pseudo(checked):
		if ksq >= 0 and not checked and m.piece != ChessTypes.KING and (m.flags & ChessTypes.FLAG_EP) == 0:
			var df := (m.from_sq & 7) - kf
			var dr := (m.from_sq >> 3) - kr
			if df != 0 and dr != 0 and df != dr and df != -dr:
				legal.append(m)
				continue
		_make(m)
		if not in_check(us):
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


func find_uci(uci: String) -> ChessMove:
	var u := uci.strip_edges().to_lower()
	if u.length() < 4:
		return null
	for m in generate_legal_moves():
		if m.to_uci() == u:
			return m
	return null


func is_legal(from_sq: int, to_sq: int, promo: int = 0) -> bool:
	return find_move(from_sq, to_sq, promo) != null


func play(from_sq: int, to_sq: int, promo: int = 0) -> ChessMove:
	var m := find_move(from_sq, to_sq, promo)
	if m == null:
		return null
	return apply_move(m)


func play_uci(uci: String) -> ChessMove:
	var m := find_uci(uci)
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
	_keys.append(hash_key)
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
	if _keys.size() > 1:
		_keys.resize(_keys.size() - 1)
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
	return not history.is_empty() and result != Result.RESIGNATION and result != Result.TIMEOUT and result != Result.DRAW_TIMEOUT_MATERIAL


func can_redo() -> bool:
	return not redo_stack.is_empty() and result == Result.NONE


func resign(side: int) -> void:
	result = Result.RESIGNATION
	resigned_side = side
	result_side = ChessTypes.opp(side)


## FIDE 6.9: a flag fall is only a loss if the opponent could still checkmate.
func flag_timeout(side: int) -> void:
	timed_out_side = side
	var other := ChessTypes.opp(side)
	if has_mating_material(other):
		result = Result.TIMEOUT
		result_side = other
	else:
		result = Result.DRAW_TIMEOUT_MATERIAL
		result_side = -1


func agree_draw() -> void:
	result = Result.DRAW_AGREED
	result_side = -1


func game_over() -> bool:
	return result != Result.NONE


## False when `side` has only a king, or a king plus exactly one minor piece.
func has_mating_material(side: int) -> bool:
	var minors := 0
	for i in 64:
		var p := squares[i]
		if p == 0 or ChessTypes.pcolor(p) != side:
			continue
		match ChessTypes.ptype(p):
			ChessTypes.PAWN, ChessTypes.ROOK, ChessTypes.QUEEN:
				return true
			ChessTypes.KNIGHT, ChessTypes.BISHOP:
				minors += 1
	return minors >= 2


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
		Result.DRAW_REPETITION:
			return "Draw by threefold repetition"
		Result.RESIGNATION:
			return "%s resigns — %s wins" % [ChessTypes.side_name(resigned_side), ChessTypes.side_name(result_side)]
		Result.TIMEOUT:
			return "%s flagged — %s wins" % [ChessTypes.side_name(timed_out_side), ChessTypes.side_name(result_side)]
		Result.DRAW_TIMEOUT_MATERIAL:
			return "Draw — %s ran out of time, but %s cannot checkmate" % [ChessTypes.side_name(timed_out_side), ChessTypes.side_name(ChessTypes.opp(timed_out_side))]
		_:
			if in_check():
				return "%s is in check" % ChessTypes.side_name(side_to_move)
			return "In progress"


func result_reason() -> String:
	match result:
		Result.CHECKMATE:
			return "Checkmate"
		Result.STALEMATE:
			return "Stalemate"
		Result.DRAW_50:
			return "Fifty-move rule"
		Result.DRAW_MATERIAL:
			return "Insufficient material"
		Result.DRAW_AGREED:
			return "Agreement"
		Result.DRAW_REPETITION:
			return "Threefold repetition"
		Result.RESIGNATION:
			return "Resignation"
		Result.TIMEOUT:
			return "Time forfeit"
		Result.DRAW_TIMEOUT_MATERIAL:
			return "Timeout vs insufficient material"
		_:
			return ""


func result_token() -> String:
	match result:
		Result.CHECKMATE, Result.RESIGNATION, Result.TIMEOUT:
			return "1-0" if result_side == ChessTypes.WHITE else "0-1"
		Result.NONE:
			return "*"
		_:
			return "1/2-1/2"


func is_draw() -> bool:
	return result != Result.NONE and result_side < 0


func repetition_count() -> int:
	var n := _keys.size()
	var count := 1
	var top := n - 1
	if n > 0 and _keys[top] == hash_key:
		top -= 1
	var lo := maxi(0, n - 1 - halfmove)
	var i := top
	while i >= lo:
		if _keys[i] == hash_key:
			count += 1
		i -= 1
	return count


func position_keys() -> PackedInt64Array:
	return _keys.duplicate()


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
	result_side = -1
	if _insufficient_material():
		result = Result.DRAW_MATERIAL
	elif halfmove >= 100:
		result = Result.DRAW_50
	elif repetition_count() >= 3:
		result = Result.DRAW_REPETITION
	else:
		result = Result.NONE


func _insufficient_material() -> bool:
	var knights := 0
	var bishops := 0
	var light := 0
	for i in 64:
		var p := squares[i]
		if p == 0:
			continue
		match ChessTypes.ptype(p):
			ChessTypes.PAWN, ChessTypes.ROOK, ChessTypes.QUEEN:
				return false
			ChessTypes.KNIGHT:
				knights += 1
			ChessTypes.BISHOP:
				bishops += 1
				light += ((i & 7) + (i >> 3)) & 1
	if knights == 0:
		return light == 0 or light == bishops
	return knights == 1 and bishops == 0


## Piece types captured BY `color`, most valuable first.
func captured_by(color: int) -> Array[int]:
	var out: Array[int] = []
	for m in history:
		if m.captured != 0 and ChessTypes.pcolor(m.captured) != color:
			out.append(ChessTypes.ptype(m.captured))
	out.sort_custom(func(a: int, b: int) -> bool:
		if _VALUE[a] != _VALUE[b]:
			return _VALUE[a] > _VALUE[b]
		return a > b
	)
	return out


## White material minus Black material (Q9 R5 B3 N3 P1).
func material_diff() -> int:
	var d := 0
	for i in 64:
		var p := squares[i]
		if p != 0:
			d += _VALUE[ChessTypes.ptype(p)] * (1 if ChessTypes.pcolor(p) == ChessTypes.WHITE else -1)
	return d


func move_number_for_ply(ply: int) -> int:
	var off := 1 if _start_side == ChessTypes.BLACK else 0
	return _start_fullmove + ((ply + off) >> 1)


func is_white_ply(ply: int) -> bool:
	var off := 1 if _start_side == ChessTypes.BLACK else 0
	return ((ply + off) & 1) == 0


func start_side() -> int:
	return _start_side


func _generate_pseudo(checked: bool = false) -> Array[ChessMove]:
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
				if not checked:
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
				var fwd2 := ChessTypes.sq(f, r + dir * 2)
				if squares[fwd2] == 0:
					moves.append(_build(sq, fwd2, ChessTypes.PAWN, 0, ChessTypes.FLAG_DOUBLE, 0, -1))
	for side_step in 2:
		var cf: int = f - 1 + side_step * 2
		if cf < 0 or cf > 7:
			continue
		var to := ChessTypes.sq(cf, nr)
		var dest := squares[to]
		if dest != 0 and ChessTypes.pcolor(dest) != side_to_move and ChessTypes.ptype(dest) != ChessTypes.KING:
			if nr == promo_rank:
				_add_promos(sq, to, dest, to, moves)
			else:
				moves.append(_build(sq, to, ChessTypes.PAWN, dest, ChessTypes.FLAG_CAPTURE, 0, to))
		elif to == ep_square and ep_square >= 0 and dest == 0:
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
		if nf < 0 or nf > 7 or nr < 0 or nr > 7:
			continue
		var to := (nr << 3) | nf
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
		while nf >= 0 and nf < 8 and nr >= 0 and nr < 8:
			var to := (nr << 3) | nf
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
	if side_to_move == ChessTypes.WHITE and sq != 4:
		return
	if side_to_move == ChessTypes.BLACK and sq != 60:
		return
	var enemy := ChessTypes.opp(side_to_move)
	if side_to_move == ChessTypes.WHITE:
		if (castling & ChessTypes.WK) != 0 and squares[5] == 0 and squares[6] == 0 and ChessTypes.ptype(squares[7]) == ChessTypes.ROOK and ChessTypes.pcolor(squares[7]) == ChessTypes.WHITE:
			if not is_square_attacked(4, enemy) and not is_square_attacked(5, enemy) and not is_square_attacked(6, enemy):
				moves.append(_build(4, 6, ChessTypes.KING, 0, ChessTypes.FLAG_CASTLE_K, 0, -1))
		if (castling & ChessTypes.WQ) != 0 and squares[3] == 0 and squares[2] == 0 and squares[1] == 0 and ChessTypes.ptype(squares[0]) == ChessTypes.ROOK and ChessTypes.pcolor(squares[0]) == ChessTypes.WHITE:
			if not is_square_attacked(4, enemy) and not is_square_attacked(3, enemy) and not is_square_attacked(2, enemy):
				moves.append(_build(4, 2, ChessTypes.KING, 0, ChessTypes.FLAG_CASTLE_Q, 0, -1))
	else:
		if (castling & ChessTypes.BK) != 0 and squares[61] == 0 and squares[62] == 0 and ChessTypes.ptype(squares[63]) == ChessTypes.ROOK and ChessTypes.pcolor(squares[63]) == ChessTypes.BLACK:
			if not is_square_attacked(60, enemy) and not is_square_attacked(61, enemy) and not is_square_attacked(62, enemy):
				moves.append(_build(60, 62, ChessTypes.KING, 0, ChessTypes.FLAG_CASTLE_K, 0, -1))
		if (castling & ChessTypes.BQ) != 0 and squares[59] == 0 and squares[58] == 0 and squares[57] == 0 and ChessTypes.ptype(squares[56]) == ChessTypes.ROOK and ChessTypes.pcolor(squares[56]) == ChessTypes.BLACK:
			if not is_square_attacked(60, enemy) and not is_square_attacked(59, enemy) and not is_square_attacked(58, enemy):
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


func _zkey(p: int, sq: int) -> int:
	return _zp[((p >> 4) * 6 + (p & 15) - 1) * 64 + sq]


func _make(m: ChessMove) -> void:
	m.prev_castling = castling
	m.prev_ep = ep_square
	m.prev_halfmove = halfmove
	m.prev_hash = hash_key
	var us := side_to_move
	var h := hash_key ^ _zs ^ _zc[castling]
	if ep_square >= 0 and ChessZobrist.ep_capturable(squares, ep_square, us):
		h ^= _ze[ep_square & 7]
	var moving := squares[m.from_sq]
	h ^= _zkey(moving, m.from_sq)
	if m.captured != 0 and m.captured_sq >= 0:
		h ^= _zkey(m.captured, m.captured_sq)
	squares[m.from_sq] = 0
	if m.is_en_passant():
		squares[m.captured_sq] = 0
	squares[m.to_sq] = moving
	if m.is_promotion():
		squares[m.to_sq] = ChessTypes.pack(m.promotion, us)
	h ^= _zkey(squares[m.to_sq], m.to_sq)
	if m.is_castle():
		var rf := m.from_sq + 3
		var rt := m.from_sq + 1
		if m.to_sq != m.from_sq + 2:
			rf = m.from_sq - 4
			rt = m.from_sq - 1
		var rook := squares[rf]
		squares[rt] = rook
		squares[rf] = 0
		h ^= _zkey(rook, rf) ^ _zkey(rook, rt)
	if ChessTypes.ptype(moving) == ChessTypes.KING:
		_kings[us] = m.to_sq
	_update_castling_rights(m)
	h ^= _zc[castling]
	if m.is_double_pawn():
		ep_square = (m.from_sq + m.to_sq) >> 1
	else:
		ep_square = -1
	if ChessTypes.ptype(moving) == ChessTypes.PAWN or m.captured != 0:
		halfmove = 0
	else:
		halfmove += 1
	if us == ChessTypes.BLACK:
		fullmove += 1
	side_to_move = ChessTypes.opp(us)
	if ep_square >= 0 and ChessZobrist.ep_capturable(squares, ep_square, side_to_move):
		h ^= _ze[ep_square & 7]
	hash_key = h


func _unmake(m: ChessMove) -> void:
	side_to_move = ChessTypes.opp(side_to_move)
	if side_to_move == ChessTypes.BLACK:
		fullmove -= 1
	castling = m.prev_castling
	ep_square = m.prev_ep
	halfmove = m.prev_halfmove
	hash_key = m.prev_hash
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
	if m.piece == ChessTypes.KING:
		_kings[side_to_move] = m.from_sq


func _update_castling_rights(m: ChessMove) -> void:
	if castling == 0:
		return
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


func _compute_hash() -> int:
	return ChessZobrist.compute(squares, side_to_move, castling, ep_square)


func to_fen() -> String:
	return Fen.dump(self)


static func validate_fen(fen: String) -> String:
	return Fen.validate(fen)


## Loads a position. On invalid input returns false, sets last_fen_error and
## leaves the current position untouched.
func from_fen(fen: String) -> bool:
	var d := Fen.decode(fen)
	if not d.ok:
		last_fen_error = str(d.error)
		return false
	last_fen_error = ""
	clear()
	var sq: PackedInt32Array = d.squares
	for i in 64:
		squares[i] = sq[i]
	side_to_move = d.side
	castling = d.castling
	ep_square = d.ep
	halfmove = d.halfmove
	fullmove = d.fullmove
	start_fen = Fen.dump(self)
	_start_side = side_to_move
	_start_fullmove = fullmove
	find_king(ChessTypes.WHITE)
	find_king(ChessTypes.BLACK)
	hash_key = _compute_hash()
	_keys = PackedInt64Array([hash_key])
	_refresh_result()
	return true


func make_raw(m: ChessMove) -> void:
	_make(m)


func unmake_raw(m: ChessMove) -> void:
	_unmake(m)


func perft(depth: int) -> int:
	if depth <= 0:
		return 1
	var moves := generate_legal_moves()
	if depth == 1:
		return moves.size()
	var n := 0
	for m in moves:
		_make(m)
		n += perft(depth - 1)
		_unmake(m)
	return n


func san_history() -> PackedStringArray:
	var out := PackedStringArray()
	for m in history:
		out.append(m.san if not m.san.is_empty() else m.to_uci())
	return out


func uci_history() -> PackedStringArray:
	var out := PackedStringArray()
	for m in history:
		out.append(m.to_uci())
	return out


func numbered_san() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for i in history.size():
		if is_white_ply(i):
			parts.append("%d." % move_number_for_ply(i))
		elif i == 0:
			parts.append("%d..." % move_number_for_ply(i))
		parts.append(history[i].san if not history[i].san.is_empty() else history[i].to_uci())
	return " ".join(parts)
