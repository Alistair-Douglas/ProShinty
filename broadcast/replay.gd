class_name ShintyReplay
extends RefCounted
## Records what the match view shows (every player's position and pose, the
## caman, the referee and the ball) for the last few seconds, and plays it
## back. It records the drawn result rather than the match state, so replays
## work whatever the match logic does.

const KEEP_SECONDS := 10.0

## Each tracked figure: {"root": Node3D, "model": ShintyPlayerModel}
var figures: Array = []
var ball: Node3D
var frames: Array = []    # [{"t": float, "ball": Vector3, "f": [figure data]}]
var time := 0.0

var _skels: Array = []
var _camans: Array = []
var _bone_counts: Array = []


func track(figure_list: Array, ball_node: Node3D) -> void:
	figures = figure_list
	ball = ball_node
	_skels.clear()
	_camans.clear()
	_bone_counts.clear()
	for f in figures:
		var model: Node3D = f["model"]
		var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
		_skels.append(skel)
		_camans.append(model.find_child("Caman", true, false))
		_bone_counts.append(skel.get_bone_count() if skel else 0)


## Start recording one more figure (a substitute coming on). Frames from
## before it arrived show it hidden.
func add_figure(f: Dictionary) -> void:
	figures.append(f)
	var model: Node3D = f["model"]
	var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
	_skels.append(skel)
	_camans.append(model.find_child("Caman", true, false))
	_bone_counts.append(skel.get_bone_count() if skel else 0)


## Store the current frame. Call once per drawn frame, after the view updated.
func record(delta: float) -> void:
	time += delta
	var fd := []
	for i in figures.size():
		var f: Dictionary = figures[i]
		var root: Node3D = f["root"]
		var skel: Skeleton3D = _skels[i]
		var n: int = _bone_counts[i]
		var pos := PackedVector3Array()
		var rot := []
		pos.resize(n)
		for b in n:
			pos[b] = skel.get_bone_pose_position(b)
			rot.append(skel.get_bone_pose_rotation(b))
		var caman: Node3D = _camans[i]
		fd.append([root.transform, root.visible, pos, rot, caman.transform if caman else Transform3D()])
	frames.append({"t": time, "ball": ball.position, "f": fd})
	while frames.size() > 2 and time - frames[0]["t"] > KEEP_SECONDS:
		frames.pop_front()


func first_time() -> float:
	return frames[0]["t"] if not frames.is_empty() else time


## Pose everything as it was at time `t` (blending between recorded frames).
## Returns the ball position then.
func show_at(t: float) -> Vector3:
	if frames.is_empty():
		return Vector3.ZERO
	var i := 0
	while i < frames.size() - 2 and frames[i + 1]["t"] < t:
		i += 1
	var a: Dictionary = frames[i]
	var b: Dictionary = frames[mini(i + 1, frames.size() - 1)]
	var span: float = b["t"] - a["t"]
	var k := clampf((t - a["t"]) / span, 0.0, 1.0) if span > 0.0 else 0.0
	for fi in figures.size():
		var root: Node3D = figures[fi]["root"]
		if fi >= a["f"].size() or fi >= b["f"].size():
			root.visible = false   # not on yet
			continue
		var fa: Array = a["f"][fi]
		var fb: Array = b["f"][fi]
		root.transform = (fa[0] as Transform3D).interpolate_with(fb[0], k)
		root.visible = fa[1]
		var skel: Skeleton3D = _skels[fi]
		for bi in _bone_counts[fi]:
			skel.set_bone_pose_position(bi, fa[2][bi].lerp(fb[2][bi], k))
			skel.set_bone_pose_rotation(bi, (fa[3][bi] as Quaternion).slerp(fb[3][bi], k))
		var caman: Node3D = _camans[fi]
		if caman:
			caman.transform = (fa[4] as Transform3D).interpolate_with(fb[4], k)
	var bp: Vector3 = (a["ball"] as Vector3).lerp(b["ball"], k)
	ball.position = bp
	return bp


## Stop the models animating themselves while a replay drives them.
func hold_models(on: bool) -> void:
	for f in figures:
		f["model"].manual_update = on
