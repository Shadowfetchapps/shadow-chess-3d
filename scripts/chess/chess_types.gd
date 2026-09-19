class_name ChessTypes
extends RefCounted

const WHITE := 0
const BLACK := 1

const NONE := 0
const PAWN := 1
const KNIGHT := 2
const BISHOP := 3
const ROOK := 4
const QUEEN := 5
const KING := 6

const WK := 1
const WQ := 2
const BK := 4
const BQ := 8

const FLAG_CAPTURE := 1
const FLAG_DOUBLE := 2
const FLAG_EP := 4
const FLAG_CASTLE_K := 8
const FLAG_CASTLE_Q := 16
const FLAG_PROMO := 32

const FILE_NAMES: Array[String] = ["a", "b", "c", "d", "e", "f", "g", "h"]
const PIECE_LETTERS: Array[String] = ["", "P", "N", "B", "R", "Q", "K"]
const FEN_CHARS := " PNBRQK"

const KNIGHT_DELTAS: Array[Vector2i] = [
	Vector2i(1, 2), Vector2i(2, 1), Vector2i(-1, 2), Vector2i(-2, 1),
	Vector2i(1, -2), Vector2i(2, -1), Vector2i(-1, -2), Vector2i(-2, -1),
]
const KING_DELTAS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]
const BISHOP_DIRS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const ROOK_DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

const START_FEN := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"


static func opp(side: int) -> int:
	return 1 - side


static func pack(type: int, color: int) -> int:
	if type == NONE:
		return 0
	return type | (color << 4)


static func ptype(p: int) -> int:
	return p & 0x0F


static func pcolor(p: int) -> int:
	return p >> 4


static func sq(file: int, rank: int) -> int:
	return (rank << 3) | file


static func file_of(s: int) -> int:
	return s & 7


static func rank_of(s: int) -> int:
	return s >> 3


static func in_board(file: int, rank: int) -> bool:
	return file >= 0 and file < 8 and rank >= 0 and rank < 8


static func algebraic(s: int) -> String:
	if s < 0 or s > 63:
		return "-"
	return "%s%d" % [FILE_NAMES[file_of(s)], rank_of(s) + 1]


static func parse_square(text: String) -> int:
	if text.length() < 2:
		return -1
	var f := text.unicode_at(0) - 97
	var r := text.unicode_at(1) - 49
	if not in_board(f, r):
		return -1
	return sq(f, r)


static func piece_char(p: int) -> String:
	var t := ptype(p)
	if t == NONE:
		return "."
	var ch := PIECE_LETTERS[t]
	return ch if pcolor(p) == WHITE else ch.to_lower()


static func side_name(side: int) -> String:
	return "White" if side == WHITE else "Black"


static func piece_name(type: int) -> String:
	match type:
		PAWN:
			return "Pawn"
		KNIGHT:
			return "Knight"
		BISHOP:
			return "Bishop"
		ROOK:
			return "Rook"
		QUEEN:
			return "Queen"
		KING:
			return "King"
		_:
			return ""
