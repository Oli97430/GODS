class_name SurfaceOcean
extends MeshInstance3D
## Plan d'eau de SURFACE : un grand plan horizontal au niveau de mer (Y monde), CENTRÉ sur
## le joueur (le suit chaque frame), dimensionné pour couvrir le rayon visuel. Le shader
## water_surface le COURBE pour suivre la sphère de mer (cohérent avec le terrain) et anime
## les vagues en espace MONDE (stables, ne « nagent » pas avec le joueur). Compatible origine
## flottante : comme il suit la position monde du joueur, il se recentre tout seul au rebase.

const WATER_SHADER := preload("res://shaders/water_surface.gdshader")
const PLANE_SIZE := 4500.0     # m : couvre le rayon visuel (~2 km) + marge de rebase
const SUBDIV := 128            # subdivisions (courbure lisse + vagues vertex)

var _mat: ShaderMaterial
var _sun: DirectionalLight3D
var _player: Node3D
var _sea_y := 0.0

func setup(seed_local: int, sun: DirectionalLight3D, player: Node3D, vertical_scale: float, planet_radius: float, sky_tint: Color) -> void:
	_sun = sun
	_player = player
	_sea_y = PlanetGenerator.sea_level_height(vertical_scale)
	var pm := PlaneMesh.new()
	pm.size = Vector2(PLANE_SIZE, PLANE_SIZE)
	pm.subdivide_width = SUBDIV
	pm.subdivide_depth = SUBDIV
	mesh = pm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = WATER_SHADER
	_mat.set_shader_parameter("water_color", PlanetGenerator.water_color(seed_local))
	_mat.set_shader_parameter("sky_tint", Vector3(sky_tint.r, sky_tint.g, sky_tint.b))
	_mat.set_shader_parameter("planet_radius", planet_radius)
	material_override = _mat
	visible = true

func _process(_dt: float) -> void:
	if _player == null or _mat == null:
		return
	# Suit le joueur en XZ, reste au niveau de mer en Y (=> se recentre au rebase).
	global_position = Vector3(_player.global_position.x, _sea_y, _player.global_position.z)
	_mat.set_shader_parameter("wave_time", float(Time.get_ticks_msec()) * 0.001)
	if _sun:
		_mat.set_shader_parameter("sun_direction", _sun.global_transform.basis.z)
		_mat.set_shader_parameter("sun_up", smoothstep(-0.08, 0.15, _sun.global_transform.basis.z.y))   # jour/nuit
