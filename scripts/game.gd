extends Node2D
# The match: 2 to 4 pens on one desk, any mix of people and computer players.
# Every round opens with a shot at the middle point; the closest pen then shoots first and the
# turns go round in that order. A pen is out when its center leaves the desk, and the last pen on
# the desk wins the round.

const UIKit := preload("res://scripts/ui_kit.gd")
const PenArt := preload("res://scripts/pen_art.gd")
const PenData := preload("res://scripts/pen_data.gd")
const Levels := preload("res://scripts/levels.gd")
const FONT := UIKit.FONT
const INK := UIKit.INK
const PAPER := UIKit.PAPER
const PLAYER_COLOR := UIKit.GREEN
const PLAYER_TIP := Color("#ff865e")
const PEN_LENGTH := PenArt.PEN_LENGTH
const PEN_HALF_LENGTH := PenArt.PEN_HALF_LENGTH
const PEN_RADIUS := PenArt.PEN_RADIUS
const MAX_PULL := 220.0
const FIXED_STEP := 1.0 / 240.0
const FALL_DURATION := 0.62
const PULL_DEAD_ZONE := 12.0
# The computer's look-ahead plays shots forward at this step, for at most this many steps.
const ROLLOUT_STEP := 1.0 / 240.0
const ROLLOUT_STEPS := 720
const ROLLOUTS_PER_FRAME := 1
# Power maps to travel distance, so 50% power slides about half as far as 100%.
const MIN_TRAVEL := 60.0
const MAX_TRAVEL := 680.0
# Plastic on wood: plain Coulomb friction, so a pen slows at a steady rate and then simply stops.
const SLIDE_DECEL := 2600.0
const FRICTION_POINTS := 9
# A round barrel rolls a little more easily sideways than it slides lengthwise.
const ROLL_RATIO := 0.8
# Below these a pen is held by static friction and stops dead.
const SLEEP_SPEED := 8.0
const SLEEP_SPIN := 0.25
const MAX_SPIN := 40.0
# Hard plastic pens: how bouncy they are, and how much their surfaces grip each other.
const RESTITUTION := 0.68
const PEN_GRIP := 0.2
const LEOS_ROUND_WIN := 10
const LEOS_ROUND_LOSS := 2
const LEOS_LAG_WIN := 3
const LEOS_HIT := 1
const LEOS_HIT_CAP := 6
const LEOS_MATCH_WIN := 40
const LEOS_MATCH_LOSS := 8
const LEOS_FLAWLESS := 20
const LEOS_PER_EXTRA_OPPONENT := 15
# The desk gets smaller the longer a round lasts: first after a minute of play, then every half minute.
const SHRINK_FIRST := 60.0
const SHRINK_EVERY := 30.0
const SHRINK_FACTOR := 0.8
const SHRINK_MIN := 0.45
const SHRINK_SPEED := 0.07
const LOBBY_SCENE := "res://scenes/lobby.tscn"
# Each human gets this long to take a shot; when it runs out the turn passes on.
const TURN_TIME := 10.0
# When the XP bar on the result card starts to fill, after the leos have counted up.
const XP_FILL_START := 1.95
# How far down the result card the level bar sits.
const XP_ROW_Y := 384.0
# Power coins: grab one with your pen and your next shot hits harder (+) or softer (-).
# Each level makes the pen this much heavier, so it shoves harder and is harder to shove.
const BOOST_MASS := 1.3
const MAX_BOOST := 3
const COIN_RADIUS := 26.0
const MAX_COINS := 3
const COIN_SPAWN_CHANCE := 0.65
const COIN_COLORS := {
	3: Color("#7b6cf0"), 2: Color("#3fa8e8"), 1: Color("#4fc98a"),
	-1: Color("#f2a24a"), -2: Color("#e8613f"), -3: Color("#b03a4e"),
}

enum Turn { AIM, ROLL, CPU_WAIT, ROUND_WAIT, ROUND_END, MATCH_END }


class Seat extends RefCounted:
	var index := 0
	var is_human := true
	var label := "P1"
	var color := Color.WHITE
	var skin: Dictionary = {}
	var skill := 0.5
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var angle := 0.0
	var omega := 0.0
	var alive := true
	var score := 0
	var lag_distance := 0.0
	var trail: Array[Dictionary] = []
	var falling := false
	var fall_t := 0.0
	var fall_start := Vector2.ZERO
	var fall_angle := 0.0
	var fall_dir := Vector2.DOWN
	var fall_vel := Vector2.ZERO
	var fall_spin := 0.0
	var fall_thud := false
	# Power from coins, -3..3, spent when this pen's own shot ends.
	var boost := 0
	# Computer players play at the profile's level; on boss levels the first one is the boss.
	var level := 0
	var boss := false


var screen_size := Vector2.ZERO
var ui_scale := 1.0
var compact_layout := false

var seats: Array[Seat] = []
var human_count := 1
var rounds_to_win := 3
var current := 0
var order: Array[int] = []
var lag_queue: Array[int] = []
var lag_pos := 0
var lag_active := false
var lag_result_timer := 0.0

var turn: Turn = Turn.AIM
var turn_timer := 0.0
var shot_time := 0.0
var physics_accumulator := 0.0

var round_number := 1
var round_winner := -1
var match_winner := -1

var dragging := false
var drag_origin := Vector2.ZERO
var drag_end := Vector2.ZERO
var launch_direction := Vector2.RIGHT
var shot_power := 0.0
# Where the finger strikes the pen: signed distance from its middle along its length.
var flick_offset := 0.0

var cpu_shot_direction := Vector2.LEFT
var cpu_shot_power := 0.7
var cpu_shot_offset := 0.0
# A shot the computer is still thinking over; empty once it has decided.
var cpu_plan: Dictionary = {}

var impact_timer := 0.0
var impact_cooldown := 0.0
var sound_cooldown := 0.0
var impact_position := Vector2.ZERO
var shake := 0.0
var sparks: Array[Dictionary] = []
var toast_timer := 0.0
var toast_text := ""
var banner_timer := 0.0
var banner_text := ""
var rng := RandomNumberGenerator.new()

var match_earned := 0
var earn_breakdown: Dictionary = {}
var match_start_level := 1
var solid_hits := 0
var rounds_lost := 0
var popups: Array[Dictionary] = []
# Matches with a computer player count toward the level climb (see levels.gd).
var vs_cpu := false
var level_result: Dictionary = {}
var xp_clock := 0.0
var xp_shown := 0.0
var levelup_active := false
var levelup_done := false
var levelup_time := 0.0
var levelup_wait := 0.0
var levelup_shown := 0
var xp_pop_at := -10.0
var confetti: Array[Dictionary] = []
var coins: Array[Dictionary] = []
var coin_flashes: Array[Dictionary] = []
var shot_boost := 0

var round_clock := 0.0
var shrink_level := 0
var desk_scale := 1.0
var desk_target := 1.0
var shrink_warned := false
var tick_second := -1

# Screen flow: the pause menu, the pressed HUD button, fades between scenes, the result reveal.
var paused := false
var turn_left := TURN_TIME
var turn_tick := -1
var pressed_key := ""
var fade := 1.0
var leaving := false
var result_time := 0.0
var result_stars_shown := 0
var banner_age := 0.0
var banner_last := 0.0


func _ready() -> void:
	rng.randomize()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_update_layout()
	_setup_seats()
	_start_match()
	set_process(true)
	set_process_input(true)


func _process(delta: float) -> void:
	var current_size := get_viewport_rect().size
	if current_size != screen_size:
		_update_layout()
	var frame_delta := minf(delta, 0.05)
	if leaving:
		fade = minf(1.0, fade + frame_delta * 4.0)
		if fade >= 1.0:
			set_process(false)
			get_tree().change_scene_to_file(LOBBY_SCENE)
		queue_redraw()
		return
	fade = maxf(0.0, fade - frame_delta * 3.0)
	if turn == Turn.MATCH_END:
		_update_result(frame_delta)
	if paused:
		Sfx.set_scrape(0.0)
		queue_redraw()
		return
	_update_effects(frame_delta)
	_update_falls(frame_delta)
	_update_coins(frame_delta)

	if turn == Turn.AIM:
		_update_turn_clock(frame_delta)
	if turn == Turn.ROLL:
		physics_accumulator += frame_delta
		var steps := 0
		while physics_accumulator >= FIXED_STEP and steps < 20 and turn == Turn.ROLL:
			_physics_step(FIXED_STEP)
			physics_accumulator -= FIXED_STEP
			steps += 1
	elif turn == Turn.CPU_WAIT:
		if not cpu_plan.is_empty():
			_advance_cpu_plan()
		turn_timer -= frame_delta
		if turn_timer <= 0.0 and cpu_plan.is_empty():
			_cpu_take_turn()
	elif turn == Turn.ROUND_WAIT:
		turn_timer -= frame_delta
		if turn_timer <= 0.0 and not _any_falling():
			_finish_round()
	elif turn == Turn.ROUND_END:
		turn_timer -= frame_delta
		if turn_timer <= 0.0:
			round_number += 1
			_start_round()

	if not lag_active and (turn == Turn.AIM or turn == Turn.CPU_WAIT or turn == Turn.ROLL):
		_update_shrink(frame_delta)
	_update_scrape()
	for seat in seats:
		_record_trail(seat, turn == Turn.ROLL)

	shake *= exp(-9.0 * frame_delta)
	if shake > 0.25:
		position = Vector2(rng.randf_range(-shake, shake), rng.randf_range(-shake, shake))
	else:
		shake = 0.0
		position = Vector2.ZERO
	if toast_timer > 0.0:
		toast_timer = maxf(0.0, toast_timer - frame_delta)
	if banner_timer > banner_last + 0.001:
		banner_age = 0.0
	banner_age += frame_delta
	if banner_timer > 0.0:
		banner_timer = maxf(0.0, banner_timer - frame_delta)
	banner_last = banner_timer
	queue_redraw()


# ------------------------------------------------------------------ setup and layout

func _update_layout() -> void:
	var next_size := get_viewport_rect().size
	if next_size.x <= 0.0 or next_size.y <= 0.0:
		return
	var had_size := screen_size.x > 0.0 and screen_size.y > 0.0
	if had_size:
		var factor := Vector2(next_size.x / screen_size.x, next_size.y / screen_size.y)
		for seat in seats:
			seat.pos *= factor
			seat.vel *= factor
			seat.fall_start *= factor
		drag_origin *= factor
		drag_end *= factor
	screen_size = next_size
	ui_scale = clampf(minf(screen_size.x / 1280.0, screen_size.y / 720.0), 0.78, 1.15)
	compact_layout = screen_size.x < 620.0
	if had_size:
		for seat in seats:
			seat.pos = _clamp_pen(seat.pos)


func _setup_seats() -> void:
	seats.clear()
	human_count = 0
	var count := clampi(Profile.player_count, 2, Profile.MAX_SEATS)
	for i in range(count):
		var config: Dictionary = Profile.seats[i]
		var seat := Seat.new()
		seat.index = i
		seat.is_human = bool(config["human"])
		seat.color = UIKit.SEAT_COLORS[i]
		if seat.is_human:
			human_count += 1
			seat.skin = Profile.seat_skin(i)
		seats.append(seat)
	vs_cpu = human_count < count
	rounds_to_win = 3 if count == 2 else 2


func _setup_cpu_levels() -> void:
	# The computer plays at your level, read afresh for every match so a rematch after levelling up
	# is already harder. Each computer player varies a little around it; on a boss level the first
	# one is the boss. People keep their plain labels, and games of only people are left alone.
	var cpu_total := seats.size() - human_count
	var boss_level := Levels.is_boss(Profile.level)
	var first_cpu := true
	for seat in seats:
		if seat.is_human:
			seat.label = "You" if human_count == 1 else "P%d" % (seat.index + 1)
			continue
		seat.level = Profile.level
		seat.boss = boss_level and first_cpu
		first_cpu = false
		seat.skill = Levels.cpu_skill(seat.level, seat.boss) + rng.randf_range(-0.04, 0.04)
		if seat.boss:
			seat.label = "BOSS"
		else:
			seat.label = "CPU" if cpu_total == 1 else "CPU %d" % (seat.index + 1)


func _start_match() -> void:
	match_start_level = Profile.level
	for seat in seats:
		seat.score = 0
	round_number = 1
	match_winner = -1
	match_earned = 0
	earn_breakdown.clear()
	solid_hits = 0
	rounds_lost = 0
	shake = 0.0
	paused = false
	result_time = 0.0
	result_stars_shown = 0
	level_result.clear()
	xp_clock = 0.0
	levelup_active = false
	levelup_done = false
	levelup_time = 0.0
	levelup_wait = 0.0
	levelup_shown = 0
	xp_pop_at = -10.0
	confetti.clear()
	_setup_cpu_levels()
	_start_round()
	if _boss_seat() != null:
		banner_text = "BOSS FIGHT!"
		banner_timer = 1.8
		toast_text = "LEVEL %d BOSS — BEAT IT TO RANK UP" % Profile.level if Profile.level < Levels.MAX_LEVEL else "THE FINAL BOSS — WIN A CROWN"
		toast_timer = 2.6
		Sfx.play("boss", -3.0)
	Analytics.track_event("match_start", {
		"game_mode": "vs_cpu" if vs_cpu else "local_multiplayer",
		"player_count": seats.size(),
		"level": match_start_level,
	})
	queue_redraw()


func _boss_seat() -> Seat:
	for seat in seats:
		if seat.boss:
			return seat
	return null


func _start_round() -> void:
	dragging = false
	cpu_plan.clear()
	shot_power = 0.0
	shot_time = 0.0
	physics_accumulator = 0.0
	impact_timer = 0.0
	impact_cooldown = 0.0
	sparks.clear()
	coins.clear()
	coin_flashes.clear()
	round_winner = -1
	round_clock = 0.0
	shrink_level = 0
	desk_scale = 1.0
	desk_target = 1.0
	shrink_warned = false
	tick_second = -1
	var cpu_index := 0
	for seat in seats:
		seat.vel = Vector2.ZERO
		seat.omega = 0.0
		seat.alive = true
		seat.falling = false
		seat.fall_t = 0.0
		seat.fall_thud = false
		seat.lag_distance = 0.0
		seat.boost = 0
		seat.trail.clear()
		if seat.is_human:
			seat.skin = Profile.seat_skin(seat.index)
		else:
			seat.skin = _cpu_skin(seat, cpu_index)
			cpu_index += 1
	_make_colors_unique()
	_place_pens()
	# Opening shot: everyone aims for the middle in turn, starting from a different seat each round.
	lag_active = true
	lag_result_timer = 0.0
	lag_queue.clear()
	for k in range(seats.size()):
		lag_queue.append((round_number - 1 + k) % seats.size())
	lag_pos = 0
	current = lag_queue[0]
	banner_text = "ROUND %d" % round_number
	banner_timer = 1.3
	toast_text = "REACH THE MIDDLE — CLOSEST GOES FIRST"
	toast_timer = 2.4
	_begin_turn()


func _make_colors_unique() -> void:
	# Every pen on the desk gets its own barrel color; a pen that would look like an earlier
	# one switches to its seat's color, or else to the first free palette color.
	var used: Array[Color] = []
	for seat in seats:
		var barrel := Color(seat.skin["barrel"])
		if _color_used(used, barrel):
			var options: Array[Color] = [UIKit.SEAT_COLORS[seat.index]]
			options.append_array(PenData.palette())
			for option in options:
				if not _color_used(used, option):
					seat.skin = seat.skin.duplicate()
					seat.skin["barrel"] = option
					barrel = option
					break
		used.append(barrel)


func _color_used(used: Array[Color], color: Color) -> bool:
	for other in used:
		if absf(other.r - color.r) + absf(other.g - color.g) + absf(other.b - color.b) < 0.25:
			return true
	return false


func _cpu_skin(seat: Seat, cpu_index: int) -> Dictionary:
	# The computer brings stronger pens at higher levels and in later rounds, each in its own color.
	var step := Levels.cpu_pen_step(seat.level, seat.boss) + round_number - 1 + cpu_index
	var pen := PenData.cpu_pen(Profile.pens, step, rng)
	if cpu_index == 0:
		return pen
	return PenData.recolor(pen, (round_number + cpu_index * 3) % PenData.palette().size())


func _place_pens() -> void:
	# Pens start around the desk, facing the middle point they all have to reach.
	var desk := _table_bounds()
	var middle := desk.get_center()
	var count := seats.size()
	var reach_x := minf(desk.size.x * 0.36, 430.0 * ui_scale)
	var reach_y := desk.size.y * 0.34
	var wobble := rng.randf_range(-24.0, 24.0) * ui_scale
	if count == 2:
		if compact_layout:
			seats[0].pos = middle + Vector2(wobble, reach_y)
			seats[1].pos = middle - Vector2(wobble, reach_y)
		else:
			seats[0].pos = middle + Vector2(-reach_x, desk.size.y * 0.16 + wobble)
			seats[1].pos = middle + Vector2(reach_x, -desk.size.y * 0.16 - wobble)
	else:
		var angles: Array = [2.62, -1.57, 0.52] if count == 3 else [2.36, -0.79, 0.79, -2.36]
		if compact_layout:
			reach_x = desk.size.x * 0.3
		for i in range(count):
			var around := float(angles[i])
			seats[i].pos = middle + Vector2(cos(around) * reach_x, sin(around) * reach_y)
	for seat in seats:
		seat.angle = (middle - seat.pos).angle()


func _full_bounds() -> Rect2:
	# The desk at full size, inside the frame and clear of any notch.
	var inset := 34.0 * ui_scale
	return UIKit.safe_rect(self).grow(-inset)


func _table_bounds() -> Rect2:
	# The desk as it is right now; past its edge is a drop. It shrinks toward the middle over time.
	var full := _full_bounds()
	if desk_scale >= 0.9999:
		return full
	var size := full.size * desk_scale
	return Rect2(full.get_center() - size * 0.5, size)


func _clamp_pen(point: Vector2) -> Vector2:
	var bounds := _table_bounds().grow(-PEN_RADIUS * 3.0 * ui_scale)
	return Vector2(clampf(point.x, bounds.position.x, bounds.end.x), clampf(point.y, bounds.position.y, bounds.end.y))


func _edge_distance(point: Vector2) -> float:
	# Signed distance to the nearest desk edge; negative once the point is off the desk.
	var desk := _table_bounds()
	return minf(minf(point.x - desk.position.x, desk.end.x - point.x), minf(point.y - desk.position.y, desk.end.y - point.y))


func _nearest_edge_normal(point: Vector2) -> Vector2:
	var desk := _table_bounds()
	var distances := [point.x - desk.position.x, desk.end.x - point.x, point.y - desk.position.y, desk.end.y - point.y]
	var normals := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
	var best := 0
	for i in range(1, 4):
		if float(distances[i]) < float(distances[best]):
			best = i
	return normals[best]


# ------------------------------------------------------------------ turns

func _alive_count() -> int:
	var total := 0
	for seat in seats:
		if seat.alive:
			total += 1
	return total


func _any_falling() -> bool:
	for seat in seats:
		if seat.falling:
			return true
	return false


func _begin_turn() -> void:
	var seat := seats[current]
	dragging = false
	shot_power = 0.0
	if seat.is_human:
		turn = Turn.AIM
		_start_turn_clock()
		if human_count > 1:
			banner_text = "%s'S TURN" % seat.label.to_upper()
			banner_timer = 1.0
		elif not lag_active:
			toast_text = "YOUR SHOT — PRESS WHERE TO STRIKE, PULL BACK"
			toast_timer = 1.3
	else:
		turn = Turn.CPU_WAIT
		turn_timer = 0.9 if lag_active else 0.75
	if not lag_active:
		_maybe_spawn_coin()
	if not seat.is_human:
		_plan_cpu_shot()


func _next_in_order(from: int) -> int:
	var start := order.find(from)
	for k in range(1, order.size() + 1):
		var index := order[(start + k) % order.size()]
		if seats[index].alive:
			return index
	return from


func _launch(seat: Seat, direction: Vector2, power: float, offset: float) -> void:
	var kick := _flick_kick(seat, direction, power, offset)
	seat.vel = kick[0]
	seat.omega = kick[1]
	turn = Turn.ROLL
	shot_time = 0.0
	physics_accumulator = 0.0
	impact_cooldown = 0.0
	toast_timer = 0.0
	# The power held at launch is used up by this shot; coins grabbed on the way carry on.
	shot_boost = seat.boost
	Sfx.play("whoosh", lerpf(-16.0, -7.0, power), lerpf(0.9, 1.15, power))


func _flick_kick(seat: Seat, direction: Vector2, power: float, offset: float) -> Array:
	# The finger is an impulse J at one point of the pen: J/m moves it, (arm × J)/I turns it.
	# The finger moves at a set speed, and the pen's end gives way more easily than its middle
	# (its effective mass there is about a quarter), so an end strike pushes less and spins more.
	var mass := _mass_of(seat)
	var inertia := _pen_inertia(mass)
	var arm := Vector2.RIGHT.rotated(seat.angle) * offset
	var lever := arm.cross(direction)
	var effective_mass := 1.0 / (1.0 / mass + lever * lever / inertia)
	var impulse := direction * _speed_for_power(power, direction.angle() - seat.angle) * effective_mass
	var spin := clampf(arm.cross(impulse) / inertia, -MAX_SPIN, MAX_SPIN)
	return [impulse / mass, spin]


func _simulate_slide(seat: Seat, velocity: Vector2, spin: float) -> Dictionary:
	# The same friction as the real step, on a copy of this pen with nothing else on the desk.
	var ghost := Seat.new()
	ghost.skin = seat.skin
	ghost.pos = seat.pos
	ghost.angle = seat.angle
	ghost.vel = velocity
	ghost.omega = spin
	var desk := _table_bounds()
	var path := PackedVector2Array([ghost.pos])
	var falls := false
	for step in range(720):
		ghost.pos += ghost.vel * FIXED_STEP
		ghost.angle += ghost.omega * FIXED_STEP
		_apply_slide_friction(ghost, FIXED_STEP, desk)
		if step % 4 == 3:
			path.append(ghost.pos)
		if not desk.has_point(ghost.pos):
			falls = true
			break
		if ghost.vel == Vector2.ZERO and ghost.omega == 0.0:
			break
	path.append(ghost.pos)
	return {"path": path, "position": ghost.pos, "angle": ghost.angle, "falls": falls}


func _settle() -> void:
	# Everything has stopped: hand the shot to the next pen.
	if not lag_active:
		var shooter := seats[current]
		shooter.boost = clampi(shooter.boost - shot_boost, -MAX_BOOST, MAX_BOOST)
	shot_boost = 0
	for seat in seats:
		seat.vel = Vector2.ZERO
		seat.omega = 0.0
	physics_accumulator = 0.0
	if lag_active:
		lag_pos += 1
		while lag_pos < lag_queue.size() and not seats[lag_queue[lag_pos]].alive:
			lag_pos += 1
		if lag_pos < lag_queue.size():
			current = lag_queue[lag_pos]
			_begin_turn()
		else:
			_finish_lag()
	else:
		current = _next_in_order(current)
		_begin_turn()


func _finish_lag() -> void:
	lag_active = false
	var middle := _table_bounds().get_center()
	var ranked: Array[Seat] = []
	for seat in seats:
		seat.lag_distance = seat.pos.distance_to(middle)
		if seat.alive:
			ranked.append(seat)
	ranked.sort_custom(func(a: Seat, b: Seat) -> bool: return a.lag_distance < b.lag_distance)
	order.clear()
	for seat in ranked:
		order.append(seat.index)
	current = order[0]
	lag_result_timer = 2.8
	banner_text = "YOU GO FIRST" if current == 0 and human_count == 1 else "%s GOES FIRST" % seats[current].label.to_upper()
	banner_timer = 1.7
	if current == 0:
		_award(LEOS_LAG_WIN, "Closest to the middle")
	_maybe_spawn_coin()
	if seats[current].is_human:
		turn = Turn.AIM
		_start_turn_clock()
		shot_power = 0.0
		toast_text = "YOUR SHOT — PRESS WHERE TO STRIKE, PULL BACK"
		toast_timer = 1.4
	else:
		turn = Turn.CPU_WAIT
		turn_timer = 1.8
		_plan_cpu_shot()


func _finish_round() -> void:
	var winner := round_winner
	if winner >= 0:
		seats[winner].score += 1
	if winner == 0:
		_award(LEOS_ROUND_WIN, "Rounds won")
	else:
		# A draw (every pen fell) costs nothing; losing a round spoils a flawless match.
		if winner > 0:
			rounds_lost += 1
		_award(LEOS_ROUND_LOSS, "Rounds played")
	Sfx.play("win" if winner == 0 else "lose", -4.0)
	toast_timer = 0.0
	if winner >= 0 and seats[winner].score >= rounds_to_win:
		match_winner = winner
		turn = Turn.MATCH_END
		if winner == 0:
			_award(LEOS_MATCH_WIN + LEOS_PER_EXTRA_OPPONENT * (seats.size() - 2), "Match win")
			if rounds_lost == 0:
				_award(LEOS_FLAWLESS, "Flawless match")
		else:
			_award(LEOS_MATCH_LOSS, "Match played")
		if vs_cpu:
			level_result = Profile.record_match(winner == 0, seats[0].score, winner == 0 and rounds_lost == 0, seats.size() - 1)
			xp_shown = float(level_result["from_progress"])
			if int(level_result["to_level"]) > int(level_result["from_level"]):
				Analytics.track_event("level_up", {"level": int(level_result["to_level"])})
		Analytics.track_event("match_end", {
			"result": "win" if winner == 0 else "loss",
			"game_mode": "vs_cpu" if vs_cpu else "local_multiplayer",
			"player_count": seats.size(),
			"rounds_played": round_number,
			"level": match_start_level,
		})
	else:
		turn = Turn.ROUND_END
		turn_timer = 1.9
		if winner == 0:
			banner_text = "POINT TO YOU!"
		elif winner > 0:
			banner_text = "POINT TO %s" % seats[winner].label.to_upper()
		else:
			banner_text = "DRAW — REPLAY"
		banner_timer = 1.5


func _begin_fall(seat: Seat) -> void:
	seat.alive = false
	seat.falling = true
	seat.fall_t = 0.0
	seat.fall_thud = false
	seat.fall_start = seat.pos
	seat.fall_angle = seat.angle
	# The centre has just crossed this edge: the pen tips over it, keeping the slide and spin it had.
	seat.fall_dir = _nearest_edge_normal(seat.pos)
	seat.fall_vel = seat.vel
	seat.fall_spin = seat.omega
	seat.vel = Vector2.ZERO
	seat.omega = 0.0
	Sfx.play("fall", -6.0)


func _update_falls(delta: float) -> void:
	for seat in seats:
		if not seat.falling:
			continue
		seat.fall_t = minf(1.0, seat.fall_t + delta / FALL_DURATION)
		if seat.fall_t >= 0.8 and not seat.fall_thud:
			seat.fall_thud = true
			shake = maxf(shake, 4.0 * ui_scale)
			Sfx.play("thud", -2.0)
		if seat.fall_t >= 1.0:
			seat.falling = false


func _end_round_now() -> void:
	# At most one pen is left on the desk: the round is decided once the fallen pens land.
	round_winner = -1
	for seat in seats:
		if seat.alive:
			round_winner = seat.index
			seat.vel = Vector2.ZERO
			seat.omega = 0.0
	turn = Turn.ROUND_WAIT
	turn_timer = 0.3
	dragging = false


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pointer_down(event.position)
		else:
			_pointer_up(event.position)
	elif event is InputEventMouseMotion and dragging:
		_update_aim(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_pointer_down(event.position)
		else:
			_pointer_up(event.position)
	elif event is InputEventScreenDrag and dragging:
		_update_aim(event.position)


func _pointer_down(point: Vector2) -> void:
	# HUD buttons sink in when pressed and fire when the finger lifts on them.
	pressed_key = _hud_button_at(point)
	if pressed_key != "" or paused or leaving or turn != Turn.AIM:
		return
	var seat := seats[current]
	if _point_hits_pen(point, seat):
		# The finger lands on the pen's centre line at the pressed spot; that is where it will strike.
		var axis := Vector2.RIGHT.rotated(seat.angle)
		var half_length := PEN_HALF_LENGTH * ui_scale
		flick_offset = clampf((point - seat.pos).dot(axis), -half_length, half_length)
		dragging = true
		drag_origin = seat.pos + axis * flick_offset
		drag_end = point
		shot_power = 0.0
		queue_redraw()


func _go_to_lobby() -> void:
	leaving = true
	Sfx.set_scrape(0.0)


func _start_turn_clock() -> void:
	turn_left = TURN_TIME
	turn_tick = -1


func _update_turn_clock(delta: float) -> void:
	# The clock waits while a big announcement is on screen.
	if banner_timer > 0.3:
		return
	turn_left -= delta
	var second := ceili(turn_left)
	if second <= 3 and second >= 1 and second != turn_tick:
		turn_tick = second
		Sfx.play("tick", -2.0, 1.0 + float(3 - second) * 0.1)
	if turn_left <= 0.0:
		_turn_timeout()


func _turn_timeout() -> void:
	# Time's up. A shot already being aimed still goes; otherwise the turn is lost.
	if dragging and shot_power >= 0.08:
		_pointer_up(drag_end)
		return
	dragging = false
	toast_text = "TIME'S UP — TURN SKIPPED"
	toast_timer = 1.4
	Sfx.play("knock", -4.0, 0.7)
	_settle()


func _hud_button_at(point: Vector2) -> String:
	if leaving:
		return ""
	var buttons := {}
	if turn == Turn.MATCH_END:
		if levelup_active:
			return "levelup" if levelup_time >= 1.2 else ""
		if result_time < 0.6:
			return ""
		buttons = {"again": _result_button_rect(), "lobby": _result_lobby_rect()}
	elif paused:
		buttons = _pause_buttons()
	else:
		buttons = {"pause": _pause_rect()}
	for key in buttons:
		var rect: Rect2 = buttons[key]
		if rect.grow(8.0 * ui_scale).has_point(point):
			return str(key)
	return ""


func _activate_hud(key: String) -> void:
	Sfx.play("click", -4.0)
	match key:
		"pause":
			paused = true
			dragging = false
		"resume":
			paused = false
		"restart", "again":
			_count_walkout()
			_start_match()
		"lobby":
			_count_walkout()
			_go_to_lobby()
		"levelup":
			levelup_active = false


func _quit_counts() -> bool:
	# Leaving a match against the computer once a point has been played counts as a loss, so the
	# win rate can't be kept clean by quitting a match that is going badly.
	if not vs_cpu or turn == Turn.MATCH_END:
		return false
	if round_number > 1:
		return true
	for seat in seats:
		if seat.score > 0:
			return true
	return false


func _count_walkout() -> void:
	if _quit_counts():
		Profile.record_quit()
		Analytics.track_event("match_end", {
			"result": "quit",
			"game_mode": "vs_cpu",
			"player_count": seats.size(),
			"rounds_played": round_number,
			"level": match_start_level,
		})


func _point_hits_pen(point: Vector2, seat: Seat) -> bool:
	# Test the full rotated pen body as a capsule, not a single center handle.
	var axis := Vector2.RIGHT.rotated(seat.angle)
	var half_length := PEN_HALF_LENGTH * ui_scale
	var along := clampf((point - seat.pos).dot(axis), -half_length, half_length)
	var closest_point := seat.pos + axis * along
	var touch_radius := (PEN_RADIUS + 22.0) * ui_scale
	return point.distance_to(closest_point) <= touch_radius


func _pointer_up(point: Vector2) -> void:
	if pressed_key != "":
		var key := pressed_key
		pressed_key = ""
		if _hud_button_at(point) == key:
			_activate_hud(key)
		return
	if not dragging:
		return
	# Keep the power and direction locked from the last drag event so release jitter can't change the shot.
	dragging = false
	if shot_power >= 0.08:
		# Power comes from how far the finger was drawn back; the spin from where it strikes.
		_launch(seats[current], launch_direction, shot_power, flick_offset)
	else:
		toast_text = "PULL BACK FARTHER"
		toast_timer = 0.8
	queue_redraw()


func _update_aim(point: Vector2) -> void:
	var pull := point - drag_origin
	drag_end = point
	var pull_length := pull.length()
	shot_power = clampf(pull_length / (MAX_PULL * ui_scale), 0.0, 1.0)
	if pull_length > PULL_DEAD_ZONE * ui_scale:
		# Slingshot: the pen launches opposite to the pull.
		launch_direction = -pull / pull_length


func _travel_for_power(power: float) -> float:
	return lerpf(MIN_TRAVEL, MAX_TRAVEL, power) * ui_scale


func _speed_for_power(power: float, relative_angle: float = 0.0) -> float:
	# Constant friction: v² = 2·a·d, so a clean centre flick slides exactly the travel for its power.
	# Sideways the barrel rolls a little, so the same distance needs a little less speed.
	var along := cos(relative_angle)
	var across := sin(relative_angle)
	var decel := SLIDE_DECEL * ui_scale * (along * along + across * across * ROLL_RATIO)
	return sqrt(2.0 * decel * _travel_for_power(power))


# ------------------------------------------------------------------ physics

func _physics_step(delta: float) -> void:
	if turn != Turn.ROLL:
		return
	shot_time += delta
	var desk := _table_bounds()
	for seat in seats:
		if not seat.alive:
			continue
		seat.pos += seat.vel * delta
		seat.angle = wrapf(seat.angle + seat.omega * delta, -PI, PI)
		# Surface friction acts on every point of each pen, so sliding and spinning slow together.
		_apply_slide_friction(seat, delta, desk)
		_collect_coins(seat)
	# Two passes keep a pile-up of three or four pens from pushing into each other.
	for pass_index in range(2):
		for i in range(seats.size()):
			for j in range(i + 1, seats.size()):
				if seats[i].alive and seats[j].alive:
					_resolve_pair(seats[i], seats[j], pass_index == 0)
	# A pen tips off the desk once its center of mass passes the edge.
	if _check_falls():
		return
	if shot_time > 0.25 and _all_settled():
		_settle()


func _check_falls() -> bool:
	# Returns true when this ended the round.
	var desk := _table_bounds()
	var fell := false
	for seat in seats:
		if seat.alive and not desk.has_point(seat.pos):
			_begin_fall(seat)
			fell = true
	if fell and _alive_count() <= 1:
		_end_round_now()
		return true
	return false


func _all_settled() -> bool:
	for seat in seats:
		if seat.alive and (seat.vel != Vector2.ZERO or seat.omega != 0.0):
			return false
	return true


func _resolve_pair(a: Seat, b: Seat, with_events: bool) -> void:
	var a_half := Vector2.RIGHT.rotated(a.angle) * PEN_HALF_LENGTH * ui_scale
	var b_half := Vector2.RIGHT.rotated(b.angle) * PEN_HALF_LENGTH * ui_scale
	var closest := _closest_segment_points(a.pos - a_half, a.pos + a_half, b.pos - b_half, b.pos + b_half)
	var point_a: Vector2 = closest[0]
	var point_b: Vector2 = closest[1]
	var radii := PEN_RADIUS * 2.0 * ui_scale
	var between := point_b - point_a
	var distance := between.length()
	if distance >= radii:
		return
	var normal := between / distance if distance > 0.001 else (b.pos - a.pos).normalized()
	if normal.length_squared() < 0.01:
		normal = Vector2.UP.rotated(a.angle)
	var contact := (point_a + point_b) * 0.5
	var arm_a := contact - a.pos
	var arm_b := contact - b.pos
	var mass_a := _mass_of(a)
	var mass_b := _mass_of(b)
	var inverse_a := 1.0 / mass_a
	var inverse_b := 1.0 / mass_b
	var inertia_a := _pen_inertia(mass_a)
	var inertia_b := _pen_inertia(mass_b)
	var relative_velocity := b.vel + _perpendicular(arm_b) * b.omega - a.vel - _perpendicular(arm_a) * a.omega
	var relative_normal_speed := relative_velocity.dot(normal)
	if relative_normal_speed < 0.0:
		# Rigid-body impulse between two hard plastic barrels: momentum is shared, never created.
		var impact_speed := -relative_normal_speed
		var attacker := a if a.vel.dot(normal) >= -b.vel.dot(normal) else b
		# Stiffer pens (the "punch" stat) bounce a little more; very hard hits lose a little more.
		var restitution := RESTITUTION + (float(attacker.skin["punch"]) - 1.0) - 0.08 * clampf(impact_speed / (1600.0 * ui_scale), 0.0, 1.0)
		var normal_cross_a := arm_a.cross(normal)
		var normal_cross_b := arm_b.cross(normal)
		var normal_mass := inverse_a + inverse_b + normal_cross_a * normal_cross_a / inertia_a + normal_cross_b * normal_cross_b / inertia_b
		var normal_impulse := (1.0 + restitution) * impact_speed / normal_mass
		_apply_pair_impulse(a, b, normal * normal_impulse, arm_a, arm_b)
		# Surface grip: a Coulomb friction impulse along the contact, at most PEN_GRIP times the push.
		# A glancing hit near the end of a pen drags that end along and sets it spinning.
		var tangent := Vector2(-normal.y, normal.x)
		var tangent_speed := (b.vel + _perpendicular(arm_b) * b.omega - a.vel - _perpendicular(arm_a) * a.omega).dot(tangent)
		var tangent_cross_a := arm_a.cross(tangent)
		var tangent_cross_b := arm_b.cross(tangent)
		var tangent_mass := inverse_a + inverse_b + tangent_cross_a * tangent_cross_a / inertia_a + tangent_cross_b * tangent_cross_b / inertia_b
		var grip := clampf(-tangent_speed / tangent_mass, -PEN_GRIP * normal_impulse, PEN_GRIP * normal_impulse)
		_apply_pair_impulse(a, b, tangent * grip, arm_a, arm_b)
		if with_events:
			_on_pen_contact(attacker, contact, normal, impact_speed)
	# Push the pens apart, the lighter one moving more.
	var overlap := radii - distance
	var share_a := inverse_a / (inverse_a + inverse_b)
	a.pos -= normal * overlap * share_a
	b.pos += normal * overlap * (1.0 - share_a)


func _mass_of(seat: Seat) -> float:
	return float(seat.skin["mass"]) * pow(BOOST_MASS, seat.boost)


func _apply_pair_impulse(a: Seat, b: Seat, impulse: Vector2, arm_a: Vector2, arm_b: Vector2) -> void:
	var mass_a := _mass_of(a)
	var mass_b := _mass_of(b)
	a.vel -= impulse / mass_a
	b.vel += impulse / mass_b
	a.omega = clampf(a.omega - arm_a.cross(impulse) / _pen_inertia(mass_a), -MAX_SPIN, MAX_SPIN)
	b.omega = clampf(b.omega + arm_b.cross(impulse) / _pen_inertia(mass_b), -MAX_SPIN, MAX_SPIN)


func _on_pen_contact(attacker: Seat, contact: Vector2, normal: Vector2, impact_speed: float) -> void:
	# The sound follows the contact itself: even a light touch is heard, in proportion to how hard it was.
	if impact_speed > 18.0 * ui_scale and sound_cooldown <= 0.0:
		var loudness := clampf(impact_speed / (1100.0 * ui_scale), 0.0, 1.0)
		sound_cooldown = 0.05
		Sfx.play("tap" if loudness < 0.3 else "clack", lerpf(-24.0, 0.0, pow(loudness, 0.6)), lerpf(0.95, 1.08, loudness))
	if impact_speed > 52.0 * ui_scale and impact_cooldown <= 0.0:
		var strength := clampf(impact_speed / (1100.0 * ui_scale), 0.0, 1.0)
		impact_cooldown = 0.22
		if strength > 0.45:
			_spawn_impact(contact, normal, strength, attacker.skin)
		if strength > 0.7:
			shake = maxf(shake, lerpf(1.5, 3.0, (strength - 0.7) / 0.3) * ui_scale)
		if attacker.index == 0 and strength > 0.45 and solid_hits < LEOS_HIT_CAP:
			solid_hits += 1
			_award(LEOS_HIT, "Solid hits")


func _closest_segment_points(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> Array[Vector2]:
	var d1 := a1 - a0
	var d2 := b1 - b0
	var r := a0 - b0
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 0.0001 and e <= 0.0001:
		return [a0, b0]
	if a <= 0.0001:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 0.0001:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denominator := a * e - b * b
			if absf(denominator) > 0.0001:
				s = clampf((b * f - c * e) / denominator, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return [a0 + d1 * s, b0 + d2 * t]


func _perpendicular(vector: Vector2) -> Vector2:
	return Vector2(-vector.y, vector.x)


func _pen_inertia(mass: float) -> float:
	var half := PEN_HALF_LENGTH * ui_scale
	var radius := PEN_RADIUS * ui_scale
	return maxf(1.0, mass * (half * half / 3.0 + radius * radius * 0.5))


func _apply_slide_friction(seat: Seat, delta: float, desk: Rect2) -> void:
	# Coulomb friction spread along the pen: every point on the body is dragged against its own
	# velocity at a constant rate. A straight slide slows steadily and stops; a slide with spin
	# skids and pivots, and the spin and the drift die out together, as with a real pen on a desk.
	# Points hanging past the edge touch nothing, so an overhanging pen grips less and pivots on the lip.
	var axis := Vector2.RIGHT.rotated(seat.angle)
	var side := _perpendicular(axis)
	var half := PEN_HALF_LENGTH * ui_scale
	var inertia := _pen_inertia(1.0)
	var point_decel := SLIDE_DECEL * ui_scale / float(FRICTION_POINTS)
	# Just enough smoothing that friction can't overshoot and flip the motion within one step.
	var smoothing := SLIDE_DECEL * ui_scale * delta * 1.5
	var linear_accel := Vector2.ZERO
	var angular_accel := 0.0
	for k in range(FRICTION_POINTS):
		var arm := axis * half * ((float(k) + 0.5) / float(FRICTION_POINTS) * 2.0 - 1.0)
		if not desk.has_point(seat.pos + arm):
			continue
		var point_velocity := seat.vel + _perpendicular(arm) * seat.omega
		var slip := point_velocity / maxf(point_velocity.length(), smoothing)
		# Lengthwise the barrel slides; sideways it partly rolls, which costs less.
		var point_accel := -(axis * slip.dot(axis) + side * slip.dot(side) * ROLL_RATIO) * point_decel
		linear_accel += point_accel
		angular_accel += arm.cross(point_accel) / inertia
	seat.vel += linear_accel * delta
	seat.omega += angular_accel * delta
	# Static friction: once it is barely moving, the pen just stops.
	if seat.vel.length() < SLEEP_SPEED * ui_scale and absf(seat.omega) < SLEEP_SPIN:
		seat.vel = Vector2.ZERO
		seat.omega = 0.0


# ------------------------------------------------------------------ computer players

func _plan_cpu_shot() -> void:
	# Skill comes from the level (see levels.gd) and sharpens a little each round. It sets how many
	# shots the computer weighs, how true its aim is, how often it picks a poor shot, how much it
	# cares about sliding its own pen off, and how far it looks ahead.
	cpu_plan.clear()
	var seat := seats[current]
	var skill := clampf(seat.skill + float(round_number - 1) * 0.03, 0.0, 1.0)
	if lag_active:
		_plan_cpu_lag_shot(seat, skill)
		return
	# Try shots along the other pens and keep the one that best shoves a pen toward an edge.
	var targets: Array[Seat] = []
	for other in seats:
		if other.alive and other != seat:
			targets.append(other)
	if targets.is_empty():
		return
	var half_length := PEN_HALF_LENGTH * ui_scale
	var best_score := -INF
	var best_direction := (targets[0].pos - seat.pos).normalized()
	var best_power := 0.7
	var candidates := roundi(lerpf(6.0, 44.0, skill))
	var jitter := lerpf(0.26, 0.015, skill)
	var whim := lerpf(170.0, 12.0, skill)
	var caution := lerpf(0.35, 1.0, skill)
	var shortlist: Array[Dictionary] = []
	for i in range(candidates):
		var target := targets[rng.randi() % targets.size()]
		var aim := target.pos + Vector2.RIGHT.rotated(target.angle) * half_length * rng.randf_range(-0.9, 0.9)
		var direction := (aim - seat.pos).normalized()
		var power := rng.randf_range(0.4, 1.0)
		var score := _score_cpu_shot(seat, targets, direction, power, jitter, caution) + rng.randf_range(0.0, whim)
		shortlist.append({"direction": direction, "power": power, "score": score})
		if score > best_score:
			best_score = score
			best_direction = direction
			best_power = power
	# From the middle levels up, the computer plays its best few ideas forward with the real physics
	# before it chooses, and near the top it fine-tunes the winner too: this is what makes level 50
	# the hardest. Lower levels go on the quick estimate alone. The look-ahead runs a couple of shots
	# a frame while the computer lines up (see _advance_cpu_plan), so thinking never stalls the screen.
	cpu_plan = {
		"seat": seat, "skill": skill, "jitter": jitter, "whim": whim,
		"direction": best_direction, "power": best_power, "score": -INF, "queue": [], "refine": 0,
	}
	var depth := pow(clampf((skill - 0.35) / 0.65, 0.0, 1.0), 1.5)
	var lookahead := roundi(12.0 * depth)
	if lookahead > 0:
		shortlist.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
		cpu_plan["queue"] = shortlist.slice(0, lookahead)
		cpu_plan["refine"] = roundi(lerpf(0.0, 8.0, smoothstep(0.8, 1.0, skill)))
	else:
		_finish_cpu_plan()


func _advance_cpu_plan() -> void:
	for k in range(ROLLOUTS_PER_FRAME):
		if cpu_plan.is_empty():
			return
		var seat: Seat = cpu_plan["seat"]
		var queue: Array = cpu_plan["queue"]
		var direction: Vector2 = cpu_plan["direction"]
		var power: float = cpu_plan["power"]
		if not queue.is_empty():
			var idea: Dictionary = queue.pop_front()
			direction = idea["direction"]
			power = idea["power"]
		elif int(cpu_plan["refine"]) > 0:
			# Fine-tuning: small changes around the best shot so far.
			cpu_plan["refine"] = int(cpu_plan["refine"]) - 1
			direction = direction.rotated(rng.randf_range(-0.05, 0.05))
			power = clampf(power + rng.randf_range(-0.1, 0.1), 0.3, 1.0)
		else:
			_finish_cpu_plan()
			return
		var score := _rollout_score(seat, direction, power) + rng.randf_range(0.0, float(cpu_plan["whim"]))
		if score > float(cpu_plan["score"]):
			cpu_plan["score"] = score
			cpu_plan["direction"] = direction
			cpu_plan["power"] = power


func _finish_cpu_plan() -> void:
	# The shot is chosen; now the hand isn't perfect: a little aim error, and the finger lands near
	# the middle of the pen, closer with skill, like a person's.
	var skill := float(cpu_plan["skill"])
	var jitter := float(cpu_plan["jitter"])
	cpu_shot_direction = Vector2(cpu_plan["direction"]).rotated(rng.randf_range(-jitter, jitter))
	cpu_shot_power = float(cpu_plan["power"])
	cpu_shot_offset = rng.randf_range(-1.0, 1.0) * lerpf(0.36, 0.05, skill) * PEN_HALF_LENGTH * ui_scale
	cpu_plan.clear()


func _plan_cpu_lag_shot(seat: Seat, skill: float) -> void:
	# Aim at the middle point with a little human error that shrinks with skill.
	var middle := _table_bounds().get_center()
	var to_middle := middle - seat.pos
	var angle_error := rng.randf_range(-1.0, 1.0) * lerpf(0.1, 0.012, skill)
	var travel_error := rng.randf_range(-1.0, 1.0) * lerpf(150.0, 16.0, skill) * ui_scale
	cpu_shot_direction = to_middle.normalized().rotated(angle_error)
	cpu_shot_offset = 0.0
	var wanted := maxf(to_middle.length() + travel_error, MIN_TRAVEL * ui_scale)
	cpu_shot_power = clampf((wanted / ui_scale - MIN_TRAVEL) / (MAX_TRAVEL - MIN_TRAVEL), 0.0, 1.0)


func _score_cpu_shot(seat: Seat, targets: Array[Seat], direction: Vector2, power: float, jitter: float, caution: float) -> float:
	var desk := _table_bounds()
	var travel := _travel_for_power(power)
	var path_end := seat.pos + direction * travel
	# The first pen on the path is the one that gets hit.
	var victim: Seat = null
	var contact := Vector2.ZERO
	var on_victim := Vector2.ZERO
	var nearest := INF
	for target in targets:
		var half := Vector2.RIGHT.rotated(target.angle) * PEN_HALF_LENGTH * ui_scale
		var closest := _closest_segment_points(seat.pos, path_end, target.pos - half, target.pos + half)
		var hit_contact: Vector2 = closest[0]
		var hit_point: Vector2 = closest[1]
		if hit_contact.distance_to(hit_point) <= PEN_RADIUS * 3.0 * ui_scale and seat.pos.distance_to(hit_contact) < nearest:
			nearest = seat.pos.distance_to(hit_contact)
			victim = target
			contact = hit_contact
			on_victim = hit_point
	if victim == null:
		# A miss only risks sliding our own pen off.
		return (-2000.0 * caution if not desk.has_point(path_end) else -150.0 - travel * 0.05) + _coin_value_on_path(seat.pos, path_end)
	var gap := contact.distance_to(on_victim)
	var remaining := maxf(0.0, travel - nearest)
	var normal := direction
	if gap > 1.0:
		normal = (on_victim - contact) / gap
	var push_direction := (normal * 0.6 + direction * 0.4).normalized()
	var victim_end := victim.pos + push_direction * remaining * 0.55
	# The shooter keeps a fair part of its slide after the hit, more when it strikes off-centre.
	var own_end := contact + direction * remaining * 0.35
	var score := _coin_value_on_path(seat.pos, contact)
	# Its own aim isn't perfect: if a slightly-off flick would miss and slide off, that is a real risk.
	for side in [-1.0, 1.0]:
		if not desk.has_point(seat.pos + direction.rotated(side * jitter) * travel):
			score -= 700.0 * caution
	if not desk.has_point(victim_end):
		score += 1000.0
	score += (_edge_distance(victim.pos) - _edge_distance(victim_end)) * 2.0
	if not desk.has_point(own_end):
		score -= 1500.0 * caution
	score -= maxf(0.0, 70.0 * ui_scale - _edge_distance(own_end)) * 4.0 * caution
	return score


func _rollout_score(shooter: Seat, direction: Vector2, power: float) -> float:
	# Play the shot forward on copies of the pens with the real friction and collisions (no sound,
	# no effects), then judge where everything ends up: pens knocked off, who is left near an edge.
	var desk := _table_bounds()
	var ghosts: Array[Seat] = []
	var own: Seat = null
	for seat in seats:
		if not seat.alive:
			continue
		var ghost := Seat.new()
		ghost.index = seat.index
		ghost.skin = seat.skin
		ghost.boost = seat.boost
		ghost.pos = seat.pos
		ghost.angle = seat.angle
		ghosts.append(ghost)
		if seat == shooter:
			own = ghost
	var kick := _flick_kick(own, direction, power, 0.0)
	own.vel = kick[0]
	own.omega = kick[1]
	for step in range(ROLLOUT_STEPS):
		var moving := false
		for ghost in ghosts:
			if ghost.alive:
				ghost.pos += ghost.vel * ROLLOUT_STEP
				ghost.angle = wrapf(ghost.angle + ghost.omega * ROLLOUT_STEP, -PI, PI)
				_apply_slide_friction(ghost, ROLLOUT_STEP, desk)
		for i in range(ghosts.size()):
			for j in range(i + 1, ghosts.size()):
				if ghosts[i].alive and ghosts[j].alive:
					_resolve_pair(ghosts[i], ghosts[j], false)
		for ghost in ghosts:
			if ghost.alive:
				if not desk.has_point(ghost.pos):
					ghost.alive = false
				elif ghost.vel != Vector2.ZERO or ghost.omega != 0.0:
					moving = true
		if not moving:
			break
	var score := 0.0
	var others_left := 0
	for ghost in ghosts:
		if ghost == own:
			continue
		if ghost.alive:
			others_left += 1
			score += maxf(0.0, 160.0 * ui_scale - _edge_distance(ghost.pos)) * 3.0
		else:
			score += 1000.0
	if not own.alive:
		# Going off together with the last opponent only replays the round; going off alone loses it.
		score -= 600.0 if others_left == 0 else 1800.0
	else:
		score -= maxf(0.0, 90.0 * ui_scale - _edge_distance(own.pos)) * 6.0
	return score + _coin_value_on_path(shooter.pos, own.pos) * 0.5


func _cpu_take_turn() -> void:
	while not cpu_plan.is_empty():
		_advance_cpu_plan()
	_launch(seats[current], cpu_shot_direction, cpu_shot_power, cpu_shot_offset)


# ------------------------------------------------------------------ power coins

func _maybe_spawn_coin() -> void:
	if coins.size() >= MAX_COINS or rng.randf() > COIN_SPAWN_CHANCE:
		return
	# Bigger values are rarer. Power-downs sit where they are easy to hit by accident;
	# power-ups sit where they are risky to reach.
	var roll := rng.randf()
	var size := 1 if roll < 0.5 else (2 if roll < 0.83 else 3)
	# Power-downs are the common ones; power-ups are rarer prizes.
	var value := size if rng.randf() < 0.3 else -size
	var spot := _coin_spot(value)
	if spot == Vector2.INF:
		return
	var life := rng.randf_range(5.0, 6.5)
	coins.append({"position": spot, "value": value, "life": life, "max_life": life, "age": 0.0})
	Sfx.play("tick", -10.0, 1.5 if value > 0 else 1.1)


func _coin_spot(value: int) -> Vector2:
	var desk := _table_bounds()
	var shooter := seats[current]
	var margin := (COIN_RADIUS + 14.0) * ui_scale
	var inner := desk.grow(-margin)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return Vector2.INF
	var best := Vector2.INF
	var best_score := -INF
	for attempt in range(40):
		var spot := Vector2(rng.randf_range(inner.position.x, inner.end.x), rng.randf_range(inner.position.y, inner.end.y))
		# Keep clear of the tabs and clock along the top and the hint card along the bottom.
		if spot.y < _safe().position.y + 170.0 * ui_scale or spot.y > _safe().end.y - 95.0 * ui_scale:
			continue
		if not _coin_spot_is_free(spot):
			continue
		var edge := _edge_distance(spot) / ui_scale
		var reach := shooter.pos.distance_to(spot) / ui_scale
		var score := 0.0
		if value > 0:
			# Close to the drop, and harder still for bigger coins: the higher the value, the closer to the lip.
			var wanted_edge := lerpf(150.0, 50.0, float(value - 1) / 2.0)
			score = -absf(edge - wanted_edge) * 2.0 + minf(reach, 600.0) * 0.3
			if _path_blocked(shooter, spot):
				score += 120.0
		else:
			# Right in the way: near the line from the shooter to another pen, out in the open.
			var line_gap := INF
			for other in seats:
				if other.alive and other != shooter:
					var closest := Geometry2D.get_closest_point_to_segment(spot, shooter.pos, other.pos)
					line_gap = minf(line_gap, closest.distance_to(spot) / ui_scale)
			score = -absf(line_gap - 70.0) * 2.0 + minf(edge, 250.0) * 0.4
		score += rng.randf_range(0.0, 30.0)
		if score > best_score:
			best_score = score
			best = spot
	return best


func _coin_spot_is_free(spot: Vector2) -> bool:
	for seat in seats:
		if seat.alive and _distance_to_pen(spot, seat) < (PEN_RADIUS + COIN_RADIUS + 26.0) * ui_scale:
			return false
	for coin in coins:
		if spot.distance_to(coin["position"]) < COIN_RADIUS * 5.0 * ui_scale:
			return false
	return true


func _path_blocked(shooter: Seat, spot: Vector2) -> bool:
	for other in seats:
		if other.alive and other != shooter:
			var half := Vector2.RIGHT.rotated(other.angle) * PEN_HALF_LENGTH * ui_scale
			var closest := _closest_segment_points(shooter.pos, spot, other.pos - half, other.pos + half)
			if closest[0].distance_to(closest[1]) < (PEN_RADIUS * 2.0 + 8.0) * ui_scale:
				return true
	return false


func _distance_to_pen(point: Vector2, seat: Seat) -> float:
	var half := Vector2.RIGHT.rotated(seat.angle) * PEN_HALF_LENGTH * ui_scale
	return Geometry2D.get_closest_point_to_segment(point, seat.pos - half, seat.pos + half).distance_to(point)


func _collect_coins(seat: Seat) -> void:
	for index in range(coins.size() - 1, -1, -1):
		var coin: Dictionary = coins[index]
		if _distance_to_pen(coin["position"], seat) > (PEN_RADIUS + COIN_RADIUS) * ui_scale:
			continue
		var value: int = coin["value"]
		seat.boost = clampi(seat.boost + value, -MAX_BOOST, MAX_BOOST)
		coins.remove_at(index)
		var color: Color = COIN_COLORS[value]
		var word := "POWER UP" if value > 0 else "POWER DOWN"
		coin_flashes.append({"position": coin["position"], "text": "%+d %s" % [value, word], "color": color, "life": 1.3})
		for k in range(8):
			sparks.append({
				"position": coin["position"],
				"velocity": Vector2.RIGHT.rotated(TAU * float(k) / 8.0) * rng.randf_range(90.0, 160.0) * ui_scale,
				"life": 0.3,
				"max_life": 0.3,
				"color": color.lightened(0.3),
				"shape": "dot"
			})
		if value > 0:
			Sfx.play("buy", -6.0, 1.0 + 0.08 * float(value))
		else:
			Sfx.play("knock", -4.0, 1.0 - 0.08 * float(-value))


func _update_coins(delta: float) -> void:
	for index in range(coin_flashes.size() - 1, -1, -1):
		coin_flashes[index]["life"] = float(coin_flashes[index]["life"]) - delta
		if float(coin_flashes[index]["life"]) <= 0.0:
			coin_flashes.remove_at(index)
	# Coins only count down while the game is in play, not over banners and round ends.
	if turn != Turn.AIM and turn != Turn.CPU_WAIT and turn != Turn.ROLL:
		return
	var desk := _table_bounds()
	for index in range(coins.size() - 1, -1, -1):
		var coin: Dictionary = coins[index]
		coin["age"] = float(coin["age"]) + delta
		coin["life"] = float(coin["life"]) - delta
		if float(coin["life"]) <= 0.0 or not desk.has_point(coin["position"]):
			coins.remove_at(index)


func _coin_value_on_path(from: Vector2, to: Vector2) -> float:
	# How the computer weighs the coins its own pen would slide over on the way.
	var total := 0.0
	for coin in coins:
		var closest := Geometry2D.get_closest_point_to_segment(coin["position"], from, to)
		if closest.distance_to(coin["position"]) < (PEN_RADIUS + COIN_RADIUS + 10.0) * ui_scale:
			total += float(coin["value"]) * 140.0
	return total


func _draw_coins() -> void:
	var s := ui_scale
	var now := Time.get_ticks_msec() * 0.001
	for coin in coins:
		var value: int = coin["value"]
		var life: float = coin["life"]
		var age: float = coin["age"]
		var color: Color = COIN_COLORS[value]
		var center: Vector2 = coin["position"]
		# Drops in from above with a little bounce.
		var appear := minf(1.0, age / 0.35)
		var drop := pow(1.0 - appear, 2.0) * 70.0 * s - sin(appear * PI) * 6.0 * s
		center.y += -drop + sin(age * 3.5 + center.x) * 3.0 * s
		var radius := COIN_RADIUS * s * (0.5 + 0.5 * appear)
		# Fades in and out while blinking in its last moments.
		var alpha := 1.0
		if life < 1.6:
			alpha = 0.35 + 0.65 * (0.5 + 0.5 * cos(life * 22.0))
		var pulse := 0.5 + 0.5 * sin(age * 6.0)
		# A ring bursts out when it lands.
		if age < 0.7:
			var burst := age / 0.7
			draw_arc(center, radius * (1.0 + 2.2 * burst), 0.0, TAU, 40, Color(color.r, color.g, color.b, 0.8 * (1.0 - burst)), 4.0 * s * (1.0 - burst) + 1.0, true)
		# Soft glow halo that breathes.
		for layer in range(3):
			var halo := radius * (1.35 + 0.28 * float(layer) + 0.18 * pulse)
			draw_circle(center, halo, Color(color.r, color.g, color.b, (0.16 - 0.04 * float(layer)) * alpha))
		if value > 0:
			# Power-ups shine: light rays turning slowly behind the coin, and twinkling stars.
			var ray_color := Color(color.lightened(0.45).r, color.lightened(0.45).g, color.lightened(0.45).b, 0.5 * alpha)
			for k in range(10):
				var a := age * 1.2 + TAU * float(k) / 10.0
				var tip := center + Vector2.RIGHT.rotated(a) * radius * (2.0 + 0.25 * pulse)
				var side := Vector2.RIGHT.rotated(a + PI * 0.5) * radius * 0.16
				draw_colored_polygon(PackedVector2Array([center + side, tip, center - side]), ray_color)
			for k in range(3):
				var twinkle := 0.5 + 0.5 * sin(now * 5.0 + float(k) * 2.1 + center.x)
				var star_pos := center + Vector2.RIGHT.rotated(float(k) * 2.2 + age * 0.6) * radius * 1.55
				UIKit.star(self, star_pos, (3.0 + 4.0 * twinkle) * s, Color(1.0, 1.0, 0.9, 0.9 * twinkle * alpha), s)
		else:
			# Power-downs warn: a spiky ring turning the other way.
			var spike_color := Color(color.r * 0.7, color.g * 0.6, color.b * 0.6, 0.75 * alpha)
			for k in range(12):
				var a := -age * 1.5 + TAU * float(k) / 12.0
				var base_point := center + Vector2.RIGHT.rotated(a) * radius * 1.25
				var tip := center + Vector2.RIGHT.rotated(a) * radius * (1.55 + 0.1 * pulse)
				var side := Vector2.RIGHT.rotated(a + PI * 0.5) * radius * 0.12
				draw_colored_polygon(PackedVector2Array([base_point + side, tip, base_point - side]), spike_color)
		# Time left drains as a ring around the coin.
		var left := clampf(life / float(coin["max_life"]), 0.0, 1.0)
		draw_arc(center, radius + 8.0 * s, 0.0, TAU, 44, Color(INK.r, INK.g, INK.b, 0.25 * alpha), 4.0 * s, true)
		draw_arc(center, radius + 8.0 * s, -PI * 0.5, -PI * 0.5 + TAU * left, 44, Color(1.0, 0.98, 0.9, 0.95 * alpha), 4.0 * s, true)
		# The coin itself turns over now and then, like a spun coin.
		var cycle := fmod(age + float(value) * 0.37, 2.4)
		var flip := absf(cos(clampf((cycle - 1.9) / 0.5, 0.0, 1.0) * TAU * 0.5)) if cycle > 1.9 else 1.0
		flip = maxf(flip, 0.12)
		draw_circle(center + Vector2(4.0, 6.0) * s, radius, Color(0.1, 0.05, 0.02, 0.3 * alpha))
		draw_set_transform(center, 0.0, Vector2(flip, 1.0))
		draw_circle(Vector2.ZERO, radius + 3.0 * s, Color(INK.r, INK.g, INK.b, alpha))
		draw_circle(Vector2.ZERO, radius, Color(color.r, color.g, color.b, alpha))
		draw_circle(Vector2.ZERO, radius * 0.78, Color(color.darkened(0.12).r, color.darkened(0.12).g, color.darkened(0.12).b, alpha))
		draw_arc(Vector2.ZERO, radius * 0.78, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.45 * alpha), 2.0 * s, true)
		# A glint sweeps across the face.
		var glint := fmod(age * 0.8, 1.0)
		draw_arc(Vector2.ZERO, radius * 0.9, PI * (1.05 + glint), PI * (1.35 + glint), 12, Color(1.0, 1.0, 1.0, 0.7 * alpha), 3.0 * s, true)
		if flip > 0.55:
			var label := "%+d" % value
			var font_size := roundi(radius * 1.05)
			var origin := Vector2(-radius - 1.0 * s, font_size * 0.36)
			draw_string_outline(FONT, origin, label, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, font_size, roundi(6.0 * s), Color(INK.r, INK.g, INK.b, alpha))
			_draw_bold_string(origin, label, font_size, Color(1.0, 0.98, 0.94, alpha), radius * 2.0, HORIZONTAL_ALIGNMENT_CENTER)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_power_chip(center: Vector2, value: int, radius: float) -> void:
	var color: Color = COIN_COLORS[clampi(value, -MAX_BOOST, MAX_BOOST)]
	draw_circle(center, radius + 2.0 * ui_scale, INK)
	draw_circle(center, radius, color)
	var label := "%+d" % value
	var font_size := roundi(radius * 1.0)
	_draw_bold_string(Vector2(center.x - radius, center.y + font_size * 0.36), label, font_size, Color("#fffaf0"), radius * 2.0, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_coin_flashes() -> void:
	for flash in coin_flashes:
		var life: float = flash["life"]
		var rise := (1.3 - life) * 46.0 * ui_scale
		var alpha := clampf(life / 0.5, 0.0, 1.0)
		var color: Color = flash["color"]
		var width := 240.0 * ui_scale
		var origin: Vector2 = flash["position"] + Vector2(-width * 0.5, -34.0 * ui_scale - rise)
		var font_size := roundi(20.0 * ui_scale)
		draw_string_outline(FONT, origin, flash["text"], HORIZONTAL_ALIGNMENT_CENTER, width, font_size, roundi(7.0 * ui_scale), Color(INK.r, INK.g, INK.b, alpha))
		draw_string(FONT, origin, flash["text"], HORIZONTAL_ALIGNMENT_CENTER, width, font_size, Color(color.lightened(0.45).r, color.lightened(0.45).g, color.lightened(0.45).b, alpha))


# ------------------------------------------------------------------ leos

func _award(amount: int, reason: String) -> void:
	match_earned += amount
	earn_breakdown[reason] = int(earn_breakdown.get(reason, 0)) + amount
	popups.append({"text": "+%d  %s" % [amount, reason], "life": 2.4})
	Sfx.play("coin", -8.0)
	Profile.add_leos(amount)


# ------------------------------------------------------------------ effects

func _record_trail(seat: Seat, rolling: bool) -> void:
	# Only a faint blur behind a fast pen.
	if rolling and seat.alive and seat.vel.length() > 700.0 * ui_scale:
		seat.trail.append({"position": seat.pos, "angle": seat.angle})
		if seat.trail.size() > 4:
			seat.trail.pop_front()
	elif not seat.trail.is_empty():
		seat.trail.pop_front()


func _spawn_impact(point: Vector2, normal: Vector2, strength: float, skin: Dictionary = {}) -> void:
	impact_position = point
	impact_timer = 0.3
	var spark_a := Color("#ffc23a")
	var spark_b := Color("#e8553a")
	var shape := "line"
	var rainbow := false
	if not skin.is_empty():
		spark_a = skin["spark_a"]
		spark_b = skin["spark_b"]
		shape = skin["spark_shape"]
		rainbow = skin["rainbow"]
	var count := roundi(lerpf(4.0, 11.0, strength))
	for i in range(count):
		var angle := TAU * float(i) / float(count) + rng.randf_range(-0.12, 0.12)
		var direction := Vector2.RIGHT.rotated(angle)
		if i % 2 == 0:
			direction = normal.rotated(rng.randf_range(-0.9, 0.9))
		var particle_color := spark_a if i % 3 != 0 else spark_b
		if rainbow:
			particle_color = Color.from_hsv(rng.randf(), 0.75, 1.0)
		sparks.append({
			"position": point,
			"velocity": direction * rng.randf_range(80.0, 200.0) * lerpf(0.8, 1.2, strength) * ui_scale,
			"life": rng.randf_range(0.15, 0.28),
			"max_life": 0.28,
			"color": particle_color,
			"shape": shape
		})


func _update_effects(delta: float) -> void:
	impact_timer = maxf(0.0, impact_timer - delta)
	impact_cooldown = maxf(0.0, impact_cooldown - delta)
	sound_cooldown = maxf(0.0, sound_cooldown - delta)
	lag_result_timer = maxf(0.0, lag_result_timer - delta)
	for index in range(popups.size() - 1, -1, -1):
		popups[index]["life"] = float(popups[index]["life"]) - delta
		if float(popups[index]["life"]) <= 0.0:
			popups.remove_at(index)
	for index in range(sparks.size() - 1, -1, -1):
		var particle: Dictionary = sparks[index]
		particle["life"] = float(particle["life"]) - delta
		var particle_position: Vector2 = particle["position"]
		var particle_velocity: Vector2 = particle["velocity"]
		particle["position"] = particle_position + particle_velocity * delta
		particle["velocity"] = particle_velocity * exp(-3.8 * delta) + Vector2(0, 160.0 * ui_scale * delta)
		if float(particle["life"]) <= 0.0:
			sparks.remove_at(index)
		else:
			sparks[index] = particle

















# ------------------------------------------------------------------ layout of the HUD

func _safe() -> Rect2:
	return UIKit.safe_rect(self)


func _hud_margin() -> float:
	return 16.0 * ui_scale


func _leos_rect() -> Rect2:
	var s := ui_scale
	var width := UIKit.heavy_width(str(Profile.leos), roundi(24.0 * s)) + 74.0 * s
	var safe := _safe()
	return Rect2(safe.position.x + _hud_margin(), safe.end.y - 14.0 * s - 58.0 * s, width, 58.0 * s)


func _pause_rect() -> Rect2:
	var s := ui_scale
	var safe := _safe()
	var size := 72.0 * s
	return Rect2(safe.end.x - _hud_margin() - size, safe.end.y - 12.0 * s - size, size, size)


func _result_card_rect() -> Rect2:
	# Matches against the computer leave room for the level bar.
	var height := 560.0 if vs_cpu else 500.0
	var card_size := Vector2(minf(580.0 * ui_scale, screen_size.x - 40.0 * ui_scale), minf(height * ui_scale, screen_size.y - 70.0 * ui_scale))
	return Rect2(screen_size * 0.5 - card_size * 0.5 + Vector2(0.0, 18.0 * ui_scale), card_size)


func _result_button_rect() -> Rect2:
	var card := _result_card_rect()
	var width := (card.size.x - 72.0 * ui_scale) * 0.5
	return Rect2(card.position.x + 24.0 * ui_scale, card.end.y - 96.0 * ui_scale, width, 74.0 * ui_scale)


func _result_lobby_rect() -> Rect2:
	var button := _result_button_rect()
	return Rect2(button.end.x + 24.0 * ui_scale, button.position.y, button.size.x, button.size.y)


func _pause_card_rect() -> Rect2:
	var card_size := Vector2(420.0, 412.0 if _quit_counts() else 380.0) * ui_scale
	return Rect2(screen_size * 0.5 - card_size * 0.5 + Vector2(0.0, 14.0 * ui_scale), card_size)


func _pause_buttons() -> Dictionary:
	var s := ui_scale
	var card := _pause_card_rect()
	var width := card.size.x - 100.0 * s
	var x := card.get_center().x - width * 0.5
	var y := card.position.y + 70.0 * s
	var buttons := {}
	for key in ["resume", "restart", "lobby"]:
		buttons[key] = Rect2(x, y, width, 76.0 * s)
		y += 76.0 * s + 22.0 * s
	return buttons


func _hud_layout() -> Dictionary:
	# Player cards along the top, two per side, with the round ribbon in the middle.
	var s := ui_scale
	var count := seats.size()
	var safe := _safe()
	var margin := _hud_margin()
	var gap := 10.0 * s
	var top := safe.position.y + 10.0 * s
	var per_side := ceili(float(count) / 2.0)
	var side_width := screen_size.x * 0.5 - safe.position.x - margin - 175.0 * s
	var card_width := minf(250.0 * s, (side_width - gap * float(per_side - 1)) / float(per_side))
	var chips: Array[Rect2] = []
	for i in range(count):
		var slot := floori(float(i) / 2.0)
		var x := safe.position.x + margin + float(slot) * (card_width + gap) if i % 2 == 0 else safe.end.x - margin - card_width - float(slot) * (card_width + gap)
		chips.append(Rect2(x, top, card_width, 70.0 * s))
	return {"chips": chips, "ribbon": Vector2(screen_size.x * 0.5, top + 26.0 * s)}


# ------------------------------------------------------------------ drawing: wrappers

func _draw_round_rect(rect: Rect2, radius: float, fill: Color, outline: Color = Color.TRANSPARENT, outline_width: float = 0.0) -> void:
	UIKit.round_rect(self, rect, radius, fill, outline, outline_width)


func _draw_bold_string(pos: Vector2, label: String, font_size: int, color: Color, width: float = -1.0, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	UIKit.bold_string(self, pos, label, font_size, color, ui_scale, width, alignment)


func _draw_coin(center: Vector2, radius: float) -> void:
	UIKit.coin(self, center, radius, ui_scale)


# ------------------------------------------------------------------ drawing: the world

func _draw() -> void:
	if screen_size.x <= 0.0 or seats.is_empty():
		return
	UIKit.desk(self, screen_size, _table_bounds(), ui_scale, _full_bounds())
	_draw_target()
	_draw_shrink_warning()
	_draw_coins()
	for seat in seats:
		if seat.alive:
			PenArt.trail(self, seat.trail, seat.skin, ui_scale)
	_draw_turn_glow()
	for seat in seats:
		if seat.falling:
			_draw_pen(seat)
	for seat in seats:
		if seat.alive:
			_draw_pen(seat)
	_draw_pen_labels()
	_draw_turn_timer()
	_draw_lag_result()
	_draw_aim()
	_draw_cpu_aim()
	_draw_impact()
	_draw_sparks()
	_draw_coin_flashes()
	_draw_hud()
	_draw_bottom_hint()
	_draw_corner_buttons()
	if toast_timer > 0.0:
		_draw_toast()
	if banner_timer > 0.0:
		_draw_banner()
	_draw_leos_tab()
	_draw_popups()
	if turn == Turn.MATCH_END:
		_draw_result()
		if levelup_active:
			_draw_levelup()
	elif paused:
		_draw_pause()
	_draw_confetti()
	if fade > 0.0:
		draw_rect(Rect2(Vector2(-40.0, -40.0), screen_size + Vector2(80.0, 80.0)), Color(UIKit.SKY_BOTTOM.r, UIKit.SKY_BOTTOM.g, UIKit.SKY_BOTTOM.b, fade))


func _draw_target() -> void:
	# The middle point of the desk: the aim of the opening shot, and a quiet mark afterwards.
	var s := ui_scale
	var middle := _table_bounds().get_center()
	var emphasis := 1.0 if lag_active else 0.0
	var pulse := (sin(Time.get_ticks_msec() * 0.006) + 1.0) * 0.5 * emphasis
	var ring := Color(0.55, 0.2, 0.12, 0.3 + 0.35 * emphasis)
	draw_circle(middle, 18.0 * s, Color(0.78, 0.25, 0.18, 0.2 + 0.2 * emphasis))
	draw_arc(middle, 18.0 * s, 0.0, TAU, 32, ring, 3.0 * s, true)
	draw_arc(middle, 44.0 * s, 0.0, TAU, 48, ring, 2.5 * s, true)
	draw_arc(middle, 72.0 * s, 0.0, TAU, 56, Color(ring.r, ring.g, ring.b, ring.a * 0.8), 2.0 * s, true)
	if lag_active:
		draw_arc(middle, (80.0 + 12.0 * pulse) * s, 0.0, TAU, 56, Color(0.78, 0.25, 0.18, 0.5 * (1.0 - pulse)), 3.0 * s, true)
	for k in range(4):
		var direction := Vector2.RIGHT.rotated(float(k) * PI * 0.5)
		draw_line(middle + direction * 8.0 * s, middle + direction * 26.0 * s, ring, 2.0 * s, true)
	draw_circle(middle, 4.5 * s, INK)


func _draw_turn_glow() -> void:
	# A glow in the seat color marks the pen that is about to shoot.
	if turn != Turn.AIM and turn != Turn.CPU_WAIT:
		return
	var seat := seats[current]
	if not seat.alive:
		return
	# A glowing shadow in the player's color pools under the pen, breathing, with a bright rim.
	var s := ui_scale
	var pulse := (sin(Time.get_ticks_msec() * 0.006) + 1.0) * 0.5
	var axis := Vector2.RIGHT.rotated(seat.angle) * PEN_HALF_LENGTH * s
	var glow := seat.color
	for layer in range(4):
		var width := (PEN_RADIUS * 2.0 + 14.0 + 13.0 * float(layer) + 8.0 * pulse) * s
		var color := Color(glow.r, glow.g, glow.b, (0.6 - 0.12 * float(layer)) * (0.75 + 0.25 * pulse))
		draw_line(seat.pos - axis, seat.pos + axis, color, width, true)
		draw_circle(seat.pos - axis, width * 0.5, color)
		draw_circle(seat.pos + axis, width * 0.5, color)
	# The rim: a bright capsule outline around the pen.
	var rim := (PEN_RADIUS + 8.0) * s
	var rim_color := Color(1.0, 1.0, 1.0, 0.55 + 0.35 * pulse)
	var side := Vector2(-axis.y, axis.x).normalized() * rim
	draw_line(seat.pos - axis + side, seat.pos + axis + side, rim_color, 3.0 * s, true)
	draw_line(seat.pos - axis - side, seat.pos + axis - side, rim_color, 3.0 * s, true)
	draw_arc(seat.pos + axis, rim, seat.angle - PI * 0.5, seat.angle + PI * 0.5, 16, rim_color, 3.0 * s, true)
	draw_arc(seat.pos - axis, rim, seat.angle + PI * 0.5, seat.angle + PI * 1.5, 16, rim_color, 3.0 * s, true)


func _draw_pen(seat: Seat) -> void:
	if not seat.alive:
		_draw_falling_pen(seat)
		return
	if seat.boost != 0:
		# A charged pen glows: cool for power up, warm for power down.
		var glow: Color = COIN_COLORS[clampi(seat.boost, -MAX_BOOST, MAX_BOOST)]
		var pulse := (sin(Time.get_ticks_msec() * 0.008) + 1.0) * 0.5
		var axis := Vector2.RIGHT.rotated(seat.angle) * PEN_HALF_LENGTH * ui_scale
		var glow_color := Color(glow.r, glow.g, glow.b, 0.2 + 0.12 * pulse)
		for layer in range(2):
			# Two soft rounded layers: wider and fainter outside.
			var width := (PEN_RADIUS * 2.0 + 10.0 + 6.0 * absf(seat.boost) + 12.0 * float(layer)) * ui_scale
			var color := Color(glow_color.r, glow_color.g, glow_color.b, glow_color.a * (1.0 - 0.5 * float(layer)))
			draw_line(seat.pos - axis, seat.pos + axis, color, width, true)
			draw_circle(seat.pos - axis, width * 0.5, color)
			draw_circle(seat.pos + axis, width * 0.5, color)
	var shadow := Color(0.055, 0.03, 0.018, 0.42)
	draw_set_transform(seat.pos + Vector2(5.0, 9.0) * ui_scale, seat.angle, Vector2.ONE)
	PenArt.body(self, seat.skin, ui_scale, shadow, true)
	draw_set_transform(seat.pos, seat.angle, Vector2.ONE)
	PenArt.body(self, seat.skin, ui_scale, Color.WHITE, false)
	PenArt.idle(self, seat.skin, float(seat.index) * 1.7, ui_scale)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_falling_pen(seat: Seat) -> void:
	# The pen tips over the edge it crossed: it keeps the slide and spin it had, pitches down
	# about the lip (seen from above it gets shorter across the edge), drops away from its
	# shadow and lands on the floor below.
	var s := ui_scale
	var t := clampf(seat.fall_t, 0.0, 1.0)
	var time := t * FALL_DURATION
	# The lip catches it, so most of the slide is lost as it tips; it carries on only a little way.
	var carry := (1.0 - exp(-8.0 * time)) / 8.0
	var tip := smoothstep(0.0, 0.8, t)
	var spot := seat.fall_start + seat.fall_vel.limit_length(300.0 * s) * carry + seat.fall_dir * 10.0 * s * tip
	var angle := seat.fall_angle + seat.fall_spin * carry
	var opacity := 1.0 - smoothstep(0.7, 1.0, t)
	var drop := 1.0 - 0.14 * tip
	# Foreshorten along the edge normal as the pen pitches down by up to 80°.
	var squash := 1.0 - (1.0 - cos(deg_to_rad(80.0) * tip))
	var n := seat.fall_dir
	var axis := Vector2.RIGHT.rotated(angle) * drop
	var side := Vector2.DOWN.rotated(angle) * drop
	axis -= n * axis.dot(n) * (1.0 - squash)
	side -= n * side.dot(n) * (1.0 - squash)
	# The shadow stays on the floor and drifts away from the pen as it drops.
	var shadow_offset := Vector2(5.0, 9.0) * s + (n * 18.0 + Vector2(6.0, 14.0)) * s * tip
	draw_set_transform_matrix(Transform2D(axis, side, spot + shadow_offset))
	PenArt.body(self, seat.skin, s, Color(0.055, 0.03, 0.018, 0.42 * opacity * (1.0 - 0.5 * tip)), true)
	draw_set_transform_matrix(Transform2D(axis, side, spot))
	PenArt.body(self, seat.skin, s, Color(1.0, 1.0, 1.0, opacity), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if seat.fall_thud:
		# A small puff of dust where it lands.
		var puff_t := clampf((t - 0.8) / 0.2, 0.0, 1.0)
		for puff in range(4):
			var puff_direction := Vector2.RIGHT.rotated(float(puff) * 1.57 + 0.6)
			draw_circle(spot + puff_direction * (10.0 + 24.0 * puff_t) * s, (5.0 + 8.0 * puff_t) * s, Color(0.17, 0.10, 0.06, 0.14 * (1.0 - puff_t)))


func _label_offset(angle: float) -> float:
	# Keep the name clear of the pen body however it is rotated.
	return absf(sin(angle)) * PEN_HALF_LENGTH * ui_scale + PEN_RADIUS * ui_scale + 26.0 * ui_scale


func _draw_pen_labels() -> void:
	var s := ui_scale
	var desk := _table_bounds()
	var half_label := 110.0 * s
	for seat in seats:
		if not seat.alive:
			continue
		var below := seat.index % 2 == 0
		var label_y := seat.pos.y + _label_offset(seat.angle) if below else seat.pos.y - _label_offset(seat.angle)
		if label_y > desk.end.y - 20.0 * s or label_y < _safe().position.y + 110.0 * s:
			label_y = seat.pos.y - _label_offset(seat.angle) if below else seat.pos.y + _label_offset(seat.angle)
		var center := Vector2(clampf(seat.pos.x, half_label, screen_size.x - half_label), label_y)
		var font_size := roundi(22.0 * s)
		var width := 220.0 * s
		var origin := Vector2(center.x - width * 0.5 + 10.0 * s, center.y + font_size * 0.35)
		var label_width := UIKit.text_width(seat.label, font_size)
		UIKit.title(self, origin, seat.label, font_size, Color("#fffaf0"), width, HORIZONTAL_ALIGNMENT_CENTER, INK, roundi(8.0 * s))
		var dot := Vector2(center.x + 10.0 * s - label_width * 0.5 - 14.0 * s, center.y)
		draw_circle(dot, 7.5 * s, INK)
		draw_circle(dot, 5.5 * s, seat.color)
		if seat.boost != 0:
			# The power this pen carries into its next shot.
			var chip_center := Vector2(center.x + 10.0 * s + label_width * 0.5 + 26.0 * s, center.y)
			_draw_power_chip(chip_center, seat.boost, 15.0 * s)


func _draw_lag_result() -> void:
	if lag_result_timer <= 0.0:
		return
	var alpha := clampf(lag_result_timer / 0.6, 0.0, 1.0)
	var middle := _table_bounds().get_center()
	for seat in seats:
		if seat.alive:
			_draw_lag_line(middle, seat, alpha)


func _draw_lag_line(middle: Vector2, seat: Seat, alpha: float) -> void:
	var s := ui_scale
	var color := seat.color
	draw_dashed_line(middle, seat.pos, Color(INK.r, INK.g, INK.b, 0.7 * alpha), 4.5 * s, 10.0 * s)
	draw_dashed_line(middle, seat.pos, Color(color.r, color.g, color.b, alpha), 2.5 * s, 10.0 * s)
	var label := "%d" % roundi(seat.lag_distance / s)
	var label_width := 90.0 * s
	var label_origin := middle.lerp(seat.pos, 0.5) + Vector2(-label_width * 0.5, -10.0 * s)
	draw_string_outline(FONT, label_origin, label, HORIZONTAL_ALIGNMENT_CENTER, label_width, roundi(20.0 * s), roundi(7.0 * s), Color(INK.r, INK.g, INK.b, alpha))
	draw_string(FONT, label_origin, label, HORIZONTAL_ALIGNMENT_CENTER, label_width, roundi(20.0 * s), Color(color.r, color.g, color.b, alpha).lightened(0.35))


func _draw_aim() -> void:
	if not dragging or turn != Turn.AIM:
		return
	var s := ui_scale
	var seat := seats[current]
	var pull := drag_end - drag_origin
	var pull_length := pull.length()
	draw_arc(drag_origin, 42.0 * s, 0.0, TAU, 40, Color(INK.r, INK.g, INK.b, 0.35), 2.0 * s, true)
	var kick := [Vector2.ZERO, 0.0]
	if shot_power >= 0.08:
		kick = _flick_kick(seat, launch_direction, shot_power, flick_offset)
		# Play the flick forward on this pen alone: the dotted line is where it really goes,
		# curving when the finger strikes off-centre, and the ghost is where it comes to rest.
		var preview := _simulate_slide(seat, kick[0], kick[1])
		var path: PackedVector2Array = preview["path"]
		var landing: Vector2 = preview["position"]
		var risky: bool = preview["falls"]
		draw_set_transform(landing, float(preview["angle"]), Vector2.ONE)
		PenArt.body(self, seat.skin, s, Color(1.0, 0.55, 0.5, 0.32) if risky else Color(1.0, 1.0, 1.0, 0.3), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for k in range(0, path.size() - 1, 2):
			draw_line(path[k], path[k + 1], Color(INK.r, INK.g, INK.b, 0.55), 3.0 * s, true)
		var arrow_start := seat.pos + launch_direction * 40.0 * s
		var arrow_end := seat.pos + launch_direction * clampf(seat.pos.distance_to(landing), 100.0 * s, 170.0 * s)
		UIKit.fat_arrow(self, arrow_start, arrow_end, UIKit.POWER_RED, s)
		if risky:
			var label_width := 200.0 * s
			var label_origin := landing + Vector2(-label_width * 0.5, -34.0 * s)
			draw_string_outline(FONT, label_origin, "Off the edge!", HORIZONTAL_ALIGNMENT_CENTER, label_width, roundi(18.0 * s), roundi(7.0 * s), INK)
			draw_string(FONT, label_origin, "Off the edge!", HORIZONTAL_ALIGNMENT_CENTER, label_width, roundi(18.0 * s), Color("#ffe2d8"))
	if pull_length > 6.0 * s:
		var pull_direction := pull / pull_length
		var bar_end := drag_origin + pull_direction * minf(pull_length, MAX_PULL * s)
		draw_circle(drag_end, 17.0 * s, Color(UIKit.POWER_RED.r, UIKit.POWER_RED.g, UIKit.POWER_RED.b, 0.28))
		draw_arc(drag_end, 17.0 * s, 0.0, TAU, 24, Color(UIKit.POWER_RED.r, UIKit.POWER_RED.g, UIKit.POWER_RED.b, 0.7), 2.0 * s, true)
		UIKit.power_bar(self, drag_origin, bar_end, s)
		UIKit.power_badge(self, bar_end + pull_direction * 40.0 * s, roundi(shot_power * 100.0), s)
	if absf(float(kick[1])) > 1.0:
		UIKit.spin_arrow(self, drag_origin, float(kick[1]) * 0.25, s)
	# The dot is where the finger strikes the pen.
	draw_circle(drag_origin, 14.0 * s, INK)
	draw_circle(drag_origin, 10.5 * s, Color("#fffaf0"))


func _draw_cpu_aim() -> void:
	# Telegraph the computer's shot just before it fires, once it has made up its mind.
	if turn != Turn.CPU_WAIT or turn_timer > 0.55 or not cpu_plan.is_empty():
		return
	var s := ui_scale
	var seat := seats[current]
	var t := 1.0 - clampf(turn_timer / 0.55, 0.0, 1.0)
	var start := seat.pos + cpu_shot_direction * 40.0 * s
	var finish := start + cpu_shot_direction * lerpf(50.0, 190.0, t) * s
	UIKit.fat_arrow(self, start, finish, seat.color, s)


func _draw_impact() -> void:
	if impact_timer <= 0.0:
		return
	# Just a brief soft flash where the barrels met.
	var progress := 1.0 - impact_timer / 0.3
	var fade := 1.0 - progress
	draw_circle(impact_position, (6.0 + 14.0 * progress) * ui_scale, Color(1.0, 0.95, 0.8, 0.3 * fade * fade))
	draw_arc(impact_position, (8.0 + 26.0 * progress) * ui_scale, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.45 * fade), 2.0 * ui_scale, true)


func _draw_sparks() -> void:
	for particle in sparks:
		var life_ratio := clampf(float(particle["life"]) / float(particle["max_life"]), 0.0, 1.0)
		var spark_position: Vector2 = particle["position"]
		var velocity: Vector2 = particle["velocity"]
		var color: Color = particle["color"]
		color.a *= life_ratio
		var shape: String = particle["shape"]
		if shape == "dot":
			draw_circle(spark_position, (2.5 + 3.5 * life_ratio) * ui_scale, color)
		elif shape == "star":
			UIKit.star(self, spark_position, (4.0 + 5.0 * life_ratio) * ui_scale, color, ui_scale)
		else:
			var trail := velocity.normalized() * (5.0 + 9.0 * life_ratio) * ui_scale
			draw_line(spark_position, spark_position - trail, color, 2.0 * ui_scale, true)


# ------------------------------------------------------------------ drawing: the HUD

func _draw_hud() -> void:
	var layout := _hud_layout()
	var chips: Array[Rect2] = layout["chips"]
	for i in range(seats.size()):
		var is_active := (turn == Turn.AIM or turn == Turn.CPU_WAIT) and current == i and not lag_active
		_draw_score_chip(chips[i], seats[i], is_active)
	_draw_turn_pill(layout["ribbon"])


func _clock_color(left: float) -> Color:
	if left > 0.5:
		return UIKit.BTN_GREEN
	return UIKit.BTN_RED if left <= 0.3 else UIKit.BTN_YELLOW


func _draw_turn_timer() -> void:
	# Over the pen whose turn it is: a shrinking ring and the seconds left, louder near the end.
	if turn != Turn.AIM or paused or banner_timer > 0.3:
		return
	var s := ui_scale
	var seat := seats[current]
	var left := clampf(turn_left / TURN_TIME, 0.0, 1.0)
	var second := ceili(turn_left)
	var pulse := 1.0 + (0.25 * pow(fmod(turn_left, 1.0), 3.0) if second <= 3 else 0.0)
	var center := seat.pos + Vector2(0.0, -_label_offset(seat.angle) - 26.0 * s)
	var safe := _safe()
	center.x = clampf(center.x, safe.position.x + 60.0 * s, safe.end.x - 60.0 * s)
	center.y = clampf(center.y, safe.position.y + 180.0 * s, safe.end.y - 110.0 * s)
	var radius := 24.0 * s * pulse
	var color := _clock_color(left)
	draw_circle(center + Vector2(0.0, 3.0 * s), radius + 4.0 * s, Color(0.0, 0.0, 0.1, 0.3))
	draw_circle(center, radius + 4.0 * s, INK)
	draw_circle(center, radius, Color("#fffaf0"))
	draw_arc(center, radius - 4.0 * s, -PI * 0.5, -PI * 0.5 + TAU * left, 36, color, 6.0 * s, true)
	var size := roundi(22.0 * s * pulse)
	UIKit.title(self, Vector2(center.x - radius, center.y + size * 0.36), str(maxi(second, 0)), size, INK if second > 3 else UIKit.BTN_RED, radius * 2.0, HORIZONTAL_ALIGNMENT_CENTER, INK, 0, false)


func _draw_score_chip(rect: Rect2, seat: Seat, active: bool) -> void:
	var s := ui_scale
	var t := Time.get_ticks_msec() * 0.001
	if active:
		# The pen whose turn it is: its card lifts, glows and gets a bouncing arrow.
		rect.position.y += -3.0 * s + sin(t * 6.0) * 2.0 * s
		var glow := 0.5 + 0.5 * sin(t * 5.0)
		UIKit.round_rect(self, rect.grow(6.0 * s), 26.0 * s, Color(seat.color.r, seat.color.g, seat.color.b, 0.45 + 0.35 * glow))
		var tip := Vector2(rect.get_center().x, rect.end.y + 22.0 * s + absf(sin(t * 6.0)) * 6.0 * s)
		UIKit.outlined_polygon(self, PackedVector2Array([tip, tip + Vector2(-13.0, -15.0) * s, tip + Vector2(13.0, -15.0) * s]), seat.color, 3.0 * s)
	var out := not seat.alive and turn != Turn.MATCH_END
	var face := UIKit.PANEL if not out else Color("#d8d2e2")
	UIKit.round_rect(self, Rect2(rect.position + Vector2(0.0, 8.0 * s), rect.size), 22.0 * s, Color(0.0, 0.0, 0.1, 0.25))
	UIKit.round_rect(self, Rect2(rect.position + Vector2(0.0, 5.0 * s), rect.size), 22.0 * s, face.darkened(0.3), INK, 3.0 * s)
	UIKit.round_rect(self, rect, 22.0 * s, face, INK, 3.0 * s)
	var avatar := Vector2(rect.position.x + 36.0 * s, rect.get_center().y)
	var avatar_face := UIKit.gloss_circle(self, avatar, 24.0 * s, seat.color if not out else UIKit.BTN_GREY, s)
	if turn == Turn.AIM and seat.index == current:
		var left := clampf(turn_left / TURN_TIME, 0.0, 1.0)
		draw_arc(avatar_face, 31.0 * s, 0.0, TAU, 40, Color(INK.r, INK.g, INK.b, 0.35), 6.0 * s, true)
		draw_arc(avatar_face, 31.0 * s, -PI * 0.5, -PI * 0.5 + TAU * left, 40, _clock_color(left), 6.0 * s, true)
	UIKit.icon(self, "user" if seat.is_human else "robot", avatar_face, 28.0 * s, Color("#fffaf0"), s)
	if seat.boss:
		UIKit.crown(self, avatar_face + Vector2(0.0, -31.0 * s), 24.0 * s, UIKit.GOLD, s)
	if not seat.is_human and seat.level > 0 and not out:
		# A tag in the corner: the level the computer plays at.
		var tag_text := "LV %d" % seat.level
		var tag_size := roundi(14.0 * s)
		var tag_width := UIKit.heavy_width(tag_text, tag_size) + 20.0 * s
		var tag := Rect2(rect.end.x - tag_width - 12.0 * s, rect.end.y - 32.0 * s, tag_width, 22.0 * s)
		UIKit.round_rect(self, tag, 12.0 * s, Levels.rank_color(seat.level), INK, 2.5 * s)
		UIKit.title(self, Vector2(tag.position.x, tag.get_center().y + tag_size * 0.36), tag_text, tag_size, Color("#fffaf0"), tag.size.x, HORIZONTAL_ALIGNMENT_CENTER, INK, roundi(4.0 * s), false)
	var name_size := roundi((19.0 if rect.size.x > 190.0 * s else 16.0) * s)
	UIKit.title(self, Vector2(rect.position.x + 68.0 * s, rect.get_center().y - 2.0 * s), seat.label, name_size, INK, rect.size.x - 76.0 * s, HORIZONTAL_ALIGNMENT_LEFT, INK, 0, false)
	# One star per round needed to take the match; won rounds shine gold.
	for k in range(rounds_to_win):
		var star_center := Vector2(rect.position.x + 78.0 * s + float(k) * 25.0 * s, rect.get_center().y + 19.0 * s)
		UIKit.star5(self, star_center, 10.5 * s, UIKit.GOLD if k < seat.score else Color("#ddd5e6"), s)
	if out:
		draw_set_transform(Vector2(rect.end.x - 50.0 * s, rect.get_center().y), -0.18, Vector2.ONE)
		var stamp := Rect2(-38.0 * s, -18.0 * s, 76.0 * s, 36.0 * s)
		UIKit.round_rect(self, stamp, 8.0 * s, Color(1.0, 1.0, 1.0, 0.0), UIKit.BTN_RED, 3.5 * s)
		UIKit.title(self, Vector2(stamp.position.x, 8.0 * s), "OUT", roundi(22.0 * s), UIKit.BTN_RED, stamp.size.x, HORIZONTAL_ALIGNMENT_CENTER, INK, 0, false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _turn_name(seat: Seat) -> String:
	return "Your turn" if human_count == 1 and seat.is_human else "%s's turn" % seat.label


func _turn_label() -> String:
	var seat := seats[current]
	var prefix := ""
	match turn:
		Turn.AIM:
			if dragging:
				return "Aiming"
			if lag_active:
				return "Middle shot" if compact_layout else prefix + "Reach the middle"
			return prefix + _turn_name(seat)
		Turn.CPU_WAIT:
			if lag_active:
				return seat.label + " lines up"
			return prefix + _turn_name(seat)
		Turn.ROLL:
			return "Pens moving"
		Turn.ROUND_WAIT:
			return "Falling!"
		Turn.ROUND_END:
			return "Round over"
		Turn.MATCH_END:
			if match_winner == 0 and human_count == 1:
				return "You win!"
			return "%s wins" % seats[match_winner].label if match_winner >= 0 else "Match over"
	return ""


func _draw_turn_pill(center: Vector2) -> void:
	var s := ui_scale
	# Round ribbon.
	var round_label := "ROUND %d" % round_number
	var size := roundi(26.0 * s)
	var band := UIKit.ribbon(self, center, UIKit.heavy_width(round_label, size) + 56.0 * s, 46.0 * s, UIKit.BTN_RED, s)
	UIKit.centered_title(self, band, round_label, size, Color("#fffaf0"))
	# What is happening now, in a dark pill under the ribbon.
	var label := _turn_label()
	var accent := seats[current].color if turn != Turn.ROUND_END and turn != Turn.ROUND_WAIT else PLAYER_TIP
	var label_size := roundi(17.0 * s)
	var width := UIKit.heavy_width(label, label_size) + 52.0 * s
	var pill := Rect2(center.x - width * 0.5, band.end.y + 14.0 * s, width, 34.0 * s)
	UIKit.round_rect(self, pill, 17.0 * s, Color(INK.r, INK.g, INK.b, 0.82), Color(1.0, 1.0, 1.0, 0.35), 2.0 * s)
	draw_circle(Vector2(pill.position.x + 18.0 * s, pill.get_center().y), 7.0 * s, accent)
	draw_arc(Vector2(pill.position.x + 18.0 * s, pill.get_center().y), 7.0 * s, 0.0, TAU, 20, Color("#fffaf0"), 2.0 * s, true)
	UIKit.title(self, Vector2(pill.position.x + 30.0 * s, pill.get_center().y + label_size * 0.36), label, label_size, Color("#fffaf0"), -1, HORIZONTAL_ALIGNMENT_LEFT, INK, 0, false)
	_draw_clock_pill(pill)


func _hint_text() -> Array[String]:
	var seat := seats[current]
	var who := "" if human_count == 1 else seat.label + ": "
	var title := who + "Press where to strike, pull back"
	var subtitle := "Middle slides straight, ends spin — knock the others off the desk"
	if compact_layout:
		title = who + "Pull back, release"
		subtitle = "Knock the others off"
	if lag_active:
		title = who + "Reach the middle"
		subtitle = "Closest to the target goes first" if compact_layout else "Stop your pen closest to the target — closest goes first"
	if dragging:
		title = "Aiming"
		subtitle = "Release to flick — the dotted line is where it goes"
	elif turn == Turn.ROLL:
		title = "Watch the clash"
		subtitle = "A pen tips off once its middle passes the edge"
	elif turn == Turn.CPU_WAIT:
		title = "%s is lining up…" % seat.label
		subtitle = "Get ready to answer"
	elif turn == Turn.ROUND_WAIT:
		title = "Over the edge!"
		subtitle = "The round ends when it lands"
	elif turn == Turn.ROUND_END:
		title = banner_text.capitalize() if banner_text != "" else "Round over"
		subtitle = _score_line()
	return [title, subtitle]


func _score_line() -> String:
	var parts: Array[String] = []
	for seat in seats:
		parts.append("%s: %d" % [seat.label, seat.score])
	return "   ·   ".join(parts)


func _draw_bottom_hint() -> void:
	if turn == Turn.MATCH_END or paused:
		return
	var s := ui_scale
	var texts := _hint_text()
	# A dark speech pill between the leos counter and the pause button.
	var left_end := _leos_rect().end.x + 16.0 * s
	var right_start := _pause_rect().position.x - 16.0 * s
	var title_size := roundi(18.0 * s)
	var subtitle_size := roundi(14.0 * s)
	var wanted := maxf(UIKit.heavy_width(texts[0], title_size), UIKit.text_width(texts[1], subtitle_size)) + 56.0 * s
	var width := minf(wanted, right_start - left_end)
	var x := clampf(screen_size.x * 0.5 - width * 0.5, left_end, right_start - width)
	var rect := Rect2(x, _safe().end.y - 14.0 * s - 62.0 * s, width, 62.0 * s)
	UIKit.round_rect(self, Rect2(rect.position + Vector2(0.0, 4.0 * s), rect.size), 24.0 * s, Color(0.0, 0.0, 0.1, 0.25))
	UIKit.round_rect(self, rect, 24.0 * s, Color(INK.r, INK.g, INK.b, 0.86), Color(1.0, 1.0, 1.0, 0.35), 2.0 * s)
	UIKit.title(self, Vector2(rect.position.x, rect.position.y + 27.0 * s), texts[0], title_size, Color("#fffaf0"), rect.size.x, HORIZONTAL_ALIGNMENT_CENTER, INK, 0, false)
	draw_string(FONT, Vector2(rect.position.x + 10.0 * s, rect.position.y + 49.0 * s), texts[1], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 20.0 * s, subtitle_size, Color(1.0, 1.0, 1.0, 0.72))


func _draw_corner_buttons() -> void:
	if turn == Turn.MATCH_END or paused:
		return
	var s := ui_scale
	var rect := _pause_rect()
	var face := UIKit.gloss_circle(self, rect.get_center(), rect.size.x * 0.44, UIKit.BTN_BLUE, s, pressed_key == "pause")
	UIKit.icon(self, "pause", face, 30.0 * s, Color("#fffaf0"), s)


func _draw_leos_tab() -> void:
	var s := ui_scale
	var rect := _leos_rect()
	var face := UIKit.gloss_button(self, rect, Color("#3a2f8f"), s)
	UIKit.coin(self, Vector2(face.position.x + 28.0 * s, face.get_center().y), 16.0 * s, s)
	var size := roundi(24.0 * s)
	UIKit.title(self, Vector2(face.position.x + 52.0 * s, face.get_center().y + size * 0.36), str(Profile.leos), size, UIKit.GOLD)


func _draw_popups() -> void:
	var s := ui_scale
	var tab := _leos_rect()
	for i in range(popups.size()):
		var popup: Dictionary = popups[i]
		var life := float(popup["life"])
		var alpha := clampf(life * 2.0, 0.0, 1.0)
		var slide := clampf((2.4 - life) / 0.2, 0.0, 1.0)
		var label: String = popup["text"]
		var font_size := roundi(17.0 * s)
		var width := UIKit.heavy_width(label, font_size) + 56.0 * s
		var rect := Rect2(tab.position.x - (1.0 - slide) * 60.0 * s, tab.position.y - 50.0 * s - float(popups.size() - 1 - i) * 44.0 * s, width, 38.0 * s)
		UIKit.round_rect(self, rect, 19.0 * s, Color(INK.r, INK.g, INK.b, 0.88 * alpha), Color(UIKit.GOLD.r, UIKit.GOLD.g, UIKit.GOLD.b, alpha), 2.5 * s)
		_draw_coin(Vector2(rect.position.x + 20.0 * s, rect.get_center().y), 10.0 * s)
		UIKit.title(self, Vector2(rect.position.x + 38.0 * s, rect.get_center().y + font_size * 0.36), label, font_size, Color(UIKit.GOLD.r, UIKit.GOLD.g, UIKit.GOLD.b, alpha), -1, HORIZONTAL_ALIGNMENT_LEFT, INK, 0, false)


func _draw_toast() -> void:
	var s := ui_scale
	var size := roundi(20.0 * s)
	var width := minf(UIKit.heavy_width(toast_text, size) + 60.0 * s, screen_size.x - 40.0 * s)
	var pop := 1.0
	var alpha := minf(1.0, toast_timer * 3.0)
	var rect := Rect2(screen_size.x * 0.5 - width * 0.5 * pop, screen_size.y * 0.5 + 90.0 * s, width * pop, 48.0 * s)
	UIKit.round_rect(self, rect, 24.0 * s, Color(INK.r, INK.g, INK.b, 0.86 * alpha), Color(1.0, 1.0, 1.0, 0.5 * alpha), 2.5 * s)
	UIKit.title(self, Vector2(rect.position.x, rect.get_center().y + size * 0.36), toast_text, size, Color(1.0, 0.98, 0.92, alpha), rect.size.x, HORIZONTAL_ALIGNMENT_CENTER, INK, 0, false)


func _elastic(age: float, speed: float = 1.0) -> float:
	# 0 → 1 with a springy overshoot.
	var a := age * speed
	return 1.0 - exp(-7.0 * a) * cos(13.0 * a)


func _draw_banner() -> void:
	# Big announcements spring in on a ribbon, then shrink away.
	var s := ui_scale
	var grow := _elastic(banner_age) * minf(1.0, banner_timer / 0.22)
	if grow <= 0.01:
		return
	var color := UIKit.BTN_BLUE
	if "SHRINK" in banner_text or "BOSS" in banner_text:
		color = UIKit.BTN_RED
	elif "YOU" in banner_text or "POINT TO YOU" in banner_text:
		color = UIKit.BTN_GREEN
	elif "DRAW" in banner_text:
		color = UIKit.BTN_PURPLE
	var center := Vector2(screen_size.x * 0.5, screen_size.y * 0.42)
	var size := roundi(42.0 * s)
	var width := UIKit.heavy_width(banner_text, size) + 90.0 * s
	draw_set_transform(center, 0.0, Vector2(grow, grow))
	UIKit.sunburst(self, Vector2.ZERO, width * 0.75, 14, banner_age * 0.8, Color(1.0, 0.95, 0.6, 0.2))
	var band := UIKit.ribbon(self, Vector2.ZERO, width, 78.0 * s, color, s)
	UIKit.centered_title(self, band, banner_text, size, Color("#fffaf0"))
	for side in [-1.0, 1.0]:
		UIKit.star5(self, Vector2(side * (width * 0.5 + 6.0 * s), -50.0 * s), 15.0 * s, UIKit.GOLD, s)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _result_stars() -> int:
	if match_winner < 0:
		return 0
	var mine := match_winner == 0 or (human_count > 1 and seats[match_winner].is_human)
	if mine:
		return 3 if rounds_lost == 0 else 2
	return 1 if seats[0].score > 0 else 0


func _update_result(delta: float) -> void:
	result_time += delta
	# Each earned star lands with a chime.
	var stars := _result_stars()
	while result_stars_shown < stars and result_time >= 0.55 + 0.25 * float(result_stars_shown):
		Sfx.play("coin", -4.0, 1.0 + 0.12 * float(result_stars_shown))
		result_stars_shown += 1
	_update_confetti(delta)
	if level_result.is_empty():
		return
	if levelup_active:
		levelup_time += delta
		if levelup_time >= 0.3 and levelup_time - delta < 0.3:
			# The badge lands: a thump, a burst of confetti and the reward.
			shake = maxf(shake, 7.0 * ui_scale)
			_burst_confetti(_levelup_center(), 90)
		if levelup_time >= 1.0 and levelup_time - delta < 1.0 and int(level_result["reward"]) > 0:
			Sfx.play("buy", -4.0)
		var shown := int(_levelup_number()[0])
		if shown != levelup_shown:
			if levelup_shown != 0:
				Sfx.play("tick", -3.0, 1.2 + 0.04 * float(shown - int(level_result["from_level"])))
			levelup_shown = shown
		if levelup_time >= 9.0:
			levelup_active = false
		return
	# Once the leos have counted up, the XP bar fills, ticking at every level it passes.
	if result_time < XP_FILL_START:
		return
	var from := float(level_result["from_progress"])
	var to := float(level_result["to_progress"])
	var before := xp_shown
	xp_clock += delta
	var duration := clampf(0.7 + 0.45 * (to - from), 0.7, 2.6)
	var t := clampf(xp_clock / duration, 0.0, 1.0)
	xp_shown = lerpf(from, to, 1.0 - pow(1.0 - t, 3.0))
	if floori(xp_shown) > floori(before):
		xp_pop_at = xp_clock
		Sfx.play("coin", -5.0, 1.2 + 0.05 * float(floori(xp_shown) - int(level_result["from_level"])))
		_burst_confetti(_xp_badge_point(), 14)
	if t >= 1.0 and not levelup_done:
		levelup_wait += delta
		if int(level_result["to_level"]) > int(level_result["from_level"]) and levelup_wait >= 0.35:
			levelup_done = true
			levelup_active = true
			levelup_time = 0.0
			Sfx.play("levelup", -2.0)
		elif int(level_result["to_level"]) == int(level_result["from_level"]):
			levelup_done = true


func _draw_result() -> void:
	var s := ui_scale
	var appear := minf(1.0, result_time * 3.0)
	draw_rect(Rect2(Vector2(-40.0, -40.0), screen_size + Vector2(80.0, 80.0)), Color(0.05, 0.03, 0.15, 0.62 * appear))
	var card := _result_card_rect()
	var winner := seats[match_winner] if match_winner >= 0 else seats[0]
	var won := match_winner == 0 and human_count == 1
	var heading := "VICTORY!" if won else ("%s WINS!" % winner.label.to_upper() if human_count > 1 or winner.index == 0 else "DEFEAT")
	var heading_color := UIKit.GOLD if won or (human_count > 1 and winner.is_human) else UIKit.BTN_BLUE
	var grow := _elastic(result_time, 0.9)
	var pivot := card.get_center()
	draw_set_transform(pivot, 0.0, Vector2(grow, grow))
	var local := Rect2(card.position - pivot, card.size)
	UIKit.sunburst(self, Vector2(0.0, local.position.y), card.size.x * 0.95, 16, result_time * 0.4, Color(1.0, 0.92, 0.5, 0.16 if won else 0.08))
	UIKit.panel(self, local, s)
	var ribbon_width := UIKit.heavy_width(heading, roundi(40.0 * s)) + 90.0 * s
	var band := UIKit.ribbon(self, Vector2(0.0, local.position.y + 6.0 * s), ribbon_width, 70.0 * s, heading_color, s)
	UIKit.centered_title(self, band, heading, roundi(40.0 * s), Color("#fffaf0"))
	# Stars: three for a flawless win, two for a win, one for taking a round.
	var stars := _result_stars()
	for k in range(3):
		var big := k == 1
		var center := Vector2((float(k) - 1.0) * 92.0 * s, local.position.y + (112.0 if big else 126.0) * s)
		var radius := (38.0 if big else 30.0) * s
		UIKit.star5(self, center + Vector2(0.0, 4.0 * s), radius, Color("#d9cfe6"), s)
		var at := 0.55 + 0.25 * float(k)
		if k < stars and result_time >= at:
			var pop := _elastic(result_time - at, 1.6)
			UIKit.star5(self, center, radius * pop, UIKit.GOLD, s)
	var subtitle := "%s won the match" % ("You" if won else winner.label)
	if won and bool(level_result.get("boss", false)):
		subtitle = "You beat the level %d boss!" % int(level_result["from_level"])
	UIKit.title(self, Vector2(local.position.x, local.position.y + 196.0 * s), subtitle, roundi(22.0 * s), INK, local.size.x, HORIZONTAL_ALIGNMENT_CENTER, INK, 0, false)
	draw_string(FONT, Vector2(local.position.x, local.position.y + 222.0 * s), _score_line(), HORIZONTAL_ALIGNMENT_CENTER, local.size.x, roundi(16.0 * s), UIKit.MUTED)
	# Leos earned, counting up.
	var counted := roundi(float(match_earned) * clampf((result_time - 1.0) / 0.8, 0.0, 1.0))
	var earned := "+%d" % counted
	var earned_size := roundi(36.0 * s)
	var earned_width := UIKit.heavy_width(earned, earned_size)
	var earned_y := local.position.y + 270.0 * s
	var earned_x := -(earned_width + 44.0 * s) * 0.5
	UIKit.coin(self, Vector2(earned_x + 17.0 * s, earned_y), 17.0 * s, s)
	UIKit.title(self, Vector2(earned_x + 44.0 * s, earned_y + earned_size * 0.36), earned, earned_size, UIKit.GOLD)
	var line_y := earned_y + 40.0 * s
	var reasons := earn_breakdown.keys()
	var column_width := (local.size.x - 80.0 * s) * 0.5
	for i in range(mini(reasons.size(), 4)):
		var column := i % 2
		var row := floori(float(i) / 2.0)
		var x := local.position.x + 40.0 * s + float(column) * (column_width + 0.0)
		var y := line_y + float(row) * 22.0 * s
		draw_string(FONT, Vector2(x, y), str(reasons[i]), HORIZONTAL_ALIGNMENT_LEFT, column_width - 50.0 * s, roundi(15.0 * s), UIKit.MUTED)
		draw_string(FONT, Vector2(x, y), "+%d" % int(earn_breakdown[reasons[i]]), HORIZONTAL_ALIGNMENT_RIGHT, column_width - 14.0 * s, roundi(15.0 * s), INK)
	if not level_result.is_empty():
		_draw_xp_row(local, local.position.y + XP_ROW_Y * s)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if result_time >= 0.4:
		_hud_button(_result_button_rect(), UIKit.BTN_GREEN, "again", "PLAY AGAIN", "restart")
		_hud_button(_result_lobby_rect(), UIKit.BTN_BLUE, "lobby", "LOBBY", "home")


func _hud_button(rect: Rect2, color: Color, key: String, label: String, glyph: String) -> void:
	var s := ui_scale
	var face := UIKit.gloss_button(self, rect, color, s, pressed_key == key)
	var size := roundi(24.0 * s)
	var icon_size := 30.0 * s
	var total := UIKit.heavy_width(label, size) + icon_size + 10.0 * s
	var x := face.get_center().x - total * 0.5
	UIKit.icon(self, glyph, Vector2(x + icon_size * 0.5, face.get_center().y), icon_size, Color("#fffaf0"), s)
	UIKit.title(self, Vector2(x + icon_size + 10.0 * s, face.get_center().y + size * 0.36), label, size, Color("#fffaf0"))


func _draw_pause() -> void:
	var s := ui_scale
	draw_rect(Rect2(Vector2(-40.0, -40.0), screen_size + Vector2(80.0, 80.0)), Color(0.05, 0.03, 0.15, 0.6))
	var card := _pause_card_rect()
	UIKit.panel(self, card, s)
	var band := UIKit.ribbon(self, Vector2(card.get_center().x, card.position.y + 6.0 * s), 250.0 * s, 64.0 * s, UIKit.BTN_PURPLE, s)
	UIKit.centered_title(self, band, "PAUSED", roundi(36.0 * s), Color("#fffaf0"))
	var buttons := _pause_buttons()
	_hud_button(buttons["resume"], UIKit.BTN_GREEN, "resume", "RESUME", "play")
	_hud_button(buttons["restart"], UIKit.BTN_YELLOW, "restart", "RESTART", "restart")
	_hud_button(buttons["lobby"], UIKit.BTN_BLUE, "lobby", "LOBBY", "home")
	if _quit_counts():
		draw_string(FONT, Vector2(card.position.x, card.end.y - 22.0 * s), "Restarting or leaving now counts as a loss", HORIZONTAL_ALIGNMENT_CENTER, card.size.x, roundi(15.0 * s), UIKit.MUTED)


# ------------------------------------------------------------------ levels: the result bar and the level-up show

func _xp_badge_point() -> Vector2:
	# Where the level badge of the result card sits on screen.
	var card := _result_card_rect()
	return Vector2(card.position.x + 70.0 * ui_scale, card.position.y + XP_ROW_Y * ui_scale)


func _draw_xp_row(local: Rect2, y: float) -> void:
	# The level badge, the rank, and the bar filling with this match's XP.
	var s := ui_scale
	var shown_level := mini(floori(xp_shown), Levels.MAX_LEVEL)
	var at_max := shown_level >= Levels.MAX_LEVEL
	var color := Levels.rank_color(shown_level)
	var badge := Vector2(local.position.x + 70.0 * s, y)
	var pop := 1.0 + 0.4 * exp(-9.0 * (xp_clock - xp_pop_at)) if xp_clock >= xp_pop_at else 1.0
	UIKit.level_badge(self, badge, 34.0 * s * pop, shown_level, color, s, false)
	var left := badge.x + 48.0 * s
	var right := local.end.x - 40.0 * s
	var rank_name := str(Levels.rank(shown_level)["name"]).to_upper()
	if Levels.is_boss(shown_level) and not at_max:
		rank_name += "  ·  BOSS LEVEL"
	UIKit.title(self, Vector2(left, y - 14.0 * s), rank_name, roundi(17.0 * s), color, -1, HORIZONTAL_ALIGNMENT_LEFT, INK, roundi(5.0 * s), false)
	var counted := roundi(float(level_result["xp"]) * clampf(xp_clock / 0.9, 0.0, 1.0))
	var gained := "+%d XP" % counted
	var gained_size := roundi(19.0 * s)
	UIKit.title(self, Vector2(right - UIKit.heavy_width(gained, gained_size), y - 14.0 * s), gained, gained_size, UIKit.GOLD, -1, HORIZONTAL_ALIGNMENT_LEFT, INK, roundi(5.0 * s), false)
	var bar := Rect2(left, y - 4.0 * s, right - left, 20.0 * s)
	UIKit.round_rect(self, bar, 10.0 * s, Color("#e4d5b8"), INK, 2.5 * s)
	var fill := 1.0 if at_max else xp_shown - float(shown_level)
	if fill > 0.01:
		var filled := Rect2(bar.position, Vector2(maxf(bar.size.y, bar.size.x * fill), bar.size.y))
		UIKit.round_rect(self, filled, 10.0 * s, color, INK, 2.5 * s)
		draw_rect(Rect2(filled.position + Vector2(6.0 * s, 4.0 * s), Vector2(maxf(0.0, filled.size.x - 12.0 * s), 4.0 * s)), Color(1.0, 1.0, 1.0, 0.45))
	# Under the bar: what comes next.
	var note := ""
	var note_color := UIKit.MUTED
	if at_max:
		note = "Max level — every win over the final boss earns a crown (%d)" % Profile.crowns
	elif bool(level_result["gate"]) and xp_shown >= float(level_result["to_progress"]) - 0.001:
		note = "Bar full — beat the boss to rank up!"
		note_color = UIKit.BTN_RED
	else:
		note = "Win rate %d%%   ·   Form x%.2f   ·   Streak %d" % [roundi(Profile.win_rate() * 100.0), Levels.form_multiplier(Profile.recent), Profile.streak]
	draw_string(FONT, Vector2(left, y + 36.0 * s), note, HORIZONTAL_ALIGNMENT_LEFT, right - left, roundi(14.0 * s), note_color)


func _levelup_center() -> Vector2:
	return Vector2(screen_size.x * 0.5, screen_size.y * 0.45)


func _levelup_number() -> Array:
	# The badge lands showing the old level, then counts up to the new one: [level, when it changed].
	var from := int(level_result["from_level"])
	var to := int(level_result["to_level"])
	var steps := maxi(1, to - from)
	var step_time := minf(0.22, 0.7 / float(steps))
	var passed := clampi(floori((levelup_time - 0.36) / step_time) + 1, 0, steps) if levelup_time >= 0.36 else 0
	return [from + passed, 0.36 + float(passed - 1) * step_time]


func _draw_levelup() -> void:
	var s := ui_scale
	var t := levelup_time
	var from := int(level_result["from_level"])
	var to := int(level_result["to_level"])
	var number := _levelup_number()
	var shown := int(number[0])
	var color := Levels.rank_color(shown)
	var center := _levelup_center()
	var appear := minf(1.0, t * 4.0)
	var crowned := Levels.is_boss(shown) or shown >= Levels.MAX_LEVEL
	draw_rect(Rect2(Vector2(-40.0, -40.0), screen_size + Vector2(80.0, 80.0)), Color(0.04, 0.02, 0.13, 0.9 * appear))
	# Light pours out from behind the badge: two sets of rays turning against each other.
	var bloom := clampf(_elastic(t, 0.7), 0.0, 1.2)
	var reach := screen_size.length() * 0.62 * bloom
	UIKit.sunburst(self, center, reach, 18, t * 0.35, Color(color.r, color.g, color.b, 0.16 * appear))
	UIKit.sunburst(self, center, reach * 0.7, 12, -t * 0.22, Color(1.0, 0.97, 0.8, 0.07 * appear))
	for k in range(4):
		draw_circle(center, (170.0 - 30.0 * float(k)) * s * bloom, Color(color.r, color.g, color.b, 0.07 * appear))
	# Shockwaves ring out when the badge lands.
	for k in range(3):
		var ring := (t - 0.3 - 0.14 * float(k)) / 0.9
		if ring > 0.0 and ring < 1.0:
			var eased := 1.0 - pow(1.0 - ring, 3.0)
			draw_arc(center, lerpf(70.0, 480.0, eased) * s, 0.0, TAU, 64, Color(1.0, 0.96, 0.75, 0.75 * (1.0 - ring)), (12.0 * (1.0 - ring) + 2.0) * s, true)
	# Twinkling stars circle the badge.
	var orbit := clampf((t - 0.35) * 3.0, 0.0, 1.0)
	for k in range(10):
		var a := t * 0.8 + TAU * float(k) / 10.0
		var twinkle := 0.5 + 0.5 * sin(t * 6.0 + float(k) * 1.3)
		var point := center + Vector2.RIGHT.rotated(a) * (150.0 + 16.0 * sin(t * 3.0 + float(k))) * s * orbit
		UIKit.star(self, point, (5.0 + 6.0 * twinkle) * s, Color(1.0, 1.0, 0.85, 0.9 * twinkle * orbit), s)
	# The badge drops in spinning, lands with a squash, and pops each time its number goes up.
	var radius := 96.0 * s
	var drop := 0.0
	var spin := 0.0
	var squash := Vector2.ONE
	if t < 0.3:
		var fall := t / 0.3
		drop = -(1.0 - fall * fall) * screen_size.y * 0.65
		spin = -(1.0 - fall) * 2.6
	else:
		var after := t - 0.3
		var wobble := exp(-6.0 * after) * sin(after * 22.0)
		squash = Vector2(1.0 + 0.2 * wobble, 1.0 - 0.2 * wobble)
	var since_change := t - float(number[1])
	if shown > from and since_change >= 0.0:
		squash *= 1.0 + 0.22 * exp(-12.0 * since_change)
	draw_set_transform(center + Vector2(0.0, drop), spin, squash)
	UIKit.level_badge(self, Vector2.ZERO, radius, shown, color, s)
	if crowned:
		UIKit.crown(self, Vector2(0.0, -radius - 8.0 * s), 46.0 * s, UIKit.GOLD, s)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# The heading bounces in letter by letter.
	var heading := "MAX LEVEL!" if to >= Levels.MAX_LEVEL else "LEVEL UP!"
	var size := roundi(64.0 * s)
	var x := center.x - UIKit.heavy_width(heading, size) * 0.5
	var heading_y := center.y - radius - (66.0 if crowned else 40.0) * s
	for k in range(heading.length()):
		var letter := heading[k]
		var width := UIKit.heavy_width(letter, size)
		var start := 0.32 + 0.05 * float(k)
		if t >= start and letter != " ":
			var grow := _elastic(t - start, 1.3)
			var bob := sin(t * 4.0 + float(k) * 0.6) * 4.0 * s
			draw_set_transform(Vector2(x + width * 0.5, heading_y + bob), sin(t * 2.0 + float(k)) * 0.06, Vector2(grow, grow))
			UIKit.title(self, Vector2(-width * 0.5, 0.0), letter, size, UIKit.GOLD, -1, HORIZONTAL_ALIGNMENT_LEFT, INK, roundi(14.0 * s))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		x += width
	# Beating a boss gets a stamp across the badge.
	if bool(level_result["boss"]) and t >= 0.75:
		var stamp := clampf(_elastic(t - 0.75, 1.4), 0.0, 1.3)
		draw_set_transform(center + Vector2(radius * 0.95, radius * 0.6), -0.25, Vector2(stamp, stamp))
		var box := Rect2(-94.0 * s, -22.0 * s, 188.0 * s, 44.0 * s)
		UIKit.round_rect(self, box, 10.0 * s, UIKit.BTN_RED, INK, 3.5 * s)
		UIKit.centered_title(self, box, "BOSS BEATEN!", roundi(22.0 * s), Color("#fffaf0"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# The rank ribbon, then the reward and what changes.
	var below := center.y + radius + 46.0 * s
	if t >= 0.55:
		var grow := clampf(_elastic(t - 0.55, 1.2), 0.0, 1.3)
		var new_rank := Levels.rank_index(to) > Levels.rank_index(from)
		var label := ("NEW RANK: " if new_rank else "") + str(Levels.rank(to)["name"]).to_upper()
		var label_size := roundi(26.0 * s)
		draw_set_transform(Vector2(center.x, below), 0.0, Vector2(grow, grow))
		var band := UIKit.ribbon(self, Vector2.ZERO, UIKit.heavy_width(label, label_size) + 70.0 * s, 52.0 * s, Levels.rank_color(to), s)
		UIKit.centered_title(self, band, label, label_size, Color("#fffaf0"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var reward := int(level_result["reward"])
	if t >= 0.95 and reward > 0:
		var alpha := clampf((t - 0.95) * 4.0, 0.0, 1.0)
		var label := "+%d" % reward
		var label_size := roundi(32.0 * s)
		var left := center.x - (UIKit.heavy_width(label, label_size) + 44.0 * s) * 0.5
		var row_y := below + 64.0 * s - (1.0 - alpha) * 12.0 * s
		UIKit.coin(self, Vector2(left + 16.0 * s, row_y), 16.0 * s, s)
		UIKit.title(self, Vector2(left + 44.0 * s, row_y + label_size * 0.36), label, label_size, Color(UIKit.GOLD.r, UIKit.GOLD.g, UIKit.GOLD.b, alpha), -1, HORIZONTAL_ALIGNMENT_LEFT, Color(INK.r, INK.g, INK.b, alpha))
	if t >= 1.15:
		var alpha := clampf((t - 1.15) * 4.0, 0.0, 1.0)
		var info := "The computer gets sharper: %s" % Levels.difficulty_name(to)
		if to >= Levels.MAX_LEVEL:
			info = "You reached the top. The final boss waits — beat it to win crowns."
		elif Levels.is_boss(to):
			info = "Boss level! Fill the bar, then beat the boss to rank up."
		UIKit.title(self, Vector2(0.0, below + 114.0 * s), info, roundi(19.0 * s), Color(1.0, 1.0, 1.0, alpha), screen_size.x, HORIZONTAL_ALIGNMENT_CENTER, Color(INK.r, INK.g, INK.b, alpha), roundi(5.0 * s), false)
	if t >= 1.2:
		var blink := 0.55 + 0.45 * sin(t * 5.0)
		UIKit.title(self, Vector2(0.0, _safe().end.y - 30.0 * s), "TAP TO CONTINUE", roundi(20.0 * s), Color(1.0, 1.0, 1.0, blink), screen_size.x, HORIZONTAL_ALIGNMENT_CENTER, Color(INK.r, INK.g, INK.b, blink), roundi(5.0 * s), false)


func _burst_confetti(origin: Vector2, count: int) -> void:
	var colors := [UIKit.GOLD, UIKit.BTN_RED, UIKit.BTN_BLUE, UIKit.BTN_GREEN, UIKit.BTN_PURPLE, Color("#ff9a4a"), Color("#fffaf0")]
	# Small bursts (a level ticking over on the bar) are gentler than the big celebration.
	var power := 1.0 if count > 30 else 0.45
	for k in range(count):
		confetti.append({
			"position": origin,
			"velocity": Vector2.RIGHT.rotated(rng.randf_range(-PI * 0.95, -PI * 0.05)) * rng.randf_range(260.0, 950.0) * power * ui_scale,
			"angle": rng.randf_range(0.0, TAU),
			"spin": rng.randf_range(-9.0, 9.0),
			"flip": rng.randf_range(0.0, TAU),
			"flip_speed": rng.randf_range(6.0, 14.0),
			"size": Vector2(rng.randf_range(9.0, 15.0), rng.randf_range(5.0, 8.0)) * ui_scale * lerpf(0.7, 1.0, power),
			"color": colors[rng.randi() % colors.size()],
			"life": rng.randf_range(2.0, 3.4) * lerpf(0.5, 1.0, power),
		})


func _update_confetti(delta: float) -> void:
	# Paper flutters: it falls under gravity, air drags it, and it sways as it turns over.
	for index in range(confetti.size() - 1, -1, -1):
		var piece: Dictionary = confetti[index]
		piece["life"] = float(piece["life"]) - delta
		var velocity: Vector2 = piece["velocity"]
		velocity.y += 980.0 * ui_scale * delta
		velocity *= exp(-2.2 * delta)
		piece["velocity"] = velocity
		piece["flip"] = float(piece["flip"]) + float(piece["flip_speed"]) * delta
		piece["angle"] = float(piece["angle"]) + float(piece["spin"]) * delta
		var sway := Vector2(sin(float(piece["flip"]) * 0.5) * 60.0 * ui_scale, 0.0)
		var position_now: Vector2 = piece["position"]
		piece["position"] = position_now + (velocity + sway) * delta
		if float(piece["life"]) <= 0.0 or position_now.y > screen_size.y + 40.0:
			confetti.remove_at(index)


func _draw_confetti() -> void:
	for piece in confetti:
		var size: Vector2 = piece["size"]
		var color: Color = piece["color"]
		var turn_over := absf(cos(float(piece["flip"])))
		color = color.darkened(0.25 * (1.0 - turn_over))
		color.a = clampf(float(piece["life"]) / 0.5, 0.0, 1.0)
		draw_set_transform(piece["position"], float(piece["angle"]), Vector2(1.0, 0.15 + 0.85 * turn_over))
		draw_rect(Rect2(-size * 0.5, size), color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ------------------------------------------------------------------ the shrinking desk

func _next_shrink_time() -> float:
	return SHRINK_FIRST + SHRINK_EVERY * float(shrink_level)


func _can_shrink() -> bool:
	return desk_target > SHRINK_MIN + 0.001


func _update_shrink(delta: float) -> void:
	round_clock += delta
	if _can_shrink():
		var remaining := _next_shrink_time() - round_clock
		if remaining <= 10.0 and not shrink_warned:
			shrink_warned = true
			toast_text = "THE DESK SHRINKS IN 10!"
			toast_timer = 1.6
		if remaining <= 5.0:
			var second := ceili(remaining)
			if second != tick_second and second >= 1:
				tick_second = second
				Sfx.play("tick", -4.0, 1.0 + float(5 - second) * 0.05)
		if remaining <= 0.0:
			_start_shrink()
	if desk_scale > desk_target:
		desk_scale = maxf(desk_target, desk_scale - delta * SHRINK_SPEED)
		# Pens left outside the shrinking edge fall off.
		if turn != Turn.ROLL and not _check_falls() and (turn == Turn.AIM or turn == Turn.CPU_WAIT) and not seats[current].alive:
			current = _next_in_order(current)
			_begin_turn()


func _start_shrink() -> void:
	shrink_level += 1
	desk_target = maxf(SHRINK_MIN, pow(SHRINK_FACTOR, float(shrink_level)))
	shrink_warned = false
	tick_second = -1
	banner_text = "THE DESK IS SHRINKING!"
	banner_timer = 1.8
	shake = maxf(shake, 5.0 * ui_scale)
	Sfx.play("rumble", -2.0)


func _update_scrape() -> void:
	# Sliding pens scrape: the louder, the faster they move.
	var motion := 0.0
	if turn == Turn.ROLL:
		for seat in seats:
			if seat.alive:
				motion += seat.vel.length() + absf(seat.omega) * 60.0 * ui_scale
	Sfx.set_scrape(motion / (1100.0 * ui_scale))


func _exit_tree() -> void:
	Sfx.set_scrape(0.0)


func _draw_shrink_warning() -> void:
	# For the last ten seconds, the part of the desk that is about to be lost glows red.
	if lag_active or not _can_shrink() or desk_scale > desk_target + 0.001:
		return
	if turn != Turn.AIM and turn != Turn.CPU_WAIT and turn != Turn.ROLL:
		return
	var remaining := _next_shrink_time() - round_clock
	if remaining > 10.0:
		return
	var s := ui_scale
	var full := _full_bounds()
	var next_scale := maxf(SHRINK_MIN, pow(SHRINK_FACTOR, float(shrink_level + 1)))
	var next_size := full.size * next_scale
	var inner := Rect2(full.get_center() - next_size * 0.5, next_size)
	var outer := _table_bounds()
	var pulse := (sin(Time.get_ticks_msec() * 0.012) + 1.0) * 0.5
	var danger := Color(0.85, 0.2, 0.15, 0.16 + 0.14 * pulse)
	draw_rect(Rect2(outer.position, Vector2(outer.size.x, inner.position.y - outer.position.y)), danger)
	draw_rect(Rect2(outer.position.x, inner.end.y, outer.size.x, outer.end.y - inner.end.y), danger)
	draw_rect(Rect2(outer.position.x, inner.position.y, inner.position.x - outer.position.x, inner.size.y), danger)
	draw_rect(Rect2(inner.end.x, inner.position.y, outer.end.x - inner.end.x, inner.size.y), danger)
	var line := Color(0.85, 0.2, 0.15, 0.75)
	var corners := [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]
	for k in range(4):
		draw_dashed_line(corners[k], corners[(k + 1) % 4], line, 3.0 * s, 12.0 * s)


func _draw_clock_pill(pill: Rect2) -> void:
	if lag_active or not (turn == Turn.AIM or turn == Turn.CPU_WAIT or turn == Turn.ROLL):
		return
	var label := ""
	var urgent := false
	if desk_scale > desk_target + 0.001:
		label = "Shrinking!"
		urgent = true
	elif not _can_shrink():
		label = "Smallest desk"
	else:
		var remaining := maxf(0.0, _next_shrink_time() - round_clock)
		label = "%d:%02d" % [floori(remaining / 60.0), int(remaining) % 60]
		urgent = remaining <= 10.0
	var s := ui_scale
	var font_size := roundi(17.0 * s)
	var width := UIKit.heavy_width(label, font_size) + 52.0 * s
	var rect := Rect2(screen_size.x * 0.5 - width * 0.5, pill.end.y + 8.0 * s, width, 32.0 * s)
	var pulse := (sin(Time.get_ticks_msec() * 0.012) + 1.0) * 0.5
	var fill := UIKit.BTN_RED.lerp(Color("#ff9c8a"), pulse) if urgent else Color("#fffaf0")
	UIKit.round_rect(self, Rect2(rect.position + Vector2(0.0, 3.0 * s), rect.size), 16.0 * s, Color(0.0, 0.0, 0.1, 0.25))
	UIKit.round_rect(self, rect, 16.0 * s, fill, INK, 2.5 * s)
	var ink := Color("#fffaf0") if urgent else INK
	UIKit.icon(self, "clock", Vector2(rect.position.x + 18.0 * s, rect.get_center().y), 20.0 * s, ink, s, false)
	UIKit.title(self, Vector2(rect.position.x + 32.0 * s, rect.get_center().y + font_size * 0.36), label, font_size, ink, -1, HORIZONTAL_ALIGNMENT_LEFT, INK, 0, false)
