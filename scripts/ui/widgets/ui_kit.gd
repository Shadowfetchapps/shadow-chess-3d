class_name UIKit
extends RefCounted

## Small constructors so every screen builds controls the same way: themed
## variations, hover/click sounds, icons, and tooltips.

const ICON_SIZE := 18


static func button(text: String, cb: Callable, variation: String = "", icon_name: String = "", tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	if icon_name != "":
		b.icon = IconLibrary.get_icon(icon_name, ICON_SIZE)
		b.add_theme_constant_override("icon_max_width", ICON_SIZE)
	if tooltip != "":
		b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_wire(b, cb)
	return b


static func icon_button(icon_name: String, tooltip: String, cb: Callable, size: int = 20) -> Button:
	var b := Button.new()
	b.theme_type_variation = "IconButton"
	b.icon = IconLibrary.get_icon(icon_name, size)
	b.add_theme_constant_override("icon_max_width", size)
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(size + 20, size + 20)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_wire(b, cb)
	return b


static func _wire(b: Button, cb: Callable) -> void:
	b.mouse_entered.connect(func():
		if not b.disabled:
			AudioManager.play("ui_hover")
	)
	if cb.is_valid():
		b.pressed.connect(func():
			AudioManager.play("ui_click")
			cb.call()
		)


static func label(text: String, variation: String = "", wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func hbox(sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func spacer(expand_h: bool = true) -> Control:
	var c := Control.new()
	if expand_h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func gap(px: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(px, px)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func separator() -> HSeparator:
	return HSeparator.new()


static func icon_rect(icon_name: String, size: int = 18, color: Color = ThemeFactory.GOLD) -> TextureRect:
	var t := TextureRect.new()
	t.texture = IconLibrary.get_icon(icon_name, size, color)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## A row of mutually exclusive chips. `options` = [[label, value], ...].
static func chips(options: Array, current: Variant, on_change: Callable, min_width: int = 0) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	var group := ButtonGroup.new()
	for opt in options:
		var b := Button.new()
		b.text = str(opt[0])
		b.theme_type_variation = "ChipButton"
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = opt[1] == current
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if min_width > 0:
			b.custom_minimum_size.x = min_width
		if opt.size() > 2:
			b.tooltip_text = str(opt[2])
		var value: Variant = opt[1]
		b.mouse_entered.connect(func(): AudioManager.play("ui_hover"))
		b.toggled.connect(func(on: bool):
			if on:
				AudioManager.play("ui_click")
				on_change.call(value)
		)
		row.add_child(b)
	return row


static func option(labels: Array, values: Array, current: Variant, on_change: Callable) -> OptionButton:
	var o := OptionButton.new()
	for i in labels.size():
		o.add_item(str(labels[i]))
		o.set_item_metadata(i, values[i])
		if values[i] == current:
			o.select(i)
	o.item_selected.connect(func(i: int):
		AudioManager.play("ui_click")
		on_change.call(o.get_item_metadata(i))
	)
	return o


static func toggle(text: String, on: bool, on_change: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	c.toggled.connect(func(v: bool):
		AudioManager.play("ui_click")
		on_change.call(v)
	)
	return c


static func slider(min_v: float, max_v: float, step: float, value: float, on_change: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(180, 24)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(v: float): on_change.call(v))
	return s


## Label + control on one line, label column fixed width.
static func row(text: String, control: Control, label_width: int = 190, help: String = "") -> HBoxContainer:
	var h := hbox(14)
	var l := label(text)
	l.custom_minimum_size.x = label_width
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if help != "":
		l.tooltip_text = help
		l.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	return h


static func fade_in(node: CanvasItem, dur: float = 0.25, delay: float = 0.0) -> void:
	node.modulate.a = 0.0
	var tw := node.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(node, "modulate:a", 1.0, dur if not SettingsStore.reduce_motion else 0.01)


static func slide_in(node: Control, offset: Vector2, dur: float = 0.35, delay: float = 0.0) -> void:
	if SettingsStore.reduce_motion:
		return
	var goal := node.position
	node.position = goal + offset
	node.modulate.a = 0.0
	var tw := node.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "position", goal, dur).set_delay(delay)
	tw.tween_property(node, "modulate:a", 1.0, dur * 0.8).set_delay(delay)


static func format_clock(t: float) -> String:
	var tenths := t < 10.0 and t > 0.0
	if tenths:
		return "0:%04.1f" % maxf(t, 0.0)
	var s := int(ceil(maxf(t, 0.0)))
	if s >= 3600:
		return "%d:%02d:%02d" % [int(s / 3600.0), int(s / 60.0) % 60, s % 60]
	return "%d:%02d" % [int(s / 60.0), s % 60]
