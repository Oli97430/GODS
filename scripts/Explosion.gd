extends Node3D
## Explosion brève (drone détruit) : sphère émissive additive qui enfle + flash lumineux, auto-libérée.

const LIFE := 0.55

var _t := 0.0
var _strength := 1.0
var _sphere: MeshInstance3D
var _mat: StandardMaterial3D
var _light: OmniLight3D

func play(strength: float) -> void:
	_strength = clampf(strength, 0.3, 2.0)

func _ready() -> void:
	_sphere = MeshInstance3D.new()
	_sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 10
	sm.rings = 6
	_sphere.mesh = sm
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.albedo_color = Color(1.0, 0.6, 0.2, 0.9)
	_sphere.material_override = _mat
	add_child(_sphere)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.3)
	_light.omni_range = 14.0
	_light.light_energy = 7.0
	_light.shadow_enabled = false
	add_child(_light)

func _process(delta: float) -> void:
	_t += delta
	var k := _t / LIFE
	if k >= 1.0:
		queue_free()
		return
	var r := lerpf(0.5, 3.6 * _strength, k)
	_sphere.scale = Vector3(r, r, r)
	_mat.albedo_color = Color(1.0, lerpf(0.6, 0.08, k), 0.08, (1.0 - k) * 0.9)
	_light.light_energy = (1.0 - k) * 7.0
