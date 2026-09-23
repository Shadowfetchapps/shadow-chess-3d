class_name EndCard
extends Modal

## Result card shown when a game ends: headline, reason, rating change, and
## the next actions (rematch, review, export, menu).

signal rematch_requested(swap: bool)
signal review_requested
signal export_requested
signal menu_requested

var _icon: TextureRect
var _headline: Label
var _detail: Label
var _rating: Label
var _stats: Label
var _swap: Button


func _init() -> void:
	super("", 500)
	var v := UIKit.vbox(10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(v)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(56, 56)
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(_icon)
	_headline = UIKit.label("", "HeaderLarge")
	_headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_headline)
	_detail = UIKit.label("", "Muted", true)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_detail)
	_rating = UIKit.label("", "Gold")
	_rating.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_rating)
	_stats = UIKit.label("", "Caption")
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_stats)
	v.add_child(UIKit.gap(6))
	var row := UIKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UIKit.button("Rematch", func(): close(); rematch_requested.emit(false), "PrimaryButton", "restart"))
	_swap = UIKit.button("Swap colours", func(): close(); rematch_requested.emit(true), "", "swap")
	row.add_child(_swap)
	v.add_child(row)
	var row2 := UIKit.hbox(10)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_child(UIKit.button("Review game", func(): close(); review_requested.emit(), "GhostButton", "eye"))
	row2.add_child(UIKit.button("Save PGN", func(): export_requested.emit(), "GhostButton", "download"))
	row2.add_child(UIKit.button("Main menu", func(): close(); menu_requested.emit(), "GhostButton", "menu"))
	v.add_child(row2)


func present(info: Dictionary, is_ai: bool) -> void:
	var score := float(info.get("player_score", -1.0))
	var headline := "Game over"
	var icon := "flag"
	var color := ThemeFactory.GOLD
	if is_ai:
		if score >= 1.0:
			headline = "Victory"
			icon = "trophy"
		elif score <= 0.0:
			headline = "Shadow wins"
			icon = "moon"
			color = ThemeFactory.MUTED
		else:
			headline = "Draw"
			icon = "draw"
	else:
		var winner := int(info.get("winner", -1))
		if winner < 0:
			headline = "Draw"
			icon = "draw"
		else:
			headline = "%s wins" % ChessTypes.side_name(winner)
			icon = "trophy"
	_icon.texture = IconLibrary.get_icon(icon, 44, color)
	_headline.text = headline
	_detail.text = str(info.get("text", ""))
	var delta := float(info.get("rating_delta", 0.0))
	_rating.visible = is_ai and absf(delta) > 0.01
	_rating.text = "Rating %s  (%s%d)" % [ProfileStore.rating_label(), "+" if delta >= 0 else "−", int(round(absf(delta)))]
	var n := int(info.get("moves", 0))
	_stats.text = "%d move%s  ·  %s" % [n, "" if n == 1 else "s", str(info.get("reason", ""))]
	_swap.visible = is_ai
	open()
