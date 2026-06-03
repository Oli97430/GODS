class_name ChunkManager
extends Node3D
## Streaming planétaire SANS gravité sphérique. Les chunks sont générés en VRAIES
## positions sphériques (rayon planète + élévation) et portés par un node PlanetRoot
## dont la transform "aplatit" l'espace-planète autour du joueur (FloatingOrigin) :
## le sol sous le joueur est à l'origine, normale +Y, et la courbure est suivie sans
## physique sphérique. ZÉRO distorsion (vraies positions), zéro tremblement (joueur
## ~ origine), zéro couture (bords voisins = mêmes positions-planète).
##
## Génération ASYNCHRONE (WorkerThreadPool) + insertion budgétée main-thread.
## Clés de chunk (cx,cz) = grille tangente d'atterrissage FIXE (projection gnomonique) :
## déterministes, INVARIANTES au rebase (seule la transform de PlanetRoot bouge).
## Couverture ~hémisphère (la grille tangente dégénère au-delà ; cube-sphère = futur).

const CHUNK_SIZE := SurfaceGenerator.DEFAULT_PATCH_SIZE  # 256 m / chunk
# LOD discret par anneaux (même grille 256 m/chunk ; seule la RÉSOLUTION varie par
# distance). LOD0 plein détail près du joueur, chaque niveau ~moitié de résolution.
const LOD_RES := [64, 32, 16, 8]            # cellules 4 / 8 / 16 / 32 m
const LOD_MAX_DIST := [2.0, 4.0, 6.0, 8.0]  # frontière de distance (en chunks) de chaque LOD
const LOD_HYST := 0.5                        # hystérésis (chunks) : anti-oscillation aux frontières
const SKIRT_FACTOR := 1.5                    # profondeur de jupe = cellule du LOD × facteur (couvre les fissures inter-LOD)
const VISUAL_RADIUS := 8                     # = LOD_MAX_DIST[-1] : rayon visuel ÉTENDU (~2 km), bord masqué par le fog
const COLLISION_RADIUS := 2       # rayon de collision du terrain (plus restreint : ~13 chunks)
const TREE_COLLISION_RADIUS := 1  # rayon collision des arbres (TRÈS serré : ~5 chunks ; le joueur ne touche que tout près)
const VEG_RADIUS := 4             # rayon arbres/rochers en MESH PLEIN (anneau moyen)
const GRASS_RADIUS := 2           # rayon herbe (anneau le plus proche : beaucoup d'instances)
const CLUTTER_RADIUS := 2         # rayon clutter au sol (phase 20 : petits objets, anneau serré comme l'herbe)
const POI_RADIUS := 4             # rayon d'instanciation des POI (LOD assez fin pour éviter le flottement ; ~1 km, masqué par le fog)
const IMPOSTOR_RADIUS := 7        # rayon des impostors d'arbres (au-delà de VEG_RADIUS, < visuel), puis cull ; fog masque la limite
const FAUNA_RADIUS := 1           # anneau faune TRÈS serré (~3x3 chunks = ~256 m) : créatures = nodes coûteux, instanciées que tout près (le reste reste en données de spawn légères)
const MAX_VEG_BUILDS_PER_FRAME := 2  # budget de construction de MultiMesh végétation (anti-hitch)
const MAX_FAUNA_BUILDS_PER_FRAME := 1  # budget d'instanciation de faune par frame (anti-hitch ; ~quelques créatures/chunk)
const MAX_CLUTTER_BUILDS_PER_FRAME := 2  # budget de construction de MultiMesh clutter (anti-hitch, phase 20)
const MAX_POI_BUILDS_PER_FRAME := 1  # budget d'instanciation de POI/frame (mesh le plus lourd => 1 ; POI rares)
const MAX_INSERTS_PER_FRAME := 2  # budget d'insertion/swap main-thread par frame (anti-hitch)
const MAX_LOD_REGENS_PER_FRAME := 3  # budget de régénérations de LOD ENFILÉES par frame (anti-flood worker)
const REBASE_THRESHOLD := 600.0   # m : ré-ancre l'aplatissement quand le joueur s'éloigne (tilt borné ~11°)

signal rebased(root_transform: Transform3D)

# Repère tangent d'atterrissage FIXE (keying + projection gnomonique) + paramètres.
var seed_local := 0
var palette_id := 0   # phase 20 couche C : palette régionale du système (nommage des POI notables)
var anchor_dir := Vector3.UP
var east := Vector3.RIGHT
var north := Vector3.FORWARD
var phys_radius := SurfaceGenerator.DEFAULT_PLANET_PHYS_RADIUS
var vertical_scale := SurfaceGenerator.DEFAULT_VERTICAL_SCALE

var player: Node3D
var _root: Node3D              # PlanetRoot : porte les chunks ; transform = aplatissement
var _flatten_dir := Vector3.UP  # ancre courante de l'aplatissement (maj au rebase)

var _material: ShaderMaterial
var _veg_lib: VegetationLibrary    # bibliothèque de meshes de végétation PARTAGÉE (créée une fois)
var _clutter_lib: ClutterLibrary   # bibliothèque de meshes de clutter PARTAGÉE (phase 20 couche B)
var _poi_lib: POILibrary           # générateurs de POI PARTAGÉS (phase 20 couche C)
var _fauna_lib: FaunaLibrary       # bibliothèque de meshes de faune PARTAGÉE (phase 19)
var _fauna_roster: Array = []      # espèces de la planète courante (déterministe par seed)
var _fauna_pg: PlanetGenerator     # sampler MAIN-THREAD (suivi du sol des créatures, distinct du thread)
var flow_map: PlanetFlowMap = null # phase 23 : carte hydrologique (érosion + rivières) ou null
var _inland_water_mat: ShaderMaterial   # phase 23 : matériau d'eau rivière/lac PARTAGÉ (créé/maj par SurfaceView)
var _waterfall_mat: ShaderMaterial   # phase 23-10 : matériau de cascade PARTAGÉ (mousse animée, créé ici)
var _active := {}
var _pool: Array[TerrainChunk] = []   # recyclage des NODES TerrainChunk (anti-réallocation principal)
var _mutex := Mutex.new()
var _ready_queue: Array = []
var _pending := {}
var _task_ids: Array[int] = []

func _ready() -> void:
	_root = Node3D.new()
	add_child(_root)
	set_process(false)

# Configure le repère tangent au point d'atterrissage (direction-planète unitaire).
func setup(p_seed: int, p_anchor_dir: Vector3, p_palette_id: int = 0, p_flow_map: PlanetFlowMap = null) -> void:
	_flush_pending_tasks()
	clear_all()
	seed_local = p_seed
	palette_id = p_palette_id
	flow_map = p_flow_map   # phase 23 : hydrologie de la planète (érosion + rivières), passée aux seeders
	anchor_dir = p_anchor_dir.normalized()
	var b := FloatingOrigin.tangent_basis(anchor_dir)
	east = b.x
	north = b.z
	_flatten_dir = anchor_dir
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://shaders/terrain.gdshader")   # albédo = couleur vertex + GEOMORPHING
	if _waterfall_mat == null:
		_waterfall_mat = ShaderMaterial.new()
		_waterfall_mat.shader = preload("res://shaders/waterfall.gdshader")   # nappes de cascade (mousse défilante)
	if _veg_lib == null:
		_veg_lib = VegetationLibrary.new()   # meshes de végétation générés une seule fois
	if _clutter_lib == null:
		_clutter_lib = ClutterLibrary.new()  # meshes de clutter générés une seule fois (phase 20 couche B)
	if _poi_lib == null:
		_poi_lib = POILibrary.new()          # générateurs de POI (phase 20 couche C)
	# Faune (phase 19) : bibliothèque créée une fois ; roster + sampler-sol regénérés par planète.
	if _fauna_lib == null:
		_fauna_lib = FaunaLibrary.new()
	_fauna_roster = PlanetFaunaRoster.generate(seed_local, _fauna_lib)
	_fauna_pg = PlanetGenerator.new()
	_fauna_pg.configure(seed_local)
	_fauna_pg.set_flow_map(flow_map)   # phase 23 : suivi-sol faune + biome audio sur terrain érodé
	_apply_flatten()
	set_process(true)

# Phase 23 : matériau d'eau rivière/lac PARTAGÉ (créé + maj wave_time/soleil par SurfaceView).
func set_inland_water_material(mat: ShaderMaterial) -> void:
	_inland_water_mat = mat

func _process(_dt: float) -> void:
	_maybe_rebase()
	_drain_ready()
	if player:
		update_streaming(_dir_at(player.global_position))
	# Amplitude du vent de la végétation pilotée par la météo (phase 13).
	if _veg_lib and WeatherSystem.is_configured():
		_veg_lib.set_wind_amount(WeatherSystem.get_wind())

# Transform courante du PlanetRoot (aplatissement) — pour situer un objet dans l'espace-planète
# et le recaler au rebase, comme les chunks.
func root_transform() -> Transform3D:
	return _root.transform

# Direction-planète d'une position MONDE (inverse de l'aplatissement).
func _dir_at(world_pos: Vector3) -> Vector3:
	return (_root.transform.affine_inverse() * world_pos).normalized()

# Clé de chunk (gnomonique inverse) d'une direction-planète. valid=false au-delà de
# ~l'hémisphère (projection dégénérée).
func coord_of_dir(dir: Vector3) -> Dictionary:
	var d := dir.dot(anchor_dir)
	if d <= 0.15:
		return {"valid": false, "coord": Vector2i.ZERO}
	var plane_pt := dir * (phys_radius / d)
	var rel := plane_pt - anchor_dir * phys_radius
	return {"valid": true, "coord": Vector2i(floori(rel.dot(east) / CHUNK_SIZE), floori(rel.dot(north) / CHUNK_SIZE))}

func update_streaming(player_dir: Vector3) -> void:
	var c := coord_of_dir(player_dir)
	if not c.valid:
		return
	var center: Vector2i = c.coord
	var rm: Array = []
	for coord in _active:
		if _chunk_dist(coord, center) > VISUAL_RADIUS:
			rm.append(coord)
	for coord in rm:
		_release(coord)
	var missing: Array[Vector2i] = []
	for dz in range(-VISUAL_RADIUS, VISUAL_RADIUS + 1):
		for dx in range(-VISUAL_RADIUS, VISUAL_RADIUS + 1):
			var coord := center + Vector2i(dx, dz)
			if _chunk_dist(coord, center) <= VISUAL_RADIUS and not _active.has(coord) and not _pending.has(coord):
				missing.append(coord)
	# Plus proche du joueur d'abord : le sol sous lui (et la collision) se charge en
	# priorité => spawn réactif (gel anti-chute levé vite) et pas de trou sous les pieds.
	missing.sort_custom(func(a, b): return _chunk_dist(a, center) < _chunk_dist(b, center))
	for coord in missing:
		_enqueue(coord, _select_lod(_chunk_dist(coord, center), -1))
	_update_lods(center)
	_update_morph()
	_update_collisions(center)
	_update_vegetation(center)
	_update_clutter(center)
	_update_poi(center)
	_update_fauna(center)
	_prune_tasks()

func _drain_ready() -> void:
	var c := coord_of_dir(_dir_at(player.global_position)) if player else {"valid": false, "coord": Vector2i.ZERO}
	var inserted := 0
	while inserted < MAX_INSERTS_PER_FRAME:
		_mutex.lock()
		var has := not _ready_queue.is_empty()
		var r: Dictionary = _ready_queue.pop_front() if has else {}
		_mutex.unlock()
		if not has:
			break
		_pending.erase(r.coord)
		if _active.has(r.coord):
			# Régén de LOD : remplace le mesh + la collision + l'eau, garde la végétation existante.
			_active[r.coord].swap_mesh(r.mesh, r.shape, r.cell, r.lod, r.water_mesh, _inland_water_mat, r.waterfall_mesh, _waterfall_mat)
			inserted += 1
			continue
		if c.valid and _chunk_dist(r.coord, c.coord) > VISUAL_RADIUS:
			continue
		var chunk := _acquire()
		chunk.apply(r.coord, r.mesh, _material, Transform3D(r.basis, r.center), r.shape, r.cell, r.lod)
		chunk.apply_water(r.water_mesh, _inland_water_mat)   # phase 23 : nappe d'eau rivière/lac
		chunk.apply_waterfall(r.waterfall_mesh, _waterfall_mat)   # phase 23-10 : cascades aux dénivelés
		chunk.apply_vegetation(r.veg, _veg_lib)
		chunk.apply_clutter(r.clutter, _clutter_lib)   # phase 20 couche B (lazy : construit dans l'anneau)
		chunk.set_poi_data(r.poi)                      # phase 20 couche C (descripteur ; instancié dans l'anneau POI)
		# Faune : on ne MÉMORISE que les spawns (léger) ; l'instanciation se fait dans l'anneau serré.
		chunk.set_fauna_data(r.fauna)
		if c.valid:
			chunk.set_fauna_state(_chunk_dist(r.coord, c.coord) <= FAUNA_RADIUS, _fauna_lib, _fauna_roster, player, _fauna_pg, phys_radius, vertical_scale)
		_active[r.coord] = chunk
		if c.valid:
			var d := _chunk_dist(r.coord, c.coord)
			if d <= COLLISION_RADIUS:
				chunk.enable_collision()
			chunk.set_tree_collision(d <= TREE_COLLISION_RADIUS)
			chunk.set_vegetation_state(d <= VEG_RADIUS, d <= GRASS_RADIUS, d > VEG_RADIUS and d <= IMPOSTOR_RADIUS, true)
			chunk.set_clutter_state(d <= CLUTTER_RADIUS, true)   # phase 20 couche B
			chunk.set_poi_state(d <= POI_RADIUS, _poi_lib)       # phase 20 couche C
		inserted += 1

func _enqueue(coord: Vector2i, lod: int) -> void:
	_pending[coord] = lod
	_task_ids.append(WorkerThreadPool.add_task(_gen_task.bind(coord, lod), false, "terrain chunk"))

func _gen_task(coord: Vector2i, lod: int) -> void:
	var res: int = LOD_RES[lod]
	var skirt := (CHUNK_SIZE / float(res)) * SKIRT_FACTOR
	# NB : on crée un NOUVEAU ArrayMesh hors-thread (commit sans réutilisation). Réutiliser
	# un ArrayMesh existant via commit(existing) hors-thread N'EST PAS thread-safe (modifie
	# une ressource déjà créée) et provoque un DEADLOCK. Le recyclage se fait au niveau des
	# NODES TerrainChunk (_pool), qui évite l'essentiel des réallocations.
	var data := SurfaceGenerator.generate_chunk(seed_local, coord.x, coord.y, anchor_dir, east, north, CHUNK_SIZE, res, phys_radius, vertical_scale, skirt, flow_map)
	# Semis de végétation DANS la même tâche de fond (zéro calcul de semis sur le main-thread).
	var veg := VegetationSeeder.seed_chunk(seed_local, coord.x, coord.y, anchor_dir, east, north, CHUNK_SIZE, phys_radius, vertical_scale, flow_map)
	# Clutter au sol (phase 20 couche B) dans la MÊME tâche de fond (calcul pur, comme la végétation).
	var clutter := ClutterSeeder.seed_chunk(seed_local, coord.x, coord.y, anchor_dir, east, north, CHUNK_SIZE, phys_radius, vertical_scale, flow_map)
	# POI (phase 20 couche C) : décision/placement/nom PUR off-thread (présence rare). null si aucun.
	var poi := POIDistributor.seed_chunk(seed_local, coord.x, coord.y, palette_id, anchor_dir, east, north, CHUNK_SIZE, phys_radius, vertical_scale, flow_map)
	# Faune (phase 19) dans la MÊME tâche de fond (calcul pur ; _fauna_roster = lecture seule).
	var fauna := ChunkFauna.seed_chunk(seed_local, coord.x, coord.y, _fauna_roster, anchor_dir, east, north, CHUNK_SIZE, phys_radius, vertical_scale, flow_map)
	_mutex.lock()
	_ready_queue.append({"coord": coord, "lod": lod, "mesh": data.mesh, "shape": data.collision_shape, "cell": data.cell_size, "center": data.center, "basis": data.basis, "veg": veg, "clutter": clutter, "poi": poi, "fauna": fauna, "water_mesh": data.water_mesh, "waterfall_mesh": data.waterfall_mesh})
	_mutex.unlock()

func _update_collisions(center: Vector2i) -> void:
	for coord in _active:
		var d := _chunk_dist(coord, center)
		if d <= COLLISION_RADIUS:
			_active[coord].enable_collision()
		else:
			_active[coord].disable_collision()
		_active[coord].set_tree_collision(d <= TREE_COLLISION_RADIUS)   # arbres solides très près

# Affiche la végétation par rayon (arbres/rochers <= VEG_RADIUS, herbe <= GRASS_RADIUS),
# masque au-delà. Construction des MultiMesh BUDGÉTÉE (anti-hitch) : au plus
# MAX_VEG_BUILDS_PER_FRAME nouveaux chunks construits par frame (les autres une frame plus tard).
func _update_vegetation(center: Vector2i) -> void:
	var budget := MAX_VEG_BUILDS_PER_FRAME
	for coord in _active:
		var d := _chunk_dist(coord, center)
		if _active[coord].set_vegetation_state(d <= VEG_RADIUS, d <= GRASS_RADIUS, d > VEG_RADIUS and d <= IMPOSTOR_RADIUS, budget > 0):
			budget -= 1

# Affiche/masque le clutter au sol par anneau serré (CLUTTER_RADIUS). Construction BUDGÉTÉE des
# MultiMesh (anti-hitch), comme la végétation : au plus MAX_CLUTTER_BUILDS_PER_FRAME chunks/frame.
func _update_clutter(center: Vector2i) -> void:
	var budget := MAX_CLUTTER_BUILDS_PER_FRAME
	for coord in _active:
		var show: bool = _chunk_dist(coord, center) <= CLUTTER_RADIUS
		if _active[coord].set_clutter_state(show, budget > 0):
			budget -= 1

# Instancie/libère les POI par anneau (POI_RADIUS). Instanciation BUDGÉTÉE (mesh lourd => 1/frame) ;
# les libérations ne sont pas plafonnées. Seuls les chunks PORTEURS d'un POI sont concernés (rares).
func _update_poi(center: Vector2i) -> void:
	var budget := MAX_POI_BUILDS_PER_FRAME
	for coord in _active:
		var chunk: TerrainChunk = _active[coord]
		if not chunk.has_poi():
			continue
		var want: bool = _chunk_dist(coord, center) <= POI_RADIUS
		if want and budget <= 0 and not chunk.has_poi_node():
			continue   # report l'instanciation d'une frame (budget épuisé)
		if chunk.set_poi_state(want, _poi_lib) and want:
			budget -= 1

# Nom du POI nommé le plus proche d'une position MONDE dans un rayon donné (mètres) — pour le
# WristComputer. { name:String ("" si aucun), distance:float }. Ignore les POI mineurs (anonymes).
func nearest_poi_name(world_pos: Vector3, radius: float) -> Dictionary:
	var best := ""
	var best_d := radius
	for coord in _active:
		var chunk: TerrainChunk = _active[coord]
		if not chunk.has_poi() or chunk.poi_name() == "":
			continue
		var d := world_pos.distance_to(chunk.poi_world_position())
		if d < best_d:
			best_d = d
			best = chunk.poi_name()
	return {"name": best, "distance": best_d}

# Instancie/libère la faune par ANNEAU SERRÉ (FAUNA_RADIUS) : les chunks lointains gardent juste
# leurs données de spawn (légères), zéro node créature. Instanciation BUDGÉTÉE (anti-hitch) : au plus
# MAX_FAUNA_BUILDS_PER_FRAME nouveaux chunks peuplés par frame (les libérations ne sont pas plafonnées).
func _update_fauna(center: Vector2i) -> void:
	var budget := MAX_FAUNA_BUILDS_PER_FRAME
	for coord in _active:
		var want := _chunk_dist(coord, center) <= FAUNA_RADIUS
		if want and budget <= 0 and _active[coord].fauna_count() == 0:
			continue   # report l'instanciation d'une frame (budget épuisé)
		if _active[coord].set_fauna_state(want, _fauna_lib, _fauna_roster, player, _fauna_pg, phys_radius, vertical_scale) and want:
			budget -= 1

func _chunk_dist(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a.x - b.x, a.y - b.y).length()

# Choisit le LOD d'un chunk selon sa distance, avec HYSTÉRÉSIS : ne change que d'un cran
# à la fois et seulement après avoir franchi la frontière d'au moins LOD_HYST (évite le
# thrashing quand le joueur stationne à une frontière). current = -1 => LOD de base direct.
const MORPH_RANGE := 0.7   # geomorph : largeur (chunks) de la rampe de morph juste avant le swap LOD

# Geomorph : facteur 0..1 par chunk = rampe de `boundary - MORPH_RANGE` à `boundary` (seuil du swap LOD).
# À 1 = forme entièrement morphée vers le LOD plus grossier => bascule sans pop. Le LOD le plus grossier
# ne morphe pas (rien de plus grossier chargé au-delà).
func _morph_factor_for(lod: int, dist: float) -> float:
	if lod < 0 or lod >= LOD_MAX_DIST.size() - 1:
		return 0.0
	var boundary: float = LOD_MAX_DIST[lod]
	return smoothstep(boundary - MORPH_RANGE, boundary, dist)

# Maj du morph_factor de TOUS les chunks actifs chaque frame (distance MONDE continue joueur→chunk =>
# morph FLUIDE, pas par paliers de chunk). Coût : ~200 chunks × (distance + smoothstep + uniform GPU).
func _update_morph() -> void:
	if player == null:
		return
	var pw := player.global_position
	for coord in _active:
		var ch: TerrainChunk = _active[coord]
		ch.set_morph(_morph_factor_for(ch.lod, pw.distance_to(ch.global_position) / CHUNK_SIZE))

func _select_lod(dist: float, current: int) -> int:
	var base := LOD_RES.size() - 1
	for l in LOD_MAX_DIST.size():
		if dist <= LOD_MAX_DIST[l]:
			base = l
			break
	if current < 0 or base == current:
		return base
	if base > current:                                  # plus loin => LOD plus grossier
		if dist > LOD_MAX_DIST[current] + LOD_HYST:
			return current + 1
	elif dist < LOD_MAX_DIST[current - 1] - LOD_HYST:   # plus près => LOD plus fin
		return current - 1
	return current

# Met à jour le LOD des chunks actifs : régénération OFF-THREAD (même tâche que le chargement)
# puis swap du mesh au drain (budgété). Nombre de régénérations enfilées par frame plafonné.
func _update_lods(center: Vector2i) -> void:
	var budget := MAX_LOD_REGENS_PER_FRAME
	for coord in _active:
		if budget <= 0:
			break
		if _pending.has(coord):
			continue
		var chunk: TerrainChunk = _active[coord]
		var desired := _select_lod(_chunk_dist(coord, center), chunk.lod)
		if desired != chunk.lod:
			_enqueue(coord, desired)   # régén OFF-THREAD ; swap_mesh au drain
			budget -= 1

func _acquire() -> TerrainChunk:
	if _pool.is_empty():
		var c := TerrainChunk.new()
		_root.add_child(c)
		return c
	return _pool.pop_back()

func _release(coord: Vector2i) -> void:
	var chunk: TerrainChunk = _active[coord]
	chunk.release()
	_pool.append(chunk)
	_active.erase(coord)

# Aplatit l'espace-planète autour de _flatten_dir (transform de PlanetRoot).
func _apply_flatten() -> void:
	if _root:
		_root.transform = FloatingOrigin.flatten(_flatten_dir, phys_radius)

# REBASE : si le joueur s'éloigne trop de l'origine monde, ré-ancre l'aplatissement
# sur sa position-planète courante et le recentre. Chunks (espace-planète) inchangés.
func _maybe_rebase() -> void:
	if player == null:
		return
	var pos := player.global_position
	if Vector2(pos.x, pos.z).length() < REBASE_THRESHOLD:
		return
	var planet_pos := _root.transform.affine_inverse() * pos
	_flatten_dir = planet_pos.normalized()
	_apply_flatten()
	player.global_position = _root.transform * planet_pos   # recentre (~ origine)
	rebased.emit(_root.transform)

func clear_all() -> void:
	for coord in _active.keys():
		_release(coord)

# Arrêt propre (décollage) : attend les workers, décharge tout, libère le pool.
func shutdown() -> void:
	set_process(false)
	player = null
	_flush_pending_tasks()
	clear_all()
	for c in _pool:
		c.queue_free()
	_pool.clear()

func _flush_pending_tasks() -> void:
	for id in _task_ids:
		WorkerThreadPool.wait_for_task_completion(id)
	_task_ids.clear()
	_pending.clear()
	_mutex.lock()
	_ready_queue.clear()
	_mutex.unlock()

func _prune_tasks() -> void:
	var still: Array[int] = []
	for id in _task_ids:
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)  # libère le slot (retour immédiat si déjà fini)
		else:
			still.append(id)
	_task_ids = still

# Vrai si le chunk sous cette position monde est chargé ET a sa collision active.
func is_ground_ready(world_pos: Vector3) -> bool:
	var c := coord_of_dir(_dir_at(world_pos))
	return c.valid and _active.has(c.coord) and _active[c.coord].has_collision

# Position monde de spawn : au-dessus du sol au point d'ancrage (origine après aplatissement).
func spawn_world_pos() -> Vector3:
	var pg := PlanetGenerator.new()
	pg.configure(seed_local)
	pg.set_flow_map(flow_map)   # phase 23 : hauteur de spawn sur le terrain érodé
	var ground_h := maxf(pg.sample_elevation(anchor_dir), PlanetGenerator.DEFAULT_SEA_LEVEL) * vertical_scale
	return Vector3(0.0, ground_h + 3.0, 0.0)

# Hauteur de sol ANALYTIQUE (sample_elevation) sous une position monde — sans dépendre de la collision
# (pas encore prête). Sert au re-calage anti-chute du joueur si la collision tarde. Réutilise le
# PlanetGenerator faune déjà configuré (avec flow_map) pour éviter une allocation.
func ground_height_at(world_pos: Vector3) -> float:
	if _fauna_pg == null:
		return world_pos.y   # pas encore configuré : ne pas déplacer
	var dir := _dir_at(world_pos)
	return maxf(_fauna_pg.sample_elevation(dir), PlanetGenerator.DEFAULT_SEA_LEVEL) * vertical_scale

# Hauteur Y RÉELLE du terrain (NON bornée au niveau de mer, contrairement à ground_height_at qui clampe à
# la mer) — pour enraciner le kelp sur le fond marin (sous le niveau de mer). Lecture seule, déterministe.
func seafloor_height_at(world_pos: Vector3) -> float:
	if _fauna_pg == null:
		return world_pos.y
	return _fauna_pg.sample_elevation(_dir_at(world_pos)) * vertical_scale

func active_count() -> int:
	return _active.size()

# Coord ESPACE-PLANÈTE du chunk sous le joueur (pour l'affichage des coordonnées).
func player_coord() -> Dictionary:
	if player == null:
		return {"valid": false, "coord": Vector2i.ZERO}
	return coord_of_dir(_dir_at(player.global_position))

# Histogramme des LOD des chunks actifs : [nb LOD0, nb LOD1, ...] (diagnostic).
func lod_histogram() -> Array:
	var h := [0, 0, 0, 0]
	for coord in _active:
		var l: int = _active[coord].lod
		if l >= 0 and l < h.size():
			h[l] += 1
	return h

# Total d'instances de végétation actuellement construites (diagnostic perf).
func vegetation_instance_count() -> int:
	var n := 0
	for coord in _active:
		n += _active[coord].vegetation_instance_count()
	return n

# Total d'instances de végétation VISIBLES (diagnostic rayon).
func visible_vegetation_instance_count() -> int:
	var n := 0
	for coord in _active:
		n += _active[coord].visible_vegetation_instance_count()
	return n

# Total d'instances de clutter VISIBLES (diagnostic anneau/perf — phase 20 couche B).
func visible_clutter_instance_count() -> int:
	var n := 0
	for coord in _active:
		n += _active[coord].visible_clutter_instance_count()
	return n

# Nombre de chunks actifs PORTEURS d'un POI (descripteur) — phase 20 couche C (diagnostic).
func poi_descriptor_count() -> int:
	var n := 0
	for coord in _active:
		if _active[coord].has_poi():
			n += 1
	return n

# Nombre de POI réellement INSTANCIÉS (Node3D présents) — phase 20 couche C (diagnostic anneau/perf).
func poi_active_count() -> int:
	var n := 0
	for coord in _active:
		if _active[coord].has_poi_node():
			n += 1
	return n

# Phase 22 : POI (catégorie/seed/pos/nom) dans un rayon MONDE autour d'une position — pour POIAudio.
func pois_near(world_pos: Vector3, radius: float) -> Array:
	var out := []
	for coord in _active:
		var c: TerrainChunk = _active[coord]
		if not c.has_poi():
			continue
		var p := c.poi_world_position()
		if world_pos.distance_to(p) <= radius:
			out.append({"category": c.poi_category(), "seed": c.poi_seed(), "pos": p, "name": c.poi_name()})
	return out

# Phase 22 : biome sous une position MONDE (pour l'audio de pas). Repli PLAINS si non configuré.
func biome_at_world(world_pos: Vector3) -> int:
	if _fauna_pg == null:
		return PlanetGenerator.Biome.PLAINS
	var dir := _dir_at(world_pos)
	return _fauna_pg.sample_biome(dir, _fauna_pg.sample_elevation(dir))

# Total d'impostors d'arbres visibles (diagnostic tier lointain).
func impostor_instance_count() -> int:
	var n := 0
	for coord in _active:
		n += _active[coord].impostor_instance_count()
	return n

# Total de MultiMesh végétation VISIBLES (≈ draw calls de végétation) — diagnostic perf.
func visible_vegetation_node_count() -> int:
	var n := 0
	for coord in _active:
		n += _active[coord].visible_vegetation_node_count()
	return n

# Total de nodes MultiMeshInstance3D détenus (actifs + pool) — diagnostic pooling/mémoire.
func vegetation_node_count() -> int:
	var n := 0
	for coord in _active:
		n += _active[coord].vegetation_node_count()
	for ch in _pool:
		n += ch.vegetation_node_count()
	return n

# Total de colliders d'arbres actifs (diagnostic collision végétation).
func vegetation_collider_count() -> int:
	var n := 0
	for coord in _active:
		n += _active[coord].vegetation_collider_count()
	return n

func pool_count() -> int:
	return _pool.size()

func pending_count() -> int:
	return _pending.size()
