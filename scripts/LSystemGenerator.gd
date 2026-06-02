class_name LSystemGenerator
extends RefCounted
## Phase 24 — moteur L-system GÉNÉRIQUE (indépendant de l'espèce), 100% par code, DÉTERMINISTE.
## Deux étapes :
##   1. expand(axiom, rules, iterations, seed) -> chaîne de symboles (réécriture stochastique seedée)
##   2. to_mesh(chaîne, params) -> ArrayMesh unique (tortue 3D : segments coniques + amas de feuilles)
## Sortie = UN ArrayMesh à COULEURS DE VERTICES (bois + feuilles) => se branche tel quel sur le
## matériau de vent partagé de VegetationLibrary (double-face). Base aux pieds (y≈0), pousse vers +Y.
##
## Symboles de tortue (repère basis : x=gauche, y=heading/pousse, z=haut) :
##   F  segment conique vers l'avant (heading) + avance ; rétrécit longueur & rayon
##   L  amas de feuilles à la position courante
##   +/- lacet  (rotation autour de z)      &/^ tangage (rotation autour de x)      /\ roulis (autour de y)
##   [ ] empile / dépile l'état (branche)    !  réduit le rayon courant (tronc->brindille)
##
## rules : { "F": [[poids, "remplacement"], ...], ... }. Symboles sans règle = inchangés (constants).

const MAX_SEGMENTS := 700   # plafond de segments 'F' : au-delà, on garde l'itération précédente (auto-réduction)

# Styles d'amas de feuilles (cf. _add_leaves).
const LEAF_BLOB := 0     # amas rond (canopée feuillue)
const LEAF_NEEDLE := 1   # touffe d'aiguilles retombante (conifère)
const LEAF_FROND := 2    # fronde allongée (palmier / tropical)

# --- 1. Expansion (réécriture) ---

# Applique les règles `iterations` fois depuis `axiom`. RNG seedé => même (rules, seed) = même chaîne.
# Auto-réduction : si une itération dépasse MAX_SEGMENTS segments 'F', on s'arrête à l'itération précédente.
static func expand(axiom: String, rules: Dictionary, iterations: int, seed_val: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var s := axiom
	for _it in iterations:
		var next := ""
		for ch in s:
			if rules.has(ch):
				next += _pick(rules[ch], rng)
			else:
				next += ch
		if next.count("F") > MAX_SEGMENTS:
			return s   # explosion : on s'en tient à l'itération précédente (silencieux côté lib)
		s = next
	return s

# Choix pondéré parmi options = [[poids, "remplacement"], ...].
static func _pick(options: Array, rng: RandomNumberGenerator) -> String:
	if options.size() == 1:
		return options[0][1]
	var total := 0.0
	for o in options:
		total += o[0]
	var r := rng.randf() * total
	for o in options:
		r -= o[0]
		if r <= 0.0:
			return o[1]
	return options[options.size() - 1][1]

# Nombre de segments dessinés (diagnostic budget).
static func segment_count(lstring: String) -> int:
	return lstring.count("F")

# --- 2. Interprétation tortue -> mesh ---

# params (avec valeurs par défaut) :
#   length 0.5, length_falloff 0.86, angle 28 (deg), radius 0.07, radius_falloff 0.80, taper 0.85,
#   sides 5, wood_color, leaf_color, leaf_size 0.32, leaf_style LEAF_BLOB, tropism 0.0 (courbure gravité)
static func to_mesh(lstring: String, params: Dictionary) -> ArrayMesh:
	var length: float = params.get("length", 0.5)
	var len_fall: float = params.get("length_falloff", 0.86)
	var angle: float = deg_to_rad(params.get("angle", 28.0))
	var radius: float = params.get("radius", 0.07)
	var rad_fall: float = params.get("radius_falloff", 0.80)
	var taper: float = params.get("taper", 0.85)
	var sides: int = params.get("sides", 5)
	var wood: Color = params.get("wood_color", Color(0.32, 0.23, 0.15))
	var leaf: Color = params.get("leaf_color", Color(0.22, 0.43, 0.18))
	var leaf_size: float = params.get("leaf_size", 0.32)
	var leaf_style: int = params.get("leaf_style", LEAF_BLOB)
	var tropism: float = params.get("tropism", 0.0)   # >0 : les branches retombent (gravité), <0 : se redressent

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# État tortue : position, orientation, longueur & rayon courants. Pile pour [ ].
	var pos := Vector3.ZERO
	var basis := Basis.IDENTITY   # heading initial = +Y (pousse vers le haut)
	var cur_len := length
	var cur_rad := radius
	var stack: Array = []

	for ch in lstring:
		match ch:
			"F":
				var head := basis.y
				# Tropisme : infléchit le heading vers le bas (gravité) avant d'avancer.
				if tropism != 0.0:
					head = (head + Vector3.DOWN * tropism).normalized()
				var p1 := pos + head * cur_len
				_add_segment(st, pos, p1, cur_rad, cur_rad * taper, sides, wood)
				pos = p1
				cur_len *= len_fall
				cur_rad *= rad_fall
			"L":
				_add_leaves(st, pos, basis, leaf, leaf_size, leaf_style)
			"!":
				cur_rad *= 0.72   # rétrécissement explicite du rayon (tronc -> brindille)
			"+":
				basis = basis.rotated(basis.z.normalized(), angle)
			"-":
				basis = basis.rotated(basis.z.normalized(), -angle)
			"&":
				basis = basis.rotated(basis.x.normalized(), angle)
			"^":
				basis = basis.rotated(basis.x.normalized(), -angle)
			"/":
				basis = basis.rotated(basis.y.normalized(), angle)
			"\\":
				basis = basis.rotated(basis.y.normalized(), -angle)
			"[":
				stack.push_back([pos, basis, cur_len, cur_rad])
			"]":
				if not stack.is_empty():
					var s0: Array = stack.pop_back()
					pos = s0[0]
					basis = s0[1]
					cur_len = s0[2]
					cur_rad = s0[3]

	st.generate_normals()
	return st.commit()

# Segment conique OUVERT (sans capuchons : bouché par le segment suivant / les feuilles). Faces sortantes.
static func _add_segment(st: SurfaceTool, p0: Vector3, p1: Vector3, r0: float, r1: float, sides: int, col: Color) -> void:
	var axis := p1 - p0
	var seg_len := axis.length()
	if seg_len < 1e-5:
		return
	axis /= seg_len
	# Base perpendiculaire stable à l'axe du segment.
	var ref := Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT
	var u := ref.cross(axis).normalized()
	var v := axis.cross(u).normalized()
	st.set_color(col)
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		var b0 := p0 + d0 * r0
		var b1 := p0 + d1 * r0
		var t0 := p1 + d0 * r1
		var t1 := p1 + d1 * r1
		st.add_vertex(b0); st.add_vertex(t0); st.add_vertex(b1)   # winding sortant (cf. VegetationLibrary._frustum)
		st.add_vertex(b1); st.add_vertex(t0); st.add_vertex(t1)

# Amas de feuilles selon le style. Couleurs de vertices = leaf (teintées par espèce).
static func _add_leaves(st: SurfaceTool, pos: Vector3, basis: Basis, col: Color, size: float, style: int) -> void:
	match style:
		LEAF_NEEDLE:
			_leaf_needle(st, pos, basis, col, size)
		LEAF_FROND:
			_leaf_frond(st, pos, basis, col, size)
		_:
			_leaf_blob(st, pos, col, size)

# Amas rond : octaèdre légèrement aplati (8 tris). Canopée feuillue.
static func _leaf_blob(st: SurfaceTool, c: Vector3, col: Color, s: float) -> void:
	st.set_color(col)
	var top := c + Vector3(0, s, 0)
	var bot := c + Vector3(0, -s * 0.55, 0)
	var ring := [c + Vector3(s, 0, 0), c + Vector3(0, 0, s), c + Vector3(-s, 0, 0), c + Vector3(0, 0, -s)]
	for i in 4:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % 4]
		st.add_vertex(top); st.add_vertex(a); st.add_vertex(b)
		st.add_vertex(bot); st.add_vertex(b); st.add_vertex(a)

# Touffe d'aiguilles : petit éventail retombant le long de la branche (conifère). 4 tris fins.
static func _leaf_needle(st: SurfaceTool, c: Vector3, basis: Basis, col: Color, s: float) -> void:
	st.set_color(col)
	var droop := (basis.y * 0.3 + Vector3.DOWN * 0.7).normalized() * s * 1.6   # retombe vers le bas
	for d in [basis.x, basis.z, -basis.x, -basis.z]:
		var lat: Vector3 = d * s * 0.18
		st.add_vertex(c + lat)
		st.add_vertex(c - lat)
		st.add_vertex(c + droop + (d as Vector3) * s * 0.25)

# Fronde : bande de quads le long du heading, légèrement retombante (palmier / fougère). ~8 tris.
static func _leaf_frond(st: SurfaceTool, c: Vector3, basis: Basis, col: Color, s: float) -> void:
	st.set_color(col)
	var fwd := basis.y
	var side := basis.x
	var segs := 4
	var prev := c
	var prev_w := s * 0.34
	for k in range(1, segs + 1):
		var t := float(k) / float(segs)
		var droop := Vector3.DOWN * t * t * s * 1.1   # retombée croissante vers la pointe
		var p := c + fwd * (t * s * 2.2) + droop
		var wdt := (1.0 - t) * s * 0.34
		st.add_vertex(prev + side * prev_w); st.add_vertex(p + side * wdt); st.add_vertex(p - side * wdt)
		st.add_vertex(prev + side * prev_w); st.add_vertex(p - side * wdt); st.add_vertex(prev - side * prev_w)
		prev = p
		prev_w = wdt
