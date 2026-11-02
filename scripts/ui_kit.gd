extends RefCounted
# Shared drawing helpers for the cartoon look: every function draws on the CanvasItem it is given.
# `s` is the UI scale of the screen being drawn.

const FONT: Font = preload("res://assets/fonts/Nunito-Variable.ttf")
const INK := Color("#203349")
const PAPER := Color("#fff3df")
const CREAM := Color("#f7ecd6")
const SAND := Color("#f1dfb9")
const SAND_EDGE := Color("#d9bd88")
const MUTED := Color("#7a6a55")
const POWER_RED := Color("#d65546")
const POWER_PINK := Color("#f7d6cc")
const ORANGE := Color("#ff9a70")
const GREEN := Color("#50c9b4")
const GREEN_DARK := Color("#176e70")
# Seat colors identify players on the HUD and under the pens.
const SEAT_COLORS: Array[Color] = [Color("#50c9b4"), Color("#7296f2"), Color("#ff9a4a"), Color("#c46fe0")]


static func round_rect(ci: CanvasItem, rect: Rect2, radius: float, fill: Color, outline: Color = Color.TRANSPARENT, outline_width: float = 0.0) -> void:
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		return
	# Stop just short of a full half-circle: corners that meet exactly give duplicate points,
	# which the polygon triangulator rejects.
	var r := maxf(0.0, minf(radius, minf(rect.size.x, rect.size.y) * 0.5 - 0.5))
	var points := PackedVector2Array()
	var centers := [
		Vector2(rect.end.x - r, rect.position.y + r),
		Vector2(rect.end.x - r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.position.y + r)
	]
	var starts := [-PI * 0.5, 0.0, PI * 0.5, PI]
	for corner in range(4):
		for step in range(7):
			var angle: float = starts[corner] + (PI * 0.5) * float(step) / 6.0
			points.append(centers[corner] + Vector2.RIGHT.rotated(angle) * r)
	ci.draw_colored_polygon(points, fill)
	if outline.a > 0.0 and outline_width > 0.0:
		points.append(points[0])
		ci.draw_polyline(points, outline, outline_width, true)


static func bold_string(ci: CanvasItem, pos: Vector2, label: String, font_size: int, color: Color, s: float, width: float = -1.0, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	# The variable font only ships one weight, so a second pass a pixel over fakes a bold face.
	ci.draw_string(FONT, pos, label, alignment, width, font_size, color)
	ci.draw_string(FONT, pos + Vector2(0.9 * s, 0.0), label, alignment, width, font_size, color)


static func outlined_polygon(ci: CanvasItem, points: PackedVector2Array, fill: Color, outline_width: float) -> void:
	ci.draw_colored_polygon(points, fill)
	var closed := points.duplicate()
	closed.append(points[0])
	ci.draw_polyline(closed, INK, outline_width, true)


static func text_width(label: String, font_size: int) -> float:
	return FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


static func coin(ci: CanvasItem, center: Vector2, radius: float, s: float) -> void:
	ci.draw_circle(center, radius + 2.0 * s, INK)
	ci.draw_circle(center, radius, Color("#f6bf3b"))
	ci.draw_arc(center, radius * 0.72, 0.0, TAU, 20, Color("#c98f1a"), 1.6 * s, true)
	var font_size := roundi(radius * 1.15)
	bold_string(ci, Vector2(center.x - radius, center.y + font_size * 0.35), "L", font_size, Color("#8a5a10"), s, radius * 2.0, HORIZONTAL_ALIGNMENT_CENTER)


static func star(ci: CanvasItem, center: Vector2, size: float, color: Color, s: float) -> void:
	var line_width := 2.0 * s
	ci.draw_line(center - Vector2(size, 0.0), center + Vector2(size, 0.0), color, line_width, true)
	ci.draw_line(center - Vector2(0.0, size), center + Vector2(0.0, size), color, line_width, true)
	ci.draw_line(center - Vector2(size, size) * 0.5, center + Vector2(size, size) * 0.5, color, line_width * 0.7, true)
	ci.draw_line(center - Vector2(size, -size) * 0.5, center + Vector2(size, -size) * 0.5, color, line_width * 0.7, true)


static func fat_arrow(ci: CanvasItem, from: Vector2, to: Vector2, fill: Color, s: float) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 4.0:
		return
	var direction := delta / length
	var normal := Vector2(-direction.y, direction.x)
	var head_length := minf(36.0 * s, length * 0.6)
	var shaft_half := 7.0 * s
	var head_half := 21.0 * s
	var base := to - direction * head_length
	var points := PackedVector2Array([
		from + normal * shaft_half,
		base + normal * shaft_half,
		base + normal * head_half,
		to,
		base - normal * head_half,
		base - normal * shaft_half,
		from - normal * shaft_half
	])
	outlined_polygon(ci, points, fill, 3.5 * s)


static func power_bar(ci: CanvasItem, from: Vector2, to: Vector2, s: float) -> void:
	var width := 22.0 * s
	var layers := [[INK, width + 8.0 * s], [POWER_PINK, width + 1.0 * s], [POWER_RED, width - 6.0 * s]]
	for layer in layers:
		var color: Color = layer[0]
		var layer_width: float = layer[1]
		ci.draw_line(from, to, color, layer_width, true)
		ci.draw_circle(from, layer_width * 0.5, color)
		ci.draw_circle(to, layer_width * 0.5, color)
	var length := from.distance_to(to)
	if length > 90.0 * s:
		var direction := (to - from) / length
		var normal := Vector2(-direction.y, direction.x)
		for fraction in [0.34, 0.68]:
			var tick := from.lerp(to, fraction)
			ci.draw_line(tick - normal * width * 0.5, tick + normal * width * 0.5, INK, 3.0 * s, true)


static func power_badge(ci: CanvasItem, center: Vector2, value: int, s: float) -> void:
	ci.draw_circle(center, 33.0 * s, INK)
	ci.draw_circle(center, 30.0 * s, POWER_RED)
	ci.draw_circle(center, 24.0 * s, Color("#fbf0dc"))
	var font_size := roundi(26.0 * s)
	bold_string(ci, Vector2(center.x - 30.0 * s, center.y + font_size * 0.35), str(value), font_size, INK, s, 60.0 * s, HORIZONTAL_ALIGNMENT_CENTER)


static func spin_arrow(ci: CanvasItem, center: Vector2, spin: float, s: float) -> void:
	# A curved arrow over the pivot shows which way the pen will turn.
	var radius := 34.0 * s
	var sweep := lerpf(1.3, 2.6, clampf(absf(spin) / 6.0, 0.0, 1.0))
	var clockwise := spin > 0.0
	var start_angle := -PI * 0.5 - sweep * 0.5
	var points := PackedVector2Array()
	for i in range(15):
		points.append(center + Vector2.RIGHT.rotated(start_angle + sweep * float(i) / 14.0) * radius)
	ci.draw_polyline(points, INK, 10.0 * s, true)
	ci.draw_polyline(points, POWER_RED, 5.0 * s, true)
	var head_angle := start_angle + sweep if clockwise else start_angle
	var tangent := Vector2(-sin(head_angle), cos(head_angle)) * (1.0 if clockwise else -1.0)
	var normal := Vector2(-tangent.y, tangent.x)
	var head_point := center + Vector2.RIGHT.rotated(head_angle) * radius
	var head := PackedVector2Array([
		head_point + tangent * 16.0 * s,
		head_point - tangent * 4.0 * s + normal * 12.0 * s,
		head_point - tangent * 4.0 * s - normal * 12.0 * s
	])
	outlined_polygon(ci, head, POWER_RED, 3.0 * s)


static func wood_knot(ci: CanvasItem, center: Vector2, knot_scale: float, s: float) -> void:
	var ks := s * knot_scale
	ci.draw_set_transform(center, 0.0, Vector2(3.4, 1.0))
	for ring in range(5):
		ci.draw_arc(Vector2.ZERO, (10.0 + ring * 11.0) * ks, 0.0, TAU, 40, Color(0.42, 0.25, 0.1, 0.13 - ring * 0.018), 1.6 * ks, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func desk(ci: CanvasItem, screen_size: Vector2, board: Rect2, s: float, outer: Rect2 = Rect2()) -> void:
	# Cream backdrop beyond the frame; drawn oversized so screen shake never shows a gap.
	ci.draw_rect(Rect2(Vector2(-40.0, -40.0), screen_size + Vector2(80.0, 80.0)), Color("#f5ebd6"))
	var frame := Rect2(Vector2(8.0, 8.0) * s, screen_size - Vector2(16.0, 16.0) * s)
	round_rect(ci, Rect2(frame.position + Vector2(0, 6.0 * s), frame.size), 40.0 * s, Color(0.25, 0.14, 0.06, 0.28))
	round_rect(ci, frame, 40.0 * s, Color("#8b5a2e"), Color("#6a4222"), 2.0 * s)
	round_rect(ci, frame.grow(-3.0 * s), 37.0 * s, Color(0, 0, 0, 0), Color(0.86, 0.62, 0.38, 0.55), 2.0 * s)
	var radius := 26.0 * s
	if outer.size.x > board.size.x + 1.0:
		# The shrunken desk: what used to be desk is now a dark drop around it.
		round_rect(ci, outer, radius, Color("#3b2417"))
		for k in range(10):
			var plank_y := outer.position.y + (float(k) + 0.5) / 10.0 * outer.size.y
			ci.draw_line(Vector2(outer.position.x + 12.0 * s, plank_y), Vector2(outer.end.x - 12.0 * s, plank_y), Color(0, 0, 0, 0.25), 2.0 * s)
		round_rect(ci, outer, radius, Color(0, 0, 0, 0), Color(0.86, 0.62, 0.38, 0.25), 2.0 * s)
		round_rect(ci, Rect2(board.position + Vector2(-2.0 * s, 12.0 * s), board.size + Vector2(4.0 * s, 0.0)), radius, Color(0, 0, 0, 0.45))
		round_rect(ci, Rect2(board.position + Vector2(0.0, 8.0 * s), board.size), radius, Color("#8b5a2e"), Color("#6a4222"), 2.0 * s)
	round_rect(ci, board, radius, Color("#dcb27c"))
	# Soft horizontal grain: fine dark lines, pale streaks and wide faint bands.
	var grain_count := 46
	for i in range(grain_count):
		var fraction := (float(i) + 0.5) / float(grain_count)
		var y := board.position.y + 18.0 * s + fraction * (board.size.y - 36.0 * s)
		var phase := float(i) * 2.13
		var points := PackedVector2Array()
		for j in range(41):
			var x := board.position.x + 12.0 * s + float(j) / 40.0 * (board.size.x - 24.0 * s)
			var wave := sin(float(j) * 0.17 + phase) * 3.5 + sin(float(j) * 0.06 + phase * 0.7) * 7.0
			points.append(Vector2(x, y + wave * s))
		var kind := i % 4
		if kind == 0:
			ci.draw_polyline(points, Color(0.42, 0.25, 0.1, 0.16), 1.4 * s, true)
		elif kind == 1:
			ci.draw_polyline(points, Color(1.0, 0.9, 0.7, 0.2), 2.6 * s, true)
		elif kind == 2:
			ci.draw_polyline(points, Color(0.5, 0.3, 0.12, 0.07), 7.0 * s, true)
		else:
			ci.draw_polyline(points, Color(0.42, 0.25, 0.1, 0.1), 0.9 * s, true)
	wood_knot(ci, board.position + Vector2(board.size.x * 0.72, board.size.y * 0.3), 1.0, s)
	wood_knot(ci, board.position + Vector2(board.size.x * 0.22, board.size.y * 0.78), 0.7, s)
	# Glossy bevel along the inside edge of the desk.
	round_rect(ci, board.grow(-5.0 * s), radius - 4.0 * s, Color(0, 0, 0, 0), Color(1.0, 0.95, 0.85, 0.38), 3.0 * s)
	round_rect(ci, board, radius, Color(0, 0, 0, 0), Color(0.35, 0.2, 0.08, 0.45), 2.5 * s)


# ------------------------------------------------------------------ casual mobile kit
# Glossy, chunky pieces: thick ink outlines, a darker "lip" under every face, a white gloss
# on top, and heavy outlined lettering.

const SKY_TOP := Color("#5b4bdb")
const SKY_BOTTOM := Color("#2c2386")
const PANEL := Color("#fff7e8")
const PANEL_DEEP := Color("#f3e3c4")
const BTN_GREEN := Color("#5ccf4f")
const BTN_YELLOW := Color("#ffc93a")
const BTN_BLUE := Color("#4aa3ff")
const BTN_RED := Color("#ff5d5a")
const BTN_PURPLE := Color("#a46cff")
const BTN_GREY := Color("#b9b3c9")
const GOLD := Color("#ffd23f")

static var _heavy: FontVariation


static func heavy() -> Font:
	# The variable font at its boldest weight: the chunky lettering of casual games.
	if _heavy == null:
		_heavy = FontVariation.new()
		_heavy.base_font = FONT
		_heavy.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 900}
	return _heavy


static func heavy_width(label: String, font_size: int) -> float:
	return heavy().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


static func title(ci: CanvasItem, pos: Vector2, label: String, font_size: int, fill: Color, width: float = -1.0, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, outline: Color = INK, outline_size: int = -1, shadow: bool = true) -> void:
	# Heavy text with a thick outline and a soft drop shadow.
	var font := heavy()
	var thickness := outline_size if outline_size >= 0 else maxi(2, roundi(float(font_size) * 0.24))
	if shadow:
		var drop := Vector2(0.0, maxf(2.0, float(font_size) * 0.09))
		var shade := Color(0.0, 0.0, 0.08, 0.38 * outline.a)
		ci.draw_string_outline(font, pos + drop, label, alignment, width, font_size, thickness, shade)
		ci.draw_string(font, pos + drop, label, alignment, width, font_size, shade)
	if thickness > 0:
		ci.draw_string_outline(font, pos, label, alignment, width, font_size, thickness, outline)
	ci.draw_string(font, pos, label, alignment, width, font_size, fill)


static func centered_title(ci: CanvasItem, rect: Rect2, label: String, font_size: int, fill: Color, outline: Color = INK, outline_size: int = -1) -> void:
	title(ci, Vector2(rect.position.x, rect.get_center().y + float(font_size) * 0.36), label, font_size, fill, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER, outline, outline_size)


static func gradient_rect(ci: CanvasItem, rect: Rect2, top: Color, bottom: Color) -> void:
	ci.draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]), PackedColorArray([top, top, bottom, bottom]))


static func sunburst(ci: CanvasItem, center: Vector2, radius: float, rays: int, angle: float, color: Color) -> void:
	var step := TAU / float(rays * 2)
	for k in range(rays):
		var a := angle + step * 2.0 * float(k)
		ci.draw_colored_polygon(PackedVector2Array([center, center + Vector2.RIGHT.rotated(a) * radius, center + Vector2.RIGHT.rotated(a + step) * radius]), color)


static func gloss_button(ci: CanvasItem, rect: Rect2, color: Color, s: float, pressed: bool = false, radius: float = -1.0) -> Rect2:
	# A 3D candy button. Returns the face rect so the caller can put a label or icon on it.
	var r := radius if radius >= 0.0 else minf(rect.size.y * 0.38, 24.0 * s)
	var lip := minf(7.0 * s, rect.size.y * 0.12)
	var face := Rect2(rect.position, Vector2(rect.size.x, rect.size.y - lip))
	if pressed:
		face.position.y += lip * 0.75
	round_rect(ci, Rect2(rect.position + Vector2(0.0, 4.0 * s), rect.size), r, Color(0.0, 0.0, 0.1, 0.28))
	round_rect(ci, Rect2(rect.position.x, rect.position.y + lip, rect.size.x, rect.size.y - lip), r, color.darkened(0.4), INK, 3.0 * s)
	round_rect(ci, face, r, color, INK, 3.0 * s)
	# A darker band low on the face, then the gloss and a spark of light on top.
	var low := color.darkened(0.14)
	var shade := Rect2(face.position.x + 4.0 * s, face.position.y + face.size.y * 0.55, face.size.x - 8.0 * s, face.size.y * 0.45 - 4.0 * s)
	round_rect(ci, shade, r * 0.7, Color(low.r, low.g, low.b, 0.85))
	round_rect(ci, Rect2(face.position.x + 7.0 * s, face.position.y + 5.0 * s, face.size.x - 14.0 * s, face.size.y * 0.36), r * 0.6, Color(1.0, 1.0, 1.0, 0.34))
	ci.draw_circle(face.position + Vector2(minf(r, face.size.x * 0.3) * 0.75 + 5.0 * s, face.size.y * 0.26 + 3.0 * s), 3.2 * s, Color(1.0, 1.0, 1.0, 0.85))
	return face


static func gloss_circle(ci: CanvasItem, center: Vector2, radius: float, color: Color, s: float, pressed: bool = false) -> Vector2:
	# A round 3D button. Returns the center of its face.
	var lip := 5.0 * s
	var face := center + Vector2(0.0, -lip * 0.5 + (lip * 0.75 if pressed else 0.0))
	var low := color.darkened(0.12)
	ci.draw_circle(center + Vector2(0.0, lip * 0.5 + 3.0 * s), radius + 3.0 * s, Color(0.0, 0.0, 0.1, 0.28))
	ci.draw_circle(center + Vector2(0.0, lip * 0.5), radius + 3.0 * s, INK)
	ci.draw_circle(center + Vector2(0.0, lip * 0.5), radius, color.darkened(0.4))
	ci.draw_circle(face, radius + 3.0 * s, INK)
	ci.draw_circle(face, radius, color)
	ci.draw_circle(face + Vector2(0.0, radius * 0.25), radius * 0.72, Color(low.r, low.g, low.b, 0.6))
	ci.draw_set_transform(face + Vector2(0.0, -radius * 0.38), 0.0, Vector2(1.0, 0.55))
	ci.draw_circle(Vector2.ZERO, radius * 0.62, Color(1.0, 1.0, 1.0, 0.32))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return face


static func panel(ci: CanvasItem, rect: Rect2, s: float, face: Color = PANEL, radius: float = -1.0) -> void:
	var r := radius if radius >= 0.0 else 26.0 * s
	round_rect(ci, Rect2(rect.position + Vector2(0.0, 10.0 * s), rect.size), r, Color(0.0, 0.0, 0.1, 0.3))
	round_rect(ci, Rect2(rect.position + Vector2(0.0, 6.0 * s), rect.size), r, face.darkened(0.3), INK, 3.5 * s)
	round_rect(ci, rect, r, face, INK, 3.5 * s)
	round_rect(ci, rect.grow(-6.0 * s), maxf(4.0, r - 5.0 * s), Color(0, 0, 0, 0), Color(1.0, 1.0, 1.0, 0.75), 2.5 * s)


static func ribbon(ci: CanvasItem, center: Vector2, width: float, height: float, color: Color, s: float) -> Rect2:
	# A banner with folded tails. Returns the front band.
	var band := Rect2(center.x - width * 0.5, center.y - height * 0.5, width, height)
	var tail := height * 0.95
	var drop := height * 0.3
	var outline := 3.5 * s
	var back := color.darkened(0.35)
	for side in [-1.0, 1.0]:
		var edge: float = band.position.x if side < 0.0 else band.end.x
		var inner: float = edge - side * tail * 0.45
		var outer: float = edge + side * tail
		outlined_polygon(ci, PackedVector2Array([
			Vector2(inner, band.position.y + drop), Vector2(outer, band.position.y + drop),
			Vector2(outer - side * tail * 0.4, band.get_center().y + drop), Vector2(outer, band.end.y + drop),
			Vector2(inner, band.end.y + drop)]), back, outline)
		# The fold where the band turns back into the tail.
		outlined_polygon(ci, PackedVector2Array([
			Vector2(edge, band.end.y), Vector2(inner, band.end.y + drop), Vector2(inner, band.end.y)]), back.darkened(0.3), outline * 0.8)
	outlined_polygon(ci, PackedVector2Array([band.position, Vector2(band.end.x, band.position.y), band.end, Vector2(band.position.x, band.end.y)]), color, outline)
	ci.draw_rect(Rect2(band.position.x + 4.0 * s, band.position.y + 4.0 * s, band.size.x - 8.0 * s, band.size.y * 0.3), Color(1.0, 1.0, 1.0, 0.28))
	return band


static func star5(ci: CanvasItem, center: Vector2, radius: float, fill: Color, s: float, outline: bool = true) -> void:
	var points := PackedVector2Array()
	for k in range(10):
		var r := radius if k % 2 == 0 else radius * 0.48
		points.append(center + Vector2.UP.rotated(TAU * float(k) / 10.0) * r)
	if outline:
		outlined_polygon(ci, points, fill, maxf(2.0, radius * 0.16))
		if fill.a > 0.5:
			ci.draw_circle(center + Vector2(-radius * 0.18, -radius * 0.2), radius * 0.16, Color(1.0, 1.0, 1.0, 0.6))
	else:
		ci.draw_colored_polygon(points, fill)


static func level_badge(ci: CanvasItem, center: Vector2, radius: float, level: int, color: Color, s: float, caption: bool = true) -> void:
	# A scalloped rosette in the rank color with the level number in the middle. It never sets a
	# transform of its own, so it can be drawn scaled or spinning inside the caller's.
	var outline := maxf(2.0, radius * 0.07)
	var rim := PackedVector2Array()
	var shade := PackedVector2Array()
	for k in range(48):
		var a := TAU * float(k) / 48.0
		var point := center + Vector2.RIGHT.rotated(a) * radius * (0.91 + 0.09 * cos(a * 12.0))
		rim.append(point)
		shade.append(point + Vector2(0.0, radius * 0.09))
	ci.draw_colored_polygon(shade, Color(0.0, 0.0, 0.1, 0.3))
	outlined_polygon(ci, rim, color.darkened(0.28), outline)
	ci.draw_circle(center, radius * 0.74 + outline, INK)
	ci.draw_circle(center, radius * 0.74, color)
	ci.draw_circle(center + Vector2(0.0, radius * 0.16), radius * 0.6, Color(color.darkened(0.14).r, color.darkened(0.14).g, color.darkened(0.14).b, 0.7))
	var gloss := PackedVector2Array()
	for k in range(20):
		var a := TAU * float(k) / 20.0
		gloss.append(center + Vector2(cos(a) * radius * 0.5, -radius * 0.3 + sin(a) * radius * 0.24))
	ci.draw_colored_polygon(gloss, Color(1.0, 1.0, 1.0, 0.3))
	var label := str(level)
	var size := roundi(radius * (0.78 if label.length() < 2 else 0.66))
	var drop := 0.0
	if caption:
		var caption_size := maxi(8, roundi(radius * 0.2))
		title(ci, Vector2(center.x - radius, center.y - radius * 0.3), "LEVEL", caption_size, Color("#fffaf0"), radius * 2.0, HORIZONTAL_ALIGNMENT_CENTER, INK, maxi(2, roundi(caption_size * 0.3)), false)
		drop = radius * 0.12
	title(ci, Vector2(center.x - radius, center.y + float(size) * 0.36 + drop), label, size, Color("#fffaf0"), radius * 2.0, HORIZONTAL_ALIGNMENT_CENTER, INK, maxi(2, roundi(float(size) * 0.2)))


static func crown(ci: CanvasItem, center: Vector2, size: float, fill: Color, s: float) -> void:
	# A three-pointed crown for bosses and legends.
	var points := PackedVector2Array([
		center + Vector2(-0.5, 0.32) * size, center + Vector2(-0.56, -0.34) * size, center + Vector2(-0.24, -0.02) * size,
		center + Vector2(0.0, -0.46) * size, center + Vector2(0.24, -0.02) * size, center + Vector2(0.56, -0.34) * size,
		center + Vector2(0.5, 0.32) * size])
	outlined_polygon(ci, points, fill, maxf(2.0, size * 0.09))
	for tip in [Vector2(-0.56, -0.34), Vector2(0.0, -0.46), Vector2(0.56, -0.34)]:
		ci.draw_circle(center + tip * size, size * 0.11 + maxf(2.0, size * 0.09) * 0.5, INK)
		ci.draw_circle(center + tip * size, size * 0.11, fill.lightened(0.3))
	ci.draw_line(center + Vector2(-0.44, 0.16) * size, center + Vector2(0.44, 0.16) * size, Color(1.0, 1.0, 1.0, 0.45), maxf(1.5, size * 0.06), true)


static func icon(ci: CanvasItem, kind: String, center: Vector2, size: float, color: Color, s: float, shadow: bool = true) -> void:
	# Simple bold glyphs, drawn twice: a dark shadow, then the color.
	if shadow:
		_glyph(ci, kind, center + Vector2(0.0, 2.5 * s), size, Color(0.0, 0.0, 0.1, 0.45))
	_glyph(ci, kind, center, size, color)


static func _glyph(ci: CanvasItem, kind: String, c: Vector2, z: float, color: Color) -> void:
	var w := z * 0.2
	match kind:
		"home":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.55, -0.02) * z, c + Vector2(0.0, -0.52) * z, c + Vector2(0.55, -0.02) * z]), color)
			round_rect(ci, Rect2(c + Vector2(-0.38, -0.08) * z, Vector2(0.76, 0.56) * z), 0.08 * z, color)
		"restart":
			ci.draw_arc(c, z * 0.36, 0.6, 5.4, 24, color, w, true)
			var head := c + Vector2(cos(5.4), sin(5.4)) * z * 0.36
			var along := Vector2.RIGHT.rotated(5.4 + PI * 0.5)
			var across := Vector2(-along.y, along.x)
			ci.draw_colored_polygon(PackedVector2Array([head + along * 0.26 * z, head - along * 0.06 * z + across * 0.22 * z, head - along * 0.06 * z - across * 0.22 * z]), color)
		"pause":
			round_rect(ci, Rect2(c + Vector2(-0.34, -0.38) * z, Vector2(0.24, 0.76) * z), 0.08 * z, color)
			round_rect(ci, Rect2(c + Vector2(0.1, -0.38) * z, Vector2(0.24, 0.76) * z), 0.08 * z, color)
		"play":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.3, -0.42) * z, c + Vector2(0.45, 0.0) * z, c + Vector2(-0.3, 0.42) * z]), color)
		"back":
			ci.draw_polyline(PackedVector2Array([c + Vector2(0.18, -0.38) * z, c + Vector2(-0.22, 0.0) * z, c + Vector2(0.18, 0.38) * z]), color, w * 1.25, true)
		"shop":
			# A little shopping cart.
			ci.draw_polyline(PackedVector2Array([c + Vector2(-0.52, -0.4) * z, c + Vector2(-0.34, -0.4) * z, c + Vector2(-0.18, 0.18) * z, c + Vector2(0.36, 0.18) * z]), color, w * 0.7, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.3, -0.28) * z, c + Vector2(0.52, -0.28) * z, c + Vector2(0.4, 0.08) * z, c + Vector2(-0.2, 0.08) * z]), color)
			ci.draw_circle(c + Vector2(-0.12, 0.36) * z, z * 0.1, color)
			ci.draw_circle(c + Vector2(0.3, 0.36) * z, z * 0.1, color)
		"trophy":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.36, -0.42) * z, c + Vector2(0.36, -0.42) * z, c + Vector2(0.22, 0.05) * z, c + Vector2(-0.22, 0.05) * z]), color)
			ci.draw_arc(c + Vector2(-0.36, -0.22) * z, z * 0.15, PI * 0.5, PI * 1.5, 10, color, w * 0.6, true)
			ci.draw_arc(c + Vector2(0.36, -0.22) * z, z * 0.15, -PI * 0.5, PI * 0.5, 10, color, w * 0.6, true)
			ci.draw_rect(Rect2(c + Vector2(-0.07, 0.04) * z, Vector2(0.14, 0.2) * z), color)
			round_rect(ci, Rect2(c + Vector2(-0.28, 0.24) * z, Vector2(0.56, 0.18) * z), 0.05 * z, color)
		"globe":
			ci.draw_arc(c, z * 0.42, 0.0, TAU, 28, color, w * 0.7, true)
			ci.draw_line(c + Vector2(-0.42, 0.0) * z, c + Vector2(0.42, 0.0) * z, color, w * 0.6, true)
			ci.draw_set_transform(c, 0.0, Vector2(0.45, 1.0))
			ci.draw_arc(Vector2.ZERO, z * 0.42, 0.0, TAU, 28, color, w * 0.6 / 0.45, true)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"user":
			ci.draw_circle(c + Vector2(0.0, -0.18) * z, z * 0.2, color)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.4, 0.45) * z, c + Vector2(-0.3, 0.12) * z, c + Vector2(0.0, 0.04) * z, c + Vector2(0.3, 0.12) * z, c + Vector2(0.4, 0.45) * z]), color)
		"robot":
			round_rect(ci, Rect2(c + Vector2(-0.38, -0.26) * z, Vector2(0.76, 0.62) * z), 0.14 * z, color)
			ci.draw_line(c + Vector2(0.0, -0.26) * z, c + Vector2(0.0, -0.44) * z, color, w * 0.6, true)
			ci.draw_circle(c + Vector2(0.0, -0.46) * z, z * 0.07, color)
			var eye := Color(0.0, 0.0, 0.1, 0.55 * color.a)
			ci.draw_circle(c + Vector2(-0.15, 0.02) * z, z * 0.08, eye)
			ci.draw_circle(c + Vector2(0.15, 0.02) * z, z * 0.08, eye)
		"lock":
			ci.draw_arc(c + Vector2(0.0, -0.1) * z, z * 0.2, PI, TAU, 14, color, w * 0.7, true)
			round_rect(ci, Rect2(c + Vector2(-0.32, -0.12) * z, Vector2(0.64, 0.5) * z), 0.08 * z, color)
		"clock":
			ci.draw_arc(c, z * 0.42, 0.0, TAU, 28, color, w * 0.7, true)
			ci.draw_line(c, c + Vector2(0.0, -0.26) * z, color, w * 0.6, true)
			ci.draw_line(c, c + Vector2(0.2, 0.08) * z, color, w * 0.6, true)
		"plus":
			ci.draw_line(c + Vector2(-0.34, 0.0) * z, c + Vector2(0.34, 0.0) * z, color, w * 1.2, true)
			ci.draw_line(c + Vector2(0.0, -0.34) * z, c + Vector2(0.0, 0.34) * z, color, w * 1.2, true)
		"check":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-0.36, 0.0) * z, c + Vector2(-0.1, 0.28) * z, c + Vector2(0.4, -0.3) * z]), color, w * 1.2, true)


static func safe_rect(ci: CanvasItem) -> Rect2:
	# The part of the screen clear of notches and rounded corners, in this canvas's units.
	var view := ci.get_viewport_rect()
	if not OS.has_feature("mobile"):
		return view
	var window := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if window.x <= 0.0 or window.y <= 0.0 or safe.size.x <= 0.0:
		return view
	var factor := view.size / window
	return Rect2(safe.position * factor, safe.size * factor).intersection(view)


static func backdrop(ci: CanvasItem, screen_size: Vector2, t: float, s: float) -> void:
	# Deep purple-blue sky with a slowly turning sunburst and drifting sparkles.
	var full := Rect2(Vector2(-40.0, -40.0), screen_size + Vector2(80.0, 80.0))
	gradient_rect(ci, full, SKY_TOP, SKY_BOTTOM)
	sunburst(ci, Vector2(screen_size.x * 0.5, screen_size.y * 0.45), screen_size.length(), 16, t * 0.05, Color(1.0, 1.0, 1.0, 0.055))
	for k in range(26):
		var seed_x := fmod(float(k) * 0.6180339 * 7.0, 1.0)
		var seed_y := fmod(float(k) * 0.7548776 * 3.0 + t * 0.012 * (1.0 + float(k % 3)), 1.0)
		var p := Vector2(seed_x * screen_size.x, (1.0 - seed_y) * (screen_size.y + 40.0) - 20.0)
		var twinkle := 0.5 + 0.5 * sin(t * 2.0 + float(k) * 1.7)
		if k % 4 == 0:
			star(ci, p, (3.0 + 3.0 * twinkle) * s, Color(1.0, 1.0, 1.0, 0.25 + 0.3 * twinkle), s)
		else:
			ci.draw_circle(p, (1.5 + 2.0 * twinkle) * s, Color(1.0, 1.0, 1.0, 0.12 + 0.18 * twinkle))
