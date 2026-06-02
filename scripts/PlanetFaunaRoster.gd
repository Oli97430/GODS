class_name PlanetFaunaRoster
extends RefCounted
## Roster de FAUNE d'une planète (phase 19) : dérive du seed_local une liste DÉTERMINISTE de 2 à 5
## espèces. Chaque espèce = { archétype + paramètres de meshes (FaunaLibrary), biome préféré,
## rayon de fuite, vitesse de marche, cycle d'activité (diurne/nocturne/crépusculaire), sensibilité
## à l'orage, densité }. RNG seedé par une graine DISTINCTE (n'interfère pas avec terrain/lunes).
## Mêmes paramètres = même roster (revenir sur la planète => mêmes espèces reconnaissables).

enum Activity { DIURNAL, NOCTURNAL, CREPUSCULAR }
const ACTIVITY_NAMES := ["diurne", "nocturne", "crépusculaire"]
const BIOME_NAMES := ["océan", "plage", "plaine", "forêt", "roche", "neige"]
const ROSTER_SEED_OFFSET := 4242   # graine distincte (terrain/lunes inchangés)

# Biomes terrestres habitables (pas d'océan : faune aquatique = phase 20).
const LAND_BIOMES := [
	PlanetGenerator.Biome.PLAINS, PlanetGenerator.Biome.FOREST,
	PlanetGenerator.Biome.ROCK, PlanetGenerator.Biome.SNOW, PlanetGenerator.Biome.BEACH,
]
const ARCHETYPES := [FaunaLibrary.Archetype.QUADRUPED, FaunaLibrary.Archetype.BIPED, FaunaLibrary.Archetype.HEXAPOD]

# Liste déterministe des espèces d'une planète (phase 20 couche A : 3 à 7, cf. PopulationTuning).
# 'lib' sert à construire les params de meshes.
static func generate(seed_local: int, lib: FaunaLibrary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_local + ROSTER_SEED_OFFSET
	var count := rng.randi_range(PopulationTuning.FAUNA_ROSTER_MIN, PopulationTuning.FAUNA_ROSTER_MAX)
	var out := []
	for i in count:
		out.append(_make_species(rng, lib, seed_local, i))
	return out

static func _make_species(rng: RandomNumberGenerator, lib: FaunaLibrary, seed_local: int, idx: int) -> Dictionary:
	var arch: int = ARCHETYPES[rng.randi() % ARCHETYPES.size()]
	var biome: int = LAND_BIOMES[rng.randi() % LAND_BIOMES.size()]
	var color := _biome_color(biome, rng)
	var s := rng.randf_range(0.7, 1.5)   # facteur de taille de l'espèce
	var params: Dictionary
	match arch:
		FaunaLibrary.Archetype.BIPED:
			params = lib.make_params(arch, 0.5 * s, 1.0 * s, 0.5 * s, 0.9 * s, 0.11 * s, 0.42 * s, color)
		FaunaLibrary.Archetype.HEXAPOD:
			params = lib.make_params(arch, 1.8 * s, 0.45 * s, 0.6 * s, 0.5 * s, 0.07 * s, 0.32 * s, color)
		_:
			params = lib.make_params(arch, 1.4 * s, 0.6 * s, 0.7 * s, 0.7 * s, 0.10 * s, 0.40 * s, color)
	return {
		"key": seed_local * 16 + idx,            # clé stable pour le cache de meshes (FaunaLibrary)
		"name": "Espèce %s" % String.chr(65 + idx),
		"archetype": arch,
		"params": params,
		"biome": biome,                          # biome préféré (filtre de spawn)
		"flee_radius": rng.randf_range(6.0, 16.0),
		"walk_speed": rng.randf_range(1.0, 3.0),
		"activity": rng.randi() % 3,             # Activity (diurne/nocturne/crépusculaire)
		"storm_sensitivity": rng.randf_range(0.4, 0.8),
		"density": rng.randf_range(0.4, 1.0),    # densité relative au spawn par chunk
	}

# Couleur de créature teintée par le biome (cohérence visuelle), avec variation seedée.
static func _biome_color(biome: int, rng: RandomNumberGenerator) -> Color:
	match biome:
		PlanetGenerator.Biome.FOREST:
			return Color.from_hsv(rng.randf_range(0.25, 0.42), rng.randf_range(0.35, 0.60), rng.randf_range(0.32, 0.58))
		PlanetGenerator.Biome.SNOW:
			return Color.from_hsv(rng.randf_range(0.50, 0.66), rng.randf_range(0.00, 0.16), rng.randf_range(0.70, 0.95))
		PlanetGenerator.Biome.ROCK:
			return Color.from_hsv(rng.randf_range(0.04, 0.12), rng.randf_range(0.10, 0.32), rng.randf_range(0.32, 0.58))
		PlanetGenerator.Biome.BEACH:
			return Color.from_hsv(rng.randf_range(0.08, 0.14), rng.randf_range(0.30, 0.50), rng.randf_range(0.58, 0.85))
		_:  # PLAINS
			return Color.from_hsv(rng.randf_range(0.09, 0.18), rng.randf_range(0.35, 0.60), rng.randf_range(0.48, 0.75))

static func activity_name(a: int) -> String:
	return ACTIVITY_NAMES[a] if a >= 0 and a < ACTIVITY_NAMES.size() else "?"

static func biome_name(b: int) -> String:
	return BIOME_NAMES[b] if b >= 0 and b < BIOME_NAMES.size() else "?"
