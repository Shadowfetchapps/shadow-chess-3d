class_name EvalBar
extends Control

## Vertical evaluation bar. White's share grows from the bottom when White is
## at the bottom of the screen; flips with the board.

var white_bottom := true
var _shown := 0.5
var _goal := 0.5
var _text := "0.0"
var _mate := false


func _init() -> void:
	custom_minimum_size = Vector2(28, 200)
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = "Shadow's evaluation of the position"


func set_eval(white_cp: int, mate_white: int) -> void:
	_mate = mate_white != 0
	if _mate:
		_goal = 1.0 if mate_white > 0 else 0.0
		_text = "M%d" % absi(mate_white)
	elif absi(white_cp) >= 9000:
		_goal = 1.0 if white_cp > 0 else 0.0
		_text = "1-0" if white_cp > 0 else "0-1"
	else:
		_goal = 1.0 / (1.0 + exp(-float(white_cp) / 260.0))
		var pawns := absf(white_cp / 100.0)
		_text = "%s%.1f" % ["+" if white_cp > 0 else ("−" if white_cp < 0 else ""), pawns]
	tooltip_text = "Evaluation %s (%s)" % [_text, "White better" if _goal > 0.5 else ("Black better" if _goal < 0.5 else "equal")]


func _process(delta: float) -> void:
	var k := 1.0 - exp(-delta * 6.0)
	var prev := _shown
	_shown = lerpf(_shown, _goal, k)
	if absf(prev - _shown) > 0.0005:
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var radius := 5
	var dark := StyleBoxFlat.new()
	dark.bg_color = Color(0.07, 0.065, 0.06)
	dark.border_color = Color(ThemeFactory.GOLD.r, ThemeFactory.GOLD.g, ThemeFactory.GOLD.b, 0.35)
	dark.set_border_width_all(1)
	dark.set_corner_radius_all(radius)
	draw_style_box(dark, r)
	var h := size.y * _shown
	var white_rect := Rect2(0, size.y - h, size.x, h) if white_bottom else Rect2(0, 0, size.x, h)
	var light := StyleBoxFlat.new()
	light.bg_color = Color(0.93, 0.90, 0.82)
	light.set_corner_radius_all(radius)
	if white_bottom:
		light.corner_radius_top_left = 2 if _shown < 0.98 else radius
		light.corner_radius_top_right = light.corner_radius_top_left
	else:
		light.corner_radius_bottom_left = 2 if _shown < 0.98 else radius
		light.corner_radius_bottom_right = light.corner_radius_bottom_left
	if h > 1.0:
		draw_style_box(light, white_rect.grow(-1))
	draw_line(Vector2(1, size.y * 0.5), Vector2(size.x - 1, size.y * 0.5), Color(ThemeFactory.GOLD.r, ThemeFactory.GOLD.g, ThemeFactory.GOLD.b, 0.6), 1.0)
	var font := ThemeFactory.font("tabular")
	var fs := 10
	var white_ahead := _goal >= 0.5
	var txt_col := Color(0.1, 0.09, 0.07) if white_ahead else ThemeFactory.CREAM
	var y := size.y - 6.0 if white_ahead == white_bottom else 14.0
	var w := font.get_string_size(_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	draw_string(font, Vector2((size.x - w) * 0.5, y), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, txt_col)
