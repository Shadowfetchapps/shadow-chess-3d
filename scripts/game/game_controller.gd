class_name GameController
extends Node3D

## Owns the live game: rules engine, 3D board and pieces, input (click and
## drag), animation, clocks, Shadow's threaded search, evaluation, hints,
## history review, puzzles, and autosave. The HUD talks to it through signals
## and the small query API at the bottom of this file.

signal state_changed
signal move_played(move: ChessMove)
signal promotion_requested(from_sq: int, to_sq: int, color: int)
signal game_finished(info: Dictionary)
signal thinking_changed(on: bool)
signal eval_updated(white_cp: int, mate_white: int, depth: int, pv_san: String)
signal hint_shown(text: String)
signal view_changed(ply: int, live: bool)
signal toast(text: String, kind: String)
signal puzzle_event(kind: String, text: String)
signal clock_low(side: int)

const DRAG_THRESHOLD := 7.0
const DRAG_LIFT := 0.42

class FuncJob:
	extends RefCounted
	var fn: Callable
	var result: Variant
	var cancelled := false
	func run() -> void:
		result = fn.call()

var engine := ChessEngine.new()
var board: BoardView
var camera_rig: OrbitCamera
var clock_prop: ChessClockProp
var pieces_root: Node3D
var piece_nodes: Dictionary = {}
var tray_nodes: Array[PieceView] = []

var selected := -1
var legal: Array[ChessMove] = []
var animating := false
var paused := false
var view_ply := 0
var clock_enabled := false
var clock_base := 0
var clock_increment := 0
var clocks: Array[float] = [0.0, 0.0]
var last_eval := {"cp": 0, "mate": 0, "depth": 0, "ply": -1, "pv": ""}

var _world_env: WorldEnvironment
var _lights: Dictionary = {}
var _ai_job: ChessAI.SearchJob
var _ai_task := -1
var _ai_started_ms := 0
var _ai_min_ms := 0
var _eval_job: ChessAI.SearchJob
var _eval_task := -1
var _eval_ply := -1
var _eval_dirty := false
var _hint_job: ChessAI.SearchJob
var _hint_task := -1
var _func_job: FuncJob
var _func_task := -1
var _func_done: Callable

var _press_pos := Vector2.ZERO
var _press_sq := -1
var _press_was_selected := false
var _mouse_down := false
var _dragging := false
var _drag_piece: PieceView
var _hover_sq := -1
var _ended := false
var _recorded := false
var _pending_promo := {}
var _low_warned: Array[bool] = [false, false]
var _last_tick := -1
var _view_cache: Dictionary = {}
var _moves_this_session := 0

var _puzzle_moves_left := 0
var _puzzle_step := 0
var _puzzle_clean := true
var _puzzle_solved := false
var _puzzle_on_line := true


func _ready() -> void:
	MaterialLibrary.apply_theme(SettingsStore.board_theme, SettingsStore.piece_style)
	MaterialLibrary.set_high_contrast(SettingsStore.high_contrast)
	ChessAI.warmup()
	_build_world()
	_start_from_session()
	view_ply = engine.history.size()
	rebuild_pieces()
	_refresh_marks()
	SettingsStore.settings_changed.connect(_on_settings_changed)
	state_changed.emit()
	AudioManager.play("game_start")
	call_deferred("_after_start")


func _after_start() -> void:
	if engine.game_over():
		_finish()
		return
	_maybe_ai()
	_request_eval()


func _exit_tree() -> void:
	_cancel_ai()
	_cancel_task("eval")
	_cancel_task("hint")
	_cancel_task("func")
	if not _ended and GameSession.mode != GameSession.Mode.PUZZLE and not engine.history.is_empty():
		SaveManager.save_game(snapshot(), SaveManager.autosave_path())


# --- World -----------------------------------------------------------------------

func _build_world() -> void:
	_world_env = WorldEnvironment.new()
	_world_env.environment = WorldLook.make_environment()
	add_child(_world_env)
	_lights = WorldLook.add_lights(self)
	var salon := SalonBuilder.build(self, true)
	clock_prop = salon.get_node_or_null("ChessClock") as ChessClockProp
	board = BoardView.new()
	board.name = "Board"
	add_child(board)
	pieces_root = Node3D.new()
	pieces_root.name = "Pieces"
	add_child(pieces_root)
	camera_rig = OrbitCamera.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.view_changed.connect(func(): board.set_white_bottom(camera_rig.is_white_bottom()); state_changed.emit())


func _start_from_session() -> void:
	clock_base = GameSession.clock_base
	clock_increment = GameSession.clock_increment
	clock_enabled = clock_base > 0 and GameSession.mode in [GameSession.Mode.LOCAL, GameSession.Mode.AI]
	clocks = [float(clock_base), float(clock_base)]
	var ok := true
	if GameSession.load_path != "":
		var data := SaveManager.load_game(GameSession.load_path)
		ok = not data.is_empty()
		if ok:
			_apply_save_meta(data)
			ok = SaveManager.apply_to_engine(engine, data)
		if not ok:
			engine.reset()
			call_deferred("_emit_toast", "That save could not be read. Started a new game.", "error")
	elif GameSession.pending_pgn != "":
		var res := Pgn.import_game(GameSession.pending_pgn)
		if bool(res.get("ok", false)):
			engine = res["engine"]
			var h: Dictionary = res.get("headers", {})
			GameSession.white_name = str(h.get("White", "White"))
			GameSession.black_name = str(h.get("Black", "Black"))
		else:
			engine.reset()
			call_deferred("_emit_toast", "PGN import failed: %s" % res.get("error", "unknown error"), "error")
	elif GameSession.pending_fen != "":
		if not engine.from_fen(GameSession.pending_fen):
			engine.reset()
			call_deferred("_emit_toast", "That FEN is not a legal position.", "error")
	else:
		engine.reset()
	if GameSession.mode == GameSession.Mode.PUZZLE:
		_puzzle_moves_left = int(GameSession.puzzle.get("depth", 1))
		_puzzle_step = 0
		_puzzle_clean = true
	var white_bottom := true
	if GameSession.mode in [GameSession.Mode.AI, GameSession.Mode.PUZZLE]:
		white_bottom = GameSession.ai_side == ChessTypes.BLACK
	camera_rig.reset_view(white_bottom, true)
	board.set_white_bottom(white_bottom)


func _apply_save_meta(data: Dictionary) -> void:
	var mode := str(data.get("mode", "local"))
	GameSession.mode = {"ai": GameSession.Mode.AI, "analysis": GameSession.Mode.ANALYSIS}.get(mode, GameSession.Mode.LOCAL)
	GameSession.ai_side = int(data.get("ai_side", ChessTypes.BLACK))
	GameSession.ai_level = str(data.get("ai_level", SettingsStore.ai_level))
	GameSession.white_name = str(data.get("white_name", "White"))
	GameSession.black_name = str(data.get("black_name", "Black"))
	var c: Dictionary = data.get("clock", {})
	clock_base = int(c.get("base", 0))
	clock_increment = int(c.get("increment", 0))
	clock_enabled = bool(c.get("enabled", false)) and clock_base > 0
	clocks = [float(c.get("white", clock_base)), float(c.get("black", clock_base))]
	GameSession.clock_base = clock_base
	GameSession.clock_increment = clock_increment


func _emit_toast(text: String, kind: String) -> void:
	toast.emit(text, kind)


# --- Frame loop -------------------------------------------------------------------

func _process(delta: float) -> void:
	_tick_clocks(delta)
	_poll_ai()
	_poll_eval()
	_poll_hint()
	_poll_func()
	if clock_prop:
		var running := engine.side_to_move if _clocks_running() else -1
		clock_prop.set_times(clocks[0], clocks[1], running, clock_enabled)


func _clocks_running() -> bool:
	return clock_enabled and not paused and not engine.game_over() and engine.history.size() >= 2


func _tick_clocks(delta: float) -> void:
	if not _clocks_running() or animating:
		return
	var side := engine.side_to_move
	clocks[side] = maxf(clocks[side] - delta, 0.0)
	var human := _is_human(side)
	if clocks[side] <= 10.0 and not _low_warned[side]:
		_low_warned[side] = true
		clock_low.emit(side)
		if human:
			AudioManager.play("clock_warning")
	if human and clocks[side] <= 10.0:
		var s := int(ceil(clocks[side]))
		if s != _last_tick:
			_last_tick = s
			AudioManager.play("clock_tick")
	if clocks[side] <= 0.0:
		_cancel_ai()
		engine.flag_timeout(side)
		_finish()


# --- Input ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_on_mouse_motion((event as InputEventMouseMotion).position)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_press(mb.position)
			else:
				_on_release(mb.position)
		return
	if paused:
		return
	if event.is_action_pressed("flip_board"):
		flip_board()
	elif event.is_action_pressed("redo_move"):
		redo()
	elif event.is_action_pressed("undo_move"):
		undo()
	elif event.is_action_pressed("hint"):
		request_hint()
	elif event.is_action_pressed("review_prev"):
		step_view(-1)
	elif event.is_action_pressed("review_next"):
		step_view(1)
	elif event.is_action_pressed("review_first"):
		set_view_ply(0)
	elif event.is_action_pressed("review_last"):
		set_view_ply(engine.history.size())
	else:
		return
	get_viewport().set_input_as_handled()


func can_interact() -> bool:
	if paused or animating or _ai_task >= 0 or _func_task >= 0 or not _pending_promo.is_empty():
		return false
	if engine.game_over() and GameSession.mode != GameSession.Mode.ANALYSIS:
		return false
	if GameSession.mode == GameSession.Mode.PUZZLE and _puzzle_solved:
		return false
	if not is_live() and GameSession.mode != GameSession.Mode.ANALYSIS:
		return false
	return _is_human(_view_side_to_move())


func _on_press(screen: Vector2) -> void:
	_mouse_down = true
	_press_pos = screen
	_press_sq = -1
	if not is_live() and GameSession.mode != GameSession.Mode.ANALYSIS and not animating:
		set_view_ply(engine.history.size())
		return
	if not can_interact():
		if not paused and not animating and _ai_task < 0 and not engine.game_over():
			AudioManager.play("illegal")
		return
	var hit := _pick(screen, 1 | 2)
	if hit < 0:
		_deselect()
		return
	var pos := _view_engine()
	var p := pos.piece_at(hit)
	if selected >= 0 and hit != selected:
		if _try_move(selected, hit, false):
			return
	if p != 0 and ChessTypes.pcolor(p) == pos.side_to_move:
		_press_was_selected = hit == selected
		_press_sq = hit
		if hit != selected:
			_select(hit)
		return
	if selected >= 0:
		AudioManager.play("illegal")
	_deselect()


func _on_release(screen: Vector2) -> void:
	_mouse_down = false
	if _dragging:
		_finish_drag(screen)
		return
	if _press_sq >= 0 and _press_sq == selected and _press_was_selected and screen.distance_to(_press_pos) < DRAG_THRESHOLD:
		_deselect()
	_press_sq = -1


func _on_mouse_motion(screen: Vector2) -> void:
	if _mouse_down and _press_sq >= 0 and not _dragging and screen.distance_to(_press_pos) >= DRAG_THRESHOLD and can_interact():
		var pv: PieceView = piece_nodes.get(_press_sq)
		if pv:
			_dragging = true
			_drag_piece = pv
			pv.set_selected(false)
			pv.set_dragging(true)
			AudioManager.play("select")
	if _dragging and is_instance_valid(_drag_piece):
		var p := _ray_plane(screen, BoardView.TOP_Y + DRAG_LIFT)
		if p != Vector3.INF:
			p.x = clampf(p.x, -5.2, 5.2)
			p.z = clampf(p.z, -5.2, 5.2)
			_drag_piece.position = _drag_piece.position.lerp(p, 0.65)
		_set_hover(_pick(screen, 1))
		return
	if not can_interact():
		_set_hover(-1)
		return
	_set_hover(_pick(screen, 1 | 2))


func _finish_drag(screen: Vector2) -> void:
	_dragging = false
	var pv := _drag_piece
	_drag_piece = null
	var from := _press_sq
	_press_sq = -1
	var to := _pick(screen, 1)
	if is_instance_valid(pv):
		pv.set_dragging(false)
	if to >= 0 and to != from and _try_move(from, to, true):
		return
	if is_instance_valid(pv):
		var home := board.square_to_world(from)
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(pv, "position", home, 0.18)
		if to >= 0 and to != from:
			AudioManager.play("illegal")
	if from >= 0:
		_select(from)


func _set_hover(sq: int) -> void:
	if sq == _hover_sq:
		return
	if _hover_sq >= 0 and piece_nodes.has(_hover_sq):
		(piece_nodes[_hover_sq] as PieceView).set_hovered(false)
	_hover_sq = sq
	board.show_hover(sq)
	if sq >= 0 and piece_nodes.has(sq) and not _dragging:
		var pos := _view_engine()
		var p := pos.piece_at(sq)
		if p != 0 and ChessTypes.pcolor(p) == pos.side_to_move and can_interact():
			(piece_nodes[sq] as PieceView).set_hovered(true)


func _try_move(from_sq: int, to_sq: int, dragged: bool) -> bool:
	var pos := _view_engine()
	var candidates: Array[ChessMove] = []
	for m in pos.generate_legal_from(from_sq):
		if m.to_sq == to_sq:
			candidates.append(m)
	if candidates.is_empty():
		return false
	if candidates[0].is_promotion():
		if SettingsStore.auto_queen:
			_submit_move(from_sq, to_sq, ChessTypes.QUEEN, dragged)
			return true
		_pending_promo = {"from": from_sq, "to": to_sq, "dragged": dragged}
		if dragged and piece_nodes.has(from_sq):
			var pv: PieceView = piece_nodes[from_sq]
			var tw := create_tween()
			tw.tween_property(pv, "position", board.square_to_world(to_sq), 0.12)
		promotion_requested.emit(from_sq, to_sq, pos.side_to_move)
		return true
	_submit_move(from_sq, to_sq, 0, dragged)
	return true


## Plays a move typed as SAN ("Nf3", "exd5", "O-O", "e8=Q") or UCI ("g1f3").
func play_text(text: String) -> bool:
	var t := text.strip_edges()
	if t.is_empty():
		return false
	if not can_interact():
		toast.emit("It isn't your move.", "info")
		return false
	var pos := _view_engine()
	var m: ChessMove = San.parse(pos, t)
	if m == null and t.length() >= 4:
		m = _move_from_uci(pos, t.to_lower())
	if m == null:
		AudioManager.play("illegal")
		toast.emit("“%s” isn't a legal move here." % t, "error")
		return false
	_deselect(false)
	_submit_move(m.from_sq, m.to_sq, m.promotion, false)
	return true


func complete_promotion(type: int) -> void:
	if _pending_promo.is_empty():
		return
	var p := _pending_promo
	_pending_promo = {}
	_submit_move(int(p["from"]), int(p["to"]), type, bool(p["dragged"]))


func cancel_promotion() -> void:
	if _pending_promo.is_empty():
		return
	var from := int(_pending_promo["from"])
	_pending_promo = {}
	if piece_nodes.has(from):
		var tw := create_tween()
		tw.tween_property(piece_nodes[from], "position", board.square_to_world(from), 0.15)
	_select(from)


## Human move entry point (after promotion choice). Routes puzzles through the
## solution checker; everything else is played directly.
func _submit_move(from_sq: int, to_sq: int, promo: int, dragged: bool) -> void:
	if GameSession.mode == GameSession.Mode.PUZZLE:
		_puzzle_submit(from_sq, to_sq, promo, dragged)
		return
	if not is_live():
		_truncate_to_view()
	var m := engine.find_move(from_sq, to_sq, promo)
	if m == null:
		return
	_moves_this_session += 1
	ProfileStore.record_moves(1)
	_play(m, dragged)


func _truncate_to_view() -> void:
	while engine.history.size() > view_ply:
		engine.undo()
	engine.redo_stack.clear()
	_view_cache.clear()
	_ended = false


# --- Playing moves ------------------------------------------------------------------

func _play(m: ChessMove, dragged: bool = false, after: Callable = Callable()) -> void:
	var mover_side := engine.side_to_move
	var applied := engine.apply_move(m)
	if applied == null:
		return
	if clock_enabled and engine.history.size() > 2:
		clocks[mover_side] += float(clock_increment)
	if clocks[mover_side] > 10.0:
		_low_warned[mover_side] = false
	view_ply = engine.history.size()
	_view_cache.clear()
	_deselect(false)
	board.clear_arrows()
	animating = true
	_animate(applied, dragged, func():
		animating = false
		_refresh_marks()
		move_played.emit(applied)
		state_changed.emit()
		view_changed.emit(view_ply, true)
		if GameSession.mode != GameSession.Mode.PUZZLE:
			SaveManager.save_game(snapshot(), SaveManager.autosave_path())
		if after.is_valid():
			after.call()
			return
		if engine.game_over():
			_finish()
		else:
			_maybe_ai()
			_request_eval()
	)


func _animate(m: ChessMove, dragged: bool, done: Callable) -> void:
	var speed := maxf(SettingsStore.animation_speed, 0.25)
	var reduce := SettingsStore.reduce_motion
	var mover: PieceView = piece_nodes.get(m.from_sq)
	if mover == null:
		rebuild_pieces()
		done.call()
		return
	piece_nodes.erase(m.from_sq)
	mover.kill_motion()
	var dest := board.square_to_world(m.to_sq)
	var start := mover.position
	var dist := Vector2(start.x - dest.x, start.z - dest.z).length()
	var dur := (0.16 + 0.05 * dist) / speed
	var height := 0.0
	if not reduce:
		height = 0.62 if m.piece == ChessTypes.KNIGHT else 0.14 + 0.035 * dist
	if dragged:
		dur = 0.1
		height = 0.0
	elif reduce:
		dur = 0.1
	var captured_view: PieceView = null
	if m.is_capture():
		var cap_sq := m.captured_sq if m.captured_sq >= 0 else m.to_sq
		captured_view = piece_nodes.get(cap_sq)
		piece_nodes.erase(cap_sq)
	if m.is_castle():
		var rook_from := m.from_sq + 3 if m.is_castle_kingside() else m.from_sq - 4
		var rook_to := m.from_sq + 1 if m.is_castle_kingside() else m.from_sq - 1
		var rook: PieceView = piece_nodes.get(rook_from)
		if rook:
			piece_nodes.erase(rook_from)
			rook.square = rook_to
			piece_nodes[rook_to] = rook
			_arc(rook, board.square_to_world(rook_to), dur * 1.1, 0.0 if reduce else 0.22, dur * 0.35)
	mover.square = m.to_sq
	piece_nodes[m.to_sq] = mover
	var tw := create_tween()
	tw.tween_method(func(t: float):
		if is_instance_valid(mover):
			var e := _ease_in_out(t)
			var p := start.lerp(dest, e)
			p.y = lerpf(start.y, dest.y, e) + sin(t * PI) * height
			mover.position = p
	, 0.0, 1.0, dur)
	if captured_view:
		var capturer := mover.piece_color
		get_tree().create_timer(dur * 0.55).timeout.connect(func(): _send_to_tray(captured_view, capturer))
	tw.tween_callback(func():
		if is_instance_valid(mover):
			mover.play_land(1.3 if m.is_capture() else 1.0)
		_play_move_sound(m)
	)
	if m.is_promotion():
		tw.tween_callback(func():
			var color := mover.piece_color if is_instance_valid(mover) else ChessTypes.opp(engine.side_to_move)
			if is_instance_valid(mover):
				mover.queue_free()
			var nv := _spawn(m.to_sq, m.promotion, color)
			nv.pop_in()
			AudioManager.play("promote")
		)
	tw.tween_interval(0.05)
	tw.tween_callback(done)


## The check and checkmate cues carry their own placement, so they replace
## the ordinary move sound rather than layering on top of it.
func _play_move_sound(m: ChessMove) -> void:
	var pos := _view_engine()
	if pos.result == ChessEngine.Result.CHECKMATE:
		AudioManager.play("checkmate")
	elif pos.in_check():
		AudioManager.play("check")
	elif m.is_castle():
		AudioManager.play("castle")
	elif m.is_capture():
		AudioManager.play("capture")
	else:
		AudioManager.play("move")
	if pos.in_check():
		var k := pos.find_king(pos.side_to_move)
		if piece_nodes.has(k):
			(piece_nodes[k] as PieceView).pulse_check()


func _ease_in_out(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _arc(node: Node3D, dest: Vector3, dur: float, height: float, delay: float = 0.0) -> Tween:
	var start := node.position
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_method(func(t: float):
		if is_instance_valid(node):
			var e := _ease_in_out(t)
			var p := start.lerp(dest, e)
			p.y += sin(t * PI) * height
			node.position = p
	, 0.0, 1.0, dur)
	return tw


func _send_to_tray(pv: PieceView, capturer: int) -> void:
	if not is_instance_valid(pv):
		return
	var index := 0
	for t in tray_nodes:
		if is_instance_valid(t) and t.piece_color == pv.piece_color:
			index += 1
	pv.set_tray(true)
	tray_nodes.append(pv)
	var slot := board.tray_slot(capturer, index)
	var dur := 0.45 / maxf(SettingsStore.animation_speed, 0.25)
	if SettingsStore.reduce_motion:
		pv.position = slot
		pv.scale = Vector3.ONE * 0.72
		return
	_arc(pv, slot, dur, 1.1)
	var tw := create_tween()
	tw.tween_property(pv, "scale", Vector3.ONE * 0.72, dur).set_trans(Tween.TRANS_SINE)


# --- Pieces -------------------------------------------------------------------------

func rebuild_pieces() -> void:
	for c in pieces_root.get_children():
		c.queue_free()
	piece_nodes.clear()
	tray_nodes.clear()
	var pos := _view_engine()
	for sq in 64:
		var p := pos.piece_at(sq)
		if p != 0:
			_spawn(sq, ChessTypes.ptype(p), ChessTypes.pcolor(p))
	for capturer in [ChessTypes.WHITE, ChessTypes.BLACK]:
		var taken: Array = pos.captured_by(capturer)
		for i in taken.size():
			var pv := PieceView.new()
			pv.setup(int(taken[i]), ChessTypes.opp(capturer), -1)
			pv.set_tray(true)
			pv.position = board.tray_slot(capturer, i)
			pv.scale = Vector3.ONE * 0.72
			pieces_root.add_child(pv)
			tray_nodes.append(pv)


func _spawn(sq: int, type: int, color: int) -> PieceView:
	var pv := PieceView.new()
	pv.setup(type, color, sq)
	pv.position = board.square_to_world(sq)
	pieces_root.add_child(pv)
	piece_nodes[sq] = pv
	return pv


# --- Selection and marks -------------------------------------------------------------

func _select(sq: int) -> void:
	if selected >= 0 and piece_nodes.has(selected):
		(piece_nodes[selected] as PieceView).set_selected(false)
	selected = sq
	legal = _view_engine().generate_legal_from(sq)
	if piece_nodes.has(sq) and not _dragging:
		(piece_nodes[sq] as PieceView).set_selected(true)
		AudioManager.play("select")
	_refresh_marks()
	state_changed.emit()


func _deselect(emit: bool = true) -> void:
	if selected >= 0 and piece_nodes.has(selected):
		(piece_nodes[selected] as PieceView).set_selected(false)
	selected = -1
	legal.clear()
	_refresh_marks()
	if emit:
		state_changed.emit()


func _refresh_marks() -> void:
	board.clear_highlights()
	var pos := _view_engine()
	if view_ply > 0:
		var last: ChessMove = engine.history[view_ply - 1]
		board.show_highlight(last.from_sq, "last")
		board.show_highlight(last.to_sq, "last")
	if pos.in_check():
		board.show_highlight(pos.find_king(pos.side_to_move), "check")
	if selected >= 0:
		board.show_highlight(selected, "select")
		if SettingsStore.show_legal_moves:
			for m in legal:
				board.show_highlight(m.to_sq, "capture" if m.is_capture() else "legal")


# --- Picking ------------------------------------------------------------------------

func _pick(screen: Vector2, mask: int) -> int:
	var cam := camera_rig.camera
	if cam == null:
		return -1
	var from := cam.project_ray_origin(screen)
	var to := from + cam.project_ray_normal(screen) * 100.0
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return -1
	var node: Node = hit.get("collider")
	if node and node.has_meta("square"):
		return int(node.get_meta("square"))
	while node and not node is PieceView:
		node = node.get_parent()
	if node is PieceView and not (node as PieceView).in_tray:
		return (node as PieceView).square
	return -1


func _ray_plane(screen: Vector2, y: float) -> Vector3:
	var cam := camera_rig.camera
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	if absf(d.y) < 0.0001:
		return Vector3.INF
	var t := (y - o.y) / d.y
	if t < 0.0:
		return Vector3.INF
	return o + d * t


# --- History review -------------------------------------------------------------------

func is_live() -> bool:
	return view_ply == engine.history.size()


func step_view(delta: int) -> void:
	set_view_ply(view_ply + delta)


func set_view_ply(ply: int) -> void:
	ply = clampi(ply, 0, engine.history.size())
	if ply == view_ply or animating or _dragging:
		return
	_deselect(false)
	board.clear_arrows()
	var forward_one := ply == view_ply + 1
	view_ply = ply
	if forward_one:
		animating = true
		_animate(engine.history[ply - 1], false, func():
			animating = false
			_refresh_marks()
			state_changed.emit()
		)
	else:
		rebuild_pieces()
		_refresh_marks()
		AudioManager.play("move", -6.0)
	view_changed.emit(view_ply, is_live())
	state_changed.emit()
	_request_eval()


## Position at the reviewed ply (the live engine when not reviewing).
func _view_engine() -> ChessEngine:
	if is_live():
		return engine
	if _view_cache.has(view_ply):
		return _view_cache[view_ply]
	var e := ChessEngine.new()
	e.from_fen(engine.start_fen)
	for i in view_ply:
		var m: ChessMove = engine.history[i]
		e.play(m.from_sq, m.to_sq, m.promotion)
	_view_cache.clear()
	_view_cache[view_ply] = e
	return e


func _view_side_to_move() -> int:
	return _view_engine().side_to_move


# --- Shadow (AI) ------------------------------------------------------------------------

func _is_ai_turn() -> bool:
	return GameSession.mode == GameSession.Mode.AI and engine.side_to_move == GameSession.ai_side


func _is_human(side: int) -> bool:
	return side in GameSession.human_sides()


func is_thinking() -> bool:
	return _ai_task >= 0


func _maybe_ai() -> void:
	if not _is_ai_turn() or engine.game_over() or paused or _ai_task >= 0:
		return
	_ai_job = ChessAI.SearchJob.new()
	_ai_job.start_fen = engine.start_fen
	_ai_job.moves_uci = _moves_uci(engine.history.size())
	_ai_job.level = GameSession.ai_level
	if clock_enabled:
		var remaining := clocks[GameSession.ai_side]
		if remaining < 180.0:
			_ai_job.time_ms = int(clampf(remaining / 40.0 + clock_increment * 0.6, 0.08, 3.0) * 1000.0)
	_ai_started_ms = Time.get_ticks_msec()
	_ai_min_ms = 450 + randi() % 450
	_ai_task = WorkerThreadPool.add_task(_ai_job.run, true, "shadow-chess-ai")
	thinking_changed.emit(true)
	state_changed.emit()


func _poll_ai() -> void:
	if _ai_task < 0 or paused:
		return
	if not WorkerThreadPool.is_task_completed(_ai_task):
		return
	if Time.get_ticks_msec() - _ai_started_ms < _ai_min_ms and not _ai_job.from_book:
		return
	WorkerThreadPool.wait_for_task_completion(_ai_task)
	_ai_task = -1
	var job := _ai_job
	_ai_job = null
	thinking_changed.emit(false)
	if job == null or job.cancelled:
		state_changed.emit()
		return
	var m := _move_from_uci(engine, job.best_uci)
	if m == null:
		var all := engine.generate_legal_moves()
		if all.is_empty():
			state_changed.emit()
			return
		m = all[0]
	if not job.from_book and job.depth > 0:
		var stm_after_white := GameSession.ai_side == ChessTypes.WHITE
		last_eval = {"cp": job.score_white_cp, "mate": job.mate_in if stm_after_white else -job.mate_in, "depth": job.depth, "ply": engine.history.size() + 1, "pv": ""}
	_play(m)


func _cancel_ai() -> void:
	if _ai_task >= 0:
		if _ai_job:
			_ai_job.cancelled = true
		WorkerThreadPool.wait_for_task_completion(_ai_task)
		_ai_task = -1
		_ai_job = null
		thinking_changed.emit(false)


# --- Evaluation and hints ---------------------------------------------------------------

func eval_wanted() -> bool:
	return SettingsStore.show_eval_bar or GameSession.mode == GameSession.Mode.ANALYSIS or (_ended and GameSession.mode != GameSession.Mode.PUZZLE)


func _request_eval() -> void:
	if not eval_wanted():
		return
	if _eval_task >= 0:
		_eval_dirty = true
		if _eval_job:
			_eval_job.cancelled = true
		return
	var pos := _view_engine()
	if pos.game_over():
		var cp := 0
		var mate := 0
		if pos.result == ChessEngine.Result.CHECKMATE:
			mate = 0
			cp = 10000 if pos.result_side == ChessTypes.WHITE else -10000
		last_eval = {"cp": cp, "mate": mate, "depth": 0, "ply": view_ply, "pv": ""}
		eval_updated.emit(cp, mate, 0, "")
		return
	_eval_job = ChessAI.SearchJob.new()
	_eval_job.start_fen = engine.start_fen
	_eval_job.moves_uci = _moves_uci(view_ply)
	_eval_job.level = "analysis"
	_eval_job.use_book = false
	_eval_job.time_ms = 1600 if GameSession.mode == GameSession.Mode.ANALYSIS else 800
	_eval_ply = view_ply
	_eval_dirty = false
	_eval_task = WorkerThreadPool.add_task(_eval_job.run, true, "shadow-chess-eval")


func _poll_eval() -> void:
	if _eval_task < 0 or not WorkerThreadPool.is_task_completed(_eval_task):
		return
	WorkerThreadPool.wait_for_task_completion(_eval_task)
	_eval_task = -1
	var job := _eval_job
	_eval_job = null
	if _eval_dirty or job == null or job.cancelled or _eval_ply != view_ply:
		_eval_dirty = false
		_request_eval()
		return
	var pos := _view_engine()
	var white_stm := pos.side_to_move == ChessTypes.WHITE
	var mate_white := job.mate_in if white_stm else -job.mate_in
	var pv := _pv_san(pos, job.pv, 6)
	last_eval = {"cp": job.score_white_cp, "mate": mate_white, "depth": job.depth, "ply": view_ply, "pv": pv}
	eval_updated.emit(job.score_white_cp, mate_white, job.depth, pv)


func request_hint() -> void:
	if not can_interact() or _hint_task >= 0:
		return
	board.clear_arrows()
	_puzzle_clean = false
	if GameSession.mode == GameSession.Mode.PUZZLE and _puzzle_on_line:
		var sol: Array = GameSession.puzzle.get("solution", [])
		if _puzzle_step < sol.size():
			var m := _move_from_uci(engine, str(sol[_puzzle_step]))
			if m:
				board.show_arrow(m.from_sq, m.to_sq)
				hint_shown.emit("Try %s" % _san_for(engine, m))
				AudioManager.play("hint")
				return
	_hint_job = ChessAI.SearchJob.new()
	_hint_job.start_fen = engine.start_fen
	_hint_job.moves_uci = _moves_uci(view_ply)
	_hint_job.level = "analysis"
	_hint_job.use_book = true
	_hint_job.time_ms = 1200
	_hint_task = WorkerThreadPool.add_task(_hint_job.run, true, "shadow-chess-hint")
	ProfileStore.record_hint()
	toast.emit("Shadow is looking for a move…", "info")


func _poll_hint() -> void:
	if _hint_task < 0 or not WorkerThreadPool.is_task_completed(_hint_task):
		return
	WorkerThreadPool.wait_for_task_completion(_hint_task)
	_hint_task = -1
	var job := _hint_job
	_hint_job = null
	if job == null or job.cancelled:
		return
	var pos := _view_engine()
	var m := _move_from_uci(pos, job.best_uci)
	if m == null:
		return
	board.show_arrow(m.from_sq, m.to_sq)
	hint_shown.emit("Shadow suggests %s" % _san_for(pos, m))
	AudioManager.play("hint")


func _cancel_task(kind: String) -> void:
	match kind:
		"eval":
			if _eval_task >= 0:
				if _eval_job:
					_eval_job.cancelled = true
				WorkerThreadPool.wait_for_task_completion(_eval_task)
				_eval_task = -1
		"hint":
			if _hint_task >= 0:
				if _hint_job:
					_hint_job.cancelled = true
				WorkerThreadPool.wait_for_task_completion(_hint_task)
				_hint_task = -1
		"func":
			if _func_task >= 0:
				WorkerThreadPool.wait_for_task_completion(_func_task)
				_func_task = -1


func _run_async(fn: Callable, done: Callable) -> void:
	_func_job = FuncJob.new()
	_func_job.fn = fn
	_func_done = done
	_func_task = WorkerThreadPool.add_task(_func_job.run, true, "shadow-chess-puzzle")
	state_changed.emit()


func _poll_func() -> void:
	if _func_task < 0 or not WorkerThreadPool.is_task_completed(_func_task):
		return
	WorkerThreadPool.wait_for_task_completion(_func_task)
	_func_task = -1
	var r: Variant = _func_job.result
	_func_job = null
	var cb := _func_done
	_func_done = Callable()
	if cb.is_valid():
		cb.call(r)
	state_changed.emit()


# --- Puzzles ------------------------------------------------------------------------------

func _puzzle_submit(from_sq: int, to_sq: int, promo: int, dragged: bool) -> void:
	var m := engine.find_move(from_sq, to_sq, promo)
	if m == null:
		return
	var uci := m.to_uci()
	var sol: Array = GameSession.puzzle.get("solution", [])
	if _puzzle_on_line and _puzzle_step < sol.size() and str(sol[_puzzle_step]) == uci:
		_puzzle_correct(m, dragged, true)
		return
	var probe := engine.clone()
	var left := _puzzle_moves_left
	_run_async(func(): return ChessPuzzles.is_solving_move(probe, uci, left), func(ok: Variant):
		if bool(ok):
			_puzzle_correct(engine.find_move(from_sq, to_sq, promo), dragged, false)
		else:
			_puzzle_wrong(engine.find_move(from_sq, to_sq, promo), dragged)
	)


func _puzzle_correct(m: ChessMove, dragged: bool, on_line: bool) -> void:
	if m == null:
		return
	_puzzle_on_line = _puzzle_on_line and on_line
	_play(m, dragged, func():
		if engine.result == ChessEngine.Result.CHECKMATE:
			_puzzle_solved = true
			ProfileStore.mark_puzzle(str(GameSession.puzzle.get("id", "")), true)
			get_tree().create_timer(1.2).timeout.connect(func(): AudioManager.play("puzzle_solved"))
			puzzle_event.emit("solved", "Checkmate — puzzle solved!" if _puzzle_clean else "Solved — with a little help.")
			state_changed.emit()
			return
		_puzzle_moves_left -= 1
		_puzzle_step += 1
		puzzle_event.emit("correct", "Good move. Keep going.")
		_puzzle_reply()
	)


func _puzzle_reply() -> void:
	var sol: Array = GameSession.puzzle.get("solution", [])
	var listed := str(sol[_puzzle_step]) if _puzzle_on_line and _puzzle_step < sol.size() else ""
	var probe := engine.clone()
	var left := _puzzle_moves_left
	_run_async(func(): return ChessPuzzles.best_defense(probe, left, listed) if listed != "" else ChessPuzzles.best_defense(probe, left), func(reply: Variant):
		var r := str(reply)
		if _puzzle_on_line and r != listed:
			_puzzle_on_line = false
		var m := _move_from_uci(engine, r)
		if m == null:
			return
		get_tree().create_timer(0.35).timeout.connect(func():
			_play(m, false, func():
				_puzzle_step += 1
				state_changed.emit()
			)
		)
	)


func _puzzle_wrong(m: ChessMove, dragged: bool) -> void:
	if m == null:
		return
	_puzzle_clean = false
	ProfileStore.puzzle_attempts += 1
	AudioManager.play("puzzle_wrong")
	puzzle_event.emit("wrong", "Not the winning move — try again.")
	_play(m, dragged, func():
		get_tree().create_timer(0.75).timeout.connect(func():
			engine.undo()
			engine.redo_stack.clear()
			view_ply = engine.history.size()
			_view_cache.clear()
			rebuild_pieces()
			_refresh_marks()
			state_changed.emit()
		)
	)


func puzzle_info() -> Dictionary:
	return {
		"title": str(GameSession.puzzle.get("title", "Puzzle")),
		"depth": int(GameSession.puzzle.get("depth", 1)),
		"moves_left": _puzzle_moves_left,
		"solved": _puzzle_solved,
		"clean": _puzzle_clean,
		"theme": str(GameSession.puzzle.get("theme", "")),
		"difficulty": int(GameSession.puzzle.get("difficulty", 1)),
	}


func restart_puzzle() -> void:
	if GameSession.mode != GameSession.Mode.PUZZLE:
		return
	_cancel_task("func")
	engine.from_fen(str(GameSession.puzzle.get("fen", "")))
	_puzzle_moves_left = int(GameSession.puzzle.get("depth", 1))
	_puzzle_step = 0
	_puzzle_solved = false
	_puzzle_on_line = true
	view_ply = 0
	_view_cache.clear()
	board.clear_arrows()
	rebuild_pieces()
	_deselect()


# --- Game commands --------------------------------------------------------------------------

func undo() -> void:
	if animating or GameSession.mode == GameSession.Mode.PUZZLE or not _pending_promo.is_empty():
		return
	_cancel_ai()
	if not engine.can_undo():
		return
	if not is_live():
		set_view_ply(engine.history.size())
	engine.undo()
	if GameSession.mode == GameSession.Mode.AI and engine.side_to_move == GameSession.ai_side and engine.can_undo():
		engine.undo()
	_after_history_edit()


func redo() -> void:
	if animating or GameSession.mode == GameSession.Mode.PUZZLE:
		return
	if not engine.can_redo():
		return
	engine.redo()
	if GameSession.mode == GameSession.Mode.AI and engine.side_to_move == GameSession.ai_side and engine.can_redo():
		engine.redo()
	_after_history_edit()
	_maybe_ai()


func can_undo() -> bool:
	return GameSession.mode != GameSession.Mode.PUZZLE and engine.can_undo() and not animating


func can_redo() -> bool:
	return GameSession.mode != GameSession.Mode.PUZZLE and engine.can_redo() and not animating


func _after_history_edit() -> void:
	_ended = false
	view_ply = engine.history.size()
	_view_cache.clear()
	board.clear_arrows()
	rebuild_pieces()
	_deselect(false)
	_refresh_marks()
	view_changed.emit(view_ply, true)
	state_changed.emit()
	_request_eval()


func restart(swap_colors: bool = false) -> void:
	_cancel_ai()
	_cancel_task("hint")
	if GameSession.mode == GameSession.Mode.PUZZLE:
		restart_puzzle()
		return
	if swap_colors and GameSession.mode == GameSession.Mode.AI:
		GameSession.ai_side = ChessTypes.opp(GameSession.ai_side)
		var w := GameSession.white_name
		GameSession.white_name = GameSession.black_name
		GameSession.black_name = w
		camera_rig.reset_view(GameSession.ai_side == ChessTypes.BLACK)
	engine.from_fen(engine.start_fen)
	engine.redo_stack.clear()
	clocks = [float(clock_base), float(clock_base)]
	_low_warned = [false, false]
	_ended = false
	_recorded = false
	last_eval = {"cp": 0, "mate": 0, "depth": 0, "ply": -1, "pv": ""}
	_after_history_edit()
	AudioManager.play("game_start")
	_maybe_ai()


func resign() -> void:
	if engine.game_over():
		return
	_cancel_ai()
	var side := engine.side_to_move
	if GameSession.mode == GameSession.Mode.AI:
		side = ChessTypes.opp(GameSession.ai_side)
	engine.resign(side)
	_finish()


## Returns true if the draw was agreed.
func offer_draw() -> bool:
	if engine.game_over():
		return false
	if GameSession.mode != GameSession.Mode.AI:
		engine.agree_draw()
		_finish()
		return true
	var ai_view_cp: int = int(last_eval.get("cp", 0))
	if GameSession.ai_side == ChessTypes.BLACK:
		ai_view_cp = -ai_view_cp
	var plies := engine.history.size()
	var accept := (plies >= 40 and ai_view_cp <= 25) or (plies >= 20 and ai_view_cp <= -150)
	if accept:
		engine.agree_draw()
		_finish()
		return true
	toast.emit("Shadow declines the draw.", "info")
	return false


func flip_board() -> void:
	camera_rig.face_side(not camera_rig.white_side)


func set_paused(on: bool) -> void:
	paused = on
	if not on:
		_maybe_ai()


func save_now() -> String:
	var path := SaveManager.save_game(snapshot())
	if path != "":
		toast.emit("Game saved", "success")
	else:
		toast.emit("Could not save the game", "error")
	return path


func snapshot() -> Dictionary:
	var mode_name: String = {GameSession.Mode.AI: "ai", GameSession.Mode.ANALYSIS: "analysis", GameSession.Mode.PUZZLE: "puzzle"}.get(GameSession.mode, "local")
	return {
		"mode": mode_name,
		"ai_side": GameSession.ai_side,
		"ai_level": GameSession.ai_level,
		"white_name": GameSession.white_name,
		"black_name": GameSession.black_name,
		"title": "%s vs %s" % [GameSession.white_name, GameSession.black_name],
		"start_fen": engine.start_fen,
		"moves_uci": Array(_moves_uci(engine.history.size())),
		"fen": engine.to_fen(),
		"result": engine.result_token(),
		"result_text": engine.result_text() if engine.game_over() else "",
		"finished": engine.game_over(),
		"clock": {
			"base": clock_base,
			"increment": clock_increment,
			"white": clocks[0],
			"black": clocks[1],
			"enabled": clock_enabled,
		},
		"pgn": export_pgn(),
	}


func export_pgn() -> String:
	var headers := {
		"Event": "Shadow Chess 3D",
		"Site": "Shadowfetch Private Salon",
		"White": GameSession.white_name,
		"Black": GameSession.black_name,
	}
	if clock_enabled:
		headers["TimeControl"] = "%d+%d" % [clock_base, clock_increment]
	return Pgn.export_game(engine, headers)


func export_fen() -> String:
	return _view_engine().to_fen()


func load_fen(fen: String) -> bool:
	var err := engine.validate_fen(fen)
	if err != "":
		toast.emit(err, "error")
		return false
	_cancel_ai()
	if not engine.from_fen(fen):
		toast.emit("That FEN is not a legal position.", "error")
		return false
	clocks = [float(clock_base), float(clock_base)]
	_after_history_edit()
	_maybe_ai()
	return true


func load_pgn(text: String) -> bool:
	var res := Pgn.import_game(text)
	if not bool(res.get("ok", false)):
		toast.emit("PGN: %s" % str(res.get("error", "could not read the game")), "error")
		return false
	_cancel_ai()
	engine = res["engine"]
	var h: Dictionary = res.get("headers", {})
	if GameSession.mode != GameSession.Mode.AI:
		GameSession.white_name = str(h.get("White", GameSession.white_name))
		GameSession.black_name = str(h.get("Black", GameSession.black_name))
	clocks = [float(clock_base), float(clock_base)]
	_after_history_edit()
	if engine.game_over():
		_finish()
	else:
		_maybe_ai()
	return true


func _finish() -> void:
	if _ended:
		return
	_ended = true
	_cancel_task("hint")
	var info := {
		"text": engine.result_text(),
		"reason": engine.result_reason(),
		"token": engine.result_token(),
		"winner": engine.result_side,
		"player_score": -1.0,
		"rating_delta": 0.0,
		"moves": int(ceil(engine.history.size() / 2.0)),
	}
	# A mating move already rang the checkmate bell; let it breathe first.
	var outcome_delay := 1.5 if engine.result == ChessEngine.Result.CHECKMATE else 0.0
	var outcome := ""
	if GameSession.mode == GameSession.Mode.AI:
		var human := ChessTypes.opp(GameSession.ai_side)
		var score := 0.5
		if engine.result_side == human:
			score = 1.0
		elif engine.result_side == GameSession.ai_side:
			score = 0.0
		info["player_score"] = score
		if not _recorded and engine.history.size() >= 2:
			_recorded = true
			info["rating_delta"] = ProfileStore.record_ai_result(GameSession.ai_level, score)
		outcome = "victory" if score >= 1.0 else ("defeat" if score <= 0.0 else "draw")
	elif GameSession.mode in [GameSession.Mode.LOCAL, GameSession.Mode.ANALYSIS]:
		if GameSession.mode == GameSession.Mode.LOCAL and not _recorded and engine.history.size() >= 2:
			_recorded = true
			ProfileStore.record_local_game()
		outcome = "draw" if engine.result_side < 0 else ("victory" if outcome_delay > 0.0 else "checkmate")
	if outcome != "":
		if outcome_delay > 0.0:
			get_tree().create_timer(outcome_delay).timeout.connect(func(): AudioManager.play(outcome))
		else:
			AudioManager.play(outcome)
	if GameSession.mode != GameSession.Mode.PUZZLE:
		SaveManager.save_game(snapshot(), SaveManager.autosave_path())
	_refresh_marks()
	state_changed.emit()
	game_finished.emit(info)
	_request_eval()


func _on_settings_changed() -> void:
	MaterialLibrary.apply_theme(SettingsStore.board_theme, SettingsStore.piece_style)
	MaterialLibrary.set_high_contrast(SettingsStore.high_contrast)
	board.apply_settings()
	WorldLook.apply_quality(_world_env.environment)
	WorldLook.apply_light_quality(_lights)
	WorldLook.apply_camera_quality(camera_rig.attributes, camera_rig.distance)
	_refresh_marks()
	_request_eval()
	state_changed.emit()


# --- Queries for the HUD --------------------------------------------------------------------

func view_position() -> ChessEngine:
	return _view_engine()


func side_name(side: int) -> String:
	return GameSession.white_name if side == ChessTypes.WHITE else GameSession.black_name


func is_ai_side(side: int) -> bool:
	return GameSession.mode == GameSession.Mode.AI and side == GameSession.ai_side


func bottom_side() -> int:
	return ChessTypes.WHITE if camera_rig.is_white_bottom() else ChessTypes.BLACK


func status_text() -> String:
	var pos := _view_engine()
	if not is_live():
		return "Reviewing move %d of %d" % [int(ceil(view_ply / 2.0)), int(ceil(engine.history.size() / 2.0))]
	if engine.game_over():
		return engine.result_text()
	if _ai_task >= 0:
		return "Shadow is thinking"
	if _func_task >= 0:
		return "Checking your move"
	var who := ChessTypes.side_name(pos.side_to_move)
	if GameSession.mode == GameSession.Mode.PUZZLE:
		if _puzzle_solved:
			return "Puzzle solved"
		return "%s to move · mate in %d" % [who, _puzzle_moves_left]
	var check := pos.in_check()
	if GameSession.mode == GameSession.Mode.AI:
		if _is_human(pos.side_to_move):
			return "Check — your move" if check else "Your move"
		return "Shadow's move"
	return "Check — %s to move" % who if check else "%s to move" % who


func in_check_now() -> bool:
	return _view_engine().in_check() and not engine.game_over()


func is_puzzle_busy() -> bool:
	return _func_task >= 0


# --- Helpers ----------------------------------------------------------------------------------

func _moves_uci(count: int) -> PackedStringArray:
	var out := PackedStringArray()
	for i in mini(count, engine.history.size()):
		out.append(engine.history[i].to_uci())
	return out


func _move_from_uci(e: ChessEngine, uci: String) -> ChessMove:
	if uci.length() < 4:
		return null
	var promo := 0
	if uci.length() >= 5:
		promo = {"q": ChessTypes.QUEEN, "r": ChessTypes.ROOK, "b": ChessTypes.BISHOP, "n": ChessTypes.KNIGHT}.get(uci.substr(4, 1), 0)
	return e.find_move(ChessTypes.parse_square(uci.substr(0, 2)), ChessTypes.parse_square(uci.substr(2, 2)), promo)


func _san_for(e: ChessEngine, m: ChessMove) -> String:
	var c := e.clone()
	var applied := c.apply_move(_move_from_uci(c, m.to_uci()))
	return applied.san if applied else m.to_uci()


func _pv_san(pos: ChessEngine, pv: PackedStringArray, limit: int) -> String:
	if pv.is_empty():
		return ""
	var c := pos.clone()
	var parts := PackedStringArray()
	for i in mini(pv.size(), limit):
		var m := _move_from_uci(c, pv[i])
		if m == null:
			break
		var white := c.side_to_move == ChessTypes.WHITE
		var num := c.fullmove
		var applied := c.apply_move(m)
		if applied == null:
			break
		if white:
			parts.append("%d. %s" % [num, applied.san])
		elif i == 0:
			parts.append("%d… %s" % [num, applied.san])
		else:
			parts.append(applied.san)
	return " ".join(parts)
