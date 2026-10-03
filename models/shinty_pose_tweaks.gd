@tool
class_name ShintyPoseTweaks
extends RefCounted
## Hand-made adjustments to the player model's actions, made in the training
## ground's pose editor and saved in data/poses.json (user://poses.json when
## the game folder can't be written to, which then wins).
##
## The moves themselves are built in code (shinty_player.gd). A tweak sits on
## top of one. For a one-off move (a swing, a trap, a save) that's how long it
## takes, and at each of three moments (wind-up, strike, finish) how far to
## turn a few joints and move the caman; in between, the tweak fades in and
## out so the move stays smooth. For walking, jogging and sprinting the
## moments are each foot coming forward, plus all the time. For a held pose
## (standing, carrying, a held backswing, reaching, the throw-up) there's one.
## Angles are stored in degrees and the caman in centimetres, for a
## right-hander; left-handers get the mirror image.

const RES_PATH := "res://data/poses.json"
const USER_PATH := "user://poses.json"
const PHASES := ["Wind-up", "Strike", "Finish"]
const STRIDE_PHASES := ["Left foot forward", "Right foot forward", "All the time"]
const HELD_PHASES := ["Held"]
## Poses that aren't one-off actions: name -> "stride" or "held".
const STATES := {
	"stand": "held", "walk": "stride", "jog": "stride", "sprint": "stride",
	"carry_low": "held", "carry_shoulder": "held", "backswing_hold": "held",
	"reach": "held", "throw_up": "held",
}

## What can be adjusted at each moment: [key, label, bone or "caman"/"twist",
## axis (0 x, 1 y, 2 z), range]. Turning a joint the other way is a minus.
const SLIDERS := [
	["spine_bend", "Bend at the waist (+ forward)", "Spine", 0, 45.0],
	["spine_turn", "Turn the waist (+ left)", "Spine", 1, 45.0],
	["spine_lean", "Lean to the side", "Spine", 2, 30.0],
	["chest_bend", "Bend the chest (+ forward)", "Chest", 0, 30.0],
	["shoulder_turn", "Turn the shoulders", "twist", 0, 60.0],
	["head_nod", "Head (+ up)", "Head", 0, 40.0],
	["hips_turn", "Turn the hips (+ left)", "Hips", 1, 40.0],
	["left_hip", "Left leg (+ forward)", "LeftUpperLeg", 0, 50.0],
	["left_knee", "Left knee (+ bend)", "LeftLowerLeg", 0, 60.0],
	["right_hip", "Right leg (+ forward)", "RightUpperLeg", 0, 50.0],
	["right_knee", "Right knee (+ bend)", "RightLowerLeg", 0, 60.0],
	["caman_across", "Hands (+ to the right)", "caman", 0, 40.0],
	["caman_up", "Hands (+ up)", "caman", 1, 40.0],
	["caman_out", "Hands (+ out in front)", "caman", 2, 40.0],
	["caman_tilt", "Caman head (+ up)", "tilt", 0, 45.0],
	["caman_point", "Caman points (+ left)", "tilt", 1, 45.0],
	["top_grip", "Top hand (+ down the shaft)", "grip", 0, 40.0],
	["low_grip", "Lower hand (+ down the shaft)", "grip", 1, 40.0],
]

## Sliders whose plus way is a minus turn of the joint (bending forward, a
## knee bending, hands out in front along -Z), so plus reads naturally.
const FLIPPED := ["spine_bend", "chest_bend", "left_knee", "right_knee", "caman_out"]

## action -> {"length": 1.0, "keys": [{slider key: value}, x3]}
static var data := {}
## Where they're read from and saved to; tests point these elsewhere.
static var res_path := RES_PATH
static var user_path := USER_PATH
static var _loaded := false
## Bumped on every change, so models can tell their cache is stale.
static var version := 0


static func ensure_loaded(again := false) -> void:
	if _loaded and not again:
		return
	_loaded = true
	data = {}
	for path in [res_path, user_path]:
		if not FileAccess.file_exists(path):
			continue
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			for action in d:
				if d[action] is Dictionary:
					data[action] = _clean(d[action])
	version += 1


static func _clean(t: Dictionary) -> Dictionary:
	var out := {"length": clampf(float(t.get("length", 1.0)), 0.5, 2.0), "keys": [{}, {}, {}]}
	var keys: Variant = t.get("keys", [])
	if keys is Array:
		for i in mini(3, keys.size()):
			if keys[i] is Dictionary:
				for s in SLIDERS:
					if keys[i].has(s[0]):
						out["keys"][i][s[0]] = clampf(float(keys[i][s[0]]), -s[4], s[4])
	return out


## How much longer (or shorter) than built the action takes: 1 = unchanged.
static func length_scale(action: String) -> float:
	ensure_loaded()
	return float(data.get(action, {}).get("length", 1.0))


static func get_value(action: String, phase: int, key: String) -> float:
	ensure_loaded()
	return float(data.get(action, {}).get("keys", [{}, {}, {}])[phase].get(key, 0.0))


static func set_value(action: String, phase: int, key: String, value: float) -> void:
	ensure_loaded()
	if not data.has(action):
		data[action] = {"length": 1.0, "keys": [{}, {}, {}]}
	if absf(value) < 0.01:
		data[action]["keys"][phase].erase(key)
	else:
		data[action]["keys"][phase][key] = value
	version += 1


static func set_length(action: String, scale: float) -> void:
	ensure_loaded()
	if not data.has(action):
		data[action] = {"length": 1.0, "keys": [{}, {}, {}]}
	data[action]["length"] = clampf(scale, 0.5, 2.0)
	version += 1


## Back to the move as built: one moment, or the whole move when phase < 0.
static func reset(action: String, phase: int = -1) -> void:
	ensure_loaded()
	if not data.has(action):
		return
	if phase < 0:
		data.erase(action)
	else:
		data[action]["keys"][phase] = {}
	version += 1


## The moments that can be set for a move or pose, by name.
static func phase_names(name: String) -> Array:
	match STATES.get(name, ""):
		"stride":
			return STRIDE_PHASES
		"held":
			return HELD_PHASES
	return PHASES


## Whether a move has a length to change (one-off actions do).
static func has_length(name: String) -> bool:
	return not STATES.has(name)


## A walk, jog or sprint at stride phase `ph` (radians; the left leg is
## forward while sin(ph) > 0), faded by `amount`.
static func stride(name: String, ph: float, amount: float) -> Dictionary:
	if amount <= 0.001:
		return {}
	var s := sin(ph)
	return _blend(name, [maxf(0.0, s) * amount, maxf(0.0, -s) * amount, amount])


## A held pose (standing, carrying, ...), faded by `amount`.
static func held(name: String, amount: float) -> Dictionary:
	if amount <= 0.001:
		return {}
	return _blend(name, [amount, 0.0, 0.0])


## Adds tweak `b` onto `a` (both as returned by at/stride/held).
static func add(a: Dictionary, b: Dictionary) -> Dictionary:
	if b.is_empty():
		return a
	if a.is_empty():
		return b
	var rot: Dictionary = a["rot"].duplicate()
	for k in b["rot"]:
		rot[k] = rot.get(k, Vector3.ZERO) + b["rot"][k]
	return {"rot": rot, "caman": a["caman"] + b["caman"], "twist": a["twist"] + b["twist"],
		"tilt": a["tilt"] + b["tilt"], "grip": a["grip"] + b["grip"]}


## The adjustment `t` seconds into an action of length `len`, whose three
## moments fall at `times`: {"rot": {bone: Vector3 radians}, "caman":
## Vector3 metres, "twist": radians, "tilt": Vector2 radians (caman head up,
## caman turned left), "grip": Vector2 metres (top and lower hand further
## down the shaft)}, or {} when there is none.
static func at(action: String, t: float, times: Array, len: float) -> Dictionary:
	ensure_loaded()
	var tw: Dictionary = data.get(action, {})
	if tw.is_empty():
		return {}
	var keys: Array = tw["keys"]
	if keys[0].is_empty() and keys[1].is_empty() and keys[2].is_empty():
		return {}
	# Fade in to the wind-up, through the strike and finish, then back out.
	var pts := [0.0, float(times[0]), float(times[1]), float(times[2]), len]
	var w := [0.0, 0.0, 0.0]
	for i in 4:
		var a: float = pts[i]
		var b: float = pts[i + 1]
		if t >= a and (t < b or i == 3):
			var k := clampf((t - a) / maxf(0.001, b - a), 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)
			if i > 0:
				w[i - 1] = 1.0 - k
			if i < 3:
				w[i] = k
			break
	return _blend(action, w)


## The three moments' values mixed by weights `w`.
static func _blend(action: String, w: Array) -> Dictionary:
	ensure_loaded()
	var tw: Dictionary = data.get(action, {})
	if tw.is_empty():
		return {}
	var keys: Array = tw["keys"]
	if keys[0].is_empty() and keys[1].is_empty() and keys[2].is_empty():
		return {}
	var rot := {}
	var caman := Vector3.ZERO
	var twist := 0.0
	var tilt := Vector2.ZERO
	var grip := Vector2.ZERO
	for s in SLIDERS:
		var v := 0.0
		for i in 3:
			v += float(keys[i].get(s[0], 0.0)) * w[i]
		if v == 0.0:
			continue
		if s[0] in FLIPPED:
			v = -v
		match str(s[2]):
			"caman":
				caman[int(s[3])] += v * 0.01
			"twist":
				twist += deg_to_rad(v)
			"tilt":
				tilt[int(s[3])] += deg_to_rad(v)
			"grip":
				grip[int(s[3])] += v * 0.01
			_:
				var e: Vector3 = rot.get(s[2], Vector3.ZERO)
				e[int(s[3])] += deg_to_rad(v)
				rot[s[2]] = e
	return {"rot": rot, "caman": caman, "twist": twist, "tilt": tilt, "grip": grip}


## The three moments of an action, as times into it.
static func moments(action: String, len: float, hit_times: Array) -> Array:
	if action in ["swing", "pass", "volley", "shy"]:
		return hit_times
	return [len * 0.25, len * 0.5, len * 0.75]


## Writes the tweaks out. Returns the file written, or "" on failure.
static func save() -> String:
	ensure_loaded()
	var out := {}
	for action in data:
		var tw: Dictionary = data[action]
		var empty: bool = tw["keys"].all(func(k): return k.is_empty())
		if empty and is_equal_approx(float(tw["length"]), 1.0):
			continue
		out[action] = tw
	var text := JSON.stringify(out, "\t", true)
	for path in [res_path, user_path]:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(text + "\n")
			f.close()
			if path == res_path and FileAccess.file_exists(user_path):
				DirAccess.remove_absolute(user_path)   # it would win over this one when loaded
			return ProjectSettings.globalize_path(path)
	return ""
