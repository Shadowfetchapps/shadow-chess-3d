class_name PieceIcons
extends Node

## Renders the actual 3D pieces (current style) into small UI thumbnails in a
## single off-screen pass, so captured-piece rows and the promotion picker
## always match the board. Results are cached per piece style.

signal icons_ready

const CELL := 112
const ORDER := [ChessTypes.PAWN, ChessTypes.KNIGHT, ChessTypes.BISHOP, ChessTypes.ROOK, ChessTypes.QUEEN, ChessTypes.KING]

static var _icons: Dictionary = {}
static var _style := ""

var _busy := false


static func get_icon(type: int, color: int) -> Texture2D:
	return _icons.get("%d_%d" % [color, type])


static func has_icons() -> bool:
	return not _icons.is_empty() and _style == MaterialLibrary.current_pieces


func render() -> void:
	if has_icons():
		icons_ready.emit()
		return
	if _busy or DisplayServer.get_name() == "headless":
		return
	_busy = true
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL * 6, CELL * 2)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	var sky_env := WorldLook.make_environment()
	if sky_env.sky:
		env.sky = sky_env.sky
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.9
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.5, 0.45, 0.4)
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -35, 0)
	key.light_energy = 1.6
	key.light_color = Color(1.0, 0.93, 0.82)
	world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 160, 0)
	rim.light_energy = 1.1
	rim.light_color = Color(0.95, 0.85, 0.7)
	world.add_child(rim)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.2
	cam.position = Vector3(0, 0, 10)
	cam.current = true
	world.add_child(cam)
	var cell := 1.6
	for row in 2:
		var color := ChessTypes.WHITE if row == 0 else ChessTypes.BLACK
		for col in ORDER.size():
			var type: int = ORDER[col]
			var holder := Node3D.new()
			var visual := PieceMeshBuilder.build(type, color)
			holder.add_child(visual)
			var h := PieceMeshBuilder.height_of(type)
			var s := 1.22 / 1.2
			holder.scale = Vector3.ONE * s
			holder.rotation_degrees = Vector3(14, 90 if type == ChessTypes.KNIGHT else 20, 0)
			var base_y := (1.6 if row == 0 else 0.0) - cell + 0.14
			holder.position = Vector3((col - 2.5) * cell, base_y + (1.2 - h) * 0.0, 0)
			world.add_child(holder)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img:
		_icons.clear()
		for row in 2:
			var color := ChessTypes.WHITE if row == 0 else ChessTypes.BLACK
			for col in ORDER.size():
				var region := img.get_region(Rect2i(col * CELL, row * CELL, CELL, CELL))
				region.generate_mipmaps()
				_icons["%d_%d" % [color, ORDER[col]]] = ImageTexture.create_from_image(region)
		_style = MaterialLibrary.current_pieces
	vp.queue_free()
	_busy = false
	icons_ready.emit()
