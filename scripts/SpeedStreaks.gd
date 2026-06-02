extends MultiMeshInstance3D
## Lignes de vitesse "Iron Man" : motes étirées qui défilent autour de la caméra pendant le vol libre,
## orientées le long du mouvement et accélérées avec la vitesse => impression de vitesse (bureau ET XR).
## Piloté par PlayerController._fly ; s'estompe quand on ne vole plus. `top_level` => positionné à la
## caméra chaque frame, les motes vivent en repère caméra (boîte torique recentrée).

const N := 130       # nombre de motes (discret)
const BOX := 7.0     # demi-étendue de la boîte (m) autour de la caméra
const LEN := 1.5     # longueur de base d'une mote (m), étirée par la vitesse

var _pos := PackedVector3Array()
var _intensity := 0.0

func _ready() -> void:
	top_level = true   # ignore la transform parente : on place le node à la caméra nous-mêmes
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mm.mesh = box
	mm.instance_count = N
	multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD          # additif : RGB de l'instance module l'intensité
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat
	visible = false
	_pos.resize(N)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xC0FFEE
	for i in N:
		_pos[i] = Vector3(rng.randf_range(-BOX, BOX), rng.randf_range(-BOX, BOX), rng.randf_range(-BOX, BOX))
		multimesh.set_instance_color(i, Color(0, 0, 0))

# cam : caméra active ; world_vel : vitesse monde ; speed_frac 0..1 ; delta s. No-op si cam nulle.
func update_streaks(cam: Camera3D, world_vel: Vector3, speed_frac: float, delta: float) -> void:
	if cam == null:
		visible = false
		return
	_intensity = move_toward(_intensity, clampf(speed_frac, 0.0, 1.0), delta * 3.0)
	if _intensity < 0.02:
		visible = false
		return
	visible = true
	global_transform = Transform3D(cam.global_transform.basis, cam.global_position)
	var lv := cam.global_transform.basis.inverse() * world_vel   # vitesse en repère caméra
	var dir := lv.normalized() if lv.length() > 0.05 else Vector3(0, 0, -1)
	var basis := _streak_basis(dir, LEN * (0.35 + 1.7 * _intensity))
	var k := _intensity * _intensity   # courbe : quasi invisible en croisière, présent à pleine vitesse
	var col := Color(0.28 * k, 0.38 * k, 0.56 * k)   # additif faible (discret)
	var step := lv * delta
	for i in N:
		var p: Vector3 = _pos[i] - step          # défile à l'opposé du mouvement (rush vers l'arrière)
		p.x = wrapf(p.x, -BOX, BOX)
		p.y = wrapf(p.y, -BOX, BOX)
		p.z = wrapf(p.z, -BOX, BOX)
		_pos[i] = p
		multimesh.set_instance_transform(i, Transform3D(basis, p))
		multimesh.set_instance_color(i, col)

# Base qui aligne l'axe Z local sur `dir` (mote fine en X/Y, longue en Z).
func _streak_basis(dir: Vector3, length: float) -> Basis:
	var z := dir
	var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	return Basis(x * 0.03, y * 0.03, z * length)
