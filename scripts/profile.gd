extends Node
# The player's saved profile: leos, owned pens, pen colors, the lobby setup and the level climb.
# Registered as the `Profile` autoload so the lobby and the game share it.

const PenData := preload("res://scripts/pen_data.gd")
const Levels := preload("res://scripts/levels.gd")
const SAVE_PATH := "user://leos.cfg"
const START_LEOS := 40
const MAX_SEATS := 4
# Each seat starts in its own color (palette indices; -1 = the pen's own color), matching the
# seat colors on the HUD: teal, blue, orange, purple.
const DEFAULT_SEAT_COLORS := [-1, 1, 3, 6]

var pens: Array[Dictionary] = []
var leos := 0
var owned_ids: Array[String] = []
var pen_colors: Dictionary = {}
var player_count := 2
# One entry per seat: {"human": bool, "pen": String, "color": int}. Seat 0 is always the person
# holding the profile. Each seat has its own pen color (-1 = the pen's own), so two players on the
# same pen can still tell their pens apart.
var seats: Array[Dictionary] = []
# The level climb against the computer (see levels.gd). `recent` holds the last few results,
# oldest first; `crowns` counts wins over the level 50 boss.
var level := 1
var xp := 0
var matches := 0
var wins := 0
var streak := 0
var best_streak := 0
var recent: Array[bool] = []
var crowns := 0


func _ready() -> void:
	pens = PenData.all()
	load_profile()


func load_profile() -> void:
	var config := ConfigFile.new()
	owned_ids.clear()
	pen_colors.clear()
	seats.clear()
	var humans: Array = [true, false, false, false]
	var seat_pens: Array = ["classic", "classic", "classic", "classic"]
	var seat_colors: Array = []
	if config.load(SAVE_PATH) == OK:
		leos = int(config.get_value("wallet", "leos", START_LEOS))
		for id in config.get_value("pens", "owned", ["classic"]):
			owned_ids.append(str(id))
		var colors: Dictionary = config.get_value("pens", "colors", {})
		for id in colors:
			pen_colors[str(id)] = int(colors[id])
		player_count = clampi(int(config.get_value("lobby", "count", 2)), 2, MAX_SEATS)
		humans = config.get_value("lobby", "human", humans)
		seat_pens = config.get_value("lobby", "pens", [str(config.get_value("pens", "equipped", "classic")), "classic", "classic", "classic"])
		seat_colors = config.get_value("lobby", "colors", [])
		level = clampi(int(config.get_value("levels", "level", 1)), 1, Levels.MAX_LEVEL)
		xp = maxi(0, int(config.get_value("levels", "xp", 0)))
		matches = maxi(0, int(config.get_value("levels", "matches", 0)))
		wins = clampi(int(config.get_value("levels", "wins", 0)), 0, matches)
		streak = maxi(0, int(config.get_value("levels", "streak", 0)))
		best_streak = maxi(streak, int(config.get_value("levels", "best_streak", 0)))
		crowns = maxi(0, int(config.get_value("levels", "crowns", 0)))
		recent.clear()
		for result in config.get_value("levels", "recent", []):
			recent.append(bool(result))
	else:
		leos = START_LEOS
	if not owned_ids.has("classic"):
		owned_ids.append("classic")
	for i in range(MAX_SEATS):
		var pen_id := str(seat_pens[i]) if i < seat_pens.size() else "classic"
		if not owned_ids.has(pen_id):
			pen_id = "classic"
		# Older saves kept one color per pen; seats start from that until they choose their own.
		var color := int(seat_colors[i]) if i < seat_colors.size() else int(pen_colors.get(pen_id, -1))
		if not _has_chosen_colors(seat_colors):
			color = DEFAULT_SEAT_COLORS[i]
		seats.append({"human": i == 0 or (i < humans.size() and bool(humans[i])), "pen": pen_id, "color": color})


func save_profile() -> void:
	var config := ConfigFile.new()
	config.set_value("wallet", "leos", leos)
	config.set_value("pens", "owned", owned_ids)
	config.set_value("pens", "colors", pen_colors)
	var humans: Array = []
	var seat_pens: Array = []
	var seat_colors: Array = []
	for seat in seats:
		humans.append(seat["human"])
		seat_pens.append(seat["pen"])
		seat_colors.append(seat["color"])
	config.set_value("lobby", "count", player_count)
	config.set_value("lobby", "human", humans)
	config.set_value("lobby", "pens", seat_pens)
	config.set_value("lobby", "colors", seat_colors)
	config.set_value("levels", "level", level)
	config.set_value("levels", "xp", xp)
	config.set_value("levels", "matches", matches)
	config.set_value("levels", "wins", wins)
	config.set_value("levels", "streak", streak)
	config.set_value("levels", "best_streak", best_streak)
	config.set_value("levels", "recent", recent)
	config.set_value("levels", "crowns", crowns)
	config.save(SAVE_PATH)


func add_leos(amount: int) -> void:
	leos += amount
	save_profile()


func owns(pen_id: String) -> bool:
	return owned_ids.has(pen_id)


func pen_info(pen_id: String) -> Dictionary:
	for pen in pens:
		if pen["id"] == pen_id:
			return pen
	return pens[0]


func buy(pen_id: String) -> bool:
	var price := int(pen_info(pen_id)["price"])
	if owns(pen_id) or leos < price:
		return false
	leos -= price
	owned_ids.append(pen_id)
	save_profile()
	return true


func _has_chosen_colors(seat_colors: Array) -> bool:
	# A save where no seat ever picked a color gets the default, all-different colors.
	for color in seat_colors:
		if int(color) >= 0:
			return true
	return false


func seat_barrel(seat_index: int) -> Color:
	return Color(seat_skin(seat_index)["barrel"])


func color_taken_by(seat_index: int, color_index: int) -> int:
	# Another human player already showing this color, or -1.
	var wanted := Color(PenData.recolor(pen_info(str(seats[seat_index]["pen"])), color_index)["barrel"])
	for i in range(player_count):
		if i != seat_index and bool(seats[i]["human"]) and seat_barrel(i).is_equal_approx(wanted):
			return i
	return -1


func seat_color(seat_index: int) -> int:
	return int(seats[seat_index]["color"])


func set_seat_color(seat_index: int, color_index: int) -> void:
	seats[seat_index]["color"] = color_index
	save_profile()


func seat_skin(seat_index: int) -> Dictionary:
	# This player's pen, in this player's color.
	return PenData.recolor(pen_info(str(seats[seat_index]["pen"])), seat_color(seat_index))


# ------------------------------------------------------------------ levels

func win_rate() -> float:
	return float(wins) / float(matches) if matches > 0 else 0.0


func level_progress() -> float:
	# Level plus how full its bar is, e.g. 12.4; a full bar waiting on a boss stays just below the next level.
	if level >= Levels.MAX_LEVEL:
		return float(Levels.MAX_LEVEL)
	return float(level) + minf(float(xp) / float(Levels.xp_to_next(level)), 0.999)


func boss_gate() -> bool:
	# The bar is full, but the boss of this level still has to be beaten.
	return level < Levels.MAX_LEVEL and Levels.is_boss(level) and xp >= Levels.xp_to_next(level)


func record_match(won: bool, rounds_won: int, flawless: bool, opponents: int) -> Dictionary:
	# A finished match against the computer: count it, add its XP and climb as far as it reaches.
	var from_level := level
	var from_progress := level_progress()
	var boss := Levels.is_boss(level)
	_count_result(won)
	var gain := Levels.match_xp(won, rounds_won, flawless, opponents, streak, boss, Levels.form_multiplier(recent))
	var reward := 0
	if level < Levels.MAX_LEVEL:
		xp += int(gain["total"])
	while level < Levels.MAX_LEVEL and xp >= Levels.xp_to_next(level):
		if Levels.is_boss(level) and not won:
			# The bar stays full until the boss is beaten.
			xp = Levels.xp_to_next(level)
			break
		var beat_boss := Levels.is_boss(level)
		xp -= Levels.xp_to_next(level)
		reward += Levels.level_reward(level + 1, beat_boss)
		level += 1
		if beat_boss:
			# Beating a boss moves you up exactly one level, and the new rank starts at most half full.
			xp = mini(xp, floori(float(Levels.xp_to_next(level)) * 0.5))
			break
	if level >= Levels.MAX_LEVEL:
		xp = 0
		if won and from_level >= Levels.MAX_LEVEL:
			crowns += 1
	leos += reward
	save_profile()
	return {
		"won": won,
		"xp": int(gain["total"]),
		"parts": gain["parts"],
		"from_level": from_level,
		"to_level": level,
		"from_progress": from_progress,
		"to_progress": level_progress(),
		"reward": reward,
		"boss": boss,
		"gate": boss_gate(),
		"crown": won and from_level >= Levels.MAX_LEVEL,
	}


func record_quit() -> void:
	# Walking out of a match against the computer once a point has been played counts as a loss.
	_count_result(false)
	save_profile()


func _count_result(won: bool) -> void:
	matches += 1
	if won:
		wins += 1
		streak += 1
		best_streak = maxi(best_streak, streak)
	else:
		streak = 0
	recent.append(won)
	while recent.size() > Levels.FORM_GAMES:
		recent.pop_front()
