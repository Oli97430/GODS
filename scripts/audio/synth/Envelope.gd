class_name Envelope
extends RefCounted
## Phase 21 — modulations lentes : LFO sine (respiration des drones) + enveloppe AR (attack/release)
## pour les évènements ponctuels (tonalités lointaines sparse, coups de tonnerre). Échelle échantillon.

var _sr := 44100.0

# --- LFO ---
var _lfo_phase := 0.0
var _lfo_inc := 0.0

# --- Enveloppe Attack/Release (one-shot) ---
var _env := 0.0
var _atk := 0.0       # gain / échantillon en attaque
var _rel := 0.0       # gain / échantillon en release
var _state := 0       # 0 idle, 1 attack, 2 release

func _init(sample_rate := 44100.0) -> void:
	_sr = sample_rate

# LFO : fréquence (Hz). lfo() avance d'un échantillon et renvoie [-1, 1].
func set_lfo(freq: float) -> void:
	_lfo_inc = TAU * maxf(freq, 0.0) / _sr

func lfo() -> float:
	_lfo_phase += _lfo_inc
	if _lfo_phase >= TAU:
		_lfo_phase -= TAU
	return sin(_lfo_phase)

# Enveloppe AR : durées en secondes.
func set_ar(attack_s: float, release_s: float) -> void:
	_atk = 1.0 / maxf(attack_s * _sr, 1.0)
	_rel = 1.0 / maxf(release_s * _sr, 1.0)

func trigger() -> void:
	_state = 1

func is_active() -> bool:
	return _state != 0

# Avance l'enveloppe d'un échantillon, renvoie le niveau [0, 1].
func ar() -> float:
	if _state == 1:
		_env += _atk
		if _env >= 1.0:
			_env = 1.0
			_state = 2
	elif _state == 2:
		_env -= _rel
		if _env <= 0.0:
			_env = 0.0
			_state = 0
	return _env
