class_name SynthNoise
extends RefCounted
## Phase 21 — générateurs de bruit (nommé SynthNoise car `Noise` est une classe abstraite intégrée
## à Godot, base de FastNoiseLite). BLANC (plat), ROSE (-3 dB/oct, filtre économique de Paul Kellet),
## BRUN (-6 dB/oct, intégrateur borné). next() renvoie ~[-1, 1]. La texture n'est PAS seedée par défaut
## (bruit du moment = vivant) ; un seed optionnel ne sert qu'aux tests de reproductibilité.
## NB : l'enum s'appelle Kind (et non Color) car `Color` est un type intégré => collision de résolution.

enum Kind { WHITE, PINK, BROWN }

var kind := Kind.WHITE
var _rng := RandomNumberGenerator.new()
var _brown := 0.0
var _p0 := 0.0
var _p1 := 0.0
var _p2 := 0.0

func _init(k := Kind.WHITE, seed_val := 0) -> void:
	kind = k
	if seed_val != 0:
		_rng.seed = seed_val
	else:
		_rng.randomize()   # texture vivante (non reproductible) — conforme au brief

func _white() -> float:
	return _rng.randf() * 2.0 - 1.0

func next() -> float:
	match kind:
		Kind.PINK:
			var w := _white()
			# Filtre rose économique (Paul Kellet) : 3 pôles passe-bas additionnés.
			_p0 = 0.99765 * _p0 + w * 0.0990460
			_p1 = 0.96300 * _p1 + w * 0.2965164
			_p2 = 0.57000 * _p2 + w * 1.0526913
			return (_p0 + _p1 + _p2 + w * 0.1848) * 0.2
		Kind.BROWN:
			_brown += _white() * 0.02
			_brown = clampf(_brown, -1.0, 1.0)
			return _brown * 3.2   # compense la faible énergie du brun
	return _white()
