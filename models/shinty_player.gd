@tool
class_name ShintyPlayerModel
extends Node3D
## A rigged, animated shinty player built entirely in code: humanoid skeleton,
## kit, helmet with face guard, and a caman (stick) held in both hands.
##
## Units are metres. The model stands on y = 0 and faces -Z (Godot's forward),
## so its right-hand side is +X. Height and build come from player stats;
## kit and helmet colours come from team data. Call setup() with the player and
## team dictionaries from data/teams.json, then each frame call
## set_locomotion() with the player's velocity and play_action() for hits,
## passes, tackles and saves. Listen to the `strike` signal to hit the ball at
## the exact moment the caman reaches it.

## Emitted at the contact frame of "swing", "pass" and "volley". `head_position`
## is the caman head in world space; `power` is 0..1.
signal strike(head_position: Vector3, power: float)
## Emitted when any action finishes and the player returns to running/idle.
signal action_finished(action: StringName)

const BASE_HEIGHT := 1.80
const CAMAN_LENGTH := 0.98
const GRIP_TOP := 0.05     ## distance of the top hand from the butt of the caman
const GRIP_LOW := 0.24     ## distance of the lower hand from the butt
const HAND_GRIP := 0.065   ## wrist to the middle of the grip
const HEAD_LOCAL := Vector3(0.0, -CAMAN_LENGTH + 0.015, -0.055)  ## caman head centre in caman space

## Keeper shirts, picked to stand out from the team's own colours.
const KEEPER_CHOICES := [Color("f2c400"), Color("2e9e4f"), Color("f07c1a"), Color("26262b"), Color("8e44ad")]
const SKIN_TONES := [
	Color("f1d3bc"), Color("e8c1a0"), Color("d9a47f"), Color("f3dccb"),
	Color("c68a64"), Color("8d5a3b"), Color("e5b896"), Color("5e3a26"),
]

## Actions and their total duration in seconds (swing and pass scale with power).
const ACTIONS := {
	"swing": 0.78, "pass": 0.55, "volley": 0.62, "tackle": 0.55, "trap": 0.4,
	"save_left": 0.9, "save_right": 0.9, "celebrate": 1.6,
}

@export_group("Body")
@export_range(150.0, 210.0, 0.5) var height_cm := 180.0:
	set(v): height_cm = v; _dirty = true
## 0 = slight, 1 = heavy-set.
@export_range(0.0, 1.0, 0.01) var build := 0.5:
	set(v): build = v; _dirty = true
@export var skin_color := Color("e8c1a0"):
	set(v): skin_color = v; _dirty = true
## Left-handed players swing from the left side.
@export var left_handed := false:
	set(v): left_handed = v; _dirty = true

@export_group("Kit")
@export var shirt_color := Color("b3122e"):
	set(v): shirt_color = v; _dirty = true
@export var trim_color := Color("f2f2f2"):
	set(v): trim_color = v; _dirty = true
@export var shorts_color := Color("f2f2f2"):
	set(v): shorts_color = v; _dirty = true
@export var socks_color := Color("b3122e"):
	set(v): socks_color = v; _dirty = true
@export var helmet_color := Color("b3122e"):
	set(v): helmet_color = v; _dirty = true
@export var wear_helmet := true:
	set(v): wear_helmet = v; _dirty = true
@export var shirt_number := 0:
	set(v): shirt_number = v; _dirty = true
@export var is_keeper := false:
	set(v): is_keeper = v; _dirty = true

@export_group("Behaviour")
## Fewer meshes (no face guard bars, eyes or number) for distant players.
@export var low_detail := false:
	set(v): low_detail = v; _dirty = true
## Turn to face the direction of travel automatically.
@export var auto_face := false
## When true, call advance(delta) yourself instead of relying on _process.
@export var manual_update := false

var player_data: Dictionary = {}

var _dirty := true
var _skel: Skeleton3D
var _caman: Node3D
var _bone := {}           # name -> index
var _rest_origin := {}    # name -> Vector3
var _hips_rest_y := 0.98
var _velocity := Vector3.ZERO
var _speed := 0.0
var _phase := 0.0
var _time := 0.0
var _action := &""
var _action_t := 0.0
var _action_len := 0.0
var _action_power := 1.0
var _action_height := 0.0
var _struck := false
var _charging := false
var _charge := 0.0
var _look_target = null
var _head_prev := Vector3.ZERO
var _head_velocity := Vector3.ZERO

static var _materials := {}


# --- Public API -------------------------------------------------------------

## Configure from a player and team dictionary as found in data/teams.json.
## Optional player keys: height_cm, weight_kg, skin ("#rrggbb"), hand ("L"/"R").
## Optional team colour keys: primary, secondary, shorts, socks, helmet, keeper.
func setup(player: Dictionary, team: Dictionary = {}) -> void:
	player_data = player
	var body := body_from_stats(player)
	height_cm = body["height_cm"]
	build = body["build"]
	shirt_number = int(player.get("number", 0))
	is_keeper = str(player.get("position", "")) == "GK"
	left_handed = str(player.get("hand", "R")).to_upper().begins_with("L")
	if player.has("skin"):
		skin_color = Color(str(player["skin"]))
	else:
		skin_color = SKIN_TONES[_seed_of(player) % SKIN_TONES.size()]
	var kit := kit_from_team(team, is_keeper)
	shirt_color = kit["shirt"]
	trim_color = kit["trim"]
	shorts_color = kit["shorts"]
	socks_color = kit["socks"]
	helmet_color = kit["helmet"]
	rebuild()


## Height (cm) and build (0..1) for a player. Uses height_cm and weight_kg from
## the data when present; otherwise derives them from the ratings, so strong
## tacklers are bigger and quick players leaner, with a stable per-player
## variation of a few centimetres.
static func body_from_stats(p: Dictionary) -> Dictionary:
	var seed_val := _seed_of(p)
	var jitter := float(seed_val % 1000) / 1000.0 - 0.5
	var jitter2 := float((seed_val / 1000) % 1000) / 1000.0 - 0.5
	var tackling := float(p.get("tackling", 50))
	var keeping := float(p.get("keeping", 20))
	var shooting := float(p.get("shooting", 50))
	var pace := float(p.get("pace", 60))
	var stamina := float(p.get("stamina", 60))
	var h := float(p.get("height_cm", 0))
	if h <= 0.0:
		h = 178.0 + (tackling - 60.0) * 0.12 + maxf(0.0, keeping - 40.0) * 0.1 \
			+ (shooting - 60.0) * 0.04 - (pace - 70.0) * 0.06 + jitter * 10.0
		h = clampf(h, 165.0, 196.0)
	var b: float
	var w := float(p.get("weight_kg", 0))
	if w > 0.0:
		var bmi := w / pow(h / 100.0, 2.0)
		b = clampf((bmi - 20.0) / 10.0, 0.0, 1.0)
	else:
		b = 0.45 + (tackling - 60.0) * 0.012 + (stamina - 65.0) * 0.004 \
			- (pace - 70.0) * 0.01 + jitter2 * 0.2
		b = clampf(b, 0.05, 0.95)
		w = (20.0 + b * 10.0) * pow(h / 100.0, 2.0)
	return {"height_cm": h, "build": b, "weight_kg": roundf(w)}


## Kit colours for a team. Missing colours fall back to primary/secondary.
static func kit_from_team(team: Dictionary, keeper: bool) -> Dictionary:
	var c: Dictionary = team.get("colors", {})
	var primary := Color(str(c.get("primary", "#b3122e")))
	var secondary := Color(str(c.get("secondary", "#f2f2f2")))
	var shirt := primary
	var trim := secondary
	if keeper:
		shirt = Color(str(c["keeper"])) if c.has("keeper") else _contrasting_keeper(primary, secondary)
		trim = primary
	return {
		"shirt": shirt,
		"trim": trim,
		"shorts": Color(str(c["shorts"])) if c.has("shorts") else secondary,
		"socks": Color(str(c["socks"])) if c.has("socks") else primary,
		"helmet": Color(str(c["helmet"])) if c.has("helmet") else primary,
	}


## Tell the model how fast (and which way) the player is moving, in world
## space metres per second. Drives the run cycle.
func set_locomotion(velocity: Vector3) -> void:
	_velocity = Vector3(velocity.x, 0.0, velocity.z)


## Play a one-shot action: swing, pass, volley, tackle, trap, save_left,
## save_right, celebrate. `power` (0..1) scales swings. `contact_height` is the
## ball height in metres for "volley" (0 = ground, up to about 1.6).
func play_action(action: StringName, power: float = 1.0, contact_height: float = 0.0) -> void:
	if not ACTIONS.has(String(action)):
		push_warning("Unknown shinty action: %s" % action)
		return
	_action = action
	_action_t = 0.0
	_action_power = clampf(power, 0.0, 1.0)
	_action_height = clampf(contact_height, 0.0, 1.6)
	_action_len = ACTIONS[String(action)]
	if action == &"swing" or action == &"pass":
		_action_len *= lerpf(0.75, 1.0, _action_power)
	_struck = false
	_charging = false


## Seconds from play_action() to the strike signal, so match logic can launch
## the ball at the moment of contact.
func time_to_contact(action: StringName = &"swing", power: float = 1.0) -> float:
	var saved := [_action, _action_len, _action_power]
	_action = action
	_action_power = clampf(power, 0.0, 1.0)
	_action_len = ACTIONS.get(String(action), 0.78)
	if action == &"swing" or action == &"pass":
		_action_len *= lerpf(0.75, 1.0, _action_power)
	var t := _contact_time()
	_action = saved[0]
	_action_len = saved[1]
	_action_power = saved[2]
	return t


## For match logic that launches the ball the instant a hit is decided: start
## the swing already at the top of the backswing, so contact comes within
## about a tenth of a second instead of half a second later.
func play_hit_now(action: StringName = &"swing", power: float = 1.0, contact_height: float = 0.0) -> void:
	play_action(action, power, contact_height)
	if _is_hit_action(_action):
		_action_t = _swing_times()[0]


## Hold the caman back while the hit button is held. Call release_swing() to hit.
func charge_swing() -> void:
	_charging = true
	_action = &""


func release_swing(power: float) -> void:
	var from_charge := _charge
	play_action(&"swing", power)
	# Skip the part of the backswing already done while charging.
	_action_t = _swing_times()[0] * from_charge
	_charge = 0.0


func is_busy() -> bool:
	return _action != &"" or _charging


func current_action() -> StringName:
	return _action


## Turn the head towards a world point (usually the ball). Pass null to stop.
func look_at_point(target) -> void:
	_look_target = target


## World position of the caman head (the part that hits the ball).
func get_caman_head_position() -> Vector3:
	if _caman == null:
		return global_position
	return _caman.global_transform * HEAD_LOCAL


## World velocity of the caman head, measured from the animation.
func get_caman_head_velocity() -> Vector3:
	return _head_velocity


## Where the ball should sit for a ground strike, in world space (just in
## front of the player on the stick side). Useful for hit range checks.
func get_strike_spot() -> Vector3:
	var s := height_cm / 100.0 / BASE_HEIGHT
	var side := -1.0 if left_handed else 1.0
	return global_transform * Vector3(0.21 * side * s, ShintyBallPhysics.RADIUS, -0.55 * s)


## Height of the top of the helmet/head in metres (for tests and cameras).
func get_top_height() -> float:
	return height_cm / 100.0


func rebuild() -> void:
	_build()
	_dirty = false


# --- Lifecycle --------------------------------------------------------------

func _ready() -> void:
	if _dirty:
		rebuild()


func _process(delta: float) -> void:
	if _dirty:
		rebuild()
	if Engine.is_editor_hint():
		_time += delta
		_pose(delta)
		return
	if not manual_update:
		advance(delta)


## Step the animation by `delta` seconds. Called automatically unless
## manual_update is on.
func advance(delta: float) -> void:
	if _dirty:
		rebuild()
	_time += delta
	_speed = _velocity.length()
	if auto_face and _speed > 0.3:
		var target_yaw := atan2(-_velocity.x, -_velocity.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * 10.0, 0.0, 1.0))
	var stride := lerpf(1.3, 3.4, clampf(_speed / 8.0, 0.0, 1.0)) * height_cm / 180.0
	_phase = fmod(_phase + delta * _speed / stride * TAU, TAU)
	if _charging:
		_charge = minf(1.0, _charge + delta / 0.35)
	elif _action == &"":
		_charge = maxf(0.0, _charge - delta * 4.0)
	if _action != &"":
		_action_t += delta
		if not _struck and _is_hit_action(_action) and _action_t >= _contact_time():
			_struck = true
			_pose(0.0)
			strike.emit(get_caman_head_position(), _action_power)
		if _action_t >= _action_len:
			var done := _action
			_action = &""
			action_finished.emit(done)
	_pose(delta)
	var head := get_caman_head_position()
	if delta > 0.0:
		_head_velocity = (head - _head_prev) / delta
	_head_prev = head


# --- Construction ------------------------------------------------------------

func _build() -> void:
	for c in get_children():
		if c.has_meta("shinty_generated"):
			remove_child(c)
			c.queue_free()
	_bone.clear()
	_rest_origin.clear()

	var s := height_cm / 100.0 / BASE_HEIGHT
	var w := lerpf(0.86, 1.22, build)       # girth multiplier for meshes
	var sw := lerpf(0.94, 1.1, build)       # shoulder/hip width multiplier

	_skel = Skeleton3D.new()
	_skel.name = "Skeleton3D"
	_skel.set_meta("shinty_generated", true)
	_skel.scale = Vector3.ONE * s
	add_child(_skel)

	var defs := [
		["Hips", "", Vector3(0, 0.98, 0)],
		["Spine", "Hips", Vector3(0, 0.10, 0)],
		["Chest", "Spine", Vector3(0, 0.14, 0)],
		["UpperChest", "Chest", Vector3(0, 0.14, 0)],
		["Neck", "UpperChest", Vector3(0, 0.13, 0)],
		["Head", "Neck", Vector3(0, 0.08, 0)],
		["LeftUpperArm", "UpperChest", Vector3(-0.19 * sw, 0.08, 0)],
		["LeftLowerArm", "LeftUpperArm", Vector3(0, -0.29, 0)],
		["LeftHand", "LeftLowerArm", Vector3(0, -0.27, 0)],
		["RightUpperArm", "UpperChest", Vector3(0.19 * sw, 0.08, 0)],
		["RightLowerArm", "RightUpperArm", Vector3(0, -0.29, 0)],
		["RightHand", "RightLowerArm", Vector3(0, -0.27, 0)],
		["LeftUpperLeg", "Hips", Vector3(-0.095 * sw, -0.05, 0)],
		["LeftLowerLeg", "LeftUpperLeg", Vector3(0, -0.44, 0)],
		["LeftFoot", "LeftLowerLeg", Vector3(0, -0.43, 0)],
		["RightUpperLeg", "Hips", Vector3(0.095 * sw, -0.05, 0)],
		["RightLowerLeg", "RightUpperLeg", Vector3(0, -0.44, 0)],
		["RightFoot", "RightLowerLeg", Vector3(0, -0.43, 0)],
	]
	for d in defs:
		var idx := _skel.get_bone_count()
		_skel.add_bone(d[0])
		if d[1] != "":
			_skel.set_bone_parent(idx, _bone[d[1]])
		_skel.set_bone_rest(idx, Transform3D(Basis(), d[2]))
		_skel.set_bone_pose_position(idx, d[2])
		_bone[d[0]] = idx
		_rest_origin[d[0]] = d[2]
	_hips_rest_y = 0.98

	var skin := _mat(skin_color, 0.7)
	var shirt := _mat(shirt_color, 0.8)
	var trim := _mat(trim_color, 0.8)
	var shorts := _mat(shorts_color, 0.8)
	var socks := _mat(socks_color, 0.85)
	var boot := _mat(Color("16161a"), 0.45)

	# Torso
	var hips := _attach("Hips")
	_part(hips, _cyl(0.155 * w, 0.165 * w, 0.24), shorts, Vector3(0, -0.02, 0), Vector3(1, 1, 0.72))
	var spine := _attach("Spine")
	_part(spine, _cyl(0.15 * w, 0.145 * w, 0.17), shirt, Vector3(0, 0.07, 0), Vector3(1, 1, 0.68))
	var chest := _attach("Chest")
	_part(chest, _cyl(0.17 * w, 0.15 * w, 0.17), shirt, Vector3(0, 0.07, 0), Vector3(1, 1, 0.66))
	var upper := _attach("UpperChest")
	_part(upper, _cyl(0.175 * w * sw, 0.17 * w, 0.14), shirt, Vector3(0, 0.05, 0), Vector3(1, 1, 0.64))
	var shoulders := _part(upper, _capsule(0.075 * w, 0.44 * sw), shirt, Vector3(0, 0.085, 0.0), Vector3(1, 1, 0.9))
	shoulders.rotation = Vector3(0, 0, PI / 2)
	# Collar
	_part(upper, _cyl(0.068, 0.078, 0.035), trim, Vector3(0, 0.135, 0))
	# Chest band in the trim colour so teams read at a distance
	_part(chest, _cyl(0.172 * w, 0.168 * w, 0.035), trim, Vector3(0, 0.13, 0), Vector3(1, 1, 0.66))
	if shirt_number > 0 and not low_detail:
		var back := Label3D.new()
		back.text = str(shirt_number)
		back.font_size = 96
		back.pixel_size = 0.0022
		back.outline_size = 14
		back.modulate = trim_color
		back.outline_modulate = shirt_color.darkened(0.45)
		back.position = Vector3(0, 0.0, 0.123 * w)
		back.double_sided = false
		upper.add_child(back)

	# Head and neck
	var neck := _attach("Neck")
	_part(neck, _cyl(0.052, 0.058, 0.11), skin, Vector3(0, 0.03, 0))
	var head := _attach("Head")
	_part(head, _sphere(0.112), skin, Vector3(0, 0.11, 0), Vector3(0.9, 1.05, 1.0))
	_part(head, _sphere(0.02), skin, Vector3(0, 0.09, -0.112))  # nose
	if not low_detail:
		var eye := _mat(Color("1d1d22"), 0.3)
		_part(head, _sphere(0.012), eye, Vector3(-0.037, 0.125, -0.098))
		_part(head, _sphere(0.012), eye, Vector3(0.037, 0.125, -0.098))
		_part(head, _sphere(0.02), skin, Vector3(-0.1, 0.11, 0.0), Vector3(0.5, 1, 0.8))  # ears
		_part(head, _sphere(0.02), skin, Vector3(0.1, 0.11, 0.0), Vector3(0.5, 1, 0.8))
	if wear_helmet:
		_build_helmet(head)
	else:
		var hair := _mat(skin_color.darkened(0.7), 0.9)
		var cap := _part(head, _hemi(0.118), hair, Vector3(0, 0.125, 0.008), Vector3(0.93, 1.0, 1.0))
		cap.rotation.x = -0.25

	# Arms
	for side in ["Left", "Right"]:
		var ua := _attach(side + "UpperArm")
		_part(ua, _capsule(0.052 * w, 0.31), shirt, Vector3(0, -0.14, 0))
		_part(ua, _cyl(0.054 * w, 0.054 * w, 0.03), trim, Vector3(0, -0.255, 0))
		var la := _attach(side + "LowerArm")
		_part(la, _capsule(0.042 * w, 0.29), skin, Vector3(0, -0.135, 0))
		var hand := _attach(side + "Hand")
		_part(hand, _sphere(0.045), skin, Vector3(0, -0.05, 0), Vector3(0.85, 1.25, 0.95))

	# Legs
	for side in ["Left", "Right"]:
		var ul := _attach(side + "UpperLeg")
		_part(ul, _capsule(0.07 * w, 0.46), skin, Vector3(0, -0.22, 0))
		_part(ul, _cyl(0.092 * w, 0.086 * w, 0.2), shorts, Vector3(0, -0.07, 0))
		var ll := _attach(side + "LowerLeg")
		_part(ll, _capsule(0.056 * w, 0.44), skin, Vector3(0, -0.2, 0))
		_part(ll, _cyl(0.061 * w, 0.046 * w, 0.33), socks, Vector3(0, -0.25, 0))
		_part(ll, _cyl(0.063 * w, 0.063 * w, 0.03), trim, Vector3(0, -0.1, 0))
		var foot := _attach(side + "Foot")
		_part(foot, _box(Vector3(0.1, 0.075, 0.27)), boot, Vector3(0, -0.02, -0.06))

	_build_caman()
	_pose(0.0)
	_head_prev = get_caman_head_position()


func _build_helmet(head: Node3D) -> void:
	var shell := _mat(helmet_color, 0.35, 0.1)
	var metal := _mat(Color("b8bcc2"), 0.3, 0.8)
	var black := _mat(Color("1b1b1f"), 0.6)
	var c := Vector3(0, 0.115, 0.004)
	# Shell: dome plus a band round the back of the head
	var dome := _part(head, _hemi(0.132), shell, c + Vector3(0, 0.005, 0), Vector3(0.92, 1.0, 1.02))
	dome.rotation.x = -0.12
	var band := _part(head, _cyl(0.13, 0.126, 0.07), shell, c + Vector3(0, -0.02, 0.012), Vector3(0.92, 1, 1.0))
	band.rotation.x = -0.05
	# Rim over the brow
	_part(head, _box(Vector3(0.2, 0.022, 0.03)), shell, c + Vector3(0, 0.035, -0.118))
	if low_detail:
		_part(head, _box(Vector3(0.17, 0.14, 0.012)), metal, c + Vector3(0, -0.05, -0.137))
		return
	# Face guard: vertical bars on an arc in front of the face
	var r := 0.138
	for deg in [-50.0, -25.0, 0.0, 25.0, 50.0]:
		var a := deg_to_rad(deg)
		var p := c + Vector3(sin(a) * r * 0.92, -0.045, -cos(a) * r)
		_part(head, _cyl(0.0055, 0.0055, 0.15), metal, p)
	# Horizontal bars (built from short segments round the arc)
	for y in [-0.005, -0.075, -0.115]:
		var prev := Vector3.ZERO
		for i in 9:
			var a2 := deg_to_rad(lerpf(-62.0, 62.0, i / 8.0))
			var p2 := c + Vector3(sin(a2) * r * 0.92, y, -cos(a2) * r)
			if i > 0:
				_segment(head, prev, p2, 0.0055, metal)
			prev = p2
	# Chin strap
	_part(head, _box(Vector3(0.012, 0.11, 0.012)), black, c + Vector3(-0.104, -0.075, -0.02))
	_part(head, _box(Vector3(0.012, 0.11, 0.012)), black, c + Vector3(0.104, -0.075, -0.02))


func _build_caman() -> void:
	_caman = Node3D.new()
	_caman.name = "Caman"
	_skel.add_child(_caman)
	var wood := _mat(Color("b98a52"), 0.55)
	var head_wood := _mat(Color("a8763f"), 0.5)
	var tape := _mat(Color("202024"), 0.8)
	# Shaft from the butt (origin) down -Y
	_part(_caman, _cyl(0.015, 0.018, CAMAN_LENGTH - 0.12), wood, Vector3(0, -(CAMAN_LENGTH - 0.12) / 2.0, 0))
	_part(_caman, _cyl(0.019, 0.019, 0.3), tape, Vector3(0, -0.15, 0))
	_part(_caman, _cyl(0.022, 0.022, 0.02), tape, Vector3(0, -0.005, 0))
	# The bas (head): a wedge that curves forward (-Z); both faces can strike.
	var segs := [
		[Vector3(0, -CAMAN_LENGTH + 0.1, 0.004), 0.06, 0.0],
		[Vector3(0, -CAMAN_LENGTH + 0.05, -0.012), 0.06, 0.35],
		[Vector3(0, -CAMAN_LENGTH + 0.018, -0.045), 0.065, 0.95],
		[Vector3(0, -CAMAN_LENGTH + 0.008, -0.09), 0.055, 1.4],
	]
	for sgm in segs:
		var m := _part(_caman, _box(Vector3(0.036, sgm[1], 0.05)), head_wood, sgm[0])
		m.rotation.x = sgm[2]


func _attach(bone_name: String) -> BoneAttachment3D:
	var a := BoneAttachment3D.new()
	a.name = bone_name + "Attach"
	a.bone_name = bone_name
	_skel.add_child(a)
	return a


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _segment(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	var mi := _part(parent, _cyl(radius, radius, a.distance_to(b)), mat, (a + b) / 2.0)
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.basis = Basis(x, y, x.cross(y))


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 10 if low_detail else 16
	m.rings = 1
	return m


func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, r * 2.0)
	m.radial_segments = 10 if low_detail else 16
	m.rings = 4
	return m


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 10 if low_detail else 18
	m.rings = 6 if low_detail else 10
	return m


func _hemi(r: float) -> SphereMesh:
	var m := _sphere(r)
	m.is_hemisphere = true
	m.height = r
	return m


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _mat(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var key := "%s/%.2f/%.2f" % [color.to_html(), roughness, metallic]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	_materials[key] = m
	return m


static func _contrasting_keeper(primary: Color, secondary: Color) -> Color:
	var best: Color = KEEPER_CHOICES[0]
	var best_d := -1.0
	for c in KEEPER_CHOICES:
		var col: Color = c
		var d := minf(_color_distance(col, primary), _color_distance(col, secondary))
		if d > best_d + 0.05:
			best_d = d
			best = col
	return best


static func _color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


static func _seed_of(p: Dictionary) -> int:
	return absi(hash("%s#%s" % [p.get("name", ""), p.get("number", 0)]))


# --- Animation ---------------------------------------------------------------

func _is_hit_action(a: StringName) -> bool:
	return a == &"swing" or a == &"pass" or a == &"volley"


## [backswing end, contact, follow-through end] as times in seconds.
func _swing_times() -> Array:
	var l := _action_len
	if _action == &"volley":
		return [l * 0.3, l * 0.42, l * 0.65]
	return [l * 0.36, l * 0.47, l * 0.7]


func _contact_time() -> float:
	return _swing_times()[1]


## Pose everything for the current state. Legs and torso are forward
## kinematics; the caman is placed, then both arms reach it with two-bone IK.
func _pose(_delta: float) -> void:
	if _skel == null:
		return
	var run := clampf(_speed / 2.5, 0.0, 1.0)
	var sprint := clampf((_speed - 4.0) / 4.0, 0.0, 1.0)
	var ph := _phase
	var rot := {}       # bone name -> Vector3 euler
	var hips_off := Vector3.ZERO

	# Ready stance / idle breathing
	var idle := 1.0 - run
	var breathe := sin(_time * 1.8) * 0.015
	rot["Spine"] = Vector3(-0.22 * idle - 0.12 * run - 0.16 * sprint, 0, 0)
	rot["Chest"] = Vector3(breathe, 0, 0)
	rot["UpperChest"] = Vector3(-0.08 * idle, 0, 0)
	rot["Neck"] = Vector3(0.2 * idle + 0.2 * run + 0.15 * sprint, 0, 0)
	rot["Head"] = Vector3(0.04, 0, 0)

	# Legs: run cycle blended with a slightly crouched stance
	var amp := lerpf(0.35, 0.85, sprint)
	var knee_amp := lerpf(0.8, 1.5, sprint)
	for side in ["Left", "Right"]:
		var p := ph if side == "Left" else ph + PI
		var sgn := -1.0 if side == "Left" else 1.0
		var thigh_run := sin(p) * amp - 0.05
		var knee_run := -(0.2 + knee_amp * maxf(0.0, cos(p)) * 0.85)
		var thigh_idle := 0.22
		var knee_idle := -0.42
		rot[side + "UpperLeg"] = Vector3(lerpf(thigh_idle, thigh_run, run), 0, sgn * 0.05 * idle)
		rot[side + "LowerLeg"] = Vector3(lerpf(knee_idle, knee_run, run), 0, 0)
		rot[side + "Foot"] = Vector3(lerpf(0.2, -0.2 - 0.3 * sin(p), run), 0, 0)
	hips_off.y = -absf(cos(ph)) * 0.045 * run
	rot["Hips"] = Vector3(0, sin(ph) * 0.12 * run, 0)
	rot["Chest"] += Vector3(0, -sin(ph) * 0.1 * run, 0)

	# Caman carry pose (in hips-relative skeleton space, right-handed)
	var cam_p := _lerp3(Vector3(0.13, -0.08, -0.28), Vector3(0.2, -0.02, -0.22), run)
	var cam_d := _lerp3(Vector3(0.25, -0.85, -0.45), Vector3(0.25, -0.62, -0.72), run).normalized()
	cam_p.y += sin(ph * 2.0) * 0.025 * run
	var twist := 0.0

	if _charging or _charge > 0.0:
		var k := _ease(_charge)
		var bp := _backswing(1.0)
		cam_p = cam_p.lerp(bp[0], k)
		cam_d = cam_d.slerp(bp[1], k)
		twist = -0.55 * k
		_crouch(rot, 0.4 * k)

	if _action != &"":
		var r := _action_pose(rot)
		if r.size() > 0:
			cam_p = r[0]
			cam_d = r[1]
			twist = r[2]
			hips_off += r[3]

	# Torso twist through the swing
	rot["Spine"] += Vector3(0, twist * 0.35, 0)
	rot["Chest"] += Vector3(0, twist * 0.35, 0)
	rot["UpperChest"] += Vector3(0, twist * 0.3, 0)

	# Look at the ball
	if _look_target != null and _look_target is Vector3:
		var local: Vector3 = global_transform.affine_inverse() * (_look_target as Vector3)
		var yaw := clampf(atan2(-local.x, -local.z) - twist, -1.1, 1.1)
		var pitch := clampf(atan2(local.y - 1.6, Vector2(local.x, local.z).length()), -0.6, 0.4)
		rot["Neck"] += Vector3(-pitch * 0.4, yaw * 0.45, 0)
		rot["Head"] += Vector3(-pitch * 0.6, yaw * 0.55, 0)

	# Mirror for left-handers: swap left/right bones and flip yaw/roll.
	if left_handed:
		rot = _mirror_rot(rot)
		cam_p.x = -cam_p.x
		cam_d.x = -cam_d.x
		twist = -twist

	# Keep feet on the ground: drop the hips by however much the longer leg shortened.
	var drop := minf(_leg_drop(rot, "Left"), _leg_drop(rot, "Right"))
	hips_off.y -= drop

	for bone_name in _bone:
		var e: Vector3 = rot.get(bone_name, Vector3.ZERO)
		_skel.set_bone_pose_rotation(_bone[bone_name], Quaternion.from_euler(e))
	_skel.set_bone_pose_position(_bone["Hips"], _rest_origin["Hips"] + hips_off)

	# Place the caman relative to the hips, turned with the torso.
	var hips_g := _skel.get_bone_global_pose(_bone["Hips"])
	var yaw_b := Basis(Vector3.UP, (-twist if left_handed else twist) * 0.5 + rot["Hips"].y * (-1.0 if left_handed else 1.0))
	if left_handed:
		yaw_b = Basis(Vector3.UP, -twist * 0.5 - rot["Hips"].y)
	var p_sk: Vector3 = hips_g.origin + yaw_b * cam_p
	var d_sk: Vector3 = (yaw_b * cam_d).normalized()
	var cb := _caman_basis(d_sk, yaw_b * Vector3(0.0, -0.3, -1.0))
	var ct := Transform3D(cb, p_sk)
	var top_side := "Right" if left_handed else "Left"
	var low_side := "Left" if left_handed else "Right"
	# Keep both grips within arm's reach: slide the caman towards the shoulders.
	for iter in 3:
		for g in [[top_side, GRIP_TOP], [low_side, GRIP_LOW]]:
			var grip: Vector3 = ct * Vector3(0, -g[1], 0)
			var to_grip: Vector3 = grip - _shoulder(g[0])
			var reach := _arm_reach(g[0]) * 0.985
			if to_grip.length() > reach:
				ct.origin -= to_grip.normalized() * (to_grip.length() - reach)
	# Never let the head dig into the ground.
	var head_y := (ct * HEAD_LOCAL).y - 0.02
	if head_y < 0.0:
		ct.origin.y -= head_y
	_caman.transform = ct

	# Both hands grip the shaft: top hand near the butt, lower hand further down.
	var top := ct * Vector3(0, -GRIP_TOP, 0)
	var low := ct * Vector3(0, -GRIP_LOW, 0)
	_solve_arm(top_side, top)
	_solve_arm(low_side, low)


## Returns [caman position, caman direction, twist, hips offset] for the
## current action, or [] for none. May also adjust `rot` (legs, torso).
func _action_pose(rot: Dictionary) -> Array:
	var t := _action_t
	var hips_off := Vector3.ZERO
	var ready_p := Vector3(0.13, -0.08, -0.28)
	var ready_d := Vector3(0.25, -0.85, -0.45).normalized()
	match _action:
		&"swing", &"pass", &"volley":
			var times := _swing_times()
			var t0: float = times[0]
			var t1: float = times[1]
			var t2: float = times[2]
			var size := lerpf(0.45, 1.0, _action_power) if _action != &"pass" else 0.35 + 0.25 * _action_power
			var h := _action_height if _action == &"volley" else 0.0
			var back := _backswing(size)
			var contact := _contact(h)
			var follow := _follow(size, h)
			var p: Vector3
			var d: Vector3
			var twist: float
			if t < t0:
				var k := _ease(t / t0)
				p = ready_p.lerp(back[0], k)
				d = ready_d.slerp(back[1], k)
				twist = -0.55 * size * k
				_crouch(rot, 0.75 * k)
			elif t < t1:
				var k := (t - t0) / (t1 - t0)
				k = k * k  # accelerate into the ball
				p = back[0].lerp(contact[0], k)
				d = back[1].slerp(contact[1], k)
				twist = lerpf(-0.55 * size, 0.1, k)
				_crouch(rot, 0.75)
				_step(rot, k)
			elif t < t2:
				var k := _ease_out((t - t1) / (t2 - t1))
				p = contact[0].lerp(follow[0], k)
				d = contact[1].slerp(follow[1], k)
				twist = lerpf(0.1, 0.5 * size, k)
				_crouch(rot, 0.75 * (1.0 - k * 0.5))
				_step(rot, 1.0)
			else:
				var k := _ease((t - t2) / maxf(0.01, _action_len - t2))
				p = follow[0].lerp(ready_p, k)
				d = follow[1].slerp(ready_d, k)
				twist = lerpf(0.5 * size, 0.0, k)
				_step(rot, 1.0 - k)
			if h > 0.3:
				hips_off.y += 0.0
			return [p, d, twist, hips_off]
		&"tackle":
			var k := sin(clampf(t / _action_len, 0.0, 1.0) * PI)
			rot["Spine"] += Vector3(-0.45 * k, 0, 0)
			rot["LeftUpperLeg"] = rot["LeftUpperLeg"].lerp(Vector3(0.95, 0, -0.05), k)
			rot["LeftLowerLeg"] = rot["LeftLowerLeg"].lerp(Vector3(-0.9, 0, 0), k)
			rot["RightUpperLeg"] = rot["RightUpperLeg"].lerp(Vector3(-0.45, 0, 0.05), k)
			rot["RightLowerLeg"] = rot["RightLowerLeg"].lerp(Vector3(-0.2, 0, 0), k)
			hips_off.z = -0.12 * k
			var p2 := ready_p.lerp(Vector3(0.02, -0.25, -0.5), k)
			var d2 := ready_d.slerp(Vector3(0.05, -0.55, -0.83).normalized(), k)
			return [p2, d2, 0.1 * k, hips_off]
		&"trap":
			var k := sin(clampf(t / _action_len, 0.0, 1.0) * PI)
			_crouch(rot, 0.6 * k)
			var p3 := ready_p.lerp(Vector3(0.06, -0.2, -0.33), k)
			var d3 := ready_d.slerp(Vector3(0.06, -0.8, -0.6).normalized(), k)
			return [p3, d3, 0.0, hips_off]
		&"save_left", &"save_right":
			var side := -1.0 if _action == &"save_left" else 1.0
			var u := clampf(t / _action_len, 0.0, 1.0)
			var k := sin(minf(1.0, u * 2.2) * PI * 0.5) * (1.0 - _ease(maxf(0.0, (u - 0.6) / 0.4)))
			rot["Spine"] += Vector3(-0.1, 0, -side * 0.5 * k)
			rot["Chest"] += Vector3(0, 0, -side * 0.2 * k)
			var lead := "Left" if side < 0.0 else "Right"
			var trail := "Right" if side < 0.0 else "Left"
			rot[lead + "UpperLeg"] = rot[lead + "UpperLeg"].lerp(Vector3(0.3, 0, side * 0.55), k)
			rot[lead + "LowerLeg"] = rot[lead + "LowerLeg"].lerp(Vector3(-0.7, 0, 0), k)
			rot[trail + "UpperLeg"] = rot[trail + "UpperLeg"].lerp(Vector3(0.0, 0, side * 0.2), k)
			rot[trail + "LowerLeg"] = rot[trail + "LowerLeg"].lerp(Vector3(-0.1, 0, 0), k)
			hips_off.x = side * 0.28 * k
			var p4 := ready_p.lerp(Vector3(side * 0.42, 0.05, -0.22), k)
			var d4 := ready_d.slerp(Vector3(side * 0.35, -0.94, -0.05).normalized(), k)
			if side < 0.0:
				# Stick crosses the body to block on the left
				p4 = ready_p.lerp(Vector3(-0.3, 0.1, -0.3), k)
				d4 = ready_d.slerp(Vector3(-0.45, -0.89, -0.1).normalized(), k)
			return [p4, d4, 0.0, hips_off]
		&"celebrate":
			var u := clampf(t / _action_len, 0.0, 1.0)
			var k := sin(minf(1.0, u * 3.0) * PI * 0.5) * (1.0 - _ease(maxf(0.0, (u - 0.75) / 0.25)))
			var hop := maxf(0.0, sin(u * TAU * 2.0)) * 0.12 * k
			hips_off.y += hop
			rot["Spine"] += Vector3(0.12 * k, 0, 0)
			rot["Neck"] += Vector3(-0.25 * k, 0, 0)
			var p5 := ready_p.lerp(Vector3(0.05, 0.62, -0.12), k)
			var d5 := ready_d.slerp(Vector3(0.12, 0.99, 0.08).normalized(), k)
			return [p5, d5, 0.0, hips_off]
	return []


func _backswing(size: float) -> Array:
	var p := Vector3(0.14, -0.08, -0.26).lerp(Vector3(0.3, 0.36, 0.02), size)
	var d := Vector3(0.25, -0.85, -0.45).normalized().slerp(Vector3(0.4, 0.55, 0.73).normalized(), size)
	return [p, d]


func _contact(h: float) -> Array:
	var k := clampf(h / 1.4, 0.0, 1.0)
	var p := Vector3(0.1, -0.2, -0.22).lerp(Vector3(0.12, 0.3, -0.3), k)
	var d := Vector3(0.18, -0.93, -0.32).normalized().slerp(Vector3(0.75, -0.05, -0.66).normalized(), k)
	return [p, d]


func _follow(size: float, h: float) -> Array:
	var k := clampf(h / 1.4, 0.0, 1.0)
	var p := Vector3(-0.05, -0.05, -0.3).lerp(Vector3(-0.22, 0.28, -0.25), size)
	var d := Vector3(-0.2, -0.75, -0.63).normalized().slerp(Vector3(-0.5, 0.6, -0.62).normalized(), size)
	p = p.lerp(Vector3(-0.25, 0.3, -0.2), k * 0.5)
	return [p, d]


func _crouch(rot: Dictionary, k: float) -> void:
	for side in ["Left", "Right"]:
		rot[side + "UpperLeg"] += Vector3(0.25 * k, 0, 0)
		rot[side + "LowerLeg"] += Vector3(-0.45 * k, 0, 0)
		rot[side + "Foot"] += Vector3(0.2 * k, 0, 0)
	rot["Spine"] += Vector3(-0.2 * k, 0, 0)


## Front (left) foot steps towards the ball during the downswing.
func _step(rot: Dictionary, k: float) -> void:
	rot["LeftUpperLeg"] += Vector3(0.3 * k, 0, 0)
	rot["LeftLowerLeg"] += Vector3(-0.1 * k, 0, 0)
	rot["RightUpperLeg"] += Vector3(-0.2 * k, 0, 0)


## How much a leg's vertical reach shrank from bending, in skeleton units.
func _leg_drop(rot: Dictionary, side: String) -> float:
	var a: Vector3 = rot.get(side + "UpperLeg", Vector3.ZERO)
	var b: Vector3 = rot.get(side + "LowerLeg", Vector3.ZERO)
	var l1 := 0.44
	var l2 := 0.43
	var t := Basis.from_euler(a)
	var knee := t * Vector3(0, -l1, 0)
	var ankle := knee + (t * Basis.from_euler(b)) * Vector3(0, -l2, 0)
	return (l1 + l2) + ankle.y


func _mirror_rot(rot: Dictionary) -> Dictionary:
	var out := {}
	for k in rot:
		var name: String = k
		var e: Vector3 = rot[k]
		e = Vector3(e.x, -e.y, -e.z)
		if name.begins_with("Left"):
			name = "Right" + name.substr(4)
		elif name.begins_with("Right"):
			name = "Left" + name.substr(5)
		out[name] = e
	return out


func _caman_basis(dir: Vector3, face: Vector3) -> Basis:
	var y := -dir.normalized()
	var f := face - y * face.dot(y)
	if f.length() < 0.05:
		f = Vector3.FORWARD - y * Vector3.FORWARD.dot(y)
		if f.length() < 0.05:
			f = Vector3.UP - y * Vector3.UP.dot(y)
	var z := -f.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


func _shoulder(side: String) -> Vector3:
	var ua: int = _bone[side + "UpperArm"]
	return _skel.get_bone_global_pose(_skel.get_bone_parent(ua)) * _rest_origin[side + "UpperArm"]


func _arm_reach(side: String) -> float:
	return (_rest_origin[side + "LowerArm"] as Vector3).length() \
		+ (_rest_origin[side + "Hand"] as Vector3).length() + HAND_GRIP


## Two-bone IK in skeleton space: bend the arm so the hand reaches `target`.
func _solve_arm(side: String, target: Vector3) -> void:
	var ua: int = _bone[side + "UpperArm"]
	var la: int = _bone[side + "LowerArm"]
	var hd: int = _bone[side + "Hand"]
	var parent_g := _skel.get_bone_global_pose(_skel.get_bone_parent(ua))
	var shoulder: Vector3 = parent_g * _rest_origin[side + "UpperArm"]
	var a: float = (_rest_origin[side + "LowerArm"] as Vector3).length()
	var b: float = (_rest_origin[side + "Hand"] as Vector3).length() + HAND_GRIP
	var to_t := target - shoulder
	var d := clampf(to_t.length(), 0.05, (a + b) * 0.999)
	var dir := to_t.normalized()
	var sgn := -1.0 if side == "Left" else 1.0
	# Elbows point down and out, a little backwards.
	var pole := parent_g.basis * Vector3(sgn * 0.8, -1.0, 0.35)
	var perp := pole - dir * pole.dot(dir)
	if perp.length() < 0.001:
		perp = parent_g.basis * Vector3(0, 0, 1)
	perp = perp.normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var elbow := shoulder + dir * (cos_a * a) + perp * (sqrt(1.0 - cos_a * cos_a) * a)
	var hand := shoulder + dir * d
	var ub := _basis_down(elbow - shoulder, perp)
	var lb := _basis_down(hand - elbow, perp)
	var pb := parent_g.basis.orthonormalized()
	_skel.set_bone_pose_rotation(ua, (pb.inverse() * ub).get_rotation_quaternion())
	_skel.set_bone_pose_rotation(la, (ub.inverse() * lb).get_rotation_quaternion())
	_skel.set_bone_pose_rotation(hd, Quaternion.IDENTITY)


func _basis_down(v: Vector3, ref: Vector3) -> Basis:
	var y := -v.normalized()
	var x := ref.cross(y)
	if x.length() < 0.001:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


static func _lerp3(a: Vector3, b: Vector3, t: float) -> Vector3:
	return a.lerp(b, t)


static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func _ease_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - (1.0 - x) * (1.0 - x)
