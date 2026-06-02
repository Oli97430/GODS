class_name MoonRenderer
extends Node3D
## Rend UNE lune : mesh baké via PlanetGenerator (subdiv basse, océan désactivé, palette
## rocheuse via shader), positionné sur son orbite circulaire et orienté (rotation propre ou
## verrouillage de marée) — le tout fonction de TimeOfDay.simulated_seconds (horloge unique).
## La position/orientation sont calculées en LOCAL (parent supposé à l'origine de la vue).

const MOON_SHADER := preload("res://shaders/moon.gdshader")
const MOON_SUBDIV := 3            # lunes = mesh léger (~642 sommets)
const MOON_SEA_LEVEL := -10.0     # pas d'océan : sol sec partout

var _moon                         # MoonsGenerator.MoonData
var _planet_radius := 30.0        # rayon planète dans l'échelle de la vue courante
var _mesh: MeshInstance3D
var _axis := Vector3.UP           # axe de rotation propre (non tidal)

# Bake + paramètre la lune pour un rayon planète donné (unités de la vue : système ou orbite).
func setup(moon, planet_radius: float) -> void:
	_moon = moon
	_planet_radius = planet_radius
	_mesh = MeshInstance3D.new()
	_mesh.mesh = PlanetGenerator.generate(moon.seed_local, MOON_SUBDIV, PlanetGenerator.DEFAULT_AMPLITUDE, MOON_SEA_LEVEL)
	var f: float = moon.size_rel * planet_radius / PlanetGenerator.DEFAULT_RADIUS
	_mesh.scale = Vector3(f, f, f)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = MOON_SHADER
	var rng := RandomNumberGenerator.new()
	rng.seed = moon.seed_local + 31
	var tint := Color.from_hsv(rng.randf_range(0.04, 0.12), rng.randf_range(0.05, 0.25), rng.randf_range(0.55, 0.80))
	mat.set_shader_parameter("rock_tint", Vector3(tint.r, tint.g, tint.b))
	_mesh.material_override = mat
	add_child(_mesh)
	_axis = Vector3(sin(moon.inclination) * 0.4, 1.0, 0.0).normalized()

# Met à jour position + orientation (LOCAL) pour l'instant simulé, autour d'un centre planète.
func update_state(simulated_seconds: float, planet_center: Vector3) -> void:
	var off := MoonsGenerator.orbital_offset_rel(_moon, simulated_seconds) * _planet_radius
	position = planet_center + off
	if _moon.tidal_locked:
		# Même face vers la planète : -Z pointe vers le centre (calcul local, sans look_at).
		var to_planet := planet_center - position
		if to_planet.length() > 0.0001:
			basis = _facing_basis(to_planet.normalized())
	else:
		basis = Basis(_axis, TAU * (simulated_seconds / _moon.spin_period))

# Base orthonormée dont -Z pointe vers 'fwd'.
func _facing_basis(fwd: Vector3) -> Basis:
	var z := -fwd
	var up := Vector3.UP
	if absf(z.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)

func moon_data():
	return _moon
