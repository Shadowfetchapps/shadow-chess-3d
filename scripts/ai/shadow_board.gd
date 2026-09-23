class_name ShadowBoard
extends RefCounted

## Compact 0x88 board for the Shadow search. Pieces are ints (type | color << 3),
## moves are ints: from | to << 7 | promo_type << 14 | flag << 17.
## Keeps piece lists (king always at slot 0), incremental Zobrist keys that match
## ChessEngine.hash_key, and incremental PeSTO mid/endgame sums.

const WHITE := 0
const BLACK := 1
const PAWN := 1
const KNIGHT := 2
const BISHOP := 3
const ROOK := 4
const QUEEN := 5
const KING := 6

const FLAG_DOUBLE := 1
const FLAG_EP := 2
const FLAG_CASTLE := 3
const PB_LINE := 32

const MAX_STACK := 1100
const MOVE_STACK := 16384
const HIST_COMPACT := 900

const N_DIRS: Array[int] = [33, 31, 18, 14, -33, -31, -18, -14]
const DIRS: Array[int] = [1, -1, 16, -16, 15, 17, -15, -17]

var board: PackedInt32Array = PackedInt32Array()
var plist: PackedInt32Array = PackedInt32Array()
var pcount: PackedInt32Array = PackedInt32Array()
var pidx: PackedInt32Array = PackedInt32Array()
var cnt: PackedInt32Array = PackedInt32Array()
var stm: int = WHITE
var castle: int = 0
var ep: int = -1
var half: int = 0
var fullmove: int = 1
var key: int = 0
var pawn_key: int = 0
var mg: int = 0
var eg: int = 0
var phase: int = 0

var sp: int = 0
var u_move: PackedInt32Array = PackedInt32Array()
var u_cap: PackedInt32Array = PackedInt32Array()
var u_castle: PackedInt32Array = PackedInt32Array()
var u_ep: PackedInt32Array = PackedInt32Array()
var u_half: PackedInt32Array = PackedInt32Array()
var u_key: PackedInt64Array = PackedInt64Array()
var u_pkey: PackedInt64Array = PackedInt64Array()
var u_mg: PackedInt32Array = PackedInt32Array()
var u_eg: PackedInt32Array = PackedInt32Array()
var u_phase: PackedInt32Array = PackedInt32Array()

var hist: PackedInt64Array = PackedInt64Array()
var hp: int = 0

var mv: PackedInt32Array = PackedInt32Array()
var ms: PackedInt32Array = PackedInt32Array()
var mtop: int = 0

var _zob: PackedInt64Array
var _zc: PackedInt64Array
var _ze: PackedInt64Array
var _zs: int = 0
var _pmg: PackedInt32Array
var _peg: PackedInt32Array
var _phinc: PackedInt32Array
var _pbit: PackedInt32Array
var _att: PackedInt32Array
var _adelta: PackedInt32Array
var _cmask: PackedInt32Array


func _init() -> void:
	ShadowTables.ensure_tables()
	_zob = ShadowTables.zob
	_zc = ShadowTables.zob_castle
	_ze = ShadowTables.zob_ep
	_zs = ShadowTables.zob_side
	_pmg = ShadowTables.pst_mg
	_peg = ShadowTables.pst_eg
	_phinc = ShadowTables.phase_inc
	_pbit = ShadowTables.piece_bit
	_att = ShadowTables.att_bits
	_adelta = ShadowTables.att_delta
	_cmask = ShadowTables.castle_mask
	board.resize(128)
	plist.resize(64)
	pcount.resize(2)
	pidx.resize(128)
	cnt.resize(16)
	u_move.resize(MAX_STACK)
	u_cap.resize(MAX_STACK)
	u_castle.resize(MAX_STACK)
	u_ep.resize(MAX_STACK)
	u_half.resize(MAX_STACK)
	u_mg.resize(MAX_STACK)
	u_eg.resize(MAX_STACK)
	u_phase.resize(MAX_STACK)
	u_key.resize(MAX_STACK)
	u_pkey.resize(MAX_STACK)
	hist.resize(MAX_STACK + 64)
	mv.resize(MOVE_STACK)
	ms.resize(MOVE_STACK)


func set_fen(fen: String) -> bool:
	var d := Fen.decode(fen)
	if not d.ok:
		return false
	board.fill(0)
	pidx.fill(0)
	cnt.fill(0)
	pcount[0] = 0
	pcount[1] = 0
	key = 0
	pawn_key = 0
	mg = 0
	eg = 0
	phase = 0
	sp = 0
	hp = 0
	mtop = 0
	var sq: PackedInt32Array = d.squares
	for pass_kings in [true, false]:
		for s in 64:
			var p := sq[s]
			if p == 0:
				continue
			var t := p & 15
			if (t == KING) != pass_kings:
				continue
			_add(t | ((p >> 4) << 3), ShadowTables.sq88(s))
	stm = int(d.side)
	castle = int(d.castling)
	half = int(d.halfmove)
	fullmove = int(d.fullmove)
	ep = -1
	if int(d.ep) >= 0:
		var e := ShadowTables.sq88(int(d.ep))
		if _ep_capturable(e, stm):
			ep = e
			key ^= _ze[e & 7]
	key ^= _zc[castle]
	if stm == BLACK:
		key ^= _zs
	return true


## Plays game moves (UCI) permanently; keeps their keys for repetition checks.
func play_line(ucis: PackedStringArray) -> bool:
	for u in ucis:
		var m := parse_uci(u)
		if m == 0:
			return false
		make(m)
		if stm == WHITE:
			fullmove += 1
		sp = 0
		if hp > HIST_COMPACT:
			_compact_hist()
	sp = 0
	return true


func _compact_hist() -> void:
	var keep := mini(hp, maxi(half, 0) + 2)
	var off := hp - keep
	for i in keep:
		hist[i] = hist[off + i]
	hp = keep


func _ep_capturable(e: int, side: int) -> bool:
	var pawn_sq := e - 16 if side == WHITE else e + 16
	var want := PAWN | (side << 3)
	if ((pawn_sq - 1) & 0x88) == 0 and board[pawn_sq - 1] == want:
		return true
	if ((pawn_sq + 1) & 0x88) == 0 and board[pawn_sq + 1] == want:
		return true
	return false


func _add(p: int, s: int) -> void:
	var side := p >> 3
	board[s] = p
	var i := pcount[side]
	plist[side * 32 + i] = s
	pidx[s] = i
	pcount[side] = i + 1
	cnt[p] += 1
	var z := _zob[p * 128 + s]
	key ^= z
	if (p & 7) == PAWN:
		pawn_key ^= z
	mg += _pmg[p * 128 + s]
	eg += _peg[p * 128 + s]
	phase += _phinc[p]


func _remove(p: int, s: int) -> void:
	var side := p >> 3
	var base := side * 32
	var i := pidx[s]
	var last := pcount[side] - 1
	var ls := plist[base + last]
	plist[base + i] = ls
	pidx[ls] = i
	pcount[side] = last
	board[s] = 0
	cnt[p] -= 1
	var z := _zob[p * 128 + s]
	key ^= z
	if (p & 7) == PAWN:
		pawn_key ^= z
	mg -= _pmg[p * 128 + s]
	eg -= _peg[p * 128 + s]
	phase -= _phinc[p]


func _shift(p: int, from: int, to: int) -> void:
	board[to] = p
	board[from] = 0
	var i := pidx[from]
	plist[(p >> 3) * 32 + i] = to
	pidx[to] = i
	var z := _zob[p * 128 + from] ^ _zob[p * 128 + to]
	key ^= z
	if (p & 7) == PAWN:
		pawn_key ^= z
	mg += _pmg[p * 128 + to] - _pmg[p * 128 + from]
	eg += _peg[p * 128 + to] - _peg[p * 128 + from]


func make(m: int) -> void:
	var from := m & 127
	var to := (m >> 7) & 127
	var flag := m >> 17
	var us := stm
	var p := board[from]
	var cap := board[to]
	var s := sp
	u_move[s] = m
	u_cap[s] = cap
	u_castle[s] = castle
	u_ep[s] = ep
	u_half[s] = half
	u_key[s] = key
	u_pkey[s] = pawn_key
	u_mg[s] = mg
	u_eg[s] = eg
	u_phase[s] = phase
	sp = s + 1
	hist[hp] = key
	hp += 1
	if ep >= 0:
		key ^= _ze[ep & 7]
		ep = -1
	half += 1
	if cap != 0:
		# inline capture removal
		var them_base := (cap >> 3) * 32
		var ci := pidx[to]
		var last := pcount[cap >> 3] - 1
		var ls := plist[them_base + last]
		plist[them_base + ci] = ls
		pidx[ls] = ci
		pcount[cap >> 3] = last
		cnt[cap] -= 1
		var zc := _zob[cap * 128 + to]
		key ^= zc
		if (cap & 7) == PAWN:
			pawn_key ^= zc
		mg -= _pmg[cap * 128 + to]
		eg -= _peg[cap * 128 + to]
		phase -= _phinc[cap]
		half = 0
	# inline piece shift
	board[to] = p
	board[from] = 0
	var ix := pidx[from]
	plist[us * 32 + ix] = to
	pidx[to] = ix
	var zp := _zob[p * 128 + from] ^ _zob[p * 128 + to]
	key ^= zp
	mg += _pmg[p * 128 + to] - _pmg[p * 128 + from]
	eg += _peg[p * 128 + to] - _peg[p * 128 + from]
	if (p & 7) == PAWN:
		pawn_key ^= zp
		half = 0
		var promo := (m >> 14) & 7
		if promo != 0:
			_remove(p, to)
			_add(promo | (us << 3), to)
		elif flag == FLAG_DOUBLE:
			var e := (from + to) >> 1
			if _ep_capturable(e, us ^ 1):
				ep = e
				key ^= _ze[e & 7]
		elif flag == FLAG_EP:
			var cs := to - 16 if us == WHITE else to + 16
			_remove(board[cs], cs)
	elif flag == FLAG_CASTLE:
		if to > from:
			_shift(board[from + 3], from + 3, from + 1)
		else:
			_shift(board[from - 4], from - 4, from - 1)
	if castle != 0:
		var nc := castle & _cmask[from] & _cmask[to]
		if nc != castle:
			key ^= _zc[castle] ^ _zc[nc]
			castle = nc
	stm = us ^ 1
	key ^= _zs


func unmake() -> void:
	sp -= 1
	hp -= 1
	var s := sp
	var m := u_move[s]
	var from := m & 127
	var to := (m >> 7) & 127
	var flag := m >> 17
	var us := stm ^ 1
	stm = us
	var p := board[to]
	if ((m >> 14) & 7) != 0:
		cnt[p] -= 1
		p = PAWN | (us << 3)
		cnt[p] += 1
	board[from] = p
	board[to] = 0
	var ix := pidx[to]
	plist[us * 32 + ix] = from
	pidx[from] = ix
	var cap := u_cap[s]
	if cap != 0:
		board[to] = cap
		var side := cap >> 3
		var n := pcount[side]
		plist[side * 32 + n] = to
		pidx[to] = n
		pcount[side] = n + 1
		cnt[cap] += 1
	elif flag == FLAG_EP:
		var cs := to - 16 if us == WHITE else to + 16
		var pawn := PAWN | ((us ^ 1) << 3)
		board[cs] = pawn
		var n2 := pcount[us ^ 1]
		plist[(us ^ 1) * 32 + n2] = cs
		pidx[cs] = n2
		pcount[us ^ 1] = n2 + 1
		cnt[pawn] += 1
	elif flag == FLAG_CASTLE:
		var rf := from + 3
		var rt := from + 1
		if to < from:
			rf = from - 4
			rt = from - 1
		var rook := board[rt]
		board[rf] = rook
		board[rt] = 0
		var ri := pidx[rt]
		plist[us * 32 + ri] = rf
		pidx[rf] = ri
	castle = u_castle[s]
	ep = u_ep[s]
	half = u_half[s]
	key = u_key[s]
	pawn_key = u_pkey[s]
	mg = u_mg[s]
	eg = u_eg[s]
	phase = u_phase[s]


func make_null() -> void:
	var s := sp
	u_move[s] = 0
	u_ep[s] = ep
	u_half[s] = half
	u_key[s] = key
	sp = s + 1
	hist[hp] = key
	hp += 1
	if ep >= 0:
		key ^= _ze[ep & 7]
		ep = -1
	half = 0
	stm ^= 1
	key ^= _zs


func unmake_null() -> void:
	sp -= 1
	hp -= 1
	stm ^= 1
	ep = u_ep[sp]
	half = u_half[sp]
	key = u_key[sp]


func is_attacked(sq: int, by: int) -> bool:
	var base := by * 32
	var n := pcount[by]
	for i in n:
		var s := plist[base + i]
		var diff := sq - s + 119
		var bits := _att[diff]
		if bits == 0:
			continue
		var p := board[s]
		if (bits & _pbit[p]) == 0:
			continue
		var t := p & 7
		if t < BISHOP or t == KING:
			return true
		var d := _adelta[diff]
		var x := s + d
		while x != sq and board[x] == 0:
			x += d
		if x == sq:
			return true
	return false


func in_check() -> bool:
	return is_attacked(plist[stm * 32], stm ^ 1)


## Called right after make(m): true when the mover's king is safe.
func legal_after(m: int, was_in_check: bool) -> bool:
	var us := stm ^ 1
	var ksq := plist[us * 32]
	if was_in_check or ksq == ((m >> 7) & 127) or (m >> 17) == FLAG_EP:
		return not is_attacked(ksq, stm)
	var diff := (m & 127) - ksq + 119
	if (_att[diff] & ShadowTables.PB_Q) == 0:
		return true
	var d := _adelta[diff]
	var x := ksq + d
	while (x & 0x88) == 0:
		var q := board[x]
		if q != 0:
			if (q >> 3) == us:
				return true
			var t := q & 7
			if t == QUEEN:
				return false
			if d == 1 or d == -1 or d == 16 or d == -16:
				return t != ROOK
			return t != BISHOP
		x += d
	return true


## Called right after make(m): true when the side now to move is in check.
func gives_check(m: int) -> bool:
	var ksq := plist[stm * 32]
	var flag := m >> 17
	if flag == FLAG_EP or flag == FLAG_CASTLE:
		return is_attacked(ksq, stm ^ 1)
	var to := (m >> 7) & 127
	var p := board[to]
	var diff := ksq - to + 119
	if (_att[diff] & _pbit[p]) != 0:
		var t := p & 7
		if t < BISHOP:
			return true
		var d := _adelta[diff]
		var x := to + d
		while x != ksq and board[x] == 0:
			x += d
		if x == ksq:
			return true
	var dd := (m & 127) - ksq + 119
	if (_att[dd] & ShadowTables.PB_Q) == 0:
		return false
	var d2 := _adelta[dd]
	var y := ksq + d2
	while (y & 0x88) == 0 and board[y] == 0:
		y += d2
	if (y & 0x88) != 0:
		return false
	var q := board[y]
	if (q >> 3) == stm:
		return false
	var qt := q & 7
	if qt == QUEEN:
		return true
	if d2 == 1 or d2 == -1 or d2 == 16 or d2 == -16:
		return qt == ROOK
	return qt == BISHOP


## Captures and queen promotions only (quiescence).
func gen_captures(start: int) -> int:
	var n := start
	var us := stm
	var them := us ^ 1
	var base := us * 32
	var count := pcount[us]
	var fwd := 16 if us == WHITE else -16
	var promo_rank := 7 if us == WHITE else 0
	for i in count:
		var from := plist[base + i]
		var p := board[from]
		var t := p & 7
		if t == PAWN:
			var to := from + fwd
			var promo := (to >> 4) == promo_rank
			if promo and board[to] == 0:
				mv[n] = from | (to << 7) | (QUEEN << 14)
				n += 1
			var c := to - 1
			if (c & 0x88) == 0:
				var q := board[c]
				if q != 0:
					if (q >> 3) == them:
						mv[n] = from | (c << 7) | ((QUEEN << 14) if promo else 0)
						n += 1
				elif c == ep:
					mv[n] = from | (c << 7) | (FLAG_EP << 17)
					n += 1
			c = to + 1
			if (c & 0x88) == 0:
				var q2 := board[c]
				if q2 != 0:
					if (q2 >> 3) == them:
						mv[n] = from | (c << 7) | ((QUEEN << 14) if promo else 0)
						n += 1
				elif c == ep:
					mv[n] = from | (c << 7) | (FLAG_EP << 17)
					n += 1
		elif t == KNIGHT or t == KING:
			var dirs := N_DIRS if t == KNIGHT else DIRS
			for d in dirs:
				var to := from + d
				if (to & 0x88) == 0:
					var q := board[to]
					if q != 0 and (q >> 3) == them:
						mv[n] = from | (to << 7)
						n += 1
		else:
			var d0 := 4 if t == BISHOP else 0
			var d1 := 4 if t == ROOK else 8
			for di in range(d0, d1):
				var d := DIRS[di]
				var to := from + d
				while (to & 0x88) == 0 and board[to] == 0:
					to += d
				if (to & 0x88) == 0 and (board[to] >> 3) == them:
					mv[n] = from | (to << 7)
					n += 1
	return n


## Pseudo-legal generation into mv[start..]; returns the end index.
func gen(start: int, captures_only: bool, checked: bool) -> int:
	var n := start
	var us := stm
	var them := us ^ 1
	var base := us * 32
	var count := pcount[us]
	var fwd := 16 if us == WHITE else -16
	var start_rank := 1 if us == WHITE else 6
	var promo_rank := 7 if us == WHITE else 0
	for i in count:
		var from := plist[base + i]
		var p := board[from]
		var t := p & 7
		if t == PAWN:
			var to := from + fwd
			var promo := (to >> 4) == promo_rank
			if board[to] == 0:
				if promo:
					n = _add_promos(n, from, to, captures_only)
				elif not captures_only:
					mv[n] = from | (to << 7)
					n += 1
					if (from >> 4) == start_rank and board[to + fwd] == 0:
						mv[n] = from | ((to + fwd) << 7) | (FLAG_DOUBLE << 17)
						n += 1
			var c := to - 1
			if (c & 0x88) == 0:
				var q := board[c]
				if q != 0:
					if (q >> 3) == them:
						if promo:
							n = _add_promos(n, from, c, captures_only)
						else:
							mv[n] = from | (c << 7)
							n += 1
				elif c == ep:
					mv[n] = from | (c << 7) | (FLAG_EP << 17)
					n += 1
			c = to + 1
			if (c & 0x88) == 0:
				var q2 := board[c]
				if q2 != 0:
					if (q2 >> 3) == them:
						if promo:
							n = _add_promos(n, from, c, captures_only)
						else:
							mv[n] = from | (c << 7)
							n += 1
				elif c == ep:
					mv[n] = from | (c << 7) | (FLAG_EP << 17)
					n += 1
		elif t == KNIGHT:
			for d in N_DIRS:
				var to := from + d
				if (to & 0x88) != 0:
					continue
				var q := board[to]
				if q == 0:
					if not captures_only:
						mv[n] = from | (to << 7)
						n += 1
				elif (q >> 3) == them:
					mv[n] = from | (to << 7)
					n += 1
		elif t == KING:
			for d in DIRS:
				var to := from + d
				if (to & 0x88) != 0:
					continue
				var q := board[to]
				if q == 0:
					if not captures_only:
						mv[n] = from | (to << 7)
						n += 1
				elif (q >> 3) == them:
					mv[n] = from | (to << 7)
					n += 1
			if not captures_only and not checked and castle != 0:
				n = _gen_castles(n, from, us)
		else:
			var d0 := 4 if t == BISHOP else 0
			var d1 := 4 if t == ROOK else 8
			for di in range(d0, d1):
				var d := DIRS[di]
				var to := from + d
				while (to & 0x88) == 0:
					var q := board[to]
					if q == 0:
						if not captures_only:
							mv[n] = from | (to << 7)
							n += 1
					else:
						if (q >> 3) == them:
							mv[n] = from | (to << 7)
							n += 1
						break
					to += d
	return n


func _add_promos(n: int, from: int, to: int, queen_only: bool) -> int:
	var base := from | (to << 7)
	mv[n] = base | (QUEEN << 14)
	if queen_only:
		return n + 1
	mv[n + 1] = base | (KNIGHT << 14)
	mv[n + 2] = base | (ROOK << 14)
	mv[n + 3] = base | (BISHOP << 14)
	return n + 4


func _gen_castles(n: int, from: int, us: int) -> int:
	var them := us ^ 1
	if us == WHITE:
		if from != 4:
			return n
		if (castle & 1) != 0 and board[5] == 0 and board[6] == 0 and not is_attacked(5, them):
			mv[n] = 4 | (6 << 7) | (FLAG_CASTLE << 17)
			n += 1
		if (castle & 2) != 0 and board[3] == 0 and board[2] == 0 and board[1] == 0 and not is_attacked(3, them):
			mv[n] = 4 | (2 << 7) | (FLAG_CASTLE << 17)
			n += 1
	else:
		if from != 0x74:
			return n
		if (castle & 4) != 0 and board[0x75] == 0 and board[0x76] == 0 and not is_attacked(0x75, them):
			mv[n] = 0x74 | (0x76 << 7) | (FLAG_CASTLE << 17)
			n += 1
		if (castle & 8) != 0 and board[0x73] == 0 and board[0x72] == 0 and board[0x71] == 0 and not is_attacked(0x73, them):
			mv[n] = 0x74 | (0x72 << 7) | (FLAG_CASTLE << 17)
			n += 1
	return n


func legal_moves() -> PackedInt32Array:
	var out := PackedInt32Array()
	var checked := in_check()
	var start := mtop
	var end := gen(start, false, checked)
	mtop = end
	for i in range(start, end):
		var m := mv[i]
		make(m)
		if legal_after(m, checked):
			out.append(m)
		unmake()
	mtop = start
	return out


func perft(depth: int) -> int:
	var checked := in_check()
	var start := mtop
	var end := gen(start, false, checked)
	mtop = end
	var total := 0
	for i in range(start, end):
		var m := mv[i]
		make(m)
		if legal_after(m, checked):
			total += 1 if depth <= 1 else perft(depth - 1)
		unmake()
	mtop = start
	return total


func has_non_pawn(side: int) -> bool:
	var c := side << 3
	return cnt[c | KNIGHT] + cnt[c | BISHOP] + cnt[c | ROOK] + cnt[c | QUEEN] > 0


func insufficient() -> bool:
	if cnt[1] + cnt[9] + cnt[4] + cnt[12] + cnt[5] + cnt[13] != 0:
		return false
	return cnt[2] + cnt[3] + cnt[10] + cnt[11] <= 1


func is_repetition() -> bool:
	var i := hp - 2
	var lo := maxi(0, hp - half)
	while i >= lo:
		if hist[i] == key:
			return true
		i -= 2
	return false


static func sq_name(s88: int) -> String:
	return "%s%d" % [char(97 + (s88 & 7)), (s88 >> 4) + 1]


static func move_to_uci(m: int) -> String:
	if m == 0:
		return ""
	var s := sq_name(m & 127) + sq_name((m >> 7) & 127)
	var promo := (m >> 14) & 7
	if promo != 0:
		s += " pnbrqk"[promo]
	return s


func parse_uci(uci: String) -> int:
	var u := uci.strip_edges().to_lower()
	if u.length() < 4:
		return 0
	var f1 := u.unicode_at(0) - 97
	var r1 := u.unicode_at(1) - 49
	var f2 := u.unicode_at(2) - 97
	var r2 := u.unicode_at(3) - 49
	if f1 < 0 or f1 > 7 or r1 < 0 or r1 > 7 or f2 < 0 or f2 > 7 or r2 < 0 or r2 > 7:
		return 0
	var from := (r1 << 4) | f1
	var to := (r2 << 4) | f2
	var promo := 0
	if u.length() >= 5:
		promo = "pnbrqk".find(u[4]) + 1
	for m in legal_moves():
		if (m & 127) == from and ((m >> 7) & 127) == to:
			var mp := (m >> 14) & 7
			if mp == promo or (promo == 0 and mp == QUEEN):
				return m
	return 0


func fen() -> String:
	var rows := PackedStringArray()
	for r in range(7, -1, -1):
		var row := ""
		var empty := 0
		for f in 8:
			var p := board[(r << 4) | f]
			if p == 0:
				empty += 1
				continue
			if empty > 0:
				row += str(empty)
				empty = 0
			var ch := " PNBRQK"[p & 7]
			row += ch if (p >> 3) == WHITE else ch.to_lower()
		if empty > 0:
			row += str(empty)
		rows.append(row)
	var eps := "-" if ep < 0 else sq_name(ep)
	return "%s %s %s %s %d %d" % ["/".join(rows), "w" if stm == WHITE else "b", Fen.castling_string(castle), eps, half, fullmove]
