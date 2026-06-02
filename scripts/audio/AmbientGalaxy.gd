class_name AmbientGalaxy
extends AmbientLayer
## Phase 21 — ambiance GALAXIE : drone cosmique sourd (deux sines graves très proches => battement
## lent + bruit brun filtré bas) et quelques TONALITÉS hautes lointaines, rares, à enveloppes très
## lentes (immensité froide). Non positionnel (stéréo doux). Le chemin de drone est INLINÉ (boucle
## temps réel : zéro appel de méthode par échantillon) ; les tonalités rares utilisent Osc + Envelope.

# Drone (accumulateurs de phase inlinés).
var _ph1 := 0.0
var _ph2 := 0.0
var _inc1 := 0.0
var _inc2 := 0.0
var _brown := 0.0     # état du bruit brun
var _lp := 0.0        # état du passe-bas 1-pôle sur le bruit
var _breath := 0.0    # LFO de respiration (phase)
var _binc := 0.0
var _rng := RandomNumberGenerator.new()

# Tonalités hautes sparse (Osc + Envelope AR).
var _tones: Array = []
var _tone_timer := 5.0
var _tone_rng := RandomNumberGenerator.new()

func _setup() -> void:
	stream.setup("Ambient_World", -11.0, SR, 0.3)
	_inc1 = TAU * 46.0 / SR
	_inc2 = TAU * 46.55 / SR        # léger désaccord => battement ~0.5 Hz
	_binc = TAU * 0.05 / SR         # respiration ~20 s
	_rng.randomize()
	_tone_rng.randomize()
	for i in 3:
		_tones.append({"osc": Osc.new(SR, 1000.0, Osc.Wave.SINE), "env": _make_env()})

func _make_env() -> Envelope:
	var e := Envelope.new(SR)
	e.set_ar(4.0, 8.0)              # montée 4 s, descente 8 s (très lent)
	return e

func _fill(buf: PackedVector2Array, frames: int) -> void:
	var g := gain
	if g < 0.0008:                       # couche muette : zéro synthèse (perf)
		for i in frames:
			buf[i] = Vector2.ZERO
		return
	var ph1 := _ph1
	var ph2 := _ph2
	var brown := _brown
	var lp := _lp
	var bph := _breath
	# Tonalités actives à ce buffer (évite d'itérer les inactives par échantillon).
	var live: Array = []
	for t in _tones:
		if t.env.is_active():
			live.append(t)
	for i in frames:
		ph1 += _inc1
		if ph1 >= TAU:
			ph1 -= TAU
		ph2 += _inc2
		if ph2 >= TAU:
			ph2 -= TAU
		bph += _binc
		if bph >= TAU:
			bph -= TAU
		var breath := 0.7 + 0.18 * sin(bph)
		var drone := (sin(ph1) + sin(ph2)) * 0.5 * breath
		# Bruit brun (intégrateur borné) + passe-bas 1-pôle.
		brown += (_rng.randf() * 2.0 - 1.0) * 0.02
		brown = clampf(brown, -1.0, 1.0)
		lp += (brown * 3.2 - lp) * 0.02
		var s := drone * 0.5 + lp * 0.13
		for t in live:
			s += t.osc.next() * t.env.ar() * 0.06
		s *= g
		buf[i] = Vector2(s, s)
	_ph1 = ph1
	_ph2 = ph2
	_brown = brown
	_lp = lp
	_breath = bph

func _modulate(dt: float) -> void:
	_tone_timer -= dt
	if _tone_timer <= 0.0:
		_tone_timer = _tone_rng.randf_range(7.0, 16.0)
		for t in _tones:
			if not t.env.is_active():
				t.osc.set_freq(_tone_rng.randf_range(700.0, 1900.0))
				t.env.trigger()
				break
