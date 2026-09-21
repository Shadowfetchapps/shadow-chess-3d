class_name WorldLook
extends RefCounted


static func make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.028, 0.022)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.36, 0.28)
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.04
	env.glow_enabled = SettingsStore.bloom_enabled()
	env.glow_intensity = 0.20
	env.glow_bloom = 0.032
	env.glow_hdr_threshold = 1.28
	env.ssao_enabled = SettingsStore.ssao_enabled()
	env.ssao_radius = 0.95
	env.ssao_intensity = 0.42
	env.ssr_enabled = SettingsStore.ssr_enabled()
	env.ssr_max_steps = 24
	env.ssr_fade_in = 0.15
	env.fog_enabled = SettingsStore.graphics_quality != "low"
	env.fog_light_color = Color(0.07, 0.06, 0.05)
	env.fog_density = 0.0035
	env.fog_aerial_perspective = 0.35
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.06
	env.adjustment_contrast = 1.03
	return env


static func apply_quality(env: Environment) -> void:
	if env == null:
		return
	env.glow_enabled = SettingsStore.bloom_enabled()
	env.ssao_enabled = SettingsStore.ssao_enabled()
	env.ssr_enabled = SettingsStore.ssr_enabled()
	env.fog_enabled = SettingsStore.graphics_quality != "low"


static func add_lights(parent: Node3D) -> Dictionary:
	var nodes := {}
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_color = Color(1.0, 0.93, 0.80)
	key.light_energy = 1.55
	key.shadow_enabled = SettingsStore.shadows_enabled()
	key.directional_shadow_max_distance = 28.0
	key.rotation_degrees = Vector3(-50, -30, 6)
	parent.add_child(key)
	nodes["key"] = key
	var spot := SpotLight3D.new()
	spot.name = "BoardSpot"
	spot.position = Vector3(0.0, 8.4, 5.6)
	spot.light_color = Color(1.0, 0.84, 0.58)
	spot.light_energy = 2.55
	spot.spot_range = 16.0
	spot.spot_angle = 36.0
	spot.shadow_enabled = SettingsStore.shadows_enabled() and SettingsStore.graphics_quality == "high"
	parent.add_child(spot)
	spot.look_at(Vector3(0.0, 0.2, 0.0))
	nodes["spot"] = spot
	var fill := OmniLight3D.new()
	fill.position = Vector3(5.4, 3.4, 5.0)
	fill.light_color = Color(0.48, 0.62, 0.86)
	fill.light_energy = 0.38
	fill.omni_range = 16.0
	parent.add_child(fill)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-5.8, 4.2, -5.2)
	rim.light_color = Color(0.92, 0.72, 0.36)
	rim.light_energy = 0.72
	rim.omni_range = 14.0
	parent.add_child(rim)
	var board_fill := OmniLight3D.new()
	board_fill.position = Vector3(0.0, 3.2, 1.4)
	board_fill.light_color = Color(1.0, 0.96, 0.88)
	board_fill.light_energy = 1.25
	board_fill.omni_range = 8.5
	parent.add_child(board_fill)
	return nodes
