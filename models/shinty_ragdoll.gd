class_name ShintyRagdoll
extends RefCounted
## A small Verlet ragdoll for a player knocked off their feet: 15 joints and
## the caman as point masses in world space, held together by distance links,
## with knees and elbows that only bend the right way, gravity and a grassy
## ground that grips. ShintyPlayerModel seeds it from the pose the player was
## in, pushes it the way they were hit, and turns the joints back into bone
## rotations. It only exists while someone is going down, so it costs nothing
## the rest of the match.

enum { PELVIS, CHEST, HEAD, L_SH, L_EL, L_WR, R_SH, R_EL, R_WR,
	L_HIP, L_KNEE, L_ANK, R_HIP, R_KNEE, R_ANK, BUTT, TIP, COUNT }

## Collision radius of each joint against the ground, metres.
const RADIUS := [0.11, 0.12, 0.11, 0.07, 0.05, 0.05, 0.07, 0.05, 0.05,
	0.08, 0.06, 0.05, 0.08, 0.06, 0.05, 0.02, 0.04]
## How quickly each joint answers the muscles getting up: feet and knees
## come under the body first, then the trunk rises over them.
const PULL := [1.0, 0.6, 0.5, 0.7, 0.9, 0.9, 0.7, 0.9, 0.9,
	1.2, 2.0, 2.2, 1.2, 2.0, 2.2, 0.8, 0.8]
const STEP := 1.0 / 120.0
const GRAVITY := 9.81
const ITERATIONS := 4
const GRIP := 0.45        ## share of sliding speed the grass takes each step
const AIR_DRAG := 0.995

var pos := PackedVector3Array()
var prev := PackedVector3Array()
var age := 0.0
var _links := []          # [a, b, rest length, stiffness]
var _left := 0.0          # simulation time not yet stepped
var ground := 0.0         ## height of the grass, world y
## Where the muscles want each joint (world), and how hard they pull: the
## share of the gap closed each step. 0 = limp.
var targets := PackedVector3Array()
var pull_strength := 0.0
var _brace := Vector3.ZERO   # push direction: the arms go out that way to break the fall


## `joints`: world positions indexed by the enum. `velocity`: how the body was
## moving (m/s). `push`: extra velocity from the hit, strongest at the
## shoulders and nothing at the feet, so the player topples rather than slides.
## `grip`: the wrist (L_WR or R_WR) that keeps hold of the caman.
func _init(joints: PackedVector3Array, velocity: Vector3, push: Vector3, grip: int) -> void:
	pos = joints.duplicate()
	prev = joints.duplicate()
	var foot_y := minf(pos[L_ANK].y, pos[R_ANK].y)
	var head_y := maxf(pos[HEAD].y, foot_y + 0.5)
	for i in COUNT:
		var up := clampf((pos[i].y - foot_y) / (head_y - foot_y), 0.0, 1.0)
		var v := velocity * lerpf(0.5, 1.0, up) + push * up * up
		if i == BUTT or i == TIP:
			v = velocity * 0.8 + push * 0.6
		prev[i] = pos[i] - v * STEP
	_brace = Vector3(push.x, 0.0, push.z).normalized() if Vector2(push.x, push.z).length() > 0.01 \
		else Vector3(velocity.x, 0.0, velocity.z).normalized()
	# Solid parts: the pelvis, the shoulders and the head.
	for pair in [[PELVIS, L_HIP], [PELVIS, R_HIP], [L_HIP, R_HIP],
			[CHEST, L_SH], [CHEST, R_SH], [L_SH, R_SH],
			[HEAD, CHEST], [HEAD, L_SH], [HEAD, R_SH], [PELVIS, CHEST],
			[L_SH, L_EL], [L_EL, L_WR], [R_SH, R_EL], [R_EL, R_WR],
			[L_HIP, L_KNEE], [L_KNEE, L_ANK], [R_HIP, R_KNEE], [R_KNEE, R_ANK],
			[BUTT, TIP], [grip, BUTT], [grip, TIP]]:
		_link(pair[0], pair[1], 1.0)
	# The trunk bends and twists a little between hips and shoulders.
	for pair in [[L_HIP, L_SH], [R_HIP, R_SH], [L_HIP, R_SH], [R_HIP, L_SH], [PELVIS, HEAD]]:
		_link(pair[0], pair[1], 0.35)
	# A little muscle tone: knees and elbows keep some bend instead of lying
	# dead straight.
	for limb in [[L_HIP, L_KNEE, L_ANK, 0.9], [R_HIP, R_KNEE, R_ANK, 0.9],
			[L_SH, L_EL, L_WR, 0.75], [R_SH, R_EL, R_WR, 0.75]]:
		var full := pos[limb[0]].distance_to(pos[limb[1]]) + pos[limb[1]].distance_to(pos[limb[2]])
		_links.append([limb[0], limb[2], full * limb[3], 0.04])


func _link(a: int, b: int, stiffness: float) -> void:
	_links.append([a, b, pos[a].distance_to(pos[b]), stiffness])


## Move the whole body without changing how it moves (it is carried along
## with the player's position in the match).
func shift(d: Vector3) -> void:
	for i in COUNT:
		pos[i] += d
		prev[i] += d


## Advance by `delta` seconds in fixed steps.
func step(delta: float) -> void:
	_left = minf(_left + delta, 0.1)
	while _left >= STEP:
		_left -= STEP
		age += STEP
		_integrate()
		for it in ITERATIONS:
			_solve()


## How fast the body is still moving, m/s (the fastest joint).
func speed() -> float:
	var top := 0.0
	for i in R_ANK + 1:
		top = maxf(top, (pos[i] - prev[i]).length() / STEP)
	return top


func _integrate() -> void:
	var g := Vector3.DOWN * GRAVITY * STEP * STEP
	# Hands go out to break the fall for the first half second or so.
	var brace := clampf(1.0 - age / 0.6, 0.0, 1.0)
	for i in COUNT:
		var p := pos[i]
		var v := (p - prev[i]) * AIR_DRAG
		prev[i] = p
		var a := g
		if brace > 0.0 and (i == L_WR or i == R_WR):
			var want: Vector3 = pos[CHEST] + _brace * 0.55 + Vector3.DOWN * 0.45
			a += (want - p) * 30.0 * brace * STEP * STEP
		pos[i] = p + v + a


func _solve() -> void:
	for l in _links:
		var a: int = l[0]
		var b: int = l[1]
		var d: Vector3 = pos[b] - pos[a]
		var len := d.length()
		if len < 0.0001:
			continue
		var corr: Vector3 = d * ((len - l[2]) / len) * 0.5 * l[3]
		pos[a] += corr
		pos[b] -= corr
	# Hinges: knees bend forwards only, elbows backwards only.
	var right := pos[R_HIP] - pos[L_HIP]
	var up := pos[CHEST] - pos[PELVIS]
	var fwd := up.cross(right).normalized()
	_hinge(L_HIP, L_KNEE, L_ANK, fwd)
	_hinge(R_HIP, R_KNEE, R_ANK, fwd)
	# Hips: a thigh can't swing far behind the trunk (the body folds at the
	# waist or goes down like a log instead of arching back).
	_behind(L_HIP, L_KNEE, fwd, 0.3)
	_behind(R_HIP, R_KNEE, fwd, 0.3)
	var sh_fwd := up.cross(pos[R_SH] - pos[L_SH]).normalized()
	_hinge(L_SH, L_EL, L_WR, -sh_fwd)
	_hinge(R_SH, R_EL, R_WR, -sh_fwd)
	if pull_strength > 0.0 and targets.size() == COUNT:
		for i in COUNT:
			pos[i] = pos[i].lerp(targets[i], minf(1.0, pull_strength * PULL[i]) / ITERATIONS)
			# Muscles, not springs: no bouncing past the pose.
			prev[i] = prev[i].lerp(pos[i], 0.25 / ITERATIONS)
	# The grass: nothing goes through it, and it grips what lies on it.
	for i in COUNT:
		var r: float = RADIUS[i] + ground
		if pos[i].y < r:
			pos[i].y = r
			prev[i].y = r
			prev[i].x = lerpf(prev[i].x, pos[i].x, GRIP)
			prev[i].z = lerpf(prev[i].z, pos[i].z, GRIP)


## Keep the middle joint of a limb on the `side` of the line between its ends.
func _hinge(a: int, m: int, b: int, side: Vector3) -> void:
	var mid := (pos[a] + pos[b]) * 0.5
	var off := (pos[m] - mid).dot(side)
	if off < 0.0:
		pos[m] -= side * off


## Keep joint `b` from going further than `limit` (share of the bone length)
## behind joint `a` along `fwd`.
func _behind(a: int, b: int, fwd: Vector3, limit: float) -> void:
	var v := pos[b] - pos[a]
	var back := -v.dot(fwd) - v.length() * limit
	if back > 0.0:
		pos[b] += fwd * back * 0.5
		pos[a] -= fwd * back * 0.5
