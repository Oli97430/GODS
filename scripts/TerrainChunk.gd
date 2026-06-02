class_name TerrainChunk
extends StaticBody3D
## Un chunk de terrain : mesh visuel + collision HeightMap OPTIONNELLE (activée
## seulement pour les chunks proches). Connaît sa coordonnée en ESPACE-PLANÈTE
## (cx, cz), invariante au rebase. Recyclable (pooling) : apply()/release() sans
## réallouer. Node placé au CENTRE du chunk ; mesh et collision centrés => coïncident.

var coord := Vector2i.ZERO
var lod := -1            # niveau de LOD courant (-1 = non assigné) ; piloté par ChunkManager
var active := false
var has_collision := false

var _mesh_instance: MeshInstance3D
var _water_instance: MeshInstance3D   # phase 23 : nappe d'eau rivière/lac (matériau partagé, sans collision)
var _waterfall_instance: MeshInstance3D   # phase 23-10 : nappes verticales de cascade (matériau partagé, sans collision)
var _collision: CollisionShape3D
var _shape: Shape3D       # forme de collision du chunk (trimesh, activable à la demande)
var _cell := 1.0

# --- Végétation : MultiMesh PARTAGÉS (mesh de la VegetationLibrary), un par variante
# présente, recyclés au pooling. Le semis (transforms) est calculé hors-thread ; les
# MultiMesh ne sont remplis qu'à l'affichage (dans le rayon végétation). ---
const VEG_COLLISION := true        # colliders d'arbres (mettre false si trop coûteux au casque)
var _veg_seeds: Dictionary = {}    # variant:int -> Array[Transform3D] (repère LOCAL du chunk)
var _veg_mm: Dictionary = {}       # variant:int -> MultiMeshInstance3D (réutilisés)
var _veg_built: Dictionary = {}    # variant:int -> bool (MultiMesh rempli pour le semis courant)
var _veg_lib: VegetationLibrary
var _veg_colliders: Array[CollisionShape3D] = []   # capsules d'arbres (rayon collision serré uniquement)
var _veg_colliders_built := false
var _impostor_mm: Dictionary = {}      # phase 24 : espèce:int -> MultiMeshInstance3D (1 impostor PAR espèce, anneau LOINTAIN)
var _impostor_built := false

# --- Faune (phase 19) : créatures = nodes Creature enfants du chunk (despawn avec le chunk). ---
var _fauna: Array[Creature] = []
var _fauna_spawns: Array = []   # données de spawn (légères, hors-thread) ; instanciées que dans l'anneau

# --- Clutter (phase 20 couche B) : petits objets au sol, MultiMesh PARTAGÉS (ClutterLibrary), un par
# variante présente, recyclés au pooling. Calque exact de la végétation : semis calculé hors-thread,
# MultiMesh remplis (lazy) seulement à l'affichage dans l'anneau clutter (serré). ---
var _clutter_seeds: Dictionary = {}   # variant:int -> Array[Transform3D] (repère LOCAL du chunk)
var _clutter_mm: Dictionary = {}      # variant:int -> MultiMeshInstance3D (réutilisés)
var _clutter_built: Dictionary = {}   # variant:int -> bool (MultiMesh rempli pour le semis courant)
var _clutter_lib: ClutterLibrary

# --- POI (phase 20 couche C) : lieu d'intérêt = UN Node3D procédural enfant du chunk (rare). Le
# descripteur (catégorie/pose/nom) est calculé hors-thread ; le Node3D n'est construit qu'à l'entrée
# dans l'anneau POI (main-thread, budgété) et libéré en sortie / au recyclage. ---
var _poi_data: POIInstance   # descripteur léger (hors-thread) ou null si pas de POI ici
var _poi_node: Node3D        # instance visuelle (dans l'anneau POI) ou null

func _init() -> void:
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)
	_collision = CollisionShape3D.new()
	add_child(_collision)
	_water_instance = MeshInstance3D.new()
	_water_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_water_instance.visible = false
	add_child(_water_instance)
	_waterfall_instance = MeshInstance3D.new()
	_waterfall_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_waterfall_instance.visible = false
	add_child(_waterfall_instance)
	_reset_internal()

# Installe le visuel + transform ESPACE-PLANÈTE (base tangente + centre sur la sphère)
# + garde le shape de collision (pas encore actif). Appelé sur le thread principal ;
# le mesh/shape ont été construits hors-thread. Le chunk est enfant de PlanetRoot.
func apply(chunk_coord: Vector2i, mesh: Mesh, material: Material, planet_transform: Transform3D, shape: Shape3D, cell: float, p_lod: int) -> void:
	coord = chunk_coord
	lod = p_lod
	transform = planet_transform
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = material
	_mesh_instance.visible = true
	_shape = shape
	_cell = cell
	active = true
	visible = true

# Remplace le mesh + la forme de collision (changement de LOD) SANS toucher au reste
# (transform, végétation, coord). Si la collision est active, la met à jour vers la
# nouvelle forme. Appelé sur le thread principal ; mesh/forme construits hors-thread.
func swap_mesh(mesh: Mesh, shape: Shape3D, cell: float, p_lod: int, water_mesh: Mesh = null, water_mat: Material = null, waterfall_mesh: Mesh = null, waterfall_mat: Material = null) -> void:
	lod = p_lod
	_mesh_instance.mesh = mesh
	_shape = shape
	_cell = cell
	if has_collision:
		_collision.shape = shape
	apply_water(water_mesh, water_mat)
	apply_waterfall(waterfall_mesh, waterfall_mat)

# Geomorph : facteur de morph (0..1) du LOD courant, poussé par ChunkManager chaque frame (instance uniform
# `morph_factor` de terrain.gdshader). Persiste à travers swap_mesh (propriété d'instance, pas du mesh).
var _morph := -1.0   # cache : évite les set_instance_shader_parameter redondants (la plupart des chunks = 0 stable)
func set_morph(f: float) -> void:
	if absf(f - _morph) < 0.003:
		return
	_morph = f
	_mesh_instance.set_instance_shader_parameter("morph_factor", f)

# Phase 23 : installe (ou masque) la nappe d'eau rivière/lac du chunk. Matériau PARTAGÉ (eau de la planète).
func apply_water(water_mesh: Mesh, mat: Material) -> void:
	if water_mesh != null:
		_water_instance.mesh = water_mesh
		_water_instance.material_override = mat
		_water_instance.visible = true
	else:
		_water_instance.mesh = null
		_water_instance.visible = false

# Phase 23-10 : installe (ou masque) les nappes de cascade du chunk. Matériau PARTAGÉ (mousse animée).
func apply_waterfall(waterfall_mesh: Mesh, mat: Material) -> void:
	if waterfall_mesh != null:
		_waterfall_instance.mesh = waterfall_mesh
		_waterfall_instance.material_override = mat
		_waterfall_instance.visible = true
	else:
		_waterfall_instance.mesh = null
		_waterfall_instance.visible = false

# Mesh visuel courant (pour le recyclage par ChunkManager avant release/swap).
func get_mesh() -> Mesh:
	return _mesh_instance.mesh

# Active la collision HeightMap (chunks dans le rayon restreint).
func enable_collision() -> void:
	if has_collision or _shape == null:
		return
	# Trimesh en coords locales (mètres) : AUCUNE mise à l'échelle (sinon cisaillement
	# sous la rotation du chunk). La collision suit donc exactement le mesh visuel.
	_collision.shape = _shape
	_collision.disabled = false
	has_collision = true

func disable_collision() -> void:
	if not has_collision:
		return
	_collision.shape = null
	_collision.disabled = true
	has_collision = false

# --- Végétation ---

# Mémorise le semis (transforms calculées hors-thread). Purge l'ancien rendu (chunk
# recyclé) ; les MultiMesh ne seront (re)construits qu'à l'affichage (set_vegetation_state),
# donc uniquement dans le rayon végétation => zéro travail pour les chunks lointains.
func apply_vegetation(seeds: Dictionary, lib: VegetationLibrary) -> void:
	for v in _veg_mm:
		_veg_mm[v].multimesh.instance_count = 0
		_veg_mm[v].visible = false
	for sp in _impostor_mm:
		_impostor_mm[sp].multimesh.instance_count = 0
		_impostor_mm[sp].visible = false
	_impostor_built = false
	_clear_veg_colliders()   # semis changé => colliders d'arbres obsolètes
	_veg_seeds = seeds
	_veg_lib = lib
	_veg_built.clear()

# Affiche/masque la végétation par catégorie (piloté par les rayons côté ChunkManager).
# Construit le MultiMesh d'une variante à la 1re demande (lazy), puis ne bascule que la
# visibilité (peu coûteux).
## allow_build : autorise la construction (coûteuse) du MultiMesh cette frame. Si false
## et qu'une variante doit apparaître mais n'est pas encore construite, on la laisse
## masquée (elle sera construite une frame suivante => budget anti-hitch côté ChunkManager).
## Renvoie true si une construction a eu lieu (pour décrémenter le budget appelant).
func set_vegetation_state(show_full: bool, show_grass: bool, show_impostor: bool, allow_build: bool) -> bool:
	if _veg_lib == null:
		return false
	var did_build := false
	# Meshes pleins : herbe (anneau proche) + arbres/rochers (anneau moyen).
	for v in _veg_seeds:
		var is_grass: bool = _veg_lib.category_of(v) == VegetationLibrary.Category.GRASS
		var want: bool = show_grass if is_grass else show_full
		if want:
			if not _veg_built.get(v, false):
				if not allow_build:
					continue   # reste masquée cette frame (budget) ; construite plus tard
				_build_mm(v)
				did_build = true
			_veg_mm[v].visible = true
		elif _veg_mm.has(v):
			_veg_mm[v].visible = false
	# Impostors d'arbres : anneau LOINTAIN (au-delà du mesh plein), aux positions des arbres.
	if show_impostor:
		if not _impostor_built and allow_build:
			_build_impostor()
			did_build = true
		for sp in _impostor_mm:
			_impostor_mm[sp].visible = true
	else:
		for sp in _impostor_mm:
			_impostor_mm[sp].visible = false
	return did_build

# Construit le MultiMesh d'impostors aux positions de TOUS les arbres du chunk (mesh + matériau
# d'impostor PARTAGÉS). Lazy ; recyclé comme les autres MultiMesh.
func _build_impostor() -> void:
	_impostor_built = true
	# Phase 24 : 1 impostor PAR ESPÈCE (silhouette/teinte propres). On regroupe les positions d'arbres
	# par espèce (= variante / VARIANTS_PER) puis on remplit/recycle un MultiMesh dédié par espèce.
	var by_species: Dictionary = {}
	for v in _veg_seeds:
		if VegetationLibrary.is_tree_variant(v):
			var sp: int = v / VegetationLibrary.TREE_VARIANTS_PER
			if not by_species.has(sp):
				by_species[sp] = []
			by_species[sp].append_array(_veg_seeds[v])
	for sp in by_species:
		var transforms: Array = by_species[sp]
		var mmi: MultiMeshInstance3D = _impostor_mm.get(sp)
		if mmi == null:
			var mm0 := MultiMesh.new()
			mm0.transform_format = MultiMesh.TRANSFORM_3D
			mm0.mesh = _veg_lib.impostor_mesh_for(sp)
			mmi = MultiMeshInstance3D.new()
			mmi.multimesh = mm0
			mmi.material_override = _veg_lib.impostor_material()
			add_child(mmi)
			_impostor_mm[sp] = mmi
		var mm: MultiMesh = mmi.multimesh
		if mm.mesh == null:
			mm.mesh = _veg_lib.impostor_mesh_for(sp)
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])

# Construit (une fois par semis) le MultiMesh d'une variante depuis ses transforms.
# Réutilise le MultiMeshInstance3D existant (pooling) : seul le contenu change.
func _build_mm(v: int) -> void:
	if _veg_built.get(v, false):
		return
	var mmi: MultiMeshInstance3D = _veg_mm.get(v)
	var tinted: bool = VegetationLibrary.is_tree_variant(v)   # phase 24 : teinte par instance (arbres)
	if mmi == null:
		# mesh (PARTAGÉ) + format assignés AVANT l'entrée dans l'arbre (jamais de mesh nul résident).
		var mm0 := MultiMesh.new()
		mm0.transform_format = MultiMesh.TRANSFORM_3D
		if tinted:
			mm0.use_custom_data = true   # INSTANCE_CUSTOM = teinte d'instance (variété de forêt)
		mm0.mesh = _veg_lib.mesh_for(v)
		mmi = MultiMeshInstance3D.new()
		mmi.multimesh = mm0
		mmi.material_override = _veg_lib.material_for(v)
		add_child(mmi)
		_veg_mm[v] = mmi
	var mm: MultiMesh = mmi.multimesh
	if mm.mesh == null:
		mm.mesh = _veg_lib.mesh_for(v)
	var arr: Array = _veg_seeds[v]
	mm.instance_count = arr.size()
	for i in arr.size():
		mm.set_instance_transform(i, arr[i])
		if tinted:
			mm.set_instance_custom_data(i, _hue_tint(i))
	_veg_built[v] = true

# Teinte d'instance déterministe (variété de forêt) : luminosité + léger glissement chaud/froid.
# alpha=1 => le shader applique la teinte (herbe sans custom data => INSTANCE_CUSTOM=0 => teinte neutre).
func _hue_tint(i: int) -> Color:
	var f := fposmod(float(i) * 0.6180340, 1.0)
	var g := fposmod(float(i) * 0.3819660, 1.0)
	var bright := 0.84 + 0.30 * f          # 0.84..1.14 de luminosité
	var warm := 0.93 + 0.14 * g            # léger décalage vert<->jaune
	return Color(bright * warm, bright, bright * (1.86 - warm), 1.0)

# Vide la végétation (chunk recyclé) : MultiMesh remis à zéro + masqués (nodes gardés).
func clear_vegetation() -> void:
	for v in _veg_mm:
		_veg_mm[v].multimesh.instance_count = 0
		_veg_mm[v].visible = false
	for sp in _impostor_mm:
		_impostor_mm[sp].multimesh.instance_count = 0
		_impostor_mm[sp].visible = false
	_impostor_built = false
	_clear_veg_colliders()
	_veg_seeds = {}
	_veg_built.clear()

# --- Clutter (phase 20 couche B) : mêmes mécanismes que la végétation (lazy, recyclage, anneau) ---

# Mémorise le semis de clutter (transforms calculées hors-thread). Purge l'ancien rendu (chunk
# recyclé) ; les MultiMesh ne seront (re)construits qu'à l'affichage (set_clutter_state) => zéro
# travail pour les chunks hors de l'anneau clutter.
func apply_clutter(seeds: Dictionary, lib: ClutterLibrary) -> void:
	for v in _clutter_mm:
		_clutter_mm[v].multimesh.instance_count = 0
		_clutter_mm[v].visible = false
	_clutter_seeds = seeds
	_clutter_lib = lib
	_clutter_built.clear()

# Affiche/masque le clutter (anneau serré côté ChunkManager). Construit le MultiMesh d'une variante à
# la 1re demande (lazy), puis ne bascule que la visibilité. allow_build borne le coût (anti-hitch) :
# si false et qu'une variante doit apparaître mais n'est pas construite, on la laisse masquée (plus tard).
# Renvoie true si une construction a eu lieu (pour décrémenter le budget appelant).
func set_clutter_state(show: bool, allow_build: bool) -> bool:
	if _clutter_lib == null:
		return false
	var did_build := false
	for v in _clutter_seeds:
		if show:
			if not _clutter_built.get(v, false):
				if not allow_build:
					continue
				_build_clutter_mm(v)
				did_build = true
			_clutter_mm[v].visible = true
		elif _clutter_mm.has(v):
			_clutter_mm[v].visible = false
	return did_build

# Construit (une fois par semis) le MultiMesh d'une variante de clutter. Réutilise le
# MultiMeshInstance3D existant (pooling) : seul le contenu change.
func _build_clutter_mm(v: int) -> void:
	if _clutter_built.get(v, false):
		return
	var mmi: MultiMeshInstance3D = _clutter_mm.get(v)
	if mmi == null:
		var mm0 := MultiMesh.new()
		mm0.transform_format = MultiMesh.TRANSFORM_3D
		mm0.mesh = _clutter_lib.mesh_for(v)
		mmi = MultiMeshInstance3D.new()
		mmi.multimesh = mm0
		mmi.material_override = _clutter_lib.material_for(v)
		add_child(mmi)
		_clutter_mm[v] = mmi
	var mm: MultiMesh = mmi.multimesh
	if mm.mesh == null:
		mm.mesh = _clutter_lib.mesh_for(v)
	var arr: Array = _clutter_seeds[v]
	mm.instance_count = arr.size()
	for i in arr.size():
		mm.set_instance_transform(i, arr[i])
	_clutter_built[v] = true

# Vide le clutter (chunk recyclé) : MultiMesh remis à zéro + masqués (nodes gardés pour pooling).
func clear_clutter() -> void:
	for v in _clutter_mm:
		_clutter_mm[v].multimesh.instance_count = 0
		_clutter_mm[v].visible = false
	_clutter_seeds = {}
	_clutter_built.clear()

# Instances de clutter VISIBLES (diagnostic anneau/perf).
func visible_clutter_instance_count() -> int:
	var n := 0
	for v in _clutter_mm:
		if _clutter_mm[v].visible:
			n += _clutter_mm[v].multimesh.instance_count
	return n

# --- POI (phase 20 couche C) ---

# Mémorise le descripteur de POI (hors-thread) SANS instancier. Léger : l'instanciation (coûteuse)
# est différée à l'entrée dans l'anneau POI (set_poi_state). 'poi' peut être null (chunk sans POI).
func set_poi_data(poi: POIInstance) -> void:
	clear_poi()
	_poi_data = poi

func has_poi() -> bool:
	return _poi_data != null and _poi_data.is_valid()

# Vrai si le Node3D du POI est actuellement instancié (pour le budget de build côté ChunkManager).
func has_poi_node() -> bool:
	return _poi_node != null

# Catégorie / seed du POI (phase 22 : audio par catégorie + « résonance » par seed). -1 / 0 si aucun.
func poi_category() -> int:
	return _poi_data.category if _poi_data != null else -1

func poi_seed() -> int:
	return _poi_data.seed_val if _poi_data != null else 0

# Nom du POI (vide si POI mineur/anonyme ou pas de POI).
func poi_name() -> String:
	return _poi_data.poi_name if _poi_data != null else ""

# Position MONDE du POI, calculée depuis le repère LOCAL du chunk (valable même non instancié).
func poi_world_position() -> Vector3:
	if _poi_data == null:
		return global_position
	return global_transform * _poi_data.local_transform.origin

# Instancie / libère le Node3D du POI selon l'anneau (piloté + budgété par ChunkManager). Construction
# MAIN-THREAD via POILibrary.generate (rare => au plus quelques POI vivants). True si un travail a eu lieu.
func set_poi_state(want: bool, lib: POILibrary) -> bool:
	if want and _poi_node == null and has_poi():
		_poi_node = lib.generate(_poi_data.category, _poi_data.seed_val)
		add_child(_poi_node)
		_poi_node.transform = _poi_data.local_transform
		return true
	if not want and _poi_node != null:
		clear_poi_node()
		return true
	return false

func clear_poi_node() -> void:
	if _poi_node != null:
		_poi_node.queue_free()
		_poi_node = null

# Libère le POI (node + descripteur) — chunk recyclé.
func clear_poi() -> void:
	clear_poi_node()
	_poi_data = null

# --- Faune (phase 19) ---

# Mémorise les spawns de faune (calculés hors-thread par ChunkFauna) SANS instancier : léger.
# L'instanciation (coûteuse, main-thread) est différée à l'entrée dans l'anneau faune (set_fauna_state),
# qui est BIEN plus serré que le rayon visuel => au plus ~quelques chunks peuplés à la fois.
func set_fauna_data(spawns: Array) -> void:
	clear_fauna()
	_fauna_spawns = spawns

# Instancie / libère les créatures selon l'anneau faune (piloté + budgété par ChunkManager).
# Renvoie true si un travail (instanciation ou libération) a eu lieu (pour décrémenter le budget).
func set_fauna_state(want: bool, lib: FaunaLibrary, roster: Array, player: Node3D, pg: PlanetGenerator, phys_radius: float, vertical_scale: float) -> bool:
	if want and _fauna.is_empty() and not _fauna_spawns.is_empty():
		_instantiate_fauna(lib, roster, player, pg, phys_radius, vertical_scale)
		return true
	if not want and not _fauna.is_empty():
		clear_fauna()
		return true
	return false

# Instancie les créatures depuis _fauna_spawns. Main-thread. Construit un FaunaGround propre au chunk
# (repère tangent = transform du chunk) pour le suivi du sol. Déterministe (sseed = coord + index).
func _instantiate_fauna(lib: FaunaLibrary, roster: Array, player: Node3D, pg: PlanetGenerator, phys_radius: float, vertical_scale: float) -> void:
	if lib == null or roster.is_empty():
		return
	var ground := FaunaGround.new(pg, transform.origin, transform.basis, phys_radius, vertical_scale, PlanetGenerator.DEFAULT_SEA_LEVEL)
	for i in _fauna_spawns.size():
		var sp: Dictionary = _fauna_spawns[i]
		var si: int = sp.species_idx
		if si < 0 or si >= roster.size():
			continue
		var species: Dictionary = roster[si]
		var parts: Dictionary = lib.species_parts(species.key, species.params)
		var creature := Creature.new()
		add_child(creature)
		creature.position = sp.local
		creature.rotation.y = sp.yaw
		var sseed := coord.x * 92837111 + coord.y * 689287499 + i * 283923481
		creature.setup(species, parts, lib.material(), player, ground, sseed)
		_fauna.append(creature)

# Libère les créatures instanciées (sortie d'anneau / chunk recyclé). Garde _fauna_spawns pour
# pouvoir réinstancier à l'identique si le chunk re-rentre dans l'anneau.
func clear_fauna() -> void:
	for c in _fauna:
		c.queue_free()
	_fauna.clear()

# Nombre de créatures vivantes dans ce chunk (diagnostic).
func fauna_count() -> int:
	return _fauna.size()

# --- Collision des arbres (rayon serré uniquement) ---

# Active/désactive les capsules d'arbres (appelé par ChunkManager dans un rayon TRÈS
# serré, distinct du rayon terrain). Construction PARESSEUSE (1re activation), puis simple
# bascule de disabled (recyclage). Réutilise le StaticBody du chunk : pas de body par arbre.
func set_tree_collision(active: bool) -> void:
	if not VEG_COLLISION:
		return
	if active:
		if not _veg_colliders_built:
			_build_veg_colliders()
	elif _veg_colliders_built:
		_clear_veg_colliders()   # hors du rayon serré => libère (nœuds bornés au rayon arbres)

func _build_veg_colliders() -> void:
	_veg_colliders_built = true
	if _veg_lib == null:
		return
	for v in _veg_seeds:
		if _veg_lib.category_of(v) != VegetationLibrary.Category.TREE:
			continue
		for t in _veg_seeds[v]:
			var sc: float = t.basis.get_scale().y
			var cap := CapsuleShape3D.new()
			cap.radius = 0.28 * sc
			cap.height = 1.9 * sc
			var cs := CollisionShape3D.new()
			cs.shape = cap
			cs.position = t.origin + Vector3(0.0, 0.95 * sc, 0.0)   # tronc vertical centré
			add_child(cs)
			_veg_colliders.append(cs)

func _clear_veg_colliders() -> void:
	for cs in _veg_colliders:
		cs.queue_free()
	_veg_colliders.clear()
	_veg_colliders_built = false

# Nombre de colliders d'arbres actuels (diagnostic).
func vegetation_collider_count() -> int:
	return _veg_colliders.size()

# Nombre total d'instances de végétation actuellement construites (diagnostic).
func vegetation_instance_count() -> int:
	var n := 0
	for v in _veg_mm:
		n += _veg_mm[v].multimesh.instance_count
	for sp in _impostor_mm:
		n += _impostor_mm[sp].multimesh.instance_count
	return n

# Instances de végétation réellement VISIBLES (diagnostic rayon).
func visible_vegetation_instance_count() -> int:
	var n := 0
	for v in _veg_mm:
		if _veg_mm[v].visible:
			n += _veg_mm[v].multimesh.instance_count
	for sp in _impostor_mm:
		if _impostor_mm[sp].visible:
			n += _impostor_mm[sp].multimesh.instance_count
	return n

# MultiMesh VISIBLES (≈ draw calls de végétation de ce chunk).
func visible_vegetation_node_count() -> int:
	var n := 0
	for v in _veg_mm:
		if _veg_mm[v].visible:
			n += 1
	for sp in _impostor_mm:
		if _impostor_mm[sp].visible:
			n += 1
	return n

# Nombre de nodes MultiMeshInstance3D détenus (diagnostic pooling/mémoire).
func vegetation_node_count() -> int:
	return _veg_mm.size() + _impostor_mm.size()

# Instances d'impostors d'arbres VISIBLES (diagnostic tier lointain).
func impostor_instance_count() -> int:
	var n := 0
	for sp in _impostor_mm:
		if _impostor_mm[sp].visible:
			n += _impostor_mm[sp].multimesh.instance_count
	return n

# Recycle le chunk (retour au pool) : masque + libère ses ressources lourdes.
func release() -> void:
	_mesh_instance.mesh = null
	_mesh_instance.material_override = null
	_water_instance.mesh = null
	_water_instance.visible = false
	_waterfall_instance.mesh = null
	_waterfall_instance.visible = false
	_shape = null
	disable_collision()
	clear_vegetation()
	clear_clutter()
	clear_poi()
	clear_fauna()
	_fauna_spawns = []   # purge aussi les données de spawn (chunk rendu au pool)
	_reset_internal()

func _reset_internal() -> void:
	active = false
	visible = false
	has_collision = false
	_mesh_instance.visible = false
	_collision.disabled = true
