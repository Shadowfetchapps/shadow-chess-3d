class_name TestPresentation
extends RefCounted

## Headless checks for the presentation layer: shared materials and theme
## switching, piece construction, settings migration and validation, save-file
## migration, rating maths, and UI building blocks that don't need a GPU.

var _passed := 0
var _failed := 0
var _errors: PackedStringArray = PackedStringArray()


func run_all() -> bool:
	_passed = 0
	_failed = 0
	_errors.clear()
	print("presentation")
	_materials_cached()
	_theme_switch_in_place()
	_piece_meshes_cached()
	_piece_surfaces()
	_settings_migration()
	_settings_validation()
	_save_migration()
	_rating_math()
	_ui_theme()
	_icons()
	_clock_format()
	print("\n==============================")
	print("Shadow Chess presentation  —  %d passed, %d failed" % [_passed, _failed])
	for e in _errors:
		print("  FAIL  ", e)
	print("==============================\n")
	return _failed == 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("  ok    ", name)
	else:
		_failed += 1
		var msg := name if detail.is_empty() else "%s — %s" % [name, detail]
		_errors.append(msg)
		print("  FAIL  ", msg)


func _materials_cached() -> void:
	MaterialLibrary.ensure()
	MaterialLibrary.ensure()
	_ok("shared white body", MaterialLibrary.piece_white != null)
	_ok("shared black body", MaterialLibrary.piece_black != null)
	_ok("body identity", MaterialLibrary.piece_body(ChessTypes.WHITE) == MaterialLibrary.piece_white)
	_ok("trim identity", MaterialLibrary.piece_trim(ChessTypes.BLACK) == MaterialLibrary.trim_black)
	_ok("square variants", MaterialLibrary.light_sq.size() == MaterialLibrary.SQUARE_VARIANTS and MaterialLibrary.dark_sq.size() == MaterialLibrary.SQUARE_VARIANTS)
	_ok("legal marker", MaterialLibrary.mark_legal != null and MaterialLibrary.legal_mat == MaterialLibrary.mark_legal)
	_ok("legacy aliases", MaterialLibrary.ivory_mat == MaterialLibrary.piece_white and MaterialLibrary.gold_trim_mat == MaterialLibrary.trim_white)


func _theme_switch_in_place() -> void:
	var body := MaterialLibrary.piece_white
	var sq := MaterialLibrary.light_square(0)
	for theme in MaterialLibrary.BOARD_THEMES:
		for style in MaterialLibrary.PIECE_STYLES:
			MaterialLibrary.apply_theme(theme, style)
	_ok("theme switch keeps material identity", MaterialLibrary.piece_white == body and MaterialLibrary.light_square(0) == sq)
	MaterialLibrary.apply_theme("marble", "marble")
	_ok("marble trim is metal", MaterialLibrary.trim_white.metallic > 0.9)
	MaterialLibrary.apply_theme("tournament", "tournament")
	_ok("tournament trim matches body", MaterialLibrary.trim_white.metallic < 0.1)
	MaterialLibrary.apply_theme("nonsense", "nonsense")
	_ok("unknown theme falls back", MaterialLibrary.current_board == "salon" and MaterialLibrary.current_pieces == "classic")
	MaterialLibrary.apply_theme("salon", "classic")


func _piece_meshes_cached() -> void:
	var a := PieceMeshBuilder.build(ChessTypes.QUEEN, ChessTypes.WHITE)
	var b := PieceMeshBuilder.build(ChessTypes.QUEEN, ChessTypes.WHITE)
	_ok("queen instances distinct", a != b)
	var ma := _first_mesh(a)
	var mb := _first_mesh(b)
	_ok("queen meshes shared", ma != null and ma == mb)
	_ok("collision present", _has_body(a) and _has_body(b))
	a.free()
	b.free()
	for t in [ChessTypes.PAWN, ChessTypes.KNIGHT, ChessTypes.BISHOP, ChessTypes.ROOK, ChessTypes.QUEEN, ChessTypes.KING]:
		var h := PieceMeshBuilder.height_of(t)
		_ok("height sane %s" % ChessTypes.piece_name(t), h > 0.4 and h < 1.6, str(h))
	_ok("king tallest", PieceMeshBuilder.height_of(ChessTypes.KING) > PieceMeshBuilder.height_of(ChessTypes.QUEEN))
	_ok("pawn shortest", PieceMeshBuilder.height_of(ChessTypes.PAWN) < PieceMeshBuilder.height_of(ChessTypes.ROOK))


func _piece_surfaces() -> void:
	var m := PieceMeshBuilder.mesh_for(ChessTypes.KING)
	if m == null:
		_ok("authored king mesh (optional)", true)
		return
	_ok("king has surfaces", m.get_surface_count() >= 1)
	var roles := {}
	for i in m.get_surface_count():
		roles[PieceMeshBuilder.surface_role(m, i)] = true
	_ok("king has body surface", roles.has("body"))
	var inst := PieceMeshBuilder.build(ChessTypes.KING, ChessTypes.BLACK)
	var mi := inst.get_node_or_null("Mesh") as MeshInstance3D
	_ok("king override materials", mi != null and mi.get_surface_override_material(0) != null)
	inst.free()


func _settings_migration() -> void:
	var s = load("res://scripts/save/settings_store.gd").new()
	s.from_dict({"fullscreen": true, "sound_volume": 0.4, "ai_difficulty": "hard", "clock_seconds": 300, "board_orientation": "black"})
	_ok("v2 fullscreen migrates", s.window_mode == "fullscreen")
	_ok("v2 volume migrates", absf(s.master_volume - 0.4) < 0.001)
	_ok("v2 difficulty migrates", s.ai_level == "advanced")
	_ok("v2 clock migrates", s.clock_preset == "5+0")
	var round_trip = load("res://scripts/save/settings_store.gd").new()
	round_trip.from_dict(s.to_dict())
	_ok("settings round trip", round_trip.to_dict() == s.to_dict())
	s.free()
	round_trip.free()


func _settings_validation() -> void:
	var s = load("res://scripts/save/settings_store.gd").new()
	s.from_dict({"schema": 3, "graphics_quality": "insane", "msaa": 3, "ui_scale": 9.0, "board_theme": "plaid", "ai_level": "god", "resolution": [10, 10], "player_name": "   "})
	_ok("bad quality rejected", s.graphics_quality == "high")
	_ok("bad msaa rejected", s.msaa == 4)
	_ok("ui scale clamped", s.ui_scale <= 1.5)
	_ok("bad theme rejected", s.board_theme == "salon")
	_ok("bad level rejected", s.ai_level == "club")
	_ok("resolution clamped", s.resolution.x >= 960 and s.resolution.y >= 600)
	_ok("blank name defaults", s.player_name == "You")
	_ok("clock parse", s.clock_base_increment("15+10") == Vector2i(900, 10) and s.clock_base_increment("none") == Vector2i.ZERO)
	s.free()


func _save_migration() -> void:
	var v1 := {"version": 1, "fen": "x", "history_uci": ["e2e4", "e7e5"], "mode": "ai", "ai_side": 1, "ai_difficulty": "master", "clock": {"white": 250.0, "black": 300.0, "enabled": true}}
	var n := SaveManager._normalize(v1)
	_ok("v1 save gets moves", (n["moves_uci"] as Array).size() == 2)
	_ok("v1 save gets start fen", str(n["start_fen"]) == ChessTypes.START_FEN)
	_ok("v1 level mapped", str(n["ai_level"]) == "master")
	var e := ChessEngine.new()
	_ok("v1 save replays", SaveManager.apply_to_engine(e, n) and e.history.size() == 2)
	var bad := {"version": 2, "start_fen": ChessTypes.START_FEN, "moves_uci": ["e2e5"]}
	_ok("illegal save rejected", not SaveManager.apply_to_engine(ChessEngine.new(), bad))


func _rating_math() -> void:
	var p = load("res://scripts/save/profile_store.gd").new()
	p.rating = 1200.0
	var opp := 1400.0
	var expected := 1.0 / (1.0 + pow(10.0, (opp - p.rating) / 400.0))
	_ok("expected score below half vs stronger", expected < 0.5)
	p.levels = {"club": {"w": 2, "d": 1, "l": 1}, "master": {"w": 0, "d": 0, "l": 3}}
	var t: Dictionary = p.totals()
	_ok("profile totals", t["w"] == 2 and t["d"] == 1 and t["l"] == 4 and t["games"] == 7)
	p.free()


func _ui_theme() -> void:
	var th := ThemeFactory.make()
	_ok("theme cached", th == ThemeFactory.make())
	for v in ["PrimaryButton", "GhostButton", "IconButton", "ChipButton", "MoveButton", "MainMenuButton"]:
		_ok("button variation %s" % v, th.get_type_variation_base(v) == "Button")
	for v in ["Card", "CardActive", "Modal", "Pill", "Toast", "Inset"]:
		_ok("panel variation %s" % v, th.get_type_variation_base(v) == "PanelContainer")
	_ok("tabular font", ThemeFactory.font("tabular") != null)


func _icons() -> void:
	for n in ["undo", "redo", "flip", "hint", "settings", "play", "star", "trophy", "moon"]:
		var tex := IconLibrary.get_icon(n, 20)
		_ok("icon %s" % n, tex != null and tex.get_width() == 40, str(tex.get_width() if tex else -1))
	_ok("icon cache", IconLibrary.get_icon("undo", 20) == IconLibrary.get_icon("undo", 20))


func _clock_format() -> void:
	_ok("clock mm:ss", UIKit.format_clock(125.0) == "2:05")
	_ok("clock tenths", UIKit.format_clock(9.44) == "0:09.4")
	_ok("clock hours", UIKit.format_clock(3725.0) == "1:02:05")
	_ok("clock zero", UIKit.format_clock(0.0) == "0:00")


func _first_mesh(node: Node) -> Mesh:
	for c in node.get_children():
		if c is MeshInstance3D:
			return (c as MeshInstance3D).mesh
		var nested := _first_mesh(c)
		if nested:
			return nested
	return null


func _has_body(node: Node) -> bool:
	for c in node.get_children():
		if c is StaticBody3D:
			return true
		if _has_body(c):
			return true
	return false
