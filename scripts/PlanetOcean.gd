class_name PlanetOcean
extends MeshInstance3D
## Sphère d'océan ORBITALE au niveau de mer (enfant de PlanetView). Shader water_orbit ;
## teinte/soleil dérivés du seed. Posée un poil AU-DESSUS du sol marin plat (anti z-fight) :
## les basses terres passent sous l'eau, les hautes émergent — le z-buffer fait le tri
## avec la sphère terrain (qui l'intersecte).

const WATER_SHADER := preload("res://shaders/water_orbit.gdshader")
const RADIUS_EPSILON := 1.0015   # légèrement au-dessus du niveau de mer (couvre le sol marin plat)

var _mat: ShaderMaterial
var _sun: DirectionalLight3D

func setup(seed_local: int, _planet_radius: float, sun: DirectionalLight3D) -> void:
	_sun = sun
	var r := PlanetGenerator.sea_level_radius(seed_local) * RADIUS_EPSILON
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 48
	sm.rings = 32
	mesh = sm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = WATER_SHADER
	_mat.set_shader_parameter("water_color", PlanetGenerator.water_color(seed_local))
	material_override = _mat

func _process(_dt: float) -> void:
	if _mat == null or not is_visible_in_tree():
		return
	_mat.set_shader_parameter("wave_time", float(Time.get_ticks_msec()) * 0.001)
	if _sun:
		_mat.set_shader_parameter("sun_direction", _sun.global_transform.basis.z)
