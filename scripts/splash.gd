extends Node2D
# The opening: the studio logo picks up exactly where the engine's boot splash left it, then
# gives way to the game's title: two pens swing in and clash, the letters drop into place,
# and the lobby follows. A tap skips ahead. The lobby loads in the background meanwhile.

const UIKit := preload("res://scripts/ui_kit.gd")
const PenArt := preload("res://scripts/pen_art.gd")
const STUDIO_LOGO: Texture2D = preload("res://assets/branding/bondhuu_logo.png")
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const INK := UIKit.INK
const STUDIO_BG := Color("#fefefe")
const TITLE := "PEN FIGHT"
const TAGLINE := "FLICK  ·  CLASH  ·  WIN"

# The studio logo is switched off for now; set this to true to bring it back (and set the logo
# as the boot splash image in Project Settings so the hand-off is seamless).
const SHOW_STUDIO := false
const STUDIO_TIME := 1.7  # the studio logo holds this long...
const STUDIO_FADE := 0.5  # ...then dissolves into the title
const CLASH_TIME := 0.55  # title time at which the pens meet
const LETTERS_START := 0.7
const LETTER_GAP := 0.07
const LETTER_DROP := 0.5
const TAGLINE_TIME := 1.65
const SHINE_TIME := 1.9
const TITLE_HOLD := 3.3  # title time before moving on
const OUT_FADE := 0.35

var screen_size := Vector2.ZERO
var ui_scale := 1.0
var clock := 0.0
var clashed := false
var landed := 0
var leaving := false
var out_fade := 0.0
var lobby: PackedScene
var previous_clear := Color.BLACK


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if SHOW_STUDIO:
		previous_clear = RenderingServer.get_default_clear_color()
		RenderingServer.set_default_clear_color(STUDIO_BG)
	else:
		clock = STUDIO_TIME
	ResourceLoader.load_threaded_request(LOBBY_SCENE)
	_update_layout()


func _process(delta: float) -> void:
	if get_viewport_rect().size != screen_size:
		_update_layout()
	clock += delta
	var tt := _title_time()
	if not clashed and tt >= CLASH_TIME:
		clashed = true
		Sfx.play("clack", 0.0, 0.85)
		Sfx.play("thud", -6.0)
	while landed < TITLE.length() and tt >= _letter_start(landed) + LETTER_DROP * 0.55:
		if TITLE[landed] != " ":
			Sfx.play("tap", -10.0, 1.0 + float(landed) * 0.04)
		landed += 1
	if lobby == null and ResourceLoader.load_threaded_get_status(LOBBY_SCENE) == ResourceLoader.THREAD_LOAD_LOADED:
		lobby = ResourceLoader.load_threaded_get(LOBBY_SCENE)
	if not leaving and tt >= TITLE_HOLD and lobby != null:
		leaving = true
	if leaving:
		out_fade = minf(1.0, out_fade + delta / OUT_FADE)
		if out_fade >= 1.0:
			set_process(false)
			if SHOW_STUDIO:
				RenderingServer.set_default_clear_color(previous_clear)
			get_tree().change_scene_to_packed(lobby)
	# A short shake when the pens clash.
	var shake := clampf(1.0 - (tt - CLASH_TIME) / 0.3, 0.0, 1.0) if clashed else 0.0
	position = Vector2(sin(clock * 90.0), cos(clock * 77.0)) * 7.0 * ui_scale * shake * shake
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var tapped := (event is InputEventScreenTouch or event is InputEventMouseButton) and event.is_pressed()
	if not tapped and not (event is InputEventKey and event.is_pressed()):
		return
	# First tap jumps to the title, a second one moves on as soon as the lobby is ready.
	if _title_time() < 0.0:
		clock = STUDIO_TIME + STUDIO_FADE
	else:
		clock = maxf(clock, STUDIO_TIME + TITLE_HOLD)


func _update_layout() -> void:
	var next_size := get_viewport_rect().size
	if next_size.x <= 0.0 or next_size.y <= 0.0:
		return
	screen_size = next_size
	ui_scale = clampf(minf(screen_size.x / 1280.0, screen_size.y / 720.0), 0.6, 1.4)


func _title_time() -> float:
	return clock - STUDIO_TIME


func _letter_start(k: int) -> float:
	return LETTERS_START + float(k) * LETTER_GAP


static func _ease_out_back(x: float, overshoot: float = 1.70158) -> float:
	var u := clampf(x, 0.0, 1.0) - 1.0
	return 1.0 + (overshoot + 1.0) * u * u * u + overshoot * u * u


static func _ease_out_cubic(x: float) -> float:
	var u := 1.0 - clampf(x, 0.0, 1.0)
	return 1.0 - u * u * u


func _draw() -> void:
	var tt := _title_time()
	if tt > 0.0:
		_draw_title(tt)
	# The studio logo, on top until it has dissolved.
	if SHOW_STUDIO:
		var studio_alpha := 1.0 - clampf(tt / STUDIO_FADE, 0.0, 1.0)
		if studio_alpha > 0.0:
			_draw_studio(studio_alpha)
	else:
		# Rise out of the boot screen's plain sky color.
		var rise := 1.0 - clampf(tt / 0.3, 0.0, 1.0)
		if rise > 0.0:
			var sky := UIKit.SKY_BOTTOM
			draw_rect(_cover_rect(), Color(sky.r, sky.g, sky.b, rise))
	if out_fade > 0.0:
		var sky := UIKit.SKY_BOTTOM
		draw_rect(_cover_rect(), Color(sky.r, sky.g, sky.b, out_fade))


func _cover_rect() -> Rect2:
	return Rect2(-position - Vector2(40.0, 40.0), screen_size + Vector2(80.0, 80.0))


func _draw_studio(alpha: float) -> void:
	draw_rect(_cover_rect(), Color(STUDIO_BG.r, STUDIO_BG.g, STUDIO_BG.b, alpha))
	# Placed the way the boot splash places it (fit inside the screen, centered), so the hand-off
	# is invisible; then it eases forward a touch and fades to white before the white dissolves.
	# (The logo has its own white background, so fading both together would show its square.)
	var logo_alpha := clampf((STUDIO_TIME - clock) / 0.4, 0.0, 1.0)
	if logo_alpha <= 0.0:
		return
	var tex_size := STUDIO_LOGO.get_size()
	var fit := minf(screen_size.x / tex_size.x, screen_size.y / tex_size.y)
	var grow := 1.0 + 0.035 * _ease_out_cubic(clock / STUDIO_TIME)
	var drawn := tex_size * fit * grow
	draw_texture_rect(STUDIO_LOGO, Rect2((screen_size - drawn) * 0.5, drawn), false, Color(1.0, 1.0, 1.0, logo_alpha * alpha))


func _draw_title(tt: float) -> void:
	var s := ui_scale
	UIKit.backdrop(self, screen_size, clock, s)
	var center := Vector2(screen_size.x * 0.5, screen_size.y * 0.44)
	_draw_glow(center, tt)
	_draw_pens(center, tt)
	_draw_clash_burst(center, tt)
	_draw_letters(center, tt)
	_draw_tagline(center, tt)
	_draw_loader(tt)


func _draw_glow(center: Vector2, tt: float) -> void:
	# A soft pool of light behind the title that blooms when the pens meet.
	var bloom := clampf((tt - CLASH_TIME + 0.1) / 0.6, 0.0, 1.0)
	var breathe := 0.9 + 0.1 * sin(clock * 2.2)
	for k in range(6):
		var r := (120.0 + float(k) * 55.0) * ui_scale * (0.6 + 0.4 * bloom) * breathe
		draw_circle(center, r, Color(1.0, 0.85, 0.45, 0.045 * bloom))


func _draw_pens(center: Vector2, tt: float) -> void:
	# Player one's pen from the left, player two's from the right; they swing in and cross in an X.
	var s := ui_scale
	var arrive := _ease_out_cubic(tt / CLASH_TIME)
	var recoil := sin(clampf((tt - CLASH_TIME) / 0.35, 0.0, 1.0) * PI) * 0.12
	var hover := sin(clock * 1.8) * 4.0 * s
	var pen_scale := 1.55 * s
	for side in range(2):
		var dir := -1.0 if side == 0 else 1.0
		var skin: Dictionary = Profile.seat_skin(side)
		var rest_angle := -0.62 if side == 0 else PI + 0.62
		var angle := rest_angle - dir * ((1.0 - arrive) * 1.4 + recoil)
		var from := center + Vector2(dir * screen_size.x * 0.75, screen_size.y * 0.35)
		var at := center + Vector2(dir * 18.0 * s, 26.0 * s + hover)
		draw_set_transform(from.lerp(at, arrive), angle, Vector2.ONE)
		# A motion streak while they are still flying in.
		var streak := 1.0 - arrive
		if streak > 0.02:
			PenArt.body(self, skin, pen_scale, Color(1.0, 1.0, 1.0, 0.25 * streak), true)
		PenArt.body(self, skin, pen_scale, Color.WHITE, false)
		if tt > CLASH_TIME:
			PenArt.idle(self, skin, float(side) * 1.3, pen_scale)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_clash_burst(center: Vector2, tt: float) -> void:
	var k := (tt - CLASH_TIME) / 0.55
	if k < 0.0 or k > 1.0:
		return
	var s := ui_scale
	var spot := center + Vector2(0.0, 26.0 * s)
	var fade := 1.0 - k
	var spread := _ease_out_cubic(k)
	draw_circle(spot, (30.0 + 40.0 * spread) * s, Color(1.0, 1.0, 1.0, 0.55 * fade * fade))
	draw_arc(spot, (40.0 + 170.0 * spread) * s, 0.0, TAU, 48, Color(1.0, 0.9, 0.5, 0.8 * fade), 6.0 * s * fade + 1.0, true)
	for i in range(12):
		var a := float(i) / 12.0 * TAU + 0.2
		var inner := (40.0 + 120.0 * spread) * s
		var outer := inner + 46.0 * s * fade
		draw_line(spot + Vector2.RIGHT.rotated(a) * inner, spot + Vector2.RIGHT.rotated(a) * outer, Color(1.0, 0.95, 0.7, fade), 5.0 * s * fade + 1.0, true)


func _draw_letters(center: Vector2, tt: float) -> void:
	# Each letter drops in and lands with a springy squash; once all are down, they bob gently
	# and a shine sweeps across.
	var s := ui_scale
	var size := roundi(132.0 * s)
	var outline := roundi(26.0 * s)
	var spacing := 4.0 * s
	var total := 0.0
	for k in range(TITLE.length()):
		total += UIKit.heavy_width(TITLE[k], size) + spacing
	total -= spacing
	var x := center.x - total * 0.5
	var shine_x := lerpf(-0.3, 1.3, clampf((tt - SHINE_TIME) / 0.7, 0.0, 1.0))
	for k in range(TITLE.length()):
		var letter := TITLE[k]
		var w := UIKit.heavy_width(letter, size)
		var local := (tt - _letter_start(k)) / LETTER_DROP
		if letter != " " and local > 0.0:
			var drop := _ease_out_back(local, 2.2)
			var squash := sin(clampf((local - 0.55) / 0.45, 0.0, 1.0) * PI) * 0.14
			var bob := sin(clock * 3.0 + float(k) * 0.55) * 3.0 * s * clampf(local - 1.0, 0.0, 1.0)
			var y := center.y - lerpf(screen_size.y * 0.7, 0.0, drop) + bob
			var fill := UIKit.GOLD if k < 3 else Color("#ff8f5a")
			var glint := clampf(1.0 - absf((x + w * 0.5 - center.x + total * 0.5) / total - shine_x) * 7.0, 0.0, 1.0)
			fill = fill.lerp(Color.WHITE, glint * 0.75)
			var pivot := Vector2(x + w * 0.5, y)
			var tilt := (1.0 - clampf(local, 0.0, 1.0)) * (0.35 if k % 2 == 0 else -0.35)
			draw_set_transform(pivot, tilt, Vector2(1.0 + squash, 1.0 - squash))
			UIKit.title(self, Vector2(-w * 0.5, float(size) * 0.36), letter, size, fill, -1, HORIZONTAL_ALIGNMENT_LEFT, INK, outline)
		x += w + spacing
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_tagline(center: Vector2, tt: float) -> void:
	var k := clampf((tt - TAGLINE_TIME) / 0.5, 0.0, 1.0)
	if k <= 0.0:
		return
	var s := ui_scale
	var size := roundi(26.0 * s)
	var e := _ease_out_cubic(k)
	var y := center.y + 120.0 * s + (1.0 - e) * 18.0 * s
	var width := UIKit.heavy_width(TAGLINE, size)
	var line := 70.0 * s * e
	var gap := 22.0 * s
	var tint := Color(1.0, 1.0, 1.0, 0.9 * e)
	draw_line(Vector2(center.x - width * 0.5 - gap - line, y - size * 0.32), Vector2(center.x - width * 0.5 - gap, y - size * 0.32), Color(UIKit.BTN_BLUE, e), 4.0 * s, true)
	draw_line(Vector2(center.x + width * 0.5 + gap, y - size * 0.32), Vector2(center.x + width * 0.5 + gap + line, y - size * 0.32), Color(Color("#ff8f5a"), e), 4.0 * s, true)
	UIKit.title(self, Vector2(center.x - width * 0.5, y), TAGLINE, size, tint, -1, HORIZONTAL_ALIGNMENT_LEFT, Color(INK, 0.8 * e), roundi(6.0 * s), false)


func _draw_loader(tt: float) -> void:
	# A slim progress bar along the bottom; it fills with the clock, held back by the real load.
	var appear := clampf((tt - TAGLINE_TIME) / 0.4, 0.0, 1.0)
	if appear <= 0.0:
		return
	var s := ui_scale
	var safe := UIKit.safe_rect(self)
	var width := minf(360.0 * s, safe.size.x * 0.5)
	var rect := Rect2(safe.get_center().x - width * 0.5, safe.end.y - 48.0 * s, width, 8.0 * s)
	var progress := clampf((tt - TAGLINE_TIME) / (TITLE_HOLD - TAGLINE_TIME), 0.0, 1.0)
	if lobby == null:
		var loaded := []
		ResourceLoader.load_threaded_get_status(LOBBY_SCENE, loaded)
		progress = minf(progress, maxf(0.9, float(loaded[0]) if not loaded.is_empty() else 0.0))
	UIKit.round_rect(self, rect, rect.size.y * 0.5, Color(0.0, 0.0, 0.1, 0.35 * appear))
	if progress > 0.0:
		var fill := Rect2(rect.position, Vector2(maxf(rect.size.y, rect.size.x * progress), rect.size.y))
		UIKit.round_rect(self, fill, rect.size.y * 0.5, Color(UIKit.GOLD, appear))
