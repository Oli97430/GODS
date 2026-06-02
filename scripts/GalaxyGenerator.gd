class_name GalaxyGenerator
extends RefCounted
## Génère une galaxie spirale 100% déterministe à partir d'une graine.
##
## Toute l'aléa découle d'un RandomNumberGenerator seedé + d'un FastNoiseLite seedé :
## même graine => galaxie identique à chaque lancement. Chaque système reçoit un
## seed_local qui servira aux phases 2/3 à générer son contenu (planètes...) de
## façon reproductible.

# Classes spectrales réelles, de la plus chaude/bleue à la plus froide/rouge.
enum StarType { O, B, A, F, G, K, M }

# Un système stellaire de la galaxie.
class StarSystem:
	var id: int
	var position: Vector3   # position locale (centre de la galaxie = origine)
	var seed_local: int     # graine déterministe propre au système (phases 2/3)
	var star_type: int      # valeur de GalaxyGenerator.StarType
	var name: String        # phase 19.5 : nom propre (palette = région galactique de la position)
	var palette_id: int     # phase 19.5 : palette linguistique régionale (héritée par les planètes)

# Conteneur de données détenu par GalaxyView.
class GalaxyData:
	var galaxy_seed: int = 0
	var radius: float = 0.0
	var systems: Array = []  # éléments : StarSystem

# --- Paramètres de forme (constants => reproductibles) ---
const ARMS := 3              # nombre de bras spiraux
const ARM_TWIST := 2.4       # enroulement des bras (tours sur le rayon)
const ARM_SPREAD := 0.30     # dispersion angulaire autour d'un bras (radians)
const ARM_WAVE := 0.35       # amplitude de l'ondulation organique (bruit)
const DISK_THICKNESS := 3.5  # demi-épaisseur du disque au centre
const RADIAL_BIAS := 0.65    # <1 : léger renflement central (bulbe)

const TYPE_LETTERS := ["O", "B", "A", "F", "G", "K", "M"]

# Génère la galaxie. radius = rayon du disque en unités locales.
static func generate(galaxy_seed: int, system_count: int, radius: float) -> GalaxyData:
	var data := GalaxyData.new()
	data.galaxy_seed = galaxy_seed
	data.radius = radius

	# Source d'aléa unique : l'ordre des tirages ci-dessous est figé => déterministe.
	var rng := RandomNumberGenerator.new()
	rng.seed = galaxy_seed

	# Bruit seedé : ondulation organique mais reproductible des bras.
	var noise := FastNoiseLite.new()
	noise.seed = galaxy_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.02

	for i in system_count:
		var sys := StarSystem.new()
		sys.id = i

		# Rayon normalisé (0..1) avec léger biais central, puis rayon réel.
		var rn := pow(rng.randf(), RADIAL_BIAS)
		var r := rn * radius

		# Bras assigné + angle de base enroulé selon le rayon.
		var arm := rng.randi() % ARMS
		var base_angle := float(arm) / float(ARMS) * TAU + rn * ARM_TWIST * TAU

		# Dispersion : ondulation par bruit + étalement gaussien autour du bras.
		var wave := noise.get_noise_2d(cos(base_angle) * r, sin(base_angle) * r)
		var angle := base_angle + wave * ARM_WAVE + rng.randfn(0.0, ARM_SPREAD)

		# Disque plus fin vers l'extérieur.
		var thickness := DISK_THICKNESS * (1.0 - rn * 0.6)
		var y := rng.randfn(0.0, 1.0) * thickness

		sys.position = Vector3(cos(angle) * r, y, sin(angle) * r)
		sys.seed_local = rng.randi()
		sys.star_type = _roll_star_type(rng)
		# Phase 19.5 : nom propre déterministe (palette = région galactique). RNG séparé dans
		# NameGenerator => la séquence ci-dessus est INCHANGÉE (positions/seeds reproductibles).
		sys.palette_id = NameGenerator.palette_for_galactic_position(sys.position)
		sys.name = NameGenerator.generate_name(sys.seed_local, sys.palette_id)
		data.systems.append(sys)

	return data

# Tirage pondéré du type spectral (M très commune, O très rare).
static func _roll_star_type(rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	if r < 0.01:
		return StarType.O
	elif r < 0.04:
		return StarType.B
	elif r < 0.10:
		return StarType.A
	elif r < 0.20:
		return StarType.F
	elif r < 0.35:
		return StarType.G
	elif r < 0.60:
		return StarType.K
	return StarType.M

# Couleur du point lumineux selon le type spectral.
static func star_color(star_type: int) -> Color:
	match star_type:
		StarType.O:
			return Color(0.62, 0.72, 1.0)
		StarType.B:
			return Color(0.74, 0.82, 1.0)
		StarType.A:
			return Color(0.92, 0.95, 1.0)
		StarType.F:
			return Color(1.0, 0.99, 0.92)
		StarType.G:
			return Color(1.0, 0.94, 0.72)
		StarType.K:
			return Color(1.0, 0.82, 0.55)
		StarType.M:
			return Color(1.0, 0.66, 0.50)
	return Color.WHITE

# Taille relative du point selon le type (multiplicateur, O géante -> M naine).
static func star_size(star_type: int) -> float:
	match star_type:
		StarType.O:
			return 1.6
		StarType.B:
			return 1.4
		StarType.A:
			return 1.2
		StarType.F:
			return 1.05
		StarType.G:
			return 1.0
		StarType.K:
			return 0.9
	return 0.8

# Lettre de classe spectrale (pour l'affichage / les noms de système).
static func star_type_letter(star_type: int) -> String:
	return TYPE_LETTERS[star_type]
