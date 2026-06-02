class_name GalaxyView
extends MultiMeshInstance3D
## Affiche la galaxie en UN seul MultiMeshInstance3D (un point lumineux par
## système, jamais 400 nodes). Détient les GalaxyData et expose select_nearest().
##
## La transform de ce node EST « la transform de galaxie » manipulée par
## NavigationController (rotation / échelle / position), identique en bureau et XR.

const SYSTEM_COUNT := 400
const GALAXY_RADIUS := 50.0
const STAR_QUAD_SIZE := 1.0
# Demi-angle (en tangente) du cône de sélection autour du rayon visé.
const SELECT_MAX_TANGENT := 0.05

var data: GalaxyGenerator.GalaxyData
var selected_index: int = -1

const STAR_SHADER := preload("res://shaders/star_point.gdshader")

func _ready() -> void:
	data = GalaxyGenerator.generate(GameState.global_seed, SYSTEM_COUNT, GALAXY_RADIUS)
	_build_multimesh()
	print("[GalaxyView] Galaxie générée : ", data.systems.size(), " systèmes (seed=", GameState.global_seed, ").")

# Construit le MultiMesh : un quad billboardé par instance, coloré selon le type.
func _build_multimesh() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(STAR_QUAD_SIZE, STAR_QUAD_SIZE)

	var mat := ShaderMaterial.new()
	mat.shader = STAR_SHADER
	material_override = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = data.systems.size()

	for i in data.systems.size():
		var sys = data.systems[i]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, sys.position))
		mm.set_instance_color(i, GalaxyGenerator.star_color(sys.star_type))
		# Custom data : .r = flag de surlignage, .g = taille selon le type spectral.
		mm.set_instance_custom_data(i, Color(0.0, GalaxyGenerator.star_size(sys.star_type), 0.0, 0.0))

	multimesh = mm

# Sélectionne le système dont la direction est la plus proche du rayon (origin, dir),
# dans la limite d'un cône. Met à jour le surlignage et renvoie l'index (-1 si aucun).
func select_nearest(origin: Vector3, dir: Vector3) -> int:
	dir = dir.normalized()
	var gt := global_transform
	var best := -1
	var best_score := SELECT_MAX_TANGENT
	for i in data.systems.size():
		var world_pos: Vector3 = gt * data.systems[i].position
		var to_p := world_pos - origin
		var t := to_p.dot(dir)
		if t <= 0.0:
			continue  # système derrière l'origine du rayon
		var perp := (to_p - dir * t).length()
		var score := perp / t  # tangente de l'angle au rayon
		if score < best_score:
			best_score = score
			best = i
	_apply_highlight(best)
	return best

# Bascule le flag de surlignage (custom data .r) de l'ancien vers le nouveau système.
func _apply_highlight(index: int) -> void:
	if index == selected_index:
		return
	if selected_index >= 0 and selected_index < multimesh.instance_count:
		var c := multimesh.get_instance_custom_data(selected_index)
		c.r = 0.0
		multimesh.set_instance_custom_data(selected_index, c)
	if index >= 0:
		var c2 := multimesh.get_instance_custom_data(index)
		c2.r = 1.0
		multimesh.set_instance_custom_data(index, c2)
	selected_index = index

# --- Accès pour l'affichage de la sélection (NavigationController) ---

func get_system_world_position(index: int) -> Vector3:
	return global_transform * data.systems[index].position

func get_system_local_position(index: int) -> Vector3:
	return data.systems[index].position

# Nom déterministe et lisible (lettre de classe spectrale + identifiant catalogue).
func get_system_display_name(index: int) -> String:
	var sys = data.systems[index]
	return "%s-%04d" % [GalaxyGenerator.star_type_letter(sys.star_type), sys.id]

# --- API générique de sélection (utilisée par NavigationController, commune à SystemView) ---

# Texte d'info de la sélection : nom propre (phase 19.5) + classe spectrale + coordonnées locales.
func get_selection_text(index: int) -> String:
	var sys = data.systems[index]
	var lp := get_system_local_position(index)
	# Le nom propre prime ; classe spectrale en sous-titre discret (ton contemplatif, pas de code « G-0042 »).
	var nm: String = sys.name if sys.name != "" else get_system_display_name(index)
	return "%s\nClasse %s · X %.1f  Y %.1f  Z %.1f" % [nm, GalaxyGenerator.star_type_letter(sys.star_type), lp.x, lp.y, lp.z]

func get_selection_world_position(index: int) -> Vector3:
	return get_system_world_position(index)
