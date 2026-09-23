class_name PlayerCard
extends PanelContainer

## Player row in the side panel: avatar, name, subtitle, clock, captured
## pieces (rendered icons) with material balance, and a thinking indicator.

var side: int = ChessTypes.WHITE
var _avatar: PanelContainer
var _avatar_label: Label
var _avatar_icon: TextureRect
var _name: Label
var _sub: Label
var _clock: Label
var _clock_box: PanelContainer
var _captured: HBoxContainer
var _diff: Label
var _dots: Label
var _active := false
var _low := false
var _dots_phase := 0.0
var _thinking := false


func _init() -> void:
	theme_type_variation = "Card"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UIKit.vbox(8)
	add_child(v)
	var top := UIKit.hbox(12)
	v.add_child(top)
	_avatar = PanelContainer.new()
	_avatar.custom_minimum_size = Vector2(40, 40)
	var av_style := ThemeFactory.box(Color(0.16, 0.13, 0.08), Color(ThemeFactory.GOLD.r, ThemeFactory.GOLD.g, ThemeFactory.GOLD.b, 0.5), 20, 1, Vector4(0, 0, 0, 0))
	_avatar.add_theme_stylebox_override("panel", av_style)
	_avatar_label = UIKit.label("", "Subheader")
	_avatar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_avatar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_avatar.add_child(_avatar_label)
	_avatar_icon = TextureRect.new()
	_avatar_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_avatar_icon.visible = false
	_avatar.add_child(_avatar_icon)
	top.add_child(_avatar)
	var names := UIKit.vbox(1)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_row := UIKit.hbox(6)
	name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name = UIKit.label("", "Subheader")
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name)
	_dots = UIKit.label("", "Gold")
	name_row.add_child(_dots)
	names.add_child(name_row)
	_sub = UIKit.label("", "Caption")
	names.add_child(_sub)
	top.add_child(names)
	_clock_box = PanelContainer.new()
	_clock_box.theme_type_variation = "Inset"
	_clock = UIKit.label("—", "Clock")
	_clock.add_theme_font_size_override("font_size", 26)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock.custom_minimum_size.x = 92
	_clock_box.add_child(_clock)
	top.add_child(_clock_box)
	var cap_row := UIKit.hbox(4)
	cap_row.custom_minimum_size.y = 24
	_captured = UIKit.hbox(-6)
	cap_row.add_child(_captured)
	_diff = UIKit.label("", "Caption")
	_diff.add_theme_color_override("font_color", ThemeFactory.GOLD)
	cap_row.add_child(_diff)
	v.add_child(cap_row)


func setup(p_side: int, display_name: String, subtitle: String, is_ai: bool) -> void:
	side = p_side
	_name.text = display_name
	_sub.text = subtitle
	var disc := Color(0.93, 0.89, 0.80) if side == ChessTypes.WHITE else Color(0.08, 0.07, 0.07)
	var ring := ThemeFactory.GOLD
	var st := ThemeFactory.box(disc, Color(ring.r, ring.g, ring.b, 0.8), 20, 2, Vector4(0, 0, 0, 0))
	_avatar.add_theme_stylebox_override("panel", st)
	if is_ai:
		_avatar_icon.texture = IconLibrary.get_icon("moon", 20, ThemeFactory.GOLD if side == ChessTypes.BLACK else Color(0.25, 0.2, 0.12))
		_avatar_icon.visible = true
		_avatar_label.visible = false
	else:
		_avatar_icon.visible = false
		_avatar_label.visible = true
		_avatar_label.text = display_name.left(1).to_upper()
		_avatar_label.add_theme_color_override("font_color", Color(0.12, 0.1, 0.07) if side == ChessTypes.WHITE else ThemeFactory.CREAM)


func set_clock(seconds: float, enabled: bool) -> void:
	_clock_box.visible = enabled
	if enabled:
		_clock.text = UIKit.format_clock(seconds)
		var low := seconds <= 20.0
		if low != _low:
			_low = low
		_clock.add_theme_color_override("font_color", ThemeFactory.DANGER if low and _active else (ThemeFactory.GOLD_BRIGHT if _active else ThemeFactory.MUTED))


func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	theme_type_variation = "CardActive" if on else "Card"


func set_thinking(on: bool) -> void:
	_thinking = on
	if not on:
		_dots.text = ""


func set_captured(types: Array, diff: int) -> void:
	for c in _captured.get_children():
		c.queue_free()
	var opp := ChessTypes.opp(side)
	for t in types:
		var tex := PieceIcons.get_icon(int(t), opp)
		if tex:
			var r := TextureRect.new()
			r.texture = tex
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			r.custom_minimum_size = Vector2(30, 30)
			# Lift dark pieces so they read against the dark card.
			if opp == ChessTypes.BLACK:
				r.modulate = Color(2.2, 2.0, 1.8)
			_captured.add_child(r)
		else:
			var l := UIKit.label(ChessTypes.PIECE_LETTERS[int(t)], "Caption")
			_captured.add_child(l)
	_diff.text = "+%d" % diff if diff > 0 else ""


func set_subtitle(text: String) -> void:
	_sub.text = text


func _process(delta: float) -> void:
	if not _thinking:
		return
	_dots_phase += delta * 2.5
	var n := int(_dots_phase) % 4
	_dots.text = ".".repeat(n)
