class_name SurfaceGenerator
extends RefCounted
## Génère un PATCH LOCAL borné de surface autour d'une coordonnée d'atterrissage,
## 100% déterministe. Échantillonne LE MÊME bruit que la sphère orbitale (via
## PlanetGenerator.sample_elevation / sample_biome_color) => le sol est cohérent
## avec la vue d'en haut.
##
## Présentation À PLAT : up local = +Y monde (pas de gravité sphérique). On place
## une grille tangente au point d'atterrissage et on mappe l'élévation sur Y.
## Pas de streaming ni de chunking : patch de taille fixe + murs de bordure (gérés
## par SurfaceView).

const DEFAULT_RESOLUTION := 96          # cellules/côté => (R+1)^2 vertices
const DEFAULT_PATCH_SIZE := 256.0       # mètres (1:1)
const DEFAULT_VERTICAL_SCALE := 165.0   # mètres par unité d'élévation (relief doux & arrondi, larges plaines)
const DEFAULT_PLANET_PHYS_RADIUS := 3000.0  # mètres : règle l'angle couvert par le patch
const RIVER_WATER_THR := PlanetFlowMap.WATER_THRESHOLD   # phase 23 : force de rivière mini pour poser de l'eau (seuil partagé)
const RIVER_FILL := 1.0         # phase 23 (legacy) : ancien remplissage rivière
const RIVER_SKIN := 0.25        # phase 24 : fine pellicule d'eau au-dessus du lit (la surface vient du remplissage LISSÉ)
# Cascades (phase 23-10) : une cellule d'eau dont la SURFACE chute fortement entre ses coins => nappe d'écume.
# Seuils HAUTS : le relief est marqué (vertical_scale 165) donc la rivière moyenne descend déjà ~1 m/cellule ;
# on ne veut PAS écumer toute la rivière, seulement les VRAIES parois (les cellules raides s'y regroupent
# naturellement => cascade cohérente, pas des taches éparses). Calibré headless (_falltest).
const WATERFALL_MIN_DROP := 8.0   # m : chute mini absolue
const WATERFALL_SLOPE := 3.0      # drop/cell mini (~72°) : quasi-paroi (croît avec le LOD => rare au loin)
const WATER_CARVE := 0.025      # phase 24 : creuse le lit SOUS la surface d'eau (≈4 m) => cuvette/chenal réels (l'eau épouse le relief)
const BATHY_MAX_DROP := 0.045   # phase 24 (eau) : descente MAX du fond sous le niveau de mer (×vertical_scale ≈ ~7 m)
const BATHY_SLOPE := 0.7        # pente du fond marin (fraction de la profondeur réelle) => bas-fonds visibles

# Renvoie { mesh: ArrayMesh, heightmap_shape: HeightMapShape3D, cell_size, patch_size, spawn_height }.
static func generate(seed_local: int, landing_dir: Vector3, resolution: int = DEFAULT_RESOLUTION, patch_size: float = DEFAULT_PATCH_SIZE, vertical_scale: float = DEFAULT_VERTICAL_SCALE, planet_phys_radius: float = DEFAULT_PLANET_PHYS_RADIUS) -> Dictionary:
	var pg := PlanetGenerator.new()
	pg.configure(seed_local)  # mêmes bruits (sea_level / fréquence par défaut) que l'orbite

	var n := landing_dir.normalized()
	# Repère tangent au point d'atterrissage (évite le cas dégénéré aux pôles).
	var ref := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var east := ref.cross(n).normalized()
	var north := n.cross(east).normalized()

	var sea := PlanetGenerator.DEFAULT_SEA_LEVEL
	var cell_size := patch_size / float(resolution)
	var w := resolution + 1

	# Élévation au centre = référence (le joueur spawn ~ y = 0).
	var center_h: float = maxf(pg.sample_elevation(n), sea)

	var heights := PackedFloat32Array()
	heights.resize(w * w)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in w:
		for i in w:
			var x := (float(i) / resolution - 0.5) * patch_size
			var z := (float(j) / resolution - 0.5) * patch_size
			# Direction sur la sphère : petit décalage tangent autour de n.
			var dir := (n + east * (x / planet_phys_radius) + north * (z / planet_phys_radius)).normalized()
			var e := pg.sample_elevation(dir)
			var land_e: float = maxf(e, sea)
			var height := (land_e - center_h) * vertical_scale
			heights[j * w + i] = height
			st.set_color(pg.sample_biome_color(dir, e))
			st.add_vertex(Vector3(x, height, z))

	# Deux triangles par cellule (face vers le haut, +Y).
	for j in resolution:
		for i in resolution:
			var a := j * w + i
			var b := j * w + i + 1
			var c := (j + 1) * w + i
			var d := (j + 1) * w + i + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	st.generate_normals()
	var mesh := st.commit()

	# Collision = grille régulière HeightMapShape3D (efficace, pas de trimesh lourd).
	# Le node porteur sera mis à l'échelle (cell_size, 1, cell_size) par SurfaceView
	# pour faire correspondre l'espacement des cellules aux mètres du mesh.
	var shape := HeightMapShape3D.new()
	shape.map_width = w
	shape.map_depth = w
	shape.map_data = heights

	return {
		"mesh": mesh,
		"heightmap_shape": shape,
		"cell_size": cell_size,
		"patch_size": patch_size,
		"spawn_height": 0.0,
	}

# Génère UN chunk en VRAIES positions sphériques (rayon planète + élévation radiale),
# keyé par la grille tangente FIXE (anchor_dir, east, north) en coords tangentes
# GLOBALES => bords voisins échantillonnés à l'identique (zéro couture en espace-
# planète). Le mesh + le heightmap sont exprimés dans le repère tangent AU CENTRE du
# chunk (heightfield) ; le node sera placé à Transform3D(basis, center) en espace-
# planète, sous PlanetRoot. Déterministe + thread-safe. Renvoie
# { mesh, collision_shape (trimesh ConcavePolygonShape3D), cell_size, center, basis }.
static func generate_chunk(seed_local: int, cx: int, cz: int, anchor_dir: Vector3, east: Vector3, north: Vector3, chunk_size: float = DEFAULT_PATCH_SIZE, resolution: int = DEFAULT_RESOLUTION, phys_radius: float = DEFAULT_PLANET_PHYS_RADIUS, vertical_scale: float = DEFAULT_VERTICAL_SCALE, skirt_depth: float = 0.0, flow_map: PlanetFlowMap = null) -> Dictionary:
	var pg := PlanetGenerator.new()
	pg.configure(seed_local)
	pg.set_flow_map(flow_map)   # phase 23 : terrain érodé + rivières/lacs teintés (cohérent orbite↔sol)
	var sea := PlanetGenerator.DEFAULT_SEA_LEVEL
	var cell := chunk_size / float(resolution)
	var w := resolution + 1

	# Direction + repère tangent au CENTRE du chunk (le heightfield y est exprimé).
	var cgx := cx * chunk_size + chunk_size * 0.5
	var cgz := cz * chunk_size + chunk_size * 0.5
	var dir_c := (anchor_dir * phys_radius + east * cgx + north * cgz).normalized()
	var center := dir_c * phys_radius                 # centre du chunk sur la sphère (espace-planète)
	var basis := FloatingOrigin.tangent_basis(dir_c)  # colonnes east_c, up_c, north_c
	var inv := basis.inverse()                        # espace-planète -> local chunk

	# HALO : on échantillonne 1 rangée de voisins AU-DELÀ de chaque bord. Les normales calculées depuis
	# ce halo sont IDENTIQUES de part et d'autre d'un bord de chunk (le halo d'un chunk = l'intérieur du
	# voisin) => zéro couture d'ombrage entre chunks (la cause des « lignes » au sol). PUR + thread-safe.
	var hw := w + 2
	var hgrid := PackedVector3Array()
	hgrid.resize(hw * hw)
	var he := PackedFloat32Array()     # élévations du halo (réutilisées pour la couleur, pas de re-sample)
	he.resize(hw * hw)
	for hj in hw:
		for hi in hw:
			var gx := cx * chunk_size + (hi - 1) * cell   # hi=1 => 1er sommet de surface ; hi=0 => 1 cellule avant
			var gz := cz * chunk_size + (hj - 1) * cell
			var dir := (anchor_dir * phys_radius + east * gx + north * gz).normalized()
			var e := pg.sample_elevation(dir)
			he[hj * hw + hi] = e
			# Sous la mer : le fond descend (bas-fonds). Au-dessus : terrain, MAIS on CREUSE le lit sous la
			# surface d'eau LISSE (lac/rivière) => la terre forme une cuvette/chenal et l'eau épouse le relief.
			# Bathymétrie océan uniquement ; la vallée/bassin d'eau douce vient déjà de sample_elevation (creusement).
			var floor_e := e
			if e < sea:
				floor_e = sea - minf((sea - e) * BATHY_SLOPE, BATHY_MAX_DROP)
			var sphere_pos := dir * (phys_radius + floor_e * vertical_scale)
			hgrid[hj * hw + hi] = inv * (sphere_pos - center)

	var grid := PackedVector3Array()   # positions locales (mètres) réutilisées pour la collision + jupes
	grid.resize(w * w)
	var cols := PackedColorArray()     # couleurs de biome (réutilisées par les jupes)
	cols.resize(w * w)
	var mdeltas := PackedVector3Array() # geomorph : déplacement de chaque sommet vers la forme du LOD plus grossier
	mdeltas.resize(w * w)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGB_FLOAT)   # CUSTOM0 = delta de morph (xyz local)
	for j in w:
		for i in w:
			var hi := i + 1
			var hj := j + 1
			var local: Vector3 = hgrid[hj * hw + hi]
			grid[j * w + i] = local
			# Normale ANALYTIQUE depuis les voisins du halo => cohérente aux bords inter-chunks (zéro couture).
			var tx := hgrid[hj * hw + (hi + 1)] - hgrid[hj * hw + (hi - 1)]
			var tz := hgrid[(hj + 1) * hw + hi] - hgrid[(hj - 1) * hw + hi]
			var nrm := tz.cross(tx).normalized()
			var gx := cx * chunk_size + i * cell
			var gz := cz * chunk_size + j * cell
			var dir := (anchor_dir * phys_radius + east * gx + north * gz).normalized()
			var col := pg.sample_biome_color(dir, he[hj * hw + hi])
			cols[j * w + i] = col
			# Geomorph : cible des sommets IMPAIRS = milieu de l'arête/diagonale (triangulation b-c) du LOD
			# plus grossier => morph EXACT (zéro pop résiduel). Sommets PAIRS = survivent => delta nul.
			# Réutilise hgrid (AUCUN sample_elevation en plus => la fonction chaude n'est pas alourdie).
			var md := Vector3.ZERO
			var oi := i & 1
			var oj := j & 1
			if oi == 1 and oj == 0:
				md = (hgrid[hj * hw + (hi - 1)] + hgrid[hj * hw + (hi + 1)]) * 0.5 - local
			elif oi == 0 and oj == 1:
				md = (hgrid[(hj - 1) * hw + hi] + hgrid[(hj + 1) * hw + hi]) * 0.5 - local
			elif oi == 1 and oj == 1:
				md = (hgrid[(hj - 1) * hw + (hi + 1)] + hgrid[(hj + 1) * hw + (hi - 1)]) * 0.5 - local
			mdeltas[j * w + i] = md
			st.set_custom(0, Color(md.x, md.y, md.z, 0.0))
			st.set_normal(nrm)
			st.set_color(col)
			st.add_vertex(local)

	# Collision = TRIMESH (ConcavePolygonShape3D) en coords locales (mètres), construite
	# depuis les MÊMES sommets que la SURFACE (sans les jupes) => AUCUNE mise à l'échelle
	# (donc pas de cisaillement sous la rotation du chunk, que Jolt gère mal pour une
	# HeightMapShape) et collision EXACTEMENT alignée sur le visuel. Pur => sûr hors-thread.
	var faces := PackedVector3Array()
	faces.resize(resolution * resolution * 6)
	var fi := 0
	for j in resolution:
		for i in resolution:
			var a := j * w + i
			var b := j * w + i + 1
			var c := (j + 1) * w + i
			var d := (j + 1) * w + i + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
			faces[fi] = grid[a]
			faces[fi + 1] = grid[b]
			faces[fi + 2] = grid[c]
			faces[fi + 3] = grid[b]
			faces[fi + 4] = grid[d]
			faces[fi + 5] = grid[c]
			fi += 6

	# JUPES de bordure (visuel uniquement) : murets verticaux descendant le long des 4 bords,
	# pour masquer les fissures inter-LOD (un chunk grossier interpole droit là où le voisin
	# fin ondule). Sommets séparés (pas partagés avec la surface) => normales de surface
	# propres. Ordre de parcours par bord choisi pour des normales SORTANTES (pas de back-face).
	if skirt_depth > 0.0:
		var vc := w * w
		vc = _add_skirt(st, grid, cols, mdeltas, _edge_indices(w, resolution, "S"), skirt_depth, vc)
		vc = _add_skirt(st, grid, cols, mdeltas, _edge_indices(w, resolution, "N"), skirt_depth, vc)
		vc = _add_skirt(st, grid, cols, mdeltas, _edge_indices(w, resolution, "E"), skirt_depth, vc)
		vc = _add_skirt(st, grid, cols, mdeltas, _edge_indices(w, resolution, "W"), skirt_depth, vc)

	# Pas de generate_normals : les normales sont déjà posées analytiquement (halo) => cohérentes aux bords.
	var mesh := st.commit()

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)

	# Phase 23 : nappe d'eau (rivières + lacs) + cascades, repère LOCAL du chunk (vides si pas de FlowMap / chunk sec).
	var water := _build_water(flow_map, grid, w, resolution, cell, chunk_size, cx, cz, anchor_dir, east, north, phys_radius, vertical_scale, inv, center)

	return {"mesh": mesh, "collision_shape": shape, "cell_size": cell, "center": center, "basis": basis, "water_mesh": water.water, "waterfall_mesh": water.falls}

# Phase 23 — construit la nappe d'eau d'un chunk : rivières (suivent le lit + fin remplissage) et lacs
# (surface PLATE au niveau d'exutoire). En repère LOCAL du chunk (comme le terrain) ; rendue avec
# water_surface.gdshader (courbure de mer désactivée côté matériau : déjà portée par la transform du chunk).
# PUR + thread-safe. Renvoie null si la FlowMap est absente ou si aucune eau ne traverse le chunk.
static func _build_water(flow_map: PlanetFlowMap, grid: PackedVector3Array, w: int, resolution: int, cell: float, chunk_size: float, cx: int, cz: int, anchor_dir: Vector3, east: Vector3, north: Vector3, phys_radius: float, vertical_scale: float, inv: Basis, center: Vector3) -> Dictionary:
	if flow_map == null:
		return {"water": null, "falls": null}
	var base_x := cx * chunk_size
	var base_z := cz * chunk_size
	# Pré-test grossier : eau dans ce chunk ? (sinon on évite le scan plein des chunks secs, la majorité)
	var has_water := false
	var step := maxi(resolution / 8, 1)
	for j in range(0, w, step):
		for i in range(0, w, step):
			var dd := (anchor_dir * phys_radius + east * (base_x + i * cell) + north * (base_z + j * cell)).normalized()
			if flow_map.is_lake_at(dd) or flow_map.river_at(dd) > RIVER_WATER_THR:
				has_water = true
				break
		if has_water:
			break
	if not has_water:
		return {"water": null, "falls": null}
	# Scan plein : masque humide + niveau d'eau (Y local) par vertex.
	var wet := PackedByteArray()
	wet.resize(w * w)
	var wy := PackedFloat32Array()
	wy.resize(w * w)
	for j in w:
		for i in w:
			var idx := j * w + i
			var dir := (anchor_dir * phys_radius + east * (base_x + i * cell) + north * (base_z + j * cell)).normalized()
			# Niveau d'eau (élévation) : lac = surface plate (exutoire) ; rivière = PEU PROFONDE au FOND de sa
			# vallée creusée (filled - VALLEY_DEPTH + RIVER_DEPTH). On ne mouille QUE là où l'eau dépasse le
			# terrain carvé (la vallée vient de sample_elevation) => berges/îlots naturels, ni débord ni flottement.
			var water_e := -1000.0
			if flow_map.is_lake_at(dir):
				water_e = flow_map.lake_level_at(dir)
			elif flow_map.river_at(dir) > RIVER_WATER_THR:
				water_e = flow_map.filled_at(dir) - PlanetFlowMap.VALLEY_DEPTH + PlanetFlowMap.RIVER_DEPTH
			if water_e > -999.0:
				var wsphere := dir * (phys_radius + water_e * vertical_scale)
				var wy_local := (inv * (wsphere - center)).y
				if wy_local > grid[idx].y:
					wy[idx] = wy_local
					wet[idx] = 1
				else:
					wy[idx] = grid[idx].y
			else:
				wy[idx] = grid[idx].y
	# Un quad par cellule ayant ≥1 coin humide. Cellule à CHUTE RAIDE (cascade) => routée vers le mesh
	# "falls" (shader de mousse) au lieu de l'eau calme : MÊME géométrie (épouse la paroi, pas de clipping),
	# juste un autre rendu. UV de cascade = (x local m, profondeur sous la lèvre m) => mousse défilant vers le bas.
	var wst := SurfaceTool.new()
	wst.begin(Mesh.PRIMITIVE_TRIANGLES)
	wst.set_normal(Vector3.UP)   # ignorée par le shader (recalcule la normale via les vagues), évite un warning
	var fst := SurfaceTool.new()
	fst.begin(Mesh.PRIMITIVE_TRIANGLES)
	fst.set_normal(Vector3.UP)
	var emitted := false
	var any_fall := false
	for j in resolution:
		for i in resolution:
			var a := j * w + i
			var b := j * w + i + 1
			var c := (j + 1) * w + i
			var d := (j + 1) * w + i + 1
			if wet[a] == 0 and wet[b] == 0 and wet[c] == 0 and wet[d] == 0:
				continue
			var va := Vector3(grid[a].x, wy[a], grid[a].z)
			var vb := Vector3(grid[b].x, wy[b], grid[b].z)
			var vc := Vector3(grid[c].x, wy[c], grid[c].z)
			var vd := Vector3(grid[d].x, wy[d], grid[d].z)
			# Cellule en cascade ? Chute RAIDE de la SURFACE D'EAU (coins HUMIDES seulement — sinon une
			# berge sèche raide passerait pour une chute). On exige ≥3 coins humides (cellule submergée).
			var nwet := int(wet[a]) + int(wet[b]) + int(wet[c]) + int(wet[d])
			var is_fall := false
			var hi := wy[a]
			if nwet >= 3:
				var hiw := -1.0e9
				var low := 1.0e9
				for k in [a, b, c, d]:
					if wet[k] == 1:
						hiw = maxf(hiw, wy[k])
						low = minf(low, wy[k])
				var dropw := hiw - low
				is_fall = dropw >= WATERFALL_MIN_DROP and dropw >= cell * WATERFALL_SLOPE
				hi = hiw
			if is_fall:
				_fall_tri(fst, va, vb, vc, hi)
				_fall_tri(fst, vb, vd, vc, hi)
				any_fall = true
			else:
				wst.add_vertex(va); wst.add_vertex(vb); wst.add_vertex(vc)
				wst.add_vertex(vb); wst.add_vertex(vd); wst.add_vertex(vc)
				emitted = true
	var water_mesh: ArrayMesh = wst.commit() if emitted else null
	var falls_mesh: ArrayMesh = fst.commit() if any_fall else null
	return {"water": water_mesh, "falls": falls_mesh}

# Cascade : ajoute un triangle au mesh de chute avec des UV pour waterfall.gdshader.
# UV.x = position locale X (largeur, m) ; UV.y = profondeur sous la lèvre (hi - y, m, 0 en haut) => défilement bas.
static func _fall_tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, hi: float) -> void:
	# maxf : un coin sec (cellule nwet==3) peut dépasser la lèvre d'eau => UV.y<0 (mousse parasite sur la berge).
	st.set_uv(Vector2(p0.x, maxf(hi - p0.y, 0.0))); st.add_vertex(p0)
	st.set_uv(Vector2(p1.x, maxf(hi - p1.y, 0.0))); st.add_vertex(p1)
	st.set_uv(Vector2(p2.x, maxf(hi - p2.y, 0.0))); st.add_vertex(p2)

# Indices de grille d'un bord, dans l'ordre de parcours donnant une normale SORTANTE pour
# la jupe (cf. _add_skirt). S/N = bords j ; E/W = bords i.
static func _edge_indices(w: int, resolution: int, edge: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	match edge:
		"S":  # j=0, i croissant (dir +X => normale -Z)
			for i in w:
				out.append(i)
		"N":  # j=res, i décroissant (dir -X => normale +Z)
			for i in range(resolution, -1, -1):
				out.append(resolution * w + i)
		"E":  # i=res, j croissant (dir +Z => normale +X)
			for j in w:
				out.append(j * w + resolution)
		"W":  # i=0, j décroissant (dir -Z => normale -X)
			for j in range(resolution, -1, -1):
				out.append(j * w)
	return out

# Ajoute une bande de jupe le long d'un bord : sommets « hauts » dupliqués (mêmes positions
# que le bord, normales indépendantes) + sommets « bas » (descendus de depth en -Y local) +
# quads sortants. Renvoie le nouveau compteur de sommets.
static func _add_skirt(st: SurfaceTool, grid: PackedVector3Array, cols: PackedColorArray, mdeltas: PackedVector3Array, idx_list: PackedInt32Array, depth: float, vcount: int) -> int:
	var n := idx_list.size()
	var down := Vector3(0.0, depth, 0.0)
	st.set_normal(Vector3.UP)   # jupe : normale neutre (mur surtout caché sous la surface)
	for k in n:
		var gi := idx_list[k]
		var md := mdeltas[gi]
		st.set_custom(0, Color(md.x, md.y, md.z, 0.0))   # la jupe morphe avec son bord
		st.set_color(cols[gi])
		st.add_vertex(grid[gi])              # haut (dupliqué)
	for k in n:
		var gi := idx_list[k]
		var md := mdeltas[gi]
		st.set_custom(0, Color(md.x, md.y, md.z, 0.0))
		st.set_color(cols[gi])
		st.add_vertex(grid[gi] - down)       # bas
	for k in n - 1:
		var t0 := vcount + k
		var t1 := vcount + k + 1
		var b0 := vcount + n + k
		var b1 := vcount + n + k + 1
		st.add_index(t0)
		st.add_index(t1)
		st.add_index(b1)
		st.add_index(t0)
		st.add_index(b1)
		st.add_index(b0)
	return vcount + 2 * n
