class_name MaterialLibrary
extends RefCounted

const GOLD := Color(0.84, 0.70, 0.36)
const IVORY := Color(0.94, 0.90, 0.80)
const EBONY := Color(0.10, 0.09, 0.10)

static var _ready := false
static var ivory_mat: StandardMaterial3D
static var ebony_mat: StandardMaterial3D
static var gold_mat: StandardMaterial3D
static var gold_trim_mat: StandardMaterial3D
static var light_sq: StandardMaterial3D
static var dark_sq: StandardMaterial3D
static var wood_frame: StandardMaterial3D
static var wood_floor: StandardMaterial3D
static var felt_mat: StandardMaterial3D
static var brass_mat: StandardMaterial3D
static var drape_mat: StandardMaterial3D
static var wall_mat: StandardMaterial3D
static var column_mat: StandardMaterial3D
static var select_mat: StandardMaterial3D
static var legal_mat: StandardMaterial3D
static var capture_mat: StandardMaterial3D
static var check_mat: StandardMaterial3D
static var last_mat: StandardMaterial3D
static var hover_mat: StandardMaterial3D
static var gold_emit: StandardMaterial3D
static var lamp_glass: StandardMaterial3D


static func ensure() -> void:
	if _ready:
		return
	_ready = true
	ivory_mat = _piece(IVORY, 0.16, 0.34, 0.20)
	ivory_mat.albedo_texture = _ivory_tex()
	ebony_mat = _piece(EBONY, 0.22, 0.40, 0.14)
	ebony_mat.albedo_texture = _ebony_tex()
	gold_mat = _metal(GOLD, 0.78, 0.28)
	gold_trim_mat = _metal(Color(0.90, 0.74, 0.38), 0.82, 0.22)
	gold_trim_mat.emission_enabled = true
	gold_trim_mat.emission = Color(0.72, 0.54, 0.22)
	gold_trim_mat.emission_energy_multiplier = 0.22
	light_sq = _pbr(Color(0.84, 0.76, 0.60), 0.58, 0.05)
	light_sq.albedo_texture = _wood_tex(Color(0.86, 0.76, 0.58), Color(0.62, 0.50, 0.34), 0.11, 0.028)
	dark_sq = _pbr(Color(0.16, 0.12, 0.10), 0.64, 0.08)
	dark_sq.albedo_texture = _stone_tex()
	wood_frame = _pbr(Color(0.22, 0.13, 0.08), 0.42, 0.14)
	wood_frame.albedo_texture = _wood_tex(Color(0.28, 0.16, 0.09), Color(0.10, 0.06, 0.04), 0.09, 0.02)
	wood_frame.clearcoat_enabled = true
	wood_frame.clearcoat = 0.22
	wood_floor = _pbr(Color(0.16, 0.11, 0.07), 0.74, 0.04)
	wood_floor.albedo_texture = _wood_tex(Color(0.20, 0.13, 0.08), Color(0.08, 0.055, 0.035), 0.06, 0.018)
	felt_mat = _pbr(Color(0.06, 0.05, 0.045), 0.90, 0.0)
	brass_mat = _metal(Color(0.78, 0.58, 0.24), 0.74, 0.30)
	drape_mat = _pbr(Color(0.22, 0.07, 0.08), 0.80, 0.02)
	wall_mat = _pbr(Color(0.12, 0.10, 0.085), 0.86, 0.0)
	column_mat = _pbr(Color(0.22, 0.18, 0.14), 0.46, 0.16)
	select_mat = _emit(Color(0.90, 0.76, 0.38, 0.42), 0.85)
	legal_mat = _emit(Color(0.86, 0.70, 0.34, 0.78), 1.15)
	capture_mat = _emit(Color(0.92, 0.38, 0.28, 0.72), 1.05)
	check_mat = _emit(Color(0.95, 0.22, 0.24, 0.55), 1.25)
	last_mat = _emit(Color(0.90, 0.72, 0.32, 0.26), 0.45)
	hover_mat = _emit(Color(0.94, 0.84, 0.52, 0.34), 0.55)
	gold_emit = _emit(Color(0.90, 0.74, 0.36, 1.0), 0.55)
	gold_emit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_glass = _pbr(Color(1.0, 0.86, 0.58, 0.35), 0.12, 0.0)
	lamp_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lamp_glass.emission_enabled = true
	lamp_glass.emission = Color(1.0, 0.78, 0.42)
	lamp_glass.emission_energy_multiplier = 1.6


static func piece_body(color: int) -> StandardMaterial3D:
	ensure()
	return ivory_mat if color == ChessTypes.WHITE else ebony_mat


static func _pbr(albedo: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	return m


static func _piece(albedo: Color, metal: float, rough: float, rim: float) -> StandardMaterial3D:
	var m := _pbr(albedo, rough, metal)
	m.rim_enabled = true
	m.rim = rim
	m.rim_tint = 0.35
	m.clearcoat_enabled = true
	m.clearcoat = 0.18
	m.clearcoat_roughness = 0.32
	return m


static func _metal(albedo: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := _pbr(albedo, rough, metal)
	m.clearcoat_enabled = true
	m.clearcoat = 0.28
	m.clearcoat_roughness = 0.18
	return m


static func _emit(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(c.r, c.g, c.b)
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _hash(x: int, y: int, seed: int) -> float:
	var n := x * 374761393 + y * 668265263 + seed * 1274126177
	n = (n ^ (n >> 13)) * 1274126177
	return float(n & 0x7fffffff) / 2147483647.0


static func _vnoise(x: float, y: float, seed: int) -> float:
	var x0 := int(floor(x))
	var y0 := int(floor(y))
	var fx := x - float(x0)
	var fy := y - float(y0)
	var u := fx * fx * (3.0 - 2.0 * fx)
	var v := fy * fy * (3.0 - 2.0 * fy)
	var a := _hash(x0, y0, seed)
	var b := _hash(x0 + 1, y0, seed)
	var c := _hash(x0, y0 + 1, seed)
	var d := _hash(x0 + 1, y0 + 1, seed)
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


static func _fbm(x: float, y: float, seed: int) -> float:
	return _vnoise(x, y, seed) * 0.57 + _vnoise(x * 2.1, y * 2.1, seed + 17) * 0.28 + _vnoise(x * 4.3, y * 4.3, seed + 31) * 0.15


static func _tex_from(img: Image) -> ImageTexture:
	var tex := ImageTexture.create_from_image(img)
	return tex


static func _wood_tex(a: Color, b: Color, stretch: float, grain: float) -> ImageTexture:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in 256:
		for x in 256:
			var n := _fbm(float(x) * stretch, float(y) * grain, 11)
			var ring := absf(sin((float(y) * 0.085 + n * 3.2)))
			var t := clampf(n * 0.65 + ring * 0.35, 0.0, 1.0)
			img.set_pixel(x, y, a.lerp(b, t))
	return _tex_from(img)


static func _stone_tex() -> ImageTexture:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var deep := Color(0.13, 0.10, 0.09)
	var lift := Color(0.22, 0.17, 0.14)
	for y in 256:
		for x in 256:
			var n := _fbm(float(x) * 0.035, float(y) * 0.035, 41)
			var c := deep.lerp(lift, n)
			if _hash(x, y, 99) > 0.993:
				c = c.lerp(GOLD, 0.45)
			img.set_pixel(x, y, c)
	return _tex_from(img)


static func _ivory_tex() -> ImageTexture:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var a := Color(0.96, 0.92, 0.82)
	var b := Color(0.86, 0.78, 0.64)
	for y in 128:
		for x in 128:
			var n := _fbm(float(x) * 0.07, float(y) * 0.07, 7)
			img.set_pixel(x, y, a.lerp(b, n * 0.55))
	return _tex_from(img)


static func _ebony_tex() -> ImageTexture:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var a := Color(0.09, 0.085, 0.095)
	var b := Color(0.18, 0.16, 0.17)
	for y in 128:
		for x in 128:
			var n := _fbm(float(x) * 0.08, float(y) * 0.08, 23)
			img.set_pixel(x, y, a.lerp(b, n * 0.5))
	return _tex_from(img)
