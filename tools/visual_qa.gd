extends SceneTree

const OUT_DIR := "res://docs/screenshots"

var _shots: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("visual_qa needs a display")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await _run()
	print("visual_qa wrote %d shots" % _shots.size())
	for s in _shots:
		print("  ", s)
	quit(0 if _shots.size() >= 3 else 1)


func _run() -> void:
	change_scene_to_file("res://scenes/menus/main_menu.tscn")
	await _settle(1.4)
	_shot("01-main-menu.png")
	GameSession.configure_local(false)
	change_scene_to_file("res://scenes/main/game.tscn")
	await _settle(1.2)
	_shot("02-new-game.png")
	var world := _controller()
	if world == null:
		return
	world._try_play(ChessTypes.parse_square("e2"), ChessTypes.parse_square("e4"))
	await _settle(0.55)
	_shot("03-after-e4.png")
	world._try_play(ChessTypes.parse_square("e7"), ChessTypes.parse_square("e5"))
	await _settle(0.55)
	world._select(ChessTypes.parse_square("g1"))
	await _settle(0.25)
	_shot("04-legal-moves.png")
	world._try_play(ChessTypes.parse_square("g1"), ChessTypes.parse_square("f3"))
	await _settle(0.45)
	world._try_play(ChessTypes.parse_square("b8"), ChessTypes.parse_square("c6"))
	await _settle(0.35)
	world._try_play(ChessTypes.parse_square("f1"), ChessTypes.parse_square("c4"))
	await _settle(0.35)
	world._try_play(ChessTypes.parse_square("g8"), ChessTypes.parse_square("f6"))
	await _settle(0.35)
	world._try_play(ChessTypes.parse_square("c4"), ChessTypes.parse_square("f7"))
	await _settle(0.55)
	_shot("05-capture.png")
	if world.engine.in_check():
		_shot("06-check.png")
	change_scene_to_file("res://scenes/menus/settings_menu.tscn")
	await _settle(0.7)
	_shot("07-settings.png")


func _controller() -> GameController:
	var scene := root.get_child(0)
	if scene == null:
		return null
	return scene.get_node_or_null("World") as GameController


func _settle(seconds: float) -> void:
	await create_timer(seconds).timeout
	await process_frame
	await process_frame


func _shot(name: String) -> void:
	var vp := root.get_viewport()
	if vp == null:
		return
	var img := vp.get_texture().get_image()
	if img == null:
		return
	var path := OUT_DIR.path_join(name)
	var abs_path := ProjectSettings.globalize_path(path)
	img.save_png(abs_path)
	_shots.append(abs_path)
