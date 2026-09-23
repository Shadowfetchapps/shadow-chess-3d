class_name ToastLayer
extends Control

## Stacked, self-dismissing notifications at the top centre of the screen.

const KINDS := {
	"info": ["info", ThemeFactory.GOLD],
	"success": ["check", ThemeFactory.SUCCESS],
	"error": ["close", ThemeFactory.DANGER],
	"hint": ["hint", Color(0.62, 0.86, 1.0)],
}

var _stack: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack = VBoxContainer.new()
	_stack.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_stack.offset_top = 74
	_stack.alignment = BoxContainer.ALIGNMENT_BEGIN
	_stack.add_theme_constant_override("separation", 8)
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stack)


func show_toast(text: String, kind: String = "info", seconds: float = 2.6) -> void:
	var spec: Array = KINDS.get(kind, KINDS["info"])
	var card := PanelContainer.new()
	card.theme_type_variation = "Toast"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UIKit.hbox(10)
	row.add_child(UIKit.icon_rect(spec[0], 16, spec[1]))
	var l := UIKit.label(text)
	l.add_theme_font_size_override("font_size", 14)
	row.add_child(l)
	card.add_child(row)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_stack.add_child(card)
	while _stack.get_child_count() > 3:
		_stack.get_child(0).queue_free()
	card.modulate.a = 0.0
	var tw := card.create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.18)
	tw.tween_interval(seconds)
	tw.tween_property(card, "modulate:a", 0.0, 0.35)
	tw.tween_callback(card.queue_free)
