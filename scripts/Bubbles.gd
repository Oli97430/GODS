extends MultiMeshInstance3D
## Bulles sous-marines : petites sphères translucides (rim fresnel) qui MONTENT autour du joueur et sont
## recyclées en bas quand elles percent le plafond du volume. player-relative (top_level => insensible au
## rebase). Visibles seulement SOUS L'EAU. AUTO-CONTENU. CPU léger (N petit). Piloté par SurfaceView.

const N := 40
const RADIUS := 4.0
const Y_LOW := -1.5
const Y_HIGH := 6.0
const RISE_MIN := 0.7    # m/s
const RISE_MAX := 1.5

var _pos: PackedVector3Array
var _spd: PackedFloat32Array
var _rng := RandomNumberGenerator.new()
var _t := 0.0

func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rng.randomize()
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 6
	sm.rings = 4
	multimesh.mesh = sm
	multimesh.instance_count = N
	_pos = PackedVector3Array()
	_pos.resize(N)
	_spd = PackedFloat32Array()
	_spd.resize(N)
	for i in N:
		_respawn(i, true)
	var smat := ShaderMaterial.new()
	smat.shader = preload("res://shaders/bubble.gdshader")
	material_override = smat
	visible = false

func _respawn(i: int, anywhere: bool) -> void:
	var ang := _rng.randf() * TAU
	var rad := sqrt(_rng.randf()) * RADIUS
	var y := _rng.randf_range(Y_LOW, Y_HIGH) if anywhere else Y_LOW
	_pos[i] = Vector3(cos(ang) * rad, y, sin(ang) * rad)
	_spd[i] = _rng.randf_range(RISE_MIN, RISE_MAX)
	var sc := _rng.randf_range(0.03, 0.07)
	multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(sc, sc, sc)), _pos[i]))

func update(center: Vector3, submerged: float, delta: float) -> void:
	if submerged < 0.08:
		if visible:
			visible = false
		return
	visible = true
	global_transform = Transform3D(Basis(), center)
	var dt := minf(delta, 0.05)
	_t += dt
	# Plafond = la SURFACE (Y monde 0) si elle est plus basse que Y_HIGH : les bulles éclatent en arrivant
	# à la surface (local = -center.y), pas en plein air au-dessus.
	var ceil_y := minf(Y_HIGH, -center.y)
	for i in N:
		var p := _pos[i]
		p.y += _spd[i] * dt
		# léger zigzag latéral (les bulles ne montent pas droit)
		p.x += sin(_t * 2.3 + float(i)) * 0.12 * dt
		p.z += cos(_t * 1.9 + float(i) * 1.7) * 0.12 * dt
		if p.y > ceil_y:
			_respawn(i, false)
			continue
		_pos[i] = p
		var sc: float = (multimesh.get_instance_transform(i).basis.get_scale()).x
		multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(sc, sc, sc)), p))
