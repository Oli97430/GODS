class_name CraftLibrary
extends RefCounted
## Catalogue de CRAFT data-driven (CP-CRAFT) : table CENTRALE et PURE de toutes les recettes (aucun
## état, aucune scène). Remplace les boutons codés en dur de la montre. Chaque recette dit QUOI consommer
## (catégorie de ressource OU id exact) et QUOI produire (item + quantité), et si le résultat se POSE
## dans le monde (pièce de construction / bloc / déco) ou va à l'inventaire (lingot, repas…).
##
## Conventions : identifiants d'items EN ANGLAIS (clés stables, partagées avec HarvestLibrary / BuildManager),
## noms d'affichage EN FRANÇAIS. L'EXÉCUTION (consommer + produire + entrer en pose) reste dans la montre
## (helpers _craft_*), pilotée par ces données => zéro duplication, recettes ajoutables sans code.
##
## Champs d'une recette :
##   id    : id de l'item PRODUIT (= clé HarvestLibrary.ITEMS ; pour les posables, = clé BuildManager.PIECES)
##   name  : libellé FR (bouton)
##   cat   : catégorie d'onglet (CAT_*)
##   src   : ce qu'on consomme — soit une CATÉGORIE (HarvestLibrary.KIND_*) si by_kind, soit un id exact sinon
##   by_kind : true => src est une catégorie (n'importe quelle ressource du type) ; false => id précis
##   qty   : quantité consommée
##   out_n : quantité produite (défaut 1 ; >1 = lot, ex. blocs)
##   place : true => après fabrication, entrer en mode POSE (pièce/bloc/déco) ; false => reste à l'inventaire

const CAT_SMELT := "Fonderie"
const CAT_BUILD := "Construction"
const CAT_FURNITURE := "Mobilier"
const CAT_LIGHT := "Lumière"
const CAT_BLOCK := "Blocs"
const CAT_FOOD := "Cuisine"
const CAT_FISHING := "Pêche"

# Ordre d'affichage des catégories dans l'onglet Bâtir.
const CATEGORIES: Array[String] = [CAT_BUILD, CAT_FURNITURE, CAT_LIGHT, CAT_BLOCK, CAT_SMELT, CAT_FOOD, CAT_FISHING]

# Libellé court d'une catégorie de ressource consommée (pour l'affichage du coût).
const KIND_LABEL := {
	"wood": "Bois", "stone": "Pierre", "leaf": "Feuillage", "fruit": "Fruit",
}

static func _r(id: String, name: String, cat: String, src: String, by_kind: bool, qty: int, place: bool, out_n: int = 1) -> Dictionary:
	return {"id": id, "name": name, "cat": cat, "src": src, "by_kind": by_kind, "qty": qty, "place": place, "out_n": out_n}

# Toutes les recettes (les 6 premières reproduisent À L'IDENTIQUE l'ancien comportement → zéro régression).
static var RECIPES: Array = [
	# --- Fonderie (minerai → lingot, va à l'inventaire) ---
	_r("ingot_iron",   "Lingot de fer",    CAT_SMELT, "ore_iron",   false, 2, false),
	_r("ingot_copper", "Lingot de cuivre", CAT_SMELT, "ore_copper", false, 2, false),
	_r("ingot_gold",   "Lingot d'or",      CAT_SMELT, "ore_gold",   false, 2, false),

	# --- Construction (pièces posables) ---
	_r("plank",        "Planche",        CAT_BUILD, HarvestLibrary.KIND_WOOD,  true, 3, true),
	_r("beam_wood",    "Poutre",         CAT_BUILD, HarvestLibrary.KIND_WOOD,  true, 2, true),
	_r("fence_wood",   "Clôture",        CAT_BUILD, HarvestLibrary.KIND_WOOD,  true, 2, true),
	_r("ladder_wood",  "Échelle",        CAT_BUILD, HarvestLibrary.KIND_WOOD,  true, 3, true),
	_r("stairs_wood",  "Escalier",       CAT_BUILD, HarvestLibrary.KIND_WOOD,  true, 4, true),
	_r("window_wood",  "Fenêtre",        CAT_BUILD, HarvestLibrary.KIND_WOOD,  true, 4, true),
	_r("wall_stone",   "Mur de pierre",  CAT_BUILD, HarvestLibrary.KIND_STONE, true, 5, true),
	_r("floor_stone",  "Dalle",          CAT_BUILD, HarvestLibrary.KIND_STONE, true, 3, true),
	_r("roof_thatch",  "Toit de chaume", CAT_BUILD, HarvestLibrary.KIND_LEAF,  true, 4, true),
	_r("pillar_iron",  "Pilier en fer",  CAT_BUILD, "ingot_iron",   false, 3, true),
	_r("door_copper",  "Porte en cuivre",CAT_BUILD, "ingot_copper", false, 2, true),

	# --- Mobilier / déco (posables) ---
	_r("table_wood",   "Table",      CAT_FURNITURE, HarvestLibrary.KIND_WOOD,  true, 4, true),
	_r("chair_wood",   "Chaise",     CAT_FURNITURE, HarvestLibrary.KIND_WOOD,  true, 3, true),
	_r("shelf_wood",   "Étagère",    CAT_FURNITURE, HarvestLibrary.KIND_WOOD,  true, 4, true),
	_r("chest_wood",   "Coffre",     CAT_FURNITURE, HarvestLibrary.KIND_WOOD,  true, 5, true),
	_r("barrel_wood",  "Tonneau",    CAT_FURNITURE, HarvestLibrary.KIND_WOOD,  true, 5, true),
	_r("bed_wood",     "Lit",        CAT_FURNITURE, HarvestLibrary.KIND_WOOD,  true, 6, true),
	_r("column_stone", "Colonne",    CAT_FURNITURE, HarvestLibrary.KIND_STONE, true, 4, true),
	_r("statue_stone", "Statue",     CAT_FURNITURE, HarvestLibrary.KIND_STONE, true, 6, true),
	_r("rug_leaf",     "Tapis",      CAT_FURNITURE, HarvestLibrary.KIND_LEAF,  true, 3, true),
	_r("banner_leaf",  "Banderole",  CAT_FURNITURE, HarvestLibrary.KIND_LEAF,  true, 2, true),

	# --- Lumière (posables, émissives) ---
	_r("torch_wood",     "Torche",          CAT_LIGHT, HarvestLibrary.KIND_WOOD,  true, 2, true),
	_r("brazier_stone",  "Brasero",         CAT_LIGHT, HarvestLibrary.KIND_STONE, true, 4, true),
	_r("lantern_iron",   "Lanterne de fer", CAT_LIGHT, "ingot_iron",   false, 1, true),
	_r("lamp_gold",      "Lanterne dorée",  CAT_LIGHT, "ingot_gold",   false, 1, true),

	# --- Blocs cubiques (façon Minecraft, posables, par lot) ---
	_r("block_wood",   "Bloc de bois ×4",      CAT_BLOCK, HarvestLibrary.KIND_WOOD,  true, 1, true, 4),
	_r("block_stone",  "Bloc de pierre ×4",    CAT_BLOCK, HarvestLibrary.KIND_STONE, true, 1, true, 4),
	_r("block_leaf",   "Bloc de feuillage ×4", CAT_BLOCK, HarvestLibrary.KIND_LEAF,  true, 2, true, 4),
	_r("block_iron",   "Bloc de fer ×2",       CAT_BLOCK, "ingot_iron",   false, 1, true, 2),
	_r("block_copper", "Bloc de cuivre ×2",    CAT_BLOCK, "ingot_copper", false, 1, true, 2),
	_r("block_gold",   "Bloc d'or ×2",         CAT_BLOCK, "ingot_gold",   false, 1, true, 2),

	# --- Cuisine (consommables, vont à l'inventaire ; soin via « Manger ») ---
	_r("meal_cooked",  "Repas chaud",       CAT_FOOD, HarvestLibrary.KIND_FRUIT, true, 2, false),
	_r("dried_fruit",  "Fruits séchés ×2",  CAT_FOOD, HarvestLibrary.KIND_FRUIT, true, 3, false, 2),

	# --- Pêche (CP-PÊCHE) : la canne va à l'inventaire puis s'ÉQUIPE depuis le Sac / la montre ---
	_r("fishing_rod",  "Canne à pêche",     CAT_FISHING, HarvestLibrary.KIND_WOOD, true, 4, false),
]

# Recettes d'une catégorie (ordre de la table).
static func recipes_for(cat: String) -> Array:
	var out: Array = []
	for r in RECIPES:
		if r.cat == cat:
			out.append(r)
	return out

# Libellé du COÛT d'une recette (« 3 Bois », « 2 Minerai de fer »).
static func cost_text(r: Dictionary) -> String:
	var what: String
	if bool(r.by_kind):
		what = String(KIND_LABEL.get(String(r.src), String(r.src)))
	else:
		what = HarvestLibrary.item_name(String(r.src))
	return "%d %s" % [int(r.qty), what]
