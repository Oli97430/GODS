class_name PlanetView
extends Node3D
## Vue planète : instancie le mesh procédural baké (ArrayMesh statique), tourne
## lentement sur elle-même et expose l'API de sélection (inerte : à l'échelle
## planète on observe la surface, il n'y a pas de cible à sélectionner). La
## transform de ce node est manipulée par NavigationController à l'échelle PLANET.

var selected_index: int = -1  # aucune cible sélectionnable à cette échelle
var _seed_local := 0           # phase 23 : seed courant (pour rebâtir le mesh érodé quand la FlowMap arrive)

@onready var _planet: MeshInstance3D = $Planet
@onready var _sun: DirectionalLight3D = $SunLight

var _atmosphere: PlanetAtmosphere
var _planet_ocean: PlanetOcean
var _moons: Array = []   # phase 14 : MoonRenderer de la planète courante (orbite proche)
var _ring: RingRenderer  # phase 14 : anneau (ou null) de la planète courante

func _ready() -> void:
	# Soleil orbital FIXE = direction inertielle de l'étoile (TimeOfDay). La planète tourne
	# sous lui (jour/nuit). _sun.basis.z = direction vers le soleil (lu par les shaders).
	var z := TimeOfDay.SUN_WORLD_DIR.normalized()
	var x := Vector3.UP.cross(z)
	if x.length() < 0.01:
		x = Vector3.RIGHT.cross(z)
	x = x.normalized()
	_sun.basis = Basis(x, z.cross(x).normalized(), z)
	_sun.shadow_enabled = false   # pas d'ombres : mobile-friendly
	_sun.light_energy = 1.3
	# Océan orbital (phase 11) : sphère d'eau au niveau de mer, enfant de la vue.
	_planet_ocean = PlanetOcean.new()
	add_child(_planet_ocean)
	# Couches de ciel (phase 4), enfants de la vue (suivent la nav, pas l'auto-rotation).
	_atmosphere = PlanetAtmosphere.new()
	add_child(_atmosphere)

# Bake et installe le mesh de la planète à partir de son seed_local (déterministe).
func build(seed_local: int) -> void:
	_seed_local = seed_local   # phase 23 : retenu pour apply_flow_map (rebuild érodé)
	# Période/axe/heure de rotation déterministes pour cette planète (source de temps unique).
	TimeOfDay.configure_planet(seed_local)
	# Météo déterministe de la planète (couverture nuageuse variable vue d'orbite).
	WeatherSystem.configure_planet(seed_local)
	_planet.mesh = PlanetGenerator.generate(seed_local)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true   # biomes via couleurs de vertices
	mat.roughness = 0.95
	mat.metallic = 0.0
	_planet.material_override = mat
	_planet.rotation = Vector3.ZERO
	# Océan orbital (même seed) : niveau de mer + teinte partagés avec la surface.
	_planet_ocean.setup(seed_local, PlanetGenerator.DEFAULT_RADIUS, _sun)
	# Couches de ciel (atmosphère + nuages) dérivées du même seed_local.
	_atmosphere.setup(PlanetGenerator.DEFAULT_RADIUS, seed_local, _sun)
	# Lunes (phase 14) : régénérées du seed (mêmes que SystemView), orbitent via TimeOfDay.
	_build_moons(seed_local)
	_build_ring(seed_local)

# Phase 23 : la carte hydrologique (générée off-thread) est prête -> rebâtit le SEUL mesh terrain avec
# l'érosion (vallées adoucies) + rivières/lacs teintés en eau. Matériau/océan/atmo/lunes inchangés.
func apply_flow_map(fm: PlanetFlowMap) -> void:
	if fm == null or _seed_local == 0:
		return
	# Mesh pré-baké dans le worker (off-thread) si dispo => assignation instantanée ; sinon bake de secours.
	if fm.orbital_mesh != null:
		_planet.mesh = fm.orbital_mesh
	else:
		_planet.mesh = PlanetGenerator.generate(_seed_local, PlanetGenerator.DEFAULT_SUBDIVISIONS, PlanetGenerator.DEFAULT_AMPLITUDE, PlanetGenerator.DEFAULT_SEA_LEVEL, PlanetGenerator.DEFAULT_NOISE_FREQ, PlanetGenerator.DEFAULT_RADIUS, fm)

# (Re)crée l'anneau de la planète (si présent), à l'échelle orbite, rétro-éclairé par _sun.
func _build_ring(seed_local: int) -> void:
	if _ring:
		_ring.queue_free()
		_ring = null
	var rd = MoonsGenerator.generate_ring(seed_local)
	if rd != null:
		_ring = RingRenderer.new()
		add_child(_ring)
		_ring.setup(rd, PlanetGenerator.DEFAULT_RADIUS, _sun)

# (Re)crée les lunes de la planète à l'échelle orbite (rayon = DEFAULT_RADIUS), éclairées par _sun.
func _build_moons(seed_local: int) -> void:
	_clear_moons()
	for moon in MoonsGenerator.generate_moons(seed_local):
		var mr := MoonRenderer.new()
		add_child(mr)
		mr.setup(moon, PlanetGenerator.DEFAULT_RADIUS)
		_moons.append(mr)

func _clear_moons() -> void:
	for mr in _moons:
		mr.queue_free()
	_moons.clear()

# Rayon de la planète (pour les seuils de transition de distance).
func planet_radius() -> float:
	return PlanetGenerator.DEFAULT_RADIUS

# Rotation propre lente (en pause quand la vue est masquée).
func _process(_delta: float) -> void:
	if not visible:
		return
	# Rotation pilotée par la source de temps unique (jour/nuit synchrone avec le sol).
	_planet.basis = TimeOfDay.spin_basis()
	# Lunes en orbite autour du centre de la planète (origine locale), même horloge.
	for mr in _moons:
		mr.update_state(TimeOfDay.simulated_seconds, Vector3.ZERO)

# --- API générique de sélection (inerte : on observe seulement la surface) ---

func select_nearest(_origin: Vector3, _dir: Vector3) -> int:
	return -1

func get_selection_text(_index: int) -> String:
	return ""

func get_selection_world_position(_index: int) -> Vector3:
	return global_position

# Intersection rayon-sphère : renvoie la direction unitaire LOCALE du point visé sur
# la planète (annule la rotation propre + la transform de la vue), ou Vector3.ZERO si
# le rayon manque la planète. Sert de coordonnée d'atterrissage (phase 6).
func get_landing_direction(origin: Vector3, dir: Vector3) -> Vector3:
	dir = dir.normalized()
	var center := global_position
	var r := PlanetGenerator.DEFAULT_RADIUS * global_transform.basis.get_scale().x
	var oc := origin - center
	var b := oc.dot(dir)
	var c := oc.dot(oc) - r * r
	var disc := b * b - c
	if disc < 0.0:
		return Vector3.ZERO
	var sq := sqrt(disc)
	var t := -b - sq
	if t < 0.0:
		t = -b + sq
	if t < 0.0:
		return Vector3.ZERO
	var hit := origin + dir * t
	# Repasse en espace local de la planète (mesh tournant) => point fixe à la surface.
	return (_planet.global_transform.affine_inverse() * hit).normalized()
