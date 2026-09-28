extends Node3D
## Draws the match in 3D: the chosen ground and its scenery (pitch/shinty_pitch.tscn),
## hails, players with camans and shirt sponsors, pitchside ad boards, the ball
## and the TV coverage (camera and replays, see broadcast/tv_director.gd). It only
## reads the match state, never changes it. One world unit is one yard; the
## centre spot is the origin.

const TeamData := preload("res://scripts/team_data.gd")
const PitchScene := preload("res://pitch/shinty_pitch.tscn")

var m: Node  # the match (parent)
var pitch: Node3D
var camera: Camera3D
var ball: Node3D
var ball_shadow: MeshInstance3D
var figures := {}  # Player -> Dictionary of nodes
var referee_figure: Dictionary
var cam_x := 0.0
var cam_zoom := 1.0
var shy_blend := 0.0      # 0 = broadcast camera, 1 = shy camera
var shy_look := Vector3.ZERO
var shy_eye := Vector3.ZERO
var director: ShintyTVDirector
var aim_arrow: Node3D     # where the player is aiming a shy, hit-out or corner

const SKIN := Color(0.93, 0.76, 0.62)
const WOOD := Color(0.55, 0.36, 0.18)


func _ready() -> void:
	m = get_parent()
	pitch = PitchScene.instantiate()
	pitch.venue = int(m.config.get("venue", 0))
	pitch.units_per_yard = 1.0
	pitch.length_yd = m.PITCH.x
	pitch.width_yd = m.PITCH.y
	pitch.show_placeholder_goals = false  # our own hails below
	var q: int = get_node("/root/Game").graphics_quality if has_node("/root/Game") else ShintyPitch.Detail.MEDIUM
	pitch.graphics_quality = q
	pitch.scenery_detail = ShintyPitch.Detail.LOW if q == ShintyPitch.Detail.LOW else ShintyPitch.Detail.MEDIUM
	add_child(pitch)
	_build_hails()
	for p in m.players:
		figures[p] = _build_player(p)
	referee_figure = _build_referee()
	var bm := ShintyBallModel.new()
	bm.simulate = false
	bm.auto_find_hails = false
	bm.scale = Vector3.ONE * ShintyMatchAdapter.TO_YARDS
	bm.display_scale = 1.6  # a touch over real size (6.4 cm) so it reads on TV
	ball = bm
	add_child(ball)
	camera = Camera3D.new()
	camera.fov = 45.0
	camera.far = 6000.0  # the far shore of the Forth
	camera.current = true
	add_child(camera)
	_build_boards()
	_build_aim_arrow()
	director = ShintyTVDirector.new()
	director.name = "TVDirector"
	add_child(director)
	var tracked: Array = figures.values()
	tracked.append(referee_figure)
	director.setup(self, tracked, ball)
	var audio := ShintyMatchAudio.new()
	audio.name = "Audio"
	audio.m = m
	add_child(audio)
	cam_x = m.ball_pos.x - m.PITCH.x / 2.0
	_update_camera(1.0)


func w(v: Vector2, height: float = 0.0) -> Vector3:
	return pitch.sim_to_world(v, height)


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if director.playing:
		director.step(delta)
		return
	for p in figures:
		if p in m.players:
			_update_player(p, figures[p], delta)
		else:
			figures[p]["root"].visible = false  # sent off
	_update_referee(delta)
	_update_aim_arrow()
	ball.position = w(m.ball_pos, m.ball_z + ShintyBallPhysics.RADIUS * ShintyMatchAdapter.TO_YARDS)
	_update_camera(delta)
	director.after_frame(delta)


func _update_player(p, f: Dictionary, delta: float) -> void:
	var root: Node3D = f["root"]
	var speed: float = p.vel.length()
	f["phase"] += delta * speed * 1.6
	root.position = w(p.pos)
	var dir := Vector3(p.facing.x, 0, p.facing.y)
	if dir.length() > 0.01:
		var target := atan2(-dir.x, -dir.z)
		root.rotation.y = lerp_angle(root.rotation.y, target, min(1.0, delta * 14.0))
	var model: ShintyPlayerModel = f["model"]
	model.set_locomotion(Vector3(p.vel.x, 0.0, p.vel.y) * ShintyMatchAdapter.YARD)
	model.look_at_point(w(m.ball_pos, m.ball_z))
	# One-off actions the match asked for (hits, shies, pokes, stumbles, saves).
	if p.anim_seq != f["anim_seq"]:
		f["anim_seq"] = p.anim_seq
		var a: Dictionary = p.anim
		var name := StringName(a["name"])
		if name == &"swing" and a["charge"] > 0.0 and model.is_busy():
			model.release_swing(a["power"])
		else:
			model.play_action(name, a["power"], m.ball_z * ShintyMatchAdapter.YARD)
	elif p == m.human and m.charge >= 0.0 and p.swing_t < 0.0 and not model.is_busy():
		model.charge_swing()   # the backswing while the hit button is held
	elif model.is_charging() and (p != m.human or m.charge < 0.0):
		model.cancel_charge()
	# The caman head goes where the match's stick physics put it.
	model.set_reach(w(Vector2(p.stick.x, p.stick.y), p.stick.z) if p.reach > 0.05 else null, p.reach, p.one_hand)
	f["ring"].visible = p == m.human
	f["arrow"].visible = p == m.human
	f["tag"].visible = p == m.human or p.is_keeper()


func _update_referee(delta: float) -> void:
	var ref = m.referee
	var root: Node3D = referee_figure["root"]
	root.position = w(ref.pos)
	var target := atan2(-ref.facing.x, -ref.facing.y)
	root.rotation.y = lerp_angle(root.rotation.y, target, min(1.0, delta * 8.0))
	ShintyMatchAdapter.update_player(referee_figure, ref.vel, 0.0, false, w(m.ball_pos, m.ball_z))


func _update_camera(delta: float) -> void:
	# The TV gantry camera: pans and zooms from high in the stand.
	var tv: Array = director.live_camera(delta)
	var eye: Vector3 = tv[0]
	var look: Vector3 = tv[1]
	# Shy, hit-out or corner: play stops and the camera comes down behind the
	# taker, looking where they'll send it. It eases back once the ball is struck.
	var taker = m.shy_taker()
	var set_piece_taker = m.set_piece_taker_now()
	if taker != null:
		var f := Vector3(taker.facing.x, 0.0, taker.facing.y)
		var side := Vector3(-f.z, 0.0, f.x)
		var at := w(taker.pos)
		shy_eye = at - f * 5.0 - side * 2.2 + Vector3(0, 2.4, 0)
		shy_look = at + f * 9.0 + Vector3(0, 1.4, 0)
		shy_blend = move_toward(shy_blend, 1.0, delta * 1.5)
	elif set_piece_taker != null:
		var at := w(set_piece_taker.pos)
		var goal := w(m.target_goal(set_piece_taker.team))
		if m.set_piece == "Corner":
			# From behind the corner flag, high enough to see the D and the goalmouth.
			var d_centre := goal - Vector3(signf(goal.x), 0, 0) * 8.0
			var to_d := (d_centre - at).normalized()
			shy_eye = at - to_d * 6.0 + Vector3(0, 5.5, 0)
			shy_look = at.lerp(d_centre, 0.6) + Vector3(0, 0.5, 0)
		else:
			# Hit-out: from behind the goal, over the keeper's shoulder, up the park.
			var up_park := (goal - at).normalized()
			shy_eye = at - up_park * 9.0 + Vector3(0, 5.0, 0)
			shy_look = at + up_park * 30.0 + Vector3(0, 1.0, 0)
		shy_blend = move_toward(shy_blend, 1.0, delta * 1.2)
	else:
		shy_blend = move_toward(shy_blend, 0.0, delta * 0.8)
	var k := shy_blend * shy_blend * (3.0 - 2.0 * shy_blend)
	camera.position = eye.lerp(shy_eye, k)
	camera.look_at(look.lerp(shy_look, k), Vector3.UP)
	camera.fov = lerpf(tv[2], 45.0, k)


## A flat arrow on the grass from the player's taker along their aim, while
## they line up a shy, hit-out or corner.
func _build_aim_arrow() -> void:
	aim_arrow = Node3D.new()
	aim_arrow.name = "AimArrow"
	var mat := _mat(Color(1, 0.92, 0.2, 0.75), true)
	var shaft := _mesh(_box(Vector3(0.18, 0.02, 5.0)), mat)
	shaft.position = Vector3(0, 0, -2.5)
	aim_arrow.add_child(shaft)
	var tip := _mesh(_cone(0.45, 0.9), mat)
	tip.rotation_degrees = Vector3(-90, 0, 0)
	tip.position = Vector3(0, 0, -5.4)
	aim_arrow.add_child(tip)
	aim_arrow.visible = false
	add_child(aim_arrow)


func _update_aim_arrow() -> void:
	var p = m.human
	var on: bool = p != null and p in m.players and (p == m.set_piece_taker_now() or (p.shy_ready and m.carrier == p))
	aim_arrow.visible = on
	if on:
		aim_arrow.position = w(p.pos + p.facing * 0.9, 0.05)
		aim_arrow.rotation = Vector3(0, atan2(-p.facing.x, -p.facing.y), 0)


## Screen position of a pitch point, for the HUD.
func screen_pos(v: Vector2, height: float = 0.0) -> Vector2:
	return camera.unproject_position(w(v, height))


# ---------------------------------------------------------------- building

## Hail models: swap point for proper goal models. Each hail is built in the
## pitch's goal frame (origin on the goal line, +X across, -Z out of the pitch).
func _build_hails() -> void:
	for end in 2:
		var hail := ShintyHailModel.new()
		hail.name = "Hail%d" % end
		hail.width = m.GOAL_W * ShintyMatchAdapter.YARD
		hail.height = m.CROSSBAR * ShintyMatchAdapter.YARD
		# The pitch's goal frame has the net towards -Z; the model's is +Z.
		hail.transform = pitch.goal_transform(end) * Transform3D(
			Basis(Vector3.UP, PI).scaled(Vector3.ONE * ShintyMatchAdapter.TO_YARDS), Vector3.ZERO)
		add_child(hail)


func _build_player(p) -> Dictionary:
	var f := ShintyMatchAdapter.build_player(self, p.data, {"colors": m.kits[p.team]})
	var root: Node3D = f["root"]
	var team: Dictionary = m.teams[p.team]
	ShintyKitSponsor.apply(f["model"], ShintySponsors.shirt_texture(ShintySponsors.for_team(team)))
	var ring := _mesh(_torus(0.75, 0.95), _mat(Color(1, 0.92, 0.2), true))
	ring.position = Vector3(0, 0.04, 0)
	root.add_child(ring)
	var arrow := _mesh(_cone(0.25, 0.4), _mat(Color(1, 0.92, 0.2), true))
	arrow.rotation_degrees = Vector3(180, 0, 0)
	arrow.position = Vector3(0, 2.6, 0)
	root.add_child(arrow)
	var tag := Label3D.new()
	tag.text = str(p.number)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.font_size = 48
	tag.outline_size = 12
	tag.pixel_size = 0.01
	tag.position = Vector3(0, 2.25, 0)
	root.add_child(tag)
	root.position = w(p.pos)
	f.merge({"ring": ring, "arrow": arrow, "tag": tag, "phase": 0.0, "anim_seq": 0})
	return f


## Pitchside advertising boards where the ground puts them (usually along the
## far touchline, where the TV camera sees them, and behind each goal; see
## ShintyPitch.board_rows()).
func _build_boards() -> void:
	var holder := Node3D.new()
	holder.name = "AdBoards"
	add_child(holder)
	var s := 1.0 / ShintyMatchAdapter.YARD  # yards per metre
	for r in pitch.board_rows():
		ShintyAdBoard.place_row(holder, r[0], r[1], Vector3.ZERO, s, 6.0, true, r[2])


## The referee: black kit (a bright top if a team wears black), no helmet and
## no caman.
func _build_referee() -> Dictionary:
	var top := TeamData.referee_colour(m.kits)
	var kit := {"colors": {"primary": top, "secondary": "#15161a", "shorts": "#15161a", "socks": "#15161a"}}
	var f := ShintyMatchAdapter.build_player(self, {"name": "Referee", "number": 0, "position": "REF", "pace": 60, "tackling": 40}, kit)
	var model: ShintyPlayerModel = f["model"]
	model.wear_helmet = false
	model.rebuild()
	var caman := model.find_child("Caman", true, false)
	if caman:
		caman.visible = false
	f["root"].position = w(m.referee.pos)
	return f


# ---------------------------------------------------------------- mesh helpers

func _mesh(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _mat(c: Color, unshaded: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 0.9
	if c.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s


func _cylinder(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	return c


func _cone(r: float, h: float) -> CylinderMesh:
	var c := _cylinder(r, h)
	c.top_radius = 0.0
	return c


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	return c


func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	return t
