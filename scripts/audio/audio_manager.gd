extends Node

## Sound for the whole app. Samples live in res://assets/audio (rendered by
## tools/assetgen/gen_audio.py). Each cue may have numbered variants that are
## rotated so repeated moves never sound identical. Missing files fall back to
## a small procedural tone so the game is never silent.

const AUDIO_DIR := "res://assets/audio/"
const BUSES := ["Music", "SFX", "UI"]
const SFX_VOICES := 8
const UI_VOICES := 4

## cue -> [bus, base volume dB, pitch jitter]
const CUES := {
	"move": ["SFX", 0.0, 0.03],
	"capture": ["SFX", 0.0, 0.03],
	"castle": ["SFX", 0.0, 0.0],
	"check": ["SFX", -1.0, 0.0],
	"checkmate": ["SFX", 0.0, 0.0],
	"draw": ["SFX", -1.0, 0.0],
	"promote": ["SFX", -1.0, 0.0],
	"illegal": ["SFX", -3.0, 0.0],
	"select": ["SFX", -6.0, 0.04],
	"game_start": ["SFX", -2.0, 0.0],
	"clock_tick": ["SFX", -4.0, 0.0],
	"clock_warning": ["SFX", -2.0, 0.0],
	"hint": ["SFX", -2.0, 0.0],
	"puzzle_solved": ["SFX", 0.0, 0.0],
	"puzzle_wrong": ["SFX", -2.0, 0.0],
	"victory": ["SFX", 0.0, 0.0],
	"defeat": ["SFX", -1.0, 0.0],
	"ui_click": ["UI", 0.0, 0.02],
	"ui_hover": ["UI", -8.0, 0.02],
	"ui_open": ["UI", -2.0, 0.0],
	"ui_close": ["UI", -2.0, 0.0],
}
## Legacy names used by older call sites.
const ALIASES := {"ui": "ui_click", "win": "victory"}

var _streams: Dictionary = {}
var _rotation: Dictionary = {}
var _sfx_pool: Array[AudioStreamPlayer] = []
var _ui_pool: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _ui_next := 0
var _music: AudioStreamPlayer
var _music_tween: Tween
var _rng := RandomNumberGenerator.new()
var _last_hover_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_ensure_buses()
	for cue in CUES:
		_streams[cue] = _load_variants(cue)
		_rotation[cue] = 0
	for i in SFX_VOICES:
		_sfx_pool.append(_voice("SFX"))
	for i in UI_VOICES:
		_ui_pool.append(_voice("UI"))
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.volume_db = -80.0
	add_child(_music)
	var track := AUDIO_DIR + "music_salon.ogg"
	if ResourceLoader.exists(track):
		var s: AudioStream = load(track)
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		_music.stream = s
	SettingsStore.settings_changed.connect(_on_settings)
	SettingsStore.apply_audio()
	call_deferred("_on_settings")


func play(cue: String, volume_offset_db: float = 0.0) -> void:
	cue = ALIASES.get(cue, cue)
	if not _streams.has(cue):
		return
	if cue == "ui_hover":
		var now := Time.get_ticks_msec()
		if now - _last_hover_ms < 45:
			return
		_last_hover_ms = now
	var variants: Array = _streams[cue]
	if variants.is_empty():
		return
	var idx: int = _rotation[cue]
	_rotation[cue] = (idx + 1 + _rng.randi_range(0, maxi(variants.size() - 2, 0))) % variants.size()
	var spec: Array = CUES[cue]
	var player := _next_voice(spec[0])
	player.stream = variants[idx % variants.size()]
	player.volume_db = float(spec[1]) + volume_offset_db
	var jitter: float = spec[2]
	player.pitch_scale = 1.0 + (_rng.randf_range(-jitter, jitter) if jitter > 0.0 else 0.0)
	player.play()


func play_music(fade_seconds: float = 2.5) -> void:
	if _music == null or _music.stream == null:
		return
	if not SettingsStore.music_enabled:
		return
	if not _music.playing:
		_music.volume_db = -40.0
		_music.play()
	_fade_music(0.0, fade_seconds)


func stop_music(fade_seconds: float = 1.2) -> void:
	if _music == null or not _music.playing:
		return
	_fade_music(-60.0, fade_seconds, true)


func duck_music(on: bool) -> void:
	if _music and _music.playing:
		_fade_music(-9.0 if on else 0.0, 0.6)


func _fade_music(target_db: float, seconds: float, stop_after: bool = false) -> void:
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", target_db, maxf(seconds, 0.01))
	if stop_after:
		_music_tween.tween_callback(_music.stop)


func _on_settings() -> void:
	SettingsStore.apply_audio()
	if SettingsStore.music_enabled and SettingsStore.music_volume > 0.01:
		play_music(1.5)
	else:
		stop_music(0.6)


func _ensure_buses() -> void:
	for name in BUSES:
		if AudioServer.get_bus_index(name) >= 0:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, name)
		AudioServer.set_bus_send(idx, "Master")
	var music := AudioServer.get_bus_index("Music")
	if music >= 0 and AudioServer.get_bus_effect_count(music) == 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 16000.0
		AudioServer.add_bus_effect(music, lp)
	var master := AudioServer.get_bus_index("Master")
	if master >= 0 and AudioServer.get_bus_effect_count(master) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(master, lim)


func _voice(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func _next_voice(bus: String) -> AudioStreamPlayer:
	if bus == "UI":
		_ui_next = (_ui_next + 1) % _ui_pool.size()
		return _ui_pool[_ui_next]
	for i in _sfx_pool.size():
		var p := _sfx_pool[(_sfx_next + i) % _sfx_pool.size()]
		if not p.playing:
			_sfx_next = (_sfx_next + i + 1) % _sfx_pool.size()
			return p
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	return _sfx_pool[_sfx_next]


func _load_variants(cue: String) -> Array:
	var out: Array = []
	var single := AUDIO_DIR + cue + ".ogg"
	if ResourceLoader.exists(single):
		out.append(load(single))
	for i in range(1, 9):
		var p := AUDIO_DIR + "%s_%d.ogg" % [cue, i]
		if not ResourceLoader.exists(p):
			break
		out.append(load(p))
	if out.is_empty():
		out.append(_fallback(cue))
	return out


# --- Procedural fallback -------------------------------------------------------

func _fallback(cue: String) -> AudioStreamWAV:
	match cue:
		"move", "select":
			return _knock(520.0, 0.09)
		"capture":
			return _knock(260.0, 0.16)
		"castle":
			return _knock(380.0, 0.14)
		"check", "hint", "clock_warning":
			return _chime([660.0, 880.0], 0.3)
		"checkmate", "victory", "puzzle_solved":
			return _chime([392.0, 523.0, 659.0], 0.8)
		"draw", "defeat", "puzzle_wrong":
			return _chime([330.0, 392.0], 0.5)
		"promote":
			return _chime([523.0, 784.0], 0.35)
		_:
			return _knock(900.0, 0.04)


func _knock(freq: float, seconds: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var env := exp(-t * 55.0)
		var v := (sin(t * TAU * freq) * 0.6 + sin(t * TAU * freq * 2.7) * 0.25 + _rng.randf_range(-1.0, 1.0) * exp(-t * 400.0) * 0.4) * env
		data.encode_s16(i * 2, clampi(int(v * 20000.0), -32767, 32767))
	return _wav(data, rate)


func _chime(freqs: Array, seconds: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var v := 0.0
		for f in freqs:
			v += sin(t * TAU * float(f)) + 0.3 * sin(t * TAU * float(f) * 2.76) * exp(-t * 6.0)
		v = v / float(freqs.size()) * exp(-t * 4.0) * minf(t * 200.0, 1.0)
		data.encode_s16(i * 2, clampi(int(v * 12000.0), -32767, 32767))
	return _wav(data, rate)


func _wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	return s
