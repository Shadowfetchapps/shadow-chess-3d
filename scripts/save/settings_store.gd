extends Node

## Persistent user settings (XDG config). Schema is versioned; older files are
## migrated on load and a corrupt file is moved aside instead of crashing.

signal settings_changed

const APP_ID := "shadow-chess-3d"
const SCHEMA := 3

const QUALITIES := ["low", "medium", "high", "ultra"]
const BOARD_THEMES := ["salon", "walnut", "marble", "tournament"]
const PIECE_STYLES := ["classic", "wood", "marble", "tournament"]
const CLOCK_PRESETS := ["none", "1+0", "3+2", "5+0", "10+0", "15+10", "30+0"]

var window_mode: String = "windowed"
var resolution: Vector2i = Vector2i(1600, 900)
var vsync: bool = true
var fps_limit: int = 0
var graphics_quality: String = "high"
var msaa: int = 4
var render_scale: float = 1.0
var ui_scale: float = 1.0

var board_theme: String = "salon"
var piece_style: String = "classic"
var show_legal_moves: bool = true
var show_coordinates: bool = true
var highlight_last_move: bool = true
var show_eval_bar: bool = false
var auto_queen: bool = false
var animation_speed: float = 1.0
var reduce_motion: bool = false
var high_contrast: bool = false

var camera_sensitivity: float = 1.0
var invert_orbit: bool = false
var camera_view: String = "player"

var master_volume: float = 0.9
var sfx_volume: float = 0.85
var music_volume: float = 0.35
var ui_volume: float = 0.6
var music_enabled: bool = true
var sfx_enabled: bool = true

var ai_level: String = "club"
var clock_preset: String = "10+0"
var player_name: String = "You"
var last_new_game: Dictionary = {}

var _loaded_from_disk := false


func _ready() -> void:
	load_settings()
	if not is_headless():
		apply_display()
	apply_audio()


# --- Paths --------------------------------------------------------------------

func config_dir() -> String:
	var xdg := OS.get_environment("XDG_CONFIG_HOME")
	if xdg.is_empty():
		xdg = OS.get_environment("HOME").path_join(".config")
	return xdg.path_join(APP_ID)


func data_dir() -> String:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if xdg.is_empty():
		xdg = OS.get_environment("HOME").path_join(".local/share")
	return xdg.path_join(APP_ID)


func saves_dir() -> String:
	return data_dir().path_join("saves")


func settings_path() -> String:
	return config_dir().path_join("settings.json")


func ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(config_dir())
	DirAccess.make_dir_recursive_absolute(saves_dir())


# --- Serialisation ------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA,
		"window_mode": window_mode,
		"resolution": [resolution.x, resolution.y],
		"vsync": vsync,
		"fps_limit": fps_limit,
		"graphics_quality": graphics_quality,
		"msaa": msaa,
		"render_scale": render_scale,
		"ui_scale": ui_scale,
		"board_theme": board_theme,
		"piece_style": piece_style,
		"show_legal_moves": show_legal_moves,
		"show_coordinates": show_coordinates,
		"highlight_last_move": highlight_last_move,
		"show_eval_bar": show_eval_bar,
		"auto_queen": auto_queen,
		"animation_speed": animation_speed,
		"reduce_motion": reduce_motion,
		"high_contrast": high_contrast,
		"camera_sensitivity": camera_sensitivity,
		"invert_orbit": invert_orbit,
		"camera_view": camera_view,
		"master_volume": master_volume,
		"sfx_volume": sfx_volume,
		"music_volume": music_volume,
		"ui_volume": ui_volume,
		"music_enabled": music_enabled,
		"sfx_enabled": sfx_enabled,
		"ai_level": ai_level,
		"clock_preset": clock_preset,
		"player_name": player_name,
		"last_new_game": last_new_game,
	}


func from_dict(d: Dictionary) -> void:
	var schema := int(d.get("schema", 1))
	if schema < 3:
		d = _migrate_v2(d)
	window_mode = _pick(d.get("window_mode", window_mode), ["windowed", "fullscreen", "borderless"], window_mode)
	var res: Variant = d.get("resolution", [resolution.x, resolution.y])
	if res is Array and res.size() >= 2:
		resolution = Vector2i(clampi(int(res[0]), 960, 7680), clampi(int(res[1]), 600, 4320))
	vsync = bool(d.get("vsync", vsync))
	fps_limit = clampi(int(d.get("fps_limit", fps_limit)), 0, 500)
	graphics_quality = _pick(d.get("graphics_quality", graphics_quality), QUALITIES, graphics_quality)
	msaa = _pick_int(int(d.get("msaa", msaa)), [0, 2, 4, 8], msaa)
	render_scale = clampf(float(d.get("render_scale", render_scale)), 0.5, 1.0)
	ui_scale = clampf(float(d.get("ui_scale", ui_scale)), 0.8, 1.5)
	board_theme = _pick(d.get("board_theme", board_theme), BOARD_THEMES, board_theme)
	piece_style = _pick(d.get("piece_style", piece_style), PIECE_STYLES, piece_style)
	show_legal_moves = bool(d.get("show_legal_moves", show_legal_moves))
	show_coordinates = bool(d.get("show_coordinates", show_coordinates))
	highlight_last_move = bool(d.get("highlight_last_move", highlight_last_move))
	show_eval_bar = bool(d.get("show_eval_bar", show_eval_bar))
	auto_queen = bool(d.get("auto_queen", auto_queen))
	animation_speed = clampf(float(d.get("animation_speed", animation_speed)), 0.4, 2.5)
	reduce_motion = bool(d.get("reduce_motion", reduce_motion))
	high_contrast = bool(d.get("high_contrast", high_contrast))
	camera_sensitivity = clampf(float(d.get("camera_sensitivity", camera_sensitivity)), 0.2, 3.0)
	invert_orbit = bool(d.get("invert_orbit", invert_orbit))
	camera_view = _pick(d.get("camera_view", camera_view), ["player", "top"], camera_view)
	master_volume = clampf(float(d.get("master_volume", master_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(d.get("sfx_volume", sfx_volume)), 0.0, 1.0)
	music_volume = clampf(float(d.get("music_volume", music_volume)), 0.0, 1.0)
	ui_volume = clampf(float(d.get("ui_volume", ui_volume)), 0.0, 1.0)
	music_enabled = bool(d.get("music_enabled", music_enabled))
	sfx_enabled = bool(d.get("sfx_enabled", sfx_enabled))
	ai_level = str(d.get("ai_level", ai_level))
	if not ai_level in ["beginner", "casual", "club", "advanced", "expert", "master"]:
		ai_level = "club"
	clock_preset = _pick(d.get("clock_preset", clock_preset), CLOCK_PRESETS, clock_preset)
	player_name = str(d.get("player_name", player_name)).strip_edges().left(24)
	if player_name.is_empty():
		player_name = "You"
	var lng: Variant = d.get("last_new_game", {})
	last_new_game = lng if lng is Dictionary else {}


## 2.0 stored `fullscreen`, `sound_volume`, `ai_difficulty`, `clock_seconds`.
func _migrate_v2(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	if d.has("fullscreen") and not d.has("window_mode"):
		out["window_mode"] = "fullscreen" if bool(d["fullscreen"]) else "windowed"
	if d.has("sound_volume") and not d.has("master_volume"):
		out["master_volume"] = float(d["sound_volume"])
	if d.has("ai_difficulty") and not d.has("ai_level"):
		out["ai_level"] = {"easy": "casual", "medium": "club", "hard": "advanced", "master": "master"}.get(str(d["ai_difficulty"]), "club")
	if d.has("clock_seconds") and not d.has("clock_preset"):
		var secs := int(d["clock_seconds"])
		out["clock_preset"] = "none" if secs <= 0 else "%d+0" % int(secs / 60.0)
		if not out["clock_preset"] in CLOCK_PRESETS:
			out["clock_preset"] = "10+0"
	if d.has("board_orientation"):
		out.erase("board_orientation")
	out["schema"] = SCHEMA
	return out


func _pick(v: Variant, allowed: Array, fallback: String) -> String:
	var s := str(v)
	return s if s in allowed else fallback


func _pick_int(v: int, allowed: Array, fallback: int) -> int:
	return v if v in allowed else fallback


func save_settings() -> void:
	ensure_dirs()
	var tmp := settings_path() + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write settings to %s" % tmp)
		return
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	DirAccess.rename_absolute(tmp, settings_path())
	settings_changed.emit()


func load_settings() -> void:
	var path := settings_path()
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		from_dict(parsed)
		_loaded_from_disk = true
	else:
		# Keep the broken file for inspection and continue with defaults.
		DirAccess.rename_absolute(path, path + ".corrupt")
		push_warning("Settings file was unreadable; moved to %s.corrupt" % path)


func reset_defaults() -> void:
	var fresh = get_script().new()
	from_dict(fresh.to_dict())
	fresh.free()
	save_settings()
	apply_display()
	apply_audio()


# --- Apply --------------------------------------------------------------------

func apply_display() -> void:
	if is_headless():
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = fps_limit
	match window_mode:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
			var size := Vector2i(mini(resolution.x, screen.size.x), mini(resolution.y, screen.size.y))
			if DisplayServer.window_get_size() != size:
				DisplayServer.window_set_size(size)
				DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = {8: Viewport.MSAA_8X, 4: Viewport.MSAA_4X, 2: Viewport.MSAA_2X}.get(msaa, Viewport.MSAA_DISABLED)
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if graphics_quality != "low" and msaa == 0 else Viewport.SCREEN_SPACE_AA_DISABLED
		vp.use_taa = graphics_quality == "ultra"
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = render_scale
		get_tree().root.content_scale_factor = ui_scale


func apply_audio() -> void:
	_set_bus("Master", master_volume, false)
	_set_bus("Music", music_volume, not music_enabled)
	_set_bus("SFX", sfx_volume, not sfx_enabled)
	_set_bus("UI", ui_volume, not sfx_enabled)


func _set_bus(name: String, linear: float, muted: bool) -> void:
	var idx := AudioServer.get_bus_index(name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, muted or linear <= 0.001)


# --- Derived quality switches ------------------------------------------------

func bloom_enabled() -> bool:
	return graphics_quality != "low"


func shadows_enabled() -> bool:
	return graphics_quality != "low"


func ssao_enabled() -> bool:
	return graphics_quality in ["high", "ultra"]


func ssil_enabled() -> bool:
	return graphics_quality == "ultra"


func ssr_enabled() -> bool:
	return graphics_quality in ["high", "ultra"]


func dof_enabled() -> bool:
	return graphics_quality in ["high", "ultra"] and not reduce_motion


func volumetric_fog_enabled() -> bool:
	return graphics_quality == "ultra"


func clock_base_increment(preset: String = "") -> Vector2i:
	var p := clock_preset if preset.is_empty() else preset
	if p == "none" or not "+" in p:
		return Vector2i.ZERO
	var parts := p.split("+")
	return Vector2i(int(parts[0]) * 60, int(parts[1]))


func motion_scale() -> float:
	return 0.0 if reduce_motion else 1.0


func is_headless() -> bool:
	return DisplayServer.get_name() == "headless" or OS.has_feature("headless")


func was_loaded_from_disk() -> bool:
	return _loaded_from_disk
