class_name MenuBackdrop
extends Node3D

## Living title-screen scene: the salon with Morphy's "Opera Game" (Paris,
## 1858 — public domain) replaying slowly on the board under an orbiting camera.

const OPERA_GAME := "e4 e5 Nf3 d6 d4 Bg4 dxe5 Bxf3 Qxf3 dxe5 Bc4 Nf6 Qb3 Qe7 Nc3 c6 Bg5 b5 Nxb5 cxb5 Bxb5+ Nbd7 O-O-O Rd8 Rxd7 Rxd7 Rd1 Qe6 Bxd7+ Nxd7 Qb8+ Nxb8 Rd8#"
const MOVE_EVERY := 3.4

var camera_rig: OrbitCamera
var board: BoardView
var _engine := ChessEngine.new()
var _pieces: Node3D
var _nodes: Dictionary = {}
var _sans: PackedStringArray
var _index := 0
var _timer := 0.0
var _world_env: WorldEnvironment


func _ready() -> void:
	MaterialLibrary.apply_theme(SettingsStore.board_theme, SettingsStore.piece_style)
	_world_env = WorldEnvironment.new()
	_world_env.environment = WorldLook.make_environment()
	add_child(_world_env)
	WorldLook.add_lights(self)
	SalonBuilder.build(self, true)
	board = BoardView.new()
	add_child(board)
	_pieces = Node3D.new()
	add_child(_pieces)
	camera_rig = OrbitCamera.new()
	camera_rig.interactive = false
	camera_rig.auto_orbit_speed = 2.2 if not SettingsStore.reduce_motion else 0.0
	add_child(camera_rig)
	camera_rig.pitch = 38.0
	camera_rig.yaw = 28.0
	camera_rig.distance = camera_rig.frame_distance() * 0.92
	camera_rig.call_deferred("_snap")
	_sans = OPERA_GAME.split(" ")
	_restart()
	SettingsStore.settings_changed.connect(func():
		MaterialLibrary.apply_theme(SettingsStore.board_theme, SettingsStore.piece_style)
		WorldLook.apply_quality(_world_env.environment)
		board.apply_settings()
	)


func set_insets(left: float, right: float) -> void:
	camera_rig.set_insets(left, right, 0.0, 0.0)
	camera_rig.distance = camera_rig.frame_distance() * 0.92


func _process(delta: float) -> void:
	if SettingsStore.reduce_motion:
		return
	_timer += delta
	if _timer < MOVE_EVERY:
		return
	_timer = 0.0
	if _index >= _sans.size():
		_restart()
		return
	var m := San.parse_and_play(_engine, _sans[_index])
	_index += 1
	if m:
		_animate(m)


func _restart() -> void:
	_engine.reset()
	_index = 0
	for c in _pieces.get_children():
		c.queue_free()
	_nodes.clear()
	for sq in 64:
		var p := _engine.piece_at(sq)
		if p != 0:
			var pv := PieceView.new()
			pv.setup(ChessTypes.ptype(p), ChessTypes.pcolor(p), sq)
			pv.position = board.square_to_world(sq)
			_pieces.add_child(pv)
			_nodes[sq] = pv


func _animate(m: ChessMove) -> void:
	var mover: PieceView = _nodes.get(m.from_sq)
	if mover == null:
		return
	_nodes.erase(m.from_sq)
	var cap_sq := m.captured_sq if m.is_capture() else -1
	if cap_sq >= 0 and _nodes.has(cap_sq):
		var victim: PieceView = _nodes[cap_sq]
		_nodes.erase(cap_sq)
		var tw := create_tween()
		tw.tween_interval(0.3)
		tw.tween_property(victim, "scale", Vector3.ZERO, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(victim.queue_free)
	if m.is_castle():
		var rf := m.from_sq + 3 if m.is_castle_kingside() else m.from_sq - 4
		var rt := m.from_sq + 1 if m.is_castle_kingside() else m.from_sq - 1
		var rook: PieceView = _nodes.get(rf)
		if rook:
			_nodes.erase(rf)
			_nodes[rt] = rook
			create_tween().tween_property(rook, "position", board.square_to_world(rt), 0.6).set_trans(Tween.TRANS_CUBIC)
	_nodes[m.to_sq] = mover
	var start := mover.position
	var dest := board.square_to_world(m.to_sq)
	var h := 0.55 if m.piece == ChessTypes.KNIGHT else 0.18
	var tw2 := create_tween()
	tw2.tween_method(func(t: float):
		if is_instance_valid(mover):
			var e := t * t * (3.0 - 2.0 * t)
			var p := start.lerp(dest, e)
			p.y += sin(t * PI) * h
			mover.position = p
	, 0.0, 1.0, 0.55)
	tw2.tween_callback(func():
		if is_instance_valid(mover):
			mover.play_land()
	)
