class_name AmbientSystem
extends AmbientLayer
## Phase 21 — ambiance SYSTÈME : drone moyen plus CHALEUREUX qu'en galaxie (fondamentale + quinte +
## léger battement), respiration LFO lente. Plus enveloppant, plus calme (pas de tonalités hautes).
## Chemin inliné (temps réel). Non positionnel (stéréo doux).

var _ph1 := 0.0
var _ph2 := 0.0
var _ph3 := 0.0
var _inc1 := 0.0
var _inc2 := 0.0
var _inc3 := 0.0
var _brown := 0.0
var _lp := 0.0
var _bph := 0.0
var _binc := 0.0
var _rng := RandomNumberGenerator.new()

func _setup() -> void:
	stream.setup("Ambient_World", -11.0, SR, 0.3)
	_inc1 = TAU * 72.0 / SR        # fondamentale chaude
	_inc2 = TAU * 108.0 / SR       # quinte (×1.5)
	_inc3 = TAU * 72.7 / SR        # battement lent (~0.7 Hz)
	_binc = TAU * 0.07 / SR        # respiration ~14 s
	_rng.randomize()

func _fill(buf: PackedVector2Array, frames: int) -> void:
	var g := gain
	if g < 0.0008:                       # couche muette : zéro synthèse (perf)
		for i in frames:
			buf[i] = Vector2.ZERO
		return
	var ph1 := _ph1
	var ph2 := _ph2
	var ph3 := _ph3
	var brown := _brown
	var lp := _lp
	var bph := _bph
	for i in frames:
		ph1 += _inc1
		if ph1 >= TAU:
			ph1 -= TAU
		ph2 += _inc2
		if ph2 >= TAU:
			ph2 -= TAU
		ph3 += _inc3
		if ph3 >= TAU:
			ph3 -= TAU
		bph += _binc
		if bph >= TAU:
			bph -= TAU
		var breath := 0.72 + 0.16 * sin(bph)
		var drone := (sin(ph1) * 0.5 + sin(ph2) * 0.28 + sin(ph3) * 0.45) * breath
		brown += (_rng.randf() * 2.0 - 1.0) * 0.02
		brown = clampf(brown, -1.0, 1.0)
		lp += (brown * 3.2 - lp) * 0.015
		var s := (drone * 0.42 + lp * 0.10) * g
		buf[i] = Vector2(s, s)
	_ph1 = ph1
	_ph2 = ph2
	_ph3 = ph3
	_brown = brown
	_lp = lp
	_bph = bph
