class_name PlanetGenerator
extends RefCounted
## Génère la surface d'une planète, 100% déterministe à partir d'un seed_local.
## Icosphère subdivisée + élévation par bruit Perlin 3D échantillonné selon la
## DIRECTION du vertex (bruit 3D => pas de couture UV), déplacement radial,
## couleurs de biomes bakées et normales recalculées.
##
## Phase 6 : le sampling est désormais exposé via des fonctions PURES
## (sample_elevation / sample_biome_color) sur une instance configurée par seed.
## La sphère orbitale (generate, statique) ET le patch de surface (SurfaceGenerator)
## partagent ces fonctions => le sol au sien est cohérent avec la vue d'en haut.

const DEFAULT_SUBDIVISIONS := 5      # 5 => ~10k vertices / ~20k tris (sûr casque autonome)
const DEFAULT_RADIUS := 30.0         # même ordre de grandeur que galaxie/système (cadrage commun)
const DEFAULT_AMPLITUDE := 0.13      # relief orbital en fraction du rayon (budget sous les nuages)
const DEFAULT_SEA_LEVEL := 0.0       # seuil d'élévation de l'océan
const DEFAULT_NOISE_FREQ := 1.6
const NOISE_OCTAVES := 4   # continents un peu plus lisses (moins de fines rides = moins de pentes locales)

# Palette de biomes (bakée en couleurs de vertices).
const OCEAN_DEEP := Color(0.02, 0.08, 0.26)
const OCEAN_SHALLOW := Color(0.10, 0.42, 0.60)
const BEACH := Color(0.85, 0.78, 0.50)
const PLAINS := Color(0.35, 0.57, 0.21)
const FOREST := Color(0.09, 0.29, 0.12)
const ROCK := Color(0.40, 0.35, 0.31)
const SNOW := Color(0.95, 0.96, 0.99)
# Biomes climatiques (température latitude+altitude × humidité) — palette CONTRASTÉE, bien distincte.
const DESERT := Color(0.86, 0.71, 0.36)    # chaud très sec (sable doré)
const SAVANNA := Color(0.64, 0.58, 0.25)   # chaud semi-sec (herbe rase dorée)
const JUNGLE := Color(0.05, 0.40, 0.09)    # chaud humide (forêt tropicale vive)
const STEPPE := Color(0.58, 0.53, 0.32)    # tempéré sec (steppe/garrigue olive)
const TUNDRA := Color(0.49, 0.53, 0.47)    # froid sec (toundra gris-vert)
const TAIGA := Color(0.14, 0.31, 0.25)     # froid humide (conifères sombres)
const BADLANDS := Color(0.56, 0.29, 0.18)  # aride + relief => roche rougeâtre (variété)
const LAND_SPAN := 0.5   # amplitude approx. d'élévation au-dessus du niveau de mer

# Façonnage du relief (amélioration "continents & montagnes") — borné pour rester déterministe et
# SOUS la couche de nuages (cf. PlanetAtmosphere.CLOUD_SCALE=1.12 ; 1 + ELEV_MAX*AMPLITUDE < 1.12).
const CONTINENT_CONTRAST := 1.35   # > 1 : côtes plus nettes, océans plus profonds (continents francs)
const HIGHLAND_AMP := 0.20         # hautes terres : surélève les régions continentales hautes (plateaux/massifs LARGES & doux)
const MOUNTAIN_AMP := 0.10         # hauteur des crêtes (ridged) — montagnes basses, arrondies, flancs très doux
const DETAIL_AMP := 0.007          # rugosité haute fréquence du sol (réduite : marche très douce, peu de bosses)
const ELEV_MAX := 0.85             # plafond d'élévation (1 + ELEV_MAX*AMPLITUDE < CLOUD_SCALE 1.12)

# --- Cratères d'impact + volcans (procéduraux, déterministes ; visibles orbite + sol) ---
const CRATER_REGION_FREQ := 1.2    # taille des RÉGIONS cratérisées (zones criblées vs lisses)
const CRATER_REGION_THR := 0.10    # seuil de région : au-dessus => cratères présents
const CRATER_FREQ := 8.0           # densité des cratères (cellulaire ; + grand = + petits & nombreux)
const CRATER_DEPTH := 0.085        # profondeur du bol (pleinement réalisée depuis le recalage _cell01)
const CRATER_RIM := 0.040          # hauteur du bourrelet
const CRATER_RADIUS := 0.60        # rayon du cratère (en valeur cellulaire normalisée 0..1)
const CRATER2_FREQ := 20.0         # petits cratères superposés (variété de tailles, même région)
const CRATER2_DEPTH := 0.035       # moins profonds que les gros
const CRATER2_RIM := 0.015
const CRATER2_RADIUS := 0.55
const VOLCANO_FREQ := 6.0          # taille/espacement des cônes (BASSE => gros & espacés)
const VOLCANO_SELECT := 0.74       # seuil sur la VALEUR de cellule : seules les rares cellules => volcan
const VOLCANO_HEIGHT := 0.34       # hauteur du cône (point haut le plus marquant du relief)
const VOLCANO_CALDERA := 0.10      # profondeur du cratère sommital
const VOLCANO_CONE_R := 0.80       # rayon du cône (en valeur cellulaire normalisée 0..1)
const VOLCANO_CALDERA_R := 0.20    # rayon de la caldeira (assez large pour apparaître au sommet, cf. sonde)

# Types de biome discrets (mêmes seuils que _biome_color) — pilotent le semis de
# végétation en phase 8 (type + densité).
enum Biome { OCEAN, BEACH, PLAINS, FOREST, ROCK, SNOW }

# --- État d'instance (bruits configurés à partir du seed) ---
var _elev: FastNoiseLite
var _humid: FastNoiseLite
var _ridge: FastNoiseLite   # bruit des crêtes de montagnes (relief sur la terre)
var _detail: FastNoiseLite  # rugosité fine du sol (relief de marche, haute fréquence)
var _crater: FastNoiseLite          # cellulaire : cratères d'impact (distance au point le plus proche)
var _crater2: FastNoiseLite         # cellulaire : petits cratères superposés (variété de tailles)
var _crater_region: FastNoiseLite   # masque : régions cratérisées
var _volcano: FastNoiseLite         # cellulaire (distance) : forme du cône volcanique
var _volcano_cell: FastNoiseLite    # cellulaire (valeur) : sélecteur — rares cellules => volcan
var _sea_level: float = DEFAULT_SEA_LEVEL
var _flow_map: PlanetFlowMap = null   # phase 23 : carte hydrologique (érosion + rivières) ou null
var _seed_local := 0
# Archétype de monde (par seed) : biaise le climat + teinte la palette => planètes TRÈS différentes.
var _temp_bias := 0.0      # décale la température partout (+ chaud / - froid)
var _humid_bias := 0.0     # décale l'humidité (+ humide / - sec)
var _accent := Color.WHITE # teinte multiplicative de la palette TERRESTRE (océans/eau intacts)
var _accent_amt := 0.0     # force de la teinte (0 = neutre)
var _water_color := Color(0.0, 0.0, 0.0, 1.0)   # phase 23 : teinte d'eau CACHÉE (évite une alloc RNG/vertex)

# Configure les bruits déterministes pour ce seed. À appeler avant les sample_*.
func configure(seed_local: int, sea_level: float = DEFAULT_SEA_LEVEL, noise_frequency: float = DEFAULT_NOISE_FREQ) -> void:
	_sea_level = sea_level
	_seed_local = seed_local
	_init_world_archetype(seed_local)
	_elev = FastNoiseLite.new()
	_elev.noise_type = FastNoiseLite.TYPE_PERLIN
	_elev.seed = seed_local
	_elev.frequency = noise_frequency
	_elev.fractal_type = FastNoiseLite.FRACTAL_FBM
	_elev.fractal_octaves = NOISE_OCTAVES
	# Domain warp : déforme l'échantillonnage => continents/chaînes organiques (moins « patatoïdes »).
	_elev.domain_warp_enabled = true
	_elev.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	_elev.domain_warp_amplitude = 0.45
	_elev.domain_warp_frequency = noise_frequency * 0.5
	_elev.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_PROGRESSIVE
	_elev.domain_warp_fractal_octaves = 3

	_humid = FastNoiseLite.new()
	_humid.noise_type = FastNoiseLite.TYPE_PERLIN
	_humid.seed = seed_local + 1337
	_humid.frequency = noise_frequency * 0.6
	_humid.fractal_type = FastNoiseLite.FRACTAL_FBM
	_humid.fractal_octaves = 3

	# Crêtes de montagnes : bruit plus fin, ajouté SUR la terre (cf. sample_elevation).
	_ridge = FastNoiseLite.new()
	_ridge.noise_type = FastNoiseLite.TYPE_PERLIN
	_ridge.seed = seed_local + 7777
	_ridge.frequency = noise_frequency * 1.0   # crêtes PLUS LARGES => flancs de montagne très doux
	_ridge.fractal_type = FastNoiseLite.FRACTAL_FBM
	_ridge.fractal_octaves = 3                  # moins d'octaves fines => moins de creux/crêtes raides
	_ridge.fractal_gain = 0.42                  # octaves hautes atténuées => relief lissé
	_ridge.domain_warp_enabled = true
	_ridge.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	_ridge.domain_warp_amplitude = 0.30
	_ridge.domain_warp_frequency = noise_frequency

	# Détail fin du sol (rugosité, relief de marche) — haute fréquence, faible amplitude.
	_detail = FastNoiseLite.new()
	_detail.noise_type = FastNoiseLite.TYPE_PERLIN
	_detail.seed = seed_local + 9001
	_detail.frequency = noise_frequency * 1.6   # bosses plus larges (moins de micro-pentes sous les pas)
	_detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	_detail.fractal_octaves = 2

	# Cratères : champ cellulaire (distance au point d'impact le plus proche) + masque de régions.
	_crater = FastNoiseLite.new()
	_crater.noise_type = FastNoiseLite.TYPE_CELLULAR
	_crater.seed = seed_local + 4040
	_crater.frequency = CRATER_FREQ
	_crater.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	_crater.cellular_jitter = 1.0
	_crater2 = FastNoiseLite.new()
	_crater2.noise_type = FastNoiseLite.TYPE_CELLULAR
	_crater2.seed = seed_local + 4042
	_crater2.frequency = CRATER2_FREQ
	_crater2.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	_crater2.cellular_jitter = 1.0
	_crater_region = FastNoiseLite.new()
	_crater_region.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_crater_region.seed = seed_local + 4041
	_crater_region.frequency = CRATER_REGION_FREQ
	# Volcans : cône = distance cellulaire (BASSE fréquence => gros & espacés) ; rareté = valeur de
	# cellule (mêmes seed/fréquence/jitter => MÊME partition : seules de rares cellules deviennent volcan).
	_volcano = FastNoiseLite.new()
	_volcano.noise_type = FastNoiseLite.TYPE_CELLULAR
	_volcano.seed = seed_local + 5050
	_volcano.frequency = VOLCANO_FREQ
	_volcano.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	_volcano.cellular_jitter = 1.0
	_volcano_cell = FastNoiseLite.new()
	_volcano_cell.noise_type = FastNoiseLite.TYPE_CELLULAR
	_volcano_cell.seed = seed_local + 5050
	_volcano_cell.frequency = VOLCANO_FREQ
	_volcano_cell.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	_volcano_cell.cellular_jitter = 1.0

# Phase 23 : attache la carte hydrologique pour le RENDU (orbite/surface). Non utilisée pendant la
# génération de la FlowMap elle-même (le PlanetGenerator de PlanetFlowMap n'en a pas => pas de circularité).
func set_flow_map(fm: PlanetFlowMap) -> void:
	_flow_map = fm
	if fm != null:
		_water_color = water_color(_seed_local)   # cachée UNE fois (au lieu d'une alloc RNG par vertex)

# --- Fonctions PURES de sampling (partagées sphère + patch) ---

# Élévation (~[-1, ELEV_MAX]) selon la direction unitaire. Continents francs (contraste) +
# montagnes (crêtes ridged) sur la terre, fondues près de la côte. Plafonnée sous les nuages.
## Phase 24 (eau) : force de fonte du relief fin vers le niveau hydrologique LISSÉ près de l'eau
## (l'eau tombe dans un vrai creux du terrain au lieu de traverser les crêtes tourmentées).
const WATER_CONFORM := 1.3

# Champ cratères + volcans (ajout d'altitude, MÊMES unités que sample_elevation). Cellulaire = distance
# au point le plus proche => bol + bourrelet (cratère) / cône + caldeira (volcan). Cratères gatés par un
# masque de régions (épars) ; volcans gatés par la VALEUR de cellule (rares) ET la TERRE seule.
func _crater_field(unit_dir: Vector3, base: float) -> float:
	var m := 0.0
	var creg := _crater_region.get_noise_3dv(unit_dir)
	if creg > CRATER_REGION_THR:
		var dens := smoothstep(CRATER_REGION_THR, CRATER_REGION_THR + 0.20, creg)
		var d := _cell01(_crater.get_noise_3dv(unit_dir))
		var bowl := smoothstep(CRATER_RADIUS, 0.0, d)   # 1 au centre -> 0 au rayon
		var rim := smoothstep(CRATER_RADIUS * 0.6, CRATER_RADIUS, d) * (1.0 - smoothstep(CRATER_RADIUS, CRATER_RADIUS * 1.5, d))
		m += (rim * CRATER_RIM - bowl * CRATER_DEPTH) * dens
		# Petits cratères superposés (variété de tailles) — même région cratérisée, plus fins.
		var d2 := _cell01(_crater2.get_noise_3dv(unit_dir))
		var bowl2 := smoothstep(CRATER2_RADIUS, 0.0, d2)
		var rim2 := smoothstep(CRATER2_RADIUS * 0.6, CRATER2_RADIUS, d2) * (1.0 - smoothstep(CRATER2_RADIUS, CRATER2_RADIUS * 1.5, d2))
		m += (rim2 * CRATER2_RIM - bowl2 * CRATER2_DEPTH) * dens
	# Volcan : TERRE seulement (pas de cône en mer/côte => évite l'éval cellulaire sur les marges, perf) et
	# cellule rare (valeur > seuil). Hauteur fondue sur les hautes terres pour garder l'apex sous ELEV_MAX.
	if base > 0.0:
		var vcell := _volcano_cell.get_noise_3dv(unit_dir)
		if vcell > VOLCANO_SELECT:
			var vsel := smoothstep(VOLCANO_SELECT, VOLCANO_SELECT + 0.06, vcell)  # apparition douce par cellule
			var head := 1.0 - smoothstep(0.32, 0.62, base)  # plein relief sur terres basses, éteint sur hautes terres
			var dv := _cell01(_volcano.get_noise_3dv(unit_dir))
			var cone := smoothstep(VOLCANO_CONE_R, 0.0, dv)        # 1 au sommet -> 0 au pied
			var caldera := smoothstep(VOLCANO_CALDERA_R, 0.0, dv)  # creux sommital (caldeira)
			m += (cone * VOLCANO_HEIGHT - caldera * VOLCANO_CALDERA) * vsel * head
	return m

# Mappe la sortie cellulaire FastNoiseLite (RETURN_DISTANCE) en 0..1 : 0 au point le plus proche
# (centre cratère / sommet volcan, apex pleinement réalisé), 1 au bord de cellule. La plage ~[-0.80, -0.15]
# est une PROPRIÉTÉ de FastNoiseLite (Euclidien, jitter=1) — indépendante du seed, valable pour toute planète.
func _cell01(v: float) -> float:
	return clampf((v + 0.80) / 0.65, 0.0, 1.0)

func sample_elevation(unit_dir: Vector3) -> float:
	var base := _elev.get_noise_3dv(unit_dir)              # [-1,1] FBM continental (domain-warped)
	base = clampf(base * CONTINENT_CONTRAST, -1.0, 1.0)    # côtes nettes, océans profonds
	var e := base
	if base > 0.0:                                        # terre
		# Hautes terres : surélèvement TARDIF (large bande de plaines basses & plates avant que ça monte)
		# => beaucoup de zones planes, vistas douces, marche facile.
		e += smoothstep(0.28, 0.82, base) * HIGHLAND_AMP
		# Montagnes ridged ARRONDIES (mélange plus linéaire = crêtes moins pointues), confinées aux
		# HAUTES terres (smoothstep tardif) => côtes & plaines restent PLATES, montagnes douces au loin.
		var ridge := 1.0 - absf(_ridge.get_noise_3dv(unit_dir))
		var mtn := (ridge * ridge * 0.45 + ridge * 0.55) * MOUNTAIN_AMP
		e += mtn * smoothstep(0.20, 0.45, base)
		e += _detail.get_noise_3dv(unit_dir) * DETAIL_AMP * smoothstep(0.0, 0.06, base)
	# Cratères d'impact + volcans (procéduraux) : ajoutés au relief sur terre & côtes (océan profond exclu, perf).
	if base > -0.25:
		e += _crater_field(unit_dir, base)
	if _flow_map != null:
		if e < _flow_map.sea_level:   # phase 24 (perf) : océan = érosion nulle + pas de vallée => early-out gratuit
			return clampf(e, -1.0, ELEV_MAX)
		# Phase 24 (perf) : UNE seule passe de warp partagée par tous les échantillonnages (chemin TRÈS chaud).
		var wdir := _flow_map.warp(unit_dir)
		e += _flow_map.erosion_raw(wdir)   # phase 23 : creusement des vallées (≤ 0)
		# Phase 24 (eau) : CREUSE une vraie vallée/bassin près de l'eau (proximité PRÉ-CALCULÉE, plus de scan).
		var prox := _flow_map.water_prox_raw(wdir)
		var lake := _flow_map.is_lake_raw(wdir)
		if lake:
			prox = 1.0
		if prox > 0.001:
			var wl: float = _flow_map.lake_level_raw(wdir) if lake else _flow_map.filled_raw(wdir)
			var floor_t := minf(e, wl - PlanetFlowMap.VALLEY_DEPTH)   # fond de vallée (ne surélève jamais le sol)
			e = lerpf(e, floor_t, clampf(prox * WATER_CONFORM, 0.0, 0.95))
	return clampf(e, -1.0, ELEV_MAX)

# Tire un archétype de monde DÉTERMINISTE par seed (tempéré / aride / luxuriant / gelé / volcanique /
# alien) qui biaise le climat (température + humidité) ET teinte la palette terrestre. Tempéré le plus
# fréquent, alien rare. Cohérent orbite ↔ sol (la MÊME instance configurée sert partout).
func _init_world_archetype(seed_local: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_local + 4242
	var r := rng.randi() % 100
	if r < 34:        # TEMPÉRÉ (terrien) — défaut, le plus courant
		_temp_bias = 0.0; _humid_bias = 0.0; _accent = Color.WHITE; _accent_amt = 0.0
	elif r < 50:      # ARIDE (désertique)
		_temp_bias = 0.06; _humid_bias = -0.32; _accent = Color(1.10, 0.99, 0.80); _accent_amt = 0.14
	elif r < 66:      # LUXURIANT (jungle)
		_temp_bias = 0.10; _humid_bias = 0.28; _accent = Color(0.82, 1.10, 0.80); _accent_amt = 0.13
	elif r < 80:      # GELÉ (glaciaire)
		_temp_bias = -0.30; _humid_bias = -0.05; _accent = Color(0.86, 0.96, 1.16); _accent_amt = 0.14
	elif r < 92:      # VOLCANIQUE (cendres/roche rouge)
		_temp_bias = 0.12; _humid_bias = -0.20; _accent = Color(1.22, 0.82, 0.66); _accent_amt = 0.20
	else:             # ALIEN (otherworldly) — rare
		_temp_bias = rng.randf_range(-0.18, 0.18)
		_humid_bias = rng.randf_range(-0.18, 0.18)
		_accent = Color.from_hsv(rng.randf(), 0.62, 1.10)
		_accent_amt = 0.34

# Couleur de biome pour une direction + son élévation (océan/plage/plaines/forêts/roche/neige).
func sample_biome_color(unit_dir: Vector3, elevation: float) -> Color:
	var lat := absf(unit_dir.y)                       # latitude normalisée (0 équateur -> 1 pôle)
	var h := clampf(_humid.get_noise_3dv(unit_dir) * 0.5 + 0.5 + _humid_bias, 0.0, 1.0)  # humidité + biais archétype
	var col := _biome_color(elevation, _sea_level, lat, h, _temp_bias)
	# Archétype : teinte la TERRE (les océans/rivières gardent leur couleur d'eau).
	if _accent_amt > 0.0 and elevation > _sea_level:
		col = col.lerp(col * _accent, _accent_amt)
	# Phase 23 : teinte d'eau sur rivières/lacs (terre seulement), cohérente orbite ↔ sol (même seed).
	if _flow_map != null and elevation > _sea_level:
		if _flow_map.is_lake_at(unit_dir):
			col = _water_color
		else:
			var rs := _flow_map.river_tint_at(unit_dir)
			if rs > 0.0:
				col = col.lerp(_water_color, clampf(0.35 + rs * 0.6, 0.0, 0.9))
	return col

# Humidité [0, 1] à une direction (même bruit que la coloration des biomes). PUR.
func sample_humidity(unit_dir: Vector3) -> float:
	return _humid.get_noise_3dv(unit_dir) * 0.5 + 0.5

# Type de biome discret (pour le SEMIS de végétation, phase 8). Suit la MÊME logique de climat
# (température latitude+altitude) que _biome_color, mappée sur l'enum à 6 types : forêt = arbres
# (zones humides : jungle/forêt/taïga), plaine = herbe (zones sèches : désert/plaine/toundra).
# PUR + thread-safe (instance configurée).
func sample_biome(unit_dir: Vector3, elevation: float) -> int:
	return sample_biome_h(unit_dir, elevation, sample_humidity(unit_dir))

# Variante CHEMIN CHAUD : humidité PRÉ-CALCULÉE passée (évite un 2e get_noise par candidat de semis).
func sample_biome_h(unit_dir: Vector3, elevation: float, humidity: float) -> int:
	if elevation < _sea_level:
		return Biome.OCEAN
	var alt := clampf((elevation - _sea_level) / LAND_SPAN, 0.0, 1.0)
	if alt < 0.05:
		return Biome.BEACH
	var lat := absf(unit_dir.y)
	var temp := clampf(1.0 - lat * 1.15 - alt * 0.5 + _temp_bias, 0.0, 1.0)   # + biais archétype (cohérent couleur)
	if temp < 0.18:
		return Biome.SNOW                 # grand froid (pôles / sommets)
	if alt > 0.55:
		return Biome.ROCK                 # haute altitude
	return Biome.FOREST if clampf(humidity + _humid_bias, 0.0, 1.0) > 0.5 else Biome.PLAINS

# Génère l'ArrayMesh de la sphère orbitale (inchangé visuellement : réutilise les
# fonctions de sampling ci-dessus). Paramètres : subdivision, amplitude, niveau de
# mer, échelle de bruit, rayon.
static func generate(seed_local: int, subdivisions: int = DEFAULT_SUBDIVISIONS, amplitude: float = DEFAULT_AMPLITUDE, sea_level: float = DEFAULT_SEA_LEVEL, noise_frequency: float = DEFAULT_NOISE_FREQ, radius: float = DEFAULT_RADIUS, flow_map: PlanetFlowMap = null) -> ArrayMesh:
	var pg := PlanetGenerator.new()
	pg.configure(seed_local, sea_level, noise_frequency)
	pg.set_flow_map(flow_map)   # phase 23 : érosion + rivières si fournie (null = aspect d'origine)

	var ico := _build_icosphere(subdivisions)
	var dirs: PackedVector3Array = ico.verts
	var indices: PackedInt32Array = ico.indices

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in dirs.size():
		var dir := dirs[i]
		var e := pg.sample_elevation(dir)
		var land_e: float = maxf(e, sea_level)  # océan plat sous le niveau de mer
		st.set_color(pg.sample_biome_color(dir, e))
		st.add_vertex(dir * (radius * (1.0 + land_e * amplitude)))
	for idx in indices:
		st.add_index(idx)
	st.generate_normals()   # normales lissées après déplacement
	return st.commit()

# --- Océans (phase 11) : niveau de mer + teinte d'eau PARTAGÉS orbite ↔ surface ---

# Rayon (espace LOCAL de la planète) au niveau de mer. L'océan orbital est une sphère à
# ce rayon ; la surface utilise le MÊME niveau de mer (DEFAULT_SEA_LEVEL) pour son plan.
static func sea_level_radius(_seed_local: int) -> float:
	return DEFAULT_RADIUS * (1.0 + DEFAULT_SEA_LEVEL * DEFAULT_AMPLITUDE)

# Hauteur Y (mètres) du niveau de mer à la surface, pour une échelle verticale donnée.
static func sea_level_height(vertical_scale: float) -> float:
	return DEFAULT_SEA_LEVEL * vertical_scale

# Couleur de l'eau, DÉTERMINISTE par seed et cohérente avec l'atmosphère du seed (même
# graine/teinte HSV que PlanetAtmosphere.atmosphere_color_for), mêlée à un bleu-vert d'océan.
static func water_color(seed_local: int) -> Color:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_local + 9001                                   # même graine que l'atmosphère
	var atmo := Color.from_hsv(rng.randf(), rng.randf_range(0.40, 0.70), 1.0)
	var base := Color(0.05, 0.28, 0.45)                            # eau profonde bleu-vert
	return base.lerp(atmo, 0.35)

# Couleur de biome : océan (profondeur), plage, plaines/forêts (humidité), roche,
# neige (latitude + altitude).
static func _biome_color(e: float, sea_level: float, lat: float, humidity: float, temp_bias: float = 0.0) -> Color:
	if e < sea_level:
		var depth := clampf((sea_level - e) / LAND_SPAN, 0.0, 1.0)
		return OCEAN_SHALLOW.lerp(OCEAN_DEEP, depth)
	var alt := clampf((e - sea_level) / LAND_SPAN, 0.0, 1.0)
	if alt < 0.05:
		return BEACH
	# Température : chaude à l'équateur (lat 0), froide aux pôles (lat 1) et en altitude. + biais archétype.
	var temp := clampf(1.0 - lat * 1.15 - alt * 0.5 + temp_bias, 0.0, 1.0)
	# Matrice climat (chaud->froid × sec->humide) => biomes DISTINCTS, transitions plus franches.
	var lowland: Color
	if temp > 0.72:                          # TROPICAL chaud : désert -> savane -> jungle
		if humidity < 0.30:
			lowland = DESERT
		elif humidity < 0.58:
			lowland = DESERT.lerp(SAVANNA, smoothstep(0.30, 0.58, humidity))
		else:
			lowland = SAVANNA.lerp(JUNGLE, smoothstep(0.58, 0.84, humidity))
	elif temp > 0.46:                        # TEMPÉRÉ : steppe -> plaine -> forêt
		if humidity < 0.34:
			lowland = STEPPE
		elif humidity < 0.62:
			lowland = STEPPE.lerp(PLAINS, smoothstep(0.34, 0.62, humidity))
		else:
			lowland = PLAINS.lerp(FOREST, smoothstep(0.55, 0.86, humidity))
	else:                                    # FROID : toundra -> taïga (neige gérée plus bas)
		lowland = TUNDRA.lerp(TAIGA, smoothstep(0.30, 0.72, humidity))
	# Badlands : terres arides + reliefs moyens en climat chaud => roche rougeâtre (variété).
	if temp > 0.50 and humidity < 0.26 and alt > 0.30:
		lowland = lowland.lerp(BADLANDS, smoothstep(0.30, 0.62, alt))
	# Roche en altitude, puis neige par grand froid (pôles + sommets).
	var land := lowland.lerp(ROCK, smoothstep(0.50, 0.78, alt))
	var snow_amount := smoothstep(0.26, 0.10, temp)
	return land.lerp(SNOW, snow_amount)

# Construit une icosphère indexée (vertices unitaires partagés) par subdivision
# récursive d'un icosaèdre. Renvoie { verts: PackedVector3Array, indices: PackedInt32Array }.
static func _build_icosphere(subdivisions: int) -> Dictionary:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)
	]
	for i in verts.size():
		verts[i] = verts[i].normalized()

	var faces: Array = [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]
	]

	var midpoint_cache := {}
	for _s in subdivisions:
		var new_faces: Array = []
		for f in faces:
			var a: int = f[0]
			var b: int = f[1]
			var c: int = f[2]
			var ab := _midpoint(a, b, verts, midpoint_cache)
			var bc := _midpoint(b, c, verts, midpoint_cache)
			var ca := _midpoint(c, a, verts, midpoint_cache)
			new_faces.append([a, ab, ca])
			new_faces.append([b, bc, ab])
			new_faces.append([c, ca, bc])
			new_faces.append([ab, bc, ca])
		faces = new_faces

	var out_verts := PackedVector3Array()
	out_verts.resize(verts.size())
	for i in verts.size():
		out_verts[i] = verts[i]
	var out_indices := PackedInt32Array()
	for f in faces:
		out_indices.append(f[0])
		out_indices.append(f[1])
		out_indices.append(f[2])
	return {"verts": out_verts, "indices": out_indices}

# Renvoie l'index du milieu (normalisé) de l'arête (a, b), en le mutualisant via cache.
static func _midpoint(a: int, b: int, verts: Array, cache: Dictionary) -> int:
	var key := mini(a, b) * 100000000 + maxi(a, b)
	if cache.has(key):
		return cache[key]
	var m: Vector3 = ((verts[a] + verts[b]) * 0.5).normalized()
	verts.append(m)
	var idx := verts.size() - 1
	cache[key] = idx
	return idx
