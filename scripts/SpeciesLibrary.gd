class_name SpeciesLibrary
extends RefCounted
## Phase 24 — registre des ESPÈCES d'arbres L-system. Chaque espèce = (axiome, règles de réécriture,
## itérations, params de tortue, palette, style de feuille, biomes préférés). On génère plusieurs
## VARIANTES par espèce (seeds différents + léger jitter de params) pour éviter la répétition.
## Tout est DÉTERMINISTE et bas-poly (forêts denses + framerate PCVR). Meshes à couleurs de vertices
## => rendus par le matériau de vent partagé de VegetationLibrary.

enum Species { CONIFER, DECIDUOUS, PALM, TWISTED }
const SPECIES_COUNT := 4
const VARIANTS_PER_SPECIES := 3   # 3 meshes distincts / espèce (variété sans exploser le nombre de MultiMesh)

# Définition d'une espèce (règles + params de tortue). Les params sont passés tels quels à to_mesh.
static func _def(sp: int) -> Dictionary:
	match sp:
		Species.CONIFER:
			# Sapin : tronc droit + verticilles de branches courtes retombantes (aiguilles), silhouette conique étroite.
			return {
				"axiom": "T",
				"rules": {
					"T": [[1.0, "F[w]!T"]],
					"w": [[1.0, "&&FL////&&FL////&&FL////&&FL////&&FL"]],
				},
				"iterations": 6,
				"params": {
					"angle": 18.0, "length": 0.62, "length_falloff": 0.90,
					"radius": 0.11, "radius_falloff": 0.85, "taper": 0.88, "sides": 4,
					"leaf_style": LSystemGenerator.LEAF_NEEDLE, "leaf_size": 0.5,
					"wood_color": Color(0.27, 0.19, 0.12), "leaf_color": Color(0.13, 0.33, 0.18),
				},
			}
		Species.DECIDUOUS:
			# Feuillu : embranchements 2-3 voies (stochastiques) + canopée ronde de blobs de feuilles.
			return {
				"axiom": "FFA",
				"rules": {
					"A": [
						[0.34, "F!&[+AL]/[-AL]^[+AL]"],
						[0.33, "F!&[-AL]/[+AL]L"],
						[0.33, "F!/[+AL]&[-AL]L"],
					],
				},
				"iterations": 4,
				"params": {
					"angle": 32.0, "length": 0.55, "length_falloff": 0.80,
					"radius": 0.13, "radius_falloff": 0.74, "taper": 0.80, "sides": 4,
					"leaf_style": LSystemGenerator.LEAF_BLOB, "leaf_size": 0.5,
					"wood_color": Color(0.33, 0.23, 0.15), "leaf_color": Color(0.24, 0.45, 0.18),
				},
			}
		Species.PALM:
			# Palmier : tronc nu élancé légèrement courbé + couronne de frondes retombantes au sommet.
			return {
				"axiom": "P",
				"rules": {
					"P": [[1.0, "FFFFFFFK"]],
					"K": [[1.0, "[R]//[R]//[R]//[R]//[R]//[R]//[R]//[R]"]],
					"R": [[1.0, "^^FF&&FFL"]],
				},
				"iterations": 3,
				"params": {
					"angle": 22.0, "length": 0.64, "length_falloff": 0.99,
					"radius": 0.09, "radius_falloff": 0.985, "taper": 0.96, "sides": 5,
					"leaf_style": LSystemGenerator.LEAF_FROND, "leaf_size": 0.7, "tropism": 0.05,
					"wood_color": Color(0.40, 0.30, 0.18), "leaf_color": Color(0.28, 0.50, 0.20),
				},
			}
		Species.TWISTED:
			# Alien : tronc noueux qui vrille (beaucoup de roulis/tangage), feuillage clairsemé aux teintes étranges.
			return {
				"axiom": "FA",
				"rules": {
					"A": [
						[0.40, "F/&[+A]!\\AL"],
						[0.35, "F\\^[-A]!/AL"],
						[0.25, "F&&[+A][-A]!L"],
					],
				},
				"iterations": 4,
				"params": {
					"angle": 36.0, "length": 0.50, "length_falloff": 0.82,
					"radius": 0.10, "radius_falloff": 0.78, "taper": 0.82, "sides": 4,
					"leaf_style": LSystemGenerator.LEAF_BLOB, "leaf_size": 0.30,
					"wood_color": Color(0.27, 0.21, 0.23), "leaf_color": Color(0.46, 0.30, 0.52),
				},
			}
	return {}

# Biomes où l'espèce peut apparaître (PlanetGenerator.Biome). Renseigne le semis (cp7).
static func biomes_for(sp: int) -> Array:
	match sp:
		Species.CONIFER:
			return [PlanetGenerator.Biome.FOREST]                              # forêts (surtout humides/altitude)
		Species.DECIDUOUS:
			return [PlanetGenerator.Biome.FOREST, PlanetGenerator.Biome.PLAINS] # forêts + plaines
		Species.PALM:
			return [PlanetGenerator.Biome.BEACH, PlanetGenerator.Biome.PLAINS]  # côtes / plaines chaudes
		Species.TWISTED:
			return [PlanetGenerator.Biome.ROCK, PlanetGenerator.Biome.PLAINS]   # terrains rocheux / étranges
	return []

# Génère toutes les variantes : renvoie Array (taille SPECIES_COUNT) de Array[Mesh] (taille VARIANTS_PER_SPECIES).
static func build_variant_meshes() -> Array:
	var out: Array = []
	for sp in SPECIES_COUNT:
		var def := _def(sp)
		var variants: Array[Mesh] = []
		for v in VARIANTS_PER_SPECIES:
			var seed_v := (sp + 1) * 100003 + v * 1013
			var lstr := LSystemGenerator.expand(def["axiom"], def["rules"], def["iterations"], seed_v)
			variants.append(LSystemGenerator.to_mesh(lstr, _jittered(def["params"], v, seed_v)))
		out.append(variants)
	return out

# Léger jitter déterministe des params par variante (angle/longueur) : variété même pour des règles non stochastiques.
static func _jittered(base: Dictionary, v: int, seed_v: int) -> Dictionary:
	if v == 0:
		return base   # variante 0 = définition canonique
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var p := base.duplicate(true)
	p["angle"] = float(base.get("angle", 28.0)) * rng.randf_range(0.88, 1.12)
	p["length"] = float(base.get("length", 0.5)) * rng.randf_range(0.90, 1.10)
	p["radius_falloff"] = clampf(float(base.get("radius_falloff", 0.8)) * rng.randf_range(0.97, 1.03), 0.6, 0.99)
	return p

# Arbre GÉANT (POI « arbre géant ») : un colosse organique L-system. Espèce feuillue (parfois twisted),
# +1 itération + échelle « géant ». Renvoie 1 ArrayMesh à couleurs de vertices (bois + feuilles). MAIN-THREAD ok.
static func build_giant(seed_val: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var sp := Species.TWISTED if rng.randf() < 0.30 else Species.DECIDUOUS
	var def := _def(sp)
	var params: Dictionary = def["params"].duplicate(true)
	params["length"] = float(params["length"]) * 5.0          # segments longs => colosse (~12 m)
	params["radius"] = float(params["radius"]) * 7.0           # tronc massif
	params["leaf_size"] = float(params["leaf_size"]) * 2.6     # canopée généreuse
	params["sides"] = 6                                         # tronc un peu plus rond (POI rare)
	params["leaf_color"] = Color.from_hsv(rng.randf_range(0.08, 0.36), rng.randf_range(0.4, 0.65), rng.randf_range(0.32, 0.52))  # vert profond -> automne
	var iters: int = int(def["iterations"]) + 1                # +1 itération = plus imposant
	var lstr := LSystemGenerator.expand(def["axiom"], def["rules"], iters, seed_val)
	return LSystemGenerator.to_mesh(lstr, params)
