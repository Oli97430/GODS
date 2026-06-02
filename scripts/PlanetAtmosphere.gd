class_name PlanetAtmosphere
extends Node3D
## Couches de ciel d'une planète : une sphère d'atmosphère (halo fresnel) et une
## sphère de nuages, toutes deux enfants de PlanetView (donc suivent la navigation,
## mais PAS l'auto-rotation de la surface). Les paramètres (teinte, densité,
## couverture, vitesse, motif) sont dérivés du seed_local => ciel reproductible.
## La direction du soleil (partagée par les deux shaders) est mise à jour chaque
## frame depuis la lumière directionnelle de la planète.

const ATMO_SHADER := preload("res://shaders/atmosphere.gdshader")
const CLOUDS_SHADER := preload("res://shaders/clouds.gdshader")

# Rayons relatifs au rayon de base de la planète. Doivent rester au-dessus des pics
# de relief (≈ 1 + maxElevation*amplitude ≈ 1.08 avec les défauts du générateur).
const CLOUD_SCALE := 1.12
const ATMO_SCALE := 1.22

# Segments des sphères de ciel (lisses mais légères).
const SPHERE_SEGMENTS := 24
const SPHERE_RINGS := 16

var _atmo: MeshInstance3D
var _clouds: MeshInstance3D
var _atmo_mat: ShaderMaterial
var _clouds_mat: ShaderMaterial
var _sun: DirectionalLight3D

# Couleur d'atmosphère déterministe pour un seed (mêmes 2 premiers tirages que
# setup => valeur identique). Réutilisée par SurfaceView pour teinter le ciel au sol.
static func atmosphere_color_for(seed_local: int) -> Color:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_local + 9001
	return Color.from_hsv(rng.randf(), rng.randf_range(0.40, 0.70), 1.0)

# (Re)construit et paramètre les deux couches pour une planète de rayon donné.
func setup(planet_radius: float, seed_local: int, sun: DirectionalLight3D) -> void:
	_sun = sun
	_clear()

	# Aléa dérivé (graine distincte de la surface) => ciel propre mais reproductible.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_local + 9001

	var atmo_color := Color.from_hsv(rng.randf(), rng.randf_range(0.40, 0.70), 1.0)
	var density := rng.randf_range(0.6, 1.4)
	var coverage := rng.randf_range(0.35, 0.70)
	var speed_sign := 1.0 if rng.randf() < 0.5 else -1.0
	var cloud_speed := rng.randf_range(0.012, 0.035) * speed_sign
	var cloud_offset := Vector3(rng.randf() * 100.0, rng.randf() * 100.0, rng.randf() * 100.0)
	var cloud_tint := Color(1, 1, 1).lerp(atmo_color, 0.15)

	# --- Atmosphère (additive, au-dessus des nuages) ---
	_atmo = _make_sphere(planet_radius * ATMO_SCALE)
	_atmo_mat = ShaderMaterial.new()
	_atmo_mat.shader = ATMO_SHADER
	_atmo_mat.set_shader_parameter("atmo_color", atmo_color)
	_atmo_mat.set_shader_parameter("density", density)
	_atmo_mat.render_priority = 1  # dessinée après les nuages (tri stéréo déterministe)
	_atmo.material_override = _atmo_mat
	add_child(_atmo)

	# --- Nuages (alpha, juste au-dessus de la surface) ---
	_clouds = _make_sphere(planet_radius * CLOUD_SCALE)
	_clouds_mat = ShaderMaterial.new()
	_clouds_mat.shader = CLOUDS_SHADER
	_clouds_mat.set_shader_parameter("coverage", coverage)
	_clouds_mat.set_shader_parameter("cloud_speed", cloud_speed)
	_clouds_mat.set_shader_parameter("cloud_offset", cloud_offset)
	_clouds_mat.set_shader_parameter("cloud_color", cloud_tint)
	_clouds_mat.render_priority = 0
	_clouds.material_override = _clouds_mat
	add_child(_clouds)

	_apply_toggle()

func _clear() -> void:
	if _atmo:
		_atmo.queue_free()
		_atmo = null
	if _clouds:
		_clouds.queue_free()
		_clouds = null

func _make_sphere(radius: float) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = SPHERE_SEGMENTS
	mesh.rings = SPHERE_RINGS
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _process(_delta: float) -> void:
	# Rien à faire quand la planète n'est pas affichée.
	if _atmo == null or not is_visible_in_tree():
		return
	_apply_toggle()
	if not GameState.atmosphere_enabled:
		return
	# Direction VERS le soleil (monde), partagée par les deux shaders.
	var sun_dir := _sun.global_transform.basis.z if _sun else Vector3(0, 0, 1)
	_atmo_mat.set_shader_parameter("sun_direction", sun_dir)
	_clouds_mat.set_shader_parameter("sun_direction", sun_dir)
	# Couverture nuageuse pilotée par la météo (phase 13) : varie dans le temps vu d'orbite.
	if WeatherSystem.is_configured():
		_clouds_mat.set_shader_parameter("coverage", WeatherSystem.get_orbit_coverage())

# Applique le toggle global (active/désactive les deux couches d'un coup).
func _apply_toggle() -> void:
	var on := GameState.atmosphere_enabled
	if _atmo:
		_atmo.visible = on
	if _clouds:
		_clouds.visible = on
