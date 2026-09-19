class_name ChessAI
extends RefCounted

const INF := 1000000
const MATE := 200000

const VAL: Array[int] = [0, 100, 320, 330, 500, 900, 20000]

const PST_PAWN: Array[int] = [
	0, 0, 0, 0, 0, 0, 0, 0,
	5, 10, 10, -20, -20, 10, 10, 5,
	5, -5, -10, 0, 0, -10, -5, 5,
	0, 0, 0, 20, 20, 0, 0, 0,
	5, 5, 10, 25, 25, 10, 5, 5,
	10, 10, 20, 30, 30, 20, 10, 10,
	50, 50, 50, 50, 50, 50, 50, 50,
	0, 0, 0, 0, 0, 0, 0, 0,
]
const PST_KNIGHT: Array[int] = [
	-50, -40, -30, -30, -30, -30, -40, -50,
	-40, -20, 0, 5, 5, 0, -20, -40,
	-30, 5, 10, 15, 15, 10, 5, -30,
	-30, 0, 15, 20, 20, 15, 0, -30,
	-30, 5, 15, 20, 20, 15, 5, -30,
	-30, 0, 10, 15, 15, 10, 0, -30,
	-40, -20, 0, 0, 0, 0, -20, -40,
	-50, -40, -30, -30, -30, -30, -40, -50,
]
const PST_BISHOP: Array[int] = [
	-20, -10, -10, -10, -10, -10, -10, -20,
	-10, 5, 0, 0, 0, 0, 5, -10,
	-10, 10, 10, 10, 10, 10, 10, -10,
	-10, 0, 10, 10, 10, 10, 0, -10,
	-10, 5, 5, 10, 10, 5, 5, -10,
	-10, 0, 5, 10, 10, 5, 0, -10,
	-10, 0, 0, 0, 0, 0, 0, -10,
	-20, -10, -10, -10, -10, -10, -10, -20,
]
const PST_ROOK: Array[int] = [
	0, 0, 0, 5, 5, 0, 0, 0,
	-5, 0, 0, 0, 0, 0, 0, -5,
	-5, 0, 0, 0, 0, 0, 0, -5,
	-5, 0, 0, 0, 0, 0, 0, -5,
	-5, 0, 0, 0, 0, 0, 0, -5,
	-5, 0, 0, 0, 0, 0, 0, -5,
	5, 10, 10, 10, 10, 10, 10, 5,
	0, 0, 0, 0, 0, 0, 0, 0,
]
const PST_QUEEN: Array[int] = [
	-20, -10, -10, -5, -5, -10, -10, -20,
	-10, 0, 5, 0, 0, 0, 0, -10,
	-10, 5, 5, 5, 5, 5, 0, -10,
	0, 0, 5, 5, 5, 5, 0, -5,
	-5, 0, 5, 5, 5, 5, 0, -5,
	-10, 0, 5, 5, 5, 5, 0, -10,
	-10, 0, 0, 0, 0, 0, 0, -10,
	-20, -10, -10, -5, -5, -10, -10, -20,
]
const PST_KING: Array[int] = [
	20, 30, 10, 0, 0, 10, 30, 20,
	20, 20, 0, 0, 0, 0, 20, 20,
	-10, -20, -20, -20, -20, -20, -20, -10,
	-20, -30, -30, -40, -40, -30, -30, -20,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30,
]


static func choose(engine: ChessEngine, difficulty: String = "medium") -> ChessMove:
	var depth := 2
	var noise := 0.0
	match difficulty:
		"easy":
			depth = 1
			noise = 35.0
		"hard":
			depth = 3
			noise = 0.0
		"master":
			depth = 4
			noise = 0.0
		_:
			depth = 2
			noise = 8.0
	return search(engine, depth, noise)


static func search(engine: ChessEngine, depth: int, noise: float = 0.0) -> ChessMove:
	var work := engine.clone()
	work.history.clear()
	work.redo_stack.clear()
	var moves := _ordered(work)
	if moves.is_empty():
		return null
	var best: ChessMove = moves[0]
	var best_score := -INF
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for m in moves:
		work.make_raw(m)
		var score := -_negamax(work, depth - 1, -INF, INF)
		work.unmake_raw(m)
		if noise > 0.0:
			score += rng.randf_range(-noise, noise)
		if score > best_score:
			best_score = score
			best = m
	return best


static func _negamax(e: ChessEngine, depth: int, alpha: int, beta: int) -> int:
	if e._insufficient_material():
		return 0
	var moves := _ordered(e)
	if moves.is_empty():
		if e.in_check():
			return -MATE - depth
		return 0
	if depth <= 0:
		return _quiesce(e, alpha, beta, 2)
	for m in moves:
		e.make_raw(m)
		var score := -_negamax(e, depth - 1, -beta, -alpha)
		e.unmake_raw(m)
		if score >= beta:
			return beta
		if score > alpha:
			alpha = score
	return alpha


static func _quiesce(e: ChessEngine, alpha: int, beta: int, extra: int) -> int:
	var stand := _eval(e)
	if stand >= beta:
		return beta
	if stand > alpha:
		alpha = stand
	if extra <= 0:
		return alpha
	for m in _ordered(e):
		if not m.is_capture() and not m.is_promotion():
			continue
		e.make_raw(m)
		var score := -_quiesce(e, -beta, -alpha, extra - 1)
		e.unmake_raw(m)
		if score >= beta:
			return beta
		if score > alpha:
			alpha = score
	return alpha


static func _eval(e: ChessEngine) -> int:
	var score := 0
	for sq in 64:
		var p := e.squares[sq]
		if p == 0:
			continue
		var t := ChessTypes.ptype(p)
		var c := ChessTypes.pcolor(p)
		var idx := sq if c == ChessTypes.WHITE else ChessTypes.sq(ChessTypes.file_of(sq), 7 - ChessTypes.rank_of(sq))
		var val: int = VAL[t] + _pst(t, idx)
		score += val if c == ChessTypes.WHITE else -val
	if e.in_check():
		score += -18 if e.side_to_move == ChessTypes.WHITE else 18
	return score if e.side_to_move == ChessTypes.WHITE else -score


static func _pst(type: int, idx: int) -> int:
	match type:
		ChessTypes.PAWN:
			return PST_PAWN[idx]
		ChessTypes.KNIGHT:
			return PST_KNIGHT[idx]
		ChessTypes.BISHOP:
			return PST_BISHOP[idx]
		ChessTypes.ROOK:
			return PST_ROOK[idx]
		ChessTypes.QUEEN:
			return PST_QUEEN[idx]
		ChessTypes.KING:
			return PST_KING[idx]
		_:
			return 0


static func _ordered(e: ChessEngine) -> Array[ChessMove]:
	var moves := e.generate_legal_moves()
	moves.sort_custom(func(a: ChessMove, b: ChessMove) -> bool:
		return _mvv(a) > _mvv(b)
	)
	return moves


static func _mvv(m: ChessMove) -> int:
	var s := 0
	if m.is_capture():
		s += 100 + VAL[ChessTypes.ptype(m.captured)] * 10 - VAL[m.piece]
	if m.is_promotion():
		s += VAL[m.promotion]
	if m.is_castle():
		s += 40
	return s
