class_name ChessAI
extends RefCounted

## "Shadow" — the chess AI. Search runs in ShadowSearch (compact 0x88 board),
## usually on a WorkerThreadPool thread through SearchJob.

const DEFAULT_LEVEL := "club"
const ANALYSIS := "analysis"

const _LEVELS: Array[Dictionary] = [
	{"id": "beginner", "name": "Beginner", "elo": 600, "blurb": "Knows how the pieces move. Misses tactics and sometimes hangs material.",
		"depth": 2, "time": 200, "window": 160, "temp": 55.0, "blunder": 0.15, "blunder_max": 350, "book": false, "tt": 14},
	{"id": "casual", "name": "Casual", "elo": 1000, "blurb": "Friendly opponent that spots simple threats but plays loosely.",
		"depth": 3, "time": 500, "window": 70, "temp": 24.0, "blunder": 0.04, "blunder_max": 180, "book": true, "tt": 15},
	{"id": "club", "name": "Club", "elo": 1400, "blurb": "Solid club player: principled openings, punishes loose pieces.",
		"depth": 4, "time": 700, "window": 22, "temp": 8.0, "blunder": 0.0, "blunder_max": 0, "book": true, "tt": 16},
	{"id": "advanced", "name": "Advanced", "elo": 1700, "blurb": "Calculates several moves deep and rarely lets a tactic slip.",
		"depth": 6, "time": 1200, "window": 8, "temp": 3.0, "blunder": 0.0, "blunder_max": 0, "book": true, "tt": 17},
	{"id": "expert", "name": "Expert", "elo": 1900, "blurb": "Deep, accurate search with no deliberate mistakes.",
		"depth": 40, "time": 2000, "window": 0, "temp": 0.0, "blunder": 0.0, "blunder_max": 0, "book": true, "tt": 18},
	{"id": "master", "name": "Master", "elo": 2100, "blurb": "Shadow at full strength, thinking up to three seconds a move.",
		"depth": 60, "time": 3000, "window": 0, "temp": 0.0, "blunder": 0.0, "blunder_max": 0, "book": true, "tt": 18},
]
const _ANALYSIS_LEVEL: Dictionary = {"id": "analysis", "name": "Analysis", "elo": 0, "blurb": "",
	"depth": 60, "time": 5000, "window": 0, "temp": 0.0, "blunder": 0.0, "blunder_max": 0, "book": false, "tt": 18}


## Builds Zobrist/eval tables and loads the opening book. Call on the main thread.
static func warmup() -> void:
	ChessZobrist.ensure()
	ShadowTables.ensure()


static func levels() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l in _LEVELS:
		out.append({"id": l.id, "name": l.name, "elo": l.elo, "blurb": l.blurb})
	return out


static func level_id_from_legacy(old: String) -> String:
	match old:
		"easy":
			return "casual"
		"medium":
			return "club"
		"hard":
			return "advanced"
		"master":
			return "master"
		_:
			for l in _LEVELS:
				if l.id == old:
					return old
			return DEFAULT_LEVEL


static func level_config(level: String) -> Dictionary:
	if level == ANALYSIS:
		return _ANALYSIS_LEVEL
	var id := level_id_from_legacy(level)
	for l in _LEVELS:
		if l.id == id:
			return l
	return _LEVELS[2]


## Synchronous search on the calling thread. Returns a move from engine.generate_legal_moves().
static func choose(engine: ChessEngine, level: String = DEFAULT_LEVEL) -> ChessMove:
	var legal := engine.generate_legal_moves()
	if legal.is_empty():
		return null
	var job := SearchJob.new()
	job.start_fen = engine.start_fen
	job.moves_uci = engine.uci_history()
	job.level = level if level == ANALYSIS else level_id_from_legacy(level)
	job.run()
	if not job.error.is_empty() or job.position_key != engine.hash_key:
		job = SearchJob.new()
		job.start_fen = engine.to_fen()
		job.level = level if level == ANALYSIS else level_id_from_legacy(level)
		job.run()
	for m in legal:
		if m.to_uci() == job.best_uci:
			return m
	return legal[0]


static func _run_job(job: SearchJob) -> void:
	var t0 := Time.get_ticks_msec()
	ShadowTables.ensure()
	var cfg := level_config(job.level)
	var s := ShadowSearch.new()
	if not s.setup(job.start_fen, job.moves_uci, int(cfg.tt)):
		job.error = "Could not set up the position from start_fen + moves_uci"
		return
	job.position_key = s.key
	var rng := RandomNumberGenerator.new()
	if job.rng_seed >= 0:
		rng.seed = job.rng_seed
	else:
		rng.randomize()
	var legal := s.legal_moves()
	if legal.is_empty():
		job.score_cp = -ShadowSearch.MATE if s.in_check() else 0
		job.score_white_cp = job.score_cp if s.stm == ShadowBoard.WHITE else -job.score_cp
		return
	if job.use_book and bool(cfg.book) and not job.cancelled:
		var bm := _book_pick(s, rng)
		if bm != 0:
			job.best_uci = ShadowBoard.move_to_uci(bm)
			job.pv = PackedStringArray([job.best_uci])
			job.from_book = true
			job.elapsed_ms = Time.get_ticks_msec() - t0
			return
	var depth := int(cfg.depth) if job.max_depth < 0 else job.max_depth
	var time_ms := int(cfg.time) if job.time_ms < 0 else job.time_ms
	if cfg.id == "beginner" and job.max_depth < 0 and rng.randf() < 0.35:
		depth = 1
	s.job = job
	s.think(depth, time_ms, _search_margin(cfg))
	var move := s.best_move
	var score := s.best_score
	if _search_margin(cfg) > 0 and s.completed_depth > 0:
		var pick := _weak_pick(s, cfg, rng)
		move = s.final_moves[pick]
		score = s.final_scores[pick]
	job.best_uci = ShadowBoard.move_to_uci(move)
	job.score_cp = score
	job.score_white_cp = score if s.stm == ShadowBoard.WHITE else -score
	job.mate_in = ShadowSearch.mate_moves(score)
	job.depth = s.completed_depth
	job.nodes = s.nodes
	job.elapsed_ms = Time.get_ticks_msec() - t0
	job.nps = int(s.nodes * 1000.0 / maxi(1, s.elapsed_ms))
	var line := PackedStringArray()
	if move == s.best_move:
		for m in s.pv:
			line.append(ShadowBoard.move_to_uci(m))
	else:
		line.append(job.best_uci)
	job.pv = line


static func _book_pick(s: ShadowSearch, rng: RandomNumberGenerator) -> int:
	var entries := ShadowTables.book_moves(s.key)
	if entries.is_empty():
		return 0
	var total := 0
	var moves: PackedInt32Array = PackedInt32Array()
	var weights: PackedInt32Array = PackedInt32Array()
	for e in entries:
		var m := s.parse_uci(str(e[0]))
		if m != 0:
			moves.append(m)
			weights.append(int(e[1]))
			total += int(e[1])
	if total <= 0:
		return 0
	var roll := rng.randi_range(1, total)
	for i in moves.size():
		roll -= weights[i]
		if roll <= 0:
			return moves[i]
	return moves[0]


## Root scores are exact only above best - margin, so the search margin must
## cover both the softmax window and the blunder range.
static func _search_margin(cfg: Dictionary) -> int:
	var w := int(cfg.window)
	if w <= 0:
		return 0
	return maxi(w, int(cfg.blunder_max)) + 10


static func _weak_pick(s: ShadowSearch, cfg: Dictionary, rng: RandomNumberGenerator) -> int:
	var n := s.final_moves.size()
	var best := -ShadowSearch.INF
	var best_i := 0
	for i in n:
		if s.final_scores[i] > best:
			best = s.final_scores[i]
			best_i = i
	if best >= ShadowSearch.MATE_BOUND and cfg.id != "beginner":
		return best_i
	var exact_floor := best - _search_margin(cfg)
	if float(cfg.blunder) > 0.0 and rng.randf() < float(cfg.blunder):
		var bad: Array[int] = []
		for i in n:
			var sc := s.final_scores[i]
			if sc <= best - 60 and sc >= best - int(cfg.blunder_max) and sc > exact_floor and sc > -ShadowSearch.MATE_BOUND:
				bad.append(i)
		if not bad.is_empty():
			return bad[rng.randi_range(0, bad.size() - 1)]
	var window := int(cfg.window)
	var temp := maxf(1.0, float(cfg.temp))
	var weights: Array[float] = []
	var total := 0.0
	for i in n:
		var sc := s.final_scores[i]
		var w := 0.0
		if sc >= best - window and sc > exact_floor:
			w = exp(float(sc - best) / temp)
		weights.append(w)
		total += w
	if total <= 0.0:
		return best_i
	var roll := rng.randf() * total
	for i in n:
		roll -= weights[i]
		if roll <= 0.0 and weights[i] > 0.0:
			return i
	return best_i


class SearchJob:
	extends RefCounted

	# inputs (set on the main thread before WorkerThreadPool.add_task(job.run))
	var start_fen: String = ChessTypes.START_FEN
	var moves_uci: PackedStringArray = PackedStringArray()
	var level: String = "club"
	var time_ms: int = -1
	var max_depth: int = -1
	var use_book: bool = true
	var rng_seed: int = -1
	var cancelled: bool = false
	# outputs
	var best_uci: String = ""
	var score_cp: int = 0
	var score_white_cp: int = 0
	var mate_in: int = 0
	var depth: int = 0
	var nodes: int = 0
	var nps: int = 0
	var pv: PackedStringArray = PackedStringArray()
	var from_book: bool = false
	var elapsed_ms: int = 0
	var position_key: int = 0
	var error: String = ""

	func run() -> void:
		ChessAI._run_job(self)
