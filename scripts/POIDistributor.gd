class_name POIDistributor
extends RefCounted
## Phase 20 — COUCHE C : décide, pour UN chunk, s'il porte un POI, lequel, où, et son nom. 100%
## déterministe et PUR (thread-safe => exécuté dans la tâche de fond du chunk). Renvoie un POIInstance
## (descripteur léger) ou null. La RARETÉ (~9 %/chunk) crée naturellement l'espacement (pas de
## Poisson-disk). Catégorie = tirage PONDÉRÉ par biome (+ légère modulation d'altitude).

const POI_CHANCE := 0.12       # proba qu'un chunk porte un POI (rareté ; océan/pente réduisent l'effectif)
const MAX_SLOPE := 0.5         # tan(angle) max au centre : POI sur sol modéré
const SEA_MARGIN := 0.02       # élévation min au-dessus du niveau de mer (clairement sur terre)
const SLOPE_EPS := 5.0
# Anti-flottement : le mesh de terrain LOINTAIN est à LOD grossier => il MOYENNE le détail haute
# fréquence (~±2.5 m) du sol. On place donc le POI à l'élévation MOYENNE de son EMPREINTE (≈ surface
# affichée) plutôt qu'à l'élévation ponctuelle exacte ; + léger enfoncement. On ne rejette que les
# emplacements VRAIMENT accidentés (falaise), où aucun placement ne tiendrait.
const FOOT_RADIUS := 4.5       # m : demi-empreinte échantillonnée
const FLAT_TOL := 6.0          # m : variation max tolérée sur l'empreinte (au-delà = cliff, on renonce)
const EMBED := 0.4             # m : enfoncement de la base (ancrage, anti-flottement résiduel)

# Poids de catégorie par biome : [ [POILibrary.Category, poids], ... ]. Couvre les 16 catégories.
const W := {
	PlanetGenerator.Biome.BEACH: [
		[POILibrary.Category.NATURAL_ARCH, 1.0], [POILibrary.Category.LONE_DUNE, 1.6],
		[POILibrary.Category.RUINED_ARCH, 0.8], [POILibrary.Category.BEACON, 1.1],
		[POILibrary.Category.MONOLITH, 0.7], [POILibrary.Category.CAIRN, 0.5],
	],
	PlanetGenerator.Biome.PLAINS: [
		[POILibrary.Category.GIANT_TREE, 1.2], [POILibrary.Category.HOODOO, 0.7],
		[POILibrary.Category.LONE_DUNE, 0.7], [POILibrary.Category.STONE_CIRCLE, 1.0],
		[POILibrary.Category.ALTAR, 1.0], [POILibrary.Category.RUINED_ARCH, 1.0],
		[POILibrary.Category.MONOLITH, 1.0], [POILibrary.Category.CAIRN, 0.6],
		[POILibrary.Category.BEACON, 0.8], [POILibrary.Category.NATURAL_ARCH, 0.6],
		[POILibrary.Category.GEYSER, 0.4],
	],
	PlanetGenerator.Biome.FOREST: [
		[POILibrary.Category.GIANT_TREE, 1.6], [POILibrary.Category.BIOLUM_GROVE, 1.4],
		[POILibrary.Category.ALTAR, 0.9], [POILibrary.Category.MONOLITH, 0.8],
		[POILibrary.Category.HOT_SPRING, 0.6], [POILibrary.Category.CAIRN, 0.5],
		[POILibrary.Category.STONE_CIRCLE, 0.6],
	],
	PlanetGenerator.Biome.ROCK: [
		[POILibrary.Category.GEYSER, 1.1], [POILibrary.Category.CRYSTAL_FOREST, 1.2],
		[POILibrary.Category.BASALT_COLUMNS, 1.3], [POILibrary.Category.HOODOO, 1.2],
		[POILibrary.Category.NATURAL_ARCH, 1.0], [POILibrary.Category.HOT_SPRING, 0.7],
		[POILibrary.Category.MONOLITH, 1.0], [POILibrary.Category.CAIRN, 1.0],
		[POILibrary.Category.STONE_CIRCLE, 0.7], [POILibrary.Category.BEACON, 0.7],
	],
	PlanetGenerator.Biome.SNOW: [
		[POILibrary.Category.FROZEN_WATERFALL, 1.4], [POILibrary.Category.CRYSTAL_FOREST, 1.0],
		[POILibrary.Category.HOT_SPRING, 0.8], [POILibrary.Category.GEYSER, 0.7],
		[POILibrary.Category.CAIRN, 1.0], [POILibrary.Category.MONOLITH, 0.8],
	],
}

# Renvoie un POIInstance (descripteur, repère LOCAL du chunk) ou null si pas de POI dans ce chunk.
static func seed_chunk(seed_local: int, cx: int, cz: int, palette_id: int, anchor_dir: Vector3, east: Vector3, north: Vector3, chunk_size: float, phys_radius: float, vertical_scale: float, flow_map: PlanetFlowMap = null, shared_pg: PlanetGenerator = null) -> POIInstance:
	var rng := RandomNumberGenerator.new()
	rng.seed = _chunk_seed(seed_local, cx, cz)
	if rng.randf() > POI_CHANCE:
		return null

	var pg: PlanetGenerator = shared_pg
	if pg == null:
		pg = PlanetGenerator.new()
		pg.configure(seed_local)
		pg.set_flow_map(flow_map)   # phase 23 : les POI suivent le terrain érodé
	var sea := PlanetGenerator.DEFAULT_SEA_LEVEL

	# Position vers le CENTRE du chunk (jitter borné => le POI ne chevauche pas les bords voisins).
	var gx := cx * chunk_size + chunk_size * rng.randf_range(0.3, 0.7)
	var gz := cz * chunk_size + chunk_size * rng.randf_range(0.3, 0.7)
	var dir := _dir(anchor_dir, east, north, phys_radius, gx, gz)
	var e := pg.sample_elevation(dir)
	if e < sea + SEA_MARGIN:
		return null
	if flow_map and (flow_map.is_lake_at(dir) or flow_map.river_at(dir) > PlanetFlowMap.WATER_THRESHOLD):
		return null   # phase 23 : pas de POI dans l'eau (rivière/lac)
	var slope := _slope(pg, anchor_dir, east, north, phys_radius, vertical_scale, gx, gz)
	if slope > MAX_SLOPE:
		return null
	# Anti-flottement : échantillonne l'empreinte. Rejette si VRAIMENT accidentée (cliff) ; sinon on
	# placera le POI à l'élévation MOYENNE (cf. plus bas) = ce que le mesh LOD lointain approxime.
	var fp := _footprint(pg, anchor_dir, east, north, phys_radius, gx, gz, e)
	if float(fp.spread) * vertical_scale > FLAT_TOL:
		return null
	var biome := pg.sample_biome(dir, e)
	var alt := clampf((e - sea) / PlanetGenerator.LAND_SPAN, 0.0, 1.0)
	var category := _pick_category(biome, alt, rng)
	if category < 0:
		return null

	# Repère tangent au CENTRE du chunk (comme les semis) => transform en local.
	var cgx := cx * chunk_size + chunk_size * 0.5
	var cgz := cz * chunk_size + chunk_size * 0.5
	var dir_c := (anchor_dir * phys_radius + east * cgx + north * cgz).normalized()
	var center := dir_c * phys_radius
	var inv := FloatingOrigin.tangent_basis(dir_c).inverse()
	# Élévation MOYENNE de l'empreinte (≈ surface du mesh LOD lointain) + enfoncement léger (EMBED) :
	# le repère repose sur la surface affichée au lieu de flotter au-dessus du détail haute fréquence.
	var e_place: float = maxf(float(fp.mean), sea)
	var sphere_pos := dir * (phys_radius + e_place * vertical_scale)
	var local := inv * (sphere_pos - center) - Vector3(0.0, EMBED, 0.0)

	var poi := POIInstance.new()
	poi.category = category
	poi.seed_val = _poi_seed(seed_local, cx, cz)
	poi.local_transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU), local)
	# Nommage : seuls les POI NOTABLES reçoivent un nom (palette régionale du système, phase 19.5).
	if POILibrary.is_named(category):
		poi.poi_name = NameGenerator.generate_name(poi.seed_val, palette_id)
	return poi

# Tirage pondéré d'une catégorie selon le biome, avec légère modulation d'altitude (certains POI
# « hauts » favorisés en altitude, certains « bas » favorisés près de la mer).
static func _pick_category(biome: int, alt: float, rng: RandomNumberGenerator) -> int:
	if not W.has(biome):
		return -1
	var table: Array = W[biome]
	var total := 0.0
	var weights := []
	for entry in table:
		var w: float = entry[1] * _alt_factor(entry[0], alt)
		weights.append(w)
		total += w
	if total <= 0.0:
		return -1
	var r := rng.randf() * total
	for k in table.size():
		r -= weights[k]
		if r <= 0.0:
			return table[k][0]
	return table[table.size() - 1][0]

# Multiplicateur d'altitude par catégorie (1.0 = neutre). Subtil : renforce la cohérence du lieu.
static func _alt_factor(category: int, alt: float) -> float:
	match category:
		POILibrary.Category.CAIRN, POILibrary.Category.CRYSTAL_FOREST, POILibrary.Category.FROZEN_WATERFALL:
			return 0.6 + alt              # plus probables en altitude
		POILibrary.Category.LONE_DUNE, POILibrary.Category.BEACON, POILibrary.Category.NATURAL_ARCH:
			return 1.4 - 0.7 * alt        # plus probables en plaine basse
	return 1.0

# --- Helpers géométriques (mêmes formules que les seeders) ---

static func _dir(anchor_dir: Vector3, east: Vector3, north: Vector3, phys_radius: float, gx: float, gz: float) -> Vector3:
	return (anchor_dir * phys_radius + east * gx + north * gz).normalized()

static func _slope(pg: PlanetGenerator, anchor_dir: Vector3, east: Vector3, north: Vector3, phys_radius: float, vertical_scale: float, gx: float, gz: float) -> float:
	var ex := pg.sample_elevation(_dir(anchor_dir, east, north, phys_radius, gx + SLOPE_EPS, gz)) - pg.sample_elevation(_dir(anchor_dir, east, north, phys_radius, gx - SLOPE_EPS, gz))
	var ez := pg.sample_elevation(_dir(anchor_dir, east, north, phys_radius, gx, gz + SLOPE_EPS)) - pg.sample_elevation(_dir(anchor_dir, east, north, phys_radius, gx, gz - SLOPE_EPS))
	var dhx := ex * vertical_scale / (2.0 * SLOPE_EPS)
	var dhz := ez * vertical_scale / (2.0 * SLOPE_EPS)
	return sqrt(dhx * dhx + dhz * dhz)

# Échantillonne l'empreinte (rayon FOOT_RADIUS) autour du POI. Renvoie { mean, spread } d'élévation
# (unités de bruit) : 'mean' ≈ ce qu'affiche le mesh LOD grossier (détail haute fréquence moyenné),
# 'spread' = amplitude (détecte les cliffs). PUR + thread-safe.
static func _footprint(pg: PlanetGenerator, anchor_dir: Vector3, east: Vector3, north: Vector3, phys_radius: float, gx: float, gz: float, e_center: float) -> Dictionary:
	var emin := e_center
	var emax := e_center
	var sum := e_center
	var d := FOOT_RADIUS
	var offsets := [Vector2(d, 0.0), Vector2(-d, 0.0), Vector2(0.0, d), Vector2(0.0, -d), Vector2(d * 0.7, d * 0.7), Vector2(-d * 0.7, -d * 0.7)]
	for off in offsets:
		var ee := pg.sample_elevation(_dir(anchor_dir, east, north, phys_radius, gx + off.x, gz + off.y))
		emin = minf(emin, ee)
		emax = maxf(emax, ee)
		sum += ee
	return {"mean": sum / float(offsets.size() + 1), "spread": emax - emin}

# Seed du tirage de présence/placement (planète + coord espace-planète + SEL distinct). Invariant rebase.
static func _chunk_seed(seed_local: int, cx: int, cz: int) -> int:
	var h := (seed_local + 91207) * 2246822519
	h ^= cx * 3266489917
	h ^= cz * 668265263
	return h

# Seed propre du POI (mesh + nom) : distinct du seed de présence.
static func _poi_seed(seed_local: int, cx: int, cz: int) -> int:
	var h := (seed_local + 778187) * 374761393
	h ^= cx * 2654435761
	h ^= cz * 40503671
	return h
