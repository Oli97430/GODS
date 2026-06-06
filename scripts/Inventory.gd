extends Node
## Inventaire PERSISTANT des améliorations lootées, SAUVEGARDÉ sur disque (user://). Le loot s'applique au
## ramassage (auto), MAIS les bonus accumulés sont CONSERVÉS entre vagues / morts / sessions (≠ ancien reset par
## RUN). Source de vérité des bonus : le joueur DÉRIVE ses multiplicateurs d'ici au début de chaque combat.
## Per-joueur LOCAL (en coop, chaque machine a le sien). Autoload : Inventory.

const PATH := "user://inventory.cfg"
# Paliers + plafonds (généreux car persistants).
const DMG_STEP := 0.25
const DMG_MAX := 3.0
const FIRE_STEP := 0.20
const FIRE_MAX := 2.5
const SHIELD_PER := 25.0
const SHIELD_CAP := 150.0
const MISSILE_CAP := 24
const HEAL_CAP := 9

signal changed

var damage_stacks := 0    # loots « dégâts » collectés (=> multiplicateur de dégâts)
var firerate_stacks := 0  # loots « cadence »
var shield_stacks := 0    # loots « bouclier » (=> capacité d'overshield)
var missiles := 0         # munitions missile EN STOCK (consommées au tir)
var heals := 0            # soins EN STOCK (consommables — bouton « utiliser », CP-INV2)
var total := 0            # total de loots collectés (stat de progression)

# Ressources de RÉCOLTE (cueillette/abattage/minage) : dict générique id(String) -> quantité(int), persistant.
# Source de vérité unique pour l'inventaire de ressources (fruits, graines, feuilles, bois, pierre, minerais…).
var resources := {}

func _ready() -> void:
	load_inv()

# --- Dérivés (bonus auto-appliqués au joueur) ---
func damage_mult() -> float:
	return minf(1.0 + float(damage_stacks) * DMG_STEP, DMG_MAX)

func firerate_mult() -> float:
	return minf(1.0 + float(firerate_stacks) * FIRE_STEP, FIRE_MAX)

func shield_cap() -> float:
	return minf(float(shield_stacks) * SHIELD_PER, SHIELD_CAP)

# Ramassage d'un loot (kind 0-4) : accumule dans l'inventaire persistant + sauvegarde.
func collect(kind: int) -> void:
	total += 1
	match kind:
		0: heals = mini(heals + 1, HEAL_CAP)           # soin : instantané côté joueur + 1 en stock
		1: damage_stacks += 1
		2: firerate_stacks += 1
		3: shield_stacks += 1
		4: missiles = mini(missiles + 2, MISSILE_CAP)
	save_inv()
	changed.emit()

# --- Ressources de récolte (générique) ---

## Ajoute (ou retire si n<0) `n` unités de la ressource `id`. Sauvegarde + signal.
func add_resource(id: String, n: int = 1) -> void:
	if id == "" or n == 0:
		return
	var v := maxi(0, int(resources.get(id, 0)) + n)
	if v == 0:
		resources.erase(id)
	else:
		resources[id] = v
	save_inv()
	changed.emit()

## Consomme `n` unités si disponibles ; retourne true si consommé.
func consume_resource(id: String, n: int = 1) -> bool:
	if int(resources.get(id, 0)) < n:
		return false
	add_resource(id, -n)
	return true

func resource_count(id: String) -> int:
	return int(resources.get(id, 0))

func resource_total() -> int:
	var s := 0
	for k in resources:
		s += int(resources[k])
	return s

func use_heal() -> bool:
	if heals <= 0:
		return false
	heals -= 1
	save_inv()
	changed.emit()
	return true

func consume_missile() -> void:
	missiles = maxi(missiles - 1, 0)
	save_inv()
	changed.emit()

func set_missiles(n: int) -> void:
	missiles = clampi(n, 0, MISSILE_CAP)
	save_inv()
	changed.emit()

func reset_all() -> void:
	damage_stacks = 0
	firerate_stacks = 0
	shield_stacks = 0
	missiles = 0
	heals = 0
	total = 0
	resources.clear()
	save_inv()
	changed.emit()

func load_inv() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) != OK:
		return   # 1re fois : valeurs par défaut (inventaire vide)
	damage_stacks = int(c.get_value("inv", "damage", 0))
	firerate_stacks = int(c.get_value("inv", "firerate", 0))
	shield_stacks = int(c.get_value("inv", "shield", 0))
	missiles = int(c.get_value("inv", "missiles", 0))
	heals = int(c.get_value("inv", "heals", 0))
	total = int(c.get_value("inv", "total", 0))
	var r = c.get_value("resources", "items", {})   # Variant : pas de `:=`
	resources = r if typeof(r) == TYPE_DICTIONARY else {}

func save_inv() -> void:
	var c := ConfigFile.new()
	c.set_value("inv", "damage", damage_stacks)
	c.set_value("inv", "firerate", firerate_stacks)
	c.set_value("inv", "shield", shield_stacks)
	c.set_value("inv", "missiles", missiles)
	c.set_value("inv", "heals", heals)
	c.set_value("inv", "total", total)
	c.set_value("resources", "items", resources)
	c.save(PATH)
