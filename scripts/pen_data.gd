extends RefCounted
# Pen catalog: every pen has a price in leos, slightly different weight and hitting power,
# and a skin (colors, pattern, trail animation, idle animation, impact animation).


static func _pen(id: String, pen_name: String, price: int, mass: float, punch: float, look: Dictionary) -> Dictionary:
	var pen := {
		"id": id,
		"name": pen_name,
		"price": price,
		"mass": mass,
		"punch": punch,
	}
	pen.merge(look)
	return pen


static func all() -> Array[Dictionary]:
	var pens: Array[Dictionary] = []
	pens.append(_pen("classic", "Classic", 0, 1.0, 1.0, {
		"barrel": Color("#50c9b4"), "accent": Color("#176e70"), "tip": Color("#ff865e"),
		"pattern": "plain", "trail": "classic", "idle": "pulse",
		"impact": "CLACK!", "spark_a": Color("#ffc23a"), "spark_b": Color("#e8553a"),
		"spark_shape": "line", "rainbow": false,
	}))
	pens.append(_pen("cobalt", "Cobalt", 120, 1.05, 1.02, {
		"barrel": Color("#5b84e6"), "accent": Color("#27458f"), "tip": Color("#ffd06f"),
		"pattern": "bands", "trail": "classic", "idle": "pulse",
		"impact": "TOCK!", "spark_a": Color("#9db8ff"), "spark_b": Color("#3f64c9"),
		"spark_shape": "line", "rainbow": false,
	}))
	pens.append(_pen("ember", "Ember", 300, 1.10, 1.05, {
		"barrel": Color("#e8553a"), "accent": Color("#7a2417"), "tip": Color("#ffb347"),
		"pattern": "stripes", "trail": "flame", "idle": "embers",
		"impact": "BOOM!", "spark_a": Color("#ffd23a"), "spark_b": Color("#ff5a1f"),
		"spark_shape": "dot", "rainbow": false,
	}))
	pens.append(_pen("frost", "Frost", 650, 1.15, 1.06, {
		"barrel": Color("#bfeaf7"), "accent": Color("#4a97b8"), "tip": Color("#8fd6f0"),
		"pattern": "dots", "trail": "frost", "idle": "twinkle",
		"impact": "CRACK!", "spark_a": Color("#e6f9ff"), "spark_b": Color("#4fb4de"),
		"spark_shape": "star", "rainbow": false,
	}))
	pens.append(_pen("volt", "Volt", 1260, 1.18, 1.09, {
		"barrel": Color("#f5d63a"), "accent": Color("#2b2b2b"), "tip": Color("#ff7a2e"),
		"pattern": "stripes", "trail": "volt", "idle": "orbit",
		"impact": "ZAP!", "spark_a": Color("#fff27a"), "spark_b": Color("#ffb800"),
		"spark_shape": "line", "rainbow": false,
	}))
	pens.append(_pen("rainbow", "Prism", 2100, 1.25, 1.12, {
		"barrel": Color("#fff1fa"), "accent": Color("#8a4fd6"), "tip": Color("#ff6fb5"),
		"pattern": "rainbow", "trail": "rainbow", "idle": "twinkle",
		"impact": "WOW!", "spark_a": Color("#ffffff"), "spark_b": Color("#ff6fb5"),
		"spark_shape": "dot", "rainbow": true,
	}))
	return pens


static func cpu_pen(pens: Array[Dictionary], step: int, rng: RandomNumberGenerator) -> Dictionary:
	# The computer brings stronger pens at higher levels and in later rounds: `step` counts along
	# the catalog from the starter pen, and now and then it brings one a step weaker.
	var pool := ["classic", "cobalt", "ember", "frost", "volt", "rainbow"]
	var index := clampi(step - (1 if rng.randf() < 0.3 else 0), 0, pool.size() - 1)
	for pen in pens:
		if pen["id"] == pool[index]:
			return pen
	return pens[0]


static func palette() -> Array[Color]:
	# Free recolors for any pen's barrel; index -1 means the pen's own color.
	return [
		Color("#50c9b4"), Color("#5b84e6"), Color("#e8553a"), Color("#ff9a4a"),
		Color("#f5d63a"), Color("#7bc96f"), Color("#9a6fe0"), Color("#f06fb0"),
	]


static func recolor(pen: Dictionary, color_index: int) -> Dictionary:
	if color_index < 0:
		return pen
	var colors := palette()
	var color := colors[clampi(color_index, 0, colors.size() - 1)]
	var tinted := pen.duplicate()
	tinted["barrel"] = color
	tinted["accent"] = color.darkened(0.45)
	return tinted
