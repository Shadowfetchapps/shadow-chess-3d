class_name ChessZobrist
extends RefCounted

## Deterministic 64-bit Zobrist keys shared by ChessEngine and the Shadow search.
## Piece index = (color * 6 + type - 1) * 64 + square (a1 = 0).
## The en-passant file is hashed only when a pawn of the side to move stands
## beside the double-pushed pawn (i.e. an en-passant capture is pseudo-legal).

const SEED := 0x5AD0C4E55

static var piece_keys: PackedInt64Array = PackedInt64Array()
static var castle_keys: PackedInt64Array = PackedInt64Array()
static var ep_keys: PackedInt64Array = PackedInt64Array()
static var side_key: int = 0
static var _ready: bool = false
static var _mutex: Mutex = Mutex.new()


static func ensure() -> void:
	if _ready:
		return
	_mutex.lock()
	if not _ready:
		_build()
		_ready = true
	_mutex.unlock()


static func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var pk := PackedInt64Array()
	pk.resize(768)
	for i in 768:
		pk[i] = _rand64(rng)
	var base: Array[int] = [_rand64(rng), _rand64(rng), _rand64(rng), _rand64(rng)]
	var ck := PackedInt64Array()
	ck.resize(16)
	for rights in 16:
		var k := 0
		for b in 4:
			if rights & (1 << b):
				k ^= base[b]
		ck[rights] = k
	var ek := PackedInt64Array()
	ek.resize(8)
	for f in 8:
		ek[f] = _rand64(rng)
	side_key = _rand64(rng)
	piece_keys = pk
	castle_keys = ck
	ep_keys = ek


static func _rand64(rng: RandomNumberGenerator) -> int:
	var hi := int(rng.randi())
	var lo := int(rng.randi())
	return (hi << 32) ^ lo


static func piece_index(packed: int, sq: int) -> int:
	return (ChessTypes.pcolor(packed) * 6 + ChessTypes.ptype(packed) - 1) * 64 + sq


## True when the side to move has a pawn that could capture en passant on ep_sq.
static func ep_capturable(squares: PackedInt32Array, ep_sq: int, side: int) -> bool:
	if ep_sq < 0:
		return false
	var f := ep_sq & 7
	var pawn_rank := 4 if side == ChessTypes.WHITE else 3
	var want := ChessTypes.pack(ChessTypes.PAWN, side)
	if f > 0 and squares[(pawn_rank << 3) | (f - 1)] == want:
		return true
	if f < 7 and squares[(pawn_rank << 3) | (f + 1)] == want:
		return true
	return false


static func compute(squares: PackedInt32Array, side: int, castling: int, ep_sq: int) -> int:
	ensure()
	var k := 0
	for s in 64:
		var p := squares[s]
		if p != 0:
			k ^= piece_keys[piece_index(p, s)]
	if side == ChessTypes.BLACK:
		k ^= side_key
	k ^= castle_keys[castling & 15]
	if ep_capturable(squares, ep_sq, side):
		k ^= ep_keys[ep_sq & 7]
	return k
