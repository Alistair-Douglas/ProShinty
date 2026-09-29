extends Node3D
## The benches in the 3D match: each side's substitutes sitting in a dugout
## on the far touchline (where the TV camera sees them), in neon bibs over
## their kit. Players who come off sit down beside them without a bib.
## Kingussie's ground has its own dugouts; elsewhere a plain one is built in
## the same place. Seated figures are posed once and never animated, and
## cast no shadows, so they cost little to draw.

const TeamData := preload("res://scripts/team_data.gd")

## Dugout centre from halfway along the touchline, and back from the line
## (metres, as the Kingussie venue places its dugouts).
const DUGOUT_X_M := 9.0
const DUGOUT_BACK_M := 5.0
const SEAT_Z_M := -0.5       # the seat, from the dugout centre (towards the back)
const SEAT_H_M := 0.45
const SLOT_M := 0.55         # seat spacing
const SLOTS := 8
const BIBS := [Color("d4ff1e"), Color("ff6a13"), Color("ff2fa8")]   # neon yellow, orange, pink

var view: Node3D             # match_view.gd
var m: Node                  # the match
var seated := {}             # player dictionary -> {"root": Node3D, "slot": int, "team": int}
var _bib := [Color.YELLOW, Color.ORANGE]
var _taken := [{}, {}]       # slot -> player dictionary


func setup(p_view: Node3D) -> void:
	view = p_view
	m = view.m
	var own_dugouts: bool = int(m.config.get("venue", 0)) == ShintyPitch.Venue.KINGUSSIE
	for t in 2:
		_bib[t] = _bib_colour(m.kits[t], _bib[1 - t] if t == 1 else Color.BLACK)
		if not own_dugouts:
			_build_dugout(t)
		for pd in m.subs.bench[t]:
			_sit(t, pd, true)


## Each frame: bench players who've gone on leave their seat, and players who
## have walked off sit down.
func step() -> void:
	for pd in seated:
		_keep_posed(seated[pd])
	for pd in seated.keys():
		var t: int = seated[pd]["team"]
		if not pd in m.subs.bench[t] and not pd in m.subs.came_off[t]:
			_stand(pd)
	for t in 2:
		for pd in m.subs.came_off[t]:
			if not seated.has(pd) and not m.subs.leaving.any(func(p): return p.data == pd):
				_sit(t, pd, false)


## Where the team's dugout is, in the match's pitch coordinates (yards). The
## home side's is in the half it defends first.
func dugout_sim(t: int) -> Vector2:
	var s: float = 1.0 / ShintyMatchAdapter.YARD
	return Vector2(m.PITCH.x / 2.0 + (-DUGOUT_X_M if t == 0 else DUGOUT_X_M) * s, -DUGOUT_BACK_M * s)


func _world(t: int, local_m: Vector3) -> Vector3:
	var s: float = 1.0 / ShintyMatchAdapter.YARD
	return view.w(dugout_sim(t)) + local_m * s


func _build_dugout(t: int) -> void:
	var s: float = 1.0 / ShintyMatchAdapter.YARD
	var holder := Node3D.new()
	holder.name = "Dugout%d" % t
	holder.position = view.w(dugout_sim(t))
	holder.scale = Vector3.ONE * s
	add_child(holder)
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.86, 0.87, 0.85)
	shell.roughness = 0.8
	var seat := StandardMaterial3D.new()
	seat.albedo_color = Color(0.12, 0.2, 0.32)
	var boxes := [
		[Vector3(5.0, 2.1, 0.15), Vector3(0, 1.05, -0.9), shell],     # back
		[Vector3(5.2, 0.12, 2.0), Vector3(0, 2.15, 0), shell],        # roof
		[Vector3(0.12, 2.1, 1.9), Vector3(-2.5, 1.05, 0), shell],     # sides
		[Vector3(0.12, 2.1, 1.9), Vector3(2.5, 1.05, 0), shell],
		[Vector3(4.6, SEAT_H_M, 0.5), Vector3(0, SEAT_H_M / 2.0, SEAT_Z_M), seat],
	]
	for b in boxes:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b[0]
		mi.mesh = bm
		mi.position = b[1]
		mi.material_override = b[2]
		holder.add_child(mi)


func _sit(t: int, pd: Dictionary, bib: bool) -> void:
	var slot := -1
	for i in SLOTS:
		# Bench players from the middle outwards, those who came off at the ends.
		var k: int = [3, 4, 2, 5, 1, 6, 0, 7][i] if bib else [0, 7, 1, 6, 2, 5, 3, 4][i]
		if not _taken[t].has(k):
			slot = k
			break
	if slot < 0:
		return
	_taken[t][slot] = pd
	var f := ShintyMatchAdapter.build_player(self, pd, {"colors": m.kits[t]})
	var root: Node3D = f["root"]
	var model: ShintyPlayerModel = f["model"]
	model.manual_update = true
	root.position = _world(t, Vector3((slot - (SLOTS - 1) / 2.0) * SLOT_M, 0, SEAT_Z_M - 0.05))
	root.rotation.y = PI   # facing the pitch
	seated[pd] = {"root": root, "model": model, "slot": slot, "team": t, "bib": bib, "skel": null}
	_keep_posed(seated[pd])


## Pose the figure, and again if the model rebuilt its skeleton (it does when
## a look setting changes after setup, as keepers' kits do).
func _keep_posed(e: Dictionary) -> void:
	var model: ShintyPlayerModel = e["model"]
	var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null or skel == e["skel"]:
		return
	e["skel"] = skel
	_pose_seated(model, e["slot"])
	if e["bib"]:
		_add_bib(model, _bib[e["team"]])
	for mi in e["root"].find_children("*", "GeometryInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _stand(pd: Dictionary) -> void:
	var e: Dictionary = seated[pd]
	_taken[e["team"]].erase(e["slot"])
	e["root"].queue_free()
	seated.erase(pd)


## Sat on the bench: thighs forward, shins down, hands on the knees, the
## caman put away.
func _pose_seated(model: ShintyPlayerModel, slot: int) -> void:
	var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return
	var lean := 0.08 * float(slot % 3 - 1)   # not all sat the same
	var rot := {
		"Hips": Vector3(0, lean, 0),
		"Spine": Vector3(0.12, 0, 0),
		"Chest": Vector3.ZERO,
		"UpperChest": Vector3.ZERO,
		"Neck": Vector3(0.05, 0, 0),
		"Head": Vector3(0.05, -lean * 2.0, 0),
		"LeftUpperLeg": Vector3(1.5, 0, -0.08),
		"RightUpperLeg": Vector3(1.5, 0, 0.08),
		"LeftLowerLeg": Vector3(-1.45, 0, 0),
		"RightLowerLeg": Vector3(-1.45, 0, 0),
		"LeftFoot": Vector3(-0.05, 0, 0),
		"RightFoot": Vector3(-0.05, 0, 0),
		"LeftUpperArm": Vector3(0.45, 0, 0.12),
		"RightUpperArm": Vector3(0.45, 0, -0.12),
		"LeftLowerArm": Vector3(0.7, 0, 0),
		"RightLowerArm": Vector3(0.7, 0, 0),
		"LeftHand": Vector3.ZERO,
		"RightHand": Vector3.ZERO,
	}
	for bone in rot:
		var i := skel.find_bone(bone)
		if i >= 0:
			skel.set_bone_pose_rotation(i, Quaternion.from_euler(rot[bone]))
	var hips := skel.find_bone("Hips")
	if hips >= 0:
		# Down onto the seat, the backside a little behind the seat's front edge.
		var seat_h: float = (SEAT_H_M + 0.07) / skel.scale.y
		skel.set_bone_pose_position(hips, Vector3(0, seat_h, 0.12))
	var caman := skel.find_bone("Caman")
	if caman >= 0:
		skel.set_bone_pose_scale(caman, Vector3.ONE * 0.001)


## A neon training bib over the shirt, on the chest bone.
func _add_bib(model: ShintyPlayerModel, colour: Color) -> void:
	var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = "Chest"
	skel.add_child(att)
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	var r := 0.25 if model.is_keeper else 0.2   # over the keeper's chest pad
	cyl.top_radius = r
	cyl.bottom_radius = r + 0.005
	cyl.height = 0.4
	cyl.radial_segments = 14
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	mi.mesh = cyl
	mi.scale = Vector3(1.0, 1.0, 0.68)
	mi.position = Vector3(0, 0.06, -0.005)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = 0.35
	mat.roughness = 0.7
	mi.material_override = mat
	att.add_child(mi)


## A neon that stands out from the team's shirt (and from the other bench).
func _bib_colour(kit: Dictionary, avoid: Color) -> Color:
	var shirt: Array = TeamData.shirt_colours(kit)
	for c in BIBS:
		var ok: bool = c != avoid
		for sc in shirt:
			if TeamData.colour_distance(c, sc) < 0.9:
				ok = false
		if ok:
			return c
	return BIBS[0]
