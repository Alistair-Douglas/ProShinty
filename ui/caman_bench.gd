class_name ShintyCamanBench
extends Node3D
## The caman designer's 3D set: a slatted wooden bench on the touchline with
## the caman being designed up on a stand, rolls of the chosen tapes, the
## club's helmet, spare camans leaning on the end and a water bottle. It faces
## the pitch (-Z), so the ground fills the view behind it.
##
## Origin is the middle of the bench on the ground; the bench runs along X.

const TOP_Y := 0.46            ## height of the seat
const LENGTH := 1.7
const DEPTH := 0.44

## Where the camera sits and looks, relative to the bench. The bench sits on
## the right of the frame so the options panel on the left doesn't cover it.
const CAMERA_POS := Vector3(-0.3, 1.14, 2.1)
const CAMERA_LOOK := Vector3(-0.42, 0.64, -0.5)

var design := {}
var team := {}

var _caman_pivot: Node3D       ## turns the displayed caman round its shaft
var _caman: Node3D
var _rolls: Array[MeshInstance3D] = []
var _helmet_holder: Node3D
var _helmet_key := ""
var _spin := 0.0
var _spin_speed := 0.35
var _time := 0.0


func _ready() -> void:
	_build_bench()
	_build_stand()
	_build_props()
	refresh()


func set_design(d: Dictionary, p_team: Dictionary) -> void:
	design = ShintyCaman.sanitize(d)
	team = p_team
	if is_inside_tree():
		refresh()


## Turn the displayed caman by hand (mouse drag); it keeps turning slowly.
func spin(amount: float) -> void:
	_spin += amount
	_spin_speed = 0.35 * signf(amount) if amount != 0.0 else _spin_speed


func camera_transform() -> Transform3D:
	return global_transform * Transform3D.IDENTITY.translated(CAMERA_POS).looking_at(CAMERA_LOOK, Vector3.UP)


func refresh() -> void:
	design = ShintyCaman.sanitize(design)
	if _caman:
		_caman.queue_free()
	_caman = Node3D.new()
	_caman.name = "DesignedCaman"
	# Lay it along the bench: shaft (-Y) to +X, bas curling up (-Z to +Y).
	_caman.transform = Transform3D(Basis(Vector3(0, 0, 1), PI / 2), Vector3(-ShintyPlayerModel.CAMAN_LENGTH * 0.5, 0, 0))
	_caman_pivot.add_child(_caman)
	ShintyCaman.build(_caman, design, true)
	var tapes := [ShintyCaman.color(design, "grip"), ShintyCaman.color(design, "grip2"),
		ShintyCaman.color(design, "bas_tape"), ShintyCaman.color(design, "band")]
	for i in _rolls.size():
		_rolls[i].material_override = ShintyMesh.tape(tapes[i])
	_rolls[1].visible = design["wrap"]
	_rolls[3].visible = design["bands"] > 0
	var hc := helmet_color()
	var key := hc.to_html()
	if key != _helmet_key:
		_helmet_key = key
		for c in _helmet_holder.get_children():
			c.queue_free()
		var kit := ShintyPlayerModel.kit_from_team(team, false)
		ShintyCamanBench.helmet(_helmet_holder, hc, kit["trim"])


func helmet_color() -> Color:
	if str(design.get("helmet", "")) != "":
		return Color(str(design["helmet"]))
	return ShintyPlayerModel.kit_from_team(team, false)["helmet"]


func _process(delta: float) -> void:
	_time += delta
	_spin += delta * _spin_speed
	if _caman_pivot:
		_caman_pivot.rotation.x = _spin


# --- Pieces -------------------------------------------------------------------------

## The players' own helmet (ShintyPlayerLook), built on its own on `parent`,
## so the bench shows the same helmet the players wear.
static func helmet(parent: Node3D, color: Color, trim: Color) -> void:
	var model := ShintyPlayerModel.new()
	model.helmet_color = color
	model.trim_color = trim
	var look := ShintyPlayerLook.new()
	look.m = model
	look.detail = true
	look.seg = 16
	look._helmet(parent, Vector3.ZERO)
	model.free()


func _build_bench() -> void:
	var wood := ShintyMesh.wood(Color("a07a52"), Color("6e4d31"))
	var steel := ShintyMesh.solid(Color("2b2f33"), 0.45, 0.7)
	# Three seat slats and one shelf slat underneath, rounded at the edges.
	for i in 3:
		var z := (i - 1) * (DEPTH / 3.0)
		_box(Vector3(LENGTH, 0.035, DEPTH / 3.0 - 0.012), Vector3(0, TOP_Y - 0.018, z), wood)
	_box(Vector3(LENGTH - 0.2, 0.025, 0.2), Vector3(0, 0.14, 0.04), wood)
	# Steel A-frame legs at each end and a rail below the seat.
	for sx in [-1.0, 1.0]:
		var x: float = sx * (LENGTH * 0.5 - 0.16)
		for sz in [-1.0, 1.0]:
			var leg := _box(Vector3(0.04, TOP_Y + 0.02, 0.04), Vector3(x, TOP_Y * 0.5 - 0.02, sz * (DEPTH * 0.5 - 0.06)), steel)
			leg.rotation.x = sz * 0.1
		_box(Vector3(0.04, 0.04, DEPTH - 0.06), Vector3(x, TOP_Y - 0.055, 0), steel)
		_box(Vector3(0.04, 0.03, DEPTH - 0.02), Vector3(x, 0.12, 0), steel)
	_box(Vector3(LENGTH - 0.3, 0.035, 0.035), Vector3(0, TOP_Y - 0.06, 0), steel)
	# A concrete pad under it, the kind dugouts and benches stand on.
	var slab := _box(Vector3(LENGTH + 0.9, 0.06, 1.2), Vector3(-0.1, 0.0, 0.12), ShintyMesh.solid(Color("6f6d68"), 0.95))
	slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A pair of padded pegs that hold the caman up level so it can turn.
func _build_stand() -> void:
	var steel := ShintyMesh.solid(Color("c9ccd1"), 0.3, 0.85)
	var pad := ShintyMesh.solid(Color("1c1d21"), 0.85)
	var y := TOP_Y + 0.3
	for x in [-0.34, 0.26]:
		_box(Vector3(0.12, 0.012, 0.1), Vector3(x, TOP_Y + 0.006, -0.02), steel)
		var post := MeshInstance3D.new()
		post.mesh = ShintyMesh.loft([[TOP_Y, 0.007, 0.007], [y - 0.03, 0.007, 0.007]], 10)
		post.material_override = steel
		post.position = Vector3(x, 0, -0.02)
		add_child(post)
		# A small cradle the shaft rests in.
		var cradle := MeshInstance3D.new()
		cradle.mesh = ShintyMesh.sweep(PackedVector3Array([Vector3(0, 0.03, -0.028), Vector3(0, -0.005, 0), Vector3(0, 0.03, 0.028)]),
			PackedVector2Array([Vector2(0.008, 0.012), Vector2(0.008, 0.012), Vector2(0.008, 0.012)]), 8, 2.0, false, Vector3.RIGHT)
		cradle.material_override = pad
		cradle.position = Vector3(x, y - 0.03, -0.02)
		add_child(cradle)
	_caman_pivot = Node3D.new()
	_caman_pivot.position = Vector3(0, y, -0.02)
	add_child(_caman_pivot)


func _build_props() -> void:
	# Tape rolls on the seat: grip, second tape, bas tape, band paint.
	var spots := [Vector3(0.26, 0, 0.12), Vector3(0.39, 0, 0.13), Vector3(0.34, 0, 0.0), Vector3(0.47, 0, 0.05)]
	var roll := _tape_roll_mesh()
	for i in spots.size():
		var mi := MeshInstance3D.new()
		mi.mesh = roll
		mi.position = spots[i] + Vector3(0, TOP_Y + 0.015, 0)
		if i == 2:
			mi.rotation = Vector3(0.0, 0.4, PI / 2 - 0.25)  # stood on its edge
			mi.position.y = TOP_Y + 0.055
		add_child(mi)
		_rolls.append(mi)
	# The club helmet at the far end of the seat, looking out at the pitch.
	_helmet_holder = Node3D.new()
	_helmet_holder.position = Vector3(0.66, TOP_Y + 0.115, -0.02)
	_helmet_holder.rotation.y = PI - 0.75  # cage turned towards the camera
	_helmet_holder.scale = Vector3.ONE * 1.05
	add_child(_helmet_holder)
	# Spare camans leaning on the near end of the bench.
	for i in 2:
		var spare := Node3D.new()
		ShintyCaman.build(spare, {"wood": 1 - i, "grip": ["#141417", "#f2f2f0"][i], "bas_tape": "#141417"}, true)
		# Butt resting on the end of the seat, bas on the grass.
		spare.position = Vector3(-LENGTH * 0.5 + 0.03, ShintyPlayerModel.CAMAN_LENGTH * 0.99, 0.1 - i * 0.2)
		spare.rotation = Vector3(0.0, PI * 0.5 + 0.3 - i * 0.6, 0.0)
		spare.rotate_object_local(Vector3.RIGHT, 0.0)
		spare.rotate(Vector3(0, 0, 1), 0.22)
		add_child(spare)
	# A water bottle under the seat.
	var bottle := MeshInstance3D.new()
	bottle.mesh = ShintyMesh.loft([[0.0, 0.034, 0.034], [0.19, 0.036, 0.036], [0.21, 0.025, 0.025], [0.24, 0.012, 0.012], [0.25, 0.012, 0.012]], 14)
	bottle.material_override = ShintyMesh.solid(Color("3a8fd6"), 0.3, 0.0, 0.6)
	bottle.position = Vector3(-0.35, 0.153, 0.05)
	add_child(bottle)


func _tape_roll_mesh() -> ArrayMesh:
	var pts := PackedVector3Array()
	var rad := PackedVector2Array()
	for i in 25:
		var a := TAU * i / 24.0
		pts.append(Vector3(cos(a) * 0.04, 0.0, sin(a) * 0.04))
		rad.append(Vector2(0.016, 0.014))
	# Section: 0.013 thick across the roll's face, 0.012 radially. Lift so it
	# sits on y = 0.
	var m := ShintyMesh.sweep(pts, rad, 10, 4.0, true, Vector3.UP)
	return m


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi
