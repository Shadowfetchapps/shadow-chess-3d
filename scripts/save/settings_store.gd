extends Node

const APP_ID := "shadow-chess-3d"

var graphics_quality: String = "high"
var resolution: Vector2i = Vector2i(1600, 900)
var fullscreen: bool = false
var vsync: bool = true
var camera_sensitivity: float = 1.0
var animation_speed: float = 1.0
var sound_volume: float = 0.8
var music_volume: float = 0.25
var sfx_enabled: bool = true
var show_legal_moves: bool = true
var board_orientation: String = "white"
var ai_difficulty: String = "medium"
var clock_seconds: int = 600
var msaa: int = 2

signal settings_changed


func _ready() -> void:
	load_settings()
	if not _is_headless():
		apply_display()
		apply_audio()


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


func to_dict() -> Dictionary:
	return {
		"graphics_quality": graphics_quality,
		"resolution": [resolution.x, resolution.y],
		"fullscreen": fullscreen,
		"vsync": vsync,
		"camera_sensitivity": camera_sensitivity,
		"animation_speed": animation_speed,
		"sound_volume": sound_volume,
		"music_volume": music_volume,
		"sfx_enabled": sfx_enabled,
		"show_legal_moves": show_legal_moves,
		"board_orientation": board_orientation,
		"ai_difficulty": ai_difficulty,
		"clock_seconds": clock_seconds,
		"msaa": msaa,
	}


func from_dict(d: Dictionary) -> void:
	graphics_quality = str(d.get("graphics_quality", graphics_quality))
	var res: Variant = d.get("resolution", [resolution.x, resolution.y])
	if res is Array and res.size() >= 2:
		resolution = Vector2i(int(res[0]), int(res[1]))
	fullscreen = bool(d.get("fullscreen", fullscreen))
	vsync = bool(d.get("vsync", vsync))
	camera_sensitivity = float(d.get("camera_sensitivity", camera_sensitivity))
	animation_speed = float(d.get("animation_speed", animation_speed))
	sound_volume = float(d.get("sound_volume", sound_volume))
	music_volume = float(d.get("music_volume", music_volume))
	sfx_enabled = bool(d.get("sfx_enabled", sfx_enabled))
	show_legal_moves = bool(d.get("show_legal_moves", show_legal_moves))
	board_orientation = str(d.get("board_orientation", board_orientation))
	ai_difficulty = str(d.get("ai_difficulty", ai_difficulty))
	clock_seconds = int(d.get("clock_seconds", clock_seconds))
	msaa = int(d.get("msaa", msaa))


func save_settings() -> void:
	ensure_dirs()
	var f := FileAccess.open(settings_path(), FileAccess.WRITE)
	if f == null:
		push_warning("Could not write settings")
		return
	f.store_string(JSON.stringify(to_dict(), "\t"))
	settings_changed.emit()


func load_settings() -> void:
	var path := settings_path()
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		from_dict(parsed)


func apply_display() -> void:
	if _is_headless():
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(resolution)
	var vp := get_viewport()
	if vp:
		match msaa:
			8:
				vp.msaa_3d = Viewport.MSAA_8X
			4:
				vp.msaa_3d = Viewport.MSAA_4X
			2:
				vp.msaa_3d = Viewport.MSAA_2X
			_:
				vp.msaa_3d = Viewport.MSAA_DISABLED


func apply_audio() -> void:
	var master := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master, linear_to_db(maxf(sound_volume, 0.0001)))
	AudioServer.set_bus_mute(master, sound_volume <= 0.001)


func ai_depth() -> int:
	match ai_difficulty:
		"easy":
			return 1
		"hard":
			return 3
		"master":
			return 4
		_:
			return 2


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless" or OS.has_feature("headless")
