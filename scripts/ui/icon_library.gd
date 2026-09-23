class_name IconLibrary
extends RefCounted

## Original stroke icons on a 24×24 grid, rasterised from SVG at runtime and
## cached. Icons are white by default so Button icon colours can tint them.
## Textures are rendered at 2× and drawn with `icon_max_width` so they stay
## crisp when the canvas is stretched on large windows.

const OVERSAMPLE := 2

const PATHS := {
	"undo": ["M9 14 4 9l5-5", "M4 9h10.5a5.5 5.5 0 0 1 0 11H11"],
	"redo": ["m15 14 5-5-5-5", "M20 9H9.5a5.5 5.5 0 0 0 0 11H13"],
	"flip": ["M7 4v16", "m3 16 4 4 4-4", "M17 20V4", "m21 8-4-4-4 4"],
	"hint": ["M9 18h6", "M10 21.5h4", "M12 2.5a6.5 6.5 0 0 0-3.8 11.8c.5.4.8 1 .8 1.7v.5h6v-.5c0-.7.3-1.3.8-1.7A6.5 6.5 0 0 0 12 2.5z"],
	"pause": ["M8.5 5v14", "M15.5 5v14"],
	"chevron_left": ["m15 18-6-6 6-6"],
	"chevron_right": ["m9 18 6-6-6-6"],
	"chevron_down": ["m6 9 6 6 6-6"],
	"chevron_up": ["m6 15 6-6 6 6"],
	"first": ["M6 5v14", "m17.5 18-6-6 6-6"],
	"last": ["M18 5v14", "m6.5 18 6-6-6-6"],
	"flag": ["M5 21V3.5", "M5 4h12l-2.5 4.5L17 13H5"],
	"draw": ["M12 3v18", "M7 21h10", "M4.5 7.5h15", "M4.5 7.5l-2.5 6a2.5 2.5 0 0 0 5 0z", "M19.5 7.5l-2.5 6a2.5 2.5 0 0 0 5 0z"],
	"save": ["M5 3.5h11l3.5 3.5v13.5H5z", "M8 3.5v5h7v-5", "M8 20.5v-6.5h8v6.5"],
	"copy": ["M9 9h11v11H9z", "M5 15H4V4h11v1"],
	"download": ["M12 4v11.5", "m7 11 5 5 5-5", "M5 20h14"],
	"upload": ["M12 20V8.5", "m7 13 5-5 5 5", "M5 4h14"],
	"close": ["M6 6l12 12", "M18 6 6 18"],
	"check": ["m5 12.5 4.5 4.5L19 7"],
	"target": ["M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18z", "M12 7.5a4.5 4.5 0 1 0 0 9a4.5 4.5 0 1 0 0-9z", "M12 11.2v1.6"],
	"trophy": ["M8 21h8", "M12 16.5V21", "M7 3.5h10v5.5a5 5 0 0 1-10 0z", "M17 5.5h3v1.5a3.5 3.5 0 0 1-3.5 3.5", "M7 5.5H4v1.5a3.5 3.5 0 0 0 3.5 3.5"],
	"chart": ["M5 20v-6", "M12 20V5", "M19 20V10", "M3 20.5h18"],
	"info": ["M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18z", "M12 11v6", "M12 7.6v.2"],
	"help": ["M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18z", "M9.5 9.5a2.6 2.6 0 1 1 3.6 2.4c-.7.3-1.1.9-1.1 1.6v.5", "M12 17.2v.2"],
	"volume": ["M4 9.5v5h3.5L13 19V5L7.5 9.5z", "M16.5 8.8a4.5 4.5 0 0 1 0 6.4", "M19 6.5a8 8 0 0 1 0 11"],
	"mute": ["M4 9.5v5h3.5L13 19V5L7.5 9.5z", "m16.5 9.5 5 5", "m21.5 9.5-5 5"],
	"fullscreen": ["M4 9V4h5", "M15 4h5v5", "M20 15v5h-5", "M9 20H4v-5"],
	"eye": ["M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z", "M12 9a3 3 0 1 0 0 6a3 3 0 1 0 0-6z"],
	"menu": ["M4 7h16", "M4 12h16", "M4 17h16"],
	"clock": ["M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18z", "M12 7.5V12l3 2"],
	"user": ["M12 4a4 4 0 1 0 0 8a4 4 0 1 0 0-8z", "M4.5 20.5a7.5 7.5 0 0 1 15 0"],
	"users": ["M9 4.5a3.5 3.5 0 1 0 0 7a3.5 3.5 0 1 0 0-7z", "M2.5 20a6.5 6.5 0 0 1 13 0", "M16 4.8a3.3 3.3 0 0 1 0 6.4", "M18 13.8a6.5 6.5 0 0 1 3.5 6.2"],
	"moon": ["M20 14.5A8.5 8.5 0 1 1 9.5 4a7 7 0 0 0 10.5 10.5z"],
	"restart": ["M4 12a8 8 0 0 1 14-5.3L20 8.5", "M20 3.5v5h-5", "M20 12a8 8 0 0 1-14 5.3L4 15.5", "M4 20.5v-5h5"],
	"trash": ["M4 7h16", "M9 7V4h6v3", "M6 7l1 13h10l1-13", "M10 11v5", "M14 11v5"],
	"folder": ["M3 6.5h6l2 2h10v11H3z"],
	"arrow_right": ["M5 12h14", "m13 6 6 6-6 6"],
	"arrow_left": ["M19 12H5", "m11 6-6 6 6 6"],
	"camera": ["M3 12a9 9 0 1 0 3-6.7L3 8", "M3 3v5h5"],
	"grid": ["M4 4h16v16H4z", "M4 12h16", "M12 4v16"],
	"settings": [],
	"play": [],
	"star": [],
	"plus": ["M12 5v14", "M5 12h14"],
	"minus": ["M5 12h14"],
	"board": ["M4 4h16v16H4z", "M4 4h8v8H4z", "M12 12h8v8h-8z"],
	"sparkle": ["M12 3v4", "M12 17v4", "M3 12h4", "M17 12h4", "m6 6 2.5 2.5", "m15.5 15.5 2.5 2.5", "m18 6-2.5 2.5", "M8.5 15.5 6 18"],
	"book": ["M4 5a2 2 0 0 1 2-2h13v15H6a2 2 0 0 0-2 2z", "M4 20a2 2 0 0 0 2 2h13v-4"],
	"file": ["M6 3h8l4 4v14H6z", "M14 3v4h4"],
	"swap": ["M4 8h14", "m14 4 4 4-4 4", "M20 16H6", "m10 20-4-4 4-4"],
}

static var _cache: Dictionary = {}


static func get_icon(name: String, size: int = 20, color: Color = Color.WHITE, oversample: int = OVERSAMPLE) -> Texture2D:
	var key := "%s|%d|%s|%d" % [name, size, color.to_html(), oversample]
	if _cache.has(key):
		return _cache[key]
	var tex := _rasterize(_svg(name, color), float(size * oversample) / 24.0)
	_cache[key] = tex
	return tex


static func toggle_icon(on: bool) -> Texture2D:
	var key := "toggle|%s" % on
	if _cache.has(key):
		return _cache[key]
	var track := "#d6b25c" if on else "#3a342c"
	var knob := "#1a140c" if on else "#a89f8a"
	var cx := 27 if on else 13
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='40' height='24' viewBox='0 0 40 24'>" \
		+ "<rect x='1' y='3' width='38' height='18' rx='9' fill='%s'/>" % track \
		+ "<circle cx='%d' cy='12' r='6.5' fill='%s'/></svg>" % [cx, knob]
	var tex := _rasterize(svg, 1.0)
	_cache[key] = tex
	return tex


static func dot_icon(size: int, color: Color) -> Texture2D:
	var key := "dot|%d|%s" % [size, color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var r := size * 0.5
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d'>" % [size, size] \
		+ "<circle cx='%f' cy='%f' r='%f' fill='#%s' stroke='#1a140c' stroke-width='1.5'/></svg>" % [r, r, r - 1.5, color.to_html(false)]
	var tex := _rasterize(svg, 1.0)
	_cache[key] = tex
	return tex


static func _svg(name: String, color: Color) -> String:
	var hex := "#" + color.to_html(false)
	var alpha := color.a
	var head := "<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24' opacity='%f'>" % alpha
	match name:
		"settings":
			return head + _gear(hex) + "</svg>"
		"play":
			return head + "<path d='M7.5 4.5v15l12-7.5z' fill='%s' stroke='%s' stroke-width='1.5' stroke-linejoin='round'/></svg>" % [hex, hex]
		"star":
			return head + "<path d='%s' fill='%s'/></svg>" % [_star_path(), hex]
	var body := ""
	for d in PATHS.get(name, PATHS["info"]):
		body += "<path d='%s'/>" % d
	return head + "<g fill='none' stroke='%s' stroke-width='1.8' stroke-linecap='round' stroke-linejoin='round'>%s</g></svg>" % [hex, body]


static func _gear(hex: String) -> String:
	var pts := PackedStringArray()
	var teeth := 8
	for i in teeth * 4:
		var a := TAU * float(i) / float(teeth * 4) - PI * 0.5
		var r := 9.6 if (i % 4 == 1 or i % 4 == 2) else 7.4
		pts.append("%.2f,%.2f" % [12.0 + cos(a) * r, 12.0 + sin(a) * r])
	return "<g fill='none' stroke='%s' stroke-width='1.7' stroke-linejoin='round'><polygon points='%s'/><circle cx='12' cy='12' r='3'/></g>" % [hex, " ".join(pts)]


static func _star_path() -> String:
	var d := "M"
	for i in 10:
		var a := -PI * 0.5 + TAU * float(i) / 10.0
		var r := 9.5 if i % 2 == 0 else 4.2
		d += "%.2f %.2f " % [12.0 + cos(a) * r, 12.5 + sin(a) * r]
		if i == 0:
			d += "L"
	return d + "z"


static func _rasterize(svg: String, scale: float) -> Texture2D:
	var img := Image.new()
	var err := img.load_svg_from_string(svg, scale)
	if err != OK or img.is_empty():
		img = Image.create(maxi(int(24 * scale), 1), maxi(int(24 * scale), 1), false, Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(img)
