class_name ThemeFactory
extends RefCounted


static func make() -> Theme:
	var theme := Theme.new()
	var regular: FontFile = load("res://assets/fonts/Inter-Regular.ttf")
	var medium: FontFile = load("res://assets/fonts/Inter-Medium.ttf")
	var display: FontFile = load("res://assets/fonts/InterDisplay-SemiBold.ttf")
	if regular:
		theme.default_font = regular
	theme.default_font_size = 16
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.12, 0.15, 0.19, 0.94)
	btn.border_color = Color(0.30, 0.55, 0.62, 0.55)
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(8)
	btn.content_margin_left = 18
	btn.content_margin_right = 18
	btn.content_margin_top = 10
	btn.content_margin_bottom = 10
	var btn_h := btn.duplicate()
	btn_h.bg_color = Color(0.16, 0.22, 0.28, 0.96)
	btn_h.border_color = Color(0.45, 0.85, 0.95, 0.9)
	var btn_p := btn.duplicate()
	btn_p.bg_color = Color(0.10, 0.28, 0.34, 0.96)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.07, 0.09, 0.12, 0.92)
	panel.border_color = Color(0.22, 0.32, 0.38, 0.5)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(12)
	panel.content_margin_left = 16
	panel.content_margin_right = 16
	panel.content_margin_top = 14
	panel.content_margin_bottom = 14
	var empty := StyleBoxEmpty.new()
	theme.set_stylebox("normal", "Button", btn)
	theme.set_stylebox("hover", "Button", btn_h)
	theme.set_stylebox("pressed", "Button", btn_p)
	theme.set_stylebox("focus", "Button", btn_h)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_color("font_color", "Button", Color(0.86, 0.91, 0.94))
	theme.set_color("font_hover_color", "Button", Color(0.94, 0.98, 1.0))
	theme.set_color("font_color", "Label", Color(0.82, 0.88, 0.92))
	if medium:
		theme.set_font("font", "Button", medium)
	if display:
		theme.set_font("font", "Header", display)
	theme.set_stylebox("normal", "LineEdit", _field())
	theme.set_stylebox("focus", "LineEdit", _field(true))
	theme.set_stylebox("grabber_area", "HSlider", empty)
	return theme


static func _field(focus := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.10, 0.13, 0.95)
	s.border_color = Color(0.40, 0.80, 0.90, 0.8) if focus else Color(0.25, 0.35, 0.40, 0.6)
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


static func accent() -> Color:
	return Color(0.42, 0.84, 0.94)


static func muted() -> Color:
	return Color(0.62, 0.70, 0.76)
