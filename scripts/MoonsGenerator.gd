class_name MoonsGenerator
extends RefCounted
## Génère, de façon 100% DÉTERMINISTE depuis le seed_local d'une planète, ses lunes (0 à 4,
## biaisé vers peu) et son éventuel anneau. Tailles/rayons exprimés RELATIVEMENT au rayon de
## la planète (sans unité) => mêmes valeurs interprétées à toutes les échelles (système, orbite
## proche, surface). Orbites circulaires à inclinaison fixe ; position = f(TimeOfDay) ailleurs.

# Une lune : mini-planète en orbite circulaire inclinée.
class MoonData:
	var seed_local: int        # graine propre (mesh via PlanetGenerator)
	var name: String           # phase 19.5 : nom (suffixe ordinal du nom de la planète parente)
	var size_rel: float        # rayon lune / rayon planète
	var orbit_rel: float       # rayon orbital / rayon planète
	var period: float          # secondes simulées par révolution
	var inclination: float     # rad : tilt du plan orbital
	var node_angle: float      # rad : orientation du nœud (varie l'axe du tilt)
	var phase: float           # rad : angle initial sur l'orbite
	var tidal_locked: bool     # même face vers la planète
	var spin_period: float     # période de rotation propre (= period si tidal_locked)

# Un anneau planétaire (disque mince).
class RingData:
	var inner_rel: float       # rayon interne / rayon planète
	var outer_rel: float       # rayon externe / rayon planète
	var tilt: float            # rad : inclinaison du plan de l'anneau
	var tint: Color
	var opacity: float
	var density_seed: int

# Lunes d'une planète (Array<MoonData>), déterministes.
static func generate_moons(planet_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = planet_seed + 5150
	var r := rng.randf()
	var count := 0
	if r < 0.45:
		count = 0
	elif r < 0.75:
		count = 1
	elif r < 0.92:
		count = 2
	elif r < 0.99:
		count = 3
	else:
		count = 4

	var moons := []
	for i in count:
		var m := MoonData.new()
		m.seed_local = rng.randi()
		m.size_rel = rng.randf_range(0.12, 0.34)
		# Plus loin pour les lunes successives (évite les chevauchements d'orbite).
		m.orbit_rel = rng.randf_range(3.5, 7.0) + float(i) * 2.6
		m.inclination = rng.randf_range(-0.45, 0.45)
		m.node_angle = rng.randf() * TAU
		m.phase = rng.randf() * TAU
		# Période ~ képlérienne simplifiée (plus loin = plus lent), en secondes simulées.
		m.period = 90.0 * pow(m.orbit_rel, 1.5) * rng.randf_range(0.85, 1.15)
		m.tidal_locked = rng.randf() < 0.7
		m.spin_period = m.period if m.tidal_locked else rng.randf_range(20.0, 120.0)
		moons.append(m)
	return moons

# Anneau d'une planète (RingData) ou null (~20% des planètes en ont un).
static func generate_ring(planet_seed: int):
	var rng := RandomNumberGenerator.new()
	rng.seed = planet_seed + 6260
	if rng.randf() >= 0.20:
		return null
	var ring := RingData.new()
	ring.inner_rel = rng.randf_range(1.4, 1.9)
	ring.outer_rel = ring.inner_rel + rng.randf_range(0.6, 1.6)
	ring.tilt = rng.randf_range(0.0, 0.5)
	ring.tint = Color.from_hsv(rng.randf_range(0.05, 0.12), rng.randf_range(0.10, 0.40), rng.randf_range(0.7, 1.0))
	ring.opacity = rng.randf_range(0.35, 0.70)
	ring.density_seed = rng.randi()
	return ring

# Angle orbital courant d'une lune (rad), dérivé de l'horloge simulée unique.
static func orbital_angle(m: MoonData, simulated_seconds: float) -> float:
	return m.phase + TAU * (simulated_seconds / m.period)

# Position de la lune RELATIVE au centre de la planète, en unités de rayon planète, dans le
# repère inertiel (non tournant). Plan orbital incliné de 'inclination' autour de l'axe défini
# par 'node_angle'. Mêmes formules à toutes les échelles => cohérence garantie.
static func orbital_offset_rel(m: MoonData, simulated_seconds: float) -> Vector3:
	var a := orbital_angle(m, simulated_seconds)
	var flat := Vector3(cos(a), 0.0, sin(a)) * m.orbit_rel
	# Axe d'inclinaison horizontal orienté par node_angle, puis rotation du plan.
	var axis := Vector3(cos(m.node_angle), 0.0, sin(m.node_angle))
	return flat.rotated(axis, m.inclination)
