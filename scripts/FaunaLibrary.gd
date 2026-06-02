class_name FaunaLibrary
extends RefCounted
## Bibliothèque de FAUNE procédurale (phase 19) — 100 % code, ZÉRO asset, ZÉRO skinning.
## Génère les MESHES DE PARTIES (corps / tête / patte) d'une créature à partir de PARAMÈTRES
## d'espèce (proportions + palette), via SurfaceTool + primitives low-poly + couleurs de vertices.
##
## Une créature n'est PAS un mesh unique : c'est un assemblage de nodes (corps, tête, N pattes)
## que Creature.gd positionne/oriente CHAQUE FRAME (animation procédurale, pas de Skeleton3D).
## FaunaLibrary fournit donc, pour une espèce : les 3 meshes de parties + les POINTS D'ANCRAGE
## (hanches, base du cou) + la hauteur de repos (corps au-dessus du sol, pattes touchant le sol).
##
## 3 archétypes imposés : QUADRUPÈDE (corps horizontal, 4 pattes), BIPÈDE (torse dressé, 2 pattes),
## HEXAPODE (corps horizontal allongé, 6 pattes). Déterministe : mêmes paramètres => mêmes meshes.
## Les meshes d'une espèce sont mis en CACHE (réutilisés par toutes ses instances ; un node par
## instance, mais meshes partagés).

enum Archetype { QUADRUPED, BIPED, HEXAPOD }

# Nombre de pattes par archétype.
const LEG_COUNT := {
	Archetype.QUADRUPED: 4,
	Archetype.BIPED: 2,
	Archetype.HEXAPOD: 6,
}

var _material: StandardMaterial3D   # partagé : couleur de vertex = albédo (palette bakée par espèce)
var _cache := {}                    # clé espèce -> Dictionary de parties (meshes + ancres)

func _init() -> void:
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0

# Matériau partagé par toutes les parties (la couleur vient des vertex colors bakées).
func material() -> Material:
	return _material

func leg_count(archetype: int) -> int:
	return LEG_COUNT.get(archetype, 4)

# Paramètres d'exemple d'un archétype (pour la scène de test de l'étape 1).
func example_params(archetype: int) -> Dictionary:
	match archetype:
		Archetype.BIPED:
			return make_params(archetype, 0.5, 1.0, 0.5, 0.9, 0.11, 0.42, Color(0.55, 0.42, 0.30))
		Archetype.HEXAPOD:
			return make_params(archetype, 1.8, 0.45, 0.6, 0.5, 0.07, 0.32, Color(0.30, 0.42, 0.34))
		_:
			return make_params(archetype, 1.4, 0.6, 0.7, 0.7, 0.10, 0.40, Color(0.52, 0.40, 0.26))

# Construit (ou récupère en cache) les parties d'une espèce. 'key' = identifiant stable d'espèce.
# Renvoie { body, head, leg : ArrayMesh ; leg_anchors : Array[Vector3] ; head_anchor : Vector3 ;
#           stand_height : float ; leg_length : float }.
func species_parts(key: int, params: Dictionary) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	var parts := _build_parts(params)
	_cache[key] = parts
	return parts

# Schéma de paramètres d'une espèce (utilisé par PlanetFaunaRoster). PUBLIC + déterministe.
func make_params(archetype: int, body_len: float, body_h: float, body_w: float, leg_len: float, leg_r: float, head: float, color: Color) -> Dictionary:
	return {
		"archetype": archetype,
		"body_length": body_len,   # le long de l'axe de marche (-Z = avant)
		"body_height": body_h,
		"body_width": body_w,
		"leg_length": leg_len,
		"leg_radius": leg_r,
		"head_size": head,
		"color": color,
		"belly": color.darkened(0.45),
	}

# --- Construction des parties d'une espèce ---

func _build_parts(p: Dictionary) -> Dictionary:
	var archetype: int = p.archetype
	var biped := archetype == Archetype.BIPED
	var legs := leg_count(archetype)
	var leg_len: float = p.leg_length
	var bl: float = p.body_length
	var bh: float = p.body_height
	var bw: float = p.body_width
	var col: Color = p.color
	var belly: Color = p.belly

	var body := _make_body(bl, bh, bw, col, belly, biped)
	var head := _make_head(p.head_size, col.lightened(0.06))
	var leg := _make_leg(leg_len, p.leg_radius, col.darkened(0.2))

	# Points d'ancrage des hanches (espace LOCAL du corps, dont le centre est à l'origine).
	var anchors: Array[Vector3] = []
	if biped:
		# 2 pattes sous le torse (torse dressé : corps "haut", pattes en bas).
		anchors.append(Vector3(-bw * 0.32, -bh * 0.45, 0.0))
		anchors.append(Vector3(bw * 0.32, -bh * 0.45, 0.0))
	else:
		# Pattes réparties le long du corps horizontal (paires avant->arrière).
		var pairs := legs / 2
		for i in pairs:
			var t := 0.0 if pairs == 1 else (float(i) / float(pairs - 1))   # 0 = avant, 1 = arrière
			var z := lerpf(-bl * 0.38, bl * 0.38, t)
			anchors.append(Vector3(-bw * 0.5, -bh * 0.4, z))
			anchors.append(Vector3(bw * 0.5, -bh * 0.4, z))

	# Base du cou : à l'avant (-Z) pour quadrupède/hexapode, au sommet pour bipède.
	var head_anchor := Vector3(0.0, bh * 0.55, 0.0) if biped else Vector3(0.0, bh * 0.25, -bl * 0.5)

	# Hauteur de repos : le corps flotte à ~leg_len au-dessus du sol (pattes touchant le sol).
	var stand := leg_len + bh * (0.5 if biped else 0.4)

	return {
		"body": body, "head": head, "leg": leg,
		"leg_anchors": anchors, "head_anchor": head_anchor,
		"stand_height": stand, "leg_length": leg_len,
	}

# Corps : ellipsoïde low-poly (icosphère subdiv 1 étirée). Dos plus clair, ventre plus sombre
# (dégradé vertical via vertex colors). Bipède = étiré en hauteur, sinon le long de l'avant (-Z).
func _make_body(length: float, height: float, width: float, top: Color, belly: Color, biped: bool) -> ArrayMesh:
	var ico := PlanetGenerator._build_icosphere(1)
	var verts: PackedVector3Array = ico.verts
	var idx: PackedInt32Array = ico.indices
	var sx := width * 0.5
	var sy := height * 0.5
	var sz := length * 0.5
	if biped:
		sy = height * 0.5
		sz = width * 0.5   # torse à peu près cylindrique vertical
	var dpos := PackedVector3Array()
	dpos.resize(verts.size())
	for i in verts.size():
		var d := verts[i]
		dpos[i] = Vector3(d.x * sx, d.y * sy, d.z * sz)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(0, idx.size(), 3):
		var p0 := dpos[idx[k]]
		var p1 := dpos[idx[k + 1]]
		var p2 := dpos[idx[k + 2]]
		var ay := ((p0.y + p1.y + p2.y) / 3.0) / maxf(sy, 0.001)   # -1 (ventre) -> +1 (dos)
		var c := belly.lerp(top, clampf(ay * 0.5 + 0.5, 0.0, 1.0))
		_tri(st, c, p0, p1, p2)
	st.generate_normals()
	return st.commit()

# Tête : petit blob (icosphère subdiv 0), centre à l'origine (Creature la place à l'ancre du cou).
func _make_head(size: float, color: Color) -> ArrayMesh:
	var ico := PlanetGenerator._build_icosphere(0)
	var verts: PackedVector3Array = ico.verts
	var idx: PackedInt32Array = ico.indices
	var r := size * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(0, idx.size(), 3):
		# museau légèrement allongé vers l'avant (-Z).
		var p0 := _muzzle(verts[idx[k]], r)
		var p1 := _muzzle(verts[idx[k + 1]], r)
		var p2 := _muzzle(verts[idx[k + 2]], r)
		_tri(st, color, p0, p1, p2)
	st.generate_normals()
	return st.commit()

func _muzzle(d: Vector3, r: float) -> Vector3:
	var z := d.z * r * (1.35 if d.z < 0.0 else 1.0)   # allonge vers l'avant
	return Vector3(d.x * r, d.y * r, z)

# Patte : tronc de cône fin, HANCHE à y=0, PIED à y=-leg_len (pend vers le bas). Creature la
# fait pivoter autour de la hanche pour la marche.
func _make_leg(leg_len: float, radius: float, color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 5
	var r0 := radius
	var r1 := radius * 0.6
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var top0 := Vector3(d0.x * r0, 0.0, d0.z * r0)
		var top1 := Vector3(d1.x * r0, 0.0, d1.z * r0)
		var bot0 := Vector3(d0.x * r1, -leg_len, d0.z * r1)
		var bot1 := Vector3(d1.x * r1, -leg_len, d1.z * r1)
		_tri(st, color, top0, bot0, top1)
		_tri(st, color, top1, bot0, bot1)
	# Petit "pied" (cap) au bout.
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var b0 := Vector3(cos(a0) * r1, -leg_len, sin(a0) * r1)
		var b1 := Vector3(cos(a1) * r1, -leg_len, sin(a1) * r1)
		_tri(st, color.darkened(0.2), Vector3(0, -leg_len, 0), b0, b1)
	st.generate_normals()
	return st.commit()

func _tri(st: SurfaceTool, color: Color, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.set_color(color); st.add_vertex(a)
	st.set_color(color); st.add_vertex(b)
	st.set_color(color); st.add_vertex(c)

# Nombre de triangles d'un mesh (diagnostic budget).
static func tri_count(m: ArrayMesh) -> int:
	if m == null or m.get_surface_count() == 0:
		return 0
	return (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
