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
const CAMAN_LENGTH := 1.14  ## a full-size caman, measured off a real one
const GRIP_TOP := 0.05     ## distance of the top hand from the butt of the caman
const GRIP_LOW := 0.24     ## distance of the lower hand from the butt
const HAND_GRIP := 0.065   ## wrist to the middle of the grip
const MEET_MAX := 0.7   ## m: furthest a swing is steered to meet the ball
const HEAD_LOCAL := Vector3(0.0, -CAMAN_LENGTH + 0.015, -0.055)  ## caman head centre in caman space
## Ready stance, hips space: butt of the caman and its direction to the head.
const READY_P := Vector3(0.16, 0.0, -0.26)
const READY_D := Vector3(-0.08, -0.55, -0.83)
## Stumble power from which the player goes down (a stagger of about 0.65 s).
const FALL_AT := 0.5
## Seconds a fallen player takes to get back up.
const GET_UP := 0.55

## Keeper shirts, picked to stand out from the team's own colours.
const KEEPER_CHOICES := [Color("f2c400"), Color("2e9e4f"), Color("f07c1a"), Color("26262b"), Color("8e44ad")]
const SKIN_TONES := [
	Color("f1d3bc"), Color("e8c1a0"), Color("d9a47f"), Color("f3dccb"),
	Color("c68a64"), Color("8d5a3b"), Color("e5b896"), Color("5e3a26"),
]

## Actions and their total duration in seconds (swing and pass scale with power).
const ACTIONS := {
	"swing": 0.78, "pass": 0.55, "volley": 0.62, "tackle": 0.55, "trap": 0.4, "feet_trap": 0.6,
	"thigh_trap": 0.6, "chest_trap": 0.65, "pencil": 0.6, "air_kill": 0.5, "air_clear": 0.45,
	"save_left": 0.9, "save_right": 0.9, "save_feet": 0.7, "save_high_left": 0.8, "save_high_right": 0.8,
	"celebrate": 1.6,
	"shy": 2.0, "stumble": 0.7, "poke": 0.35, "block": 0.6, "cleek": 0.45, "barge": 0.4,
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
## The caman's look (ShintyCaman design); empty for the plain default.
@export var caman_design := {}:
	set(v): caman_design = v; _dirty = true
@export var shirt_number := 0:
	set(v): shirt_number = v; _dirty = true
@export var is_keeper := false:
	set(v): is_keeper = v; _dirty = true

@export_group("Behaviour")
## Fewer meshes (no face guard bars, eyes or number) for distant players.
## Running off the ball, carry the caman up by the shoulder instead of low
## by the waist. setup() picks it per player.
@export var shoulder_carry := false
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
var _prev_velocity := Vector3.ZERO
var _accel := Vector3.ZERO        # smoothed, world space, for leaning
var _reach_target = null          # world point the caman head reaches for
## World direction the face of the bas turns to while reaching (null: the
## usual, hook up). The toe points the other way; the menu throw-up uses it to
## curl each bas in over the other.
var reach_face = null
var _reach_want := 0.0
var _meet_target = null           # world point the bas meets the ball at in a hit (set_meet)
var _reach := 0.0                 # smoothed 0..1
var _free_hand = null             # skeleton-space target for a hand off the caman
var _free_low = null              # the same for the lower hand (one-handed reach)
var _one_hand := false
var _carry := 0.0                 # smoothed 0..1: caman carried one-handed on the run
var _carry_from := 0.0            # _carry when the current action started
var _carry_fade := 0.15           # seconds the stick takes to come off the shoulder
var _action_age := 0.0            # seconds since the current action started
var _seed := 0.0                  # 0..1 per player, so no two move in step
var _sway := Vector3.ZERO         # trunk lean spring (x forward/back, z sideways), radians
var _sway_v := Vector3.ZERO
var _jolt := Vector3.ZERO         # last knock, world m/s beyond what legs can do
var _jolt_age := 9.0
var _yaw_prev = null
var _yaw_rate := 0.0              # how fast the player is turning, rad/s
var _puff := 0.0                  # out of breath after sprinting, 0..1
var _stumble_dir := Vector2.ZERO  # model space x/z: which way the stumble goes
var _free_blend := 1.0            # how far the free hand has gone to _free_hand
var _falling := false             # this stumble ends on the ground
var _rag: ShintyRagdoll = null    # the body while knocked down
var _rag_w := 0.0                 # 0 = animation, 1 = ragdoll
var _rag_face := Vector3.FORWARD  # world: which way the fallen caman's face points
var _rag_origin := Vector3.ZERO   # where the model stood last frame, world


# --- Public API -------------------------------------------------------------

## Configure from a player and team dictionary as found in data/teams.json.
## Optional player keys: height_cm, weight_kg, skin ("#rrggbb"), hand ("L"/"R").
## Optional team colour keys: primary, secondary, shorts, socks, helmet, keeper.
## An optional "caman" key on the player, else the team, holds the caman
## design (ShintyCaman), whose helmet colour, if set, replaces the kit's.
func setup(player: Dictionary, team: Dictionary = {}) -> void:
	player_data = player
	var body := body_from_stats(player)
	height_cm = body["height_cm"]
	build = body["build"]
	shirt_number = int(player.get("number", 0))
	is_keeper = str(player.get("position", "")) == "GK"
	shoulder_carry = carries_on_shoulder(player)
	_seed = float((_seed_of(player) / 13) % 1000) / 1000.0
	_phase = _seed * TAU
	_time = _seed * 20.0
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
	# The player's own caman if they have one, else the club's.
	var design: Dictionary = player.get("caman", team.get("caman", {})).duplicate()
	if is_keeper:
		design["shape"] = ShintyCaman.SHAPES.find("Keeper")  # the wide keeper's bas
	caman_design = design
	if str(caman_design.get("helmet", "")) != "":
		helmet_color = Color(str(caman_design["helmet"]))
	set_meta("kit_pattern", str(team.get("colors", {}).get("pattern", "")))
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


## Whether a player carries the caman up by the shoulder when running (about
## two in five do) rather than low by the waist. Stable for each player.
static func carries_on_shoulder(p: Dictionary) -> bool:
	return (_seed_of(p) / 7) % 5 < 2


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


## Reach the caman head towards a world point (a loose ball, an opponent's
## ball, a shot flying past a keeper). `amount` 0..1 is how far into the
## reach to go: the body leans and lunges, the arms extend, and the stick head
## goes as close to the point as arms and caman allow. Pass null to stop.
## `one_handed`: let go with the lower hand and reach with the top hand at the
## end of the handle, arm straight, the free arm out for balance. It reaches
## further but with less control (a poke, a block or a tap).
func set_reach(target, amount: float = 1.0, one_handed: bool = false) -> void:
	_reach_target = target
	_reach_want = clampf(amount, 0.0, 1.0) if target != null else 0.0
	_one_hand = one_handed and target != null


## Where the ball will be when this swing meets it (world space), or null.
## Through the downswing the caman is steered so the bas goes through that
## point on the contact frame, rather than through wherever the canned swing
## happens to pass, so a hit always looks like it met the ball. After contact
## the point is held for the follow-through.
func set_meet(target) -> void:
	if _struck and _is_hit_action(_action):
		return
	_meet_target = target


## Seconds from starting `action` at `power` to the caman meeting the ball.
## `from_charge` is how much of the backswing was already held (release_swing).
## Match logic without a model (headless) uses this to time its hits.
static func contact_delay(action: String, power: float = 1.0, from_charge: float = 0.0) -> float:
	var l: float = ACTIONS.get(action, 0.78)
	if action == "swing" or action == "pass":
		l *= lerpf(0.75, 1.0, clampf(power, 0.0, 1.0))
	var times := _times_for(StringName(action), l)
	return times[1] - times[0] * clampf(from_charge, 0.0, 1.0)


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
	_meet_target = null
	_charging = false
	_carry_from = _carry
	_action_age = 0.0
	_carry_fade = _swing_times()[0] if _is_hit_action(action) else 0.15
	# Stumbles go the way the player was knocked; the hardest put them down.
	# `power` is how hard (0..1).
	_falling = false
	if action == &"stumble":
		var l := global_transform.basis.orthonormalized().inverse() * _jolt
		_stumble_dir = Vector2(l.x, l.z).normalized() if _jolt_age < 0.4 and l.length() > 0.2 else Vector2(0.0, 1.0)
		_sway_v += Vector3(_stumble_dir.y, 0.0, -_stumble_dir.x) * 2.0 * _action_power
		if _action_power >= FALL_AT:
			_falling = true
			_action_len = _action_power * 1.3 + 0.45


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
		_carry_fade = (_contact_time() - _action_t) * 0.8


## Hold the caman back while the hit button is held. Call release_swing() to hit.
func charge_swing() -> void:
	_charging = true
	_action = &""


func release_swing(power: float) -> void:
	var from_charge := _charge
	play_action(&"swing", power)
	# Skip the part of the backswing already done while charging.
	_action_t = _swing_times()[0] * from_charge
	_carry_fade = (_contact_time() - _action_t) * 0.8
	_charge = 0.0


## Let go of a held backswing without hitting.
func cancel_charge() -> void:
	_charging = false


func is_charging() -> bool:
	return _charging


func is_busy() -> bool:
	return _action != &"" or _charging


func current_action() -> StringName:
	return _action


## Turn the head towards a world point (usually the ball). Pass null to stop.
func look_at_point(target) -> void:
	_look_target = target


## A knock to the body, as a sudden change of velocity in world m/s: the trunk
## rocks with it and the head snaps after it. advance() notices knocks in the
## locomotion by itself; call this for anything it can't see.
func jolt(dv: Vector3) -> void:
	dv.y = 0.0
	_jolt = dv
	_jolt_age = 0.0
	var l := global_transform.basis.orthonormalized().inverse() * dv
	_sway_v += Vector3(l.z, 0.0, -l.x) * 1.8


## True while the player is down on the grass after a big hit.
func is_down() -> bool:
	return _rag != null and _rag_w > 0.5


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
	if delta > 0.0:
		var dv := _velocity - _prev_velocity
		var a := dv / delta
		_accel = _accel.lerp(a, clampf(delta * 8.0, 0.0, 1.0))
		_prev_velocity = _velocity
		# Legs can't change speed faster than this: anything more is a knock.
		var legs := 14.0 * delta
		if dv.length() > legs + 0.6:
			jolt(dv * (1.0 - legs / dv.length()))
		_body_springs(delta)
	_jolt_age += delta
	var reach_goal := _reach_want if _reach_target != null else 0.0
	_reach = move_toward(_reach, reach_goal, delta * (6.0 if reach_goal > _reach else 3.0))
	if auto_face and _speed > 0.3:
		var target_yaw := atan2(-_velocity.x, -_velocity.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * 10.0, 0.0, 1.0))
	var stride := lerpf(1.3, 3.4, clampf(_speed / 8.0, 0.0, 1.0)) * height_cm / 180.0
	_phase = fmod(_phase + delta * _speed / stride * TAU, TAU)
	# Running off the ball, the caman goes up on the shoulder in one hand.
	# Standing, reaching for the ball or doing anything with it, both hands.
	var carry_goal := 0.0
	if _action == &"" and not _charging and _charge <= 0.0:
		carry_goal = _ease((_speed - 0.4) / 0.8) * (1.0 - clampf(_reach * 5.0, 0.0, 1.0))
		# Closing on the ball, the second hand comes on, ready to strike.
		if _look_target is Vector3:
			var to_ball: Vector3 = (_look_target as Vector3) - global_position
			carry_goal *= _ease((Vector2(to_ball.x, to_ball.z).length() - 4.0) / 4.0)
	_carry = move_toward(_carry, carry_goal, delta * (2.5 if carry_goal > _carry else 6.0))
	if _charging:
		_charge = minf(1.0, _charge + delta / 0.35)
	elif _action == &"":
		_charge = maxf(0.0, _charge - delta * 4.0)
	if _action != &"":
		_action_t += delta
		_action_age += delta
		if not _struck and _is_hit_action(_action) and _action_t >= _contact_time():
			_struck = true
			_pose(0.0)
			strike.emit(get_caman_head_position(), _action_power)
		if _action_t >= _action_len:
			var done := _action
			_action = &""
			action_finished.emit(done)
	_update_ragdoll(delta)
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
		["Caman", "", Vector3.ZERO],  # posed from _caman each frame; carries the stick's mesh
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

	# Meshes, materials and the caman live in ShintyPlayerLook.
	_caman = ShintyPlayerLook.dress(self, _skel)
	_pose(0.0)
	_head_prev = get_caman_head_position()


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
	return a == &"swing" or a == &"pass" or a == &"volley" or a == &"shy"


## [backswing end, contact, follow-through end] as times in seconds.
func _swing_times() -> Array:
	return _times_for(_action, _action_len)


static func _times_for(action: StringName, l: float) -> Array:
	if action == &"volley":
		return [l * 0.3, l * 0.42, l * 0.65]
	if action == &"shy":
		return [l * 0.5, l * 0.66, l * 0.85]
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
	# Walking (off to the dugouts, lining up for a restart) is its own gait,
	# blending into the jog from about 1.6 m/s.
	var moving := clampf(_speed / 0.5, 0.0, 1.0)
	var gait := _ease((_speed - 1.6) / 1.4)   # 0 = walking, 1 = jogging or faster
	var ph := _phase
	var rot := {}       # bone name -> Vector3 euler
	var hips_off := Vector3.ZERO

	# Ready stance / idle breathing
	var idle := 1.0 - run
	# Blowing after a sprint: faster, deeper breaths, bent over a little.
	var breathe := sin(_time * lerpf(1.8, 3.6, _puff)) * lerpf(0.015, 0.045, _puff)
	# Shinty stance is upright, not an ice hockey crouch: a slight bend, head up.
	# Everyone stands a little differently. A jog stays fairly upright; the
	# faster they go the further forward they lean, like a sprinter, with the
	# head kept up to see the play.
	var pace := _ease((_speed - 2.5) / 5.5)
	rot["Spine"] = Vector3(-0.08 * idle - 0.1 * run - 0.35 * pace - 0.12 * _puff * idle + (_seed - 0.5) * 0.08, 0, 0)
	rot["Chest"] = Vector3(breathe - 0.12 * pace, 0, 0)
	rot["UpperChest"] = Vector3(-0.03 * idle, 0, 0)
	rot["Neck"] = Vector3(0.08 * idle + 0.1 * run + 0.45 * pace, 0, 0)
	rot["Head"] = Vector3(0.04, 0, 0)

	# Legs: a football run cycle blended with a slightly crouched stance.
	# The knee drives forward and up, the heel folds under the hip as the leg
	# swings through, the leg reaches out before the foot lands and gives a
	# little under the weight, then pushes off behind.
	var amp := lerpf(0.45, 0.85, sprint)
	var fold := lerpf(1.1, 2.0, sprint)
	for side in ["Left", "Right"]:
		var p := ph if side == "Left" else ph + PI
		var sgn := -1.0 if side == "Left" else 1.0
		var thigh_run := sin(p) * amp + amp * 0.3
		var swing_fold := pow(maxf(0.0, cos(p + 0.35)), 2.0)
		# The standing leg stays soft: it bends as it takes the weight.
		var knee_run := -(0.25 + 0.12 * pace + 0.55 * maxf(0.0, -cos(p)) + fold * swing_fold)
		var foot_run := -0.15 - 0.35 * maxf(0.0, -sin(p)) + 0.2 * swing_fold
		# Walking: the standing leg nearly straight, the heel lands first and
		# the knee only bends to swing the foot through.
		var walk_swing := pow(maxf(0.0, cos(p + 0.5)), 3.0)
		var thigh_walk := sin(p) * 0.32 + 0.06
		var knee_walk := -(0.06 + 0.08 * maxf(0.0, -cos(p)) + 0.75 * walk_swing)
		var foot_walk := -0.05 - 0.2 * maxf(0.0, -sin(p)) + 0.15 * walk_swing
		var thigh_idle := 0.12
		var knee_idle := -0.24
		rot[side + "UpperLeg"] = Vector3(lerpf(thigh_idle, lerpf(thigh_walk, thigh_run, gait), moving), 0, sgn * 0.05 * idle)
		rot[side + "LowerLeg"] = Vector3(lerpf(knee_idle, lerpf(knee_walk, knee_run, gait), moving), 0, 0)
		rot[side + "Foot"] = Vector3(lerpf(0.12, lerpf(foot_walk, foot_run, gait), moving), 0, 0)
	# A runner is lowest as the foot takes the weight; a walker is highest
	# over the standing leg and lowest with both feet down.
	hips_off.y = -lerpf(absf(sin(ph)) * 0.025, absf(cos(ph)) * 0.045, gait) * moving
	# Leaning into a sprint, the hips go with it: pushed a little forward and
	# tipped forward (the legs stay under), not left behind the shoulders.
	hips_off.z -= 0.06 * pace * run
	rot["Hips"] = Vector3(-0.1 * pace, sin(ph) * 0.12 * run, sin(ph) * 0.05 * moving * (1.0 - gait))
	rot["LeftUpperLeg"] += Vector3(0.1 * pace, 0, 0)
	rot["RightUpperLeg"] += Vector3(0.1 * pace, 0, 0)
	rot["Chest"] += Vector3(0, -sin(ph) * 0.1 * run, 0)

	# Football running: lean into acceleration, sit back when braking, bank
	# into turns, rock with knocks. The trunk is on a spring (_body_springs),
	# so it overshoots a little and settles, and the head lags behind it.
	var side_sign := -1.0 if left_handed else 1.0  # undone by the mirror below
	rot["Spine"] += Vector3(_sway.x, 0, _sway.z * side_sign)
	rot["Neck"] += Vector3(clampf(-_sway_v.x * 0.05, -0.35, 0.35), 0, clampf(-_sway_v.z * 0.05, -0.35, 0.35) * side_sign)
	# Turning, the head goes first and the shoulders follow.
	rot["Head"] += Vector3(0, clampf(_yaw_rate * 0.08, -0.35, 0.35) * side_sign, 0)
	rot["Chest"] += Vector3(0, -clampf(_yaw_rate * 0.04, -0.2, 0.2) * side_sign, 0)
	# Nobody stands still: the weight drifts from one foot to the other, the
	# free knee softens and the hips drop on that side.
	if _action == &"" and not _charging:
		var shift := sin(_time * 0.5 + _seed * TAU) * idle
		hips_off.x += 0.03 * shift * side_sign
		rot["Hips"] += Vector3(0, 0, 0.05 * shift)
		rot["Spine"] += Vector3(0, 0, -0.04 * shift)
		rot["LeftUpperLeg"] += Vector3(0.07 * maxf(0.0, shift), 0, 0)
		rot["LeftLowerLeg"] += Vector3(-0.14 * maxf(0.0, shift), 0, 0)
		rot["RightUpperLeg"] += Vector3(0.07 * maxf(0.0, -shift), 0, 0)
		rot["RightLowerLeg"] += Vector3(-0.14 * maxf(0.0, -shift), 0, 0)
	_free_hand = null
	_free_blend = 1.0

	# Caman carry pose (in hips-relative skeleton space, right-handed)
	# Two hands low across the thighs, the head held just off the grass out in
	# front (a hockey player would have it flat on the ice).
	# The hands (and the stick) go forward with the lean.
	var lean_fwd := Vector3(0.0, 0.04, -0.14) * pace
	var cam_p := _lerp3(READY_P, Vector3(0.18, 0.02, -0.24), run) + lean_fwd
	var cam_d := _lerp3(READY_D, Vector3(-0.25, -0.5, -0.83), run).normalized()
	cam_p.y += sin(ph * 2.0) * 0.025 * run
	var twist := 0.0

	if _charging or _charge > 0.0:
		var k := _ease(_charge)
		var bp := _backswing(1.0)
		cam_p = cam_p.lerp(bp[0], k)
		cam_d = cam_d.slerp(bp[1], k)
		twist = -1.2 * k
		_crouch(rot, 0.4 * k)

	if _action != &"":
		var r := _action_pose(rot)
		if r.size() > 0:
			cam_p = r[0]
			cam_d = r[1]
			twist = r[2]
			hips_off += r[3]

	# Reaching: bend and lunge towards the target (hockey-style reach).
	var reaching := _reach > 0.01 and _reach_target != null and (_action == &"" or _action in [&"poke", &"block", &"trap", &"air_kill", &"air_clear"])
	if reaching:
		var loc: Vector3 = global_transform.affine_inverse() * (_reach_target as Vector3)
		var flat := Vector2(loc.x, loc.z).length()
		var lean := clampf((flat - 0.5) / 1.1, 0.0, 1.0) * _reach
		var low := clampf((0.6 - loc.y) / 0.6, 0.0, 1.0)
		var high := clampf((loc.y - 1.6) / 0.8, 0.0, 1.0) * _reach
		rot["Spine"] += Vector3(-0.45 * lean * (0.4 + 0.6 * low) + 0.25 * high, 0,
			-clampf(loc.x / 1.2, -1.0, 1.0) * 0.35 * lean * side_sign)
		_crouch(rot, 0.6 * lean * low)
		# Lunge: the leg on the reaching side strides out.
		var lead := "Left" if (loc.x < 0.0) != left_handed else "Right"
		rot[lead + "UpperLeg"] += Vector3(0.55 * lean, 0, 0)
		rot[lead + "LowerLeg"] += Vector3(-0.35 * lean, 0, 0)
		twist += clampf(-loc.x * 0.4, -0.5, 0.5) * lean * side_sign

	# Torso twist through the swing
	rot["Spine"] += Vector3(0, twist * 0.35, 0)
	rot["Chest"] += Vector3(0, twist * 0.35, 0)
	rot["UpperChest"] += Vector3(0, twist * 0.3, 0)

	# Look at the ball
	if _look_target != null and _look_target is Vector3:
		var local: Vector3 = global_transform.affine_inverse() * (_look_target as Vector3)
		var yaw := clampf(atan2(-local.x, -local.z) - twist, -1.1, 1.1)
		var pitch := clampf(atan2(local.y - 1.6, Vector2(local.x, local.z).length()), -0.6, 0.4)
		rot["Neck"] += Vector3(pitch * 0.4, yaw * 0.45, 0)
		rot["Head"] += Vector3(pitch * 0.6, yaw * 0.55, 0)

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
	# twist and rot are already mirrored for left-handers, so this turns the
	# caman with the torso either way.
	var yaw_b := Basis(Vector3.UP, twist * 0.5 + rot["Hips"].y)
	var p_sk: Vector3 = hips_g.origin + yaw_b * cam_p
	var d_sk: Vector3 = (yaw_b * cam_d).normalized()
	# A shy is struck with the back of the bas, so the face is turned round.
	# So is a block: the stick is turned so its back sits over the ball.
	# So is a clearance out of the air, swatted away like a shy.
	var back_face := _action == &"shy" or _action == &"block" or _action == &"air_clear"
	var face_dir := Vector3(0.0, 0.3, 1.0) if back_face else Vector3(0.0, -0.3, -1.0)
	if _action == &"block":
		face_dir = Vector3(0.0, -1.0, 0.2)   # hook turned down over the ball
	elif _action == &"air_kill":
		# A ball out of the air: the caman held up sideways, the curve of the
		# bas turned down, so its face knocks the ball down onto the grass.
		face_dir = Vector3(0.0, -1.0, -0.25)
	# The hook of the bas faces up, as a shinty player carries it, except for
	# a block and through a hit, where the face turns to meet the ball.
	var up := 0.0 if back_face or _action == &"air_kill" else _hook_up()
	var face_w: Vector3 = yaw_b * face_dir + Vector3.UP * 2.0 * up
	var cb := _caman_basis(d_sk, face_w)
	var ct := Transform3D(cb, p_sk)
	var top_side := "Right" if left_handed else "Left"
	var low_side := "Left" if left_handed else "Right"
	_free_low = null
	if reaching:
		# Point the caman from the hands to the target, head on the target.
		var tgt: Vector3 = _skel.global_transform.affine_inverse() * (_reach_target as Vector3)
		var head_len := HEAD_LOCAL.length()
		if _one_hand:
			# Top hand at the very end of the handle, arm straight at the target.
			var sh := _shoulder(top_side)
			var to_t := tgt - sh
			var arm := _arm_reach(top_side) * 0.97
			var butt := sh + to_t.normalized() * minf(arm, maxf(0.1, to_t.length() - head_len * 0.5))
			var dn := (tgt - butt).normalized()
			var rt := Transform3D(_caman_basis(dn, yaw_b * Vector3(0.0, -0.3, -1.0) + Vector3.UP * 2.0 * up), butt - dn * GRIP_TOP)
			ct = ct.interpolate_with(rt, _reach)
			# The free arm swings out the other way for balance.
			var out := -1.0 if top_side == "Right" else 1.0
			_free_low = hips_g.origin + yaw_b * Vector3(out * 0.5, 0.35, 0.15)
		else:
			var anchor := hips_g.origin + yaw_b * Vector3(0.05, 0.3, -0.25)
			var rd := tgt - anchor
			if rd.length() > 0.05:
				var dn := rd.normalized()
				var rf: Vector3 = face_w if reach_face == null else _skel.global_transform.basis.inverse() * (reach_face as Vector3)
				var rt := Transform3D(_caman_basis(dn, rf), tgt - dn * head_len)
				ct = ct.interpolate_with(rt, _reach)
	# A hit: steer the bas through the ball (set_meet), most strongly at contact.
	if _meet_target != null and _is_hit_action(_action) and _action != &"shy":
		var tm := _swing_times()
		var mw := 0.0
		if _action_t <= tm[1]:
			mw = _ease((_action_t - tm[0]) / maxf(0.01, tm[1] - tm[0]))
		else:
			mw = 1.0 - _ease((_action_t - tm[1]) / maxf(0.01, (tm[2] - tm[1]) * 0.6))
		if mw > 0.0:
			var mt: Vector3 = _skel.global_transform.affine_inverse() * (_meet_target as Vector3)
			ct.origin += (mt - ct * HEAD_LOCAL).limit_length(MEET_MAX) * mw
	# Running off the ball the caman is carried in the lower hand, low and
	# across the front of the body with the head out in front just off the
	# grass (as at The Dell), and the top hand is free to pump like a
	# runner's. When a swing starts the top hand joins the stick by the top of
	# the backswing, so the hit itself is always two-handed.
	var carry := _carry
	if _action != &"":
		carry = _carry_from * (1.0 - _ease(_action_age / maxf(0.01, _carry_fade)))
	var carry_top = null
	if carry > 0.001:
		var mx := -1.0 if left_handed else 1.0
		var pump := sin(ph) * run   # > 0: front (left) leg forward
		var bob := absf(cos(ph)) * 0.03 * run
		var hand := Vector3(0.2 * mx, 0.04 + bob, -0.16 - 0.05 * pump) + lean_fwd
		var cd := Vector3(-0.55 * mx, -0.45 + 0.05 * pump, -0.7).normalized()
		var face_c := Vector3(0.0, 1.0, -0.3)
		# Walking, the caman hangs relaxed in the hand by the side, head
		# forward near the grass, swinging a little with the stride; the free
		# arm hangs and swings the other way.
		var walk_k := 1.0 - gait
		var swing_w := sin(ph) * moving
		hand = hand.lerp(Vector3(0.22 * mx, -0.1, -0.04 - 0.1 * swing_w), walk_k)
		cd = cd.lerp(Vector3(-0.12 * mx, -0.8, -0.58), walk_k).normalized()
		if shoulder_carry:
			# Up by the shoulder: hand at the chest, the caman standing up
			# past the shoulder and a little back, the bas curling back.
			hand = Vector3(0.2 * mx, 0.24 + bob, -0.2 - 0.05 * pump) + lean_fwd
			cd = Vector3(0.22 * mx, 0.9, 0.34 + 0.05 * pump).normalized()
			face_c = Vector3(0.0, 0.3, 1.0)
		var d_c: Vector3 = yaw_b * cd
		var grip_c: Vector3 = hips_g.origin + yaw_b * hand
		var carry_t := Transform3D(_caman_basis(d_c, yaw_b * face_c), grip_c - d_c * GRIP_LOW)
		ct = ct.interpolate_with(carry_t, carry)
		var top_run := Vector3(-0.17 * mx, 0.24 - 0.08 * pump + bob, -0.16 + 0.22 * pump) + lean_fwd * 1.3
		var top_walk := Vector3(-0.23 * mx, -0.14, 0.02 + 0.14 * swing_w)
		carry_top = hips_g.origin + yaw_b * top_run.lerp(top_walk, walk_k)
	# Keep both grips within arm's reach: slide the caman towards the shoulders.
	for iter in 3:
		var grips := [[top_side, GRIP_TOP], [low_side, GRIP_LOW]]
		if _free_hand != null or carry > 0.5:
			grips = [[low_side, GRIP_LOW]]
		elif _free_low != null:
			grips = [[top_side, GRIP_TOP]]
		for g in grips:
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
	var caman_bone: int = _bone["Caman"]
	_skel.set_bone_pose_position(caman_bone, ct.origin)
	_skel.set_bone_pose_rotation(caman_bone, ct.basis.get_rotation_quaternion())
	_skel.set_bone_pose_scale(caman_bone, Vector3.ONE if _caman.visible else Vector3.ZERO)

	# Both hands grip the shaft: top hand near the butt, lower hand further down.
	var top := ct * Vector3(0, -GRIP_TOP, 0)
	var low := ct * Vector3(0, -GRIP_LOW, 0)
	var free_target = null
	if _free_hand != null:
		var fh: Vector3 = _free_hand
		if left_handed:
			fh.x = -fh.x
		free_target = hips_g.origin + yaw_b * fh
		free_target = top.lerp(free_target, _free_blend)
	if free_target == null and carry_top != null:
		free_target = top.lerp(carry_top, carry)
	# A runner's free arm swings with the elbow tucked down and back.
	_solve_arm(top_side, free_target if free_target != null else top, carry if carry_top != null else 0.0)
	_solve_arm(low_side, _free_low if _free_low != null else low, carry if carry_top != null else 0.0)
	if _rag != null and _rag_w > 0.0:
		_apply_ragdoll()


## Returns [caman position, caman direction, twist, hips offset] for the
## current action, or [] for none. May also adjust `rot` (legs, torso).
func _action_pose(rot: Dictionary) -> Array:
	var t := _action_t
	var hips_off := Vector3.ZERO
	var ready_p := READY_P
	var ready_d := READY_D.normalized()
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
			# Like a golf swing: the shoulders turn well back, the hips
			# half as far, and the weight goes onto the back foot; the
			# hands lead the head down (wrists cocked, then released into
			# the ball) as the weight comes onto the front foot; the finish
			# is high over the front shoulder with the chest to the target.
			var top_twist := -0.9 * size - 0.3 * _big(size)
			var fin_twist := 0.85 * size
			var shift := 0.0     # hips: + over the back foot, - the front
			if t < t0:
				var k := _ease(t / t0)
				p = ready_p.lerp(back[0], k)
				d = ready_d.slerp(back[1], k)
				twist = top_twist * k
				shift = k
				_crouch(rot, 0.75 * k)
			elif t < t1:
				var k := (t - t0) / (t1 - t0)
				k = k * k  # accelerate into the ball
				p = back[0].lerp(contact[0], minf(1.0, k * 1.25))
				d = back[1].slerp(contact[1], pow(k, 1.5))  # the head lags the hands
				twist = lerpf(top_twist, 0.1, k)
				shift = 1.0 - 1.6 * k
				_crouch(rot, 0.75)
				rot["Spine"] += Vector3(-0.3 * k, 0, 0)  # down to the ball
				_step(rot, k)
			elif t < t2:
				var k := _ease_out((t - t1) / (t2 - t1))
				p = contact[0].lerp(follow[0], k)
				d = contact[1].slerp(follow[1], k)
				twist = lerpf(0.1, fin_twist, k)
				shift = -0.6 - 0.4 * k
				_crouch(rot, 0.75 * (1.0 - k * 0.5))
				rot["Spine"] += Vector3(-0.3 * (1.0 - k), 0, 0)
				_step(rot, 1.0)
			else:
				var k := _ease((t - t2) / maxf(0.01, _action_len - t2))
				p = follow[0].lerp(ready_p, k)
				d = follow[1].slerp(ready_d, k)
				twist = lerpf(fin_twist, 0.0, k)
				shift = -(1.0 - k)
				_step(rot, 1.0 - k)
			rot["Hips"] += Vector3(0, twist * 0.3, 0)
			hips_off += Vector3(0.03, 0.0, 0.05) * shift * size
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
		&"feet_trap":
			# The ball stopped with the feet: planted and together, knees
			# bent and the body over the ball, the caman lifted out of the
			# way until it's dead.
			var u := clampf(t / _action_len, 0.0, 1.0)
			var k := sin(minf(1.0, u * 3.0) * PI * 0.5) * (1.0 - _ease(maxf(0.0, (u - 0.6) / 0.4)))
			_crouch(rot, 0.45 * k)
			for side in ["Left", "Right"]:
				var sgn := -1.0 if side == "Left" else 1.0
				rot[side + "UpperLeg"] = rot[side + "UpperLeg"].lerp(Vector3(0.2, 0, -sgn * 0.08), k)
				rot[side + "LowerLeg"] = rot[side + "LowerLeg"].lerp(Vector3(-0.45, 0, 0), k)
				rot[side + "Foot"] = rot[side + "Foot"].lerp(Vector3(0.25, 0, 0), k)
			rot["Spine"] += Vector3(-0.3 * k, 0, 0)
			rot["Neck"] += Vector3(-0.35 * k, 0, 0)   # eyes on the ball at the feet
			# A little jump to get the feet in line first: up off the grass,
			# knees tucked, and down together onto the ball.
			var jump := sin(clampf(u / 0.24, 0.0, 1.0) * PI)
			hips_off.y += 0.11 * jump
			for side in ["Left", "Right"]:
				rot[side + "LowerLeg"] += Vector3(-0.5 * jump, 0, 0)
				rot[side + "UpperLeg"] += Vector3(0.3 * jump, 0, 0)
			var p5 := ready_p.lerp(Vector3(0.3, 0.2, -0.1), k)
			var d5 := ready_d.slerp(Vector3(0.6, -0.5, -0.62).normalized(), k)
			return [p5, d5, 0.0, hips_off]
		&"thigh_trap":
			# A ball at knee to waist height: the right thigh comes up to
			# meet it and gives with it, so it drops dead in front; the caman
			# held out of the way to the side.
			var u := clampf(t / _action_len, 0.0, 1.0)
			var k := sin(minf(1.0, u * 3.0) * PI * 0.5) * (1.0 - _ease(maxf(0.0, (u - 0.55) / 0.45)))
			var give := sin(clampf((u - 0.25) / 0.3, 0.0, 1.0) * PI) * 0.25
			rot["RightUpperLeg"] = rot["RightUpperLeg"].lerp(Vector3(1.35 - give, 0, 0.05), k)
			rot["RightLowerLeg"] = rot["RightLowerLeg"].lerp(Vector3(-1.5, 0, 0), k)
			rot["RightFoot"] = rot["RightFoot"].lerp(Vector3(0.3, 0, 0), k)
			rot["LeftUpperLeg"] = rot["LeftUpperLeg"].lerp(Vector3(0.1, 0, 0), k)
			rot["LeftLowerLeg"] = rot["LeftLowerLeg"].lerp(Vector3(-0.25, 0, 0), k)
			rot["Spine"] += Vector3(-0.15 * k, 0, 0)
			rot["Neck"] += Vector3(-0.3 * k, 0, 0)
			var p9 := ready_p.lerp(Vector3(0.38, 0.3, 0.0), k)
			var d9 := ready_d.slerp(Vector3(0.7, -0.6, -0.3).normalized(), k)
			return [p9, d9, 0.0, hips_off]
		&"chest_trap":
			# A ball in the air taken on the chest: lean back and puff the
			# chest out to meet it, then give with it so it drops at the feet;
			# the caman held out wide and low, out of the way.
			var u := clampf(t / _action_len, 0.0, 1.0)
			var k := sin(minf(1.0, u * 3.0) * PI * 0.5) * (1.0 - _ease(maxf(0.0, (u - 0.55) / 0.45)))
			var give := sin(clampf((u - 0.25) / 0.3, 0.0, 1.0) * PI)
			_crouch(rot, 0.25 * k)
			rot["Spine"] += Vector3((0.45 + 0.15 * give) * k, 0, 0)   # lean back into it
			rot["Chest"] += Vector3((0.2 - 0.3 * give) * k, 0, 0)       # chest out, then cushion
			rot["Neck"] += Vector3(-0.4 * k, 0, 0)   # chin down, watching it onto the chest
			hips_off.z = 0.08 * k
			var p10 := ready_p.lerp(Vector3(0.45, 0.25, 0.05), k)
			var d10 := ready_d.slerp(Vector3(0.75, -0.55, -0.1).normalized(), k)
			return [p10, d10, 0.0, hips_off]
		&"pencil":
			# A ball at knee to waist height taken on the legs: a little hop,
			# then feet together and legs straight like a pencil, leaning over
			# it so it comes off the shins and thighs and drops in front; the
			# caman held out to the side, out of the way.
			var u := clampf(t / _action_len, 0.0, 1.0)
			var k := sin(minf(1.0, u * 3.0) * PI * 0.5) * (1.0 - _ease(maxf(0.0, (u - 0.6) / 0.4)))
			var hop := sin(clampf(u / 0.3, 0.0, 1.0) * PI)
			hips_off.y += 0.09 * hop
			for side in ["Left", "Right"]:
				var sgn := -1.0 if side == "Left" else 1.0
				rot[side + "UpperLeg"] = rot[side + "UpperLeg"].lerp(Vector3(0.12, 0, sgn * 0.06), k)
				rot[side + "LowerLeg"] = rot[side + "LowerLeg"].lerp(Vector3(-0.08, 0, 0), k)
				rot[side + "Foot"] = rot[side + "Foot"].lerp(Vector3(0.15, 0, 0), k)
			rot["Spine"] += Vector3(-0.35 * k, 0, 0)
			rot["Neck"] += Vector3(-0.35 * k, 0, 0)
			var p11 := ready_p.lerp(Vector3(0.4, 0.3, 0.0), k)
			var d11 := ready_d.slerp(Vector3(0.75, -0.55, -0.3).normalized(), k)
			return [p11, d11, 0.0, hips_off]
		&"air_kill":
			# Up on the toes under it, reaching up; set_reach() takes the bas
			# to the ball with the curve turned down.
			var k := sin(clampf(t / _action_len, 0.0, 1.0) * PI)
			rot["Spine"] += Vector3(0.12 * k, 0, 0)
			hips_off.y += 0.04 * k
			return [ready_p, ready_d, 0.0, hips_off]
		&"air_clear":
			# Swatting it away out of the air with the back of the stick:
			# shoulders turn into it as the stick comes through.
			var k := sin(clampf(t / _action_len, 0.0, 1.0) * PI)
			var u := clampf(t / _action_len, 0.0, 1.0)
			rot["Spine"] += Vector3(0.1 * k, 0, 0)
			return [ready_p, ready_d, lerpf(-0.6, 0.5, _ease(u)) * k, hips_off]
		&"save_feet":
			# Keeper: feet together and planted, knees bent, the caman blade
			# down in front of the feet so nothing goes through the legs.
			var u := clampf(t / _action_len, 0.0, 1.0)
			var k := sin(minf(1.0, u * 3.0) * PI * 0.5) * (1.0 - _ease(maxf(0.0, (u - 0.7) / 0.3)))
			_crouch(rot, 0.5 * k)
			for side in ["Left", "Right"]:
				var sgn := -1.0 if side == "Left" else 1.0
				rot[side + "UpperLeg"] = rot[side + "UpperLeg"].lerp(Vector3(0.2, 0, -sgn * 0.06), k)
				rot[side + "LowerLeg"] = rot[side + "LowerLeg"].lerp(Vector3(-0.45, 0, 0), k)
				rot[side + "Foot"] = rot[side + "Foot"].lerp(Vector3(0.25, 0, 0), k)
			rot["Spine"] += Vector3(-0.3 * k, 0, 0)
			var p7 := ready_p.lerp(Vector3(0.0, 0.0, -0.3), k)
			var d7 := ready_d.slerp(Vector3(0.0, -0.96, -0.28).normalized(), k)
			return [p7, d7, 0.0, hips_off]
		&"save_high_left", &"save_high_right":
			# Keeper: a high shot turned away with the caman, arms up and the
			# stick raised to the side of the head.
			var side := -1.0 if _action == &"save_high_left" else 1.0
			var u := clampf(t / _action_len, 0.0, 1.0)
			var k := sin(minf(1.0, u * 3.0) * PI * 0.5) * (1.0 - _ease(maxf(0.0, (u - 0.6) / 0.4)))
			rot["Spine"] += Vector3(0.1 * k, 0, -side * 0.25 * k)
			rot["Chest"] += Vector3(0.05 * k, 0, -side * 0.15 * k)
			hips_off.x = side * 0.12 * k
			var p8 := ready_p.lerp(Vector3(side * 0.25, 0.7, -0.25), k)
			var d8 := ready_d.slerp(Vector3(side * 0.55, 0.8, -0.25).normalized(), k)
			return [p8, d8, 0.0, hips_off]
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
		&"shy":
			# Side-on at the line: toss the ball up with the top hand while the
			# lower hand holds the caman down at the side, then both hands take
			# it up behind the head and over the top like a hammer.
			var u := clampf(t / _action_len, 0.0, 1.0)
			var toss_p := Vector3(0.25, -0.05, -0.05)
			var toss_d := Vector3(0.2, -0.9, 0.35).normalized()
			var wind_p := Vector3(0.1, 0.75, 0.05)
			var wind_d := Vector3(0.0, -0.5, 0.87).normalized()
			var hit_p := Vector3(0.08, 0.6, -0.3)
			var hit_d := Vector3(0.05, 0.75, -0.66).normalized()
			var fol_p := Vector3(0.0, 0.15, -0.4)
			var fol_d := Vector3(-0.1, -0.5, -0.86).normalized()
			var p6: Vector3
			var d6: Vector3
			var tw: float
			if u < 0.3:
				var k := _ease(u / 0.3)
				p6 = ready_p.lerp(toss_p, minf(1.0, k * 2.0))
				d6 = ready_d.slerp(toss_d, minf(1.0, k * 2.0))
				tw = -0.6 * k
				# The free hand throws the ball up.
				_free_hand = Vector3(-0.15, 0.1, -0.3).lerp(Vector3(-0.08, 0.95, -0.35), _ease_out(k))
			elif u < 0.5:
				var k := _ease((u - 0.3) / 0.2)
				p6 = toss_p.lerp(wind_p, k)
				d6 = toss_d.slerp(wind_d, k)
				tw = -0.6
				rot["Spine"] += Vector3(0.18 * k, 0, 0)  # arch back
			elif u < 0.66:
				var k := (u - 0.5) / 0.16
				k = k * k  # accelerate over the top
				p6 = wind_p.lerp(hit_p, k)
				d6 = wind_d.slerp(hit_d, k)
				tw = lerpf(-0.6, 0.0, k)
				rot["Spine"] += Vector3(0.18 * (1.0 - k), 0, 0)
				_step(rot, k)
			elif u < 0.85:
				var k := _ease_out((u - 0.66) / 0.19)
				p6 = hit_p.lerp(fol_p, k)
				d6 = hit_d.slerp(fol_d, k)
				tw = lerpf(0.0, 0.3, k)
				rot["Spine"] += Vector3(-0.3 * k, 0, 0)  # fold over the follow-through
				_step(rot, 1.0)
			else:
				var k := _ease((u - 0.85) / 0.15)
				p6 = fol_p.lerp(ready_p, k)
				d6 = fol_d.slerp(ready_d, k)
				tw = lerpf(0.3, 0.0, k)
				rot["Spine"] += Vector3(-0.3 * (1.0 - k), 0, 0)
				_step(rot, 1.0 - k)
			return [p6, d6, tw, hips_off]
		&"stumble":
			if _falling:
				# Down on the grass (the ragdoll has the body): getting back up
				# is a crouch that straightens as the ragdoll lets go.
				var g := _ease((t - (_action_len - GET_UP)) / GET_UP)
				_crouch(rot, 0.9 * (1.0 - g))
				rot["Spine"] += Vector3(-0.45 * (1.0 - g), 0, 0)
				return [ready_p, ready_d, 0.0, hips_off]
			# Knocked off balance the way the hit went: the trunk goes with it,
			# a quick step to catch the weight, arms out, caman flung wide.
			var u := clampf(t / _action_len, 0.0, 1.0)
			var k := sin(u * PI)
			var sev := lerpf(0.5, 1.0, _action_power)
			var sd := _stumble_dir
			if left_handed:
				sd.x = -sd.x   # rot is mirrored below
			rot["Spine"] += Vector3(0.35 * sd.y, 0, -0.3 * sd.x) * k * sev
			rot["Neck"] += Vector3(-0.2 * sd.y, 0, 0.15 * sd.x) * k
			_crouch(rot, 0.35 * k * sev)
			var st := sin(minf(1.0, u * 2.2) * PI) * sev
			var leg := "Right" if sd.x > 0.0 else "Left"
			rot[leg + "UpperLeg"] += Vector3(-0.55 * sd.y * st, 0, 0.3 * sd.x * st)
			rot[leg + "LowerLeg"] += Vector3(-0.35 * st, 0, 0)
			hips_off += Vector3(_stumble_dir.x, -0.6, _stumble_dir.y) * 0.08 * k * sev
			_free_hand = Vector3(-0.5, 0.5, 0.05 + 0.2 * sd.y)
			_free_blend = k
			var p7 := ready_p.lerp(Vector3(0.3, 0.2, -0.05 - 0.1 * sd.y), k)
			var d7 := ready_d.slerp(Vector3(0.6, 0.25, -0.75).normalized(), k)
			return [p7, d7, 0.25 * k, hips_off]
		&"poke":
			# Hockey poke check: lunge on the front leg; set_reach() drives the caman.
			var k := sin(clampf(t / _action_len, 0.0, 1.0) * PI)
			rot["Spine"] += Vector3(-0.35 * k, 0, 0)
			rot["LeftUpperLeg"] += Vector3(0.7 * k, 0, 0)
			rot["LeftLowerLeg"] += Vector3(-0.5 * k, 0, 0)
			rot["RightUpperLeg"] += Vector3(-0.35 * k, 0, 0)
			return []
		&"block":
			# Get low behind the stick; set_reach() puts its back over the ball.
			var k := sin(minf(1.0, t / (_action_len * 0.3)) * PI * 0.5)
			_crouch(rot, 0.8 * k)
			rot["Spine"] += Vector3(-0.25 * k, 0, 0)
			return []
		&"cleek":
			# Caman up at an angle in front, under the arc of the other swing.
			var u := clampf(t / _action_len, 0.0, 1.0)
			var k := sin(minf(1.0, u * 2.5) * PI * 0.5) * (1.0 - _ease(maxf(0.0, (u - 0.75) / 0.25)))
			_crouch(rot, 0.3 * k)
			var p8 := ready_p.lerp(Vector3(0.1, 0.3, -0.35), k)
			var d8 := ready_d.slerp(Vector3(-0.35, 0.8, -0.5).normalized(), k)
			return [p8, d8, 0.15 * k, hips_off]
		&"barge":
			# Shoulder first: drop and turn the shoulder into them.
			var k := sin(clampf(t / _action_len, 0.0, 1.0) * PI)
			_crouch(rot, 0.35 * k)
			rot["Spine"] += Vector3(-0.2 * k, 0, 0.25 * k)
			rot["Chest"] += Vector3(0, 0.35 * k, 0)
			return [ready_p, ready_d, -0.3 * k, hips_off]
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
	# Top: hands together up by the back shoulder, the caman nearly upright
	# above the head.
	var p := Vector3(0.14, -0.08, -0.26).lerp(Vector3(0.28, 0.5, 0.0), size)
	var d := Vector3(0.25, -0.85, -0.45).normalized().slerp(Vector3(0.08, 0.9, 0.42).normalized(), size)
	# A big hit is wound right up: hands high by the back shoulder and the
	# caman raised up and back over it.
	var big := _big(size)
	p = p.lerp(Vector3(0.24, 0.64, 0.06), big)
	d = d.slerp(Vector3(0.06, 0.8, 0.6).normalized(), big)
	return [p, d]


## How much of the extra wind-up a swing of this size gets (big hits only).
static func _big(size: float) -> float:
	return _ease((size - 0.7) / 0.3)


func _contact(h: float) -> Array:
	var k := clampf(h / 1.4, 0.0, 1.0)
	var p := Vector3(0.1, -0.25, -0.22).lerp(Vector3(0.12, 0.3, -0.3), k)
	var d := Vector3(0.18, -0.93, -0.32).normalized().slerp(Vector3(0.75, -0.05, -0.66).normalized(), k)
	return [p, d]


func _follow(size: float, h: float) -> Array:
	var k := clampf(h / 1.4, 0.0, 1.0)
	var p := Vector3(-0.05, -0.05, -0.3).lerp(Vector3(-0.2, 0.45, -0.2), size)
	var d := Vector3(-0.2, -0.75, -0.63).normalized().slerp(Vector3(-0.45, 0.85, -0.05).normalized(), size)
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


## 1 = turn the hook up; 0 = leave the face square to the ball. A hit turns
## it square over the backswing and back up after the follow-through.
func _hook_up() -> float:
	if not _is_hit_action(_action):
		return 1.0
	var times := _swing_times()
	if _action_t < times[1]:
		return 1.0 - _ease(_action_t / maxf(0.01, times[0]))
	return _ease((_action_t - times[2]) / maxf(0.01, _action_len - times[2]))


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
## `tuck` 0..1 brings the elbow in to the side (a runner's arm) instead of out.
func _solve_arm(side: String, target: Vector3, tuck: float = 0.0) -> void:
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
	var pole := parent_g.basis * Vector3(sgn * lerpf(0.8, 0.2, tuck), -1.0, lerpf(0.35, 0.8, tuck))
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


# --- Body physics ------------------------------------------------------------

## The trunk rides on a spring towards the lean that acceleration asks for, so
## it overshoots and settles like a body instead of snapping; knocks kick it.
func _body_springs(delta: float) -> void:
	var inv := global_transform.basis.orthonormalized().inverse()
	var acc_l := inv * _accel
	var goal := Vector3(-clampf(-acc_l.z * 0.035, -0.18, 0.28), 0.0, -clampf(acc_l.x * 0.03, -0.22, 0.22))
	var left := delta
	while left > 0.0:
		var h := minf(left, 1.0 / 60.0)
		left -= h
		var w := 9.0
		_sway_v += (goal - _sway) * w * w * h - _sway_v * 2.0 * 0.4 * w * h
		_sway += _sway_v * h
	_sway = _sway.clamp(Vector3(-0.7, 0.0, -0.7), Vector3(0.7, 0.0, 0.7))
	var yaw := global_transform.basis.orthonormalized().get_euler().y
	if _yaw_prev != null:
		var rate := wrapf(yaw - float(_yaw_prev), -PI, PI) / delta
		_yaw_rate = lerpf(_yaw_rate, rate, clampf(delta * 10.0, 0.0, 1.0))
	_yaw_prev = yaw
	var sprinting := _speed > 5.5
	_puff = move_toward(_puff, 1.0 if sprinting else 0.0, delta * (0.12 if sprinting else 0.04))


## Knocked down: hand the body to a ragdoll, then take it back to get up.
func _update_ragdoll(delta: float) -> void:
	if _falling and _action == &"stumble" and _rag == null and _action_t >= 0.08:
		_start_ragdoll()
	if _rag == null:
		return
	# The body goes where the match moves the player, falling as it goes, so
	# getting up never slides them back across the grass.
	var moved := global_position - _rag_origin
	_rag.shift(Vector3(moved.x, 0.0, moved.z))
	_rag_origin = global_position
	_rag.step(delta)
	if _falling and _action == &"stumble":
		var up_at := _action_len - GET_UP
		if _action_t < up_at:
			_rag_w = minf(1.0, _rag.age / 0.1)
		else:
			# Getting up is done by the body itself: the muscles pull each
			# joint towards the standing pose, harder and harder, and the
			# animation only takes over for the last bit.
			var u := (_action_t - up_at) / GET_UP
			_rag.pull_strength = 0.03 + 0.25 * u
			_rag_w = 1.0 - _ease((u - 0.65) / 0.35)
	else:
		# Something else came up (or the get-up finished): let go quickly.
		_rag_w = move_toward(_rag_w, 0.0, delta / 0.3)
	if _rag_w <= 0.0 and (_action != &"stumble" or not _falling or _action_t >= _action_len - GET_UP):
		_rag = null
		_rag_w = 0.0
		_set_cull_margin(0.0)


func _start_ragdoll() -> void:
	var j := _joints()
	_rag_face = -_caman.global_transform.basis.z
	# Knocked the way the hit went; without one, backwards off the challenge.
	var dir := Vector3(_jolt.x, 0.0, _jolt.z)
	if _jolt_age > 0.6 or dir.length() < 0.2:
		dir = global_transform.basis * Vector3(_stumble_dir.x, 0.0, _stumble_dir.y)
	var push := dir.normalized() * lerpf(2.2, 3.6, _action_power)
	# The match carries the body along at the player's speed (see
	# _update_ragdoll), so only the knock itself goes in here.
	var R := ShintyRagdoll
	_rag = ShintyRagdoll.new(j, Vector3.ZERO, push, R.L_WR if left_handed else R.R_WR)
	_rag_origin = global_position
	_rag.ground = global_position.y
	_rag_w = 0.0
	# Lying down, the body reaches well outside where it stands.
	_set_cull_margin(2.0)


## World positions of the ragdoll's joints in the skeleton's current pose.
func _joints() -> PackedVector3Array:
	var R := ShintyRagdoll
	var j := PackedVector3Array()
	j.resize(R.COUNT)
	var names := {R.PELVIS: "Hips", R.CHEST: "UpperChest",
		R.L_SH: "LeftUpperArm", R.L_EL: "LeftLowerArm", R.L_WR: "LeftHand",
		R.R_SH: "RightUpperArm", R.R_EL: "RightLowerArm", R.R_WR: "RightHand",
		R.L_HIP: "LeftUpperLeg", R.L_KNEE: "LeftLowerLeg", R.L_ANK: "LeftFoot",
		R.R_HIP: "RightUpperLeg", R.R_KNEE: "RightLowerLeg", R.R_ANK: "RightFoot"}
	var sk := _skel.global_transform
	for i in names:
		j[i] = sk * _skel.get_bone_global_pose(_bone[names[i]]).origin
	j[R.HEAD] = sk * (_skel.get_bone_global_pose(_bone["Head"]) * Vector3(0, 0.12, 0))
	j[R.BUTT] = _caman.global_transform.origin
	j[R.TIP] = get_caman_head_position()
	return j


func _set_cull_margin(m: float) -> void:
	for c in _skel.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).extra_cull_margin = m


## Turn the ragdoll's joints into bone rotations and blend them over the
## animated pose by _rag_w.
func _apply_ragdoll() -> void:
	var R := ShintyRagdoll
	# The pose the animation wants (the skeleton holds it until we blend below):
	# what the muscles pull towards when getting up.
	_rag.targets = _joints()
	var inv := _skel.global_transform.affine_inverse()
	var P := PackedVector3Array()
	P.resize(R.COUNT)
	for i in R.COUNT:
		P[i] = inv * _rag.pos[i]
	var local := {}
	var spine := P[R.CHEST] - P[R.PELVIS]
	var bh := _frame(P[R.R_HIP] - P[R.L_HIP], spine)
	var bc := _frame(P[R.R_SH] - P[R.L_SH], spine)
	var hips_t := Transform3D(bh, P[R.PELVIS])
	local["Hips"] = bh.get_rotation_quaternion()
	var third := Quaternion.IDENTITY.slerp((bh.inverse() * bc).get_rotation_quaternion(), 1.0 / 3.0)
	var uc_t := hips_t
	for b in ["Spine", "Chest", "UpperChest"]:
		local[b] = third
		uc_t = uc_t * Transform3D(Basis(third), _rest_origin[b])
	var neck: Vector3 = uc_t * _rest_origin["Neck"]
	var hv: Vector3 = uc_t.basis.inverse() * (P[R.HEAD] - neck)
	var half := Quaternion.IDENTITY
	if hv.length() > 0.01:
		half = Quaternion.IDENTITY.slerp(Quaternion(Vector3.UP, hv.normalized()), 0.5)
	local["Neck"] = half
	local["Head"] = half
	var back_c := bc.z
	var fwd_h := -bh.z
	_rag_limb(local, "LeftUpperArm", "LeftLowerArm", "LeftHand", uc_t, P[R.L_EL], P[R.L_WR], back_c)
	_rag_limb(local, "RightUpperArm", "RightLowerArm", "RightHand", uc_t, P[R.R_EL], P[R.R_WR], back_c)
	_rag_limb(local, "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", hips_t, P[R.L_KNEE], P[R.L_ANK], fwd_h)
	_rag_limb(local, "RightUpperLeg", "RightLowerLeg", "RightFoot", hips_t, P[R.R_KNEE], P[R.R_ANK], fwd_h)
	var w := _rag_w
	var wr := w
	for b in local:
		var idx: int = _bone[b]
		_skel.set_bone_pose_rotation(idx, _skel.get_bone_pose_rotation(idx).slerp(local[b], wr))
	var hb: int = _bone["Hips"]
	_skel.set_bone_pose_position(hb, _skel.get_bone_pose_position(hb).lerp(P[R.PELVIS], w))
	# The caman lies where it fell.
	var shaft := P[R.TIP] - P[R.BUTT]
	if shaft.length() > 0.01:
		var ct := Transform3D(_caman_basis(shaft.normalized(), inv.basis * _rag_face), P[R.BUTT])
		ct = _caman.transform.interpolate_with(ct, wr)
		_caman.transform = ct
		_skel.set_bone_pose_position(_bone["Caman"], ct.origin)
		_skel.set_bone_pose_rotation(_bone["Caman"], ct.basis.get_rotation_quaternion())


## Orthonormal basis with x along `x` and y as close to `y` as it can be.
static func _frame(x: Vector3, y: Vector3) -> Basis:
	x = x.normalized()
	y = (y - x * x.dot(y)).normalized()
	return Basis(x, y, x.cross(y))


## Aim a two-bone limb from its root (on `parent`) through `mid` to `tip`.
func _rag_limb(local: Dictionary, upper: String, lower: String, end: String,
		parent: Transform3D, mid: Vector3, tip: Vector3, fallback: Vector3) -> void:
	var root: Vector3 = parent * _rest_origin[upper]
	var line := (tip - root).normalized()
	var perp := (mid - root) - line * (mid - root).dot(line)
	if perp.length() < 0.01:
		perp = fallback
	var ub := _basis_down(mid - root, perp)
	var lb := _basis_down(tip - mid, perp)
	local[upper] = (parent.basis.inverse() * ub).get_rotation_quaternion()
	local[lower] = (ub.inverse() * lb).get_rotation_quaternion()
	local[end] = Quaternion.IDENTITY


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
