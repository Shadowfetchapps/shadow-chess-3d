extends Node

## Player profile: results against each Shadow level, an Elo-style rating
## against Shadow's nominal strengths, puzzle progress, and lifetime counters.
## Stored as JSON under the XDG data dir; unreadable files are moved aside.

signal profile_changed

const FILE := "profile.json"
const LEVEL_ELO := {
	"beginner": 600, "casual": 1000, "club": 1400,
	"advanced": 1700, "expert": 1900, "master": 2100,
}

var rating: float = 1200.0
var rated_games: int = 0
var peak_rating: float = 1200.0
var levels: Dictionary = {}
var local_games: int = 0
var puzzles_solved: Array = []
var puzzle_attempts: int = 0
var hints_used: int = 0
var moves_played: int = 0
var streak: int = 0
var best_streak: int = 0
var last_played: String = ""


func _ready() -> void:
	load_profile()


func path() -> String:
	return SettingsStore.data_dir().path_join(FILE)


func load_profile() -> void:
	if not FileAccess.file_exists(path()):
		return
	var f := FileAccess.open(path(), FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		DirAccess.rename_absolute(path(), path() + ".corrupt")
		return
	var d: Dictionary = parsed
	rating = float(d.get("rating", rating))
	rated_games = int(d.get("rated_games", 0))
	peak_rating = float(d.get("peak_rating", rating))
	var lv: Variant = d.get("levels", {})
	levels = lv if lv is Dictionary else {}
	local_games = int(d.get("local_games", 0))
	var ps: Variant = d.get("puzzles_solved", [])
	puzzles_solved = ps if ps is Array else []
	puzzle_attempts = int(d.get("puzzle_attempts", 0))
	hints_used = int(d.get("hints_used", 0))
	moves_played = int(d.get("moves_played", 0))
	streak = int(d.get("streak", 0))
	best_streak = int(d.get("best_streak", 0))
	last_played = str(d.get("last_played", ""))


func save_profile() -> void:
	SettingsStore.ensure_dirs()
	var f := FileAccess.open(path(), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"version": 1,
		"rating": rating,
		"rated_games": rated_games,
		"peak_rating": peak_rating,
		"levels": levels,
		"local_games": local_games,
		"puzzles_solved": puzzles_solved,
		"puzzle_attempts": puzzle_attempts,
		"hints_used": hints_used,
		"moves_played": moves_played,
		"streak": streak,
		"best_streak": best_streak,
		"last_played": last_played,
	}, "\t"))
	f.close()
	profile_changed.emit()


## score: 1.0 win, 0.5 draw, 0.0 loss (from the player's point of view).
func record_ai_result(level: String, score: float) -> float:
	var rec: Dictionary = levels.get(level, {"w": 0, "d": 0, "l": 0})
	if score >= 1.0:
		rec["w"] = int(rec["w"]) + 1
		streak += 1
		best_streak = maxi(best_streak, streak)
	elif score <= 0.0:
		rec["l"] = int(rec["l"]) + 1
		streak = 0
	else:
		rec["d"] = int(rec["d"]) + 1
	levels[level] = rec
	var opp := float(LEVEL_ELO.get(level, 1400))
	var expected := 1.0 / (1.0 + pow(10.0, (opp - rating) / 400.0))
	var k := 40.0 if rated_games < 20 else 24.0
	var delta := k * (score - expected)
	rating = clampf(rating + delta, 100.0, 3000.0)
	peak_rating = maxf(peak_rating, rating)
	rated_games += 1
	_touch()
	save_profile()
	return delta


func record_local_game() -> void:
	local_games += 1
	_touch()
	save_profile()


func record_moves(n: int) -> void:
	moves_played += n


func record_hint() -> void:
	hints_used += 1


func mark_puzzle(id: String, solved: bool) -> void:
	puzzle_attempts += 1
	if solved and not id in puzzles_solved:
		puzzles_solved.append(id)
	_touch()
	save_profile()


func is_puzzle_solved(id: String) -> bool:
	return id in puzzles_solved


func totals() -> Dictionary:
	var w := 0
	var d := 0
	var l := 0
	for k in levels:
		w += int(levels[k].get("w", 0))
		d += int(levels[k].get("d", 0))
		l += int(levels[k].get("l", 0))
	return {"w": w, "d": d, "l": l, "games": w + d + l}


func rating_label() -> String:
	var r := int(round(rating))
	return "%d%s" % [r, "?" if rated_games < 10 else ""]


func _touch() -> void:
	last_played = Time.get_datetime_string_from_system()
