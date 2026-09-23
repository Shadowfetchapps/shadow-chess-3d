extends SceneTree

## Prints Shadow's reached depth and speed per level on a few middlegame
## positions:  godot --headless --path . --script res://tools/bench_ai.gd

const POSITIONS := [
	"r1bq1rk1/pp2bppp/2n1pn2/3p4/2PP4/2N1PN2/PP3PPP/R2QKB1R w KQ - 0 8",
	"r2q1rk1/1b1nbppp/p2ppn2/1p6/3NP3/1BN1BP2/PPPQ2PP/2KR3R w - - 0 12",
	"2r2rk1/pp1bqppp/2n1p3/3pP3/3P4/P1PB1N2/5PPP/R2QR1K1 b - - 0 16",
]


func _initialize() -> void:
	ChessAI.warmup()
	for l in ChessAI.levels():
		var depth := 0
		var nps := 0
		var ms := 0
		for fen in POSITIONS:
			var job := ChessAI.SearchJob.new()
			job.start_fen = fen
			job.level = str(l["id"])
			job.use_book = false
			var t := Time.get_ticks_msec()
			job.run()
			ms += Time.get_ticks_msec() - t
			depth += job.depth
			nps += job.nps
		print("%-9s depth %.1f  nps %6d  %5d ms/move" % [l["id"], depth / float(POSITIONS.size()), nps / POSITIONS.size(), ms / POSITIONS.size()])
	quit()
