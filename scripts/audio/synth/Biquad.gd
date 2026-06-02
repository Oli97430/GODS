class_name Biquad
extends RefCounted
## Phase 21 — filtre biquad (formes RBJ cookbook) : LOWPASS / HIGHPASS / BANDPASS. process() filtre
## UN échantillon (Direct Form I). set_params() recalcule les coefficients (fréquence de coupure + Q).
## Léger et stable ; utilisé pour colorer bruit (vent, pluie) et adoucir les drones.

enum Type { LOWPASS, HIGHPASS, BANDPASS }

var _sr := 44100.0
var _b0 := 1.0
var _b1 := 0.0
var _b2 := 0.0
var _a1 := 0.0
var _a2 := 0.0
var _x1 := 0.0
var _x2 := 0.0
var _y1 := 0.0
var _y2 := 0.0

func _init(sample_rate := 44100.0) -> void:
	_sr = sample_rate

func set_params(type: int, freq: float, q := 0.707) -> void:
	freq = clampf(freq, 20.0, _sr * 0.45)
	var w0 := TAU * freq / _sr
	var cw := cos(w0)
	var sw := sin(w0)
	var alpha := sw / (2.0 * maxf(q, 0.05))
	var b0 := 1.0
	var b1 := 0.0
	var b2 := 0.0
	var a0 := 1.0 + alpha
	var a1 := -2.0 * cw
	var a2 := 1.0 - alpha
	match type:
		Type.LOWPASS:
			b0 = (1.0 - cw) * 0.5
			b1 = 1.0 - cw
			b2 = (1.0 - cw) * 0.5
		Type.HIGHPASS:
			b0 = (1.0 + cw) * 0.5
			b1 = -(1.0 + cw)
			b2 = (1.0 + cw) * 0.5
		Type.BANDPASS:
			b0 = alpha
			b1 = 0.0
			b2 = -alpha
	_b0 = b0 / a0
	_b1 = b1 / a0
	_b2 = b2 / a0
	_a1 = a1 / a0
	_a2 = a2 / a0

func process(x: float) -> float:
	var y := _b0 * x + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2
	_x2 = _x1
	_x1 = x
	_y2 = _y1
	_y1 = y
	return y
