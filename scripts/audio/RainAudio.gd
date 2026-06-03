class_name RainAudio
extends Node
## Phase 21 — texture de PLUIE procédurale (bus Ambient_Weather) : corps de bruit filtré (chuintement
## doux) + crépitement de gouttes épars en stéréo, niveau piloté par WeatherSystem.precipitation.
## Démarre muet ; monte/descend en douceur avec la pluie. Jamais agressif.

const SR := 44100.0

var stream: SynthStream
var _amount := 0.0          # cible (precipitation)
var _cur := 0.0            # niveau lissé
var _hp: Biquad
var _lp: Biquad
var _hpR: Biquad          # 2e chaîne indépendante (droite) => chuintement large
var _lpR: Biquad
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	stream = SynthStream.new()
	add_child(stream)
	stream.setup("Ambient_Weather", -9.0, SR, 0.3)
	stream.fill_func = _fill
	_hp = Biquad.new(SR)
	_hp.set_params(Biquad.Type.HIGHPASS, 700.0, 0.6)
	_lp = Biquad.new(SR)
	_lp.set_params(Biquad.Type.LOWPASS, 6500.0, 0.7)
	_hpR = Biquad.new(SR)
	_hpR.set_params(Biquad.Type.HIGHPASS, 700.0, 0.6)
	_lpR = Biquad.new(SR)
	_lpR.set_params(Biquad.Type.LOWPASS, 6500.0, 0.7)
	_rng.randomize()
	stream.start()

func set_amount(p: float) -> void:
	_amount = clampf(p, 0.0, 1.0)

func _process(dt: float) -> void:
	_cur = move_toward(_cur, _amount, 0.5 * dt)

func _fill(buf: PackedVector2Array, frames: int) -> void:
	var g := _cur
	if g < 0.001:
		for i in frames:
			buf[i] = Vector2.ZERO
		return
	for i in frames:
		# Corps : DEUX chaînes passe-haut→passe-bas INDÉPENDANTES L/R => chuintement large et enveloppant.
		var bodyL := _lp.process(_hp.process(_rng.randf() * 2.0 - 1.0)) * 0.7
		var bodyR := _lpR.process(_hpR.process(_rng.randf() * 2.0 - 1.0)) * 0.7
		# Gouttes : impulsions brèves éparses, indépendantes L/R. Densité ~ pluie.
		var dl := 0.0
		var dr := 0.0
		if _rng.randf() < 0.0045 * (0.2 + 0.8 * g):
			dl = (_rng.randf() * 2.0 - 1.0) * 0.6
		if _rng.randf() < 0.0045 * (0.2 + 0.8 * g):
			dr = (_rng.randf() * 2.0 - 1.0) * 0.6
		buf[i] = Vector2((bodyL + dl) * g * 0.5, (bodyR + dr) * g * 0.5)
