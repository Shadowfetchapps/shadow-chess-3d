extends SceneTree


func _initialize() -> void:
	print("Running Shadow Chess 3D engine tests...")
	var tests: TestChessEngine = TestChessEngine.new()
	var ok := tests.run_all()
	quit(0 if ok else 1)
