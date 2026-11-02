extends Node2D
# The lobby: choose how many players take part, who is human and who is a computer, pick and
# recolor each player's pen, buy new pens with leos, follow your level climb, then start the match.
# Everything is drawn immediate-mode: each frame the draw code registers the buttons it shows,
# and taps are matched against that list. Built for phones held sideways: every layout keeps
# inside the screen's safe area and every button is a comfortable thumb size.

const UIKit := preload("res://scripts/ui_kit.gd")
const PenArt := preload("res://scripts/pen_art.gd")
const PenData := preload("res://scripts/pen_data.gd")
const Levels := preload("res://scripts/levels.gd")
const FONT := UIKit.FONT
const INK := UIKit.INK
const GAME_SCENE := "res://scenes/main.tscn"
const WHITE := Color("#fffaf0")

enum Screen { HOME, PENS, LEVELS }

var screen_size := Vector2.ZERO
var ui_scale := 1.0
var screen := Screen.HOME
var selected_seat := 0
var buttons: Array[Dictionary] = []
var message := ""
var message_timer := 0.0
var pressed_key := ""
var press_point := Vector2.ZERO
var clock := 0.0
var fade := 1.0
var leaving := false
var consent_modal_open := false
var consent_pressed_key := ""
var consent_allow_rect := Rect2()
var consent_decline_rect := Rect2()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_update_layout()
	consent_modal_open = Analytics.should_show_consent_prompt()
	Analytics.track_screen("lobby_home")
	set_process(true)
	set_process_input(true)


func _process(delta: float) -> void:
	if get_viewport_rect().size != screen_size:
		_update_layout()
	clock += delta
	message_timer = maxf(0.0, message_timer - delta)
	if leaving:
		fade = minf(1.0, fade + delta * 4.0)
		if fade >= 1.0:
			set_process(false)
			get_tree().change_scene_to_file(GAME_SCENE)
	else:
		fade = maxf(0.0, fade - delta * 3.0)
	Sfx.set_scrape(0.0)
	queue_redraw()


func _update_layout() -> void:
	var next_size := get_viewport_rect().size
	if next_size.x <= 0.0 or next_size.y <= 0.0:
		return
	screen_size = next_size
	ui_scale = clampf(minf(screen_size.x / 1280.0, screen_size.y / 720.0), 0.78, 1.15)


func _area() -> Rect2:
	# The safe part of the screen, less a margin.
	var s := ui_scale
	var safe := UIKit.safe_rect(self)
	return Rect2(safe.position + Vector2(24.0, 14.0) * s, safe.size - Vector2(48.0, 28.0) * s)


func _human_seats() -> Array[int]:
	var humans: Array[int] = []
	for i in range(Profile.player_count):
		if bool(Profile.seats[i]["human"]):
			humans.append(i)
	return humans


func _say(text: String) -> void:
	message = text
	message_timer = 2.6


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if consent_modal_open:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_handle_consent_pointer(event.position, event.pressed)
		elif event is InputEventScreenTouch:
			_handle_consent_pointer(event.position, event.pressed)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press(event.position)
		else:
			_release(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_press(event.position)
		else:
			_release(event.position)


func _press(point: Vector2) -> void:
	# The button under the finger sinks in; it fires when the finger lifts on it.
	var button := _button_at(point)
	pressed_key = _key(button) if not button.is_empty() else ""
	press_point = point


func _handle_consent_pointer(point: Vector2, pressed: bool) -> void:
	if pressed:
		consent_pressed_key = _consent_button_at(point)
		return
	var released_key := _consent_button_at(point)
	if consent_pressed_key != "" and released_key == consent_pressed_key:
		var granted := consent_pressed_key == "allow"
		Analytics.set_user_consent(granted)
		consent_modal_open = false
		if granted:
			Analytics.track_screen("lobby_home" if screen == Screen.HOME else ("levels" if screen == Screen.LEVELS else "pen_shop"))
	consent_pressed_key = ""


func _consent_button_at(point: Vector2) -> String:
	if consent_allow_rect.has_point(point):
		return "allow"
	if consent_decline_rect.has_point(point):
		return "decline"
	return ""


func _release(point: Vector2) -> void:
	var button := _button_at(point)
	if not button.is_empty() and _key(button) == pressed_key:
		_activate(str(button["id"]), button["arg"])
	pressed_key = ""


func _button_at(point: Vector2) -> Dictionary:
	# Later buttons sit on top of earlier ones; hit areas are a little larger than they look.
	for i in range(buttons.size() - 1, -1, -1):
		var rect: Rect2 = buttons[i]["rect"]
		if rect.grow(6.0 * ui_scale).has_point(point):
			return buttons[i]
	return {}


func _key(button: Dictionary) -> String:
	return "%s:%s" % [button["id"], str(button["arg"])]


func _is_pressed(id: String, arg: Variant) -> bool:
	return pressed_key == "%s:%s" % [id, str(arg)]


func _add_button(rect: Rect2, id: String, arg: Variant = null) -> void:
	buttons.append({"rect": rect, "id": id, "arg": arg})


func _activate(id: String, arg: Variant) -> void:
	if leaving:
		return
	if id == "color":
		Sfx.play("tick", -4.0)
	elif id != "pen":
		Sfx.play("click", -4.0)
	match id:
		"count":
			Profile.player_count = int(arg)
			selected_seat = mini(selected_seat, Profile.player_count - 1)
			Profile.save_profile()
		"add_seat":
			Profile.player_count = int(arg) + 1
			selected_seat = int(arg)
			Profile.save_profile()
		"seat_type":
			var seat: Dictionary = Profile.seats[int(arg)]
			seat["human"] = not bool(seat["human"])
			Profile.save_profile()
		"select_seat":
			selected_seat = int(arg)
		"edit_pen":
			selected_seat = int(arg)
			screen = Screen.PENS
			Analytics.track_screen("pen_shop")
		"back":
			screen = Screen.HOME
			Analytics.track_screen("lobby_home")
		"levels":
			screen = Screen.LEVELS
			Analytics.track_screen("levels")
		"privacy":
			consent_modal_open = true
		"level_node":
			_say(_level_note(int(arg)))
		"tab_seat":
			selected_seat = int(arg)
		"color":
			var owner := Profile.color_taken_by(selected_seat, int(arg))
			if owner >= 0:
				_say("Player %d already uses that color." % (owner + 1))
			else:
				Profile.set_seat_color(selected_seat, int(arg))
		"pen":
			_pick_pen(str(arg))
		"play":
			Profile.save_profile()
			Sfx.play("whoosh", -6.0)
			leaving = true
		"soon":
			_say("%s is coming soon!" % str(arg))


func _pick_pen(pen_id: String) -> void:
	var info := Profile.pen_info(pen_id)
	if not Profile.owns(pen_id):
		if not Profile.buy(pen_id):
			_say("Not enough leos for %s yet." % str(info["name"]))
			Sfx.play("knock", -6.0, 0.8)
			return
		_say("Unlocked %s!" % str(info["name"]))
		Analytics.track_event("pen_unlock", {"pen_id": pen_id})
		Sfx.play("buy", -2.0)
	else:
		_say("%s equipped." % str(info["name"]))
		Sfx.play("knock", -3.0)
	Profile.seats[selected_seat]["pen"] = pen_id
	Profile.save_profile()


# ------------------------------------------------------------------ drawing helpers

func _gloss(rect: Rect2, color: Color, id: String, arg: Variant = null, label: String = "", font_size: float = 22.0, enabled: bool = true, glyph: String = "") -> Rect2:
	# A candy button with an optional icon before its label.
	var s := ui_scale
	var face := UIKit.gloss_button(self, rect, color if enabled else UIKit.BTN_GREY, s, enabled and _is_pressed(id, arg))
	var size := roundi(font_size * s)
	var text_width := UIKit.heavy_width(label, size) if label != "" else 0.0
	var icon_size := size * 1.35
	var total := text_width + (icon_size + 8.0 * s if glyph != "" else 0.0)
	var x := face.get_center().x - total * 0.5
	if glyph != "":
		UIKit.icon(self, glyph, Vector2(x + icon_size * 0.5, face.get_center().y), icon_size, WHITE, s)
		x += icon_size + 8.0 * s
	if label != "":
		UIKit.title(self, Vector2(x, face.get_center().y + size * 0.36), label, size, WHITE if enabled else Color("#f1eef7"), -1, HORIZONTAL_ALIGNMENT_LEFT, INK, roundi(size * 0.22))
	if enabled:
		_add_button(rect, id, arg)
	return face


func _set_xf(pos: Vector2, rotation_angle: float) -> void:
	draw_set_transform(pos, rotation_angle, Vector2.ONE)


func _reset_xf() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_pen_preview(skin: Dictionary, center: Vector2, target_length: float, phase: float, with_trail: bool = true) -> void:
	# A pen rocking gently with its idle animation and its trail.
	var pen_scale := target_length / PenArt.PEN_LENGTH
	var angle := -0.22 + sin(clock * 1.5 + phase) * 0.06
	var lift := sin(clock * 2.0 + phase) * 4.0 * pen_scale
	var motion := Vector2.RIGHT.rotated(angle)
	if with_trail:
		var fake_trail: Array[Dictionary] = []
		for k in range(6):
			fake_trail.append({"position": center - motion * float(5 - k) * 12.0 * pen_scale, "angle": angle})
		PenArt.trail(self, fake_trail, skin, pen_scale)
	_set_xf(center + Vector2(5.0, 14.0) * pen_scale, angle)
	PenArt.body(self, skin, pen_scale, Color(0.0, 0.0, 0.1, 0.3), true)
	_set_xf(center + Vector2(0.0, -lift), angle)
	PenArt.body(self, skin, pen_scale, Color.WHITE, false)
	PenArt.idle(self, skin, phase, pen_scale)
	_reset_xf()


func _spotlight(center: Vector2, radius: float, color: Color) -> void:
	# A soft pool of light behind showcase items, with slow rays.
	UIKit.sunburst(self, center, radius, 12, clock * 0.3, Color(color.r, color.g, color.b, 0.18))
	for k in range(4):
		draw_circle(center, radius * (1.0 - 0.2 * float(k)), Color(color.r, color.g, color.b, 0.08))


func _tier(pen: Dictionary) -> Array:
	var price := int(pen["price"])
	if price == 0:
		return ["STARTER", UIKit.BTN_GREEN]
	if price < 250:
		return ["COMMON", UIKit.BTN_BLUE]
	if price < 600:
		return ["RARE", UIKit.BTN_PURPLE]
	if price < 2000:
		return ["EPIC", UIKit.BTN_RED]
	return ["LEGEND", UIKit.GOLD]


func _draw_stat_bar(pos: Vector2, label: String, fill: float, width: float, color: Color) -> void:
	var s := ui_scale
	var label_width := 92.0 * s
	UIKit.title(self, Vector2(pos.x, pos.y + 7.0 * s), label, roundi(15.0 * s), INK, -1, HORIZONTAL_ALIGNMENT_LEFT, INK, 0, false)
	var bar := Rect2(pos.x + label_width, pos.y - 9.0 * s, width - label_width, 18.0 * s)
	UIKit.round_rect(self, bar, 9.0 * s, Color("#e4d5b8"), INK, 2.5 * s)
	var filled := Rect2(bar.position, Vector2(bar.size.x * clampf(maxf(fill, 0.1), 0.0, 1.0), bar.size.y))
	UIKit.round_rect(self, filled, 9.0 * s, color, INK, 2.5 * s)
	draw_rect(Rect2(filled.position + Vector2(5.0 * s, 3.5 * s), Vector2(maxf(0.0, filled.size.x - 10.0 * s), 3.5 * s)), Color(1.0, 1.0, 1.0, 0.45))


func _draw_stats(pos: Vector2, width: float, pen: Dictionary) -> void:
	var power_fill := clampf((float(pen["punch"]) - 1.0) / 0.12, 0.0, 1.0)
	var weight_fill := clampf((float(pen["mass"]) - 1.0) / 0.25, 0.0, 1.0)
	_draw_stat_bar(pos, "POWER", power_fill, width, UIKit.BTN_RED)
	_draw_stat_bar(pos + Vector2(0.0, 30.0 * ui_scale), "WEIGHT", weight_fill, width, UIKit.BTN_BLUE)


func _draw_palette(center_x: float, y: float, available: float, pen_id: String) -> void:
	# Free recolors: the first swatch, with a star, is the pen's own color.
	var s := ui_scale
	var colors := PenData.palette()
	var gap := 9.0 * s
	var diameter := clampf((available - gap * float(colors.size())) / float(colors.size() + 1), 26.0 * s, 38.0 * s)
	var total := diameter * float(colors.size() + 1) + gap * float(colors.size())
	var x := center_x - total * 0.5
	var current := Profile.seat_color(selected_seat)
	for k in range(-1, colors.size()):
		var color: Color = Color(Profile.pen_info(pen_id)["barrel"]) if k < 0 else colors[k]
		var chosen := k == current
		var center := Vector2(x + diameter * 0.5, y - (4.0 * s if chosen else 0.0))
		var radius := diameter * 0.5 * (1.12 if chosen else 1.0)
		if chosen:
			draw_circle(center, radius + 8.0 * s, Color(1.0, 1.0, 1.0, 0.9))
			draw_arc(center, radius + 8.0 * s, 0.0, TAU, 32, INK, 3.0 * s, true)
		draw_circle(center + Vector2(0.0, 3.0 * s), radius + 2.5 * s, INK)
		draw_circle(center, radius + 2.5 * s, INK)
		draw_circle(center, radius, color)
		draw_circle(center + Vector2(-radius * 0.3, -radius * 0.3), radius * 0.25, Color(1.0, 1.0, 1.0, 0.45))
		if k < 0:
			UIKit.star5(self, center, radius * 0.45, WHITE, s, false)
		_add_button(Rect2(center - Vector2.ONE * (radius + 5.0 * s), Vector2.ONE * (radius * 2.0 + 10.0 * s)), "color", k)
		x += diameter + gap


func _draw_leos_pill(right: float, top: float) -> float:
	var s := ui_scale
	var size := roundi(26.0 * s)
	var label := str(Profile.leos)
	var width := UIKit.heavy_width(label, size) + 96.0 * s
	var rect := Rect2(right - width, top, width, 58.0 * s)
	var shop_seat := selected_seat if bool(Profile.seats[selected_seat]["human"]) else 0
	var face := UIKit.gloss_button(self, rect, Color("#3a2f8f"), s, _is_pressed("edit_pen", shop_seat))
	UIKit.coin(self, Vector2(face.position.x + 30.0 * s, face.get_center().y), 17.0 * s, s)
	UIKit.title(self, Vector2(face.position.x + 56.0 * s, face.get_center().y + size * 0.36), label, size, UIKit.GOLD)
	# A little "+" says leos come from playing; tapping opens the pen shop.
	var plus := Vector2(face.end.x - 18.0 * s, face.get_center().y)
	draw_circle(plus, 12.0 * s, INK)
	draw_circle(plus, 9.5 * s, UIKit.BTN_GREEN)
	UIKit.icon(self, "plus", plus, 13.0 * s, WHITE, s, false)
	_add_button(rect, "edit_pen", shop_seat)
	return rect.position.x


# ------------------------------------------------------------------ the screens

func _draw() -> void:
	if screen_size.x <= 0.0:
		return
	buttons.clear()
	UIKit.backdrop(self, screen_size, clock, ui_scale)
	if screen == Screen.HOME:
		_draw_home()
	elif screen == Screen.LEVELS:
		_draw_levels()
	else:
		_draw_pens()
	if message_timer > 0.0:
		_draw_message()
	if fade > 0.0:
		draw_rect(Rect2(Vector2(-40.0, -40.0), screen_size + Vector2(80.0, 80.0)), Color(UIKit.SKY_BOTTOM.r, UIKit.SKY_BOTTOM.g, UIKit.SKY_BOTTOM.b, fade))
	if consent_modal_open:
		_draw_analytics_consent()


func _draw_analytics_consent() -> void:
	var s := ui_scale
	draw_rect(Rect2(Vector2.ZERO, screen_size), Color(INK.r, INK.g, INK.b, 0.72))
	var card_size := Vector2(minf(720.0 * s, screen_size.x - 40.0 * s), minf(390.0 * s, screen_size.y - 40.0 * s))
	var card := Rect2((screen_size - card_size) * 0.5, card_size)
	UIKit.round_rect(self, Rect2(card.position + Vector2(0.0, 6.0 * s), card.size), 28.0 * s, Color(0.0, 0.0, 0.1, 0.3))
	UIKit.round_rect(self, card, 28.0 * s, Color("#fffaf0"), INK, 4.0 * s)
	UIKit.title(self, Vector2(card.position.x, card.position.y + 56.0 * s), "ANALYTICS & PRIVACY", roundi(28.0 * s), INK, card.size.x, HORIZONTAL_ALIGNMENT_CENTER, INK, 0, false)
	var body := [
		"Optional usage analytics sends gameplay events and basic",
		"app/device data to Firebase/Google to help improve the game.",
		"No account is needed. Change your choice anytime with Privacy.",
	]
	if Analytics.consent_answered:
		body[2] = "Current setting: %s. Choose below to change it." % ("on" if Analytics.consent_granted else "off")
	for i in range(body.size()):
		draw_string(FONT, Vector2(card.position.x + 28.0 * s, card.position.y + (116.0 + float(i) * 32.0) * s), body[i], HORIZONTAL_ALIGNMENT_CENTER, card.size.x - 56.0 * s, roundi(18.0 * s), UIKit.MUTED)
	var button_gap := 18.0 * s
	var button_width := (card.size.x - 72.0 * s - button_gap) * 0.5
	var button_height := 58.0 * s
	var button_y := card.end.y - button_height - 28.0 * s
	consent_allow_rect = Rect2(card.position.x + 36.0 * s, button_y, button_width, button_height)
	consent_decline_rect = Rect2(consent_allow_rect.end.x + button_gap, button_y, button_width, button_height)
	var allow_face := UIKit.gloss_button(self, consent_allow_rect, UIKit.BTN_GREEN, s, consent_pressed_key == "allow")
	UIKit.centered_title(self, allow_face, "ALLOW", roundi(21.0 * s), Color.WHITE)
	var decline_face := UIKit.gloss_button(self, consent_decline_rect, UIKit.BTN_BLUE, s, consent_pressed_key == "decline")
	UIKit.centered_title(self, decline_face, "NO THANKS", roundi(21.0 * s), Color.WHITE)


func _draw_message() -> void:
	var s := ui_scale
	var size := roundi(20.0 * s)
	var width := minf(UIKit.heavy_width(message, size) + 60.0 * s, screen_size.x - 40.0 * s)
	var area := _area()
	var pop := clampf((2.6 - message_timer) / 0.15, 0.0, 1.0)
	var alpha := minf(1.0, message_timer * 3.0)
	var rect := Rect2(screen_size.x * 0.5 - width * 0.5, area.end.y - 170.0 * s + (1.0 - pop) * 20.0 * s, width, 52.0 * s)
	UIKit.round_rect(self, Rect2(rect.position + Vector2(0, 5.0 * s), rect.size), 26.0 * s, Color(0.0, 0.0, 0.1, 0.3 * alpha))
	UIKit.round_rect(self, rect, 26.0 * s, Color(INK.r, INK.g, INK.b, 0.92 * alpha), Color(1.0, 1.0, 1.0, 0.8 * alpha), 3.0 * s)
	UIKit.title(self, Vector2(rect.position.x, rect.get_center().y + size * 0.36), message, size, Color(1.0, 1.0, 1.0, alpha), rect.size.x, HORIZONTAL_ALIGNMENT_CENTER, Color(INK.r, INK.g, INK.b, alpha), 0, false)


func _draw_logo(pos: Vector2) -> void:
	# "PEN FIGHT" in chunky gold letters, each one bobbing on its own beat, with a pen beside it.
	var s := ui_scale
	var size := roundi(54.0 * s)
	var x := pos.x + 64.0 * s
	var skin: Dictionary = Profile.seat_skin(0)
	var pen_scale := 70.0 * s / PenArt.PEN_LENGTH
	_set_xf(pos + Vector2(26.0 * s, -18.0 * s), -0.9 + sin(clock * 2.0) * 0.08)
	PenArt.body(self, skin, pen_scale * 1.6, Color.WHITE, false)
	_reset_xf()
	var letters := "PEN FIGHT"
	for k in range(letters.length()):
		var letter := letters[k]
		var bob := sin(clock * 3.0 + float(k) * 0.55) * 3.0 * s
		var fill := UIKit.GOLD if k < 3 else Color("#ff8f5a")
		UIKit.title(self, Vector2(x, pos.y + bob), letter, size, fill, -1, HORIZONTAL_ALIGNMENT_LEFT, INK, roundi(13.0 * s))
		x += UIKit.heavy_width(letter, size) + (2.0 * s if letter != " " else 0.0)


func _draw_home() -> void:
	var s := ui_scale
	var area := _area()
	_draw_logo(Vector2(area.position.x, area.position.y + 50.0 * s))
	var leos_left := _draw_leos_pill(area.end.x, area.position.y)
	var logo_end := area.position.x + 64.0 * s + UIKit.heavy_width("PEN FIGHT", roundi(54.0 * s)) + 30.0 * s
	_draw_level_pill(logo_end, leos_left - 14.0 * s, area.position.y)
	var bottom_height := 100.0 * s
	var body := Rect2(area.position.x, area.position.y + 96.0 * s, area.size.x, area.size.y - 96.0 * s - bottom_height - 18.0 * s)
	var left_width := body.size.x * 0.56
	_draw_players_panel(Rect2(body.position, Vector2(left_width, body.size.y)))
	_draw_seat_card(Rect2(body.position.x + left_width + 24.0 * s, body.position.y, body.size.x - left_width - 24.0 * s, body.size.y))
	_draw_bottom_bar(Rect2(area.position.x, area.end.y - bottom_height, area.size.x, bottom_height))


func _draw_players_panel(panel: Rect2) -> void:
	var s := ui_scale
	UIKit.panel(self, panel, s)
	UIKit.ribbon(self, Vector2(panel.position.x + 128.0 * s, panel.position.y + 4.0 * s), 170.0 * s, 46.0 * s, UIKit.BTN_BLUE, s)
	UIKit.title(self, Vector2(panel.position.x + 43.0 * s, panel.position.y + 13.0 * s), "PLAYERS", roundi(24.0 * s), WHITE, 170.0 * s, HORIZONTAL_ALIGNMENT_CENTER)
	# How many pens are on the desk.
	var button_size := Vector2(62.0, 54.0) * s
	var gap := 8.0 * s
	var first_x := panel.end.x - 20.0 * s - button_size.x * 3.0 - gap * 2.0
	for k in range(3):
		var count := k + 2
		var rect := Rect2(first_x + float(k) * (button_size.x + gap), panel.position.y + 16.0 * s, button_size.x, button_size.y)
		_gloss(rect, UIKit.BTN_GREEN if Profile.player_count == count else Color("#d9cfe6"), "count", count, str(count), 24.0)
	var top := panel.position.y + 84.0 * s
	var row_gap := 10.0 * s
	var room := panel.end.y - 16.0 * s - top
	var row_height := minf(112.0 * s, (room - row_gap * 3.0) / 4.0)
	top += (room - row_height * 4.0 - row_gap * 3.0) * 0.5
	for i in range(Profile.MAX_SEATS):
		_draw_seat_row(Rect2(panel.position.x + 16.0 * s, top + float(i) * (row_height + row_gap), panel.size.x - 32.0 * s, row_height), i)


func _draw_seat_row(rect: Rect2, index: int) -> void:
	var s := ui_scale
	var active := index < Profile.player_count
	var config: Dictionary = Profile.seats[index]
	var human := bool(config["human"])
	var seat_color := UIKit.SEAT_COLORS[index]
	var radius := 20.0 * s
	if not active:
		# An empty seat: tap it to bring in another player.
		UIKit.round_rect(self, rect, radius, Color(1.0, 1.0, 1.0, 0.0), Color(INK.r, INK.g, INK.b, 0.25), 3.0 * s)
		var plus := Vector2(rect.position.x + 44.0 * s, rect.get_center().y)
		draw_circle(plus, 22.0 * s, Color(INK.r, INK.g, INK.b, 0.12))
		UIKit.icon(self, "plus", plus, 26.0 * s, Color(INK.r, INK.g, INK.b, 0.4), s, false)
		UIKit.title(self, Vector2(rect.position.x + 80.0 * s, rect.get_center().y + 7.0 * s), "Add player %d" % (index + 1), roundi(19.0 * s), Color(INK.r, INK.g, INK.b, 0.45), -1, HORIZONTAL_ALIGNMENT_LEFT, INK, 0, false)
		_add_button(rect, "add_seat", index)
		return
	var chosen := selected_seat == index
	if chosen:
		var glow := 0.5 + 0.5 * sin(clock * 4.0)
		UIKit.round_rect(self, rect.grow(5.0 * s), radius + 5.0 * s, Color(seat_color.r, seat_color.g, seat_color.b, 0.35 + 0.25 * glow))
	UIKit.round_rect(self, Rect2(rect.position + Vector2(0.0, 4.0 * s), rect.size), radius, UIKit.PANEL_DEEP.darkened(0.25), INK, 3.0 * s)
	UIKit.round_rect(self, rect, radius, Color("#fffdf7") if chosen else UIKit.PANEL_DEEP, INK, 3.0 * s)
	_add_button(rect, "select_seat", index)
	# Avatar.
	var avatar := Vector2(rect.position.x + 44.0 * s, rect.get_center().y)
	var face := UIKit.gloss_circle(self, avatar, 27.0 * s, seat_color, s)
	UIKit.icon(self, "user" if human else "robot", face, 30.0 * s, WHITE, s)
	var name_text := "You" if index == 0 else ("Player %d" % (index + 1) if human else "CPU %d" % (index + 1))
	UIKit.title(self, Vector2(rect.position.x + 84.0 * s, rect.get_center().y - 2.0 * s), name_text, roundi(22.0 * s), INK, 150.0 * s, HORIZONTAL_ALIGNMENT_LEFT, INK, 0, false)
	var role := "Player 1" if index == 0 else ("Human player" if human else "Computer")
	draw_string(FONT, Vector2(rect.position.x + 85.0 * s, rect.get_center().y + 20.0 * s), role, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(14.0 * s), UIKit.MUTED)
	# Human / computer switch; the first seat is always you.
	var chip := Rect2(rect.position.x + 228.0 * s, rect.get_center().y - 25.0 * s, 128.0 * s, 50.0 * s)
	if index == 0:
		_gloss(chip, UIKit.BTN_GREEN, "select_seat", index, "YOU", 18.0, true, "user")
	else:
		_gloss(chip, UIKit.BTN_YELLOW if human else UIKit.BTN_BLUE, "seat_type", index, "HUMAN" if human else "CPU", 18.0, true, "user" if human else "robot")
	# The pen this player brings.
	var area := Rect2(chip.end.x + 12.0 * s, rect.position.y + 6.0 * s, rect.end.x - chip.end.x - 18.0 * s, rect.size.y - 12.0 * s)
	if human:
		var pen_id := str(config["pen"])
		_draw_pen_preview(Profile.seat_skin(index), area.get_center() + Vector2(0.0, -8.0 * s), minf(area.size.x * 0.82, 170.0 * s), float(index), false)
		draw_string(FONT, Vector2(area.position.x, area.end.y - 4.0 * s), str(Profile.pen_info(pen_id)["name"]), HORIZONTAL_ALIGNMENT_CENTER, area.size.x, roundi(14.0 * s), UIKit.MUTED)
		_add_button(area, "edit_pen", index)
	else:
		# The level the computer plays at, which is yours; on boss levels the first computer is the boss.
		var boss := Levels.is_boss(Profile.level) and _first_cpu_seat() == index
		var badge := Vector2(area.position.x + 34.0 * s, area.get_center().y)
		UIKit.level_badge(self, badge, 26.0 * s, Profile.level, Levels.rank_color(Profile.level), s, false)
		if boss:
			UIKit.crown(self, badge + Vector2(0.0, -30.0 * s), 22.0 * s, UIKit.GOLD, s)
		var text_x := badge.x + 36.0 * s
		UIKit.title(self, Vector2(text_x, area.get_center().y - 2.0 * s), "BOSS" if boss else Levels.difficulty_name(Profile.level), roundi(17.0 * s), UIKit.BTN_RED if boss else INK, area.end.x - text_x, HORIZONTAL_ALIGNMENT_LEFT, INK, 0, false)
		draw_string(FONT, Vector2(text_x, area.get_center().y + 18.0 * s), "plays at level %d" % Profile.level, HORIZONTAL_ALIGNMENT_LEFT, area.end.x - text_x, roundi(13.0 * s), UIKit.MUTED)


func _draw_seat_card(card: Rect2) -> void:
	var s := ui_scale
	var seat := selected_seat
	var config: Dictionary = Profile.seats[seat]
	var seat_color := UIKit.SEAT_COLORS[seat]
	UIKit.panel(self, card, s)
	var center_x := card.get_center().x
	var name_text := "YOU" if seat == 0 else "PLAYER %d" % (seat + 1)
	var ribbon_width := minf(card.size.x - 90.0 * s, 230.0 * s)
	UIKit.ribbon(self, Vector2(center_x, card.position.y + 4.0 * s), ribbon_width, 46.0 * s, seat_color, s)
	UIKit.title(self, Vector2(center_x - ribbon_width * 0.5, card.position.y + 13.0 * s), name_text, roundi(24.0 * s), WHITE, ribbon_width, HORIZONTAL_ALIGNMENT_CENTER)
	var inner := card.grow(-18.0 * s)
	if not bool(config["human"]):
		var bot := Vector2(center_x, inner.position.y + (inner.size.y - 70.0 * s) * 0.45)
		_spotlight(bot, 110.0 * s, seat_color)
		var face := UIKit.gloss_circle(self, bot, 58.0 * s, seat_color, s)
		UIKit.icon(self, "robot", face, 66.0 * s, WHITE, s)
		var boss := Levels.is_boss(Profile.level) and _first_cpu_seat() == seat
		if boss:
			UIKit.crown(self, face + Vector2(0.0, -70.0 * s), 50.0 * s, UIKit.GOLD, s)
		UIKit.level_badge(self, face + Vector2(56.0 * s, -44.0 * s), 30.0 * s, Profile.level, Levels.rank_color(Profile.level), s, false)
		UIKit.title(self, Vector2(card.position.x, bot.y + 100.0 * s), "LEVEL %d BOSS" % Profile.level if boss else "COMPUTER", roundi(28.0 * s), UIKit.BTN_RED if boss else INK, card.size.x, HORIZONTAL_ALIGNMENT_CENTER, INK, 0, false)
		var about := "Beat it to rank up!" if boss else "Plays at your level: %s" % Levels.difficulty_name(Profile.level)
		draw_string(FONT, Vector2(card.position.x, bot.y + 128.0 * s), about, HORIZONTAL_ALIGNMENT_CENTER, card.size.x, roundi(16.0 * s), UIKit.MUTED)
		_gloss(Rect2(center_x - 120.0 * s, inner.end.y - 64.0 * s, 240.0 * s, 64.0 * s), UIKit.BTN_YELLOW, "seat_type", seat, "MAKE HUMAN", 22.0, true, "user")
		return
	var pen_id := str(config["pen"])
	var info := Profile.pen_info(pen_id)
	var room := inner.size.y - 70.0 * s
	var stage := Vector2(center_x, inner.position.y + 92.0 * s + maxf(0.0, room - 330.0 * s) * 0.5)
	_spotlight(stage, 120.0 * s, seat_color)
	_draw_pen_preview(Profile.seat_skin(seat), stage, minf(card.size.x * 0.72, 360.0 * s), 0.0)
	UIKit.title(self, Vector2(card.position.x, stage.y + 100.0 * s), str(info["name"]).to_upper(), roundi(30.0 * s), WHITE, card.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var bars_width := minf(card.size.x - 70.0 * s, 330.0 * s)
	_draw_stats(Vector2(center_x - bars_width * 0.5, stage.y + 136.0 * s), bars_width, info)
	_draw_palette(center_x, stage.y + 214.0 * s, card.size.x - 40.0 * s, pen_id)
	_gloss(Rect2(center_x - 120.0 * s, inner.end.y - 62.0 * s, 240.0 * s, 62.0 * s), UIKit.BTN_YELLOW, "edit_pen", seat, "CHANGE PEN", 22.0, true, "shop")


func _draw_bottom_bar(bar: Rect2) -> void:
	var s := ui_scale
	# Shop and the features still to come.
	var tile := Vector2(104.0, bar.size.y)
	var x := bar.position.x
	var shop_seat := selected_seat if bool(Profile.seats[selected_seat]["human"]) else 0
	var tiles := [
		["PENS", "shop", UIKit.BTN_YELLOW, "edit_pen", shop_seat],
		["LEVELS", "trophy", UIKit.BTN_PURPLE, "levels", null],
		["ONLINE", "globe", UIKit.BTN_BLUE, "soon", "Online play"],
		["PRIVACY", "lock", UIKit.BTN_PURPLE, "privacy", null],
	]
	for entry in tiles:
		var rect := Rect2(x, bar.position.y, tile.x * s, tile.y)
		var id: String = entry[3]
		var arg: Variant = entry[4]
		var enabled := id != "soon"
		var face := UIKit.gloss_button(self, rect, entry[2] if enabled else Color(entry[2]).lerp(UIKit.BTN_GREY, 0.55), s, _is_pressed(id, arg))
		UIKit.icon(self, entry[1], face.get_center() + Vector2(0.0, -12.0 * s), 38.0 * s, WHITE, s)
		UIKit.title(self, Vector2(face.position.x, face.end.y - 12.0 * s), entry[0], roundi(16.0 * s), WHITE, face.size.x, HORIZONTAL_ALIGNMENT_CENTER, INK, roundi(4.0 * s))
		if not enabled:
			# A "SOON" tag pinned to the corner.
			var tag := Rect2(face.end.x - 46.0 * s, face.position.y - 10.0 * s, 54.0 * s, 24.0 * s)
			UIKit.round_rect(self, tag, 12.0 * s, UIKit.BTN_RED, INK, 2.5 * s)
			UIKit.title(self, Vector2(tag.position.x, tag.get_center().y + 5.0 * s), "SOON", roundi(13.0 * s), WHITE, tag.size.x, HORIZONTAL_ALIGNMENT_CENTER, INK, 0, false)
		_add_button(rect, id, arg)
		x += tile.x * s + 14.0 * s
	# The big PLAY button breathes to draw the thumb.
	var play_width := minf(360.0 * s, bar.end.x - x - 20.0 * s)
	var play := Rect2(bar.end.x - play_width, bar.position.y, play_width, bar.size.y)
	var breath := 1.0 + 0.035 * sin(clock * 4.0)
	draw_set_transform(play.get_center(), 0.0, Vector2(breath, breath))
	var local := Rect2(-play.size * 0.5, play.size)
	UIKit.sunburst(self, Vector2.ZERO, play.size.x * 0.75, 10, clock * 0.8, Color(1.0, 0.95, 0.6, 0.12))
	var face := UIKit.gloss_button(self, local, UIKit.BTN_GREEN, s, _is_pressed("play", null), 28.0 * s)
	var size := roundi(44.0 * s)
	var label_width := UIKit.heavy_width("PLAY", size)
	var start := face.get_center().x - (label_width + 54.0 * s) * 0.5
	UIKit.icon(self, "play", Vector2(start + 20.0 * s, face.get_center().y), 44.0 * s, WHITE, s)
	UIKit.title(self, Vector2(start + 54.0 * s, face.get_center().y + size * 0.36), "PLAY", size, WHITE)
	_reset_xf()
	_add_button(play, "play")


func _draw_pens() -> void:
	var s := ui_scale
	var area := _area()
	var humans := _human_seats()
	if not humans.has(selected_seat):
		selected_seat = humans[0] if not humans.is_empty() else 0
	# Header: back, title ribbon, leos.
	var back := Vector2(area.position.x + 32.0 * s, area.position.y + 32.0 * s)
	var face := UIKit.gloss_circle(self, back, 30.0 * s, UIKit.BTN_BLUE, s, _is_pressed("back", null))
	UIKit.icon(self, "back", face + Vector2(-2.0 * s, 0.0), 30.0 * s, WHITE, s)
	_add_button(Rect2(back - Vector2.ONE * 34.0 * s, Vector2.ONE * 68.0 * s), "back")
	UIKit.ribbon(self, Vector2(screen_size.x * 0.5, area.position.y + 30.0 * s), 300.0 * s, 54.0 * s, UIKit.BTN_RED, s)
	UIKit.title(self, Vector2(screen_size.x * 0.5 - 150.0 * s, area.position.y + 41.0 * s), "PEN SHOP", roundi(30.0 * s), WHITE, 300.0 * s, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_leos_pill(area.end.x, area.position.y)
	var body := Rect2(area.position.x, area.position.y + 92.0 * s, area.size.x, area.size.y - 92.0 * s)
	var grid_width := body.size.x * 0.64
	_draw_pen_grid(Rect2(body.position, Vector2(grid_width, body.size.y)))
	_draw_pen_side(Rect2(body.position.x + grid_width + 22.0 * s, body.position.y, body.size.x - grid_width - 22.0 * s, body.size.y))


func _draw_pen_side(side: Rect2) -> void:
	var s := ui_scale
	UIKit.panel(self, side, s)
	var center_x := side.get_center().x
	var humans := _human_seats()
	var y := side.position.y + 22.0 * s
	if humans.size() > 1:
		# One tab per human player: each chooses their own pen.
		var tab_width := minf(84.0 * s, (side.size.x - 40.0 * s) / float(humans.size()) - 8.0 * s)
		var total := tab_width * float(humans.size()) + 8.0 * s * float(humans.size() - 1)
		var x := center_x - total * 0.5
		for seat in humans:
			var tab := Rect2(x, y, tab_width, 50.0 * s)
			_gloss(tab, UIKit.SEAT_COLORS[seat] if seat == selected_seat else Color("#d9cfe6"), "tab_seat", seat, "P%d" % (seat + 1), 20.0)
			x += tab_width + 8.0 * s
		y += 64.0 * s
	else:
		UIKit.title(self, Vector2(side.position.x, y + 24.0 * s), "YOUR PEN", roundi(24.0 * s), INK, side.size.x, HORIZONTAL_ALIGNMENT_CENTER, INK, 0, false)
		y += 44.0 * s
	y += maxf(0.0, side.end.y - y - 350.0 * s) * 0.4
	var pen_id := str(Profile.seats[selected_seat]["pen"])
	var info := Profile.pen_info(pen_id)
	var stage := Vector2(center_x, y + 70.0 * s)
	_spotlight(stage, 100.0 * s, UIKit.SEAT_COLORS[selected_seat])
	_draw_pen_preview(Profile.seat_skin(selected_seat), stage, minf(side.size.x * 0.75, 330.0 * s), 0.4)
	UIKit.title(self, Vector2(side.position.x, y + 168.0 * s), str(info["name"]).to_upper(), roundi(28.0 * s), WHITE, side.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var bars_width := minf(side.size.x - 56.0 * s, 300.0 * s)
	_draw_stats(Vector2(center_x - bars_width * 0.5, y + 204.0 * s), bars_width, info)
	UIKit.title(self, Vector2(side.position.x, y + 274.0 * s), "PEN COLOR", roundi(15.0 * s), UIKit.MUTED, side.size.x, HORIZONTAL_ALIGNMENT_CENTER, INK, 0, false)
	_draw_palette(center_x, y + 310.0 * s, side.size.x - 36.0 * s, pen_id)


func _draw_pen_grid(area: Rect2) -> void:
	var s := ui_scale
	var pens := Profile.pens
	var columns := 3
	var gap := 18.0 * s
	var rows := ceili(float(pens.size()) / float(columns))
	var card_width := (area.size.x - gap * float(columns - 1)) / float(columns)
	var card_height := (area.size.y - gap * float(rows - 1)) / float(rows)
	var seat_pen := str(Profile.seats[selected_seat]["pen"])
	for i in range(pens.size()):
		var column := i % columns
		var row := floori(float(i) / float(columns))
		var rect := Rect2(area.position.x + float(column) * (card_width + gap), area.position.y + float(row) * (card_height + gap), card_width, card_height - 8.0 * s)
		_draw_pen_card(pens[i], rect, i, seat_pen)


func _draw_pen_card(pen: Dictionary, rect: Rect2, index: int, seat_pen: String) -> void:
	var s := ui_scale
	var id: String = pen["id"]
	var owned := Profile.owns(id)
	var chosen := id == seat_pen
	var tier := _tier(pen)
	var tier_color: Color = tier[1]
	if chosen:
		var glow := 0.5 + 0.5 * sin(clock * 4.0)
		UIKit.round_rect(self, rect.grow(7.0 * s), 30.0 * s, Color(UIKit.GOLD.r, UIKit.GOLD.g, UIKit.GOLD.b, 0.45 + 0.35 * glow))
	UIKit.panel(self, rect, s, UIKit.PANEL, 22.0 * s)
	# A colored stage tells the pen's rarity at a glance.
	var stage := Rect2(rect.position + Vector2(10.0, 10.0) * s, Vector2(rect.size.x - 20.0 * s, rect.size.y * 0.5))
	UIKit.round_rect(self, stage, 16.0 * s, tier_color.lerp(Color.WHITE, 0.25), INK, 2.5 * s)
	UIKit.sunburst(self, stage.get_center(), stage.size.x * 0.6, 10, clock * 0.25 + float(index), Color(1.0, 1.0, 1.0, 0.16))
	var label_size := roundi(13.0 * s)
	var tag := Rect2(stage.position + Vector2(8.0, 8.0) * s, Vector2(UIKit.heavy_width(str(tier[0]), label_size) + 20.0 * s, 24.0 * s))
	UIKit.round_rect(self, tag, 12.0 * s, tier_color.darkened(0.25), INK, 2.0 * s)
	UIKit.title(self, Vector2(tag.position.x, tag.get_center().y + label_size * 0.36), str(tier[0]), label_size, WHITE, tag.size.x, HORIZONTAL_ALIGNMENT_CENTER, INK, 0, false)
	_draw_pen_preview(PenData.recolor(pen, Profile.seat_color(selected_seat)) if owned else pen, stage.get_center() + Vector2(6.0 * s, 8.0 * s), minf(stage.size.x * 0.82, 220.0 * s), float(index) * 0.9)
	if not owned:
		var lock := Vector2(stage.end.x - 22.0 * s, stage.position.y + 22.0 * s)
		draw_circle(lock, 16.0 * s, INK)
		UIKit.icon(self, "lock", lock, 20.0 * s, WHITE, s, false)
	UIKit.title(self, Vector2(rect.position.x, stage.end.y + 32.0 * s), str(pen["name"]).to_upper(), roundi(21.0 * s), INK, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER, INK, 0, false)
	var stats := "Power +%d%%   Weight %.2f" % [roundi((float(pen["punch"]) - 1.0) * 100.0), float(pen["mass"])]
	draw_string(FONT, Vector2(rect.position.x, stage.end.y + 54.0 * s), stats, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, roundi(14.0 * s), UIKit.MUTED)
	var button := Rect2(rect.position.x + 14.0 * s, rect.end.y - 64.0 * s, rect.size.x - 28.0 * s, 54.0 * s)
	if chosen:
		var face := UIKit.gloss_button(self, button, UIKit.BTN_GREEN, s)
		UIKit.icon(self, "check", Vector2(face.get_center().x - 58.0 * s, face.get_center().y), 24.0 * s, WHITE, s)
		UIKit.title(self, Vector2(face.position.x + 24.0 * s, face.get_center().y + 7.0 * s), "EQUIPPED", roundi(19.0 * s), WHITE, face.size.x - 24.0 * s, HORIZONTAL_ALIGNMENT_CENTER, INK, 4)
	elif owned:
		_gloss(button, UIKit.BTN_BLUE, "pen", id, "SELECT", 20.0)
	else:
		var price := int(pen["price"])
		var affordable := Profile.leos >= price
		var face := UIKit.gloss_button(self, button, UIKit.BTN_YELLOW if affordable else UIKit.BTN_GREY, s, _is_pressed("pen", id))
		var price_size := roundi(22.0 * s)
		var price_text := str(price)
		var start := face.get_center().x - (UIKit.heavy_width(price_text, price_size) + 34.0 * s) * 0.5
		UIKit.coin(self, Vector2(start + 12.0 * s, face.get_center().y), 12.0 * s, s)
		UIKit.title(self, Vector2(start + 32.0 * s, face.get_center().y + price_size * 0.36), price_text, price_size, WHITE, -1, HORIZONTAL_ALIGNMENT_LEFT, INK, 5)
		_add_button(button, "pen", id)


# ------------------------------------------------------------------ levels

func _first_cpu_seat() -> int:
	for i in range(Profile.player_count):
		if not bool(Profile.seats[i]["human"]):
			return i
	return -1


func _level_note(level: int) -> String:
	var computer := "computer: %s" % Levels.difficulty_name(level)
	if level < Profile.level:
		return "Level %d cleared  ·  %s" % [level, computer]
	if level == Profile.level:
		return "You are here: level %d  ·  %s" % [level, computer]
	if level >= Levels.MAX_LEVEL:
		return "Level 50: the final boss  ·  win crowns here"
	if Levels.is_boss(level):
		return "Level %d boss: beat it to become %s" % [level, str(Levels.rank(level + 1)["name"])]
	return "Level %d  ·  %s" % [level, computer]


func _draw_xp_bar(bar: Rect2, fill: float, color: Color, back: Color) -> void:
	var s := ui_scale
	UIKit.round_rect(self, bar, bar.size.y * 0.5, back, INK, 2.5 * s)
	if fill > 0.01:
		var filled := Rect2(bar.position, Vector2(maxf(bar.size.y, bar.size.x * minf(fill, 1.0)), bar.size.y))
		UIKit.round_rect(self, filled, bar.size.y * 0.5, color, INK, 2.5 * s)
		draw_rect(Rect2(filled.position + Vector2(bar.size.y * 0.4, bar.size.y * 0.2), Vector2(maxf(0.0, filled.size.x - bar.size.y * 0.8), bar.size.y * 0.2)), Color(1.0, 1.0, 1.0, 0.45))


func _bar_fill() -> float:
	if Profile.level >= Levels.MAX_LEVEL:
		return 1.0
	return clampf(float(Profile.xp) / float(Levels.xp_to_next(Profile.level)), 0.0, 1.0)


func _draw_level_pill(left_limit: float, right: float, top: float) -> void:
	# Your level in the header: the badge, the rank and how full the bar is. Tap to see the climb.
	var s := ui_scale
	var width := clampf(right - left_limit, 0.0, 260.0 * s)
	if width < 170.0 * s:
		return
	var rect := Rect2(right - width, top, width, 58.0 * s)
	var color := Levels.rank_color(Profile.level)
	var face := UIKit.gloss_button(self, rect, Color("#3a2f8f"), s, _is_pressed("levels", null))
	var badge := Vector2(face.position.x + 26.0 * s, face.get_center().y)
	UIKit.level_badge(self, badge, 31.0 * s, Profile.level, color, s, false)
	var text_x := badge.x + 40.0 * s
	var label_size := roundi(17.0 * s)
	UIKit.title(self, Vector2(text_x, face.position.y + 23.0 * s), str(Levels.rank(Profile.level)["name"]).to_upper(), label_size, WHITE, face.end.x - text_x - 12.0 * s, HORIZONTAL_ALIGNMENT_LEFT, INK, roundi(4.0 * s), false)
	var bar := Rect2(text_x, face.position.y + 30.0 * s, face.end.x - text_x - 14.0 * s, 13.0 * s)
	_draw_xp_bar(bar, _bar_fill(), color, Color("#241b63"))
	if Profile.boss_gate():
		# The bar is full: a pulsing crown says the boss is waiting.
		var pulse := 1.0 + 0.12 * sin(clock * 6.0)
		UIKit.crown(self, Vector2(face.end.x - 22.0 * s, face.position.y + 14.0 * s), 20.0 * s * pulse, UIKit.GOLD, s)
	_add_button(rect, "levels")


func _draw_levels() -> void:
	var s := ui_scale
	var area := _area()
	var back := Vector2(area.position.x + 32.0 * s, area.position.y + 32.0 * s)
	var face := UIKit.gloss_circle(self, back, 30.0 * s, UIKit.BTN_BLUE, s, _is_pressed("back", null))
	UIKit.icon(self, "back", face + Vector2(-2.0 * s, 0.0), 30.0 * s, WHITE, s)
	_add_button(Rect2(back - Vector2.ONE * 34.0 * s, Vector2.ONE * 68.0 * s), "back")
	UIKit.ribbon(self, Vector2(screen_size.x * 0.5, area.position.y + 30.0 * s), 300.0 * s, 54.0 * s, UIKit.BTN_PURPLE, s)
	UIKit.title(self, Vector2(screen_size.x * 0.5 - 150.0 * s, area.position.y + 41.0 * s), "LEVELS", roundi(30.0 * s), WHITE, 300.0 * s, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_leos_pill(area.end.x, area.position.y)
	var body := Rect2(area.position.x, area.position.y + 92.0 * s, area.size.x, area.size.y - 92.0 * s)
	var side_width := clampf(body.size.x * 0.33, 300.0 * s, 400.0 * s)
	_draw_level_card(Rect2(body.position, Vector2(side_width, body.size.y)))
	_draw_level_road(Rect2(body.position.x + side_width + 22.0 * s, body.position.y, body.size.x - side_width - 22.0 * s, body.size.y))


func _draw_level_card(card: Rect2) -> void:
	# Where you stand: your badge and bar, your record, and how the computer plays right now.
	var s := ui_scale
	var level := Profile.level
	var color := Levels.rank_color(level)
	var center_x := card.get_center().x
	UIKit.panel(self, card, s)
	var rank_name := str(Levels.rank(level)["name"]).to_upper()
	var ribbon_width := minf(card.size.x - 90.0 * s, UIKit.heavy_width(rank_name, roundi(24.0 * s)) + 60.0 * s)
	var band := UIKit.ribbon(self, Vector2(center_x, card.position.y + 4.0 * s), ribbon_width, 46.0 * s, color, s)
	UIKit.centered_title(self, band, rank_name, roundi(24.0 * s), WHITE)
	var top := card.position.y + 34.0 * s
	var room := card.size.y - 34.0 * s
	var y := top + maxf(0.0, room - 520.0 * s) * 0.3
	var badge := Vector2(center_x, y + 86.0 * s)
	_spotlight(badge, 96.0 * s, color)
	var bob := sin(clock * 2.0) * 3.0 * s
	UIKit.level_badge(self, badge + Vector2(0.0, bob), 60.0 * s, level, color, s)
	if Levels.is_boss(level) or level >= Levels.MAX_LEVEL:
		UIKit.crown(self, badge + Vector2(0.0, bob - 70.0 * s), 38.0 * s, UIKit.GOLD, s)
	# The bar to the next level.
	var bar_width := minf(card.size.x - 60.0 * s, 320.0 * s)
	var bar := Rect2(center_x - bar_width * 0.5, y + 176.0 * s, bar_width, 22.0 * s)
	var caption := ""
	var caption_color := INK
	if level >= Levels.MAX_LEVEL:
		caption = "MAX LEVEL  ·  %d crown%s" % [Profile.crowns, "" if Profile.crowns == 1 else "s"]
	elif Profile.boss_gate():
		caption = "BAR FULL — BEAT THE BOSS!"
		caption_color = UIKit.BTN_RED
	else:
		caption = "%d / %d XP" % [Profile.xp, Levels.xp_to_next(level)]
	UIKit.title(self, Vector2(card.position.x, bar.position.y - 13.0 * s), caption, roundi(17.0 * s), caption_color, card.size.x, HORIZONTAL_ALIGNMENT_CENTER, INK, 0, false)
	_draw_xp_bar(bar, _bar_fill(), color, Color("#e4d5b8"))
	var next_text := "Boss level — win to rank up" if Levels.is_boss(level) and level < Levels.MAX_LEVEL else ("The top of the climb" if level >= Levels.MAX_LEVEL else "Next boss: level %d" % Levels.next_boss(level))
	draw_string(FONT, Vector2(card.position.x, bar.end.y + 22.0 * s), next_text, HORIZONTAL_ALIGNMENT_CENTER, card.size.x, roundi(14.0 * s), UIKit.MUTED)
	# Your record against the computer.
	var stats := [
		["MATCHES", str(Profile.matches)],
		["WINS", str(Profile.wins)],
		["WIN RATE", "%d%%" % roundi(Profile.win_rate() * 100.0)],
		["BEST STREAK", str(Profile.best_streak)],
		["STREAK", str(Profile.streak)],
		["XP BOOST", "x%.2f" % Levels.form_multiplier(Profile.recent)],
	]
	var grid_top := bar.end.y + 44.0 * s
	var cell := Vector2((card.size.x - 48.0 * s) / 3.0, 58.0 * s)
	for k in range(stats.size()):
		var column := k % 3
		var row := floori(float(k) / 3.0)
		var rect := Rect2(card.position.x + 24.0 * s + float(column) * cell.x, grid_top + float(row) * (cell.y + 8.0 * s), cell.x - 8.0 * s, cell.y)
		UIKit.round_rect(self, rect, 14.0 * s, UIKit.PANEL_DEEP, Color(INK.r, INK.g, INK.b, 0.4), 2.0 * s)
		UIKit.title(self, Vector2(rect.position.x, rect.position.y + 30.0 * s), str(stats[k][1]), roundi(22.0 * s), INK, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER, INK, 0, false)
		draw_string(FONT, Vector2(rect.position.x, rect.position.y + 49.0 * s), str(stats[k][0]), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, roundi(12.0 * s), UIKit.MUTED)
	# Form: the last ten results, newest on the right. More wins here means more XP per match.
	var form_y := grid_top + 2.0 * (cell.y + 8.0 * s) + 18.0 * s
	draw_string(FONT, Vector2(card.position.x, form_y), "FORM — LAST %d MATCHES" % Levels.FORM_GAMES, HORIZONTAL_ALIGNMENT_CENTER, card.size.x, roundi(13.0 * s), UIKit.MUTED)
	var dot_gap := minf(26.0 * s, (card.size.x - 60.0 * s) / float(Levels.FORM_GAMES))
	var dots_x := center_x - dot_gap * float(Levels.FORM_GAMES - 1) * 0.5
	var missing := Levels.FORM_GAMES - Profile.recent.size()
	for k in range(Levels.FORM_GAMES):
		var dot := Vector2(dots_x + float(k) * dot_gap, form_y + 20.0 * s)
		draw_circle(dot, 9.5 * s, INK)
		if k < missing:
			draw_circle(dot, 7.0 * s, Color("#e4d5b8"))
		else:
			var won: bool = Profile.recent[k - missing]
			draw_circle(dot, 7.0 * s, UIKit.BTN_GREEN if won else UIKit.BTN_RED)
	# How the computer plays at this level.
	var cpu_y := form_y + 58.0 * s
	var chip := Rect2(card.position.x + 24.0 * s, cpu_y, card.size.x - 48.0 * s, 46.0 * s)
	if chip.end.y < card.end.y - 8.0 * s:
		UIKit.round_rect(self, chip, 16.0 * s, Color(INK.r, INK.g, INK.b, 0.88))
		UIKit.icon(self, "robot", Vector2(chip.position.x + 26.0 * s, chip.get_center().y), 26.0 * s, WHITE, s, false)
		var skill := roundi(clampf(Levels.cpu_skill(level, Levels.is_boss(level)), 0.0, 1.0) * 100.0)
		var line := "Computer: %s  ·  skill %d%%" % [Levels.difficulty_name(level), skill]
		UIKit.title(self, Vector2(chip.position.x + 48.0 * s, chip.get_center().y + 6.0 * s), line, roundi(16.0 * s), WHITE, chip.size.x - 56.0 * s, HORIZONTAL_ALIGNMENT_LEFT, INK, 0, false)


func _draw_level_road(panel: Rect2) -> void:
	# All fifty levels, a row of ten per rank, each ending in its boss. Done levels shine in their
	# rank color, yours pulses, the ones ahead wait in grey.
	var s := ui_scale
	UIKit.panel(self, panel, s)
	var rows := 5
	var inner := panel.grow(-18.0 * s)
	var row_height := inner.size.y / float(rows)
	var label_width := minf(170.0 * s, inner.size.x * 0.24)
	var start_x := inner.position.x + label_width + 8.0 * s
	var spacing := (inner.end.x - start_x) / 10.0
	var node_radius := minf(spacing * 0.34, 21.0 * s)
	for row in range(rows):
		var row_center := inner.position.y + (float(row) + 0.55) * row_height
		var rank_index := row
		var rank: Dictionary = Levels.RANKS[rank_index]
		var rank_color: Color = rank["color"]
		var reached := Profile.level >= int(rank["from"])
		# The rank's name plate.
		var plate := Rect2(inner.position.x, row_center - 21.0 * s, label_width - 6.0 * s, 42.0 * s)
		UIKit.round_rect(self, plate, 14.0 * s, rank_color if reached else Color("#d9cfe6"), INK, 2.5 * s)
		var name_text := str(rank["name"]).to_upper()
		var name_size := roundi(minf(16.0 * s, (plate.size.x - 16.0 * s) / maxf(1.0, UIKit.heavy_width(name_text, 16)) * 16.0))
		UIKit.title(self, Vector2(plate.position.x, plate.get_center().y + name_size * 0.36), name_text, name_size, WHITE if reached else Color("#8f86a3"), plate.size.x, HORIZONTAL_ALIGNMENT_CENTER, INK, roundi(4.0 * s) if reached else 0, false)
		draw_string(FONT, Vector2(plate.position.x, plate.end.y + 15.0 * s), "Levels %d–%d" % [row * 10 + 1, row * 10 + 10], HORIZONTAL_ALIGNMENT_CENTER, plate.size.x, roundi(12.0 * s), UIKit.MUTED)
		# The path that joins the row's levels.
		var first := Vector2(start_x + spacing * 0.5, row_center)
		var last := Vector2(start_x + spacing * 9.5, row_center)
		draw_line(first, last, INK, 9.0 * s, true)
		draw_line(first, last, Color("#d9cfe6"), 5.0 * s, true)
		var done_to := clampf(float(Profile.level - (row * 10 + 1)) / 9.0, 0.0, 1.0)
		if done_to > 0.0:
			draw_line(first, first.lerp(last, done_to), rank_color, 5.0 * s, true)
		for k in range(10):
			var level := row * 10 + k + 1
			_draw_level_node(Vector2(start_x + spacing * (float(k) + 0.5), row_center), node_radius, level)


func _draw_level_node(center: Vector2, radius: float, level: int) -> void:
	var s := ui_scale
	var color := Levels.rank_color(level)
	var boss := Levels.is_boss(level)
	var r := radius * (1.2 if boss else 1.0)
	if level == Profile.level:
		# You are here: a pulsing glow and a full badge.
		var glow := 0.5 + 0.5 * sin(clock * 4.0)
		draw_circle(center, r * (1.75 + 0.15 * glow), Color(color.r, color.g, color.b, 0.3 + 0.2 * glow))
		UIKit.level_badge(self, center, r * 1.45, level, color, s, false)
		var tip := center + Vector2(0.0, r * 1.45 + 12.0 * s + absf(sin(clock * 5.0)) * 4.0 * s)
		UIKit.outlined_polygon(self, PackedVector2Array([tip + Vector2(0.0, -10.0 * s), tip + Vector2(9.0, 4.0) * s, tip + Vector2(-9.0, 4.0) * s]), UIKit.GOLD, 2.5 * s)
	elif level < Profile.level:
		draw_circle(center + Vector2(0.0, 3.0 * s), r + 2.5 * s, INK)
		draw_circle(center, r + 2.5 * s, INK)
		draw_circle(center, r, color)
		draw_circle(center + Vector2(-r * 0.3, -r * 0.35), r * 0.25, Color(1.0, 1.0, 1.0, 0.45))
		var size := roundi(r * 0.85)
		UIKit.title(self, Vector2(center.x - r, center.y + size * 0.36), str(level), size, WHITE, r * 2.0, HORIZONTAL_ALIGNMENT_CENTER, INK, roundi(3.0 * s), false)
	else:
		draw_circle(center, r + 2.5 * s, INK)
		draw_circle(center, r, Color("#ece6f2"))
		var size := roundi(r * 0.8)
		UIKit.title(self, Vector2(center.x - r, center.y + size * 0.36), str(level), size, Color("#9a91ad"), r * 2.0, HORIZONTAL_ALIGNMENT_CENTER, INK, 0, false)
	if boss:
		var lift := r * (1.45 if level == Profile.level else 1.0) + 8.0 * s
		UIKit.crown(self, center + Vector2(0.0, -lift), 22.0 * s, UIKit.GOLD if level <= Profile.level else Color("#c9c0d8"), s)
	_add_button(Rect2(center - Vector2.ONE * (r + 8.0 * s), Vector2.ONE * (r * 2.0 + 16.0 * s)), "level_node", level)
