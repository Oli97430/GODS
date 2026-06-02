extends Node
## Autoload : météo LOCALE et CONTINUE, source unique de l'état météo. Quatre paramètres dans
## [0..1] — cloud_coverage, precipitation, wind, storm — échantillonnés d'un champ fbm fonction
## de (landing_dir, TimeOfDay.simulated_seconds), seedé par le seed_local de la planète. Pas
## d'états discrets : seulement des curseurs qui évoluent en douceur (le champ dérive dans le
## temps comme des fronts). DÉTERMINISTE : même planète + même point + même temps = même météo.
## Une seule source de temps (TimeOfDay) ; aucun timer concurrent.

# Tunables (réglables).
const SPATIAL_SCALE := 2.2                       # variation entre régions de la planète
const TIME_SPEED := 0.0035                        # vitesse de dérive des fronts (bruit/s simulée)
const DRIFT_DIR := Vector3(1.0, 0.3, -0.6)        # advection (déplacement des fronts)
const ORBIT_REF := Vector3(3.0, 1.0, 2.0)         # point de référence pour la couverture globale orbitale

var _cov_noise: FastNoiseLite
var _rain_noise: FastNoiseLite
var _wind_noise: FastNoiseLite
var _storm_noise: FastNoiseLite

# Biais par planète (dérivés du seed) : humide(+)/aride(-), orageuse, ventée.
var _coverage_bias := 0.0
var _storm_bias := 0.0
var _wind_bias := 0.0
var _configured := false

var _landing_dir := Vector3.UP   # point d'échantillonnage au sol (fixé à l'atterrissage)

# État courant (mis à jour chaque frame ; getters renvoient ces valeurs).
var _coverage := 0.4
var _precip := 0.0
var _wind := 0.2
var _storm := 0.0
var _orbit_coverage := 0.4

# Forçage de test (montre, phase 13) : 0 = auto (bruit), 1..3 = états imposés pour validation.
const FORCE_NAMES := ["Auto", "Couvert", "Pluie", "Orage"]
var _force_mode := 0

func _make_noise(seed_val: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_val
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 3
	n.frequency = 1.0
	return n

# Configure le champ météo d'une planète (DÉTERMINISTE par seed). Appelé à l'entrée en orbite.
func configure_planet(seed_local: int) -> void:
	_cov_noise = _make_noise(seed_local + 101)
	_rain_noise = _make_noise(seed_local + 202)
	_wind_noise = _make_noise(seed_local + 303)
	_storm_noise = _make_noise(seed_local + 404)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_local + 7777
	_coverage_bias = rng.randf_range(-0.30, 0.35)   # tendance climatique de la planète
	_storm_bias = rng.randf_range(-0.25, 0.25)
	_wind_bias = rng.randf_range(-0.10, 0.20)
	_configured = true
	_sample_now()

# Point d'échantillonnage au sol (lat/long fixe du point d'atterrissage). Appelé à l'atterrissage.
func set_location(landing_dir: Vector3) -> void:
	_landing_dir = landing_dir.normalized()
	_sample_now()

func _process(_dt: float) -> void:
	if _configured:
		_sample_now()

# Recalcule les 4 paramètres pour (lieu, temps) courants. Pur => déterministe + rebase-invariant.
func _sample_now() -> void:
	if not _configured:
		return
	var t := TimeOfDay.simulated_seconds * TIME_SPEED
	var drift := DRIFT_DIR * t
	var p := _landing_dir * SPATIAL_SCALE + drift

	_coverage = clampf(_remap(_cov_noise.get_noise_3dv(p)) + _coverage_bias, 0.0, 1.0)
	# La pluie nécessite des nuages (synergie émergente, pas d'état discret).
	var rain_raw := _remap(_rain_noise.get_noise_3dv(p + Vector3(11.0, 0.0, 0.0)))
	_precip = clampf(rain_raw * smoothstep(0.45, 0.85, _coverage), 0.0, 1.0)
	# L'orage nécessite couverture lourde + pluie soutenue.
	var storm_raw := _remap(_storm_noise.get_noise_3dv(p + Vector3(0.0, 7.0, 0.0)))
	_storm = clampf((storm_raw + _storm_bias) * smoothstep(0.55, 0.95, _coverage) * smoothstep(0.30, 0.80, _precip), 0.0, 1.0)
	# Vent : propre + renforcé par l'orage.
	var wind_raw := _remap(_wind_noise.get_noise_3dv(p + Vector3(0.0, 0.0, 5.0)))
	_wind = clampf(wind_raw * 0.7 + _wind_bias + _storm * 0.4, 0.0, 1.0)

	# Orbite : couverture GLOBALE variant dans le temps (point de référence fixe + dérive).
	_orbit_coverage = clampf(_remap(_cov_noise.get_noise_3dv(ORBIT_REF + drift)) + _coverage_bias, 0.0, 1.0)
	_apply_force()

# Forçage manuel (montre) : impose un état météo pour la validation (0 = auto, pas d'override).
func _apply_force() -> void:
	match _force_mode:
		1:  # couvert sec
			_coverage = 0.85; _precip = 0.05; _storm = 0.0; _wind = 0.45; _orbit_coverage = 0.85
		2:  # pluie
			_coverage = 0.92; _precip = 0.70; _storm = 0.12; _wind = 0.60; _orbit_coverage = 0.92
		3:  # orage
			_coverage = 0.97; _precip = 0.90; _storm = 0.90; _wind = 0.90; _orbit_coverage = 0.97

func set_force_mode(m: int) -> void:
	_force_mode = clampi(m, 0, FORCE_NAMES.size() - 1)
	_sample_now()

func get_force_mode() -> int:
	return _force_mode

func force_mode_name() -> String:
	return FORCE_NAMES[_force_mode]

func _remap(n: float) -> float:
	return n * 0.5 + 0.5

# --- API ---
func get_cloud_coverage() -> float: return _coverage
func get_precipitation() -> float: return _precip
func get_wind() -> float: return _wind
func get_storm() -> float: return _storm
func get_orbit_coverage() -> float: return _orbit_coverage
func is_configured() -> bool: return _configured

# Échantillon LOCAL ponctuel à une direction donnée + temps courant (pour comparer 2 lieux / debug).
func sample_at(landing_dir: Vector3) -> Dictionary:
	if not _configured:
		return {"coverage": 0.0, "precip": 0.0, "wind": 0.0, "storm": 0.0}
	var t := TimeOfDay.simulated_seconds * TIME_SPEED
	var p := landing_dir.normalized() * SPATIAL_SCALE + DRIFT_DIR * t
	var cov := clampf(_remap(_cov_noise.get_noise_3dv(p)) + _coverage_bias, 0.0, 1.0)
	var rain := clampf(_remap(_rain_noise.get_noise_3dv(p + Vector3(11.0, 0.0, 0.0))) * smoothstep(0.45, 0.85, cov), 0.0, 1.0)
	var stm := clampf((_remap(_storm_noise.get_noise_3dv(p + Vector3(0.0, 7.0, 0.0))) + _storm_bias) * smoothstep(0.55, 0.95, cov) * smoothstep(0.30, 0.80, rain), 0.0, 1.0)
	var wnd := clampf(_remap(_wind_noise.get_noise_3dv(p + Vector3(0.0, 0.0, 5.0))) * 0.7 + _wind_bias + stm * 0.4, 0.0, 1.0)
	return {"coverage": cov, "precip": rain, "wind": wnd, "storm": stm}
