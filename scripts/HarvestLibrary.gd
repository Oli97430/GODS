class_name HarvestLibrary
extends RefCounted
## Données de RÉCOLTE (cueillette / abattage / minage) — table centrale et PURE (aucun état, aucune scène).
## Décrit : les ITEMS (id -> nom FR + couleur + catégorie + soin si comestible + plantable), les RENDEMENTS
## par espèce d'arbre (fruit/graine/feuille/bois + nb de coups pour abattre) et par rocher (pierre/minerai),
## et les constantes de portée / repousse / geste. Consommée par HarvestManager (CP2+) et l'UI inventaire.
##
## Convention : identifiants d'items en anglais (clés stables, sauvegardées), noms d'affichage en français.

# --- Catégories (chaîne libre, sert au tri/regroupement dans l'UI) ---
const KIND_FRUIT := "fruit"
const KIND_SEED := "seed"
const KIND_LEAF := "leaf"
const KIND_WOOD := "wood"
const KIND_STONE := "stone"
const KIND_ORE := "ore"      # minerais métalliques (fer, cuivre, or…)
const KIND_GEM := "gem"      # pierres précieuses (diamant, rubis, émeraude…)
const KIND_METAL := "metal"  # lingots fondus (fer, cuivre, or) — produits intermédiaires
const KIND_BUILD := "build"  # éléments construits (planches, murs, toits…) — plaçables dans le monde

# Ordre d'affichage des catégories dans le panneau d'inventaire.
const KIND_ORDER: Array[String] = [KIND_FRUIT, KIND_SEED, KIND_LEAF, KIND_WOOD, KIND_STONE, KIND_ORE, KIND_GEM, KIND_METAL, KIND_BUILD]

# --- Table des items (static var => initialisée une fois ; autorise les Color()). ---
static var ITEMS := {
	# Fruits (comestibles : heal > 0)
	"fruit_apple":    {"name": "Pomme",            "color": Color(0.85, 0.20, 0.18), "kind": KIND_FRUIT, "heal": 12.0},
	"fruit_coconut":  {"name": "Noix de coco",     "color": Color(0.62, 0.45, 0.28), "kind": KIND_FRUIT, "heal": 18.0},
	"fruit_berry":    {"name": "Baies",            "color": Color(0.50, 0.18, 0.58), "kind": KIND_FRUIT, "heal": 8.0},
	"cone_pine":      {"name": "Pomme de pin",     "color": Color(0.45, 0.30, 0.16), "kind": KIND_FRUIT, "heal": 0.0},   # résine : non comestible
	# Graines (plantables, CP4)
	"seed_deciduous": {"name": "Pépin de pomme",        "color": Color(0.55, 0.40, 0.22), "kind": KIND_SEED, "plantable": true},
	"seed_palm":      {"name": "Graine de palmier",     "color": Color(0.50, 0.38, 0.24), "kind": KIND_SEED, "plantable": true},
	"seed_conifer":   {"name": "Graine de conifère",    "color": Color(0.42, 0.34, 0.22), "kind": KIND_SEED, "plantable": true},
	"seed_twisted":   {"name": "Graine noueuse",        "color": Color(0.40, 0.30, 0.26), "kind": KIND_SEED, "plantable": true},
	# Feuilles
	"leaf_broad":     {"name": "Feuille",          "color": Color(0.30, 0.55, 0.22), "kind": KIND_LEAF},
	"leaf_palm":      {"name": "Palme",            "color": Color(0.32, 0.52, 0.26), "kind": KIND_LEAF},
	"needle":         {"name": "Aiguilles",        "color": Color(0.24, 0.42, 0.28), "kind": KIND_LEAF},
	"leaf_dry":       {"name": "Feuille sèche",     "color": Color(0.55, 0.45, 0.22), "kind": KIND_LEAF},
	# Bois (par essence ; wood_oak = essence du feuillu à pommes => « bois de pommier » pour rester cohérent)
	"wood_oak":       {"name": "Bois de pommier",  "color": Color(0.52, 0.36, 0.20), "kind": KIND_WOOD},
	"wood_palm":      {"name": "Bois de palmier",  "color": Color(0.60, 0.45, 0.26), "kind": KIND_WOOD},
	"wood_pine":      {"name": "Bois de pin",      "color": Color(0.58, 0.42, 0.24), "kind": KIND_WOOD},
	"wood_dark":      {"name": "Bois sombre",      "color": Color(0.34, 0.26, 0.20), "kind": KIND_WOOD},
	# Minéraux
	"stone":          {"name": "Pierre",           "color": Color(0.55, 0.55, 0.58), "kind": KIND_STONE},
	"ore_iron":       {"name": "Minerai de fer",   "color": Color(0.70, 0.50, 0.35), "kind": KIND_ORE},
	"ore_copper":     {"name": "Cuivre",           "color": Color(0.74, 0.46, 0.30), "kind": KIND_ORE},
	"ore_gold":       {"name": "Or",               "color": Color(0.93, 0.77, 0.31), "kind": KIND_ORE},
	"ore_crystal":    {"name": "Cristal",          "color": Color(0.55, 0.85, 0.95), "kind": KIND_ORE},
	# Pierres précieuses (rares, issues des rochers cristallins)
	"gem_diamond":    {"name": "Diamant",          "color": Color(0.82, 0.93, 0.99), "kind": KIND_GEM},
	"gem_ruby":       {"name": "Rubis",            "color": Color(0.86, 0.16, 0.27), "kind": KIND_GEM},
	"gem_emerald":    {"name": "Émeraude",         "color": Color(0.20, 0.78, 0.50), "kind": KIND_GEM},
	# Lingots fondus (minerais transformés en barres — produits intermédiaires)
	"ingot_iron":     {"name": "Lingot de fer",     "color": Color(0.55, 0.45, 0.38), "kind": KIND_METAL},
	"ingot_copper":   {"name": "Lingot de cuivre",  "color": Color(0.72, 0.48, 0.30), "kind": KIND_METAL},
	"ingot_gold":     {"name": "Lingot d'or",       "color": Color(0.92, 0.76, 0.32), "kind": KIND_METAL},
	# Constructions (fabricables, plaçables dans le monde)
	"plank":          {"name": "Planche",           "color": Color(0.58, 0.40, 0.24), "kind": KIND_BUILD},
	"wall_stone":     {"name": "Mur de pierre",     "color": Color(0.50, 0.48, 0.44), "kind": KIND_BUILD},
	"roof_thatch":    {"name": "Toit de chaume",    "color": Color(0.45, 0.54, 0.30), "kind": KIND_BUILD},
	"pillar_iron":    {"name": "Pilier en fer",     "color": Color(0.42, 0.40, 0.38), "kind": KIND_BUILD},
	"door_copper":    {"name": "Porte en cuivre",   "color": Color(0.68, 0.46, 0.30), "kind": KIND_BUILD},
	"lamp_gold":      {"name": "Lanterne dorée",    "color": Color(0.88, 0.74, 0.34), "kind": KIND_BUILD},
	# Blocs cubiques (empilables, façon Minecraft)
	"block_wood":     {"name": "Bloc de bois",      "color": Color(0.55, 0.40, 0.24), "kind": KIND_BUILD},
	"block_stone":    {"name": "Bloc de pierre",    "color": Color(0.52, 0.52, 0.55), "kind": KIND_BUILD},
	"block_leaf":     {"name": "Bloc de feuillage", "color": Color(0.26, 0.50, 0.24), "kind": KIND_BUILD},
	"block_iron":     {"name": "Bloc de fer",       "color": Color(0.62, 0.64, 0.68), "kind": KIND_BUILD},
}

# --- Portées / gestes / repousse (s = secondes réelles) ---
const PICK_REACH := 2.4        # m : portée de cueillette mains nues (depuis la main)
const TOOL_REACH := 3.0        # m : portée d'un coup d'outil — il faut se rapprocher de l'arbre/rocher pour le viser
const SWING_SPEED := 1.2       # m/s : vitesse de main mini pour valider un coup (geste physique) — tolérant
const SWING_COOLDOWN := 0.45   # s : délai entre deux coups
const REGROW_FRUIT := 75.0     # s : repousse d'un fruit cueilli sur l'arbre
const REGROW_TREE := 240.0     # s : repousse d'un arbre abattu
const REGROW_ROCK := 200.0     # s : réapparition d'un rocher cassé
const WOOD_PER_TREE_MIN := 3
const WOOD_PER_TREE_MAX := 6
const STONE_PER_ROCK_MIN := 2
const STONE_PER_ROCK_MAX := 4
const ORE_CHANCE := 0.22       # proba qu'un rocher cassé lâche en plus un minerai

# Rendement d'une espèce d'arbre (clé = SpeciesLibrary.Species). fruit_cap = fruits portés simultanément.
static func species_yield(sp: int) -> Dictionary:
	match sp:
		SpeciesLibrary.Species.DECIDUOUS:
			return {"fruit": "fruit_apple", "seed": "seed_deciduous", "leaf": "leaf_broad", "wood": "wood_oak", "fruit_cap": 3, "fell_hits": 5}
		SpeciesLibrary.Species.PALM:
			return {"fruit": "fruit_coconut", "seed": "seed_palm", "leaf": "leaf_palm", "wood": "wood_palm", "fruit_cap": 2, "fell_hits": 4}
		SpeciesLibrary.Species.CONIFER:
			return {"fruit": "cone_pine", "seed": "seed_conifer", "leaf": "needle", "wood": "wood_pine", "fruit_cap": 3, "fell_hits": 6}
		SpeciesLibrary.Species.TWISTED:
			return {"fruit": "fruit_berry", "seed": "seed_twisted", "leaf": "leaf_dry", "wood": "wood_dark", "fruit_cap": 4, "fell_hits": 5}
	return {"fruit": "fruit_berry", "seed": "seed_deciduous", "leaf": "leaf_broad", "wood": "wood_oak", "fruit_cap": 3, "fell_hits": 5}

# Graine produite en DÉCOMPOSANT un fruit (CP4 : le joueur choisit manger OU décomposer en graines).
static func seed_for_fruit(fruit_id: String) -> String:
	match fruit_id:
		"fruit_apple":   return "seed_deciduous"
		"fruit_coconut": return "seed_palm"
		"cone_pine":     return "seed_conifer"
		"fruit_berry":   return "seed_twisted"
	return ""

# Rendement d'un rocher minable SELON SA VARIANTE (VegetationLibrary.V_ROCK_*). Les rochers communs (gris)
# donnent surtout de la pierre + parfois un minerai courant ; les rochers spéciaux (cuivre/or/cristallin) sont
# rares et donnent presque sûrement leur ressource. ore_qty = Vector2i(min,max) de quantité de minerai/gemme.
static func rock_yield_for(variant: int) -> Dictionary:
	match variant:
		VegetationLibrary.V_ROCK_COPPER:
			return {"stone": "stone", "ores": ["ore_copper"], "ore_chance": 0.85, "ore_qty": Vector2i(1, 2), "mine_hits": 5}
		VegetationLibrary.V_ROCK_GOLD:
			return {"stone": "stone", "ores": ["ore_gold"], "ore_chance": 0.90, "ore_qty": Vector2i(1, 2), "mine_hits": 6}
		VegetationLibrary.V_ROCK_CRYSTAL:
			return {"stone": "stone", "ores": ["gem_diamond", "gem_ruby", "gem_emerald"], "ore_chance": 0.80, "ore_qty": Vector2i(1, 1), "mine_hits": 7}
	# Rochers communs (gros gris / petit sombre) : pierre + un peu de fer ou cuivre.
	return {"stone": "stone", "ores": ["ore_iron", "ore_copper"], "ore_chance": ORE_CHANCE, "ore_qty": Vector2i(1, 1), "mine_hits": 5}

# Compat : rendement d'un rocher commun (sans variante connue).
static func rock_yield() -> Dictionary:
	return rock_yield_for(VegetationLibrary.V_ROCK_A)

# --- Accès items (sûrs si id inconnu) ---
static func item(id: String) -> Dictionary:
	return ITEMS.get(id, {})

static func item_name(id: String) -> String:
	return String(ITEMS.get(id, {}).get("name", id))

static func item_color(id: String) -> Color:
	return ITEMS.get(id, {}).get("color", Color(0.8, 0.8, 0.8))

static func item_kind(id: String) -> String:
	return String(ITEMS.get(id, {}).get("kind", ""))

static func item_heal(id: String) -> float:
	return float(ITEMS.get(id, {}).get("heal", 0.0))

static func is_edible(id: String) -> bool:
	return item_heal(id) > 0.0

static func is_plantable(id: String) -> bool:
	return bool(ITEMS.get(id, {}).get("plantable", false))
