class_name SystemGenerator
extends RefCounted
## Génère un système stellaire 100% déterministe à partir du seed_local d'un
## système de la galaxie. Le star_type vient du système galaxie (cohérence
## visuelle avec la vue galaxie). Chaque planète reçoit son propre seed_local,
## réservé à la génération de détail en phase 3.

# Une planète du système (orbite circulaire dans le plan XZ autour de l'étoile).
class Planet:
	var id: int
	var orbit_radius: float
	var size: float
	var color: Color
	var orbit_speed: float   # vitesse angulaire en rad/s
	var phase: float         # angle initial en rad
	var seed_local: int      # réservé phase 3
	var name: String         # phase 19.5 : nom propre (palette du système)
	var moons: Array = []    # phase 14 : Array<MoonsGenerator.MoonData> (déterministe par seed_local)
	var ring = null          # phase 14 : MoonsGenerator.RingData ou null

# Données complètes d'un système.
class SystemData:
	var star_type: int
	var star_radius: float
	var star_color: Color
	var planets: Array = []  # éléments : Planet
	var name: String         # phase 19.5 : nom propre du système (pour l'affichage)
	var palette_id: int      # phase 19.5 : palette linguistique régionale (planètes/lunes cohérentes)

# --- Paramètres (constants => reproductibles) ---
const MIN_PLANETS := 1
const MAX_PLANETS := 8
const FIRST_ORBIT_GAP := 4.0   # distance surface étoile -> 1re orbite
const MIN_ORBIT_GAP := 2.5     # écart min entre orbites successives
const MAX_ORBIT_GAP := 6.0
const PLANET_MIN_SIZE := 0.25
const PLANET_MAX_SIZE := 1.1
const BASE_ORBIT_SPEED := 0.73  # vitesse angulaire de référence (ralenti ÷3 : « planètes trop rapides »)

# Rayon de l'étoile selon le type spectral (O géante -> M naine).
const STAR_RADII := [2.8, 2.4, 2.0, 1.7, 1.5, 1.2, 1.0]

## palette_id + system_name (phase 19.5) : la palette régionale est passée par l'appelant (qui a la
## POSITION du système) ; les planètes/lunes en héritent. Défauts => rétrocompatible.
static func generate(seed_local: int, star_type: int, palette_id: int = 0, system_name: String = "") -> SystemData:
	var d := SystemData.new()
	d.star_type = star_type
	d.star_color = GalaxyGenerator.star_color(star_type)
	d.star_radius = STAR_RADII[clampi(star_type, 0, STAR_RADII.size() - 1)]
	d.palette_id = palette_id
	d.name = system_name

	# Source d'aléa unique : l'ordre des tirages ci-dessous est figé => déterministe.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_local

	var count := rng.randi_range(MIN_PLANETS, MAX_PLANETS)
	var orbit := d.star_radius + FIRST_ORBIT_GAP
	for i in count:
		var p := Planet.new()
		p.id = i
		orbit += rng.randf_range(MIN_ORBIT_GAP, MAX_ORBIT_GAP)
		p.orbit_radius = orbit
		p.size = rng.randf_range(PLANET_MIN_SIZE, PLANET_MAX_SIZE)
		p.color = Color.from_hsv(rng.randf(), rng.randf_range(0.25, 0.7), rng.randf_range(0.6, 1.0))
		# Vitesse ~ képlérienne (plus lent vers l'extérieur) avec léger aléa.
		p.orbit_speed = BASE_ORBIT_SPEED / sqrt(p.orbit_radius) * rng.randf_range(0.85, 1.15)
		p.phase = rng.randf() * TAU
		p.seed_local = rng.randi()
		# Phase 19.5 : nom propre de la planète (palette du système). RNG séparé (NameGenerator).
		p.name = NameGenerator.generate_name(p.seed_local, palette_id)
		# Phase 14 : lunes + anneau déterministes (RNG séparé seedé par p.seed_local => ne
		# perturbe pas la séquence ci-dessus, donc planètes des phases 2-13 inchangées).
		p.moons = MoonsGenerator.generate_moons(p.seed_local)
		# Phase 19.5 : nom de lune = suffixe ordinal poétique du nom de la planète (« Prime/Seconde/… »).
		for mi in p.moons.size():
			p.moons[mi].name = NameGenerator.moon_name(p.name, mi, p.seed_local, palette_id)
		p.ring = MoonsGenerator.generate_ring(p.seed_local)
		d.planets.append(p)

	return d
