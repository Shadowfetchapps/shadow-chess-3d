extends SceneTree

const _Presentation := preload("res://tests/test_presentation.gd")


func _initialize() -> void:
	print("Running Shadow Chess 3D tests...")
	var engine: TestChessEngine = TestChessEngine.new()
	var look = _Presentation.new()
	var ok := engine.run_all()
	ok = look.run_all() and ok
	quit(0 if ok else 1)
