extends SceneTree

## Engine / AI / PGN / puzzle suites. The presentation suite runs from
## tests/scene_runner.tscn because it needs autoloads.

const _Engine := preload("res://tests/test_chess_engine.gd")
const _Pgn := preload("res://tests/test_pgn.gd")
const _AI := preload("res://tests/test_ai.gd")
const _Puzzles := preload("res://tests/test_puzzles.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	print("Running Shadow Chess 3D tests...")
	var t0 := Time.get_ticks_msec()
	var ok: bool = _Engine.new().run_all()
	ok = _Pgn.new().run_all() and ok
	ok = _Puzzles.new().run_all() and ok
	var ai_ok: bool = await _AI.new().run(self)
	ok = ai_ok and ok
	print("All suites %s in %d ms" % ["PASSED" if ok else "FAILED", Time.get_ticks_msec() - t0])
	quit(0 if ok else 1)
