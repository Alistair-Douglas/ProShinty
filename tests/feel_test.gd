extends SceneTree
## Plays a match with the view and checks the feel of a hit: a hard strike
## holds the picture for a moment and then carries on at full speed, jolts the
## camera, throws up a puff of grass, leaves a streak and rumbles the pad; a
## ball put onto a caman is blended across, not snapped; and the ball is drawn
## close to where the match has it all the way through.
## godot --headless --fixed-fps 60 --path . -s tests/feel_test.gd
var frame := 0
var m: Node
var view: Node
var ok := true
var stop_frame := -1
var gap_frame := -1
var worst := 0.0


func _initialize() -> void:
	change_scene_to_file("res://scenes/match.tscn")


func _check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	ok = ok and cond


func _process(_d: float) -> bool:
	frame += 1
	if m == null:
		m = current_scene
		return false
	if view == null:
		view = m.get_node("View")
	var feel: ShintyMatchFeel = view.feel
	# The drawn ball keeps up with the match's (a step behind at most, plus any
	# gap being blended out), away from restarts.
	if frame > 5 and m.carrier == null and m.state == m.State.PLAY:
		var d: float = Vector2(view.ball_draw.x, view.ball_draw.y).distance_to(m.ball_pos)
		if d < 10.0:
			worst = maxf(worst, d)
	if frame == 120:
		# A hard strike by your player, low along the ground.
		m.carrier = null
		m.ball_z = 0.0
		m.ball_vz = 0.0
		m.ball_vel = Vector2(40.0, 3.0)
		# Straight to the feel (the match's next step could pick the ball up).
		feel._on_event({"type": "strike", "by": m.human, "at": m.ball_pos})
		stop_frame = frame
	if stop_frame > 0 and frame == stop_frame:
		_check(Engine.time_scale < 1.0, "hard strike holds the picture (time scale %.2f)" % Engine.time_scale)
		_check(feel.kicks >= 1, "hard strike jolts the camera")
		_check(feel.puffs_made >= 1, "puff of grass off the turf")
		_check(feel.trails >= 1, "hard-hit ball leaves a streak")
		_check(feel.rumbles >= 1, "your hit rumbles the pad")
	if stop_frame > 0 and frame == stop_frame + 30:
		_check(is_equal_approx(Engine.time_scale, 1.0), "game back to full speed after the hit-stop")
	if frame == 200:
		# The ball put a yard onto a caman: drawn from where it was.
		m._place_ball(m.ball_pos + Vector2(1.0, 0.0), m.ball_z)
		gap_frame = frame
	if gap_frame > 0 and frame == gap_frame + 2:
		_check(view._ball_gap.length() > 0.2, "gap to the caman blended, not snapped (%.2f yd)" % view._ball_gap.length())
	if gap_frame > 0 and frame == gap_frame + 10:
		_check(view._ball_gap.length() < 0.02, "gap closed within a few frames (%.3f yd)" % view._ball_gap.length())
	if frame == 900:
		_check(worst < 3.5, "ball drawn close to the match's ball (worst %.2f yd)" % worst)
		_check(is_equal_approx(Engine.time_scale, 1.0), "full speed at the end")
		print("hit-stops %d, camera kicks %d, puffs %d, streaks %d" % [feel.stops, feel.kicks, feel.puffs_made, feel.trails])
		print("PASS" if ok else "FAIL")
		quit(0 if ok else 1)
		return true
	return false
