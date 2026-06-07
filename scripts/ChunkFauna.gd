class_name ChunkFauna
extends RefCounted
## Semis de FAUNE d'UN chunk (phase 19), 100% déterministe et PUR (thread-safe => exécuté dans la
## tâche de fond du chunk, comme VegetationSeeder phase 8). Ne touche NI scène NI mesh : calcule
## seulement une liste de spawns { species_idx, local (repère du chunk), yaw }. L'instanciation des
## Creature (main-thread, budgétée) est faite ailleurs.
##
## Faible densité (créatures grosses, pas d'insectes) : petite grille de candidats, faible proba.
## Filtre : au-dessus du niveau de mer, pente douce. Le choix d'espèce suit une PRÉFÉRENCE DOUCE de
## biome : pleine densité dans le biome préféré, densité réduite ailleurs (présence partout sur terre
## ferme, jamais de zone totalement vide — le joueur démarre à pied au hasard et doit croiser la vie).
## RNG seedé par (planète + coord ESPACE-PLANÈTE) => mêmes créatures au même endroit (invariant rebase).

const FAUNA_GRID := 4       # 4x4 = 16 candidats / chunk (cellule ~64 m sur chunk de 256 m)
const SPAWN_CHANCE := 0.4   # proba qu'une cellule éligible fasse apparaître une créature
const OFF_BIOME_FACTOR := 0.3  # poids relatif d'une espèce hors de son biome préféré (présence diffuse)
const MAX_PER_CHUNK := 7     # plafond d'instances par chunk (budget ; relevé pour « davantage de tortues »)
const MAX_SLOPE := 0.7      # tan(angle) max : pas de créatures sur falaises
const SLOPE_EPS := 4.0      # mètres : pas pour l'estimation de pente

# Renvoie Array de { species_idx:int, local:Vector3, yaw:float } en repère LOCAL du chunk (mêmes
# (anchor_dir, east, north, phys_radius, vertical_scale) que SurfaceGenerator.generate_chunk).
static func seed_chunk(seed_local: int, cx: int, cz: int, roster: Array, anchor_dir: Vector3, east: Vector3, north: Vector3, chunk_size: float, phys_radius: float, vertical_scale: float, flow_map: PlanetFlowMap = null, shared_pg: PlanetGenerator = null) -> Array:
	var out := []
	if roster.is_empty():
		return out
	var pg: PlanetGenerator = shared_pg
	if pg == null:
		pg = PlanetGenerator.new()
		pg.configure(seed_local)
		pg.set_flow_map(flow_map)   # phase 23 : la faune suit le terrain érodé
	var sea := PlanetGenerator.DEFAULT_SEA_LEVEL

	var rng := RandomNumberGenerator.new()
	rng.seed = _chunk_seed(seed_local, cx, cz)

	# Repère tangent au CENTRE du chunk (le mesh y est exprimé) => transforms en local.
	var cgx := cx * chunk_size + chunk_size * 0.5
	var cgz := cz * chunk_size + chunk_size * 0.5
	var dir_c := (anchor_dir * phys_radius + east * cgx + north * cgz).normalized()
	var center := dir_c * phys_radius
	var inv := FloatingOrigin.tangent_basis(dir_c).inverse()

	var cell := chunk_size / FAUNA_GRID
	var n := 0
	for j in FAUNA_GRID:
		for i in FAUNA_GRID:
			if n >= MAX_PER_CHUNK:
				break
			var gx := cx * chunk_size + (i + rng.randf()) * cell
			var gz := cz * chunk_size + (j + rng.randf()) * cell
			var dir := _dir(anchor_dir, east, north, phys_radius, gx, gz)
			var e := pg.sample_elevation(dir)
			if e < sea:
				continue
			if flow_map and (flow_map.is_lake_at(dir) or flow_map.river_at(dir) > PlanetFlowMap.WATER_THRESHOLD):
				continue   # phase 23 : pas de faune dans l'eau (rivière/lac)
			var biome := pg.sample_biome(dir, e)
			# Phase 20 couche A : porte de spawn modulée par la densité de faune du biome (PopulationTuning).
			if rng.randf() > PopulationTuning.scaled_prob(SPAWN_CHANCE, PopulationTuning.fauna_density(biome)):
				continue
			var slope := _slope(pg, anchor_dir, east, north, phys_radius, vertical_scale, gx, gz)
			if slope > MAX_SLOPE:
				continue
			var si := _pick_species(roster, biome, rng)
			if si < 0:
				continue
			var local := _local_pos(inv, dir, center, e, sea, phys_radius, vertical_scale)
			out.append({"species_idx": si, "local": local, "yaw": rng.randf() * TAU})
			n += 1
	return out

# Choisit une espèce par PRÉFÉRENCE DOUCE de biome : poids = densité (×OFF_BIOME_FACTOR hors du
# biome préféré). Renvoie toujours une espèce valide si le roster est non vide (terre jamais vide).
static func _pick_species(roster: Array, biome: int, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for k in roster.size():
		total += _weight(roster[k], biome)
	if total <= 0.0:
		return -1
	var r := rng.randf() * total
	for k in roster.size():
		r -= _weight(roster[k], biome)
		if r <= 0.0:
			return k
	return roster.size() - 1

# Poids de spawn d'une espèce dans un biome donné (densité pleine si biome préféré, réduite sinon).
static func _weight(species: Dictionary, biome: int) -> float:
	var w: float = species.density
	if int(species.biome) != biome:
		w *= OFF_BIOME_FACTOR
	return w

# --- Helpers géométriques (mêmes formules que VegetationSeeder / SurfaceGenerator) ---

static func _dir(anchor_dir: Vector3, east: Vector3, north: Vector3, phys_radius: float, gx: float, gz: float) -> Vector3:
	return (anchor_dir * phys_radius + east * gx + north * gz).normalized()

static func _local_pos(inv: Basis, dir: Vector3, center: Vector3, e: float, sea: float, phys_radius: float, vertical_scale: float) -> Vector3:
	var sphere_pos := dir * (phys_radius + maxf(e, sea) * vertical_scale)
	return inv * (sphere_pos - center)

static func _slope(pg: PlanetGenerator, anchor_dir: Vector3, east: Vector3, north: Vector3, phys_radius: float, vertical_scale: float, gx: float, gz: float) -> float:
	var ex := pg.sample_elevation(_dir(anchor_dir, east, north, phys_radius, gx + SLOPE_EPS, gz)) - pg.sample_elevation(_dir(anchor_dir, east, north, phys_radius, gx - SLOPE_EPS, gz))
	var ez := pg.sample_elevation(_dir(anchor_dir, east, north, phys_radius, gx, gz + SLOPE_EPS)) - pg.sample_elevation(_dir(anchor_dir, east, north, phys_radius, gx, gz - SLOPE_EPS))
	var dhx := ex * vertical_scale / (2.0 * SLOPE_EPS)
	var dhz := ez * vertical_scale / (2.0 * SLOPE_EPS)
	return sqrt(dhx * dhx + dhz * dhz)

# Seed de chunk stable (planète + coord espace-planète), SEL DISTINCT de la végétation (positions
# de faune décorrélées des plantes). Invariant au rebase.
static func _chunk_seed(seed_local: int, cx: int, cz: int) -> int:
	var h := (seed_local + 9173) * 374761393
	h ^= cx * 668265263
	h ^= cz * 2147483647
	return h
