class_name AmbientPlanet
extends AmbientLayer
## Phase 21 — ambiance PLANÈTE orbitale : drone « tinté » dont la PALETTE (fréquence fondamentale,
## partiel harmonique, couleur du filtre) est DÉTERMINISTE via seed_local (configure()). La phase et
## le bruit restent vivants (non reproductibles). Modulé par la nuit (set_night) : plus grave + calme.

var _ph1 := 0.0
var _ph2 := 0.0
var _ph3 := 0.0
var _inc1 := 0.0
var _inc2 := 0.0
var _inc3 := 0.0
var _brown := 0.0
var _lp := 0.0
var _lp_coef := 0.02
var _bph := 0.0
var _binc := 0.0
var _rng := RandomNumberGenerator.new()

# Palette (déterministe par seed).
var _base_freq := 60.0
var _ratio2 := 1.5
var _detune := 1.006
var _cutoff := 240.0
var _part_amp := 0.26
var _night := 0.0          # 0 jour .. 1 nuit (poussé par AudioEngine)

func _setup() -> void:
	stream.setup("Ambient_World", -11.0, SR, 0.3)
	_binc = TAU * 0.06 / SR
	_rng.randomize()
	_recompute()

# Palette sonore de la planète (fréquences/couleur figées par le seed ; musicalement bornées).
func configure(seed_local: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_local * 2654435761 + 9090
	_base_freq = rng.randf_range(46.0, 92.0)
	var ratios := [1.5, 1.3333, 1.6667, 2.0, 1.25]   # quinte / quarte / sixte / octave / tierce
	_ratio2 = ratios[rng.randi() % ratios.size()]
	_detune = rng.randf_range(1.004, 1.012)
	_cutoff = rng.randf_range(150.0, 430.0)
	_part_amp = rng.randf_range(0.18, 0.36)
	_recompute()

func set_night(darkness: float) -> void:
	_night = clampf(darkness, 0.0, 1.0)

func _modulate(_dt: float) -> void:
	_recompute()

func _recompute() -> void:
	var nf := 1.0 - 0.05 * _night          # nuit : pitch -5 %
	var f1 := _base_freq * nf
	_inc1 = TAU * f1 / SR
	_inc2 = TAU * f1 * _ratio2 / SR
	_inc3 = TAU * f1 * _detune / SR
	var cut := _cutoff * (1.0 - 0.5 * _night)   # nuit : plus sombre
	_lp_coef = clampf(TAU * cut / SR, 0.002, 0.5)

func _fill(buf: PackedVector2Array, frames: int) -> void:
	if gain < 0.0008:                    # couche muette : zéro synthèse (perf)
		for i in frames:
			buf[i] = Vector2.ZERO
		return
	var amp := (1.0 - 0.25 * _night) * gain   # nuit : plus calme
	var ph1 := _ph1
	var ph2 := _ph2
	var ph3 := _ph3
	var brown := _brown
	var lp := _lp
	var bph := _bph
	var coef := _lp_coef
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
		var breath := 0.74 + 0.14 * sin(bph)
		var drone := (sin(ph1) * 0.5 + sin(ph2) * _part_amp + sin(ph3) * 0.42) * breath
		brown += (_rng.randf() * 2.0 - 1.0) * 0.02
		brown = clampf(brown, -1.0, 1.0)
		lp += (brown * 3.2 - lp) * coef
		var s := (drone * 0.42 + lp * 0.09) * amp
		buf[i] = Vector2(s, s)
	_ph1 = ph1
	_ph2 = ph2
	_ph3 = ph3
	_brown = brown
	_lp = lp
	_bph = bph
