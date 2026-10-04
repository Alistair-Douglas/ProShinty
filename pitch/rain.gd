class_name ShintyRain
extends GPUParticles3D
## Falling rain around the camera. Only the drops near the lens are drawn
## (further off, the murk in the fog does the work), so it costs little: a
## few thousand thin quads, unshaded, on the GPU. The emitter follows the
## active camera each frame; drops already falling stay where they are.

var intensity := 1.0       ## 0..1: drizzle to a downpour
var wind := Vector3.ZERO   ## world units/s, slants the rain
var unit := 1.0            ## world units per yard
var quality := 1           ## ShintyPitch.Detail: how many drops

const FALL := 9.0          ## yards/s
const BOX := Vector3(18.0, 10.0, 18.0)   ## half extents of the rain around the camera, yards
const DROPS := [900, 1800, 3600]         ## at full intensity, by graphics quality


func _ready() -> void:
	amount = maxi(80, int(DROPS[clampi(quality, 0, 2)] * clampf(intensity, 0.1, 1.0)))
	lifetime = (BOX.y * 2.0) / FALL
	preprocess = lifetime
	local_coords = false
	fixed_fps = 30
	interpolate = true
	visibility_aabb = AABB(-BOX * unit * 2.0, BOX * unit * 4.0)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = BOX * unit
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = FALL * unit * 0.9
	pm.initial_velocity_max = FALL * unit * 1.1
	pm.gravity = wind * 0.6   # the wind carries the drops sideways
	process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.01, 0.38) * unit
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.8, 0.84, 0.9, lerpf(0.2, 0.3, intensity))
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.disable_receive_shadows = true
	mat.no_depth_test = false
	quad.material = mat
	draw_pass_1 = quad


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Centre the rain a little in front of the lens and above it.
	var fwd := -cam.global_transform.basis.z
	global_position = cam.global_position + fwd * BOX.x * 0.6 * unit + Vector3(0, BOX.y * 0.5 * unit, 0)
