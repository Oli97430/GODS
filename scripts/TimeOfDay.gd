extends Node
## Autoload : UNIQUE source de vérité du temps simulé et de la direction du soleil, pour
## l'orbite ET la surface (jamais deux calculs de rotation concurrents qui dériveraient).
##
## Modèle : l'étoile est dans une direction INERTIELLE fixe (SUN_WORLD_DIR). La planète
## tourne sur son axe d'un angle θ(t) = offset + (temps simulé / période) · TAU. Un point
## body-fixe (lat/long du point d'atterrissage) a, à l'instant t, la direction inertielle
## p = R(θ)·landing_dir. Jour si SUN_WORLD_DIR·p > 0. La sphère orbitale tourne du MÊME R(θ)
## sous un soleil fixe => face éclairée en orbite ⇔ heure locale au sol (cohérence garantie).
##
## Tout est dérivable du seed (période, axe, heure de spawn) => même seed + même durée = même état.

# Direction INERTIELLE vers l'étoile. Surtout équatoriale (perpendiculaire à l'axe ~Y) pour
# un vrai cycle jour/nuit aux basses latitudes ; les pôles restent en demi-jour (réaliste).
const SUN_WORLD_DIR := Vector3(0.985, 0.10, 0.14)

var time_scale := 1.0           # secondes simulées par seconde réelle (×1 par défaut ; réglable : pause/1/10/60/600)
var simulated_seconds := 0.0    # temps simulé courant

var _rotation_period := 600.0   # secondes simulées pour un tour complet (dérivé du seed)
var _spin_axis := Vector3.UP    # axe de rotation (léger tilt dérivé du seed)
var _spin_offset := 0.0         # angle initial (dérivé du seed)

func _ready() -> void:
	_spin_axis = SUN_WORLD_DIR  # placeholder écrasé par configure_planet ; évite axe nul

func _process(dt: float) -> void:
	simulated_seconds += dt * time_scale

# Paramètres de rotation + heure de spawn d'une planète, DÉTERMINISTES par seed. Appelé à
# l'entrée en orbite de la planète (avant la descente).
func configure_planet(seed_local: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_local + 4242
	_rotation_period = rng.randf_range(240.0, 1200.0)         # 4–20 min simulées / tour
	var tilt := rng.randf_range(-0.40, 0.40)                  # ~±23° d'inclinaison d'axe
	var az := rng.randf() * TAU
	_spin_axis = Vector3(sin(tilt) * cos(az), cos(tilt), sin(tilt) * sin(az)).normalized()
	_spin_offset = rng.randf() * TAU
	simulated_seconds = rng.randf_range(0.0, _rotation_period)  # heure de départ dérivée du seed

func rotation_period() -> float:
	return _rotation_period

# Angle de rotation courant de la planète (radians). maxf garde contre une période 0/non configurée
# (évite inf/NaN propagés à toute la chaîne d'éclairage si appelé avant configure_planet).
func spin_angle() -> float:
	return _spin_offset + (simulated_seconds / maxf(_rotation_period, 0.001)) * TAU

# Rotation R(θ) de la planète : body -> inertiel. Pilote la sphère orbitale ET le soleil au sol.
func spin_basis() -> Basis:
	return Basis(_spin_axis.normalized(), spin_angle())

# Direction inertielle vers l'étoile (repère système) — pour l'orbite (soleil fixe).
func get_sun_direction_world() -> Vector3:
	return SUN_WORLD_DIR

# Direction VERS le soleil dans le repère TANGENT local au point d'atterrissage (body-fixe).
# +Y = up local. Utilisée par la lumière directionnelle + les shaders au sol.
func get_sun_direction_local(landing_dir: Vector3) -> Vector3:
	var p := spin_basis() * landing_dir.normalized()         # direction inertielle du point
	return FloatingOrigin.tangent_basis(p).inverse() * SUN_WORLD_DIR

# Sinus de l'altitude du soleil au point (= SUN·up). > 0 jour, < 0 nuit, ~0 horizon.
func get_sun_altitude(landing_dir: Vector3) -> float:
	return SUN_WORLD_DIR.dot(spin_basis() * landing_dir.normalized())

# Fraction du jour [0,1) : 0 = minuit, 0.25 = aube, 0.5 = midi, 0.75 = crépuscule.
func day_fraction() -> float:
	return fposmod(spin_angle(), TAU) / TAU

# Saute EN AVANT jusqu'à la prochaine occurrence d'une fraction de jour (montre : aube/midi/minuit).
func set_day_fraction(frac: float) -> void:
	var target := frac * TAU
	var cur := fposmod(spin_angle(), TAU)
	var delta := target - cur
	if delta < 0.0:
		delta += TAU   # toujours avancer (jamais de temps simulé négatif)
	simulated_seconds += delta / TAU * _rotation_period
