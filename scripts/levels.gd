extends RefCounted
# The 50 levels of play against the computer.
# You climb them with XP from matches that have at least one computer player: every match counts,
# a win counts far more, and your form (the share of your last ten matches you won) speeds the climb
# up or slows it down. Each level makes the computer aim truer, think harder, take fewer risks and
# bring a stronger pen. Every tenth level is a boss: fill the bar and then beat the boss to go on.
# Matches with only people at the desk are not affected and earn no XP.

const MAX_LEVEL := 50
const BOSS_EVERY := 10
const FORM_GAMES := 10
const XP_PLAYED := 15
const XP_ROUND := 10
const XP_WIN := 45
const XP_PER_EXTRA_OPPONENT := 15
const XP_FLAWLESS := 20
const XP_STREAK_STEP := 5
const XP_STREAK_CAP := 25
const BOSS_XP := 1.5
# Form multiplies the XP of a match: 0.8 when you lose them all, 1.3 when you win them all.
const FORM_LOW := 0.8
const FORM_HIGH := 1.3

# Ten levels to a rank; the boss at the end of each rank is its final exam.
const RANKS := [
	{"name": "Doodler", "from": 1, "color": Color("#5ccf4f")},
	{"name": "Scribbler", "from": 11, "color": Color("#4aa3ff")},
	{"name": "Inker", "from": 21, "color": Color("#a46cff")},
	{"name": "Calligrapher", "from": 31, "color": Color("#ff5d5a")},
	{"name": "Pen Master", "from": 41, "color": Color("#ff9a4a")},
	{"name": "Legend", "from": 50, "color": Color("#ffd23f")},
]
const DIFFICULTY := ["Very easy", "Easy", "Fair", "Tricky", "Tough", "Hard", "Expert", "Brutal", "Savage", "Legendary"]


static func xp_to_next(level: int) -> int:
	return 50 + 4 * (clampi(level, 1, MAX_LEVEL) - 1)


static func is_boss(level: int) -> bool:
	return level % BOSS_EVERY == 0


static func next_boss(level: int) -> int:
	return mini(MAX_LEVEL, ceili(float(level) / float(BOSS_EVERY)) * BOSS_EVERY)


static func rank_index(level: int) -> int:
	var index := 0
	for k in range(RANKS.size()):
		if level >= int(RANKS[k]["from"]):
			index = k
	return index


static func rank(level: int) -> Dictionary:
	return RANKS[rank_index(level)]


static func rank_color(level: int) -> Color:
	return rank(level)["color"]


static func cpu_skill(level: int, boss: bool = false) -> float:
	# 0.08 at level 1, rising steadily to about 1.0 at level 50; a boss plays a step above its level.
	var progress := float(clampi(level, 1, MAX_LEVEL) - 1) / float(MAX_LEVEL - 1)
	return lerpf(0.08, 0.97, progress) + (0.05 if boss else 0.0)


static func difficulty_name(level: int) -> String:
	return DIFFICULTY[clampi(floori(float(level - 1) / 5.0), 0, DIFFICULTY.size() - 1)]


static func cpu_pen_step(level: int, boss: bool) -> int:
	# How far along the pen catalog the computer starts: one pen stronger every ten levels.
	return clampi(floori(float(level - 1) / float(BOSS_EVERY)), 0, 4) + (1 if boss else 0)


static func level_reward(new_level: int, beat_boss: bool) -> int:
	# Leos for reaching a level; beating a boss pays double.
	var reward := 20 + 5 * new_level
	return reward * 2 if beat_boss else reward


static func form(recent: Array) -> float:
	# The share of the last ten matches won. Matches not played yet count as half a win, so a new
	# player's form starts even and one lucky win can't swing it.
	var won := 0.5 * float(maxi(0, FORM_GAMES - recent.size()))
	for result in recent.slice(-FORM_GAMES):
		if bool(result):
			won += 1.0
	return won / float(FORM_GAMES)


static func form_multiplier(recent: Array) -> float:
	# Even form (half won) is x1.0; losing them all is FORM_LOW, winning them all FORM_HIGH.
	var rate := form(recent)
	var multiplier := lerpf(FORM_LOW, 1.0, rate * 2.0) if rate < 0.5 else lerpf(1.0, FORM_HIGH, (rate - 0.5) * 2.0)
	return snappedf(multiplier, 0.05)


static func match_xp(won: bool, rounds_won: int, flawless: bool, opponents: int, streak: int, boss: bool, multiplier: float) -> Dictionary:
	# Returns {"total": int, "parts": [[label, amount], ...]} so the result card can show the sums.
	var parts: Array = [["Match played", XP_PLAYED]]
	if rounds_won > 0:
		parts.append(["Rounds won", XP_ROUND * rounds_won])
	if won:
		parts.append(["Victory", XP_WIN + XP_PER_EXTRA_OPPONENT * maxi(0, opponents - 1)])
		if flawless:
			parts.append(["Flawless", XP_FLAWLESS])
		if streak > 1:
			parts.append(["Win streak", mini(XP_STREAK_CAP, XP_STREAK_STEP * (streak - 1))])
	var base := 0
	for part in parts:
		base += int(part[1])
	var total := base
	if boss:
		var boosted := roundi(float(total) * BOSS_XP)
		parts.append(["Boss match", boosted - total])
		total = boosted
	if not is_equal_approx(multiplier, 1.0):
		var scaled := roundi(float(total) * multiplier)
		parts.append(["Form x%.2f" % multiplier, scaled - total])
		total = scaled
	return {"total": maxi(1, total), "parts": parts}
