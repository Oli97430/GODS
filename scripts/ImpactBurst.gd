extends Node3D
## Atterrissage de PUISSANCE (style Iron Man / Hulk) : à l'impact d'une chute rapide :
##   • une gerbe de DÉBRIS s'envole (gravité + tumble),
##   • une ONDE DE CHOC de poussière s'étale au sol (anneau additif),
##   • un DÔME DE POUSSIÈRE s'élève et s'estompe (cloud).
## AUTO-CONTENU, poolé (un seul node rejoué via play()). Sous-meshes top_level => positions MONDE absolues
## le temps du burst (~1.2 s => insensible au rebase). Déclenché par PlayerController.impact via SurfaceView.

const DEBRIS_N := 36
const LIFE := 1.25         # s : durée du burst
const GRAVITY := 18.0

var _t := 1e9              # > LIFE => inactif
var _strength := 1.0
var _pos: PackedVector3Array
var _vel: PackedVector3Array
var _rot: PackedVector3Array
var _spin: PackedVector3Array
var _scl: PackedFloat32Array
var _debris: MultiMeshInstance3D
var _ring: MeshInstance3D
var _ring_mat: ShaderMaterial
var _dome: MeshInstance3D
var _dome_mat: ShaderMaterial
var _origin := Vector3.ZERO
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	# Débris : MultiMesh de petits cailloux (box) qui s'envolent.
	_debris = MultiMeshInstance3D.new()
	_debris.top_level = true
	_debris.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_debris.multimesh = MultiMesh.new()
	_debris.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 0.8, 1.2)
	_debris.multimesh.mesh = bm
	_debris.multimesh.instance_count = DEBRIS_N
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.22, 0.19, 0.16)
	rock.roughness = 1.0
	_debris.material_override = rock
	_debris.visible = false
	add_child(_debris)
	# Onde de choc : disque horizontal additif qui s'étale.
	_ring = MeshInstance3D.new()
	_ring.top_level = true
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0, 2.0)
	_ring.mesh = pm
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = preload("res://shaders/shockwave.gdshader")
	_ring.material_override = _ring_mat
	_ring.visible = false
	add_child(_ring)
	# Dôme de poussière : demi-sphère translucide qui s'élève + s'étale.
	_dome = MeshInstance3D.new()
	_dome.top_level = true
	_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 12
	sm.rings = 6
	_dome.mesh = sm
	_dome_mat = ShaderMaterial.new()
	_dome_mat.shader = preload("res://shaders/dust_puff.gdshader")
	_dome.material_override = _dome_mat
	_dome.visible = false
	add_child(_dome)
	# Buffers débris.
	_pos = PackedVector3Array(); _pos.resize(DEBRIS_N)
	_vel = PackedVector3Array(); _vel.resize(DEBRIS_N)
	_rot = PackedVector3Array(); _rot.resize(DEBRIS_N)
	_spin = PackedVector3Array(); _spin.resize(DEBRIS_N)
	_scl = PackedFloat32Array(); _scl.resize(DEBRIS_N)

# Déclenche un burst à la position d'impact. strength 0..1 (intensité de la chute).
func play(world_pos: Vector3, strength: float) -> void:
	_strength = clampf(strength, 0.0, 1.0)
	_t = 0.0
	_origin = world_pos
	for i in DEBRIS_N:
		var ang := _rng.randf() * TAU
		var out := Vector3(cos(ang), 0.0, sin(ang))
		var sp := (3.0 + _rng.randf() * 6.0) * (0.7 + _strength)
		var up := (3.0 + _rng.randf() * 5.0) * (0.7 + _strength)
		_vel[i] = out * sp + Vector3.UP * up
		_pos[i] = world_pos + Vector3(out.x * 0.35, 0.1, out.z * 0.35)
		_rot[i] = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)
		_spin[i] = Vector3(_rng.randf_range(-7.0, 7.0), _rng.randf_range(-7.0, 7.0), _rng.randf_range(-7.0, 7.0))
		_scl[i] = (0.06 + _rng.randf() * 0.13) * (0.7 + _strength)
		_debris.multimesh.set_instance_transform(i, Transform3D(Basis.from_euler(_rot[i]).scaled(Vector3(_scl[i], _scl[i], _scl[i])), _pos[i]))
	_debris.visible = true
	_ring.visible = true
	_ring.global_position = world_pos + Vector3.UP * 0.06
	_ring.scale = Vector3(0.5, 1.0, 0.5)
	_ring_mat.set_shader_parameter("alpha", 0.5 + 0.5 * _strength)
	_dome.visible = true
	_dome.global_position = world_pos + Vector3.UP * 0.2
	_dome.scale = Vector3(0.8, 0.5, 0.8)
	_dome_mat.set_shader_parameter("alpha", 0.45 + 0.35 * _strength)

func _process(delta: float) -> void:
	if _t > LIFE:
		if _debris.visible:
			_debris.visible = false
			_ring.visible = false
			_dome.visible = false
		return
	_t += delta
	var k := clampf(_t / LIFE, 0.0, 1.0)
	var dt := minf(delta, 0.05)
	# Débris : gravité + tumble.
	for i in DEBRIS_N:
		_vel[i].y -= GRAVITY * dt
		_pos[i] += _vel[i] * dt
		_rot[i] += _spin[i] * dt
		var s := _scl[i] * (1.0 - k * 0.3)
		_debris.multimesh.set_instance_transform(i, Transform3D(Basis.from_euler(_rot[i]).scaled(Vector3(s, s, s)), _pos[i]))
	# Onde de choc : s'étale + s'estompe.
	var rs := lerpf(0.6, 6.5 * (0.7 + _strength), k)
	_ring.scale = Vector3(rs, 1.0, rs)
	_ring_mat.set_shader_parameter("alpha", (1.0 - k) * (0.5 + 0.5 * _strength))
	# Dôme de poussière : s'élève + s'étale + s'estompe (plus vite que l'anneau).
	var ds := lerpf(0.9, 4.8 * (0.7 + _strength), k)
	_dome.scale = Vector3(ds, ds * 0.7, ds)
	_dome.global_position = _origin + Vector3.UP * (0.2 + k * 1.4)
	_dome_mat.set_shader_parameter("alpha", (1.0 - k * k) * (0.45 + 0.35 * _strength))
