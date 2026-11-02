extends RefCounted
# Draws pens, their idle animation and their trails. Used by the game and by the lobby.

const UIKit := preload("res://scripts/ui_kit.gd")
const PEN_LENGTH := 340.0
const PEN_HALF_LENGTH := 153.0
const PEN_RADIUS := 11.0


static func body(ci: CanvasItem, skin: Dictionary, s: float, tint: Color, flat: bool) -> void:
	# Pens are drawn from shapes so every skin can have its own colors and pattern.
	# The nib points along +x; tint.a is the opacity, and flat draws a single silhouette.
	var half := PEN_LENGTH * s * 0.5
	var r := PEN_RADIUS * s
	var tip_length := PEN_LENGTH * s * 0.15
	var grip_length := PEN_LENGTH * s * 0.17
	var body_front := half - tip_length
	var outline := PackedVector2Array()
	var back_center := Vector2(-half + r, 0.0)
	for i in range(9):
		var a := PI * 0.5 + PI * float(i) / 8.0
		outline.append(back_center + Vector2(cos(a), sin(a)) * r)
	outline.append(Vector2(body_front, -r))
	outline.append(Vector2(half, -r * 0.16))
	outline.append(Vector2(half, r * 0.16))
	outline.append(Vector2(body_front, r))
	if flat:
		ci.draw_colored_polygon(outline, tint)
		return
	var alpha := tint.a
	var barrel: Color = skin["barrel"]
	var accent: Color = skin["accent"]
	var tip: Color = skin["tip"]
	var barrel_start := -half + r
	var barrel_end := body_front - grip_length
	ci.draw_colored_polygon(outline, Color(barrel.r, barrel.g, barrel.b, alpha))
	var pattern: String = skin["pattern"]
	if pattern == "stripes":
		var x := barrel_start + r * 0.4
		while x < barrel_end - r:
			ci.draw_line(Vector2(x, -r * 0.92), Vector2(x + r * 0.9, r * 0.92), Color(accent.r, accent.g, accent.b, 0.55 * alpha), r * 0.45)
			x += r * 2.4
	elif pattern == "dots":
		var x := barrel_start + r * 1.2
		var row := 0
		while x < barrel_end - r:
			ci.draw_circle(Vector2(x, -r * 0.4 if row % 2 == 0 else r * 0.4), r * 0.24, Color(accent.r, accent.g, accent.b, 0.7 * alpha))
			x += r * 1.5
			row += 1
	elif pattern == "bands":
		for fraction in [0.3, 0.42]:
			var band_x := lerpf(barrel_start, barrel_end, fraction)
			ci.draw_rect(Rect2(band_x, -r * 0.94, r * 0.5, r * 1.88), Color(accent.r, accent.g, accent.b, 0.8 * alpha))
	elif pattern == "rainbow":
		var bands := 8
		var band_width := (barrel_end - barrel_start - r) / float(bands)
		for k in range(bands):
			var band_color := Color.from_hsv(float(k) / float(bands), 0.6, 1.0, 0.75 * alpha)
			ci.draw_rect(Rect2(barrel_start + r + float(k) * band_width, -r * 0.94, band_width + 0.5, r * 1.88), band_color)
	# Shading, grip, cap clip and nib.
	ci.draw_line(Vector2(barrel_start, -r * 0.5), Vector2(barrel_end - 4.0 * s, -r * 0.5), Color(1.0, 1.0, 1.0, 0.32 * alpha), r * 0.32)
	ci.draw_line(Vector2(barrel_start, r * 0.6), Vector2(barrel_end - 4.0 * s, r * 0.6), Color(0.0, 0.0, 0.0, 0.12 * alpha), r * 0.28)
	ci.draw_rect(Rect2(barrel_end, -r * 0.94, grip_length, r * 1.88), Color(accent.r, accent.g, accent.b, alpha))
	ci.draw_rect(Rect2(barrel_start + r * 1.6, -r - 3.0 * s, PEN_LENGTH * s * 0.2, 3.2 * s), Color(accent.r, accent.g, accent.b, alpha))
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(body_front, -r),
		Vector2(half, -r * 0.16),
		Vector2(half, r * 0.16),
		Vector2(body_front, r)
	]), Color(tip.r, tip.g, tip.b, alpha))
	ci.draw_circle(Vector2(half - 2.0 * s, 0.0), r * 0.2, Color(UIKit.INK.r, UIKit.INK.g, UIKit.INK.b, alpha))
	var closed := outline.duplicate()
	closed.append(outline[0])
	ci.draw_polyline(closed, Color(UIKit.INK.r, UIKit.INK.g, UIKit.INK.b, alpha), maxf(1.6, 2.4 * s), true)


static func idle(ci: CanvasItem, skin: Dictionary, phase: float, s: float) -> void:
	# Idle animation drawn in the pen's own space: every skin has a different one.
	var t := Time.get_ticks_msec() * 0.001 + phase
	var half := PEN_LENGTH * s * 0.5
	var r := PEN_RADIUS * s
	var tip: Color = skin["tip"]
	var kind: String = skin["idle"]
	var tip_position := Vector2(half, 0.0)
	var pulse := (sin(t * 5.0) + 1.0) * 0.5
	ci.draw_circle(tip_position, (9.0 + 6.0 * pulse) * s, Color(tip.r, tip.g, tip.b, 0.14 + 0.12 * pulse))
	if kind == "orbit":
		for i in range(2):
			var orbit_angle := t * 4.0 + float(i) * PI
			ci.draw_circle(tip_position + Vector2(cos(orbit_angle), sin(orbit_angle)) * 18.0 * s, 2.8 * s, tip)
	elif kind == "twinkle":
		for i in range(3):
			var x := lerpf(-half * 0.7, half * 0.5, fmod(float(i) * 0.37 + t * 0.12, 1.0))
			var twinkle := (sin(t * 6.0 + float(i) * 2.0) + 1.0) * 0.5
			UIKit.star(ci, Vector2(x, (float(i) - 1.0) * r * 0.5), (2.0 + 4.0 * twinkle) * s, Color(1.0, 1.0, 1.0, 0.25 + 0.7 * twinkle), s)
	elif kind == "embers":
		for i in range(4):
			var rise := fmod(t * 0.8 + float(i) * 0.25, 1.0)
			var x := lerpf(-half * 0.6, half * 0.4, fmod(float(i) * 0.41, 1.0))
			ci.draw_circle(Vector2(x, -r - rise * 26.0 * s), 3.2 * (1.0 - rise) * s, Color(1.0, 0.55 + 0.4 * rise, 0.15, 1.0 - rise))


static func trail(ci: CanvasItem, entries: Array[Dictionary], skin: Dictionary, s: float) -> void:
	# Each skin leaves its own kind of trail behind a fast-moving pen.
	var count := entries.size()
	var half_length := PEN_HALF_LENGTH * s * 0.9
	var width := PEN_RADIUS * 2.0 * s
	var style: String = skin["trail"]
	var barrel: Color = skin["barrel"]
	var time := Time.get_ticks_msec() * 0.001
	for i in range(count):
		var entry: Dictionary = entries[i]
		var fraction := float(i + 1) / float(count + 1)
		var trail_position: Vector2 = entry["position"]
		var axis := Vector2.RIGHT.rotated(float(entry["angle"]))
		var normal := Vector2(-axis.y, axis.x)
		match style:
			"flame":
				var jitter := Vector2(sin(float(i) * 12.9 + time * 9.0), cos(float(i) * 7.1 + time * 8.0)) * 7.0 * s
				var flame := Color("#ff5a1f").lerp(Color("#ffd23a"), fraction)
				flame.a = 0.34 * fraction
				for k in range(3):
					var along := (float(k) - 1.0) * half_length * 0.55
					ci.draw_circle(trail_position + axis * along + jitter, (7.0 + 15.0 * fraction) * s, flame)
			"sparkle":
				for k in range(2):
					var star_position := trail_position + axis * half_length * sin(float(i * 2 + k) * 2.7) + normal * sin(float(i + k) * 5.1) * 14.0 * s
					UIKit.star(ci, star_position, (4.0 + 6.0 * fraction) * s, Color(1.0, 1.0, 1.0, 0.9 * fraction), s)
			"rainbow":
				var hue := Color.from_hsv(fmod(float(i) * 0.1 + time * 0.8, 1.0), 0.65, 1.0, 0.3 * fraction)
				ci.draw_line(trail_position - axis * half_length, trail_position + axis * half_length, hue, width * (0.4 + 0.6 * fraction), true)
			"frost":
				ci.draw_line(trail_position - axis * half_length, trail_position + axis * half_length, Color(0.85, 0.96, 1.0, 0.18 * fraction), width * (0.4 + 0.6 * fraction), true)
				for k in range(2):
					var flake := trail_position + axis * half_length * sin(float(i * 3 + k) * 1.9) + normal * cos(float(i + k) * 2.3) * 16.0 * s
					ci.draw_circle(flake, 3.0 * s * (0.5 + fraction), Color(1.0, 1.0, 1.0, 0.85 * fraction))
			"volt":
				ci.draw_line(trail_position - axis * half_length, trail_position + axis * half_length, Color(1.0, 0.9, 0.3, 0.1 * fraction), width * 0.6, true)
				if i > 0:
					var previous: Dictionary = entries[i - 1]
					var from_position: Vector2 = previous["position"]
					var middle := from_position.lerp(trail_position, 0.5) + normal * sin(float(i) * 9.0 + time * 30.0) * 16.0 * s
					var bolt := Color("#ffe84a")
					bolt.a = 0.85 * fraction
					ci.draw_line(from_position, middle, bolt, 3.0 * s, true)
					ci.draw_line(middle, trail_position, bolt, 3.0 * s, true)
			_:
				ci.draw_line(trail_position - axis * half_length, trail_position + axis * half_length, Color(barrel.r, barrel.g, barrel.b, 0.16 * fraction), width * (0.4 + 0.6 * fraction), true)
