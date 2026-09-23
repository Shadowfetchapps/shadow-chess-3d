class_name ShadowSearch
extends ShadowBoard

## Alpha-beta search for the Shadow AI: iterative deepening, aspiration windows,
## PVS, transposition table, null move, LMR, futility/late-move pruning,
## check extension, killers + history, and a quiescence search.
## Self-contained: never touches ChessEngine, the scene tree or autoloads.

const INF := 32000
const MATE := 30000
const MATE_BOUND := 29000
const MAX_PLY := 64
const TT_EXACT := 1
const TT_LOWER := 2
const TT_UPPER := 3
const TEMPO := 12
const PH_BITS := 14
const LAZY_MARGIN := 260

const Q_VAL: Array[int] = [0, 100, 320, 330, 500, 900, 0]
const FUT_MARGIN: Array[int] = [0, 150, 320, 480]
const PASSED_MG: Array[int] = [0, 2, 5, 10, 18, 30, 50, 0]
const PASSED_EG: Array[int] = [0, 8, 12, 22, 38, 62, 95, 0]
const DOUBLED_MG := 8
const DOUBLED_EG := 18
const ISOLATED_MG := 10
const ISOLATED_EG := 12

var tt_keys: PackedInt64Array = PackedInt64Array()
var tt_data: PackedInt64Array = PackedInt64Array()
var tt_mask: int = 0
var ph_keys: PackedInt64Array = PackedInt64Array()
var ph_data: PackedInt64Array = PackedInt64Array()
var ph_mask: int = 0
var killers: PackedInt32Array = PackedInt32Array()
var history_tab: PackedInt32Array = PackedInt32Array()
var pv_tab: PackedInt32Array = PackedInt32Array()
var pv_len: PackedInt32Array = PackedInt32Array()

var nodes: int = 0
var stopped: bool = false
var deadline: int = 0
var job: Object = null
var root_depth: int = 0

var root_moves: PackedInt32Array = PackedInt32Array()
var root_scores: PackedInt32Array = PackedInt32Array()
var final_moves: PackedInt32Array = PackedInt32Array()
var final_scores: PackedInt32Array = PackedInt32Array()
var best_move: int = 0
var best_score: int = 0
var completed_depth: int = 0
var pv: PackedInt32Array = PackedInt32Array()
var elapsed_ms: int = 0
var _iter_best: int = -1


func _init() -> void:
	super()
	killers.resize(MAX_PLY * 2 + 4)
	history_tab.resize(2 * 16384)
	pv_tab.resize(MAX_PLY * MAX_PLY)
	pv_len.resize(MAX_PLY + 1)
	ph_keys.resize(1 << PH_BITS)
	ph_data.resize(1 << PH_BITS)
	ph_mask = (1 << PH_BITS) - 1


func alloc_tt(bits: int) -> void:
	tt_keys.resize(1 << bits)
	tt_data.resize(1 << bits)
	tt_keys.fill(0)
	tt_data.fill(0)
	tt_mask = (1 << bits) - 1


func setup(fen: String, moves_uci: PackedStringArray, tt_bits: int = 18) -> bool:
	if not set_fen(fen):
		return false
	if not play_line(moves_uci):
		return false
	alloc_tt(tt_bits)
	return true


# ---------------------------------------------------------------- evaluation

@warning_ignore("integer_division")
func evaluate() -> int:
	var mgs := mg
	var egs := eg
	var pk := pawn_key
	var pi := pk & ph_mask
	var pd := ph_data[pi]
	if ph_keys[pi] != pk or pd == 0:
		pd = _pawn_eval()
		ph_keys[pi] = pk
		ph_data[pi] = pd
	mgs += (pd & 0xFFFF) - 32768
	egs += ((pd >> 16) & 0xFFFF) - 32768
	if cnt[ROOK] + cnt[ROOK | 8] > 0:
		var wfiles := (pd >> 32) & 0xFF
		var bfiles := (pd >> 40) & 0xFF
		for side in 2:
			var rook := ROOK | (side << 3)
			if cnt[rook] == 0:
				continue
			var own := wfiles if side == WHITE else bfiles
			var opp := bfiles if side == WHITE else wfiles
			var sign := 1 if side == WHITE else -1
			var base := side * 32
			for i in range(1, pcount[side]):
				var s := plist[base + i]
				if board[s] != rook:
					continue
				var fb := 1 << (s & 7)
				if (own & fb) == 0:
					if (opp & fb) == 0:
						mgs += 24 * sign
						egs += 10 * sign
					else:
						mgs += 11 * sign
						egs += 5 * sign
	if cnt[BISHOP] >= 2:
		mgs += 28
		egs += 48
	if cnt[BISHOP | 8] >= 2:
		mgs -= 28
		egs -= 48
	if phase > 5:
		for side in 2:
			var k := plist[side * 32]
			if (k >> 4) != (0 if side == WHITE else 7):
				continue
			var f := k & 7
			if f == 3 or f == 4:
				continue
			var fwd := 16 if side == WHITE else -16
			var pawn := PAWN | (side << 3)
			var bonus := 0
			for df in range(-1, 2):
				if f + df < 0 or f + df > 7:
					continue
				var s1 := k + fwd + df
				if board[s1] == pawn:
					bonus += 14
				elif board[s1 + fwd] == pawn:
					bonus += 7
				else:
					bonus -= 12
			mgs += bonus if side == WHITE else -bonus
	var ph := mini(phase, 24)
	var score := (mgs * ph + egs * (24 - ph)) / 24
	if stm == BLACK:
		score = -score
	return score + TEMPO


func _pawn_eval() -> int:
	var wcount := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
	var bcount := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
	var wmin := PackedInt32Array([8, 8, 8, 8, 8, 8, 8, 8])
	var bmax := PackedInt32Array([-1, -1, -1, -1, -1, -1, -1, -1])
	for side in 2:
		var pawn := PAWN | (side << 3)
		if cnt[pawn] == 0:
			continue
		var base := side * 32
		for i in range(1, pcount[side]):
			var s := plist[base + i]
			if board[s] != pawn:
				continue
			var f := s & 7
			var r := s >> 4
			if side == WHITE:
				wcount[f] += 1
				if r < wmin[f]:
					wmin[f] = r
			else:
				bcount[f] += 1
				if r > bmax[f]:
					bmax[f] = r
	var mgs := 0
	var egs := 0
	var wfiles := 0
	var bfiles := 0
	for f in 8:
		if wcount[f] > 0:
			wfiles |= 1 << f
		if bcount[f] > 0:
			bfiles |= 1 << f
		if wcount[f] > 1:
			mgs -= DOUBLED_MG * (wcount[f] - 1)
			egs -= DOUBLED_EG * (wcount[f] - 1)
		if bcount[f] > 1:
			mgs += DOUBLED_MG * (bcount[f] - 1)
			egs += DOUBLED_EG * (bcount[f] - 1)
	for side in 2:
		var pawn := PAWN | (side << 3)
		if cnt[pawn] == 0:
			continue
		var base := side * 32
		for i in range(1, pcount[side]):
			var s := plist[base + i]
			if board[s] != pawn:
				continue
			var f := s & 7
			var r := s >> 4
			var left := f > 0
			var right := f < 7
			if side == WHITE:
				if (not left or wcount[f - 1] == 0) and (not right or wcount[f + 1] == 0):
					mgs -= ISOLATED_MG
					egs -= ISOLATED_EG
				if bmax[f] <= r and (not left or bmax[f - 1] <= r) and (not right or bmax[f + 1] <= r):
					mgs += PASSED_MG[r]
					egs += PASSED_EG[r]
			else:
				if (not left or bcount[f - 1] == 0) and (not right or bcount[f + 1] == 0):
					mgs += ISOLATED_MG
					egs += ISOLATED_EG
				if wmin[f] >= r and (not left or wmin[f - 1] >= r) and (not right or wmin[f + 1] >= r):
					mgs -= PASSED_MG[7 - r]
					egs -= PASSED_EG[7 - r]
	return (mgs + 32768) | ((egs + 32768) << 16) | (wfiles << 32) | (bfiles << 40)


# ---------------------------------------------------------------- search

func _poll() -> void:
	if job != null and job.get("cancelled"):
		stopped = true
	elif completed_depth >= 1 and Time.get_ticks_msec() >= deadline:
		stopped = true


func _score_moves(start: int, end: int, tt_move: int, ply: int) -> void:
	var k1 := killers[ply * 2]
	var k2 := killers[ply * 2 + 1]
	var hbase := stm * 16384
	for i in range(start, end):
		var m := mv[i]
		if m == tt_move:
			ms[i] = 1000000
			continue
		var cap := board[(m >> 7) & 127]
		var promo := (m >> 14) & 7
		if cap != 0:
			var att := board[m & 127] & 7
			var vic := cap & 7
			if Q_VAL[att] > Q_VAL[vic] + 50 and _pawn_guarded((m >> 7) & 127, stm ^ 1):
				ms[i] = 120000 + vic * 1000 - att
			else:
				ms[i] = 200000 + vic * 1000 - att + (5000 if promo == QUEEN else 0)
		elif promo != 0:
			ms[i] = 190000 if promo == QUEEN else -50000 + promo
		elif (m >> 17) == FLAG_EP:
			ms[i] = 200999
		elif m == k1:
			ms[i] = 150000
		elif m == k2:
			ms[i] = 140000
		else:
			ms[i] = history_tab[hbase + (m & 16383)]


func _score_captures(start: int, end: int) -> void:
	for i in range(start, end):
		var m := mv[i]
		var cap := board[(m >> 7) & 127]
		var victim := (cap & 7) if cap != 0 else PAWN
		if ((m >> 14) & 7) == QUEEN:
			victim += 8
		ms[i] = victim * 1000 - (board[m & 127] & 7)


func _qsearch(alpha: int, beta: int, ply: int, checked: bool) -> int:
	pv_len[ply] = ply
	nodes += 1
	if (nodes & 1023) == 0:
		_poll()
	if stopped:
		return 0
	if ply >= MAX_PLY - 1:
		return evaluate()
	var best := -INF
	var stand := 0
	var start := mtop
	var end := start
	if checked:
		end = gen(start, false, true)
		mtop = end
		_score_moves(start, end, 0, ply)
	else:
		var ph := mini(phase, 24)
		@warning_ignore("integer_division")
		var quick := (mg * ph + eg * (24 - ph)) / 24
		if stm == BLACK:
			quick = -quick
		if quick - LAZY_MARGIN >= beta:
			return quick
		stand = evaluate()
		if stand >= beta:
			return stand
		if stand > alpha:
			alpha = stand
		best = stand
		if stand + 1150 <= alpha:
			return best
		end = gen_captures(start)
		mtop = end
		_score_captures(start, end)
	var legal := 0
	var ksq := plist[stm * 32]
	var eksq := plist[(stm ^ 1) * 32]
	for i in range(start, end):
		var bi := i
		var bs := ms[i]
		for j in range(i + 1, end):
			if ms[j] > bs:
				bs = ms[j]
				bi = j
		var m := mv[bi]
		if bi != i:
			mv[bi] = mv[i]
			ms[bi] = ms[i]
			mv[i] = m
			ms[i] = bs
		var from := m & 127
		var to := (m >> 7) & 127
		var flag := m >> 17
		if not checked:
			var gain := Q_VAL[board[to] & 7] if board[to] != 0 else 100
			if ((m >> 14) & 7) != 0:
				gain += 800
			elif stand + gain + 180 <= alpha:
				continue
			elif Q_VAL[board[from] & 7] > gain + 50 and (_pawn_guarded(to, stm ^ 1) or is_attacked(to, stm ^ 1)):
				continue
		var need_legal := checked or from == ksq or flag == FLAG_EP or (_att[from - ksq + 119] & PB_LINE) != 0
		make(m)
		if need_legal and not legal_after(m, checked):
			unmake()
			continue
		legal += 1
		var gives := false
		if flag >= FLAG_EP or (_att[eksq - to + 119] & _pbit[board[to]]) != 0 or (_att[from - eksq + 119] & PB_LINE) != 0:
			gives = gives_check(m)
		var score := -_qsearch(-beta, -alpha, ply + 1, gives)
		unmake()
		if stopped:
			mtop = start
			return 0
		if score > best:
			best = score
			if score > alpha:
				alpha = score
				if score >= beta:
					break
	mtop = start
	if checked and legal == 0:
		return -MATE + ply
	return best


func _pawn_guarded(sq: int, side: int) -> bool:
	var pawn := PAWN | (side << 3)
	var s := sq - 16 if side == WHITE else sq + 16
	if ((s - 1) & 0x88) == 0 and board[s - 1] == pawn:
		return true
	return ((s + 1) & 0x88) == 0 and board[s + 1] == pawn


func _tt_move_ok(m: int) -> bool:
	var p := board[m & 127]
	if p == 0 or (p >> 3) != stm:
		return false
	var q := board[(m >> 7) & 127]
	return q == 0 or ((q >> 3) != stm and (q & 7) != KING)


func _search(alpha: int, beta: int, depth: int, ply: int, checked: bool, can_null: bool) -> int:
	pv_len[ply] = ply
	if checked and ply <= root_depth * 2 + 2:
		depth += 1
	if depth <= 0:
		return _qsearch(alpha, beta, ply, checked)
	nodes += 1
	if (nodes & 1023) == 0:
		_poll()
	if stopped:
		return 0
	if half >= 100 or (half >= 4 and is_repetition()):
		return 0
	if cnt[1] + cnt[9] + cnt[4] + cnt[12] + cnt[5] + cnt[13] == 0 and cnt[2] + cnt[3] + cnt[10] + cnt[11] <= 1:
		return 0
	if ply >= MAX_PLY - 1:
		return evaluate()
	var mating := MATE - ply - 1
	if mating < beta:
		beta = mating
		if alpha >= beta:
			return beta
	var mated := -MATE + ply
	if mated > alpha:
		alpha = mated
		if alpha >= beta:
			return alpha
	var pv_node := beta - alpha > 1
	var idx := key & tt_mask
	var tt_move := 0
	if tt_keys[idx] == key:
		var d := tt_data[idx]
		tt_move = d & 0xFFFFF
		if not pv_node and ((d >> 40) & 0xFF) >= depth:
			var ts := ((d >> 20) & 0xFFFFF) - 524288
			if ts > MATE_BOUND:
				ts -= ply
			elif ts < -MATE_BOUND:
				ts += ply
			var fl := (d >> 48) & 3
			if fl == TT_EXACT or (fl == TT_LOWER and ts >= beta) or (fl == TT_UPPER and ts <= alpha):
				return ts
	var static_eval := 0
	if not checked:
		static_eval = evaluate()
		if not pv_node and beta < MATE_BOUND and beta > -MATE_BOUND:
			if depth <= 3 and static_eval - 110 * depth >= beta:
				return static_eval
			if can_null and depth >= 3 and static_eval >= beta and has_non_pawn(stm):
				var r := 3 if depth >= 6 else 2
				make_null()
				var ns := -_search(-beta, -beta + 1, depth - 1 - r, ply + 1, false, false)
				unmake_null()
				if stopped:
					return 0
				if ns >= beta:
					return beta
	var start := mtop
	var end := start
	var staged := tt_move != 0 and _tt_move_ok(tt_move)
	if staged:
		mv[start] = tt_move
		ms[start] = 1000000
		end = start + 1
	else:
		tt_move = 0
		end = gen(start, false, checked)
		_score_moves(start, end, 0, ply)
	mtop = end
	var futile := not checked and not pv_node and depth <= 3 and static_eval + FUT_MARGIN[depth] <= alpha
	var lmp_limit := 3 + depth * depth * 2
	var k1 := killers[ply * 2]
	var k2 := killers[ply * 2 + 1]
	var legal := 0
	var best := -INF
	var best_m := 0
	var orig_alpha := alpha
	var ksq := plist[stm * 32]
	var eksq := plist[(stm ^ 1) * 32]
	var i := start
	while true:
		if i >= end:
			if not staged:
				break
			staged = false
			end = gen(end, false, checked)
			mtop = end
			_score_moves(i, end, tt_move, ply)
			if i >= end:
				break
		var bi := i
		var bs := ms[i]
		for j in range(i + 1, end):
			if ms[j] > bs:
				bs = ms[j]
				bi = j
		var m := mv[bi]
		if bi != i:
			mv[bi] = mv[i]
			ms[bi] = ms[i]
			mv[i] = m
			ms[i] = bs
		i += 1
		if m == tt_move and i - 1 != start:
			continue
		var from := m & 127
		var to := (m >> 7) & 127
		var flag := m >> 17
		var quiet := board[to] == 0 and ((m >> 14) & 7) == 0 and flag != FLAG_EP
		var need_legal := checked or from == ksq or flag == FLAG_EP or (_att[from - ksq + 119] & PB_LINE) != 0
		make(m)
		if need_legal and not legal_after(m, checked):
			unmake()
			continue
		legal += 1
		var gives := false
		if flag >= FLAG_EP or (_att[eksq - to + 119] & _pbit[board[to]]) != 0 or (_att[from - eksq + 119] & PB_LINE) != 0:
			gives = gives_check(m)
		if quiet and not gives and legal > 1 and not checked:
			if futile or (not pv_node and depth <= 3 and legal > lmp_limit):
				unmake()
				continue
		var score := 0
		if legal == 1:
			score = -_search(-beta, -alpha, depth - 1, ply + 1, gives, true)
		else:
			var r := 0
			if depth >= 3 and quiet and not gives and not checked and legal > 3 and m != k1 and m != k2:
				r = 1
				if legal > 8 and depth >= 5:
					r = 2
				if pv_node:
					r -= 1
				r = mini(r, depth - 2)
			score = -_search(-alpha - 1, -alpha, depth - 1 - r, ply + 1, gives, true)
			if score > alpha and r > 0 and not stopped:
				score = -_search(-alpha - 1, -alpha, depth - 1, ply + 1, gives, true)
			if score > alpha and score < beta and not stopped:
				score = -_search(-beta, -alpha, depth - 1, ply + 1, gives, true)
		unmake()
		if stopped:
			mtop = start
			return 0
		if score > best:
			best = score
			best_m = m
			if score > alpha:
				alpha = score
				var row := ply * MAX_PLY
				var child := row + MAX_PLY
				pv_tab[row + ply] = m
				var clen := pv_len[ply + 1]
				for j in range(ply + 1, clen):
					pv_tab[row + j] = pv_tab[child + j]
				pv_len[ply] = maxi(clen, ply + 1)
				if score >= beta:
					if quiet:
						if k1 != m:
							killers[ply * 2 + 1] = k1
							killers[ply * 2] = m
						var hi := stm * 16384 + (m & 16383)
						history_tab[hi] = mini(history_tab[hi] + depth * depth, 100000)
					break
	mtop = start
	if legal == 0:
		return -MATE + ply if checked else 0
	var flag := TT_UPPER
	if best >= beta:
		flag = TT_LOWER
	elif best > orig_alpha:
		flag = TT_EXACT
	var store := best
	if store > MATE_BOUND:
		store += ply
	elif store < -MATE_BOUND:
		store -= ply
	var old := tt_data[idx]
	if tt_keys[idx] != key or depth >= ((old >> 40) & 0xFF) - 1 or flag == TT_EXACT:
		tt_keys[idx] = key
		tt_data[idx] = (best_m & 0xFFFFF) | ((store + 524288) << 20) | (depth << 40) | (flag << 48)
	return best


func _root_search(depth: int, alpha: int, beta: int, margin: int) -> int:
	var best := -INF
	var best_i := -1
	var n := root_moves.size()
	pv_len[0] = 0
	for i in n:
		var m := root_moves[i]
		var floor_a := alpha
		if margin > 0 and best > -INF:
			floor_a = maxi(alpha, best - margin)
		make(m)
		var gives := gives_check(m)
		var score := 0
		if i == 0:
			score = -_search(-beta, -floor_a, depth - 1, 1, gives, true)
		else:
			score = -_search(-floor_a - 1, -floor_a, depth - 1, 1, gives, true)
			if score > floor_a and score < beta and not stopped:
				score = -_search(-beta, -floor_a, depth - 1, 1, gives, true)
		unmake()
		if stopped:
			break
		root_scores[i] = score
		if score > best:
			best = score
			best_i = i
			pv_tab[0] = m
			var clen := pv_len[1]
			for j in range(1, clen):
				pv_tab[j] = pv_tab[MAX_PLY + j]
			pv_len[0] = maxi(clen, 1)
			if margin == 0 and score > alpha:
				alpha = score
			if score >= beta:
				break
	_iter_best = best_i
	return best


func _sort_root() -> void:
	var n := root_moves.size()
	for i in range(1, n):
		var m := root_moves[i]
		var s := root_scores[i]
		var j := i - 1
		while j >= 0 and root_scores[j] < s:
			root_moves[j + 1] = root_moves[j]
			root_scores[j + 1] = root_scores[j]
			j -= 1
		root_moves[j + 1] = m
		root_scores[j + 1] = s


func _order_root_initial() -> void:
	var n := root_moves.size()
	var tt_move := 0
	var idx := key & tt_mask
	if tt_keys[idx] == key:
		tt_move = tt_data[idx] & 0xFFFFF
	for i in n:
		var m := root_moves[i]
		var cap := board[(m >> 7) & 127]
		var s := 0
		if m == tt_move:
			s = 100000
		elif cap != 0:
			s = 10000 + (cap & 7) * 100 - (board[m & 127] & 7)
		elif ((m >> 14) & 7) == QUEEN:
			s = 9000
		root_scores[i] = s
	_sort_root()


## Runs iterative deepening. margin > 0 keeps exact scores for every root move
## within `margin` centipawns of the best (used by the weaker levels).
func think(max_depth: int, time_ms: int, margin: int = 0) -> void:
	var t0 := Time.get_ticks_msec()
	deadline = t0 + maxi(1, time_ms)
	nodes = 0
	stopped = false
	completed_depth = 0
	best_score = 0
	pv = PackedInt32Array()
	killers.fill(0)
	history_tab.fill(0)
	root_moves = legal_moves()
	var n := root_moves.size()
	root_scores.resize(n)
	best_move = root_moves[0] if n > 0 else 0
	final_moves = root_moves.duplicate()
	final_scores = PackedInt32Array()
	final_scores.resize(n)
	if n == 0:
		best_score = -MATE if in_check() else 0
		elapsed_ms = Time.get_ticks_msec() - t0
		return
	_order_root_initial()
	best_move = root_moves[0]
	var soft := maxi(1, int(time_ms * 0.5))
	var prev := 0
	var iter_start := t0
	for depth in range(1, maxi(1, max_depth) + 1):
		root_depth = depth
		iter_start = Time.get_ticks_msec()
		var alpha := -INF
		var beta := INF
		var delta := 35
		if margin == 0 and depth >= 4 and absi(prev) < MATE_BOUND:
			alpha = prev - delta
			beta = prev + delta
		var score := 0
		while true:
			root_scores.fill(-INF)
			score = _root_search(depth, alpha, beta, margin)
			if stopped:
				break
			if score <= alpha and alpha > -INF:
				delta *= 3
				alpha = -INF if delta > 400 else maxi(-INF, score - delta)
			elif score >= beta and beta < INF:
				delta *= 3
				beta = INF if delta > 400 else mini(INF, score + delta)
			else:
				break
		if stopped:
			if _iter_best > 0 and root_scores[_iter_best] > prev:
				best_move = root_moves[_iter_best]
				best_score = root_scores[_iter_best]
				pv = PackedInt32Array([best_move])
			break
		_sort_root()
		completed_depth = depth
		best_move = root_moves[0]
		best_score = score
		prev = score
		final_moves = root_moves.duplicate()
		final_scores = root_scores.duplicate()
		pv = PackedInt32Array()
		for j in pv_len[0]:
			pv.append(pv_tab[j])
		if pv.is_empty() or pv[0] != best_move:
			pv = PackedInt32Array([best_move])
		if absi(score) >= MATE_BOUND and MATE - absi(score) <= depth:
			break
		var now := Time.get_ticks_msec()
		if now - t0 >= soft or now - t0 + (now - iter_start) * 2 > time_ms:
			break
		if n == 1 and depth >= 3:
			break
	elapsed_ms = Time.get_ticks_msec() - t0


static func mate_moves(score: int) -> int:
	if score >= MATE_BOUND:
		return (MATE - score + 1) >> 1
	if score <= -MATE_BOUND:
		return -((MATE + score + 1) >> 1)
	return 0
