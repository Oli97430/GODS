class_name LightningEffect
extends Node
## Planificateur d'éclairs DÉTERMINISTE (pas d'effet visuel propre : il renvoie une intensité
## de flash [0..1] que SkyManager applique au ciel + ambiant). Déclencheurs « Poisson » :
## le temps simulé est découpé en fenêtres ; un hash déterministe (fenêtre, seed) décide si un
## éclair survient (probabilité ∝ storm) et son instant ; l'intensité est un bref pulse à
## double scintillement. Une seule source de temps (TimeOfDay) ; même temps + seed = même flash.

const INTERVAL := 3.0      # fenêtre (s simulées) entre tirages
const FLASH_DUR := 0.32    # durée d'un éclair (s simulées)
const MAX_PROB := 0.75     # probabilité d'éclair par fenêtre à storm = 1

var _seed := 0

func configure(seed_local: int) -> void:
	_seed = seed_local

# Intensité de flash courante [0..1] (0 hors éclair / hors orage). Déterministe.
func current_flash() -> float:
	if not WeatherSystem.is_configured():
		return 0.0
	var storm := WeatherSystem.get_storm()
	if storm < 0.05:
		return 0.0
	var t := TimeOfDay.simulated_seconds
	var idx := int(floor(t / INTERVAL))
	var flash := 0.0
	# Fenêtre courante + précédente (un éclair peut chevaucher la frontière).
	for k in [idx, idx - 1]:
		if _hash01(k) < storm * MAX_PROB:
			var offset := _hash01(k * 1009 + 7) * (INTERVAL - FLASH_DUR)
			var dt := t - (float(k) * INTERVAL + offset)
			if dt >= 0.0 and dt < FLASH_DUR:
				flash = maxf(flash, _pulse(dt / FLASH_DUR))
	return flash

# Pulse d'éclair : pic vif initial + petit second scintillement, puis extinction.
func _pulse(x: float) -> float:
	var a := exp(-x * 16.0)
	var b := 0.45 * exp(-(x - 0.38) * (x - 0.38) * 70.0)
	return clampf(a + b, 0.0, 1.0)

# Hash déterministe (fenêtre, seed) -> [0,1[. Hash entier PUR : zéro allocation (appelé plusieurs
# fois/frame sous orage — un RandomNumberGenerator.new() par appel saturait l'allocateur).
func _hash01(n: int) -> float:
	var h := hash(Vector2i(n, _seed))
	return float(h & 0x7fffffff) / 2147483647.0
