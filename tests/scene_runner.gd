extends Node

## Scene-based test entry point. Unlike `--script` runs, autoloads exist here,
## so the presentation suite and an end-to-end controller check can run.
## godot --headless --path . res://tests/scene_runner.tscn

const _Presentation := preload("res://tests/test_presentation.gd")

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("Running Shadow Chess 3D presentation tests...")
	var look = _Presentation.new()
	var ok: bool = look.run_all()
	ok = await _controller_flow() and ok
	get_tree().quit(0 if ok else 1)


func _check(name: String, cond: bool) -> void:
	if cond:
		_passed += 1
		print("  ok    ", name)
	else:
		_failed += 1
		print("  FAIL  ", name)


## Headless frames run faster than real time and animations are tweened in
## seconds, so wait on the clock as well as on frames.
func _frames(n: int) -> void:
	await get_tree().create_timer(n * 0.03).timeout
	await get_tree().process_frame


## Drives the real controller the way the HUD does: an under-promotion
## through the picker path, typed moves, review, and undo.
func _controller_flow() -> bool:
	print("controller")
	SettingsStore.auto_queen = false
	SettingsStore.reduce_motion = true
	GameSession.configure_local(false)
	# Keep a pawn each so the knight promotion doesn't leave insufficient material.
	GameSession.pending_fen = "8/4P1k1/7p/8/8/8/P4K2/8 w - - 0 1"
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	await _frames(3)
	var c := game.get_node("World") as GameController
	var asked := [false]
	c.promotion_requested.connect(func(_f, _t, _c): asked[0] = true)
	c._select(ChessTypes.parse_square("e7"))
	c._try_move(ChessTypes.parse_square("e7"), ChessTypes.parse_square("e8"), false)
	_check("promotion asks for a piece", asked[0] and c.engine.history.is_empty())
	c.complete_promotion(ChessTypes.KNIGHT)
	await _frames(20)
	_check("under-promotion to knight", c.engine.history.size() == 1 and c.engine.history[0].promotion == ChessTypes.KNIGHT)
	_check("knight is on e8", ChessTypes.ptype(c.engine.piece_at(ChessTypes.parse_square("e8"))) == ChessTypes.KNIGHT)
	_check("typed SAN plays", c.play_text("Kh7"))
	await _frames(20)
	_check("typed UCI plays", c.play_text("f2e3"))
	await _frames(20)
	_check("three plies recorded", c.engine.history.size() == 3)
	_check("illegal text rejected", not c.play_text("Qz9"))
	c.set_view_ply(1)
	await _frames(5)
	_check("review shows an earlier ply", not c.is_live() and c.view_position().history.size() == 1)
	c.set_view_ply(3)
	await _frames(20)
	c.undo()
	await _frames(5)
	_check("undo takes back one ply in local play", c.engine.history.size() == 2 and c.is_live())
	game.queue_free()
	await get_tree().process_frame
	print("Shadow Chess controller  —  %d passed, %d failed" % [_passed, _failed])
	return _failed == 0
