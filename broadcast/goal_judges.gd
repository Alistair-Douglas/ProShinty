class_name ShintyGoalJudges
extends Node3D
## The two goal judges, one behind each hail beside the far post, with a white
## flag. They watch the match's events (they never change the match):
##
## - ball over the goal line wide (a hit-out): the judge at that end raises
##   the flag straight up;
## - a corner: the flag goes up, then the judge points it at the corner flag
##   on the side the ball went out;
## - a goal: the flag waves overhead, and that team's supporters in the crowd
##   celebrate.
##
## Positions are in the match view's units (yards, centre spot at the origin).

enum Call { NONE, RAISE, CORNER, GOAL }

const HOLD := {Call.RAISE: 2.6, Call.CORNER: 3.4, Call.GOAL: 4.0}
const FLAG_COLOR := Color(0.96, 0.96, 0.94)

var m: Node       # the match
var crowd: ShintyCrowd
## Per end (0 west, 1 east): {"f": figure dictionary, "signal", "t", "side"}.
var judges: Array = []
var _next_event := 0


func setup(match_node: Node, view: Node3D, crowd_node: ShintyCrowd) -> void:
	m = match_node
	crowd = crowd_node
	_next_event = m.events.size()
	var hl: float = m.PITCH.x / 2.0
	var post: float = m.GOAL_W / 2.0
	for end in 2:
		var sgn := -1.0 if end == 0 else 1.0
		var kit := {"colors": {"primary": "#e8e6df", "secondary": "#e8e6df", "socks": "#23252b"}}
		var f := ShintyMatchAdapter.build_player(self, {"name": "Goal judge", "number": 0, "position": "GJ",
			"pace": 40, "tackling": 30, "height_cm": 176.0}, kit)
		var model: ShintyPlayerModel = f["model"]
		model.wear_helmet = false
		model.shorts_color = Color(0.14, 0.15, 0.18)   # long dark trousers, near enough
		model.manual_update = true
		model.rebuild()
		var caman := model.find_child("Caman", true, false)
		if caman:
			caman.visible = false
		var root: Node3D = f["root"]
		root.name = "GoalJudge%s" % ["West", "East"][end]
		# Just behind the goal line, outside the far post and clear of the net.
		root.position = Vector3(sgn * (hl + 1.3), 0.0, -(post + 1.4))
		root.rotation.y = atan2(sgn, 0.0)   # face down the pitch
		var flag := _flag()
		var att := BoneAttachment3D.new()
		att.bone_name = "RightHand"
		model.find_child("Skeleton3D", true, false).add_child(att)
		att.add_child(flag)
		judges.append({"f": f, "signal": Call.NONE, "t": 0.0, "side": 1.0, "att": att, "end": end})


## Called every frame by the view, also during replays.
func step(delta: float) -> void:
	_read_events()
	var ball: Vector3 = get_parent().w(m.ball_pos, m.ball_z)
	for j in judges:
		j["t"] += delta
		if j["signal"] != Call.NONE and j["t"] > HOLD[j["signal"]]:
			j["signal"] = Call.NONE
		var model: ShintyPlayerModel = j["f"]["model"]
		model.set_locomotion(Vector3.ZERO)
		model.look_at_point(ball)
		model.advance(delta)
		_pose_arms(j, model)


## The signal a judge is giving now (for tests and the TV graphics).
func signal_at(end: int) -> int:
	return judges[end]["signal"]


func corner_side(end: int) -> float:
	return judges[end]["side"]


func _read_events() -> void:
	if _next_event > m.events.size():
		_next_event = 0
	while _next_event < m.events.size():
		var e: Dictionary = m.events[_next_event]
		_next_event += 1
		match e.get("type", ""):
			"Hit-out":
				# The ball has been put on the spot at the edge of that end's D.
				_give(_end_of(m.ball_pos.x), Call.RAISE, 0.0)
			"Corner":
				_give(_end_of(m.ball_pos.x), Call.CORNER, m.ball_pos.y)
			"goal":
				var gx: float = m.own_goal(1 - int(e["team"])).x
				_give(_end_of(gx), Call.GOAL, 0.0)
				if crowd:
					crowd.cheer(int(e["team"]))


func _end_of(x: float) -> int:
	return 0 if x < m.PITCH.x / 2.0 else 1


func _give(end: int, sig: int, corner_y: float) -> void:
	var j: Dictionary = judges[end]
	j["signal"] = sig
	j["t"] = 0.0
	if sig == Call.CORNER:
		# Which hand is on the corner's side, as the judge faces the pitch.
		var root: Node3D = j["f"]["root"]
		var corner := Vector3(root.position.x, 0.0, corner_y - m.PITCH.y / 2.0)
		var local: Vector3 = root.global_transform.affine_inverse() * (get_parent().to_global(corner) as Vector3)
		j["side"] = 1.0 if local.x > 0.0 else -1.0
	var hand := "RightHand" if sig != Call.CORNER or j["side"] > 0.0 else "LeftHand"
	(j["att"] as BoneAttachment3D).bone_name = hand


## Arms by hand: the model's own pose keeps both hands on a caman, which the
## judge doesn't carry. Angles are about the chest's forward axis, 0 hanging
## down, PI straight up, positive outwards.
func _pose_arms(j: Dictionary, model: ShintyPlayerModel) -> void:
	var skel: Skeleton3D = model.find_child("Skeleton3D", true, false)
	var t: float = j["t"]
	var flag_arm := 0.12
	var flag_fwd := 0.25
	var other := 0.1
	var flag_side := 1.0
	match j["signal"]:
		Call.RAISE:
			flag_arm = lerpf(0.12, PI - 0.05, smoothstep(0.0, 0.25, t))
			flag_fwd = 0.0
		Call.CORNER:
			flag_side = j["side"]
			# Up first, then down to point along the goal line at the corner.
			var up := smoothstep(0.0, 0.25, t)
			var point := smoothstep(0.7, 1.0, t)
			flag_arm = lerpf(lerpf(0.12, PI - 0.05, up), 1.35, point)
			flag_fwd = lerpf(0.0, 0.15, point)
		Call.GOAL:
			flag_arm = PI - 0.25 + 0.4 * sin(t * 9.0) * smoothstep(0.0, 0.3, t)
			flag_fwd = 0.0
			other = 0.6
	var flag_bone := "Right" if flag_side > 0.0 else "Left"
	var other_bone := "Left" if flag_side > 0.0 else "Right"
	_set_arm(skel, flag_bone, flag_arm, flag_fwd)
	_set_arm(skel, other_bone, other, 0.05)


func _set_arm(skel: Skeleton3D, side: String, out: float, fwd: float) -> void:
	var s := 1.0 if side == "Right" else -1.0
	var q := Quaternion(Vector3.FORWARD, -fwd) * Quaternion(Vector3.BACK, s * out)
	skel.set_bone_pose_rotation(skel.find_bone(side + "UpperArm"), q)
	skel.set_bone_pose_rotation(skel.find_bone(side + "LowerArm"), Quaternion(Vector3.RIGHT, 0.08))
	skel.set_bone_pose_rotation(skel.find_bone(side + "Hand"), Quaternion.IDENTITY)


## A short pole with a white flag, running down the hand's -Y (along the
## arm), sized in metres (the judge's model is scaled to yards).
func _flag() -> Node3D:
	var n := Node3D.new()
	n.name = "Flag"
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.012
	cyl.height = 0.7
	cyl.radial_segments = 6
	cyl.rings = 1
	pole.mesh = cyl
	pole.position = Vector3(0, -0.28, 0)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.3, 0.22, 0.15)
	pole.material_override = wood
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(pole)
	var cloth := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.42, 0.34)
	cloth.mesh = q
	cloth.position = Vector3(0, -0.46, -0.22)
	cloth.rotation.y = PI * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = FLAG_COLOR
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.8
	cloth.material_override = mat
	cloth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(cloth)
	return n
