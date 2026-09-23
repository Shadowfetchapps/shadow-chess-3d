extends Node

## Drives the real game through its main screens and saves screenshots.
## Launched from the main menu with:  godot --path . -- --visual-qa [--shots=DIR] [--quality=high]
## Point XDG_CONFIG_HOME / XDG_DATA_HOME at a scratch dir so a run never
## touches real saves or settings (tools/capture_screenshots.sh does this).

var _dir := "res://docs/screenshots"
var _shots: PackedStringArray = PackedStringArray()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_dir = a.trim_prefix("--shots=")
		elif a.begins_with("--quality="):
			SettingsStore.graphics_quality = a.trim_prefix("--quality=")
	SettingsStore.show_eval_bar = false
	SettingsStore.music_enabled = false
	SettingsStore.apply_audio()
	DirAccess.make_dir_recursive_absolute(_abs(_dir))
	await _run()
	print("visual_qa wrote %d shots" % _shots.size())
	for s in _shots:
		print("  ", s)
	get_tree().quit(0 if _shots.size() >= 6 else 1)


func _run() -> void:
	await _settle(3.0)
	_shot("01-main-menu")
	var menu := get_tree().current_scene
	var ng: Modal = menu.get("_new_game")
	if ng:
		ng.open()
		await _settle(0.8)
		_shot("02-new-game")
		ng.close()
		await _settle(0.4)

	GameSession.configure_ai(true, "club", "10+0")
	get_tree().change_scene_to_file("res://scenes/main/game.tscn")
	await _settle(2.6)
	_shot("03-game-start")
	var world := _controller()
	if world == null:
		return
	world._select(ChessTypes.parse_square("g1"))
	await _settle(0.6)
	_shot("04-legal-moves")
	world._deselect()
	GameSession.configure_local(true, "10+0")
	get_tree().change_scene_to_file("res://scenes/main/game.tscn")
	await _settle(2.0)
	world = _controller()
	if world == null:
		return
	for uci in ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6"]:
		_force(world, uci)
		await _settle(0.75)
	_force(world, "c4f7")
	await _settle(1.2)
	_shot("05-capture-check")
	world.set_view_ply(3)
	await _settle(0.8)
	_shot("06-review")
	world.set_view_ply(world.engine.history.size())
	await _settle(0.6)

	var ui := get_tree().current_scene.get_node("UI")
	ui.call("_open_settings")
	await _settle(0.9)
	_shot("07-settings")
	for c in ui.root.get_children():
		if c is SettingsPanel:
			(c as SettingsPanel).close()
	await _settle(0.5)

	GameSession.configure_analysis()
	GameSession.pending_pgn = "[Event \"Opera\"]\n[White \"Morphy\"]\n[Black \"Duke Karl / Count Isouard\"]\n\n1. e4 e5 2. Nf3 d6 3. d4 Bg4 4. dxe5 Bxf3 5. Qxf3 dxe5 6. Bc4 Nf6 7. Qb3 Qe7 8. Nc3 c6 9. Bg5 b5 10. Nxb5 cxb5 11. Bxb5+ Nbd7 12. O-O-O Rd8 *"
	get_tree().change_scene_to_file("res://scenes/main/game.tscn")
	await _settle(3.5)
	_shot("08-analysis")

	var puzzles := ChessPuzzles.load_all()
	if not puzzles.is_empty():
		GameSession.configure_puzzle(puzzles[min(14, puzzles.size() - 1)], min(14, puzzles.size() - 1))
		get_tree().change_scene_to_file("res://scenes/main/game.tscn")
		await _settle(2.4)
		_shot("09-puzzle")

	GameSession.configure_ai(false, "master", "5+0")
	get_tree().change_scene_to_file("res://scenes/main/game.tscn")
	await _settle(4.5)
	world = _controller()
	if world:
		world.resign()
		await _settle(2.2)
		_shot("10-result")


func _force(world: GameController, uci: String) -> void:
	var m := world._move_from_uci(world.engine, uci)
	if m:
		world._play(m)


func _controller() -> GameController:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("World") as GameController if scene else null


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	var path := _abs(_dir).path_join(name + ".png")
	img.save_png(path)
	_shots.append(path)


func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p) if p.begins_with("res://") or p.begins_with("user://") else p
