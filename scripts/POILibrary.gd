class_name POILibrary
extends RefCounted
## Phase 20 — COUCHE C : générateurs de POI (lieux d'intérêt) 100% procéduraux. Chaque catégorie est
## une fonction generate()-> Node3D produisant une instance autonome (meshes + matériaux + éventuelles
## particules). Créée UNE fois et partagée (matériaux communs cachés) ; les generate() sont appelés
## MAIN-THREAD, budgétés, quand un chunk porteur entre dans l'anneau POI.
##
## TON CONTEMPLATIF ABSOLU : nature paisible + traces d'anciennes présences ÉRODÉES, énigmatiques,
## mélancoliques. JAMAIS de violence, combat, horreur, arme, cadavre récent. Une ruine est usée par le
## temps, pas brûlée ; un monolithe est mystérieux, pas hostile. Aucune interaction, aucun intérieur.

enum Category {
	# --- Naturel (10) ---
	GEYSER, NATURAL_ARCH, GIANT_TREE, CRYSTAL_FOREST, HOT_SPRING,
	FROZEN_WATERFALL, LONE_DUNE, HOODOO, BASALT_COLUMNS, BIOLUM_GROVE,
	# --- Traces d'anciennes présences (6) ---
	MONOLITH, STONE_CIRCLE, ALTAR, RUINED_ARCH, CAIRN, BEACON,
}
const CATEGORY_COUNT := 16

# Catégories NOTABLES (« d'envergure ») : reçoivent un nom via NameGenerator (phase 19.5). Les autres
# (geyser, source chaude, cairn, etc.) restent anonymes — le nommage souligne le remarquable.
const NAMED: Array[int] = [
	Category.NATURAL_ARCH, Category.GIANT_TREE, Category.CRYSTAL_FOREST,
	Category.MONOLITH, Category.STONE_CIRCLE, Category.ALTAR, Category.RUINED_ARCH,
]

const CATEGORY_NAMES := [
	"Geyser", "Arche naturelle", "Arbre géant", "Forêt de cristal", "Source chaude",
	"Cascade gelée", "Dune solitaire", "Cheminée de fée", "Orgues basaltiques", "Bosquet luminescent",
	"Monolithe", "Cercle de pierres", "Autel oublié", "Arche en ruines", "Cairn", "Balise abandonnée",
]

# Matériaux PARTAGÉS (les couleurs/teintes spéciales — cristal, glace, lueur, eau — sont créées
# PAR POI dans les générateurs, car elles varient avec le seed).
var _stone_mat: StandardMaterial3D
var _sand_mat: StandardMaterial3D
var _bark_mat: StandardMaterial3D
var _leaf_mat: StandardMaterial3D
var _basalt_mat: StandardMaterial3D

func _init() -> void:
	_stone_mat = _solid(true)
	_sand_mat = _solid(true)
	_bark_mat = _solid(true)
	_leaf_mat = _solid(false)   # canopée : double face
	_basalt_mat = _solid(true)

func _solid(one_sided: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	if not one_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

static func is_named(category: int) -> bool:
	return category in NAMED

static func category_name(category: int) -> String:
	return CATEGORY_NAMES[category] if category >= 0 and category < CATEGORY_NAMES.size() else "?"

# Construit l'instance procédurale d'un POI (Node3D autonome, base à y=0 => posée sur le sol).
# Déterministe par seed_val. MAIN-THREAD (crée des Nodes/particules).
func generate(category: int, seed_val: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	match category:
		Category.GEYSER: return _make_geyser(rng)
		Category.NATURAL_ARCH: return _make_natural_arch(rng)
		Category.GIANT_TREE: return _make_giant_tree(rng)
		Category.CRYSTAL_FOREST: return _make_crystal_forest(rng)
		Category.HOT_SPRING: return _make_hot_spring(rng)
		Category.FROZEN_WATERFALL: return _make_frozen_waterfall(rng)
		Category.LONE_DUNE: return _make_lone_dune(rng)
		Category.HOODOO: return _make_hoodoo(rng)
		Category.BASALT_COLUMNS: return _make_basalt_columns(rng)
		Category.BIOLUM_GROVE: return _make_biolum_grove(rng)
		Category.MONOLITH: return _make_monolith(rng)
		Category.STONE_CIRCLE: return _make_stone_circle(rng)
		Category.ALTAR: return _make_altar(rng)
		Category.RUINED_ARCH: return _make_ruined_arch(rng)
		Category.CAIRN: return _make_cairn(rng)
		Category.BEACON: return _make_beacon(rng)
	return _make_monolith(rng)

# ============================ NATUREL ============================

# GEYSER : socle de pierre minéralisé + cheminée + jet de vapeur (GPU particles verticales lentes).
func _make_geyser(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone := Color(0.55, 0.50, 0.44).lerp(Color(0.62, 0.58, 0.40), rng.randf())   # dépôts minéraux ocres
	var rad := rng.randf_range(1.3, 1.9)
	_frustum(st, stone, 0.0, rng.randf_range(0.8, 1.3), rad, rad * 0.55, 10, true)     # monticule
	_frustum(st, stone.darkened(0.3), 0.7, 0.5, rad * 0.42, rad * 0.30, 8, false)      # bouche
	st.generate_normals()
	root.add_child(_mesh_node(st.commit(), _stone_mat))
	# Jet de vapeur : haut, étroit, blanc, additif, lent (contemplatif).
	var jet := _vapor(rng.randf_range(5.0, 8.0), rad * 0.3, 30, Vector3(0, rng.randf_range(2.2, 3.2), 0), Color(0.92, 0.95, 1.0, 0.5))
	jet.position.y = 1.0
	root.add_child(jet)
	return root

# ARCHE NATURELLE : pont de pierre cintré (section rectangulaire balayée le long d'un demi-cercle).
func _make_natural_arch(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone := Color(0.50, 0.42, 0.34).lerp(Color(0.60, 0.50, 0.40), rng.randf())
	var R := rng.randf_range(3.5, 5.5)         # rayon de l'arche
	var half_w := rng.randf_range(0.7, 1.1)    # demi-largeur du pont
	var thick := rng.randf_range(0.7, 1.1)     # épaisseur de la voûte
	var steps := 16
	var prev_in := []
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var ang := t * PI
		var ero := 1.0 + 0.06 * sin(t * 9.0)   # légère érosion ondulée
		var cx := cos(ang)
		var cy := sin(ang)
		var inner := Vector3(cx * R, cy * R, 0.0)
		var outer := Vector3(cx * (R + thick * ero), cy * (R + thick * ero), 0.0)
		# 4 coins de la section (intérieur/extérieur × gauche/droite en Z).
		var ring := [
			inner + Vector3(0, 0, -half_w), inner + Vector3(0, 0, half_w),
			outer + Vector3(0, 0, half_w), outer + Vector3(0, 0, -half_w),
		]
		if i > 0:
			for k in 4:
				var a: Vector3 = prev_in[k]
				var b: Vector3 = prev_in[(k + 1) % 4]
				var c: Vector3 = ring[(k + 1) % 4]
				var d: Vector3 = ring[k]
				_quad(st, stone.darkened(0.05 * (k % 2)), a, b, c, d)
		prev_in = ring
	st.generate_normals()
	root.add_child(_mesh_node(st.commit(), _stone_mat))
	return root

# ARBRE GÉANT SOLITAIRE : tronc démesuré + grosses canopées (×8-12 d'un arbre normal).
func _make_giant_tree(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	# Phase 24 : colosse L-system (branchage organique) — bien plus vivant que l'ancien tronc + blobs.
	# Mesh unique à couleurs de vertices (bois + feuilles) rendu par _leaf_mat (double face).
	root.add_child(_mesh_node(SpeciesLibrary.build_giant(int(rng.randi())), _leaf_mat))
	return root

# FORÊT DE CRISTAL : grappe de prismes translucides émissifs (5-15), tailles/inclinaisons variées.
func _make_crystal_forest(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hue := rng.randf()
	var tint := Color.from_hsv(hue, rng.randf_range(0.35, 0.6), 0.95)
	var n := rng.randi_range(6, 14)
	for i in n:
		var off := Vector3(rng.randf_range(-2.2, 2.2), 0.0, rng.randf_range(-2.2, 2.2))
		var ht := rng.randf_range(1.2, 3.6)
		var tilt := Vector3(rng.randf_range(-0.3, 0.3), rng.randf(), rng.randf_range(-0.3, 0.3))
		var up := Vector3(sin(tilt.x), cos(tilt.x) , sin(tilt.z)).normalized()
		var base := off
		var tip := off + up * ht
		var r := rng.randf_range(0.18, 0.36)
		_tube(st, tint.lerp(Color.WHITE, rng.randf_range(0.0, 0.3)), base, tip, r, 0.02, 6)  # prisme pointu
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.62)
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 0.7
	mat.roughness = 0.15
	root.add_child(_mesh_node(st.commit(), mat))
	return root

# SOURCE CHAUDE : bassin circulaire (anneau de pierre + disque d'eau bleuté) + vapeur lente diffuse.
func _make_hot_spring(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone := Color(0.48, 0.45, 0.42)
	var R := rng.randf_range(1.6, 2.6)
	_ring_wall(st, stone, R, R + 0.35, 0.0, 0.35, 16)          # margelle de pierre
	st.generate_normals()
	root.add_child(_mesh_node(st.commit(), _stone_mat))
	# Disque d'eau translucide bleu-vert.
	var water := SurfaceTool.new()
	water.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wcol := Color(0.20, 0.55, 0.62).lerp(Color(0.15, 0.40, 0.70), rng.randf())
	_disc(water, wcol, Vector3(0, 0.18, 0), Vector3.UP, R * 0.95, 18)
	water.generate_normals()
	var wmat := StandardMaterial3D.new()
	wmat.vertex_color_use_as_albedo = true
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.albedo_color = Color(1, 1, 1, 0.78)
	wmat.metallic = 0.2
	wmat.roughness = 0.1
	wmat.emission_enabled = true
	wmat.emission = wcol.darkened(0.3)
	wmat.emission_energy_multiplier = 0.15
	root.add_child(_mesh_node(water.commit(), wmat))
	var steam := _vapor(rng.randf_range(2.0, 3.0), R * 0.8, 18, Vector3(0, rng.randf_range(0.5, 0.9), 0), Color(0.95, 0.97, 1.0, 0.28))
	steam.position.y = 0.2
	root.add_child(steam)
	return root

# CASCADE GELÉE : colonne de glace verticale (grappe de stalactites tronconiques translucides).
func _make_frozen_waterfall(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ice := Color(0.80, 0.90, 0.98).lerp(Color(0.62, 0.80, 0.95), rng.randf())
	var top := rng.randf_range(5.0, 7.5)
	var n := rng.randi_range(5, 9)
	for i in n:
		var off := Vector3(rng.randf_range(-1.1, 1.1), 0.0, rng.randf_range(-0.5, 0.5))
		var h := top * rng.randf_range(0.55, 1.0)
		_tube(st, ice.lerp(Color.WHITE, rng.randf_range(0.0, 0.3)), off + Vector3(0, h, 0), off + Vector3(rng.randf_range(-0.2, 0.2), 0, 0), rng.randf_range(0.12, 0.22), rng.randf_range(0.25, 0.4), 6)
	# Petit monticule de glace à la base.
	_blob(st, ice, Vector3(0, 0.2, 0), 1.0, 0.4)
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.7)
	mat.roughness = 0.08
	mat.metallic = 0.1
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.85, 1.0)
	mat.emission_energy_multiplier = 0.1
	root.add_child(_mesh_node(st.commit(), mat))
	return root

# DUNE SINGULIÈRE : grosse formation de sable lisse isolée (dôme déformé, crête sculptée par le vent).
func _make_lone_dune(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sand := Color(0.78, 0.69, 0.46).lerp(Color(0.82, 0.74, 0.52), rng.randf())
	var ico := PlanetGenerator._build_icosphere(2)
	var verts: PackedVector3Array = ico.verts
	var idx: PackedInt32Array = ico.indices
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_PERLIN
	nz.seed = int(rng.randi())
	nz.frequency = 0.9
	var W := rng.randf_range(4.5, 7.0)
	var H := rng.randf_range(1.8, 3.0)
	var skew := rng.randf_range(0.2, 0.5)   # asymétrie (face au vent / sous le vent)
	var dpos := PackedVector3Array()
	dpos.resize(verts.size())
	for i in verts.size():
		var d := verts[i]
		var rr := 1.0 + 0.25 * nz.get_noise_3dv(d * 1.5)
		dpos[i] = Vector3(d.x * W * rr + d.z * skew * W * 0.2, maxf(d.y, 0.0) * H * rr, d.z * W * rr)
	for k in range(0, idx.size(), 3):
		var p0 := dpos[idx[k]]
		var p1 := dpos[idx[k + 1]]
		var p2 := dpos[idx[k + 2]]
		if p0.y + p1.y + p2.y < 0.02:
			continue   # ne garde que la calotte au-dessus du sol
		var sh := clampf(((p0.y + p1.y + p2.y) / 3.0) / H * 0.2, 0.0, 0.18)
		_tri(st, sand.lightened(sh), p0, p1, p2)
	st.generate_normals()
	root.add_child(_mesh_node(st.commit(), _sand_mat))
	return root

# CHEMINÉE DE FÉE / HOODOO : pilier fin et haut coiffé d'une roche plus large, bandes d'érosion.
func _make_hoodoo(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := rng.randi_range(1, 3)
	for c in n:
		var base := Vector3(rng.randf_range(-1.2, 1.2), 0.0, rng.randf_range(-1.2, 1.2)) if c > 0 else Vector3.ZERO
		var h := rng.randf_range(3.5, 6.0)
		var r := rng.randf_range(0.30, 0.5)
		# Pilier en bandes (érosion : couleur + rayon ondulés).
		var bands := 5
		for bi in bands:
			var y0 := base.y + h * bi / bands
			var seg := h / bands
			var rr := r * (0.8 + 0.3 * sin(bi * 1.7))
			var col := Color(0.62, 0.46, 0.34).lerp(Color(0.74, 0.58, 0.42), float(bi) / bands)
			_frustum(st, col, y0, seg, rr, rr * 0.92, 8, false)
		# Chapeau plus large.
		_frustum(st, Color(0.5, 0.42, 0.36), base.y + h, 0.5, r * 1.7, r * 1.5, 8, true)
	st.generate_normals()
	root.add_child(_mesh_node(st.commit(), _stone_mat))
	return root

# ORGUES BASALTIQUES : colonnes hexagonales serrées de hauteurs variées (chaussée des géants).
func _make_basalt_columns(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var basalt := Color(0.18, 0.18, 0.20).lerp(Color(0.26, 0.24, 0.23), rng.randf())
	var cell := 0.62
	var n := rng.randi_range(10, 16)
	for i in n:
		# Disposition en grille hexagonale compacte autour du centre.
		var q := i % 5 - 2
		var rrow := i / 5 - 1
		var px := q * cell + (rrow % 2) * cell * 0.5 + rng.randf_range(-0.06, 0.06)
		var pz := rrow * cell * 0.87 + rng.randf_range(-0.06, 0.06)
		var h := rng.randf_range(1.2, 3.8)
		var base := Vector3(px, 0.0, pz)
		var top := Vector3(px, h, pz)
		_tube(st, basalt.darkened(rng.randf_range(0.0, 0.12)), base, top, cell * 0.5, cell * 0.5, 6)
		_disc(st, basalt.lightened(0.05), top, Vector3.UP, cell * 0.5, 6)   # sommet hexagonal plat
	st.generate_normals()
	root.add_child(_mesh_node(st.commit(), _basalt_mat))
	return root

# BOSQUET BIOLUMINESCENT : groupe de plantes émissives (tiges + bulbes lumineux), visibles la nuit.
func _make_biolum_grove(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var stems := SurfaceTool.new()
	stems.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem_col := Color(0.10, 0.22, 0.18)
	var n := rng.randi_range(6, 10)
	var caps := []
	for i in n:
		var off := Vector3(rng.randf_range(-2.0, 2.0), 0.0, rng.randf_range(-2.0, 2.0))
		var h := rng.randf_range(0.6, 1.6)
		var bend := Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))
		var tip := off + Vector3(0, h, 0) + bend
		_tube(stems, stem_col, off + Vector3(0, 0.02, 0), tip, 0.04, 0.02, 4)
		caps.append(tip)
	stems.generate_normals()
	root.add_child(_mesh_node(stems.commit(), _leaf_mat))
	# Bulbes lumineux (émissifs) : matériau dédié (couleur seedée).
	var bulbs := SurfaceTool.new()
	bulbs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow := Color.from_hsv(rng.randf_range(0.35, 0.62), rng.randf_range(0.4, 0.7), 1.0)
	for tip in caps:
		_blob(bulbs, glow, tip, rng.randf_range(0.10, 0.18), 1.1)
	bulbs.generate_normals()
	var gmat := StandardMaterial3D.new()
	gmat.vertex_color_use_as_albedo = true
	gmat.emission_enabled = true
	gmat.emission = glow
	gmat.emission_energy_multiplier = 2.2
	root.add_child(_mesh_node(bulbs.commit(), gmat))
	return root

# ============================ ANCIENNES PRÉSENCES ============================

# MONOLITHE SOLITAIRE : grand bloc vertical ÉRODÉ en plusieurs segments (profil aminci + bruité +
# penché vers le haut), énigmatique. POI notable => nommé. Silhouette dressée, contemplative.
func _make_monolith(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone := Color(0.34, 0.33, 0.35).lerp(Color(0.45, 0.43, 0.42), rng.randf())
	var h := rng.randf_range(5.0, 7.5)
	var segs := 5
	var w0 := rng.randf_range(0.6, 0.95)
	var d0 := rng.randf_range(0.45, 0.7)
	var lean := Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.4, 0.4))   # penché (accentué en haut)
	var prev := _quad_ring(w0, d0, 0.0, Vector3.ZERO, rng, 0.0)
	for i in range(1, segs + 1):
		var t := float(i) / float(segs)
		var w := lerpf(w0, w0 * 0.6, t)
		var d := lerpf(d0, d0 * 0.55, t)
		var off := lean * (t * t)
		var ring := _quad_ring(w, d, h * t, Vector3(off.x, 0.0, off.z), rng, 0.07 * (1.0 - t))
		for k in 4:
			_quad(st, stone.darkened(0.04 * (k % 2)), prev[k], prev[(k + 1) % 4], ring[(k + 1) % 4], ring[k])
		prev = ring
	_quad(st, stone.lightened(0.06), prev[0], prev[1], prev[2], prev[3])   # sommet érodé
	st.generate_normals()
	root.add_child(_mesh_node(st.commit(), _stone_mat))
	return root

# 4 coins d'un anneau quadrilatère (section d'un prisme), avec érosion (léger bruit horizontal).
func _quad_ring(w: float, d: float, y: float, off: Vector3, rng: RandomNumberGenerator, jit: float) -> Array:
	return [
		Vector3(-w + rng.randf_range(-jit, jit), y, -d + rng.randf_range(-jit, jit)) + off,
		Vector3(w + rng.randf_range(-jit, jit), y, -d + rng.randf_range(-jit, jit)) + off,
		Vector3(w + rng.randf_range(-jit, jit), y, d + rng.randf_range(-jit, jit)) + off,
		Vector3(-w + rng.randf_range(-jit, jit), y, d + rng.randf_range(-jit, jit)) + off,
	]

# CERCLE DE PIERRES : 5-9 pierres dressées plus modestes, disposées en cercle.
func _make_stone_circle(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone := Color(0.40, 0.39, 0.38)
	var n := rng.randi_range(5, 9)
	var R := rng.randf_range(2.8, 4.2)
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.1, 0.1)
		var c := Vector3(cos(a) * R, 0, sin(a) * R)
		var h := rng.randf_range(1.6, 2.8)
		var w := rng.randf_range(0.3, 0.5)
		var lean := Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
		_standing_stone(st, stone.darkened(rng.randf_range(0.0, 0.1)), c, h, w, lean)
	st.generate_normals()
	root.add_child(_mesh_node(st.commit(), _stone_mat))
	return root

# AUTEL ABANDONNÉ : socle parallélépipédique en gradins, fissuré, partiellement enfoui/incliné.
func _make_altar(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone := Color(0.46, 0.44, 0.40).lerp(Color(0.38, 0.37, 0.36), rng.randf())
	var w := rng.randf_range(1.1, 1.6)
	# Gradins décroissants (légèrement décalés => usure).
	_box(st, stone.darkened(0.06), Vector3(0, 0.25, 0), Vector3(w, 0.5, w * 0.8))
	_box(st, stone, Vector3(rng.randf_range(-0.08, 0.08), 0.7, rng.randf_range(-0.08, 0.08)), Vector3(w * 0.7, 0.45, w * 0.55))
	_box(st, stone.lightened(0.04), Vector3(rng.randf_range(-0.06, 0.06), 1.02, 0), Vector3(w * 0.85, 0.18, w * 0.62))   # table
	st.generate_normals()
	var mi := _mesh_node(st.commit(), _stone_mat)
	# Légèrement incliné + enfoncé (abandon).
	mi.rotation = Vector3(rng.randf_range(-0.08, 0.08), rng.randf() * TAU, rng.randf_range(-0.06, 0.06))
	mi.position.y = -0.15
	root.add_child(mi)
	return root

# ARCHE EN RUINES : fragment d'arche architecturée BRISÉE (deux montants + amorce de linteau).
func _make_ruined_arch(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone := Color(0.52, 0.48, 0.42).lerp(Color(0.44, 0.41, 0.38), rng.randf())
	var span := rng.randf_range(2.4, 3.4)
	var hL := rng.randf_range(2.8, 3.6)
	var hR := hL * rng.randf_range(0.45, 0.8)   # un côté brisé plus bas (asymétrie = ruine)
	var pw := rng.randf_range(0.35, 0.55)
	_box(st, stone, Vector3(-span * 0.5, hL * 0.5, 0), Vector3(pw, hL, pw))           # montant gauche
	_box(st, stone.darkened(0.05), Vector3(span * 0.5, hR * 0.5, 0), Vector3(pw, hR, pw))  # montant droit (brisé)
	# Amorce de linteau côté gauche (saillie qui s'interrompt).
	var ll := span * rng.randf_range(0.3, 0.5)
	_box(st, stone.lightened(0.03), Vector3(-span * 0.5 + ll * 0.5, hL + pw * 0.5, 0), Vector3(ll, pw, pw))
	# Quelques blocs tombés au sol.
	for i in rng.randi_range(2, 4):
		var p := Vector3(rng.randf_range(-span * 0.5, span * 0.5), 0.12, rng.randf_range(-0.6, 0.6))
		_box(st, stone.darkened(0.08), p, Vector3(rng.randf_range(0.3, 0.6), 0.24, rng.randf_range(0.3, 0.5)))
	st.generate_normals()
	root.add_child(_mesh_node(st.commit(), _stone_mat))
	return root

# CAIRN : tas de pierres empilées en équilibre étrange (décroissantes vers le haut).
func _make_cairn(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone := Color(0.44, 0.42, 0.39)
	var n := rng.randi_range(5, 8)
	var y := 0.0
	for i in n:
		var t := float(i) / float(n)
		var r := lerpf(0.45, 0.14, t) * rng.randf_range(0.85, 1.1)
		var off := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12)) * (1.0 - t)
		_blob(st, stone.lightened(rng.randf_range(0.0, 0.08)), Vector3(off.x, y + r * 0.7, off.z), r, 0.7)
		y += r * 1.15
	st.generate_normals()
	root.add_child(_mesh_node(st.commit(), _stone_mat))
	return root

# BALISE ABANDONNÉE : petite tour cylindrique érodée, fonction perdue (PAS d'antenne moderne).
func _make_beacon(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone := Color(0.50, 0.47, 0.43).lerp(Color(0.42, 0.40, 0.40), rng.randf())
	var h := rng.randf_range(2.8, 4.2)
	_frustum(st, stone, 0.0, h, rng.randf_range(0.7, 0.95), rng.randf_range(0.5, 0.7), 10, true)   # fût conique
	# Couronne supérieure (rebord plus large), creuse (foyer éteint, fonction oubliée).
	_ring_wall(st, stone.darkened(0.08), 0.55, 0.78, h, h + 0.5, 10)
	st.generate_normals()
	root.add_child(_mesh_node(st.commit(), _stone_mat))
	return root

# ============================ Primitives ============================

func _mesh_node(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	return mi

# Vapeur GPU : jet vertical lent (geyser / source chaude). Couleur additive douce, plafonné.
func _vapor(height: float, radius: float, amount: int, vel: Vector3, color: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = vel.y * 0.7
	pm.initial_velocity_max = vel.y * 1.2
	pm.gravity = Vector3(0, -0.25, 0)             # monte puis retombe doucement
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	pm.damping_min = 0.1
	pm.damping_max = 0.4
	p.process_material = pm
	p.amount = amount
	p.lifetime = maxf(height / maxf(vel.y, 0.5), 2.0)
	p.draw_pass_1 = _vapor_quad()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = color
	p.material_override = mat
	return p

func _vapor_quad() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.2)
	return q

# Tronc de cône vertical (r1=0 => cône). y0 base, h hauteur, sides côtés, cap inférieur optionnel.
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
			_tri(st, color, Vector3(0, y0, 0), b1, b0)

# Tube tronconique entre p0 (r0) et p1 (r1), 'sides' côtés (axe quelconque). Faces latérales seules.
func _tube(st: SurfaceTool, color: Color, p0: Vector3, p1: Vector3, r0: float, r1: float, sides: int) -> void:
	var axis := p1 - p0
	if axis.length() < 0.0001:
		return
	axis = axis.normalized()
	var ref := Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT
	var u := axis.cross(ref).normalized()
	var v := axis.cross(u).normalized()
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		_tri(st, color, p0 + d0 * r0, p1 + d0 * r1, p0 + d1 * r0)
		_tri(st, color, p0 + d1 * r0, p1 + d0 * r1, p1 + d1 * r1)

# Disque plein (fan) centré, normale 'nrm', rayon, 'sides' côtés.
func _disc(st: SurfaceTool, color: Color, center: Vector3, nrm: Vector3, radius: float, sides: int) -> void:
	var ref := Vector3.RIGHT if absf(nrm.y) > 0.95 else Vector3.UP
	var u := nrm.cross(ref).normalized()
	var v := nrm.cross(u).normalized()
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		_tri(st, color, center, center + (u * cos(a0) + v * sin(a0)) * radius, center + (u * cos(a1) + v * sin(a1)) * radius)

# Anneau-mur (cylindre creux à double paroi) entre rayons rin/rout, de y0 à y1.
func _ring_wall(st: SurfaceTool, color: Color, rin: float, rout: float, y0: float, y1: float, sides: int) -> void:
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		# Paroi externe + interne + dessus.
		_quad(st, color, d0 * rout + Vector3(0, y0, 0), d1 * rout + Vector3(0, y0, 0), d1 * rout + Vector3(0, y1, 0), d0 * rout + Vector3(0, y1, 0))
		_quad(st, color.darkened(0.1), d1 * rin + Vector3(0, y0, 0), d0 * rin + Vector3(0, y0, 0), d0 * rin + Vector3(0, y1, 0), d1 * rin + Vector3(0, y1, 0))
		_quad(st, color.lightened(0.05), d0 * rin + Vector3(0, y1, 0), d0 * rout + Vector3(0, y1, 0), d1 * rout + Vector3(0, y1, 0), d1 * rin + Vector3(0, y1, 0))

# Pierre dressée (petit prisme penché) pour le cercle de pierres.
func _standing_stone(st: SurfaceTool, color: Color, c: Vector3, h: float, w: float, lean: Vector3) -> void:
	var base := [
		c + Vector3(-w, 0, -w * 0.7), c + Vector3(w, 0, -w * 0.7),
		c + Vector3(w, 0, w * 0.7), c + Vector3(-w, 0, w * 0.7),
	]
	var top := [
		c + Vector3(-w * 0.8, h, -w * 0.5) + lean, c + Vector3(w * 0.8, h, -w * 0.5) + lean,
		c + Vector3(w * 0.8, h, w * 0.5) + lean, c + Vector3(-w * 0.8, h, w * 0.5) + lean,
	]
	for k in 4:
		_quad(st, color.darkened(0.04 * (k % 2)), base[k], base[(k + 1) % 4], top[(k + 1) % 4], top[k])
	_quad(st, color.lightened(0.04), top[0], top[1], top[2], top[3])

# Boîte axis-aligned centrée (center) de dimensions 'size' (largeur/hauteur/profondeur).
func _box(st: SurfaceTool, color: Color, center: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var p := [
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(h.x, -h.y, h.z), center + Vector3(-h.x, -h.y, h.z),
		center + Vector3(-h.x, h.y, -h.z), center + Vector3(h.x, h.y, -h.z),
		center + Vector3(h.x, h.y, h.z), center + Vector3(-h.x, h.y, h.z),
	]
	_quad(st, color, p[0], p[1], p[2], p[3])   # bas
	_quad(st, color.lightened(0.05), p[7], p[6], p[5], p[4])   # haut
	_quad(st, color.darkened(0.04), p[0], p[4], p[5], p[1])
	_quad(st, color.darkened(0.04), p[1], p[5], p[6], p[2])
	_quad(st, color.darkened(0.04), p[2], p[6], p[7], p[3])
	_quad(st, color.darkened(0.04), p[3], p[7], p[4], p[0])

# Blob (icosphère subdiv 0 déformée), faces plates.
func _blob(st: SurfaceTool, color: Color, center: Vector3, radius: float, yscale: float) -> void:
	var ico := PlanetGenerator._build_icosphere(0)
	var verts: PackedVector3Array = ico.verts
	var idx: PackedInt32Array = ico.indices
	for k in range(0, idx.size(), 3):
		var p0 := center + Vector3(verts[idx[k]].x * radius, verts[idx[k]].y * radius * yscale, verts[idx[k]].z * radius)
		var p1 := center + Vector3(verts[idx[k + 1]].x * radius, verts[idx[k + 1]].y * radius * yscale, verts[idx[k + 1]].z * radius)
		var p2 := center + Vector3(verts[idx[k + 2]].x * radius, verts[idx[k + 2]].y * radius * yscale, verts[idx[k + 2]].z * radius)
		_tri(st, color, p0, p1, p2)

func _tri(st: SurfaceTool, color: Color, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.set_color(color); st.add_vertex(a)
	st.set_color(color); st.add_vertex(b)
	st.set_color(color); st.add_vertex(c)

func _quad(st: SurfaceTool, color: Color, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, color, a, b, c)
	_tri(st, color, a, c, d)
