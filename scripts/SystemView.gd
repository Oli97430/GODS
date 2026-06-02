class_name SystemView
extends Node3D
## Rend un système stellaire : une étoile (sphère émissive + lumière) et 1 à 8
## planètes (sphères éclairées) en orbite circulaire dans le plan XZ. La transform
## de ce node EST « la transform de système » manipulée par NavigationController à
## l'échelle SYSTEM (comme GalaxyView à l'échelle GALAXY).

# Cône de sélection planète (en tangente) : large car peu de cibles.
const SELECT_MAX_TANGENT := 0.10
const HIGHLIGHT_EMISSION := 0.6   # énergie d'émission de la planète surlignée
const HIGHLIGHT_SCALE := 1.35     # agrandissement de la planète surlignée

var data: SystemGenerator.SystemData
var selected_index: int = -1

@onready var _star: MeshInstance3D = $Star
@onready var _star_light: OmniLight3D = $StarLight
@onready var _planets_root: Node3D = $PlanetsContainer

var _planet_nodes: Array = []      # MeshInstance3D par planète
var _planet_materials: Array = []  # StandardMaterial3D par planète
var _planet_moons: Array = []      # phase 14 : Array<MoonRenderer> par planète
var _time := 0.0

# (Re)construit l'étoile + les planètes à partir des données générées.
func build(system_data: SystemGenerator.SystemData) -> void:
	data = system_data
	selected_index = -1
	_time = 0.0
	_clear_planets()
	_build_star()
	_build_planets()

func _clear_planets() -> void:
	for n in _planet_nodes:
		n.queue_free()
	for moons in _planet_moons:
		for mr in moons:
			mr.queue_free()
	_planet_nodes.clear()
	_planet_materials.clear()
	_planet_moons.clear()

# Étoile : sphère non éclairée + émissive, et une omni-lumière unique (mobile).
func _build_star() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = data.star_radius
	mesh.height = data.star_radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	_star.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = data.star_color
	mat.emission_enabled = true
	mat.emission = data.star_color
	mat.emission_energy_multiplier = 1.5
	_star.material_override = mat

	_star_light.light_color = data.star_color
	_star_light.light_energy = 2.0
	_star_light.omni_range = 200.0
	_star_light.shadow_enabled = false

# Planètes : sphères éclairées colorées, créées sous PlanetsContainer.
func _build_planets() -> void:
	for i in data.planets.size():
		var p = data.planets[i]
		var mi := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = p.size
		mesh.height = p.size * 2.0
		mesh.radial_segments = 16
		mesh.rings = 8
		mi.mesh = mesh

		var mat := StandardMaterial3D.new()
		mat.albedo_color = p.color
		mat.roughness = 0.9
		mat.metallic = 0.0
		mi.material_override = mat

		_planets_root.add_child(mi)
		_planet_nodes.append(mi)
		_planet_materials.append(mat)
		# Phase 14 : lunes de cette planète (mesh baké, orbitent via TimeOfDay).
		var moons_for_p := []
		for moon in p.moons:
			var mr := MoonRenderer.new()
			_planets_root.add_child(mr)
			mr.setup(moon, p.size)
			moons_for_p.append(mr)
		_planet_moons.append(moons_for_p)
		# Phase 14 : anneau (enfant du node planète => suit sa position ; pas de directionnelle ici).
		if p.ring != null:
			var ring := RingRenderer.new()
			mi.add_child(ring)
			ring.setup(p.ring, p.size, null)
	_update_planet_positions()

# Place chaque planète sur son orbite à l'instant courant (étoile au centre, plan XZ).
func _update_planet_positions() -> void:
	for i in _planet_nodes.size():
		var p = data.planets[i]
		var ang: float = p.phase + p.orbit_speed * _time
		_planet_nodes[i].position = Vector3(cos(ang) * p.orbit_radius, 0.0, sin(ang) * p.orbit_radius)
		# Phase 14 : lunes orbitant autour de la planète, via l'horloge simulée unique.
		if i < _planet_moons.size():
			for mr in _planet_moons[i]:
				mr.update_state(TimeOfDay.simulated_seconds, _planet_nodes[i].position)

# Anime les orbites (en pause quand la vue est masquée, ex. en mode galaxie).
func _process(delta: float) -> void:
	if data == null or not visible:
		return
	_time += delta
	_update_planet_positions()

# ----------------------- SÉLECTION (API commune à GalaxyView) -----------------------

# Sélectionne la planète la plus proche du rayon (origin, dir) dans un cône.
# Met à jour le surlignage et renvoie l'index (-1 si aucune).
func select_nearest(origin: Vector3, dir: Vector3) -> int:
	dir = dir.normalized()
	var best := -1
	var best_score := SELECT_MAX_TANGENT
	for i in _planet_nodes.size():
		var wp: Vector3 = _planet_nodes[i].global_position
		var to_p := wp - origin
		var t := to_p.dot(dir)
		if t <= 0.0:
			continue  # planète derrière l'origine du rayon
		var perp := (to_p - dir * t).length()
		var score := perp / t  # tangente de l'angle au rayon
		if score < best_score:
			best_score = score
			best = i
	_apply_highlight(best)
	return best

# Surligne la planète sélectionnée (émission + léger agrandissement).
func _apply_highlight(index: int) -> void:
	if index == selected_index:
		return
	if selected_index >= 0 and selected_index < _planet_materials.size():
		_planet_materials[selected_index].emission_enabled = false
		_planet_nodes[selected_index].scale = Vector3.ONE
	if index >= 0:
		var mat: StandardMaterial3D = _planet_materials[index]
		mat.emission_enabled = true
		mat.emission = data.planets[index].color
		mat.emission_energy_multiplier = HIGHLIGHT_EMISSION
		_planet_nodes[index].scale = Vector3.ONE * HIGHLIGHT_SCALE
	selected_index = index

# Nom déterministe d'une planète (style exoplanète : b, c, d, ...).
func get_planet_display_name(index: int) -> String:
	return "Planète %s" % String.chr(98 + index)

# Texte d'info de la sélection : nom propre (phase 19.5) + taille + rayon orbital.
func get_selection_text(index: int) -> String:
	var p = data.planets[index]
	# Le nom propre prime ; repli sur la nomenclature « Planète b » si non généré (rétrocompatible).
	var nm: String = p.name if p.name != "" else get_planet_display_name(index)
	return "%s\nTaille %.2f   Orbite %.1f" % [nm, p.size, p.orbit_radius]

func get_selection_world_position(index: int) -> Vector3:
	return _planet_nodes[index].global_position

# (Section « VOL » phase 15 retirée avec le vaisseau : spawn/ciblage/bord système n'ont plus d'usage.)
