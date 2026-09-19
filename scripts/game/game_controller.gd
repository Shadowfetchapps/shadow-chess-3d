class_name GameController
extends Node3D

signal state_changed
signal promotion_required(from_sq: int, to_sq: int)
signal game_ended(text: String)

var engine := ChessEngine.new()
var board: BoardView
var camera_rig: OrbitCamera
var pieces_root: Node3D
var piece_nodes: Dictionary = {}
var selected: int = -1
var legal: Array[ChessMove] = []
var animating := false
var paused := false
var white_clock: float = 600.0
var black_clock: float = 600.0
var clock_enabled := true
var last_from: int = -1
var last_to: int = -1
var pending_from: int = -1
var pending_to: int = -1
var _ai_busy := false
var flipped := false


func _ready() -> void:
	_build_world()
	_start_from_session()
	rebuild_pieces()
	_refresh_marks()
	state_changed.emit()
	call_deferred("_maybe_ai")


func _process(delta: float) -> void:
	if paused or animating or engine.game_over() or not clock_enabled:
		return
	if engine.side_to_move == ChessTypes.WHITE:
		white_clock = maxf(white_clock - delta, 0.0)
		if white_clock <= 0.0:
			engine.flag_timeout(ChessTypes.WHITE)
			_end()
	else:
		black_clock = maxf(black_clock - delta, 0.0)
		if black_clock <= 0.0:
			engine.flag_timeout(ChessTypes.BLACK)
			_end()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("flip_board"):
		flip_board()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("undo_move"):
		undo()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_click_at(mb.position)


func _build_world() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.045, 0.05, 0.062)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.28, 0.36, 0.46)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.28
	env.glow_bloom = 0.05
	env.ssao_enabled = SettingsStore.graphics_quality != "low"
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env_node.environment = env
	add_child(env_node)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.95, 0.88)
	key.light_energy = 1.35
	key.shadow_enabled = SettingsStore.graphics_quality != "low"
	key.rotation_degrees = Vector3(-48, -28, 0)
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.45, 0.70, 0.85)
	fill.light_energy = 0.35
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-20, 140, 0)
	add_child(fill)
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.45, 0.85, 0.95)
	rim.light_energy = 1.6
	rim.omni_range = 14.0
	rim.position = Vector3(-6, 5, -5)
	add_child(rim)
	board = BoardView.new()
	add_child(board)
	pieces_root = Node3D.new()
	pieces_root.name = "Pieces"
	add_child(pieces_root)
	camera_rig = OrbitCamera.new()
	add_child(camera_rig)


func _start_from_session() -> void:
	clock_enabled = GameSession.clock_seconds > 0
	white_clock = float(GameSession.clock_seconds)
	black_clock = float(GameSession.clock_seconds)
	if GameSession.load_path != "":
		var data := SaveManager.load_game(GameSession.load_path)
		SaveManager.apply_to_engine(engine, data)
		var clock: Dictionary = data.get("clock", {})
		if clock.has("white"):
			white_clock = float(clock["white"])
		if clock.has("black"):
			black_clock = float(clock["black"])
		clock_enabled = bool(clock.get("enabled", clock_enabled))
		if str(data.get("mode", "local")) == "ai":
			GameSession.mode = GameSession.Mode.AI
			GameSession.ai_side = int(data.get("ai_side", ChessTypes.BLACK))
	elif GameSession.pending_fen != "":
		engine.from_fen(GameSession.pending_fen)
	else:
		engine.reset()
	_apply_orientation()


func rebuild_pieces() -> void:
	for c in pieces_root.get_children():
		c.queue_free()
	piece_nodes.clear()
	for sq in 64:
		var p := engine.piece_at(sq)
		if p == 0:
			continue
		_spawn(sq, ChessTypes.ptype(p), ChessTypes.pcolor(p))


func _spawn(sq: int, type: int, color: int) -> PieceView:
	var pv := PieceView.new()
	pv.setup(type, color, sq)
	pv.position = board.square_to_world(sq)
	pieces_root.add_child(pv)
	piece_nodes[sq] = pv
	return pv


func _click_at(screen: Vector2) -> void:
	if paused or animating or engine.game_over() or _ai_busy:
		return
	if _is_ai_turn():
		return
	var hit := _pick(screen)
	if hit < 0:
		_deselect()
		return
	var p := engine.piece_at(hit)
	if selected >= 0:
		if hit == selected:
			_deselect()
			return
		var promo_needed := _needs_promo(selected, hit)
		if promo_needed:
			if engine.find_move(selected, hit, ChessTypes.QUEEN) != null:
				pending_from = selected
				pending_to = hit
				promotion_required.emit(selected, hit)
				return
		var played := _try_play(selected, hit)
		if played:
			return
		if p != 0 and ChessTypes.pcolor(p) == engine.side_to_move:
			_select(hit)
			return
		_deselect()
		return
	if p != 0 and ChessTypes.pcolor(p) == engine.side_to_move:
		_select(hit)


func complete_promotion(type: int) -> void:
	if pending_from < 0:
		return
	_try_play(pending_from, pending_to, type)
	pending_from = -1
	pending_to = -1


func _needs_promo(from_sq: int, to_sq: int) -> bool:
	for m in engine.generate_legal_from(from_sq):
		if m.to_sq == to_sq and m.is_promotion():
			return true
	return false


func _try_play(from_sq: int, to_sq: int, promo: int = 0) -> bool:
	var m := engine.find_move(from_sq, to_sq, promo)
	if m == null:
		return false
	_apply_and_animate(m)
	return true


func _apply_and_animate(m: ChessMove) -> void:
	var applied := engine.apply_move(m)
	if applied == null:
		return
	last_from = m.from_sq
	last_to = m.to_sq
	_deselect()
	animating = true
	_animate_move(applied, func():
		animating = false
		_refresh_marks()
		state_changed.emit()
		if engine.game_over():
			_end()
		else:
			_maybe_ai()
	)


func _animate_move(m: ChessMove, done: Callable) -> void:
	var dur := 0.32 / maxf(SettingsStore.animation_speed, 0.25)
	var mover: PieceView = piece_nodes.get(m.from_sq, null)
	if mover == null:
		rebuild_pieces()
		done.call()
		return
	piece_nodes.erase(m.from_sq)
	if m.is_en_passant() and piece_nodes.has(m.captured_sq):
		_fade_out(piece_nodes[m.captured_sq], dur)
		piece_nodes.erase(m.captured_sq)
	elif m.is_capture() and piece_nodes.has(m.to_sq):
		_fade_out(piece_nodes[m.to_sq], dur * 0.8)
		piece_nodes.erase(m.to_sq)
	if m.is_castle():
		var rook_from := m.from_sq + 3 if m.is_castle_kingside() else m.from_sq - 4
		var rook_to := m.from_sq + 1 if m.is_castle_kingside() else m.from_sq - 1
		var rook: PieceView = piece_nodes.get(rook_from, null)
		if rook:
			piece_nodes.erase(rook_from)
			rook.square = rook_to
			piece_nodes[rook_to] = rook
			var twr := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
			twr.tween_property(rook, "position", board.square_to_world(rook_to), dur)
	var dest := board.square_to_world(m.to_sq)
	var mid := (mover.position + dest) * 0.5 + Vector3.UP * 0.55
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(mover, "position", mid, dur * 0.45)
	tw.tween_property(mover, "position", dest, dur * 0.55)
	mover.square = m.to_sq
	piece_nodes[m.to_sq] = mover
	if m.is_promotion():
		tw.tween_callback(func():
			if is_instance_valid(mover):
				mover.queue_free()
			piece_nodes.erase(m.to_sq)
			_spawn(m.to_sq, m.promotion, ChessTypes.opp(engine.side_to_move))
			AudioManager.play("promote")
		)
	tw.tween_callback(done)
	if m.is_castle():
		AudioManager.play("castle")
	elif m.is_capture():
		AudioManager.play("capture")
	else:
		AudioManager.play("move")
	if engine.result == ChessEngine.Result.CHECKMATE:
		AudioManager.play("checkmate")
	elif engine.in_check():
		AudioManager.play("check")


func _fade_out(node: Node3D, dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(node, "position:y", node.position.y - 0.25, dur)
	tw.parallel().tween_property(node, "scale", Vector3(0.2, 0.2, 0.2), dur)
	tw.tween_callback(node.queue_free)


func _select(sq: int) -> void:
	selected = sq
	legal = engine.generate_legal_from(sq)
	if piece_nodes.has(sq):
		piece_nodes[sq].set_selected(true)
	_refresh_marks()
	state_changed.emit()


func _deselect() -> void:
	if selected >= 0 and piece_nodes.has(selected):
		piece_nodes[selected].set_selected(false)
	selected = -1
	legal.clear()
	_refresh_marks()
	state_changed.emit()


func _refresh_marks() -> void:
	board.clear_highlights()
	if last_from >= 0:
		board.show_highlight(last_from, "last")
	if last_to >= 0:
		board.show_highlight(last_to, "last")
	if engine.in_check():
		var k := engine.find_king(engine.side_to_move)
		board.show_highlight(k, "check")
	if selected >= 0:
		board.show_highlight(selected, "select")
		if SettingsStore.show_legal_moves:
			for m in legal:
				board.show_highlight(m.to_sq, "capture" if m.is_capture() else "legal")


func _pick(screen: Vector2) -> int:
	var cam := camera_rig.camera
	var from := cam.project_ray_origin(screen)
	var to := from + cam.project_ray_normal(screen) * 80.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1 | 2
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return -1
	var collider: Object = hit.get("collider")
	if collider is StaticBody3D:
		var body := collider as StaticBody3D
		if body.has_meta("square"):
			return int(body.get_meta("square"))
		var parent := body.get_parent()
		if parent and parent.get_parent() is PieceView:
			return (parent.get_parent() as PieceView).square
	return -1


func _is_ai_turn() -> bool:
	return GameSession.mode == GameSession.Mode.AI and engine.side_to_move == GameSession.ai_side


func _maybe_ai() -> void:
	if not _is_ai_turn() or engine.game_over() or paused:
		return
	_ai_busy = true
	state_changed.emit()
	await get_tree().create_timer(0.28).timeout
	var move := ChessAI.choose(engine, SettingsStore.ai_difficulty)
	_ai_busy = false
	if move:
		_apply_and_animate(move)


func undo() -> void:
	if animating or _ai_busy:
		return
	if not engine.can_undo():
		return
	engine.undo()
	if GameSession.mode == GameSession.Mode.AI and engine.can_undo() and engine.side_to_move != GameSession.ai_side:
		engine.undo()
	if engine.history.is_empty():
		last_from = -1
		last_to = -1
	else:
		var last: ChessMove = engine.history[engine.history.size() - 1]
		last_from = last.from_sq
		last_to = last.to_sq
	rebuild_pieces()
	_deselect()
	state_changed.emit()


func redo() -> void:
	if animating or _ai_busy:
		return
	if engine.redo():
		if not engine.history.is_empty():
			var last: ChessMove = engine.history[engine.history.size() - 1]
			last_from = last.from_sq
			last_to = last.to_sq
		rebuild_pieces()
		_refresh_marks()
		state_changed.emit()


func restart() -> void:
	engine.reset()
	last_from = -1
	last_to = -1
	white_clock = float(GameSession.clock_seconds)
	black_clock = float(GameSession.clock_seconds)
	rebuild_pieces()
	_deselect()
	state_changed.emit()
	_maybe_ai()


func resign() -> void:
	var side := engine.side_to_move
	if GameSession.mode == GameSession.Mode.AI:
		side = ChessTypes.opp(GameSession.ai_side)
	engine.resign(side)
	_end()


func flip_board() -> void:
	flipped = not flipped
	camera_rig.face_side(not flipped)


func _apply_orientation() -> void:
	var orient := SettingsStore.board_orientation
	var white_side := true
	if orient == "black":
		white_side = false
	elif orient == "auto" and GameSession.mode == GameSession.Mode.AI:
		white_side = GameSession.ai_side == ChessTypes.BLACK
	flipped = not white_side
	camera_rig.reset_view(white_side)


func save_now() -> String:
	return SaveManager.save_game(engine, {
		"mode": "ai" if GameSession.mode == GameSession.Mode.AI else "local",
		"ai_side": GameSession.ai_side,
		"ai_difficulty": SettingsStore.ai_difficulty,
		"white_name": GameSession.white_name,
		"black_name": GameSession.black_name,
		"clock": {
			"white": white_clock,
			"black": black_clock,
			"enabled": clock_enabled,
		},
	})


func export_pgn() -> String:
	return Pgn.export_game(engine, {
		"White": GameSession.white_name,
		"Black": GameSession.black_name,
	})


func export_fen() -> String:
	return engine.to_fen()


func _end() -> void:
	state_changed.emit()
	game_ended.emit(engine.result_text())
	if engine.result == ChessEngine.Result.CHECKMATE:
		AudioManager.play("checkmate")
