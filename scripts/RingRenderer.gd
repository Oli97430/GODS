class_name RingRenderer
extends MeshInstance3D
## Anneau planétaire : disque plat (PlaneMesh) en unités de rayon planète, mis à l'échelle au
## rayon de la planète et incliné de ring.tilt, masqué en couronne + densité variable par le
## shader ring.gdshader. Semi-transparent. Présent uniquement si la planète a un RingData.

const RING_SHADER := preload("res://shaders/ring.gdshader")

var _ring                     # MoonsGenerator.RingData
var _sun: Node3D              # source de lumière (DirectionalLight en orbite) ou null (système)
var _mat: ShaderMaterial

func setup(ring, planet_radius: float, sun: Node3D) -> void:
	_ring = ring
	_sun = sun
	var pm := PlaneMesh.new()
	var s: float = ring.outer_rel * 2.0   # taille en unités de rayon planète
	pm.size = Vector2(s, s)
	mesh = pm
	scale = Vector3(planet_radius, planet_radius, planet_radius)
	rotation = Vector3(ring.tilt, 0.0, 0.0)   # incline le plan de l'anneau
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = RING_SHADER
	_mat.set_shader_parameter("ring_tint", Vector3(ring.tint.r, ring.tint.g, ring.tint.b))
	_mat.set_shader_parameter("inner_radius", ring.inner_rel)
	_mat.set_shader_parameter("outer_radius", ring.outer_rel)
	_mat.set_shader_parameter("opacity", ring.opacity)
	_mat.set_shader_parameter("density_seed", float(ring.density_seed % 1000) / 1000.0)
	material_override = _mat

func _process(_dt: float) -> void:
	if not is_visible_in_tree():
		return   # anneau masqué (hors-PLANET / système caché) : pas de set_shader_parameter par frame
	# Direction de l'étoile pour le rétro-éclairage (si une lumière directionnelle est fournie).
	if _mat and _sun:
		_mat.set_shader_parameter("sun_direction", _sun.global_transform.basis.z)
