class_name PopulationTuning
extends RefCounted
## Phase 20 — COUCHE A : configuration CENTRALE des densités de peuplement. TOUT se règle ICI,
## sans toucher au code de spawn (végétation phase 8, faune phase 19, clutter phase 20 couche B).
## Multiplicateurs par biome (indexés PlanetGenerator.Biome). Défauts proches de 1.0 => pas de
## régression visible ; on enrichit surtout la VARIÉTÉ de faune (roster) et on ajoute le clutter.
##
## Tout est STATIC + déterministe (constantes) : aucune dépendance d'état, thread-safe (lu dans les
## tâches de fond des chunks). Pour « repeupler » une planète, il suffit d'ajuster ces nombres.

# --- Faune : taille du roster par planète (phase 19 était 2-5 ; phase 20 => 3-7 = plus de variété) ---
const FAUNA_ROSTER_MIN := 3
const FAUNA_ROSTER_MAX := 7

# --- Multiplicateurs GLOBAUX (réglage rapide d'ensemble, toutes couches) ---
const VEGETATION_GLOBAL := 2.0   # densité de végétation TRÈS élevée (vraies forêts où l'on marche)
const FAUNA_GLOBAL := 1.5         # plus de créatures (tortues) : enrichit surtout les biomes pauvres vers leur plafond
const CLUTTER_GLOBAL := 1.0

# Plafond de sécurité d'une probabilité de semis après multiplication (évite « tout le temps »).
const MAX_PROB := 0.95

# --- Densité de VÉGÉTATION par biome (multiplie la proba de semis phase 8). 1.0 = inchangé ---
# (laisse la phase 8 telle quelle par défaut ; lève un biome ici s'il paraît trop vide).
const VEGETATION_BY_BIOME := {
	PlanetGenerator.Biome.OCEAN: 0.0,
	PlanetGenerator.Biome.BEACH: 1.0,
	PlanetGenerator.Biome.PLAINS: 1.15,   # plaines = prairie fournie mais OUVERTE (arbres épars)
	PlanetGenerator.Biome.FOREST: 1.5,    # forêt = VRAIS bois denses (canopée resserrée)
	PlanetGenerator.Biome.ROCK: 1.0,
	PlanetGenerator.Biome.SNOW: 1.0,
}

# --- Densité de FAUNE par biome (multiplie la proba de spawn par cellule, phase 19) ---
# Présence partout sur terre ferme (jamais 0 hors océan) ; un peu plus riche en plaine/forêt.
const FAUNA_BY_BIOME := {
	PlanetGenerator.Biome.OCEAN: 0.0,
	PlanetGenerator.Biome.BEACH: 0.7,
	PlanetGenerator.Biome.PLAINS: 1.1,
	PlanetGenerator.Biome.FOREST: 1.15,
	PlanetGenerator.Biome.ROCK: 0.7,
	PlanetGenerator.Biome.SNOW: 0.6,
}

# --- Densité de CLUTTER au sol par biome (phase 20 couche B) ---
# Dense en forêt (brindilles/feuilles), modéré en plaine, plus clairsemé en neige/roche, nul en mer.
const CLUTTER_BY_BIOME := {
	PlanetGenerator.Biome.OCEAN: 0.0,
	PlanetGenerator.Biome.BEACH: 1.0,
	PlanetGenerator.Biome.PLAINS: 1.0,
	PlanetGenerator.Biome.FOREST: 1.25,
	PlanetGenerator.Biome.ROCK: 0.85,
	PlanetGenerator.Biome.SNOW: 0.65,
}

# --- API (lecture seule, thread-safe) ---

# Multiplicateur de densité de végétation pour un biome (>= 0).
static func vegetation_density(biome: int) -> float:
	return VEGETATION_GLOBAL * float(VEGETATION_BY_BIOME.get(biome, 1.0))

# Multiplicateur de densité de faune pour un biome (>= 0).
static func fauna_density(biome: int) -> float:
	return FAUNA_GLOBAL * float(FAUNA_BY_BIOME.get(biome, 1.0))

# Multiplicateur de densité de clutter pour un biome (>= 0).
static func clutter_density(biome: int) -> float:
	return CLUTTER_GLOBAL * float(CLUTTER_BY_BIOME.get(biome, 1.0))

# Applique un multiplicateur à une probabilité de base, borné à [0, MAX_PROB] (garde-fou).
static func scaled_prob(base_prob: float, mult: float) -> float:
	return clampf(base_prob * mult, 0.0, MAX_PROB)
