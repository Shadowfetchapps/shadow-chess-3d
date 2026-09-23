class_name ChessMove
extends RefCounted

var from_sq: int = 0
var to_sq: int = 0
var piece: int = 0
var captured: int = 0
var captured_sq: int = -1
var promotion: int = 0
var flags: int = 0
var prev_castling: int = 0
var prev_ep: int = -1
var prev_halfmove: int = 0
var prev_hash: int = 0
var san: String = ""
var uci: String = ""


func is_capture() -> bool:
	return (flags & ChessTypes.FLAG_CAPTURE) != 0


func is_double_pawn() -> bool:
	return (flags & ChessTypes.FLAG_DOUBLE) != 0


func is_en_passant() -> bool:
	return (flags & ChessTypes.FLAG_EP) != 0


func is_castle() -> bool:
	return (flags & (ChessTypes.FLAG_CASTLE_K | ChessTypes.FLAG_CASTLE_Q)) != 0


func is_castle_kingside() -> bool:
	return (flags & ChessTypes.FLAG_CASTLE_K) != 0


func is_castle_queenside() -> bool:
	return (flags & ChessTypes.FLAG_CASTLE_Q) != 0


func is_promotion() -> bool:
	return (flags & ChessTypes.FLAG_PROMO) != 0


func matches(from_s: int, to_s: int, promo: int = 0) -> bool:
	if from_sq != from_s or to_sq != to_s:
		return false
	if is_promotion():
		return promo == 0 or promotion == promo
	return promo == 0 or promotion == promo


func to_uci() -> String:
	if not uci.is_empty():
		return uci
	var s := ChessTypes.algebraic(from_sq) + ChessTypes.algebraic(to_sq)
	if promotion != 0:
		s += ChessTypes.PIECE_LETTERS[promotion].to_lower()
	uci = s
	return uci


func duplicate_move() -> ChessMove:
	var m := ChessMove.new()
	m.from_sq = from_sq
	m.to_sq = to_sq
	m.piece = piece
	m.captured = captured
	m.captured_sq = captured_sq
	m.promotion = promotion
	m.flags = flags
	m.prev_castling = prev_castling
	m.prev_ep = prev_ep
	m.prev_halfmove = prev_halfmove
	m.prev_hash = prev_hash
	m.san = san
	m.uci = uci
	return m


func describe() -> String:
	if not san.is_empty():
		return san
	return to_uci()
