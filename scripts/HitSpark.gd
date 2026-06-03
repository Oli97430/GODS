extends Node3D
## Gerbe d'ÉTINCELLES d'impact (un projectile touche un drone) : éclats lumineux qui jaillissent dans toutes
## les directions, retombent (gravité) et s'éteignent, + bref flash. Couleur chaude métallique. AUTO-LIBÉRÉ.

const N := 10
const LIFE := 0.28
const GRAVITY := 16.0

var _mm: MultiMeshInstance3D
var _mat: StandardMaterial3D
var _light: OmniLight3D
var _pos: Array = []
var _vel: Array = []
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _pending := Vector3.ZERO

# Appelé AVANT add_child : position monde de l'impact.
func play(world_pos: Vector3) -> void:
	_pending = world_pos

func _ready() -> void:
	_rng.randomize()
	global_position = _pending
	_mm = MultiMeshInstance3D.new()
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(0.04, 0.04, 0.22)   # petits éclats allongés (streaks)
	mm.mesh = bm
	mm.instance_count = N
	_mm.multimesh = mm
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.albedo_color = Color(1.0, 0.85, 0.45, 1.0)
	_mm.material_override = _mat
	add_child(_mm)
	for i in N:
		var d := Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn())
		if d.length() < 0.01:
			d = Vector3.UP
		_vel.append(d.normalized() * _rng.randf_range(5.0, 13.0))
		_pos.append(Vector3.ZERO)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(0.01, 0.01, 0.01)), Vector3.ZERO))
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.8, 0.4)
	_light.omni_range = 3.0
	_light.light_energy = 5.0
	_light.shadow_enabled = false
	add_child(_light)

func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	var k := _t / LIFE
	for i in N:
		var v: Vector3 = _vel[i]
		v += Vector3.DOWN * GRAVITY * delta
		_vel[i] = v
		var p: Vector3 = _pos[i] + v * delta
		_pos[i] = p
		var sp := v.length()
		var b := Basis()
		if sp > 0.01:
			b = CombatUtil.look_basis(v / sp)
		var sc := clampf(1.0 - k, 0.12, 1.0)
		_mm.multimesh.set_instance_transform(i, Transform3D(b.scaled(Vector3(sc, sc, sc)), p))
	_mat.albedo_color = Color(1.0, 0.85, 0.45, 1.0 - k)
	if _light:
		_light.light_energy = (1.0 - k) * 5.0
