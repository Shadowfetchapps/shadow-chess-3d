class_name StatsPanel
extends Modal

## Rating against Shadow, record per level, and lifetime counters.


func _init() -> void:
	super("Statistics", 620)
	var top := UIKit.hbox(24)
	top.add_child(_big("RATING", ProfileStore.rating_label(), "Provisional until 10 games" if ProfileStore.rated_games < 10 else "Peak %d" % int(round(ProfileStore.peak_rating))))
	var t := ProfileStore.totals()
	top.add_child(_big("GAMES VS SHADOW", str(t["games"]), "%d W  ·  %d D  ·  %d L" % [t["w"], t["d"], t["l"]]))
	top.add_child(_big("PUZZLES", str(ProfileStore.puzzles_solved.size()), "solved"))
	body.add_child(top)
	body.add_child(UIKit.separator())
	body.add_child(UIKit.label("RECORD BY LEVEL", "Kicker"))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 6)
	for h in ["Level", "Won", "Drawn", "Lost", "Score"]:
		grid.add_child(UIKit.label(h, "Caption"))
	for l in ChessAI.levels():
		var id := str(l.get("id"))
		var rec: Dictionary = ProfileStore.levels.get(id, {})
		var w := int(rec.get("w", 0))
		var d := int(rec.get("d", 0))
		var lo := int(rec.get("l", 0))
		var n := w + d + lo
		grid.add_child(UIKit.label("%s  %s" % [l.get("name"), l.get("elo", "")]))
		grid.add_child(UIKit.label(str(w), "Tabular"))
		grid.add_child(UIKit.label(str(d), "Tabular"))
		grid.add_child(UIKit.label(str(lo), "Tabular"))
		grid.add_child(UIKit.label("—" if n == 0 else "%d%%" % int(round((w + d * 0.5) * 100.0 / n)), "Gold"))
	body.add_child(grid)
	body.add_child(UIKit.separator())
	var life := UIKit.label("Moves played %d   ·   Hints used %d   ·   Best win streak %d   ·   Local games %d" % [ProfileStore.moves_played, ProfileStore.hints_used, ProfileStore.best_streak, ProfileStore.local_games], "Caption", true)
	body.add_child(life)
	add_footer_button(UIKit.button("Close", close, "PrimaryButton"))


func _big(kicker: String, value: String, caption: String) -> VBoxContainer:
	var v := UIKit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UIKit.label(kicker, "Kicker"))
	var l := UIKit.label(value, "HeaderLarge")
	l.add_theme_font_override("font", ThemeFactory.font("clock"))
	v.add_child(l)
	v.add_child(UIKit.label(caption, "Caption"))
	return v
