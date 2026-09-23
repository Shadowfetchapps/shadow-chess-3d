class_name ThemeFactory
extends RefCounted

## Shadowfetch black-and-gold UI theme. One Theme instance is built lazily and
## shared by every screen; type variations cover buttons, labels, and panels.

const GOLD := Color(0.84, 0.70, 0.36)
const GOLD_BRIGHT := Color(0.95, 0.84, 0.55)
const GOLD_DIM := Color(0.56, 0.46, 0.24)
const CREAM := Color(0.96, 0.92, 0.84)
const MUTED := Color(0.68, 0.63, 0.54)
const FAINT := Color(0.46, 0.42, 0.36)
const INK := Color(0.055, 0.048, 0.040, 0.94)
const INK_SOLID := Color(0.045, 0.039, 0.032)
const CARD := Color(0.085, 0.074, 0.060, 0.96)
const DANGER := Color(0.90, 0.36, 0.30)
const SUCCESS := Color(0.52, 0.80, 0.50)
const INFO := Color(0.58, 0.72, 0.88)

static var _theme: Theme
static var _fonts: Dictionary = {}


static func make() -> Theme:
	if _theme:
		return _theme
	_theme = _build()
	return _theme


static func font(kind: String = "regular") -> Font:
	if _fonts.is_empty():
		_load_fonts()
	return _fonts.get(kind, _fonts.get("regular"))


static func accent() -> Color:
	return GOLD


static func muted() -> Color:
	return MUTED


static func cream() -> Color:
	return CREAM


static func danger() -> Color:
	return DANGER


static func success() -> Color:
	return SUCCESS


static func _load_fonts() -> void:
	var paths := {
		"regular": "res://assets/fonts/Inter-Regular.ttf",
		"medium": "res://assets/fonts/Inter-Medium.ttf",
		"semibold": "res://assets/fonts/Inter-SemiBold.ttf",
		"display": "res://assets/fonts/InterDisplay-SemiBold.ttf",
		"display_medium": "res://assets/fonts/InterDisplay-Medium.ttf",
		"display_regular": "res://assets/fonts/InterDisplay-Regular.ttf",
	}
	for key in paths:
		var f: Font = load(paths[key]) if ResourceLoader.exists(paths[key]) else null
		if f == null:
			f = ThemeDB.fallback_font
		_fonts[key] = f
	# Tabular figures keep clocks and move numbers from jittering.
	var ts := TextServerManager.get_primary_interface()
	var tnum := FontVariation.new()
	tnum.base_font = _fonts["medium"]
	var tnum_display := FontVariation.new()
	tnum_display.base_font = _fonts["display_medium"]
	if ts:
		tnum.opentype_features = {ts.name_to_tag("tnum"): 1}
		tnum_display.opentype_features = {ts.name_to_tag("tnum"): 1}
	_fonts["tabular"] = tnum
	_fonts["clock"] = tnum_display


static func box(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 10, border_w: int = 1, pad := Vector4(16, 12, 16, 12)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w if border.a > 0.0 else 0)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	s.anti_aliasing = true
	s.corner_detail = 10
	return s


static func _shadowed(s: StyleBoxFlat, size: int = 18, alpha: float = 0.45) -> StyleBoxFlat:
	s.shadow_color = Color(0, 0, 0, alpha)
	s.shadow_size = size
	s.shadow_offset = Vector2(0, 6)
	return s


static func _build() -> Theme:
	_load_fonts()
	var t := Theme.new()
	t.default_font = font("regular")
	t.default_font_size = 15

	# --- Labels -------------------------------------------------------------
	t.set_color("font_color", "Label", CREAM)
	_label_variation(t, "HeaderXL", font("display"), 54, CREAM)
	_label_variation(t, "HeaderLarge", font("display"), 30, CREAM)
	_label_variation(t, "Header", font("display"), 21, CREAM)
	_label_variation(t, "Subheader", font("semibold"), 16, CREAM)
	_label_variation(t, "Kicker", font("semibold"), 11, GOLD)
	_label_variation(t, "Caption", font("regular"), 13, MUTED)
	_label_variation(t, "Muted", font("regular"), 15, MUTED)
	_label_variation(t, "Faint", font("regular"), 12, FAINT)
	_label_variation(t, "Gold", font("medium"), 15, GOLD)
	_label_variation(t, "Clock", font("clock"), 30, CREAM)
	_label_variation(t, "Tabular", font("tabular"), 14, CREAM)

	# --- Panels -------------------------------------------------------------
	var hud := box(INK, Color(GOLD.r, GOLD.g, GOLD.b, 0.22), 14, 1, Vector4(16, 14, 16, 14))
	t.set_stylebox("panel", "PanelContainer", hud)
	t.set_stylebox("panel", "Panel", hud)
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", box(CARD, Color(1, 1, 1, 0.05), 12, 1, Vector4(14, 12, 14, 12)))
	t.set_type_variation("CardActive", "PanelContainer")
	t.set_stylebox("panel", "CardActive", box(Color(0.13, 0.105, 0.065, 0.97), Color(GOLD.r, GOLD.g, GOLD.b, 0.75), 12, 1, Vector4(14, 12, 14, 12)))
	t.set_type_variation("Modal", "PanelContainer")
	t.set_stylebox("panel", "Modal", _shadowed(box(Color(0.062, 0.054, 0.044, 0.985), Color(GOLD.r, GOLD.g, GOLD.b, 0.40), 18, 1, Vector4(28, 24, 28, 24)), 40, 0.6))
	t.set_type_variation("Pill", "PanelContainer")
	t.set_stylebox("panel", "Pill", _shadowed(box(Color(0.06, 0.052, 0.042, 0.92), Color(GOLD.r, GOLD.g, GOLD.b, 0.30), 999, 1, Vector4(18, 7, 18, 7)), 14, 0.35))
	t.set_type_variation("Toast", "PanelContainer")
	t.set_stylebox("panel", "Toast", _shadowed(box(Color(0.10, 0.085, 0.06, 0.97), Color(GOLD.r, GOLD.g, GOLD.b, 0.55), 12, 1, Vector4(16, 10, 16, 10)), 20, 0.5))
	t.set_type_variation("Inset", "PanelContainer")
	t.set_stylebox("panel", "Inset", box(Color(0.03, 0.026, 0.022, 0.75), Color(1, 1, 1, 0.04), 10, 1, Vector4(10, 8, 10, 8)))
	t.set_type_variation("Clear", "PanelContainer")
	t.set_stylebox("panel", "Clear", StyleBoxEmpty.new())

	# --- Buttons ------------------------------------------------------------
	_button_style(t, "Button",
		Color(0.11, 0.095, 0.075, 0.96), Color(GOLD.r, GOLD.g, GOLD.b, 0.32),
		Color(0.17, 0.14, 0.085, 0.98), Color(GOLD.r, GOLD.g, GOLD.b, 0.85),
		Color(0.24, 0.19, 0.10, 1.0), CREAM, GOLD_BRIGHT, 8, Vector4(16, 9, 16, 9))
	t.set_font("font", "Button", font("medium"))
	t.set_font_size("font_size", "Button", 15)

	t.set_type_variation("PrimaryButton", "Button")
	_button_style(t, "PrimaryButton",
		Color(0.80, 0.65, 0.32), Color(0.95, 0.84, 0.55, 0.9),
		Color(0.90, 0.75, 0.40), Color(1, 0.92, 0.66),
		Color(0.70, 0.56, 0.26), Color(0.09, 0.07, 0.04), Color(0.06, 0.045, 0.02), 8, Vector4(20, 10, 20, 10))
	t.set_font("font", "PrimaryButton", font("semibold"))

	t.set_type_variation("GhostButton", "Button")
	_button_style(t, "GhostButton",
		Color(0, 0, 0, 0), Color(0, 0, 0, 0),
		Color(1, 1, 1, 0.06), Color(GOLD.r, GOLD.g, GOLD.b, 0.35),
		Color(1, 1, 1, 0.10), MUTED, CREAM, 8, Vector4(12, 8, 12, 8))

	t.set_type_variation("DangerButton", "Button")
	_button_style(t, "DangerButton",
		Color(0.16, 0.06, 0.05, 0.96), Color(DANGER.r, DANGER.g, DANGER.b, 0.45),
		Color(0.26, 0.09, 0.07, 0.98), DANGER,
		Color(0.34, 0.11, 0.08), Color(1.0, 0.82, 0.78), Color(1, 0.92, 0.9), 8, Vector4(16, 9, 16, 9))

	t.set_type_variation("MainMenuButton", "Button")
	_button_style(t, "MainMenuButton",
		Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0),
		Color(0.84, 0.70, 0.36, 0.10), Color(GOLD.r, GOLD.g, GOLD.b, 0.0),
		Color(0.84, 0.70, 0.36, 0.18), CREAM, GOLD_BRIGHT, 10, Vector4(18, 11, 18, 11))
	t.set_font("font", "MainMenuButton", font("display_medium"))
	t.set_font_size("font_size", "MainMenuButton", 20)
	var menu_hover := box(Color(0.84, 0.70, 0.36, 0.10), Color(0, 0, 0, 0), 10, 0, Vector4(18, 11, 18, 11))
	menu_hover.border_width_left = 3
	menu_hover.border_color = GOLD
	t.set_stylebox("hover", "MainMenuButton", menu_hover)
	t.set_stylebox("focus", "MainMenuButton", menu_hover)

	t.set_type_variation("IconButton", "Button")
	_button_style(t, "IconButton",
		Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.07),
		Color(0.84, 0.70, 0.36, 0.14), Color(GOLD.r, GOLD.g, GOLD.b, 0.6),
		Color(0.84, 0.70, 0.36, 0.24), CREAM, GOLD_BRIGHT, 9, Vector4(9, 9, 9, 9))

	t.set_type_variation("ChipButton", "Button")
	_button_style(t, "ChipButton",
		Color(1, 1, 1, 0.035), Color(1, 1, 1, 0.08),
		Color(0.84, 0.70, 0.36, 0.10), Color(GOLD.r, GOLD.g, GOLD.b, 0.5),
		Color(0.84, 0.70, 0.36, 0.22), MUTED, CREAM, 9, Vector4(14, 9, 14, 9))
	var chip_on := box(Color(0.84, 0.70, 0.36, 0.20), GOLD, 9, 1, Vector4(14, 9, 14, 9))
	t.set_stylebox("pressed", "ChipButton", chip_on)
	t.set_stylebox("hover_pressed", "ChipButton", chip_on)
	t.set_color("font_pressed_color", "ChipButton", GOLD_BRIGHT)
	t.set_color("font_hover_pressed_color", "ChipButton", GOLD_BRIGHT)

	t.set_type_variation("MoveButton", "Button")
	_button_style(t, "MoveButton",
		Color(0, 0, 0, 0), Color(0, 0, 0, 0),
		Color(1, 1, 1, 0.06), Color(0, 0, 0, 0),
		Color(0.84, 0.70, 0.36, 0.22), CREAM, GOLD_BRIGHT, 6, Vector4(8, 3, 8, 3))
	t.set_font("font", "MoveButton", font("tabular"))
	t.set_font_size("font_size", "MoveButton", 14)
	var mv_on := box(Color(0.84, 0.70, 0.36, 0.26), Color(GOLD.r, GOLD.g, GOLD.b, 0.7), 6, 1, Vector4(8, 3, 8, 3))
	t.set_stylebox("pressed", "MoveButton", mv_on)
	t.set_stylebox("hover_pressed", "MoveButton", mv_on)
	t.set_color("font_pressed_color", "MoveButton", GOLD_BRIGHT)
	t.set_color("font_hover_pressed_color", "MoveButton", GOLD_BRIGHT)

	# --- Inputs -------------------------------------------------------------
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, _field(false))
		t.set_stylebox("focus", type, _field(true))
		t.set_stylebox("read_only", type, _field(false))
		t.set_color("font_color", type, CREAM)
		t.set_color("font_placeholder_color", type, FAINT)
		t.set_color("caret_color", type, GOLD)
		t.set_color("selection_color", type, Color(GOLD.r, GOLD.g, GOLD.b, 0.35))
		t.set_font("font", type, font("tabular"))
		t.set_font_size("font_size", type, 13)

	var opt_n := box(Color(0.10, 0.088, 0.07, 0.96), Color(1, 1, 1, 0.08), 8, 1, Vector4(12, 8, 30, 8))
	var opt_h := box(Color(0.15, 0.125, 0.08, 0.98), Color(GOLD.r, GOLD.g, GOLD.b, 0.6), 8, 1, Vector4(12, 8, 30, 8))
	t.set_stylebox("normal", "OptionButton", opt_n)
	t.set_stylebox("hover", "OptionButton", opt_h)
	t.set_stylebox("pressed", "OptionButton", opt_h)
	t.set_stylebox("focus", "OptionButton", opt_h)
	t.set_color("font_color", "OptionButton", CREAM)
	t.set_color("font_hover_color", "OptionButton", GOLD_BRIGHT)
	t.set_icon("arrow", "OptionButton", IconLibrary.get_icon("chevron_down", 14, MUTED))

	var popup := _shadowed(box(Color(0.075, 0.064, 0.052, 0.99), Color(GOLD.r, GOLD.g, GOLD.b, 0.35), 10, 1, Vector4(6, 6, 6, 6)), 20, 0.5)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", box(Color(0.84, 0.70, 0.36, 0.18), Color(0, 0, 0, 0), 6, 0, Vector4(8, 4, 8, 4)))
	t.set_color("font_color", "PopupMenu", CREAM)
	t.set_color("font_hover_color", "PopupMenu", GOLD_BRIGHT)
	t.set_constant("v_separation", "PopupMenu", 8)

	t.set_stylebox("panel", "TooltipPanel", box(Color(0.10, 0.085, 0.065, 0.98), Color(GOLD.r, GOLD.g, GOLD.b, 0.45), 8, 1, Vector4(10, 6, 10, 6)))
	t.set_color("font_color", "TooltipLabel", CREAM)
	t.set_font_size("font_size", "TooltipLabel", 13)

	# Check buttons use drawn switch icons.
	for state in ["checked", "checked_disabled"]:
		t.set_icon(state, "CheckButton", IconLibrary.toggle_icon(true))
	for state in ["unchecked", "unchecked_disabled"]:
		t.set_icon(state, "CheckButton", IconLibrary.toggle_icon(false))
	for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		t.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
	t.set_color("font_color", "CheckButton", CREAM)
	t.set_color("font_hover_color", "CheckButton", GOLD_BRIGHT)
	t.set_color("font_pressed_color", "CheckButton", CREAM)
	t.set_color("font_hover_pressed_color", "CheckButton", GOLD_BRIGHT)

	var track := box(Color(1, 1, 1, 0.10), Color(0, 0, 0, 0), 4, 0, Vector4(0, 3, 0, 3))
	var fill := box(GOLD, Color(0, 0, 0, 0), 4, 0, Vector4(0, 3, 0, 3))
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", IconLibrary.dot_icon(18, GOLD_BRIGHT))
	t.set_icon("grabber_highlight", "HSlider", IconLibrary.dot_icon(20, Color(1, 0.94, 0.72)))

	var sb_bg := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 4, 0, Vector4(2, 2, 2, 2))
	var sb_grab := box(Color(1, 1, 1, 0.14), Color(0, 0, 0, 0), 4, 0, Vector4(3, 3, 3, 3))
	var sb_grab_h := box(Color(GOLD.r, GOLD.g, GOLD.b, 0.55), Color(0, 0, 0, 0), 4, 0, Vector4(3, 3, 3, 3))
	for sb in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb, sb_bg)
		t.set_stylebox("grabber", sb, sb_grab)
		t.set_stylebox("grabber_highlight", sb, sb_grab_h)
		t.set_stylebox("grabber_pressed", sb, sb_grab_h)

	var tab_sel := box(Color(0.84, 0.70, 0.36, 0.16), Color(0, 0, 0, 0), 8, 0, Vector4(16, 8, 16, 8))
	tab_sel.border_width_bottom = 2
	tab_sel.border_color = GOLD
	t.set_stylebox("tab_selected", "TabBar", tab_sel)
	t.set_stylebox("tab_unselected", "TabBar", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 8, 0, Vector4(16, 8, 16, 8)))
	t.set_stylebox("tab_hovered", "TabBar", box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 8, 0, Vector4(16, 8, 16, 8)))
	t.set_stylebox("tab_focus", "TabBar", StyleBoxEmpty.new())
	t.set_color("font_selected_color", "TabBar", GOLD_BRIGHT)
	t.set_color("font_unselected_color", "TabBar", MUTED)
	t.set_color("font_hovered_color", "TabBar", CREAM)
	t.set_font("font", "TabBar", font("medium"))

	t.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 4, 0, Vector4(0, 0, 0, 0)))
	t.set_stylebox("fill", "ProgressBar", box(GOLD, Color(0, 0, 0, 0), 4, 0, Vector4(0, 0, 0, 0)))
	t.set_color("font_color", "ProgressBar", Color(0, 0, 0, 0))

	t.set_constant("separation", "HBoxContainer", 10)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("h_separation", "GridContainer", 10)
	t.set_constant("v_separation", "GridContainer", 10)
	t.set_stylebox("separator", "HSeparator", box(Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 0, 0, Vector4(0, 0, 0, 0)))
	t.set_constant("separation", "HSeparator", 12)
	return t


static func _label_variation(t: Theme, name: String, f: Font, size: int, color: Color) -> void:
	t.set_type_variation(name, "Label")
	t.set_font("font", name, f)
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, color)


static func _button_style(t: Theme, type: String, bg: Color, border: Color, bg_h: Color, border_h: Color, bg_p: Color, fg: Color, fg_h: Color, radius: int, pad: Vector4) -> void:
	var n := box(bg, border, radius, 1, pad)
	var h := box(bg_h, border_h, radius, 1, pad)
	var p := box(bg_p, border_h, radius, 1, pad)
	var d := box(Color(bg.r, bg.g, bg.b, bg.a * 0.5), Color(border.r, border.g, border.b, border.a * 0.4), radius, 1, pad)
	t.set_stylebox("normal", type, n)
	t.set_stylebox("hover", type, h)
	t.set_stylebox("pressed", type, p)
	t.set_stylebox("hover_pressed", type, p)
	t.set_stylebox("focus", type, h)
	t.set_stylebox("disabled", type, d)
	t.set_color("font_color", type, fg)
	t.set_color("font_hover_color", type, fg_h)
	t.set_color("font_pressed_color", type, fg_h)
	t.set_color("font_hover_pressed_color", type, fg_h)
	t.set_color("font_focus_color", type, fg_h)
	t.set_color("font_disabled_color", type, Color(fg.r, fg.g, fg.b, 0.35))
	t.set_color("icon_normal_color", type, fg)
	t.set_color("icon_hover_color", type, fg_h)
	t.set_color("icon_pressed_color", type, fg_h)
	t.set_color("icon_hover_pressed_color", type, fg_h)
	t.set_color("icon_focus_color", type, fg_h)
	t.set_color("icon_disabled_color", type, Color(fg.r, fg.g, fg.b, 0.3))
	t.set_constant("h_separation", type, 8)


static func _field(focus: bool) -> StyleBoxFlat:
	return box(Color(0.04, 0.035, 0.03, 0.95), GOLD if focus else Color(1, 1, 1, 0.08), 8, 1, Vector4(10, 8, 10, 8))
