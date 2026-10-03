extends Camera3D
## Look around the pitch. Drag with the left mouse button to orbit, scroll to
## zoom, WASD to move the focus point. Number keys jump to set views:
## 1 broadcast, 2 behind the west hail, 3 behind the east hail,
## 4 from the north touchline looking south, 5 aerial, 6 the match camera.
## L cycles the lighting preset, V switches the ground.

@export var pitch_path: NodePath

var focus := Vector3.ZERO
var yaw := 0.0
var pitch := -0.35
var distance := 110.0
var _dragging := false


func _ready() -> void:
	set_view(1)


func set_view(n: int) -> void:
	match n:
		1: _set_cam(Vector3(0, 0, 0), 0.0, -0.42, 52.0)
		2: _set_cam(Vector3(-55, 0, 0), -PI * 0.5, -0.12, 40.0)
		3: _set_cam(Vector3(55, 0, 0), PI * 0.5, -0.12, 40.0)
		4: _set_cam(Vector3(0, 1.5, -28), PI, -0.08, 8.0)
		5: _set_cam(Vector3(0, 0, -20), 0.35, -0.75, 330.0)
		6: _set_cam(Vector3(0, 0, 0), 0.0, -0.61, 33.6)
	_apply()


func _set_cam(f: Vector3, y: float, p: float, d: float) -> void:
	focus = f
	yaw = y
	pitch = p
	distance = d


func _apply() -> void:
	var offset := Basis.from_euler(Vector3(pitch, yaw, 0)) * Vector3(0, 0, distance)
	look_at_from_position(focus + offset, focus)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			_dragging = e.pressed
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = max(distance * 0.9, 5.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = min(distance * 1.1, 800.0)
		_apply()
	elif e is InputEventMouseMotion and _dragging:
		yaw -= e.relative.x * 0.005
		pitch = clamp(pitch - e.relative.y * 0.005, -1.5, -0.02)
		_apply()
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.keycode >= KEY_1 and e.keycode <= KEY_6:
			set_view(e.keycode - KEY_0)
		elif e.keycode == KEY_L:
			var p := get_node(pitch_path)
			p.lighting = (p.lighting + 1) % ShintyPitch.Lighting.size()
		elif e.keycode == KEY_V:
			var p := get_node(pitch_path)
			p.venue = (p.venue + 1) % ShintyPitch.VENUE_NAMES.size()


func _process(delta: float) -> void:
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move.z -= 1
	if Input.is_key_pressed(KEY_S): move.z += 1
	if Input.is_key_pressed(KEY_A): move.x -= 1
	if Input.is_key_pressed(KEY_D): move.x += 1
	if move != Vector3.ZERO:
		focus += Basis(Vector3.UP, yaw) * move.normalized() * delta * 40.0
		_apply()
