extends Node

enum Mode { LOCAL, AI }

var mode: Mode = Mode.LOCAL
var ai_side: int = ChessTypes.BLACK
var load_path: String = ""
var pending_fen: String = ""
var white_name: String = "White"
var black_name: String = "Black"
var clock_seconds: int = 600


func reset_defaults() -> void:
	mode = Mode.LOCAL
	ai_side = ChessTypes.BLACK
	load_path = ""
	pending_fen = ""
	white_name = "White"
	black_name = "Black"
	clock_seconds = SettingsStore.clock_seconds


func configure_local(with_clock: bool = true) -> void:
	reset_defaults()
	mode = Mode.LOCAL
	white_name = "Player 1"
	black_name = "Player 2"
	clock_seconds = SettingsStore.clock_seconds if with_clock else 0


func configure_ai(player_white: bool = true) -> void:
	reset_defaults()
	mode = Mode.AI
	ai_side = ChessTypes.BLACK if player_white else ChessTypes.WHITE
	white_name = "You" if player_white else "Shadow"
	black_name = "Shadow" if player_white else "You"
	clock_seconds = SettingsStore.clock_seconds
