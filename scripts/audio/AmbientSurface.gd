class_name AmbientSurface
extends AmbientLayer
## Phase 21 — ambiance SURFACE : drone planète ATTÉNUÉ (palette par seed) + VENT procédural (bruit
## passe-bande dont la couleur dépend de la planète ; intensité pilotée par WeatherSystem.wind). LFO
## de respiration. Modulé par la nuit (plus calme). NB : la variation de filtrage PAR BIOME (vs par
## planète) est laissée en option (nécessiterait l'échantillonnage du biome sous le joueur en continu).

var _ph1 := 0.0
var _ph2 := 0.0
var _inc1 := 0.0
var _inc2 := 0.0
var _brown := 0.0
var _lp := 0.0
var _bph := 0.0
var _binc := 0.0
var _rng := RandomNumberGenerator.new()

var _base_freq := 52.0
var _wind_bp: Biquad          # passe-bande qui colore le vent
var _wind_center := 520.0
var _wind_amt := 0.2          # cible (WeatherSystem.wind)
var _wind_cur := 0.0          # lissé
var _night := 0.0

func _setup() -> void:
	stream.setup("Ambient_World", -11.0, SR, 0.3)
	_binc = TAU * 0.045 / SR
	_rng.randomize()
	_wind_bp = Biquad.new(SR)
	_wind_bp.set_params(Biquad.Type.BANDPASS, _wind_center, 1.1)
	_recompute()

# Palette de surface (drone + couleur du vent), déterministe par seed planète.
func configure(seed_local: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_local * 2654435761 + 5151
	_base_freq = rng.randf_range(42.0, 78.0)
	_wind_center = rng.randf_range(360.0, 900.0)   # « voix » du vent propre à la planète
	if _wind_bp:
		_wind_bp.set_params(Biquad.Type.BANDPASS, _wind_center, 1.1)
	_recompute()

func set_wind(w: float) -> void:
	_wind_amt = clampf(w, 0.0, 1.0)

func set_night(d: float) -> void:
	_night = clampf(d, 0.0, 1.0)

func _recompute() -> void:
	var nf := 1.0 - 0.04 * _night
	_inc1 = TAU * _base_freq * nf / SR
	_inc2 = TAU * _base_freq * 1.5 * nf / SR

func _modulate(dt: float) -> void:
	_recompute()
	_wind_cur = move_toward(_wind_cur, _wind_amt, 0.5 * dt)   # vent lissé (pas de saut)

func _fill(buf: PackedVector2Array, frames: int) -> void:
	var g := gain
	if g < 0.0008:                       # couche muette : zéro synthèse (perf)
		for i in frames:
			buf[i] = Vector2.ZERO
		return
	var windg := _wind_cur * (1.0 - 0.25 * _night) * 0.7
	var ph1 := _ph1
	var ph2 := _ph2
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
		bph += _binc
		if bph >= TAU:
			bph -= TAU
		var breath := 0.74 + 0.14 * sin(bph)
		var drone := (sin(ph1) * 0.5 + sin(ph2) * 0.2) * breath
		# Vent : bruit blanc -> passe-bande -> amplitude (rafales lentes via le LFO de respiration).
		var gust := 0.8 + 0.2 * sin(bph * 1.7)
		var wind := _wind_bp.process(_rng.randf() * 2.0 - 1.0) * windg * gust
		brown += (_rng.randf() * 2.0 - 1.0) * 0.02
		brown = clampf(brown, -1.0, 1.0)
		lp += (brown * 3.2 - lp) * 0.02
		var s := (drone * 0.28 + lp * 0.05 + wind * 0.5) * g
		buf[i] = Vector2(s, s)
	_ph1 = ph1
	_ph2 = ph2
	_brown = brown
	_lp = lp
	_bph = bph
