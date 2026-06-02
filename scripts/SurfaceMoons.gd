class_name SurfaceMoons
extends Node3D
## Lunes vues depuis le SOL : pour chaque lune de la planète courante, un petit mesh placé sur
## la dôme du ciel à sa direction LOCALE cohérente (orbite + rotation planète + point
## d'atterrissage), dimensionné à sa taille angulaire (size_rel / orbit_rel), éclairé par
## l'étoile (lambert manuel => phases correctes, visible la nuit). Même repère que le soleil/
## starfield (tangent_basis au point d'atterrissage) => cohérence tri-échelle garantie.

const MOON_SHADER := preload("res://shaders/surface_moon.gdshader")
const MOON_SUBDIV := 3
const MOON_SEA_LEVEL := -10.0
const DOME_DIST := 2900.0   # < far (4000), au-delà du terrain (2 km)

var _player: Node3D
var _landing_dir := Vector3.UP
var _moons := []   # Array de { data, mesh, mat }

# (Re)crée les meshes de lune (mêmes seeds que l'orbite) pour le point d'atterrissage donné.
func setup(moons: Array, landing_dir: Vector3, player: Node3D) -> void:
	_clear()
	_player = player
	_landing_dir = landing_dir.normalized()
	for moon in moons:
		var mi := MeshInstance3D.new()
		mi.mesh = PlanetGenerator.generate(moon.seed_local, MOON_SUBDIV, PlanetGenerator.DEFAULT_AMPLITUDE, MOON_SEA_LEVEL)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = DOME_DIST   # mesh centré loin : évite le culling agressif
		var mat := ShaderMaterial.new()
		mat.shader = MOON_SHADER
		var rng := RandomNumberGenerator.new()
		rng.seed = moon.seed_local + 31   # même teinte que MoonRenderer (cohérence)
		var tint := Color.from_hsv(rng.randf_range(0.04, 0.12), rng.randf_range(0.05, 0.25), rng.randf_range(0.55, 0.80))
		mat.set_shader_parameter("rock_tint", Vector3(tint.r, tint.g, tint.b))
		mi.material_override = mat
		add_child(mi)
		_moons.append({"data": moon, "mesh": mi, "mat": mat})

func _clear() -> void:
	for m in _moons:
		m.mesh.queue_free()
	_moons.clear()

func _process(_dt: float) -> void:
	if GameState.current_scale != GameState.Scale.SURFACE:
		return   # node de surface : pas de calcul de ciel (trig/matrices/shaders) hors-surface
	if _player == null or _moons.is_empty():
		return
	var t: float = TimeOfDay.simulated_seconds
	var p_in: Vector3 = TimeOfDay.spin_basis() * _landing_dir       # point d'atterrissage (inertiel)
	var tb: Basis = FloatingOrigin.tangent_basis(p_in).inverse()    # inertiel -> ciel local
	var sun_local: Vector3 = TimeOfDay.get_sun_direction_local(_landing_dir)
	var ppos: Vector3 = _player.global_position
	for m in _moons:
		var moon = m.data
		var moff: Vector3 = MoonsGenerator.orbital_offset_rel(moon, t)
		var dir_local: Vector3 = (tb * (moff - p_in)).normalized()   # direction joueur -> lune (locale)
		var mi: MeshInstance3D = m.mesh
		mi.global_position = ppos + dir_local * DOME_DIST
		# Taille angulaire correcte : rayon angulaire = size_rel / orbit_rel.
		var f: float = DOME_DIST * (moon.size_rel / moon.orbit_rel) / PlanetGenerator.DEFAULT_RADIUS
		mi.scale = Vector3(f, f, f)
		mi.visible = dir_local.y > -0.05   # cachée sous l'horizon (couchée)
		m.mat.set_shader_parameter("sun_local", sun_local)
