class_name VegetationLibrary
extends RefCounted
## Bibliothèque de meshes procéduraux low-poly (arbres, rochers, herbe), générés UNE
## SEULE fois au démarrage et PARTAGÉS par tous les chunks via MultiMesh (jamais un
## mesh par chunk). 100% par code (aucun import), couleurs de biome bakées en couleurs
## de vertices. Déterministe (seeds fixes internes). Mobile-friendly : matériaux simples
## (vertex color, sans transparence ; herbe = double face).
##
## Variété par : (a) quelques variantes de meshes ici, (b) échelle/rotation par instance
## (au semis), (c) choix de variante selon le biome (au semis).

enum Category { TREE, ROCK, GRASS }

# Phase 24 : les ARBRES sont des espèces L-system (SpeciesLibrary), aplaties dans les slots d'index
# 0..TREE_COUNT-1 (= espèce × VARIANTS_PER_SPECIES + variante). Rochers + herbe (paramétriques) suivent.
# Tous les consommateurs (TerrainChunk, seeder) sont GÉNÉRIQUES : ils passent par mesh_for/material_for/
# category_of + les listes *_VARIANTS, donc le décalage d'index est transparent.
const TREE_SPECIES_COUNT := 4    # = SpeciesLibrary.SPECIES_COUNT (vérifié par assert en _build)
const TREE_VARIANTS_PER := 3     # = SpeciesLibrary.VARIANTS_PER_SPECIES (vérifié par assert en _build)
const TREE_COUNT := 12           # = TREE_SPECIES_COUNT × TREE_VARIANTS_PER (variantes d'arbres, index 0..11)
const V_ROCK_A := 12             # gros rocher anguleux (commun, gris)
const V_ROCK_B := 13             # caillou plus sombre (commun)
const V_GRASS_GREEN := 14        # touffe verte
const V_GRASS_DRY := 15          # touffe sèche (plage / faible humidité)
# Rochers spéciaux (minerais / précieux) — AJOUTÉS EN FIN (indices 0..15 inchangés) :
const V_ROCK_COPPER := 16        # rocher cuivré (patine verte) — minerai de cuivre
const V_ROCK_GOLD := 17          # rocher aurifère (ocre doré, brillant) — or
const V_ROCK_CRYSTAL := 18       # rocher cristallin (bleu glacé, anguleux, brillant) — gemmes précieuses
const VARIANT_COUNT := 19

const TREE_VARIANTS: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
const ROCK_VARIANTS: Array[int] = [V_ROCK_A, V_ROCK_B, V_ROCK_COPPER, V_ROCK_GOLD, V_ROCK_CRYSTAL]
# Rochers « précieux » : matériau brillant (métal/gemme) au lieu du matériau de pierre mat.
const PRECIOUS_VARIANTS: Array[int] = [V_ROCK_COPPER, V_ROCK_GOLD, V_ROCK_CRYSTAL]
const GRASS_VARIANTS: Array[int] = [V_GRASS_GREEN, V_GRASS_DRY]
const WIND_STRENGTH := 0.04            # amplitude du vent par défaut (0 = statique)

# Vrai si la variante est un arbre L-system (slots 0..TREE_COUNT-1).
static func is_tree_variant(v: int) -> bool:
	return v >= 0 and v < TREE_COUNT

# Index plat d'une variante d'arbre = espèce (SpeciesLibrary.Species) + tirage aléatoire de variante.
static func tree_variant(species: int, rng: RandomNumberGenerator) -> int:
	return species * TREE_VARIANTS_PER + rng.randi_range(0, TREE_VARIANTS_PER - 1)

var _meshes: Array[Mesh] = []
var _wind_mat: ShaderMaterial          # arbres + herbe : couleur de vertex + vent léger (double face)
var _rock_mat: StandardMaterial3D      # rochers : statiques (1 face)
var _copper_mat: StandardMaterial3D    # cuivre : semi-métallique, émission chaude de patine
var _gold_mat: StandardMaterial3D      # or : très métallique, émission dorée
var _crystal_mat: StandardMaterial3D   # cristal : brillant, émission bleue froide
var _impostor_meshes: Array[Mesh] = [] # phase 24 : 1 impostor PAR espèce (silhouette/teinte propres au loin)
var _impostor_mat: StandardMaterial3D  # impostor : NON éclairé, double face (très cheap, masqué par le fog)

func _init() -> void:
	_build()

# Mesh partagé d'une variante (assigné aux MultiMesh des chunks).
func mesh_for(variant: int) -> Mesh:
	return _meshes[variant]

func material_for(variant: int) -> Material:
	match variant:
		V_ROCK_COPPER: return _copper_mat
		V_ROCK_GOLD: return _gold_mat
		V_ROCK_CRYSTAL: return _crystal_mat
	return _rock_mat if variant in ROCK_VARIANTS else _wind_mat

# Active/désactive le vent (wind_strength = 0 => végétation statique). Désactivable au besoin.
func set_wind_enabled(enabled: bool) -> void:
	_wind_mat.set_shader_parameter("wind_strength", WIND_STRENGTH if enabled else 0.0)

# Amplitude du vent pilotée par la météo (wind ∈ [0,1] -> amplitude) — phase 13.
func set_wind_amount(wind: float) -> void:
	if _wind_mat:
		_wind_mat.set_shader_parameter("wind_strength", lerpf(0.01, 0.14, clampf(wind, 0.0, 1.0)))

func category_of(variant: int) -> int:
	if variant in GRASS_VARIANTS:
		return Category.GRASS
	if variant in ROCK_VARIANTS:
		return Category.ROCK
	return Category.TREE

# Mesh + matériau d'impostor d'arbre lointain (rendu aux positions des arbres, au-delà du
# rayon de mesh plein).
func impostor_mesh() -> Mesh:
	return _impostor_meshes[0]   # repli ; les chunks utilisent impostor_mesh_for(espèce)

# Impostor de l'espèce (SpeciesLibrary.Species) : silhouette + teinte propres, vu de loin.
func impostor_mesh_for(species: int) -> Mesh:
	return _impostor_meshes[clampi(species, 0, _impostor_meshes.size() - 1)]

func impostor_material() -> Material:
	return _impostor_mat

# Nombre de triangles d'une variante (diagnostic budget).
func tri_count(variant: int) -> int:
	var m := _meshes[variant]
	if m == null or m.get_surface_count() == 0:
		return 0
	var arr := m.surface_get_arrays(0)
	return (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3

# --- Construction (une fois) ---

func _build() -> void:
	_rock_mat = StandardMaterial3D.new()
	_rock_mat.vertex_color_use_as_albedo = true
	_rock_mat.roughness = 1.0
	# Cuivre : semi-métallique (patine cuivrée), faible émission chaude.
	_copper_mat = StandardMaterial3D.new()
	_copper_mat.vertex_color_use_as_albedo = true
	_copper_mat.metallic = 0.45
	_copper_mat.roughness = 0.38
	_copper_mat.emission_enabled = true
	_copper_mat.emission = Color(0.35, 0.22, 0.08)
	_copper_mat.emission_energy_multiplier = 0.25
	# Or : très métallique, émission dorée chaude.
	_gold_mat = StandardMaterial3D.new()
	_gold_mat.vertex_color_use_as_albedo = true
	_gold_mat.metallic = 0.78
	_gold_mat.roughness = 0.15
	_gold_mat.emission_enabled = true
	_gold_mat.emission = Color(0.60, 0.45, 0.10)
	_gold_mat.emission_energy_multiplier = 0.4
	# Cristal : brillant glacé, forte émission bleue froide.
	_crystal_mat = StandardMaterial3D.new()
	_crystal_mat.vertex_color_use_as_albedo = true
	_crystal_mat.metallic = 0.25
	_crystal_mat.roughness = 0.08
	_crystal_mat.emission_enabled = true
	_crystal_mat.emission = Color(0.30, 0.55, 0.75)
	_crystal_mat.emission_energy_multiplier = 0.55
	# Arbres + herbe : shader de vent (couleur de vertex, double face, lambert mobile).
	_wind_mat = ShaderMaterial.new()
	_wind_mat.shader = load("res://shaders/vegetation_wind.gdshader")
	_wind_mat.set_shader_parameter("wind_strength", WIND_STRENGTH)

	_meshes.resize(VARIANT_COUNT)
	# Arbres : espèces L-system (SpeciesLibrary), aplaties dans les slots 0..TREE_COUNT-1.
	var tree_sets := SpeciesLibrary.build_variant_meshes()   # [espèce][variante] -> Mesh
	assert(tree_sets.size() == TREE_SPECIES_COUNT, "SpeciesLibrary.SPECIES_COUNT != VegetationLibrary.TREE_SPECIES_COUNT")
	for sp in tree_sets.size():
		var variants: Array = tree_sets[sp]
		for v in variants.size():
			_meshes[sp * TREE_VARIANTS_PER + v] = variants[v]
	# Props paramétriques (inchangés) : rochers + herbe.
	_meshes[V_ROCK_A] = _make_rock(Color(0.44, 0.41, 0.37), 101, 1)
	_meshes[V_ROCK_B] = _make_rock(Color(0.33, 0.29, 0.27), 257, 0)
	# Rochers spéciaux : formes ET couleurs distinctes ; veines de minerai + cristal en amas de prismes.
	_meshes[V_ROCK_COPPER] = _make_rock(Color(0.32, 0.48, 0.36), 311, 1, Color(0.78, 0.50, 0.28), 2.8)   # patine verte + veines cuivrées
	_meshes[V_ROCK_GOLD] = _make_rock(Color(0.52, 0.44, 0.22), 733, 1, Color(0.95, 0.82, 0.30), 3.2)     # ocre sombre + veines dorées brillantes
	_meshes[V_ROCK_CRYSTAL] = _make_crystal(Color(0.50, 0.72, 0.88), 911)   # amas de prismes bleu glacé (gemmes)
	_meshes[V_GRASS_GREEN] = _make_grass(Color(0.30, 0.47, 0.19), 11)
	_meshes[V_GRASS_DRY] = _make_grass(Color(0.56, 0.52, 0.29), 22)

	# Impostor d'arbre lointain (non éclairé, double face) : croix de quads.
	_impostor_mat = StandardMaterial3D.new()
	_impostor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_impostor_mat.vertex_color_use_as_albedo = true
	_impostor_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Impostors par ESPÈCE (silhouette + teinte propres) : croix de quads, dégradé bas(tronc)/haut(feuillage).
	_impostor_meshes.resize(SpeciesLibrary.SPECIES_COUNT)
	_impostor_meshes[SpeciesLibrary.Species.CONIFER] = _make_impostor(3.6, 1.2, Color(0.10, 0.20, 0.12), Color(0.14, 0.34, 0.18))
	_impostor_meshes[SpeciesLibrary.Species.DECIDUOUS] = _make_impostor(2.7, 2.5, Color(0.16, 0.26, 0.13), Color(0.24, 0.45, 0.18))
	_impostor_meshes[SpeciesLibrary.Species.PALM] = _make_impostor(5.6, 2.1, Color(0.34, 0.26, 0.16), Color(0.30, 0.52, 0.20))
	_impostor_meshes[SpeciesLibrary.Species.TWISTED] = _make_impostor(2.3, 1.7, Color(0.30, 0.22, 0.34), Color(0.46, 0.30, 0.52))

# Arbre : tronc (tronc de cône fin) + canopée (cônes empilés pour conifère, blob sinon).
# Base aux pieds (y = 0) => l'instance se pose directement sur le sol.
func _make_tree(canopy_color: Color, conifer: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_color := Color(0.30, 0.20, 0.12)
	var trunk_h := 1.1
	var trunk_r := 0.10
	_frustum(st, trunk_color, 0.0, trunk_h, trunk_r, trunk_r * 0.8, 5, false)
	if conifer:
		_frustum(st, canopy_color, trunk_h * 0.55, 1.05, 0.58, 0.0, 7, true)
		_frustum(st, canopy_color.darkened(0.06), trunk_h * 0.55 + 0.7, 0.95, 0.44, 0.0, 7, true)
		_frustum(st, canopy_color.lightened(0.04), trunk_h * 0.55 + 1.35, 0.8, 0.30, 0.0, 7, true)
	else:
		_blob(st, canopy_color, Vector3(0.0, trunk_h + 0.55, 0.0), 0.72, 0.85)
	st.generate_normals()
	return st.commit()

# Rocher : icosphère déformée par bruit, légèrement aplatie. Faces plates (non indexé).
# Base ~ y = 0 (posé sur le sol). subdiv 0 = 20 tris (anguleux), 1 = 80 tris.
# vein_color + vein_freq > 0 : stries de minerai visibles sur certaines faces (Perlin secondaire).
func _make_rock(base_color: Color, noise_seed: int, subdiv: int, vein_color: Color = Color.BLACK, vein_freq: float = 0.0) -> ArrayMesh:
	var ico := PlanetGenerator._build_icosphere(subdiv)
	var verts: PackedVector3Array = ico.verts
	var idx: PackedInt32Array = ico.indices
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.seed = noise_seed
	n.frequency = 1.4
	# Bruit secondaire pour veines de minerai (optionnel : vein_freq > 0).
	var has_veins := vein_freq > 0.0
	var vn := FastNoiseLite.new()
	if has_veins:
		vn.noise_type = FastNoiseLite.TYPE_PERLIN
		vn.seed = noise_seed + 999
		vn.frequency = vein_freq
	var dpos := PackedVector3Array()
	dpos.resize(verts.size())
	for i in verts.size():
		var d := verts[i]
		var r := 0.5 * (1.0 + 0.4 * n.get_noise_3dv(d))   # rayon ~0.5 m déformé
		dpos[i] = Vector3(d.x * r, (d.y * 0.78 + 0.5) * r * 1.1, d.z * r)  # aplati + base ~0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(0, idx.size(), 3):
		var p0 := dpos[idx[k]]
		var p1 := dpos[idx[k + 1]]
		var p2 := dpos[idx[k + 2]]
		var shade := clampf(((p0.y + p1.y + p2.y) / 3.0) * 0.5, -0.1, 0.2)
		var face_col := base_color.lightened(maxf(shade, 0.0)).darkened(maxf(-shade, 0.0))
		if has_veins:
			var center := (p0 + p1 + p2) / 3.0
			var vv := vn.get_noise_3dv(center * 5.0)
			if vv > 0.15:
				face_col = face_col.lerp(vein_color, clampf((vv - 0.15) * 2.5, 0.0, 0.85))
		_tri(st, face_col, p0, p1, p2)
	st.generate_normals()
	return st.commit()

# Cristal : amas de prismes hexagonaux à angles variés (look « géode »). Faces plates, vertex-colored,
# dégradé base(sombre) → pointe(clair/brillant). Mesh DISTINCT des rochers (pas une icosphère).
func _make_crystal(base_color: Color, noise_seed: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	var count := rng.randi_range(5, 7)
	for i in count:
		var h := rng.randf_range(0.35, 0.95)
		var r := rng.randf_range(0.06, 0.15)
		var tilt_x := rng.randf_range(-0.40, 0.40)
		var tilt_z := rng.randf_range(-0.40, 0.40)
		var base_off := Vector3(rng.randf_range(-0.18, 0.18), 0.0, rng.randf_range(-0.18, 0.18))
		var c_dark := base_color.darkened(rng.randf_range(0.08, 0.28))
		var c_bright := base_color.lightened(rng.randf_range(0.08, 0.30))
		_hexprism(st, base_off, Vector3(tilt_x, 1.0, tilt_z).normalized(), h, r, c_dark, c_bright, rng.randf() * TAU)
	st.generate_normals()
	return st.commit()

# Prisme hexagonal avec pointe effilée : faces latérales + capuchon conique. Utilisé par _make_crystal.
func _hexprism(st: SurfaceTool, base: Vector3, up_dir: Vector3, height: float, radius: float, c_base: Color, c_tip: Color, twist: float) -> void:
	var sides := 6
	var right := up_dir.cross(Vector3.UP if absf(up_dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT).normalized()
	var fwd := right.cross(up_dir).normalized()
	var top := base + up_dir * height
	var tip := base + up_dir * (height * 1.18)
	for s in sides:
		var a0 := twist + TAU * s / sides
		var a1 := twist + TAU * (s + 1) / sides
		var d0 := right * cos(a0) + fwd * sin(a0)
		var d1 := right * cos(a1) + fwd * sin(a1)
		var b0 := base + d0 * radius
		var b1 := base + d1 * radius
		var t0 := top + d0 * radius * 0.65
		var t1 := top + d1 * radius * 0.65
		_tri(st, c_base, b0, t0, b1)
		_tri(st, c_base.lerp(c_tip, 0.5), b1, t0, t1)
		_tri(st, c_tip, t0, tip, t1)
		_tri(st, c_base, base, b1, b0)

# Herbe : touffe de brins effilés courbés, dégradé bas->haut. Matériau double face (oscillation par le vent).
func _make_grass(color: Color, seed_val: int) -> ArrayMesh:
	# Touffe PROCÉDURALE : 3 brins fins effilés, courbés, orientés au hasard (seedé => déterministe).
	# Dégradé sombre (base) -> couleur (pointe). Bas-poly ; double face + oscillation via le matériau de vent.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var cb := color.darkened(0.42)
	for i in 3:   # 3 brins/touffe (allégé) : le tapis dense (×20) fait le volume, pas chaque touffe
		var yaw := rng.randf() * TAU
		var lean := rng.randf_range(0.05, 0.22)
		var hgt := 0.42 * rng.randf_range(0.65, 1.3)
		var wid := rng.randf_range(0.028, 0.05)
		var off := Vector3(rng.randf_range(-0.11, 0.11), 0.0, rng.randf_range(-0.11, 0.11))
		_grass_blade(st, off, yaw, lean, hgt, wid, cb, color.lightened(rng.randf_range(0.0, 0.18)))
	st.generate_normals()
	return st.commit()

# Un brin d'herbe : ruban effilé courbé (2 segments) penché dans une direction. Couleur base->pointe.
func _grass_blade(st: SurfaceTool, base: Vector3, yaw: float, lean: float, height: float, width: float, c_base: Color, c_tip: Color) -> void:
	var dir := Vector3(cos(yaw), 0.0, sin(yaw))
	var perp := Vector3(-sin(yaw), 0.0, cos(yaw))
	var segs := 2
	var prev_l := base
	var prev_r := base
	for k in segs + 1:
		var t := float(k) / float(segs)
		var center := base + dir * (lean * t * t) + Vector3(0.0, t * height, 0.0)   # courbe + monte
		var hw := width * (1.0 - t * 0.85)        # effilé vers la pointe
		var l := center - perp * hw
		var r := center + perp * hw
		if k > 0:
			var cc := c_base.lerp(c_tip, t)
			var cp := c_base.lerp(c_tip, float(k - 1) / float(segs))
			st.set_color(cp); st.add_vertex(prev_l)
			st.set_color(cp); st.add_vertex(prev_r)
			st.set_color(cc); st.add_vertex(r)
			st.set_color(cp); st.add_vertex(prev_l)
			st.set_color(cc); st.add_vertex(r)
			st.set_color(cc); st.add_vertex(l)
		prev_l = l
		prev_r = r

# Impostor d'arbre lointain : 2 quads croisés (visibles de tout angle), dégradé bas/haut
# rappelant une silhouette d'arbre. Très peu de triangles ; rendu non éclairé.
func _make_impostor(h: float, w: float, lo: Color, hi: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_vquad(st, Vector3(-w * 0.5, 0, 0), Vector3(w * 0.5, 0, 0), h, lo, hi)
	_vquad(st, Vector3(0, 0, -w * 0.5), Vector3(0, 0, w * 0.5), h, lo, hi)
	st.generate_normals()
	return st.commit()

# --- Primitives bas niveau ---

# Tronc de cône (r1=0 => cône plein). Faces latérales sortantes + cap inférieur optionnel.
func _frustum(st: SurfaceTool, color: Color, y0: float, h: float, r0: float, r1: float, sides: int, base_cap: bool) -> void:
	var y1 := y0 + h
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var b0 := Vector3(d0.x * r0, y0, d0.z * r0)
		var b1 := Vector3(d1.x * r0, y0, d1.z * r0)
		if r1 <= 0.0001:
			_tri(st, color, b0, Vector3(0, y1, 0), b1)
		else:
			var t0 := Vector3(d0.x * r1, y1, d0.z * r1)
			var t1 := Vector3(d1.x * r1, y1, d1.z * r1)
			_tri(st, color, b0, t0, b1)
			_tri(st, color, b1, t0, t1)
		if base_cap:
			_tri(st, color, Vector3(0, y0, 0), b1, b0)   # face vers le bas

# Blob (icosphère subdiv 0 déformée légèrement), faces plates. Pour canopée feuillue.
func _blob(st: SurfaceTool, color: Color, center: Vector3, radius: float, yscale: float) -> void:
	var ico := PlanetGenerator._build_icosphere(0)
	var verts: PackedVector3Array = ico.verts
	var idx: PackedInt32Array = ico.indices
	for k in range(0, idx.size(), 3):
		var p0 := center + Vector3(verts[idx[k]].x * radius, verts[idx[k]].y * radius * yscale, verts[idx[k]].z * radius)
		var p1 := center + Vector3(verts[idx[k + 1]].x * radius, verts[idx[k + 1]].y * radius * yscale, verts[idx[k + 1]].z * radius)
		var p2 := center + Vector3(verts[idx[k + 2]].x * radius, verts[idx[k + 2]].y * radius * yscale, verts[idx[k + 2]].z * radius)
		_tri(st, color, p0, p1, p2)

# Quad vertical (arête de base p0->p1, élevée de h), dégradé bas/haut.
func _vquad(st: SurfaceTool, p0: Vector3, p1: Vector3, h: float, c_bot: Color, c_top: Color) -> void:
	var up := Vector3(0, h, 0)
	st.set_color(c_bot); st.add_vertex(p0)
	st.set_color(c_bot); st.add_vertex(p1)
	st.set_color(c_top); st.add_vertex(p1 + up)
	st.set_color(c_bot); st.add_vertex(p0)
	st.set_color(c_top); st.add_vertex(p1 + up)
	st.set_color(c_top); st.add_vertex(p0 + up)

func _tri(st: SurfaceTool, color: Color, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.set_color(color); st.add_vertex(a)
	st.set_color(color); st.add_vertex(b)
	st.set_color(color); st.add_vertex(c)
