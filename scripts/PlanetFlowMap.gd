class_name PlanetFlowMap
extends RefCounted
## Phase 23 — carte hydrologique basse résolution d'une planète, DÉTERMINISTE par seed_local.
## Grille équirectangulaire (lon × lat). Générée UNE fois (off-thread en prod, cf. checkpoint 2),
## cachée dans la planète courante, échantillonnée par les chunks (lit/eaux) ET la sphère orbitale
## (altitude érodée). Libérée au changement de système.
##
## Champs par cellule (idx = row*w + col) :
##  - elev_base       : altitude brute (sample_elevation), unités ~[-1, 0.85]
##  - filled          : altitude « remplie » (>= elev_base ; niveau de lac aux dépressions)
##  - flow_acc        : drainage accumulé (cellules amont pondérées par l'aire)
##  - flow_dir        : index 0..7 du voisin AVAL (255 = aucun / océan)
##  - erosion_mod     : modificateur d'altitude (<= 0 : creusement des vallées) — MÊMES unités que sample_elevation
##  - river_strength  : 0..1 (0 = pas de rivière), proxy de largeur
##  - is_lake         : 1 si lac
##  - lake_level      : altitude de surface du lac (si is_lake)

const DEFAULT_W := 512   # longitude
const DEFAULT_H := 256   # latitude
const WATER_THRESHOLD := 0.05   # phase 23 : force de rivière mini = « il y a de l'eau ici » (seuil PARTAGÉ)
const VALLEY_DEPTH := 0.14      # phase 24 : profondeur de la VALLÉE/bassin creusé sous le niveau hydrologique (≈23 m)
const RIVER_DEPTH := 0.012      # phase 24 : profondeur d'eau d'une rivière au fond de sa vallée (≈2 m)
const WARP_AMP := 0.035         # phase 23 : domain-warp de l'ÉCHANTILLONNAGE (rivières/vallées qui serpentent)
const WARP_FREQ := 7.0          # fréquence du warp (méandres naturels)

var w := DEFAULT_W
var h := DEFAULT_H
var seed_local := 0
var sea_level := 0.0
var max_flow := 1.0
var params := {}
var orbital_mesh: ArrayMesh = null   # phase 23 : mesh orbital érodé, baké dans le MÊME worker (anti-hitch)
var _warp_a: FastNoiseLite           # phase 23 : bruits de domain-warp de l'échantillonnage (méandres)
var _warp_b: FastNoiseLite

var elev_base := PackedFloat32Array()
var filled := PackedFloat32Array()
var flow_acc := PackedFloat32Array()
var flow_dir := PackedByteArray()
var erosion_mod := PackedFloat32Array()
var river_strength := PackedFloat32Array()
var is_lake := PackedByteArray()
var lake_level := PackedFloat32Array()
var water_prox := PackedFloat32Array()   # phase 24 (perf) : proximité d'eau DILATÉE 0..1 (pré-calculée) => carve de vallée SANS scan runtime

# Génère intégralement la carte pour un seed (SYNCHRONE ici ; appelée off-thread en prod).
func generate(p_seed: int, p_w: int = DEFAULT_W, p_h: int = DEFAULT_H, p_sea: float = 0.0, p_params: Dictionary = {}) -> void:
	seed_local = p_seed
	w = p_w
	h = p_h
	sea_level = p_sea
	params = p_params
	# Domain-warp de l'échantillonnage (déterministe par seed) : casse l'alignement D8 (lignes droites).
	_warp_a = FastNoiseLite.new()
	_warp_a.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_warp_a.seed = seed_local + 4451
	_warp_a.frequency = WARP_FREQ
	_warp_b = FastNoiseLite.new()
	_warp_b.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_warp_b.seed = seed_local + 8821
	_warp_b.frequency = WARP_FREQ
	var n := w * h
	elev_base.resize(n)
	var pg := PlanetGenerator.new()
	pg.configure(seed_local, sea_level)
	for row in h:
		var base_i := row * w
		for col in w:
			elev_base[base_i + col] = pg.sample_elevation(_cell_dir(row, col))
	var r := HydraulicErosion.compute(elev_base, w, h, sea_level, params)
	filled = r["filled"]
	flow_acc = r["flow"]
	flow_dir = r["dir8"]
	erosion_mod = r["erosion"]
	river_strength = r["river"]
	is_lake = r["is_lake"]
	lake_level = r["lake_level"]
	max_flow = r["max_flow"]
	_build_water_prox()   # phase 24 (perf) : champ de proximité pré-calculé (allège sample_elevation)

# Direction unitaire (monde-planète) du CENTRE de la cellule (row, col).
# y = axe latitude (cohérent avec PlanetGenerator qui lit unit_dir.y comme latitude).
func _cell_dir(row: int, col: int) -> Vector3:
	var lon: float = (float(col) + 0.5) / float(w) * TAU
	var lat: float = PI * 0.5 - (float(row) + 0.5) / float(h) * PI
	var cl := cos(lat)
	return Vector3(cl * cos(lon), sin(lat), cl * sin(lon))

# Direction unitaire du centre de la cellule d'index i (échantillonnage inverse / debug).
func dir_of(i: int) -> Vector3:
	return _cell_dir(i / w, i % w)

# --- Échantillonnage continu (bilinéaire) pour le terrain (évite les marches d'escalier) ---

func _wrapc(c: int) -> int:
	return ((c % w) + w) % w

# Interpolation bilinéaire d'un champ float à une direction unitaire.
func _bilerp(field: PackedFloat32Array, unit_dir: Vector3) -> float:
	if field.is_empty():
		return 0.0
	var lat := asin(clampf(unit_dir.y, -1.0, 1.0))
	var lon := atan2(unit_dir.z, unit_dir.x)
	if lon < 0.0:
		lon += TAU
	var cf := lon / TAU * float(w) - 0.5
	var rf := (PI * 0.5 - lat) / PI * float(h) - 0.5
	var c0 := floori(cf)
	var r0 := floori(rf)
	var fc := cf - float(c0)
	var fr := rf - float(r0)
	var c0w := _wrapc(c0)
	var c1w := _wrapc(c0 + 1)
	var r0c := clampi(r0, 0, h - 1)
	var r1c := clampi(r0 + 1, 0, h - 1)
	var v00 := field[r0c * w + c0w]
	var v10 := field[r0c * w + c1w]
	var v01 := field[r1c * w + c0w]
	var v11 := field[r1c * w + c1w]
	return lerpf(lerpf(v00, v10, fc), lerpf(v01, v11, fc), fr)

# Cellule la plus proche (pour les masques booléens).
func _nearest_idx(unit_dir: Vector3) -> int:
	var lat := asin(clampf(unit_dir.y, -1.0, 1.0))
	var lon := atan2(unit_dir.z, unit_dir.x)
	if lon < 0.0:
		lon += TAU
	var col := _wrapc(int(round(lon / TAU * float(w) - 0.5)))
	var row := clampi(int(round((PI * 0.5 - lat) / PI * float(h) - 0.5)), 0, h - 1)
	return row * w + col

# Décale la direction d'échantillonnage par un bruit tangentiel => les tracés rectilignes du routage
# D8 (rivières/vallées droites alignées sur la grille) deviennent des méandres. DÉTERMINISTE et appliqué
# à TOUS les samplers ci-dessous => terrain/eau/végétation restent parfaitement cohérents.
func _warped(unit_dir: Vector3) -> Vector3:
	if _warp_a == null:
		return unit_dir
	var b := FloatingOrigin.tangent_basis(unit_dir)   # colonnes east, up, north
	var ox := _warp_a.get_noise_3dv(unit_dir)
	var oz := _warp_b.get_noise_3dv(unit_dir)
	return (unit_dir + (b.x * ox + b.z * oz) * WARP_AMP).normalized()

# Modificateur d'érosion à ajouter à l'altitude de base (<= 0). MÊMES unités que sample_elevation.
func erosion_at(unit_dir: Vector3) -> float:
	return _bilerp(erosion_mod, _warped(unit_dir))

# Force de rivière 0..1 (0 = pas de rivière) — interpolée pour des berges douces.
func river_at(unit_dir: Vector3) -> float:
	return _bilerp(river_strength, _warped(unit_dir))

# Force de rivière DILATÉE (max sur un voisinage de cellules) : rend les rivières fines VISIBLES sur
# la sphère orbitale grossière (espacement entre vertices > largeur d'une rivière d'1 cellule).
func river_tint_at(unit_dir: Vector3, cell_radius: int = 2) -> float:
	if river_strength.is_empty():
		return 0.0
	unit_dir = _warped(unit_dir)
	var lat := asin(clampf(unit_dir.y, -1.0, 1.0))
	var lon := atan2(unit_dir.z, unit_dir.x)
	if lon < 0.0:
		lon += TAU
	var col := int(round(lon / TAU * float(w) - 0.5))
	var row := int(round((PI * 0.5 - lat) / PI * float(h) - 0.5))
	var best := 0.0
	for dr in range(-cell_radius, cell_radius + 1):
		var rr := clampi(row + dr, 0, h - 1)
		for dc in range(-cell_radius, cell_radius + 1):
			var cc := _wrapc(col + dc)
			best = maxf(best, river_strength[rr * w + cc])
	return best

# Vrai si la cellule la plus proche est un lac.
func is_lake_at(unit_dir: Vector3) -> bool:
	if is_lake.is_empty():
		return false
	return is_lake[_nearest_idx(_warped(unit_dir))] != 0

# Niveau de surface du lac (interpolé) — n'a de sens que près d'un lac.
func lake_level_at(unit_dir: Vector3) -> float:
	return _bilerp(lake_level, _warped(unit_dir))

# Niveau de REMPLISSAGE (priority-flood), basse résolution => surface d'eau LISSE pour les rivières
# (la nappe épouse la vallée au lieu de suivre les bosses fines du lit). MÊMES unités que sample_elevation.
func filled_at(unit_dir: Vector3) -> float:
	return _bilerp(filled, _warped(unit_dir))

# --- Chemin CHAUD (sample_elevation) : warp mutualisé + échantillonneurs « raw » (direction déjà warpée) ---

# Direction warpée — à calculer UNE fois puis passer aux *_raw ci-dessous (évite 3-4 re-warps par sample).
func warp(unit_dir: Vector3) -> Vector3:
	return _warped(unit_dir)

func erosion_raw(wdir: Vector3) -> float:
	return _bilerp(erosion_mod, wdir)

func water_prox_raw(wdir: Vector3) -> float:
	return _bilerp(water_prox, wdir)

func is_lake_raw(wdir: Vector3) -> bool:
	return not is_lake.is_empty() and is_lake[_nearest_idx(wdir)] != 0

func filled_raw(wdir: Vector3) -> float:
	return _bilerp(filled, wdir)

func lake_level_raw(wdir: Vector3) -> float:
	return _bilerp(lake_level, wdir)

func river_raw(wdir: Vector3) -> float:
	return _bilerp(river_strength, wdir)

# Pré-calcule la PROXIMITÉ d'eau (0..1) dilatée autour des rivières/lacs (1 à l'eau, décroît sur ~4 cellules).
# Remplace le scan de voisinage runtime de sample_elevation par 1 bilerp. Off-thread, une seule fois.
func _build_water_prox() -> void:
	var n := w * h
	water_prox = PackedFloat32Array()
	water_prox.resize(n)
	for i in n:
		water_prox[i] = 1.0 if (river_strength[i] > WATER_THRESHOLD or is_lake[i] != 0) else 0.0
	var decay := 0.80
	for _p in 4:
		var src := water_prox.duplicate()
		for row in h:
			var base := row * w
			for col in w:
				var i := base + col
				if src[i] >= 0.999:
					continue
				var cm := (col - 1 + w) % w
				var cp := (col + 1) % w
				var best := src[i]
				best = maxf(best, maxf(src[base + cm], src[base + cp]) * decay)
				if row > 0:
					var u := (row - 1) * w
					best = maxf(best, maxf(src[u + cm], maxf(src[u + col], src[u + cp])) * decay)
				if row < h - 1:
					var d := (row + 1) * w
					best = maxf(best, maxf(src[d + cm], maxf(src[d + col], src[d + cp])) * decay)
				water_prox[i] = best

# Échantillon complet en un point (pratique pour les chunks).
func sample_at(unit_dir: Vector3) -> Dictionary:
	return {
		"erosion": erosion_at(unit_dir),
		"river": river_at(unit_dir),
		"is_lake": is_lake_at(unit_dir),
		"lake_level": lake_level_at(unit_dir),
	}
