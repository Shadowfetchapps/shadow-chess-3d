class_name ShadowTables
extends RefCounted

## Read-only lookup tables for the Shadow search (0x88 board, piece code = type | color << 3).
## Built once by ensure_tables(); the opening book by ensure_book(). Both are
## idempotent and guarded by a mutex so a worker thread may call them safely.

const BOOK_PATH := "res://data/opening_book.txt"

const PB_WP := 1
const PB_BP := 2
const PB_N := 4
const PB_B := 8
const PB_R := 16
const PB_Q := 32
const PB_K := 64

const MG_VALUE: Array[int] = [0, 82, 337, 365, 477, 1025, 0]
const EG_VALUE: Array[int] = [0, 94, 281, 297, 512, 936, 0]
const PHASE_INC: Array[int] = [0, 0, 1, 1, 2, 4, 0]

# PeSTO piece-square tables (Rofchade), a8 = index 0, from White's point of view.
const MG_PAWN: Array[int] = [
	0, 0, 0, 0, 0, 0, 0, 0,
	98, 134, 61, 95, 68, 126, 34, -11,
	-6, 7, 26, 31, 65, 56, 25, -20,
	-14, 13, 6, 21, 23, 12, 17, -23,
	-27, -2, -5, 12, 17, 6, 10, -25,
	-26, -4, -4, -10, 3, 3, 33, -12,
	-35, -1, -20, -23, -15, 24, 38, -22,
	0, 0, 0, 0, 0, 0, 0, 0,
]
const EG_PAWN: Array[int] = [
	0, 0, 0, 0, 0, 0, 0, 0,
	178, 173, 158, 134, 147, 132, 165, 187,
	94, 100, 85, 67, 56, 53, 82, 84,
	32, 24, 13, 5, -2, 4, 17, 17,
	13, 9, -3, -7, -7, -8, 3, -1,
	4, 7, -6, 1, 0, -5, -1, -8,
	13, 8, 8, 10, 13, 0, 2, -7,
	0, 0, 0, 0, 0, 0, 0, 0,
]
const MG_KNIGHT: Array[int] = [
	-167, -89, -34, -49, 61, -97, -15, -107,
	-73, -41, 72, 36, 23, 62, 7, -17,
	-47, 60, 37, 65, 84, 129, 73, 44,
	-9, 17, 19, 53, 37, 69, 18, 22,
	-13, 4, 16, 13, 28, 19, 21, -8,
	-23, -9, 12, 10, 19, 17, 25, -16,
	-29, -53, -12, -3, -1, 18, -14, -19,
	-105, -21, -58, -33, -17, -28, -19, -23,
]
const EG_KNIGHT: Array[int] = [
	-58, -38, -13, -28, -31, -27, -63, -99,
	-25, -8, -25, -2, -9, -25, -24, -52,
	-24, -20, 10, 9, -1, -9, -19, -41,
	-17, 3, 22, 22, 22, 11, 8, -18,
	-18, -6, 16, 25, 16, 17, 4, -18,
	-23, -3, -1, 15, 10, -3, -20, -22,
	-42, -20, -10, -5, -2, -20, -23, -44,
	-29, -51, -23, -15, -22, -18, -50, -64,
]
const MG_BISHOP: Array[int] = [
	-29, 4, -82, -37, -25, -42, 7, -8,
	-26, 16, -18, -13, 30, 59, 18, -47,
	-16, 37, 43, 40, 35, 50, 37, -2,
	-4, 5, 19, 50, 37, 37, 7, -2,
	-6, 13, 13, 26, 34, 12, 10, 4,
	0, 15, 15, 15, 14, 27, 18, 10,
	4, 15, 16, 0, 7, 21, 33, 1,
	-33, -3, -14, -21, -13, -12, -39, -21,
]
const EG_BISHOP: Array[int] = [
	-14, -21, -11, -8, -7, -9, -17, -24,
	-8, -4, 7, -12, -3, -13, -4, -14,
	2, -8, 0, -1, -2, 6, 0, 4,
	-3, 9, 12, 9, 14, 10, 3, 2,
	-6, 3, 13, 19, 7, 10, -3, -9,
	-12, -3, 8, 10, 13, 3, -7, -15,
	-14, -18, -7, -1, 4, -9, -15, -27,
	-23, -9, -23, -5, -9, -16, -5, -17,
]
const MG_ROOK: Array[int] = [
	32, 42, 32, 51, 63, 9, 31, 43,
	27, 32, 58, 62, 80, 67, 26, 44,
	-5, 19, 26, 36, 17, 45, 61, 16,
	-24, -11, 7, 26, 24, 35, -8, -20,
	-36, -26, -12, -1, 9, -7, 6, -23,
	-45, -25, -16, -17, 3, 0, -5, -33,
	-44, -16, -20, -9, -1, 11, -6, -71,
	-19, -13, 1, 17, 16, 7, -37, -26,
]
const EG_ROOK: Array[int] = [
	13, 10, 18, 15, 12, 12, 8, 5,
	11, 13, 13, 11, -3, 3, 8, 3,
	7, 7, 7, 5, 4, -3, -5, -3,
	4, 3, 13, 1, 2, 1, -1, 2,
	3, 5, 8, 4, -5, -6, -8, -11,
	-4, 0, -5, -1, -7, -12, -8, -16,
	-6, -6, 0, 2, -9, -9, -11, -3,
	-9, 2, 3, -1, -5, -13, 4, -20,
]
const MG_QUEEN: Array[int] = [
	-28, 0, 29, 12, 59, 44, 43, 45,
	-24, -39, -5, 1, -16, 57, 28, 54,
	-13, -17, 7, 8, 29, 56, 47, 57,
	-27, -27, -16, -16, -1, 17, -2, 1,
	-9, -26, -9, -10, -2, -4, 3, -3,
	-14, 2, -11, -2, -5, 2, 14, 5,
	-35, -8, 11, 2, 8, 15, -3, 1,
	-1, -18, -9, 10, -15, -25, -31, -50,
]
const EG_QUEEN: Array[int] = [
	-9, 22, 22, 27, 27, 19, 10, 20,
	-17, 20, 32, 41, 58, 25, 30, 0,
	-20, 6, 9, 49, 47, 35, 19, 9,
	3, 22, 24, 45, 57, 40, 57, 36,
	-18, 28, 19, 47, 31, 34, 39, 23,
	-16, -27, 15, 6, 9, 17, 10, 5,
	-22, -23, -30, -16, -16, -23, -36, -32,
	-33, -28, -22, -43, -5, -32, -20, -41,
]
const MG_KING: Array[int] = [
	-65, 23, 16, -15, -56, -34, 2, 13,
	29, -1, -20, -7, -8, -4, -38, -29,
	-9, 24, 2, -16, -20, 6, 22, -22,
	-17, -20, -12, -27, -30, -25, -14, -36,
	-49, -1, -27, -39, -46, -44, -33, -51,
	-14, -14, -22, -46, -44, -30, -15, -27,
	1, 7, -8, -64, -43, -16, 9, 8,
	-15, 36, 12, -54, 8, -28, 24, 14,
]
const EG_KING: Array[int] = [
	-74, -35, -18, -18, -11, 15, 4, -17,
	-12, 17, 14, 17, 17, 38, 23, 11,
	10, 17, 23, 15, 20, 45, 44, 13,
	-8, 22, 24, 27, 26, 33, 26, 3,
	-18, -4, 21, 24, 27, 23, 9, -11,
	-19, -3, 11, 21, 23, 16, 7, -9,
	-27, -11, 4, 13, 14, 4, -5, -17,
	-53, -34, -21, -11, -28, -14, -24, -43,
]

static var zob: PackedInt64Array = PackedInt64Array()
static var zob_castle: PackedInt64Array = PackedInt64Array()
static var zob_ep: PackedInt64Array = PackedInt64Array()
static var zob_side: int = 0
static var pst_mg: PackedInt32Array = PackedInt32Array()
static var pst_eg: PackedInt32Array = PackedInt32Array()
static var phase_inc: PackedInt32Array = PackedInt32Array()
static var piece_bit: PackedInt32Array = PackedInt32Array()
static var att_bits: PackedInt32Array = PackedInt32Array()
static var att_delta: PackedInt32Array = PackedInt32Array()
static var castle_mask: PackedInt32Array = PackedInt32Array()

static var book: Dictionary = {}
static var book_lines: int = 0
static var book_errors: PackedStringArray = PackedStringArray()

static var _tables_ready: bool = false
static var _book_ready: bool = false
static var _mutex: Mutex = Mutex.new()


static func ensure() -> void:
	ensure_tables()
	ensure_book()


static func ensure_tables() -> void:
	if _tables_ready:
		return
	_mutex.lock()
	if not _tables_ready:
		_build_tables()
		_tables_ready = true
	_mutex.unlock()


static func ensure_book() -> void:
	if _book_ready:
		return
	ensure_tables()
	_mutex.lock()
	if not _book_ready:
		_load_book()
		_book_ready = true
	_mutex.unlock()


static func sq64(s88: int) -> int:
	return ((s88 >> 4) << 3) | (s88 & 7)


static func sq88(s64: int) -> int:
	return ((s64 >> 3) << 4) | (s64 & 7)


static func _pesto(type: int, mg: bool) -> Array[int]:
	match type:
		1:
			return MG_PAWN if mg else EG_PAWN
		2:
			return MG_KNIGHT if mg else EG_KNIGHT
		3:
			return MG_BISHOP if mg else EG_BISHOP
		4:
			return MG_ROOK if mg else EG_ROOK
		5:
			return MG_QUEEN if mg else EG_QUEEN
		_:
			return MG_KING if mg else EG_KING


static func _build_tables() -> void:
	ChessZobrist.ensure()
	var z := PackedInt64Array()
	z.resize(16 * 128)
	var pm := PackedInt32Array()
	pm.resize(16 * 128)
	var pe := PackedInt32Array()
	pe.resize(16 * 128)
	var ph := PackedInt32Array()
	ph.resize(16)
	var pb := PackedInt32Array()
	pb.resize(16)
	for color in 2:
		for type in range(1, 7):
			var code := type | (color << 3)
			ph[code] = PHASE_INC[type]
			match type:
				1:
					pb[code] = PB_WP if color == 0 else PB_BP
				2:
					pb[code] = PB_N
				3:
					pb[code] = PB_B
				4:
					pb[code] = PB_R
				5:
					pb[code] = PB_Q
				6:
					pb[code] = PB_K
			var mg_t := _pesto(type, true)
			var eg_t := _pesto(type, false)
			for s in 64:
				var s88 := sq88(s)
				z[code * 128 + s88] = ChessZobrist.piece_keys[(color * 6 + type - 1) * 64 + s]
				var idx := (s ^ 56) if color == 0 else s
				var sign := 1 if color == 0 else -1
				pm[code * 128 + s88] = sign * (MG_VALUE[type] + mg_t[idx])
				pe[code * 128 + s88] = sign * (EG_VALUE[type] + eg_t[idx])
	var ab := PackedInt32Array()
	ab.resize(240)
	var ad := PackedInt32Array()
	ad.resize(240)
	for d: int in [33, 31, 18, 14, -33, -31, -18, -14]:
		ab[d + 119] |= PB_N
	for d: int in [1, -1, 16, -16]:
		ab[d + 119] |= PB_K
		for k in range(1, 8):
			ab[d * k + 119] |= PB_R | PB_Q
			ad[d * k + 119] = d
	for d: int in [15, 17, -15, -17]:
		ab[d + 119] |= PB_K
		for k in range(1, 8):
			ab[d * k + 119] |= PB_B | PB_Q
			ad[d * k + 119] = d
	ab[15 + 119] |= PB_WP
	ab[17 + 119] |= PB_WP
	ab[-15 + 119] |= PB_BP
	ab[-17 + 119] |= PB_BP
	var cm := PackedInt32Array()
	cm.resize(128)
	cm.fill(15)
	cm[4] = 15 & ~3
	cm[7] = 15 & ~1
	cm[0] = 15 & ~2
	cm[0x74] = 15 & ~12
	cm[0x77] = 15 & ~4
	cm[0x70] = 15 & ~8
	zob = z
	zob_castle = ChessZobrist.castle_keys
	zob_ep = ChessZobrist.ep_keys
	zob_side = ChessZobrist.side_key
	pst_mg = pm
	pst_eg = pe
	phase_inc = ph
	piece_bit = pb
	att_bits = ab
	att_delta = ad
	castle_mask = cm


static func _load_book() -> void:
	var map := {}
	var errors := PackedStringArray()
	var count := 0
	var f := FileAccess.open(BOOK_PATH, FileAccess.READ)
	if f != null:
		var text := f.get_as_text()
		f.close()
		var board := ShadowBoard.new()
		var line_no := 0
		for raw in text.split("\n"):
			line_no += 1
			var line := raw.strip_edges()
			if line.is_empty() or line.begins_with("#"):
				continue
			board.set_fen(ChessTypes.START_FEN)
			var ok := true
			for tok in line.split(" ", false):
				var m := board.parse_uci(tok)
				if m == 0:
					errors.append("line %d: illegal move %s" % [line_no, tok])
					ok = false
					break
				var entry: Dictionary = map.get(board.key, {})
				entry[tok] = int(entry.get(tok, 0)) + 1
				map[board.key] = entry
				board.make(m)
			if ok:
				count += 1
	book = map
	book_lines = count
	book_errors = errors


## Book moves for a position key as [[uci, weight], ...]; empty when out of book.
static func book_moves(key: int) -> Array:
	ensure_book()
	var out := []
	_mutex.lock()
	var entry: Dictionary = book.get(key, {})
	for uci in entry:
		out.append([str(uci), int(entry[uci])])
	_mutex.unlock()
	return out
