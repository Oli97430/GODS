class_name ThunderAudio
extends Node
## Phase 21 — TONNERRE lointain (bus Ambient_Weather) : bursts de bruit TRÈS passe-bas (étouffé,
## distant) à longue traîne, déclenchés sporadiquement selon WeatherSystem.storm. Contemplatif :
## jamais un « boum » sec — montée douce, grondement sourd, décrue lente. Cohérent en timing avec
## les flashs visuels (phase 13) sans être les MÊMES évènements (storm-gated).

const SR := 44100.0

var stream: SynthStream
var _env: Envelope
var _lp: Biquad
var _lpR: Biquad          # 2e passe-bas indépendant (droite) => roulement large
var _brown := 0.0
var _brownR := 0.0
var _rng := RandomNumberGenerator.new()
var _storm := 0.0
var _timer := 1.0

func _ready() -> void:
	stream = SynthStream.new()
	add_child(stream)
	stream.setup("Ambient_Weather", -8.0, SR, 0.35)
	stream.fill_func = _fill
	_env = Envelope.new(SR)
	_env.set_ar(0.5, 3.5)                 # montée lente + longue traîne
	_lp = Biquad.new(SR)
	_lp.set_params(Biquad.Type.LOWPASS, 280.0, 0.6)   # très étouffé => lointain
	_lpR = Biquad.new(SR)
	_lpR.set_params(Biquad.Type.LOWPASS, 280.0, 0.6)
	_rng.randomize()
	stream.start()

func set_storm(s: float) -> void:
	_storm = clampf(s, 0.0, 1.0)

func _process(dt: float) -> void:
	# Déclenchement Poisson grossier : on tire à intervalle régulier, proba ~ storm. Pas pendant une traîne.
	_timer -= dt
	if _timer <= 0.0:
		_timer = 0.9
		if _storm > 0.05 and not _env.is_active() and _rng.randf() < _storm * 0.22:
			_env.set_ar(_rng.randf_range(0.35, 0.8), _rng.randf_range(2.5, 4.5))
			_env.trigger()

func _fill(buf: PackedVector2Array, frames: int) -> void:
	if not _env.is_active():
		for i in frames:
			buf[i] = Vector2.ZERO
		return
	var loud := 0.3 + 0.6 * _storm
	for i in frames:
		var e := _env.ar()
		_brown += (_rng.randf() * 2.0 - 1.0) * 0.02
		_brown = clampf(_brown, -1.0, 1.0)
		_brownR += (_rng.randf() * 2.0 - 1.0) * 0.02
		_brownR = clampf(_brownR, -1.0, 1.0)
		var rL := _lp.process(_brown * 3.2) * e
		var rR := _lpR.process(_brownR * 3.2) * e   # grondement décorrélé L/R => large
		var sL := rL * 0.5 * loud
		var sR := rR * 0.5 * loud
		buf[i] = Vector2(sL, sR)
