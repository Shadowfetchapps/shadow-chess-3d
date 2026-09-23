class_name Modal
extends Control

## Centered dialog over a frosted (blurred, tinted) copy of the screen.
## Esc or a click on the backdrop closes it when `dismissible`.

signal closed

const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float lod : hint_range(0.0, 6.0) = 3.0;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform vec4 tint : source_color = vec4(0.02, 0.017, 0.013, 0.58);
void fragment() {
	vec3 base = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	vec3 blurred = textureLod(screen_tex, SCREEN_UV, lod * amount).rgb;
	vec3 c = mix(base, blurred, amount);
	c = mix(c, tint.rgb, tint.a * amount);
	vec2 v = SCREEN_UV - 0.5;
	c *= 1.0 - dot(v, v) * 0.6 * amount;
	COLOR = vec4(c, 1.0);
}
"""

static var _shader: Shader

var dismissible := true
var panel: PanelContainer
var body: VBoxContainer
var footer: HBoxContainer
var title_label: Label
var subtitle_label: Label
var _backdrop: ColorRect
var _mat: ShaderMaterial
var _tween: Tween
var _scroll: ScrollContainer


func _init(title: String = "", width: int = 520, scroll: bool = false, max_height: int = 0) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	if _shader == null:
		_shader = Shader.new()
		_shader.code = BLUR_SHADER
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_backdrop.material = _mat
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_input)
	add_child(_backdrop)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = PanelContainer.new()
	panel.theme_type_variation = "Modal"
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 16)
	panel.add_child(outer)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label = UIKit.label(title, "Header")
	titles.add_child(title_label)
	subtitle_label = UIKit.label("", "Caption", true)
	subtitle_label.visible = false
	titles.add_child(subtitle_label)
	head.add_child(titles)
	var close_btn := UIKit.icon_button("close", "Close (Esc)", func(): close(), 16)
	close_btn.theme_type_variation = "GhostButton"
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_btn.name = "CloseButton"
	head.add_child(close_btn)
	head.visible = title != ""
	head.name = "Head"
	outer.add_child(head)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	if scroll:
		_scroll = ScrollContainer.new()
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_scroll.custom_minimum_size = Vector2(0, max_height if max_height > 0 else 520)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_scroll.add_child(body)
		outer.add_child(_scroll)
	else:
		outer.add_child(body)
	footer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.visible = false
	outer.add_child(footer)


func set_subtitle(text: String) -> void:
	subtitle_label.text = text
	subtitle_label.visible = text != ""


func set_dismissible(on: bool) -> void:
	dismissible = on
	var btn := panel.find_child("CloseButton", true, false)
	if btn:
		(btn as Control).visible = on


func add_footer_button(b: Button) -> Button:
	footer.visible = true
	footer.add_child(b)
	return b


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	visible = true
	move_to_front()
	AudioManager.play("ui_open")
	if _tween:
		_tween.kill()
	panel.pivot_offset = panel.size * 0.5
	if SettingsStore.reduce_motion:
		_mat.set_shader_parameter("amount", 1.0)
		panel.modulate.a = 1.0
		panel.scale = Vector2.ONE
	else:
		_mat.set_shader_parameter("amount", 0.0)
		panel.modulate.a = 0.0
		panel.scale = Vector2(0.97, 0.97)
		_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_method(func(v: float): _mat.set_shader_parameter("amount", v), 0.0, 1.0, 0.22)
		_tween.tween_property(panel, "modulate:a", 1.0, 0.2)
		_tween.tween_property(panel, "scale", Vector2.ONE, 0.26)
	call_deferred("_focus_first")


func close() -> void:
	if not visible:
		return
	AudioManager.play("ui_close")
	if _tween:
		_tween.kill()
	if SettingsStore.reduce_motion:
		visible = false
		closed.emit()
		return
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_method(func(v: float): _mat.set_shader_parameter("amount", v), 1.0, 0.0, 0.16)
	_tween.tween_property(panel, "modulate:a", 0.0, 0.14)
	_tween.tween_property(panel, "scale", Vector2(0.98, 0.98), 0.16)
	_tween.chain().tween_callback(func():
		visible = false
		closed.emit()
	)


func _focus_first() -> void:
	var b := _first_focusable(body)
	if b:
		b.grab_focus()


func _first_focusable(n: Node) -> Control:
	for c in n.get_children():
		if c is BaseButton and (c as Control).visible and not (c as BaseButton).disabled and (c as Control).focus_mode != Control.FOCUS_NONE:
			return c
		var inner := _first_focusable(c)
		if inner:
			return inner
	return null


func _on_backdrop_input(event: InputEvent) -> void:
	if dismissible and event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		close()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_game"):
		get_viewport().set_input_as_handled()
		if dismissible:
			close()
