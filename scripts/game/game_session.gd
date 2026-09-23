extends Node

## Hand-off between the menus and the game scene: what kind of game to start
## and with which options. The game scene reads this once in _ready.

enum Mode { LOCAL, AI, PUZZLE, ANALYSIS }

var mode: Mode = Mode.LOCAL
var ai_side: int = ChessTypes.BLACK
var ai_level: String = "club"
var load_path: String = ""
var pending_fen: String = ""
var pending_pgn: String = ""
var white_name: String = "White"
var black_name: String = "Black"
var clock_base: int = 600
var clock_increment: int = 0
var puzzle: Dictionary = {}
var puzzle_index: int = -1
var resume_review: bool = false


func reset_defaults() -> void:
	mode = Mode.LOCAL
	ai_side = ChessTypes.BLACK
	ai_level = SettingsStore.ai_level
	load_path = ""
	pending_fen = ""
	pending_pgn = ""
	white_name = "White"
	black_name = "Black"
	var tc := SettingsStore.clock_base_increment()
	clock_base = tc.x
	clock_increment = tc.y
	puzzle = {}
	puzzle_index = -1
	resume_review = false


## Legacy entry points kept for tools and older call sites.
var clock_seconds: int:
	get:
		return clock_base
	set(v):
		clock_base = v


func configure_local(with_clock: bool = true, preset: String = "") -> void:
	reset_defaults()
	mode = Mode.LOCAL
	white_name = "White"
	black_name = "Black"
	if not with_clock:
		clock_base = 0
		clock_increment = 0
	elif preset != "":
		_set_clock(preset)


func configure_ai(player_white: bool = true, level: String = "", preset: String = "") -> void:
	reset_defaults()
	mode = Mode.AI
	ai_side = ChessTypes.BLACK if player_white else ChessTypes.WHITE
	if level != "":
		ai_level = level
	var me := SettingsStore.player_name
	white_name = me if player_white else "Shadow"
	black_name = "Shadow" if player_white else me
	if preset != "":
		_set_clock(preset)


func configure_analysis(fen: String = "", pgn: String = "") -> void:
	reset_defaults()
	mode = Mode.ANALYSIS
	clock_base = 0
	clock_increment = 0
	pending_fen = fen
	pending_pgn = pgn
	white_name = "White"
	black_name = "Black"


func configure_puzzle(p: Dictionary, index: int) -> void:
	reset_defaults()
	mode = Mode.PUZZLE
	puzzle = p
	puzzle_index = index
	clock_base = 0
	clock_increment = 0
	var fen := str(p.get("fen", ""))
	pending_fen = fen
	var white_to_move := fen.split(" ").size() > 1 and fen.split(" ")[1] == "w"
	ai_side = ChessTypes.BLACK if white_to_move else ChessTypes.WHITE
	white_name = SettingsStore.player_name if white_to_move else "Defender"
	black_name = "Defender" if white_to_move else SettingsStore.player_name


func _set_clock(preset: String) -> void:
	var tc := SettingsStore.clock_base_increment(preset)
	clock_base = tc.x
	clock_increment = tc.y


func is_ai() -> bool:
	return mode == Mode.AI


func human_sides() -> Array[int]:
	match mode:
		Mode.AI, Mode.PUZZLE:
			return [ChessTypes.opp(ai_side)]
		_:
			return [ChessTypes.WHITE, ChessTypes.BLACK]


func mode_label() -> String:
	match mode:
		Mode.AI:
			return "vs Shadow · %s" % _level_name(ai_level)
		Mode.PUZZLE:
			return "Puzzle"
		Mode.ANALYSIS:
			return "Analysis board"
		_:
			return "Two players"


func time_control_label() -> String:
	if clock_base <= 0:
		return "No clock"
	return "%d+%d" % [int(clock_base / 60.0), clock_increment]


func _level_name(id: String) -> String:
	for l in ChessAI.levels():
		if str(l.get("id", "")) == id:
			return str(l.get("name", id))
	return id.capitalize()
