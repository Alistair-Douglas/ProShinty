@tool
class_name ShintyAdBoard
extends Node3D
## A pitchside advertising board: a sponsor face on a dark frame with a
## brace behind. LED boards glow and roll to the next sponsor every few
## seconds; printed boards show one sponsor.
##
## The board stands on y = 0, runs along +X from x = 0 and faces +Z (put +Z
## towards the pitch). Sizes are in metres; set `unit_scale` to the world
## units per metre (1 / 0.9144 for a pitch built in yards).
## Sponsors come from data/sponsors.json (see ShintySponsors).

const Shader_ := preload("res://broadcast/ad_board.gdshader")

@export var length_m := 6.0:
	set(v): length_m = v; _queue()
@export var height_m := 0.9:
	set(v): height_m = v; _queue()
@export var unit_scale := 1.0:
	set(v): unit_scale = v; _queue()
## Sponsor ids to show, in order. Empty = every sponsor.
@export var sponsors: PackedStringArray = []:
	set(v): sponsors = v; _queue()
## Index into `sponsors` of the first advert, so neighbouring boards differ.
@export var start_index := 0:
	set(v): start_index = v; _queue()
@export var led := true:
	set(v): led = v; _queue()
## Seconds each advert stays up on an LED board (0 = never changes).
@export var change_seconds := 9.0

var _mat: ShaderMaterial
var _list: PackedStringArray = []
var _index := 0
var _timer := 0.0
var _slide := -1.0
var _pending := false


func _ready() -> void:
	_build()


func _queue() -> void:
	if is_inside_tree() and not _pending:
		_pending = true
		_build.call_deferred()


func _build() -> void:
	_pending = false
	for c in get_children():
		c.queue_free()
	_list = sponsors if not sponsors.is_empty() else ShintySponsors.ids()
	_index = posmod(start_index, maxi(_list.size(), 1))
	var s := unit_scale
	var L := length_m * s
	var H := height_m * s
	var lift := 0.06 * s  # gap under the board

	# Frame and the brace legs behind it (leaning back), as one mesh: one draw
	# call and one shadow caster per board.
	var st := SurfaceTool.new()
	st.append_from(_box_mesh(Vector3(L, H + 0.06 * s, 0.12 * s)), 0,
		Transform3D(Basis(), Vector3(L / 2.0, lift + H / 2.0, -0.07 * s)))
	for x in [0.35 * s, L - 0.35 * s]:
		st.append_from(_box_mesh(Vector3(0.06 * s, H * 1.1, 0.06 * s)), 0,
			Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(x, H * 0.5, -0.45 * s)))
	var body := MeshInstance3D.new()
	body.name = "Frame"
	body.mesh = st.commit()
	body.material_override = _frame_material()
	add_child(body)

	_mat = ShaderMaterial.new()
	_mat.shader = Shader_
	var seg := height_m * 6.7  # one advert is about 6.7 times as long as it is high
	_mat.set_shader_parameter("repeats", maxf(1.0, roundf(length_m / seg)))
	_mat.set_shader_parameter("glow", 0.55 if led else 0.0)
	_mat.set_shader_parameter("slide", 0.0)
	_set_textures(_index, _index)
	var face := MeshInstance3D.new()
	face.name = "Face"
	var q := QuadMesh.new()
	q.size = Vector2(L - 0.04 * s, H)
	face.mesh = q
	face.material_override = _mat
	face.position = Vector3(L / 2.0, lift + H / 2.0 + 0.03 * s, 0.0)
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(face)
	_timer = change_seconds * (0.5 + 0.1 * (start_index % 5))


func _set_textures(a: int, b: int) -> void:
	if _list.is_empty():
		return
	_mat.set_shader_parameter("tex_a", ShintySponsors.board_texture(_list[a % _list.size()]))
	_mat.set_shader_parameter("tex_b", ShintySponsors.board_texture(_list[b % _list.size()]))


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not led or change_seconds <= 0.0 or _list.size() < 2 or _mat == null:
		return
	if _slide >= 0.0:
		_slide += delta / 0.6
		if _slide >= 1.0:
			_slide = -1.0
			_index = (_index + 1) % _list.size()
			_set_textures(_index, _index)
			_mat.set_shader_parameter("slide", 0.0)
		else:
			_mat.set_shader_parameter("slide", ease(_slide, -2.0))
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = change_seconds
		_set_textures(_index, _index + 1)
		_slide = 0.0


func _box_mesh(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static var _frame_mat: StandardMaterial3D

## Shared by every board, so the renderer can draw the frames back to back.
static func _frame_material() -> StandardMaterial3D:
	if _frame_mat == null:
		_frame_mat = StandardMaterial3D.new()
		_frame_mat.albedo_color = Color(0.08, 0.09, 0.1)
		_frame_mat.roughness = 0.6
	return _frame_mat


## Lines boards up from `from` to `to` (on the ground, world units), facing
## `toward` (a point on the pitch), with a small gap between boards. Returns
## the boards added under `parent`. This is how a ground places its boards.
static func place_row(parent: Node3D, from: Vector3, to: Vector3, toward: Vector3, unit_scale := 1.0,
		board_m := 6.0, led_boards := true, first := 0) -> Array:
	var out := []
	var span := to - from
	var dist := span.length()
	var step := (board_m + 0.3) * unit_scale
	var n := int(dist / step)
	if n < 1:
		return out
	var dir := span / dist
	# Local +X runs along the row and +Z faces the pitch; run the row the other
	# way if needed so the basis stays right-handed (text reads correctly).
	var normal := Vector3(-dir.z, 0, dir.x)
	if normal.dot(toward - from) < 0.0:
		dir = -dir
		normal = -normal
		from = to
	var start := from + dir * (dist - n * step) * 0.5
	for i in n:
		var b := ShintyAdBoard.new()
		b.length_m = board_m
		b.unit_scale = unit_scale
		b.led = led_boards
		b.start_index = first + i
		# Local +X along the row, +Z towards the pitch.
		b.transform = Transform3D(Basis(dir, Vector3.UP, normal), start + dir * i * step)
		parent.add_child(b)
		out.append(b)
	return out
