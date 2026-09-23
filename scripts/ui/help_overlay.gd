class_name HelpOverlay
extends Modal

## Controls reference plus a short rules primer.

const SHORTCUTS := [
	["Left click / drag", "Select and move a piece"],
	["Right drag", "Orbit the camera"],
	["Middle drag", "Pan"],
	["Wheel", "Zoom"],
	["Q / E", "Orbit left / right"],
	["C", "Reset camera"],
	["T", "Top-down view"],
	["F", "Flip board"],
	["H", "Hint"],
	["Ctrl+Z / Ctrl+Y", "Take back / replay"],
	["← / →", "Step through the game"],
	["Home / End", "First / latest position"],
	["F11", "Fullscreen"],
	["Esc", "Pause menu"],
	["F1", "This help"],
]


func _init() -> void:
	super("Controls and rules", 640, true, 470)
	body.add_child(UIKit.label("CONTROLS", "Kicker"))
	body.add_child(shortcut_grid())
	body.add_child(UIKit.gap(6))
	body.add_child(UIKit.label("RULES AT A GLANCE", "Kicker"))
	for line in [
		"Standard FIDE rules: castling, en passant, and promotion to any piece.",
		"Draws are automatic on stalemate, threefold repetition, the fifty-move rule, and insufficient material.",
		"On time, a flag loses — unless the opponent has no way to checkmate, which is a draw.",
		"Takebacks rewind to your last move. Shadow never takes back its own moves on its own.",
		"Click any move in the scoresheet to review it; play resumes from the live position.",
	]:
		var row := UIKit.hbox(10)
		row.add_child(UIKit.icon_rect("check", 14))
		row.add_child(UIKit.label(line, "Muted", true))
		row.get_child(1).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(row)
	add_footer_button(UIKit.button("Got it", close, "PrimaryButton"))


static func shortcut_grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 22)
	g.add_theme_constant_override("v_separation", 8)
	for s in SHORTCUTS:
		var key := PanelContainer.new()
		key.theme_type_variation = "Inset"
		var kl := UIKit.label(s[0], "Tabular")
		kl.add_theme_color_override("font_color", ThemeFactory.GOLD_BRIGHT)
		key.add_child(kl)
		key.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var wrap := UIKit.hbox(0)
		wrap.custom_minimum_size.x = 170
		wrap.add_child(key)
		g.add_child(wrap)
		var d := UIKit.label(s[1], "Muted")
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		g.add_child(d)
	return g
