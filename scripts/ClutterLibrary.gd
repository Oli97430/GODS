class_name ClutterLibrary
extends RefCounted
## Phase 20 — COUCHE B : bibliothèque de petits objets au sol (« clutter »), générés UNE fois au
## démarrage et PARTAGÉS par tous les chunks via MultiMesh (jamais un mesh par chunk). Calque exact
## de VegetationLibrary (phase 8) : 100% par code, couleurs bakées en couleurs de vertices, matériaux
## simples (mobile-friendly), déterministe (seeds internes fixes).
##
## 5 catégories obligatoires (ton organique/mélancolique, jamais agressif) :
##   CAILLOUX (icosphères bruitées), BRINDILLES (tiges pliées), OSSEMENTS (formes longues bombées,
##   os stylisés — PAS de crâne), FEUILLES/PÉTALES (quads minces colorés), COQUILLAGES (cônes spiralés).
## La variété vient de : variantes ici + échelle/lacet/inclinaison par instance (au semis) + choix de
## variante selon le biome (au semis). Tout est TRÈS bas-poly (beaucoup d'instances dans un anneau serré).

enum Category { PEBBLE, TWIG, BONE, LEAF, SHELL }

# Index de variante = index de mesh dans _meshes (ne pas réordonner sans raison).
const V_PEBBLE_A := 0     # caillou clair anguleux
const V_PEBBLE_B := 1     # caillou sombre plus plat
const V_TWIG_A := 2       # brindille pliée simple
const V_TWIG_B := 3       # brindille fourchue
const V_BONE_A := 4       # os long (tibia stylisé)
const V_BONE_B := 5       # os courbé (côte stylisée)
const V_LEAF_DRY := 6     # feuille morte (brun/ocre)
const V_LEAF_FRESH := 7   # pétale / feuille colorée
const V_SHELL := 8        # coquillage spiralé
const VARIANT_COUNT := 9

const PEBBLE_VARIANTS: Array[int] = [V_PEBBLE_A, V_PEBBLE_B]
const TWIG_VARIANTS: Array[int] = [V_TWIG_A, V_TWIG_B]
const BONE_VARIANTS: Array[int] = [V_BONE_A, V_BONE_B]
const LEAF_VARIANTS: Array[int] = [V_LEAF_DRY, V_LEAF_FRESH]
const SHELL_VARIANTS: Array[int] = [V_SHELL]

var _meshes: Array[Mesh] = []
var _solid_mat: StandardMaterial3D   # cailloux/brindilles/os/coquillages : opaque, 1 face, vertex color
var _leaf_mat: StandardMaterial3D    # feuilles : double face (quads minces visibles des deux côtés)

func _init() -> void:
	_build()

# Mesh partagé d'une variante (assigné aux MultiMesh des chunks).
func mesh_for(variant: int) -> Mesh:
	return _meshes[variant]

func material_for(variant: int) -> Material:
	return _leaf_mat if variant in LEAF_VARIANTS else _solid_mat

func category_of(variant: int) -> int:
	if variant in PEBBLE_VARIANTS:
		return Category.PEBBLE
	if variant in TWIG_VARIANTS:
		return Category.TWIG
	if variant in BONE_VARIANTS:
		return Category.BONE
	if variant in LEAF_VARIANTS:
		return Category.LEAF
	return Category.SHELL

# Nombre de triangles d'une variante (diagnostic budget).
func tri_count(variant: int) -> int:
	var m := _meshes[variant]
	if m == null or m.get_surface_count() == 0:
		return 0
	return (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3

# --- Construction (une fois) ---

func _build() -> void:
	_solid_mat = StandardMaterial3D.new()
	_solid_mat.vertex_color_use_as_albedo = true
	_solid_mat.roughness = 1.0
	_leaf_mat = StandardMaterial3D.new()
	_leaf_mat.vertex_color_use_as_albedo = true
	_leaf_mat.roughness = 1.0
	_leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # feuille mince visible des deux faces

	_meshes.resize(VARIANT_COUNT)
	_meshes[V_PEBBLE_A] = _make_pebble(Color(0.52, 0.49, 0.44), 311, 0.55)
	_meshes[V_PEBBLE_B] = _make_pebble(Color(0.34, 0.31, 0.29), 733, 0.42)
	_meshes[V_TWIG_A] = _make_twig(Color(0.31, 0.22, 0.13), 1201, false)
	_meshes[V_TWIG_B] = _make_twig(Color(0.27, 0.19, 0.12), 1607, true)
	_meshes[V_BONE_A] = _make_bone(Color(0.85, 0.83, 0.76), false)   # tibia : droit, bombé aux bouts
	_meshes[V_BONE_B] = _make_bone(Color(0.82, 0.80, 0.72), true)    # côte : arquée
	_meshes[V_LEAF_DRY] = _make_leaf(Color(0.55, 0.40, 0.18))        # feuille morte ocre
	_meshes[V_LEAF_FRESH] = _make_leaf(Color(0.74, 0.34, 0.46))      # pétale coloré
	_meshes[V_SHELL] = _make_shell(Color(0.88, 0.83, 0.72))          # coquillage spiralé crème

# --- Générateurs par catégorie ---

# Caillou : icosphère subdiv 0 (20 tris) déformée par bruit, aplatie, base ~ y=0 (posé au sol).
func _make_pebble(base_color: Color, noise_seed: int, flatten: float) -> ArrayMesh:
	var ico := PlanetGenerator._build_icosphere(0)
	var verts: PackedVector3Array = ico.verts
	var idx: PackedInt32Array = ico.indices
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.seed = noise_seed
	n.frequency = 1.7
	var radius := 0.12
	var dpos := PackedVector3Array()
	dpos.resize(verts.size())
	for i in verts.size():
		var d := verts[i]
		var r := radius * (1.0 + 0.45 * n.get_noise_3dv(d * 2.3))
		dpos[i] = Vector3(d.x * r, (d.y * flatten + flatten) * r, d.z * r)   # aplati + base ~0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(0, idx.size(), 3):
		var p0 := dpos[idx[k]]
		var p1 := dpos[idx[k + 1]]
		var p2 := dpos[idx[k + 2]]
		var shade := clampf(((p0.y + p1.y + p2.y) / 3.0) * 1.2, -0.08, 0.16)
		_tri(st, base_color.lightened(maxf(shade, 0.0)).darkened(maxf(-shade, 0.0)), p0, p1, p2)
	st.generate_normals()
	return st.commit()

# Brindille : 2-3 segments de tige pliés (tube tronconique), COUCHÉE le long de X (base ~ y=0).
# Fourchue => petite branche secondaire. Très bas-poly (4 côtés).
func _make_twig(color: Color, seed_val: int, forked: bool) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := Vector3(-0.18, 0.012, 0.0)
	var dir := Vector3(1.0, 0.0, 0.0)
	var r := 0.018
	var segs := 3
	for s in segs:
		var seg_len := rng.randf_range(0.10, 0.14)
		var nxt := p + dir * seg_len
		nxt.y = maxf(nxt.y + rng.randf_range(-0.01, 0.02), 0.008)   # léger pli, reste au sol
		var r2 := r * 0.78
		_tube(st, color.darkened(0.05 * s), p, nxt, r, r2, 4)
		if forked and s == 1:
			var br := nxt + Vector3(rng.randf_range(0.03, 0.06), 0.02, rng.randf_range(0.05, 0.09))
			_tube(st, color, nxt, br, r2, r2 * 0.5, 4)
		p = nxt
		dir = (dir + Vector3(0.0, 0.0, rng.randf_range(-0.5, 0.5))).normalized()
		r = r2
	st.generate_normals()
	return st.commit()

# Ossement stylisé MÉLANCOLIQUE (PAS de crâne) : long fût bombé aux extrémités (tibia), ou arqué
# (côte). Blanc cassé. COUCHÉ le long de X, base ~ y=0. Organique, jamais sanglant.
func _make_bone(color: Color, curved: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := 0.20
	var shaft_r := 0.026
	var knob_r := 0.05
	var arc := 0.06 if curved else 0.0
	# Fût : 4 segments suivant un léger arc (côte) pour rester lisse, COUCHÉ (y ~ knob_r).
	var steps := 4
	var prev := Vector3.ZERO
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var x := lerpf(-half, half, t)
		var y := knob_r + sin(t * PI) * arc
		var pt := Vector3(x, y, 0.0)
		if i > 0:
			_tube(st, color, prev, pt, shaft_r, shaft_r, 5)
		prev = pt
	# Bouts bombés (épiphyses) : deux blobs aux extrémités.
	_blob(st, color.lightened(0.04), Vector3(-half, knob_r, 0.0), knob_r, 0.9)
	_blob(st, color.lightened(0.04), Vector3(half, knob_r + sin(PI) * arc, 0.0), knob_r, 0.9)
	st.generate_normals()
	return st.commit()

# Feuille / pétale : quad mince légèrement gondolé, posé ~à plat (base y~0), double face.
# Dégradé nervure (sombre) -> bord (clair). Colorée selon la variante (biome au semis).
func _make_leaf(color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var l := 0.11   # longueur (axe X)
	var w := 0.06   # demi-largeur (axe Z)
	var vein := color.darkened(0.25)
	var edge := color.lightened(0.12)
	# 2 triangles formant une feuille en losange, très légèrement relevée (gondolage).
	var a := Vector3(-l, 0.004, 0.0)            # pétiole
	var b := Vector3(0.0, 0.018, -w)           # bord gauche relevé
	var c := Vector3(l, 0.006, 0.0)            # pointe
	var d := Vector3(0.0, 0.018, w)            # bord droit relevé
	_tri_c(st, a, b, c, vein, edge, vein)
	_tri_c(st, a, c, d, vein, vein, edge)
	st.generate_normals()
	return st.commit()

# Coquillage : cône SPIRALÉ (tube tronconique enroulé en hélice montante et resserrée). Évoque un
# gastéropode/ammonite. Posé sur le flanc (on l'inclinera au semis). Crème nacré.
func _make_shell(color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var turns := 2.2
	var steps := 14
	var r0 := 0.085      # rayon de l'enroulement (large -> serré)
	var tube0 := 0.045   # épaisseur du tube (large -> fine)
	var rise := 0.085
	var prev := Vector3.ZERO
	var prev_tr := 0.0
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var ang := t * turns * TAU
		var rr := r0 * (1.0 - 0.85 * t)
		var pt := Vector3(cos(ang) * rr, t * rise, sin(ang) * rr)
		var tr := tube0 * (1.0 - 0.9 * t)
		if i > 0:
			_tube(st, color.darkened(0.10 * t), prev, pt, prev_tr, tr, 6)
		prev = pt
		prev_tr = tr
	st.generate_normals()
	return st.commit()

# --- Primitives bas niveau ---

# Tube tronconique entre p0 (rayon r0) et p1 (rayon r1), 'sides' côtés. Repère perpendiculaire à
# l'axe choisi automatiquement (robuste à l'orientation). Faces latérales seulement (bouts ouverts :
# masqués par les blobs/segments adjacents).
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
		var b0 := p0 + d0 * r0
		var b1 := p0 + d1 * r0
		var t0 := p1 + d0 * r1
		var t1 := p1 + d1 * r1
		_tri(st, color, b0, t0, b1)
		_tri(st, color, b1, t0, t1)

# Blob (icosphère subdiv 0 déformée), faces plates. Pour les bouts d'os bombés.
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

# Triangle à couleur par sommet (dégradés nervure/bord des feuilles).
func _tri_c(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca); st.add_vertex(a)
	st.set_color(cb); st.add_vertex(b)
	st.set_color(cc); st.add_vertex(c)
