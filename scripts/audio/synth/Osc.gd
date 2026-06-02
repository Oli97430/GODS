class_name Osc
extends RefCounted
## Phase 21 — oscillateur mono à accumulateur de phase (sine / triangle / saw / square). next()
## avance d'UN échantillon et renvoie la valeur dans [-1, 1]. Léger : un accumulateur + une forme.
## La PHASE n'est pas seedée (texture vivante) ; seuls les PARAMÈTRES (fréquence) sont pilotés.

enum Wave { SINE, TRIANGLE, SAW, SQUARE }

var wave := Wave.SINE
var phase := 0.0            # [0, TAU)
var _inc := 0.0            # incrément de phase / échantillon
var _sr := 44100.0

func _init(sample_rate := 44100.0, freq := 220.0, w := Wave.SINE) -> void:
	_sr = sample_rate
	wave = w
	set_freq(freq)

func set_freq(f: float) -> void:
	_inc = TAU * maxf(f, 0.0) / _sr

func next() -> float:
	phase += _inc
	if phase >= TAU:
		phase -= TAU
	match wave:
		Wave.SINE:
			return sin(phase)
		Wave.TRIANGLE:
			return 4.0 * absf(phase / TAU - 0.5) - 1.0
		Wave.SAW:
			return phase / PI - 1.0
		Wave.SQUARE:
			return 1.0 if phase < PI else -1.0
	return 0.0
