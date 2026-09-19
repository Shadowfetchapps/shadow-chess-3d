extends Node

var _players: Dictionary = {}
var _streams: Dictionary = {}
var _music: AudioStreamPlayer


func _ready() -> void:
	_streams["move"] = _tone(540, 0.07, 0.28, 0.4)
	_streams["capture"] = _tone(220, 0.14, 0.38, 1.6)
	_streams["check"] = _chord([660, 880], 0.18, 0.22)
	_streams["checkmate"] = _chord([392, 523, 659], 0.55, 0.28)
	_streams["ui"] = _tone(880, 0.04, 0.16, 0.2)
	_streams["promote"] = _chord([523, 784], 0.22, 0.2)
	_streams["castle"] = _tone(360, 0.12, 0.24, 0.8)
	for key in _streams:
		var p := AudioStreamPlayer.new()
		p.stream = _streams[key]
		p.bus = "Master"
		add_child(p)
		_players[key] = p
	_music = AudioStreamPlayer.new()
	_music.stream = _pad()
	_music.volume_db = -22.0
	_music.bus = "Master"
	add_child(_music)
	SettingsStore.settings_changed.connect(_on_settings)
	_on_settings()


func play(kind: String) -> void:
	if not SettingsStore.sfx_enabled:
		return
	if SettingsStore.sound_volume <= 0.001:
		return
	if _players.has(kind):
		_players[kind].play()


func _on_settings() -> void:
	SettingsStore.apply_audio()
	if _music:
		_music.volume_db = linear_to_db(maxf(SettingsStore.music_volume * 0.35, 0.0001))
		if SettingsStore.music_volume > 0.02 and not _music.playing:
			_music.play()
		elif SettingsStore.music_volume <= 0.02:
			_music.stop()


func _tone(freq: float, seconds: float, vol: float, decay: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var env := exp(-t * (6.0 + decay * 8.0)) * (1.0 - t / seconds)
		var s := int(sin(t * TAU * freq) * 32767.0 * vol * env)
		s = clampi(s, -32767, 32767)
		data[i * 2] = s & 255
		data[i * 2 + 1] = (s >> 8) & 255
	return _wav(data, rate)


func _chord(freqs: Array, seconds: float, vol: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var env := exp(-t * 4.0) * (1.0 - t / seconds)
		var sample := 0.0
		for f in freqs:
			sample += sin(t * TAU * float(f))
		sample /= float(freqs.size())
		var s := int(sample * 32767.0 * vol * env)
		s = clampi(s, -32767, 32767)
		data[i * 2] = s & 255
		data[i * 2 + 1] = (s >> 8) & 255
	return _wav(data, rate)


func _pad() -> AudioStreamWAV:
	var rate := 22050
	var seconds := 8.0
	var n := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var sample := 0.12 * sin(t * TAU * 110.0) + 0.08 * sin(t * TAU * 164.8) + 0.05 * sin(t * TAU * 220.0)
		sample *= 0.55 + 0.45 * sin(t * TAU * 0.12)
		var s := int(sample * 32767.0)
		s = clampi(s, -32767, 32767)
		data[i * 2] = s & 255
		data[i * 2 + 1] = (s >> 8) & 255
	var w := _wav(data, rate)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w


func _wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	return s
