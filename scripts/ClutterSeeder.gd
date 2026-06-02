class_name ClutterSeeder
extends RefCounted
## Phase 20 — COUCHE B : semis de CLUTTER d'UN chunk, 100% déterministe et PUR (thread-safe =>
## exécuté dans la MÊME tâche de fond que le mesh + la végétation du chunk). Ne touche NI scène NI
## mesh : calcule seulement des tableaux de Transform3D (repère LOCAL du chunk) par variante de
## ClutterLibrary. Le rendu (MultiMesh) est fait ailleurs, sur le thread principal.
##
## Grille DENSE (petits objets) ; choix de catégorie PONDÉRÉ par le biome × PopulationTuning. RNG
## seedé par (seed planète + coord ESPACE-PLANÈTE + SEL distinct) => mêmes objets au même endroit
## (invariant rebase), décorrélés de la végétation et de la faune.

const CLUTTER_GRID := 16     # 16x16 = 256 candidats / chunk (cellule ~16 m sur chunk de 256 m)
const BASE_FILL := 0.42      # proba de base qu'une cellule éligible porte un objet (× densité biome)
const MAX_PER_CHUNK := 230   # plafond d'instances par chunk (budget)
const MAX_SLOPE := 1.0       # tan(angle) max : pas de débris sur falaises (reste sur pentes douces/moyennes)
const SLOPE_EPS := 4.0       # mètres : pas pour l'estimation de pente

# Renvoie { variant:int -> Array[Transform3D] } en repère LOCAL du chunk (mêmes paramètres
# (anchor_dir, east, north, phys_radius, vertical_scale) que SurfaceGenerator.generate_chunk).
static func seed_chunk(seed_local: int, cx: int, cz: int, anchor_dir: Vector3, east: Vector3, north: Vector3, chunk_size: float, phys_radius: float, vertical_scale: float, flow_map: PlanetFlowMap = null) -> Dictionary:
	var pg := PlanetGenerator.new()
	pg.configure(seed_local)
	pg.set_flow_map(flow_map)   # phase 23 : le clutter suit le terrain érodé
	var sea := PlanetGenerator.DEFAULT_SEA_LEVEL

	var rng := RandomNumberGenerator.new()
	rng.seed = _chunk_seed(seed_local, cx, cz)

	# Repère tangent au CENTRE du chunk (le mesh y est exprimé) => transforms en local.
	var cgx := cx * chunk_size + chunk_size * 0.5
	var cgz := cz * chunk_size + chunk_size * 0.5
	var dir_c := (anchor_dir * phys_radius + east * cgx + north * cgz).normalized()
	var center := dir_c * phys_radius
	var inv := FloatingOrigin.tangent_basis(dir_c).inverse()

	var out := {}
	var count := 0
	var cell := chunk_size / CLUTTER_GRID
	for j in CLUTTER_GRID:
		for i in CLUTTER_GRID:
			if count >= MAX_PER_CHUNK:
				break
			var gx := cx * chunk_size + (i + rng.randf()) * cell
			var gz := cz * chunk_size + (j + rng.randf()) * cell
			var dir := _dir(anchor_dir, east, north, phys_radius, gx, gz)
			var e := pg.sample_elevation(dir)
			if e < sea:
				continue
			if flow_map and (flow_map.is_lake_at(dir) or flow_map.river_at(dir) > PlanetFlowMap.WATER_THRESHOLD):
				continue   # phase 23 : pas de clutter dans l'eau (rivière/lac)
			var biome := pg.sample_biome(dir, e)
			var dens := PopulationTuning.clutter_density(biome)
			if rng.randf() > PopulationTuning.scaled_prob(BASE_FILL, dens):
				continue
			var slope := _slope(pg, anchor_dir, east, north, phys_radius, vertical_scale, gx, gz)
			if slope > MAX_SLOPE:
				continue
			var v := _pick_clutter(biome, pg.sample_humidity(dir), rng)
			if v < 0:
				continue
			var local := _local_pos(inv, dir, center, e, sea, phys_radius, vertical_scale)
			_append(out, v, _instance_transform(v, local, rng))
			count += 1
	return out

# Choisit une variante de clutter PONDÉRÉE par le biome (ou -1). Cailloux partout ; brindilles/feuilles
# en zones végétalisées ; coquillages côtiers ; ossements rares (ton mélancolique, jamais macabre).
static func _pick_clutter(biome: int, humidity: float, rng: RandomNumberGenerator) -> int:
	# Poids par catégorie [pebble, twig, bone, leaf, shell] selon le biome.
	var w: Array
	match biome:
		PlanetGenerator.Biome.BEACH:
			w = [3.0, 0.2, 0.5, 0.3, 3.0]
		PlanetGenerator.Biome.PLAINS:
			w = [3.0, 1.0, 0.4, 1.5, 0.3]
		PlanetGenerator.Biome.FOREST:
			w = [1.5, 3.0, 0.3, 3.0, 0.1]
		PlanetGenerator.Biome.ROCK:
			w = [4.0, 0.2, 0.5, 0.1, 0.0]
		PlanetGenerator.Biome.SNOW:
			w = [2.0, 0.2, 0.4, 0.1, 0.0]
		_:
			return -1
	var total := 0.0
	for x in w:
		total += x
	if total <= 0.0:
		return -1
	var r := rng.randf() * total
	var cat := 0
	for k in w.size():
		r -= w[k]
		if r <= 0.0:
			cat = k
			break
	# Catégorie -> variante concrète (pioche parmi les variantes ; feuilles selon biome/humidité).
	match cat:
		0:
			return ClutterLibrary.PEBBLE_VARIANTS[rng.randi() % ClutterLibrary.PEBBLE_VARIANTS.size()]
		1:
			return ClutterLibrary.TWIG_VARIANTS[rng.randi() % ClutterLibrary.TWIG_VARIANTS.size()]
		2:
			return ClutterLibrary.BONE_VARIANTS[rng.randi() % ClutterLibrary.BONE_VARIANTS.size()]
		3:
			# Feuille fraîche/pétale surtout en forêt humide ; feuille morte ailleurs.
			if biome == PlanetGenerator.Biome.FOREST and rng.randf() < 0.4 + 0.3 * humidity:
				return ClutterLibrary.V_LEAF_FRESH
			return ClutterLibrary.V_LEAF_DRY
		_:
			return ClutterLibrary.V_SHELL

# Transform d'instance par catégorie : lacet + inclinaison + échelle ; coquillage couché sur le flanc.
static func _instance_transform(variant: int, local: Vector3, rng: RandomNumberGenerator) -> Transform3D:
	var yaw := rng.randf() * TAU
	var b := Basis(Vector3.UP, yaw)
	if variant in ClutterLibrary.LEAF_VARIANTS:
		# Feuille : quasi à plat, infime inclinaison, échelle modérée.
		b = Basis.from_euler(Vector3(rng.randf_range(-0.12, 0.12), yaw, rng.randf_range(-0.12, 0.12)))
		var sl := rng.randf_range(0.7, 1.4)
		return Transform3D(b.scaled(Vector3(sl, sl, sl)), local)
	if variant == ClutterLibrary.V_SHELL:
		# Coquillage : couché sur le flanc (axe d'enroulement ~ horizontal) + lacet, légèrement enfoncé.
		b = Basis.from_euler(Vector3(rng.randf_range(1.1, 1.5), yaw, rng.randf_range(-0.2, 0.2)))
		var ss := rng.randf_range(0.6, 1.1)
		return Transform3D(b.scaled(Vector3(ss, ss, ss)), local - Vector3(0.0, 0.03, 0.0))
	# Cailloux / brindilles / os : léger basculement + échelle + enfoncement (ancre dans le sol,
	# anti-flottement face à l'interpolation du mesh LOD ; les feuilles plates restent en surface).
	b = Basis.from_euler(Vector3(rng.randf_range(-0.18, 0.18), yaw, rng.randf_range(-0.18, 0.18)))
	var s := rng.randf_range(0.6, 1.5)
	return Transform3D(b.scaled(Vector3(s, s * rng.randf_range(0.8, 1.05), s)), local - Vector3(0.0, 0.05, 0.0))

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

static func _append(out: Dictionary, variant: int, t: Transform3D) -> void:
	if not out.has(variant):
		out[variant] = []
	out[variant].append(t)

# Seed de chunk stable (planète + coord espace-planète), SEL DISTINCT (positions décorrélées de la
# végétation et de la faune). Invariant au rebase.
static func _chunk_seed(seed_local: int, cx: int, cz: int) -> int:
	var h := (seed_local + 50321) * 2654435761
	h ^= cx * 40503671
	h ^= cz * 1900813
	return h
