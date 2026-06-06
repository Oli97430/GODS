class_name VegetationSeeder
extends RefCounted
## Semis de végétation d'UN chunk, 100% déterministe et PUR (thread-safe => exécuté dans
## la même tâche de fond que le mesh du chunk). Ne touche NI scène NI mesh : calcule
## seulement des tableaux de Transform3D (repère LOCAL du chunk, identique au mesh) par
## variante de la VegetationLibrary. Le rendu (MultiMesh) est fait ailleurs, sur le
## thread principal.
##
## Pilotage : RNG seedé par (seed planète + coord ESPACE-PLANÈTE) => même chunk = même
## végétation à chaque chargement et après rebase. Type/densité dérivés du biome
## (PlanetGenerator.sample_biome/sample_humidity) + de la pente. Rien sous le niveau de
## mer, ni sur neige ; pas d'arbres sur pentes fortes ; herbe en plaine ; rochers plus haut.

const TREE_GRID := 34       # grille de candidats arbres/rochers (34x34 ≈ 1156 ; ×2 forêt)
const GRASS_GRID := 130     # grille de candidats herbe (130x130 ≈ 17k ; TAPIS très dense ×~20)
const MAX_TREES := 1120     # ×2 : forêt deux fois plus dense (surveiller framerate + chargement chunks)
const MAX_ROCKS := 44
const MAX_GRASS := 20000    # ×20 : tapis d'herbe très dense (touffes allégées à 3 brins pour le framerate)
const TREE_MAX_SLOPE := 0.6 # tan(angle) max pour les arbres (~31°)
const TREE_SIZE_MULT := 1.4 # arbres 40% plus gros : multiplie l'échelle PAR INSTANCE (la capsule de collision suit via t.basis.get_scale)
const SLOPE_EPS := 4.0      # mètres : pas pour l'estimation de pente
const RIVER_BANK_BOOST := 1.8   # phase 23 : densité de végétation × jusqu'à (1+ce) sur les berges de rivière
const RIVER_WATER_THR := PlanetFlowMap.WATER_THRESHOLD   # phase 23 : au-dessus => DANS l'eau (rien n'y pousse)
const WIND_LEAN_AZIMUTH := 0.7   # phase 24 : azimut du vent dominant (les troncs penchent légèrement vers lui)

# Renvoie { variant:int -> Array[Transform3D] } en repère LOCAL du chunk (mêmes
# (anchor_dir, east, north, phys_radius, vertical_scale) que SurfaceGenerator.generate_chunk).
static func seed_chunk(seed_local: int, cx: int, cz: int, anchor_dir: Vector3, east: Vector3, north: Vector3, chunk_size: float, phys_radius: float, vertical_scale: float, flow_map: PlanetFlowMap = null, shared_pg: PlanetGenerator = null) -> Dictionary:
	var pg: PlanetGenerator = shared_pg
	if pg == null:
		pg = PlanetGenerator.new()
		pg.configure(seed_local)
		pg.set_flow_map(flow_map)   # phase 23 : la végétation suit le terrain érodé (pas de flottement)
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
	var n_trees := 0
	var n_rocks := 0
	var n_grass := 0

	# --- Passe 1 : arbres + rochers (grille modérée, pente prise en compte) ---
	var tcell := chunk_size / TREE_GRID
	for j in TREE_GRID:
		for i in TREE_GRID:
			if n_trees >= MAX_TREES and n_rocks >= MAX_ROCKS:
				break
			var gx := cx * chunk_size + (i + rng.randf()) * tcell
			var gz := cz * chunk_size + (j + rng.randf()) * tcell
			var dir := _dir(anchor_dir, east, north, phys_radius, gx, gz)
			var e := pg.sample_elevation(dir)
			if e < sea:
				continue
			# Perf : UN warp FlowMap mutualisé + samplers raw + humidité calculée une fois.
			var wdir := flow_map.warp(dir) if flow_map != null else dir
			if flow_map != null and (flow_map.is_lake_raw(wdir) or flow_map.river_raw(wdir) > RIVER_WATER_THR):
				continue   # phase 23 : pas de végétation dans l'eau (rivière/lac)
			var humidity := pg.sample_humidity(dir)
			var biome := pg.sample_biome_h(dir, e, humidity)
			var slope := _slope(pg, anchor_dir, east, north, phys_radius, vertical_scale, gx, gz)
			var bank := 1.0
			if flow_map != null and flow_map.water_prox_raw(wdir) > 0.01:   # scan dilaté de berge SEULEMENT près de l'eau
				bank = 1.0 + RIVER_BANK_BOOST * flow_map.river_tint_at(dir)
			var v := _pick_tree_rock(biome, slope, humidity, rng, bank)
			if v < 0:
				continue
			if v in VegetationLibrary.TREE_VARIANTS:
				if n_trees >= MAX_TREES:
					continue
				n_trees += 1
			else:
				if n_rocks >= MAX_ROCKS:
					continue
				n_rocks += 1
			_append(out, v, _instance_transform(v, _local_pos(inv, dir, center, e, sea, phys_radius, vertical_scale), rng))

	# --- Passe 2 : herbe (grille dense, sans pente) ---
	var gcell := chunk_size / GRASS_GRID
	for j in GRASS_GRID:
		for i in GRASS_GRID:
			if n_grass >= MAX_GRASS:
				break
			var gx := cx * chunk_size + (i + rng.randf()) * gcell
			var gz := cz * chunk_size + (j + rng.randf()) * gcell
			var dir := _dir(anchor_dir, east, north, phys_radius, gx, gz)
			var e := pg.sample_elevation(dir)
			if e < sea:
				continue
			var wdir := flow_map.warp(dir) if flow_map != null else dir   # 1 warp mutualisé
			if flow_map != null and (flow_map.is_lake_raw(wdir) or flow_map.river_raw(wdir) > RIVER_WATER_THR):
				continue   # phase 23 : pas d'herbe dans l'eau
			var humidity := pg.sample_humidity(dir)
			var biome := pg.sample_biome_h(dir, e, humidity)
			var bank := 1.0
			if flow_map != null and flow_map.water_prox_raw(wdir) > 0.01:
				bank = 1.0 + RIVER_BANK_BOOST * flow_map.river_tint_at(dir)
			var v := _pick_grass(biome, humidity, rng, bank)
			if v < 0:
				continue
			n_grass += 1
			_append(out, v, _instance_transform(v, _local_pos(inv, dir, center, e, sea, phys_radius, vertical_scale), rng))

	return out

# Direction-planète d'une coord tangente globale (gnomonique, comme generate_chunk).
static func _dir(anchor_dir: Vector3, east: Vector3, north: Vector3, phys_radius: float, gx: float, gz: float) -> Vector3:
	return (anchor_dir * phys_radius + east * gx + north * gz).normalized()

# Position LOCALE (repère du chunk) posée sur le sol, identique au mesh du terrain.
static func _local_pos(inv: Basis, dir: Vector3, center: Vector3, e: float, sea: float, phys_radius: float, vertical_scale: float) -> Vector3:
	var sphere_pos := dir * (phys_radius + maxf(e, sea) * vertical_scale)
	return inv * (sphere_pos - center)

# Pente (tan de l'angle) par différences finies de l'élévation autour du point.
static func _slope(pg: PlanetGenerator, anchor_dir: Vector3, east: Vector3, north: Vector3, phys_radius: float, vertical_scale: float, gx: float, gz: float) -> float:
	var ex := pg.sample_elevation(_dir(anchor_dir, east, north, phys_radius, gx + SLOPE_EPS, gz)) - pg.sample_elevation(_dir(anchor_dir, east, north, phys_radius, gx - SLOPE_EPS, gz))
	var ez := pg.sample_elevation(_dir(anchor_dir, east, north, phys_radius, gx, gz + SLOPE_EPS)) - pg.sample_elevation(_dir(anchor_dir, east, north, phys_radius, gx, gz - SLOPE_EPS))
	var dhx := ex * vertical_scale / (2.0 * SLOPE_EPS)
	var dhz := ez * vertical_scale / (2.0 * SLOPE_EPS)
	return sqrt(dhx * dhx + dhz * dhz)

# Choix arbre/rocher selon biome+pente+humidité (ou -1 = rien). Phase 20 couche A : les seuils de
# semis sont multipliés par PopulationTuning.vegetation_density(biome) (défaut 1.0 => phase 8 inchangée).
static func _pick_tree_rock(biome: int, slope: float, humidity: float, rng: RandomNumberGenerator, bank_mult: float = 1.0) -> int:
	var dens := PopulationTuning.vegetation_density(biome) * bank_mult   # phase 23 : × boost de berge
	# Phase 24 : les arbres sont des ESPÈCES L-system (SpeciesLibrary) choisies par biome/humidité ;
	# VegetationLibrary.tree_variant() tire une variante (mesh) au sein de l'espèce.
	match biome:
		PlanetGenerator.Biome.BEACH:
			if slope < TREE_MAX_SLOPE and rng.randf() < PopulationTuning.scaled_prob(0.10, dens):
				return VegetationLibrary.tree_variant(SpeciesLibrary.Species.PALM, rng)   # palmiers en bord de mer
			return _rock_variant(biome, rng) if rng.randf() < PopulationTuning.scaled_prob(0.05, dens) else -1
		PlanetGenerator.Biome.ROCK:
			if rng.randf() < PopulationTuning.scaled_prob(0.35, dens):
				return _rock_variant(biome, rng)
			if slope < TREE_MAX_SLOPE and rng.randf() < PopulationTuning.scaled_prob(0.05, dens):
				return VegetationLibrary.tree_variant(SpeciesLibrary.Species.TWISTED, rng)  # arbres noueux clairsemés
			return -1
		PlanetGenerator.Biome.PLAINS:
			if slope < TREE_MAX_SLOPE and rng.randf() < PopulationTuning.scaled_prob(0.10 + 0.18 * humidity, dens):
				var sp_plains := SpeciesLibrary.Species.PALM if humidity < 0.30 else SpeciesLibrary.Species.DECIDUOUS
				return VegetationLibrary.tree_variant(sp_plains, rng)   # plaine sèche -> palmier ; sinon feuillu
			if rng.randf() < PopulationTuning.scaled_prob(0.06, dens):
				return _rock_variant(biome, rng)
			return -1
		PlanetGenerator.Biome.FOREST:
			if slope < TREE_MAX_SLOPE and rng.randf() < PopulationTuning.scaled_prob(0.45, dens):
				var sp_forest := SpeciesLibrary.Species.CONIFER if humidity > 0.6 else SpeciesLibrary.Species.DECIDUOUS
				return VegetationLibrary.tree_variant(sp_forest, rng)   # forêt humide -> conifères ; sinon feuillus
			if rng.randf() < PopulationTuning.scaled_prob(0.05, dens):
				return _rock_variant(biome, rng)
			return -1
	return -1

# Type de rocher : surtout commun (gros gris / petit sombre), RAREMENT précieux (cuivre/or/cristal).
# Les minerais/gemmes sont plus probables en biome ROCHE (montagnes). Déterministe (rng seedé du chunk).
static func _rock_variant(biome: int, rng: RandomNumberGenerator) -> int:
	var rocky := biome == PlanetGenerator.Biome.ROCK
	var p_crystal := 0.030 if rocky else 0.012   # gemmes : très rare
	var p_gold := 0.050 if rocky else 0.025      # or : rare
	var p_copper := 0.110 if rocky else 0.070    # cuivre : peu commun
	var r := rng.randf()
	if r < p_crystal:
		return VegetationLibrary.V_ROCK_CRYSTAL
	if r < p_crystal + p_gold:
		return VegetationLibrary.V_ROCK_GOLD
	if r < p_crystal + p_gold + p_copper:
		return VegetationLibrary.V_ROCK_COPPER
	return VegetationLibrary.V_ROCK_A if rng.randf() < 0.6 else VegetationLibrary.V_ROCK_B

# Choix herbe selon biome+humidité (ou -1 = rien). Phase 20 couche A : seuils × vegetation_density(biome).
static func _pick_grass(biome: int, humidity: float, rng: RandomNumberGenerator, bank_mult: float = 1.0) -> int:
	var dens := PopulationTuning.vegetation_density(biome) * bank_mult   # phase 23 : × boost de berge
	match biome:
		PlanetGenerator.Biome.BEACH:
			return VegetationLibrary.V_GRASS_DRY if rng.randf() < PopulationTuning.scaled_prob(0.20, dens) else -1
		PlanetGenerator.Biome.PLAINS:
			if rng.randf() < PopulationTuning.scaled_prob(0.55, dens):
				return VegetationLibrary.V_GRASS_GREEN if humidity > 0.4 else VegetationLibrary.V_GRASS_DRY
			return -1
		PlanetGenerator.Biome.FOREST:
			return VegetationLibrary.V_GRASS_GREEN if rng.randf() < PopulationTuning.scaled_prob(0.45, dens) else -1
		PlanetGenerator.Biome.ROCK:
			return VegetationLibrary.V_GRASS_DRY if rng.randf() < PopulationTuning.scaled_prob(0.08, dens) else -1
	return -1

# Transform d'instance : lacet aléatoire + échelle ; rochers = rotation/échelle libres.
static func _instance_transform(variant: int, local: Vector3, rng: RandomNumberGenerator) -> Transform3D:
	var yaw := rng.randf() * TAU
	if variant in VegetationLibrary.ROCK_VARIANTS:
		# Tailles PAR TYPE : communs = gros blocs ; précieux = nodules/filons plus petits (même nb de tirages RNG).
		var lo := 1.0
		var hi := 3.4
		match variant:
			VegetationLibrary.V_ROCK_CRYSTAL:
				lo = 0.7
				hi = 1.5
			VegetationLibrary.V_ROCK_GOLD:
				lo = 0.9
				hi = 1.9
			VegetationLibrary.V_ROCK_COPPER:
				lo = 1.0
				hi = 2.3
		var s := rng.randf_range(lo, hi)
		var b := Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), yaw, rng.randf_range(-0.3, 0.3)))
		b = b.scaled(Vector3(s, s * rng.randf_range(0.7, 1.1), s))
		return Transform3D(b, local)
	# Arbres L-system : déjà à taille « réaliste » (3-8 m) => échelle modérée + INCLINAISON légère
	# (vent dominant) ; la base reste plantée au sol (rotation autour de l'origine = pied).
	if VegetationLibrary.is_tree_variant(variant):
		var sc := rng.randf_range(0.9, 1.6) * TREE_SIZE_MULT   # +40% (le tirage RNG est inchangé => déterminisme préservé)
		var lean_az := WIND_LEAN_AZIMUTH + rng.randf_range(-1.1, 1.1)   # autour du vent dominant
		var lean := rng.randf_range(0.0, 0.13)                          # ~0..7.5° d'inclinaison
		var axis := Vector3(cos(lean_az), 0.0, sin(lean_az))
		var b := Basis(axis, lean) * Basis(Vector3.UP, yaw)
		return Transform3D(b.scaled(Vector3(sc, sc, sc)), local)
	var gsc := rng.randf_range(1.5, 2.7)   # herbe : ×2 (inchangé)
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(gsc, gsc, gsc)), local)

static func _append(out: Dictionary, variant: int, t: Transform3D) -> void:
	if not out.has(variant):
		out[variant] = []
	out[variant].append(t)

# Seed de chunk stable à partir de (seed planète + coord espace-planète). Invariant au rebase.
static func _chunk_seed(seed_local: int, cx: int, cz: int) -> int:
	var h := seed_local * 73856093
	h ^= cx * 19349663
	h ^= cz * 83492791
	return h
