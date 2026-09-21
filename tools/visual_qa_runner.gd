extends Node

const OUT_DIR := "res://docs/screenshots"

var _shots: PackedStringArray = PackedStringArray()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await _run()
	print("visual_qa wrote %d shots" % _shots.size())
	for s in _shots:
		print("  ", s)
	get_tree().quit(0 if _shots.size() >= 4 else 1)


func _run() -> void:
	await _settle(2.0)
	_shot("01-main-menu.png")
	GameSession.configure_local(false)
	get_tree().change_scene_to_file("res://scenes/main/game.tscn")
	await _settle(1.8)
	_shot("02-new-game.png")
	var world := _controller()
	if world == null:
		return
	world._try_play(ChessTypes.parse_square("e2"), ChessTypes.parse_square("e4"))
	await _settle(0.55)
	_shot("03-after-e4.png")
	world._try_play(ChessTypes.parse_square("e7"), ChessTypes.parse_square("e5"))
	await _settle(0.50)
	world._select(ChessTypes.parse_square("g1"))
	await _settle(0.28)
	_shot("04-legal-moves.png")
	world._try_play(ChessTypes.parse_square("g1"), ChessTypes.parse_square("f3"))
	await _settle(0.40)
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
	get_tree().change_scene_to_file("res://scenes/menus/settings_menu.tscn")
	await _settle(0.75)
	_shot("07-settings.png")


func _controller() -> GameController:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("World") as GameController


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame
	await get_tree().process_frame


func _shot(name: String) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var img := vp.get_texture().get_image()
	if img == null:
		return
	var path := OUT_DIR.path_join(name)
	var abs_path := ProjectSettings.globalize_path(path)
	img.save_png(abs_path)
	_shots.append(abs_path)
