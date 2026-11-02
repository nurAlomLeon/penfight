extends Node
# Sound effects, registered as the `Sfx` autoload.
#
# There are no audio files in the project, so every effect is built at startup from simple physical
# models instead of plain beeps: knocks are a few decaying resonances (like a struck bar of wood or a
# hollow plastic barrel) plus a tiny noise click, whooshes are filtered air noise, the scrape is
# grainy stick-and-slip friction, and the chimes are marimba-like bars and little coin pings.
#
# Real recordings win: drop `<name>.ogg` / `.wav` / `.mp3` (or `<name>_1`, `<name>_2`, ... for variants)
# into res://assets/sounds/ and that sound is used instead. Names:
#   clack tap whoosh scrape fall thud tick click knock coin buy win lose rumble crack levelup boss

const RATE := 32000
const SOUND_DIR := "res://assets/sounds/"
const EXTENSIONS := ["ogg", "wav", "mp3"]
const NAMES := ["clack", "tap", "whoosh", "scrape", "fall", "thud", "tick", "click", "knock", "coin", "buy", "win", "lose", "rumble", "crack", "levelup", "boss"]

var banks: Dictionary = {}
var last_variant: Dictionary = {}
var players: Array[AudioStreamPlayer] = []
var next_player := 0
var scrape_player: AudioStreamPlayer
var scrape_target := 0.0
var scrape_level := 0.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 20260
	_build_banks()
	for name_text in NAMES:
		var override := _load_override(name_text)
		if not override.is_empty():
			banks[name_text] = override
	for i in range(10):
		var player := AudioStreamPlayer.new()
		add_child(player)
		players.append(player)
	scrape_player = AudioStreamPlayer.new()
	add_child(scrape_player)
	scrape_player.stream = banks["scrape"][0]
	scrape_player.volume_db = -80.0
	scrape_player.play()


func _process(delta: float) -> void:
	# The scrape is a looping sound whose volume and pitch follow how fast the pens are moving.
	scrape_level = lerpf(scrape_level, scrape_target, 1.0 - exp(-14.0 * delta))
	if scrape_level < 0.06:
		scrape_player.volume_db = -80.0
	else:
		scrape_player.volume_db = linear_to_db(pow(scrape_level, 1.5) * 0.16)
		scrape_player.pitch_scale = lerpf(0.85, 1.15, scrape_level)


func set_scrape(level: float) -> void:
	scrape_target = clampf(level, 0.0, 1.0)


func play(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not banks.has(sound_name) or players.is_empty():
		return
	var bank: Array = banks[sound_name]
	var index := rng.randi() % bank.size()
	if bank.size() > 1 and index == int(last_variant.get(sound_name, -1)):
		index = (index + 1) % bank.size()
	last_variant[sound_name] = index
	var player := players[next_player]
	next_player = (next_player + 1) % players.size()
	player.stream = bank[index]
	player.volume_db = volume_db
	# A touch of random pitch so repeated sounds never repeat exactly.
	player.pitch_scale = pitch * rng.randf_range(0.97, 1.03)
	player.play()


# ------------------------------------------------------------------ recordings

func _load_override(sound_name: String) -> Array:
	var found: Array = []
	var candidates: Array[String] = [sound_name]
	for i in range(1, 9):
		candidates.append("%s_%d" % [sound_name, i])
	for candidate in candidates:
		for extension in EXTENSIONS:
			var path: String = SOUND_DIR + candidate + "." + extension
			if ResourceLoader.exists(path):
				var stream := load(path) as AudioStream
				if stream != null:
					if sound_name == "scrape" and "loop" in stream:
						stream.set("loop", true)
					found.append(stream)
				break
	return found


# ------------------------------------------------------------------ the sound banks

func _build_banks() -> void:
	banks["clack"] = [_clack(), _clack(), _clack(), _clack(), _clack()]
	banks["tap"] = [_tap(), _tap(), _tap()]
	banks["whoosh"] = [_whoosh(), _whoosh(), _whoosh()]
	banks["scrape"] = [_scrape()]
	banks["fall"] = [_fall()]
	banks["thud"] = [_thud(), _thud()]
	banks["tick"] = [_tick(1.0), _tick(1.04)]
	banks["click"] = [_click(), _click()]
	banks["knock"] = [_knock(), _knock(), _knock()]
	banks["coin"] = [_coin(), _coin()]
	banks["buy"] = [_buy(), _buy()]
	banks["win"] = [_win()]
	banks["lose"] = [_lose()]
	banks["rumble"] = [_rumble()]
	banks["crack"] = [_crack(), _crack()]
	banks["levelup"] = [_levelup()]
	banks["boss"] = [_boss()]


func _clack() -> AudioStreamWAV:
	# Pen on pen: a rounded, hollow "tok" like a plastic tube struck on its side. Low-mid body modes
	# (no glassy highs), a short woody thump underneath and a soft touch of noise at the contact.
	var detune := rng.randf_range(0.92, 1.1)
	var partials := [
		[240.0 * detune, 0.55, 48.0],
		[610.0 * detune, 1.0, 70.0],
		[1380.0 * detune, 0.8, 110.0],
		[2330.0 * detune, 0.4, 150.0],
		[3500.0 * detune, 0.15, 210.0],
	]
	var out := _modal(partials, 0.16, 0.5, 0.35)
	_mix(out, _modal(partials, 0.1, 0.2, 0.3), int(RATE * rng.randf_range(0.008, 0.016)), 0.22)
	return _wav(out, 0.85)


func _tap() -> AudioStreamWAV:
	# A light touch between pens: a small, soft, hollow "tk".
	var detune := rng.randf_range(0.92, 1.1)
	var partials := [
		[420.0 * detune, 0.6, 90.0],
		[1050.0 * detune, 1.0, 130.0],
		[1900.0 * detune, 0.4, 190.0],
	]
	return _wav(_modal(partials, 0.07, 0.3, 0.3), 0.7)


func _whoosh() -> AudioStreamWAV:
	# Air rushing past a flicked pen: noise through a band that sweeps upward.
	var duration := 0.3
	var count := int(RATE * duration)
	var out := PackedFloat32Array()
	out.resize(count)
	var low := 0.0
	var band := 0.0
	var start := rng.randf_range(560.0, 760.0)
	for i in range(count):
		var u := float(i) / float(count)
		var envelope := pow(sin(PI * u), 2.0)
		var center := lerpf(start, 2500.0, pow(u, 0.8))
		var f := 2.0 * sin(PI * center / float(RATE))
		var noise := rng.randf_range(-1.0, 1.0)
		low += f * band
		var high := noise - low - band * 0.8
		band += f * high
		out[i] = band * envelope
	# A tiny tick as the pen leaves the fingers.
	var tick := int(RATE * 0.004)
	for i in range(tick):
		out[i] += rng.randf_range(-1.0, 1.0) * 0.25 * (1.0 - float(i) / float(tick))
	return _wav(out, 0.7)


func _scrape() -> AudioStreamWAV:
	# Deliberately minimal: a faint, soft hiss of a pen gliding over wood. Loops seamlessly.
	var count := int(RATE * 1.6)
	var fade := int(RATE * 0.12)
	var raw := PackedFloat32Array()
	raw.resize(count + fade)
	var low_a := 0.0
	var low_b := 0.0
	for i in range(count + fade):
		low_a += (rng.randf_range(-1.0, 1.0) - low_a) * 0.1
		low_b += (low_a - low_b) * 0.16
		var t := float(i) / float(RATE)
		raw[i] = low_b * (0.88 + 0.12 * sin(TAU * 3.1 * t))
	var out := PackedFloat32Array()
	out.resize(count)
	for i in range(count):
		out[i] = lerpf(raw[count + i], raw[i], float(i) / float(fade)) if i < fade else raw[i]
	var wav := _wav(out, 0.6)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = count
	return wav


func _fall() -> AudioStreamWAV:
	# A pen dropping off the desk: air rushing past as it tumbles, falling in pitch.
	var duration := 0.6
	var count := int(RATE * duration)
	var out := PackedFloat32Array()
	out.resize(count)
	var low := 0.0
	var band := 0.0
	for i in range(count):
		var u := float(i) / float(count)
		var envelope := sin(PI * pow(u, 0.7)) * (1.0 - 0.3 * u)
		var center := lerpf(2300.0, 420.0, pow(u, 0.7))
		var f := 2.0 * sin(PI * center / float(RATE))
		var noise := rng.randf_range(-1.0, 1.0)
		low += f * band
		var high := noise - low - band * 0.9
		band += f * high
		out[i] = band * envelope
	return _wav(out, 0.7)


func _thud() -> AudioStreamWAV:
	# The pen landing on the floor and bouncing: a hollow knock that repeats, smaller and faster each time.
	var out := PackedFloat32Array()
	out.resize(int(RATE * 0.8))
	var times := [0.0, 0.16, 0.27, 0.34, 0.385]
	var gains := [1.0, 0.55, 0.3, 0.16, 0.08]
	for k in range(times.size()):
		var detune := rng.randf_range(0.94, 1.07)
		var partials := [
			[210.0 * detune, 1.0, 20.0],
			[480.0 * detune, 0.7, 32.0],
			[950.0 * detune, 0.5, 50.0],
			[1700.0 * detune, 0.3, 80.0],
		]
		_mix(out, _modal(partials, 0.3, 0.7, 0.35), int(RATE * float(times[k])), float(gains[k]))
	return _wav(out, 0.9)


func _tick(pitch: float) -> AudioStreamWAV:
	# A dry wooden tick, like a clock or a knuckle on a table.
	var partials := [[1850.0 * pitch, 1.0, 130.0], [3100.0 * pitch, 0.5, 180.0], [900.0 * pitch, 0.4, 90.0]]
	return _wav(_modal(partials, 0.08, 0.6, 0.6), 0.7)


func _click() -> AudioStreamWAV:
	var detune := rng.randf_range(0.96, 1.05)
	var partials := [[1250.0 * detune, 1.0, 110.0], [2100.0 * detune, 0.45, 150.0]]
	return _wav(_modal(partials, 0.07, 0.5, 0.5), 0.6)


func _knock() -> AudioStreamWAV:
	# A soft knuckle knock on solid wood.
	var detune := rng.randf_range(0.93, 1.08)
	var partials := [[320.0 * detune, 1.0, 38.0], [610.0 * detune, 0.6, 55.0], [1100.0 * detune, 0.35, 80.0]]
	return _wav(_modal(partials, 0.2, 0.5, 0.3), 0.8)


func _crack() -> AudioStreamWAV:
	# A dry crack of wood under strain.
	var detune := rng.randf_range(0.9, 1.12)
	var partials := [[260.0 * detune, 1.0, 40.0], [690.0 * detune, 0.6, 60.0], [1500.0 * detune, 0.4, 90.0], [3100.0 * detune, 0.2, 130.0]]
	return _wav(_modal(partials, 0.25, 1.0, 0.7), 0.85)


func _ping(base: float, duration: float) -> PackedFloat32Array:
	# A small metal ping (coin): inharmonic partials, the higher ones dying first.
	var partials := [
		[base, 1.0, 7.0],
		[base * 2.76, 0.6, 10.0],
		[base * 5.4, 0.35, 16.0],
		[base * 8.93, 0.2, 24.0],
	]
	return _modal(partials, duration, 0.4, 0.8)


func _coin() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	out.resize(int(RATE * 0.6))
	var base := rng.randf_range(2200.0, 2700.0)
	_mix(out, _ping(base, 0.5), 0, 1.0)
	_mix(out, _ping(base * 1.26, 0.45), int(RATE * 0.07), 0.7)
	return _wav(out, 0.7)


func _buy() -> AudioStreamWAV:
	# A little pour of coins.
	var out := PackedFloat32Array()
	out.resize(int(RATE * 0.8))
	var offset := 0.0
	for k in range(6):
		var base := rng.randf_range(1900.0, 3000.0)
		_mix(out, _ping(base, 0.35), int(RATE * offset), 1.0 - 0.12 * float(k))
		offset += rng.randf_range(0.04, 0.09)
	return _wav(out, 0.7)


func _bar(freq: float, duration: float, decay_scale: float) -> PackedFloat32Array:
	# A struck wooden bar (marimba): a fundamental with a bright, quickly fading overtone.
	var partials := [
		[freq, 1.0, 5.5 * decay_scale],
		[freq * 3.97, 0.28, 13.0 * decay_scale],
		[freq * 9.2, 0.08, 26.0 * decay_scale],
	]
	return _modal(partials, duration, 0.35, 0.25)


func _win() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	out.resize(int(RATE * 1.4))
	var notes := [523.25, 659.25, 783.99, 1046.5]
	var offsets := [0.0, 0.11, 0.22, 0.34]
	for k in range(notes.size()):
		_mix(out, _bar(float(notes[k]), 0.9 if k == notes.size() - 1 else 0.5, 1.0), int(RATE * float(offsets[k])), 1.0)
	return _wav(out, 0.8)


func _lose() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	out.resize(int(RATE * 1.3))
	var notes := [392.0, 329.63, 261.63]
	var offsets := [0.0, 0.17, 0.36]
	for k in range(notes.size()):
		_mix(out, _bar(float(notes[k]), 0.8, 1.5), int(RATE * float(offsets[k])), 1.0)
	return _wav(out, 0.8)


func _levelup() -> AudioStreamWAV:
	# A quick climbing arpeggio that lands on a ringing major chord, sprinkled with coin pings.
	var out := PackedFloat32Array()
	out.resize(int(RATE * 2.2))
	var climb := [523.25, 659.25, 783.99, 1046.5, 1318.5]
	for k in range(climb.size()):
		_mix(out, _bar(float(climb[k]), 0.45, 1.2), int(RATE * 0.075 * float(k)), 0.8)
	var land := int(RATE * 0.42)
	for note in [1046.5, 1318.5, 1567.98]:
		_mix(out, _bar(float(note), 1.6, 0.45), land, 0.75)
	_mix(out, _bar(523.25, 1.6, 0.4), land, 0.6)
	for k in range(7):
		_mix(out, _ping(rng.randf_range(2600.0, 3600.0), 0.4), land + int(RATE * (0.05 + 0.11 * float(k))), 0.35 - 0.03 * float(k))
	return _wav(out, 0.85)


func _boss() -> AudioStreamWAV:
	# The boss walks in: two low, heavy strikes and a long dark ring.
	var out := PackedFloat32Array()
	out.resize(int(RATE * 2.0))
	for k in range(2):
		var base := 98.0 if k == 0 else 73.42
		var partials := [[base, 1.0, 2.2], [base * 2.0, 0.5, 3.0], [base * 2.76, 0.35, 4.5], [base * 5.4, 0.15, 9.0]]
		_mix(out, _modal(partials, 1.6, 0.9, 0.3), int(RATE * 0.32 * float(k)), 1.0)
	return _wav(out, 0.85)


func _rumble() -> AudioStreamWAV:
	# The desk shrinking: a low rumble, creaking wood and a few cracks.
	var duration := 3.2
	var count := int(RATE * duration)
	var out := PackedFloat32Array()
	out.resize(count)
	var low_a := 0.0
	var low_b := 0.0
	var creak_phase := 0.0
	for i in range(count):
		var t := float(i) / float(RATE)
		var envelope := minf(1.0, t / 0.3) * minf(1.0, (duration - t) / 0.8)
		var noise := rng.randf_range(-1.0, 1.0)
		low_a += (noise - low_a) * 0.02
		low_b += (low_a - low_b) * 0.03
		var rumble := low_b * 6.0 * (0.6 + 0.4 * sin(TAU * 1.7 * t))
		var pitch := 175.0 + 55.0 * sin(TAU * 0.8 * t) + 25.0 * sin(TAU * 2.3 * t + 1.0)
		creak_phase += TAU * pitch / float(RATE)
		var gate := pow(maxf(0.0, sin(TAU * 3.1 * t + sin(TAU * 0.45 * t) * 2.0)), 2.0)
		var creak := (sin(creak_phase) + 0.55 * sin(2.0 * creak_phase) + 0.35 * sin(3.0 * creak_phase) + 0.2 * sin(4.0 * creak_phase)) * gate * 0.22
		out[i] = (rumble + creak) * envelope
	for k in range(3):
		var partials := [[260.0, 1.0, 40.0], [690.0, 0.6, 60.0], [1500.0, 0.4, 90.0]]
		_mix(out, _modal(partials, 0.25, 0.8, 0.6), int(RATE * rng.randf_range(0.4, duration - 0.6)), 0.5)
	return _wav(out, 0.85)


# ------------------------------------------------------------------ synthesis helpers

func _modal(partials: Array, duration: float, click: float, click_smooth: float) -> PackedFloat32Array:
	# Modal synthesis: a struck object rings as a sum of exponentially decaying sine resonances.
	var count := int(RATE * duration)
	var out := PackedFloat32Array()
	out.resize(count)
	for partial in partials:
		var freq: float = partial[0]
		var amp: float = partial[1]
		var decay: float = partial[2]
		var step := exp(-decay / float(RATE))
		var phase := TAU * freq / float(RATE)
		var envelope := amp
		for i in range(count):
			out[i] += envelope * sin(phase * float(i))
			envelope *= step
	# The contact itself: a few milliseconds of softened noise.
	var click_length := mini(count, int(RATE * 0.004))
	var smooth := 0.0
	for i in range(click_length):
		smooth += (rng.randf_range(-1.0, 1.0) - smooth) * click_smooth
		out[i] += smooth * click * pow(1.0 - float(i) / float(click_length), 2.0)
	return out


func _mix(target: PackedFloat32Array, part: PackedFloat32Array, offset: int, gain: float) -> void:
	for i in range(part.size()):
		var index := offset + i
		if index >= target.size():
			break
		target[index] += part[i] * gain


func _wav(samples: PackedFloat32Array, peak: float) -> AudioStreamWAV:
	var top := 0.0001
	for sample in samples:
		top = maxf(top, absf(sample))
	var scale := peak / top
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		bytes.encode_s16(i * 2, int(clampf(samples[i] * scale, -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav
