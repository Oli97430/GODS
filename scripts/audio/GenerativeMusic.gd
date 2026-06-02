class_name GenerativeMusic
extends Node
## Phase 22 — musique générative (style Eno *Reflection* / Endel). UNE seule voix de stream (économie),
## 4 voix synthétisées EN INTERNE + une voix de « découverte ». Notes tirées d'une ÉCHELLE contextuelle :
## galaxie/système = pentatonique haute ; planète = hexatonique ; surface jour = hexatonique chaude ;
## surface nuit = mineur grave (racine glissée) ; orage = tension dissonante occasionnelle, lentement
## résolue. Enveloppes TRÈS lentes (attack 2-5 s, release 4-8 s). Doit RESPIRER, jamais jouer un morceau.
## Volume TRÈS bas (le bus Music est à -24 dB). Désactivable (set_enabled).

const SR := 44100.0

var stream: SynthStream
var _voices: Array = []
var _disc := {"ph": 0.0, "inc": 0.0, "env": 0.0, "on": false}
var _root := 220.0
var _scale: Array = [0, 2, 4, 5, 7, 9]
var _game_scale := 0
var _night := 0.0
var _storm := 0.0
var _enabled := true
var _surface_view: Node
var _disc_t := 0.0

func _ready() -> void:
	stream = SynthStream.new()
	add_child(stream)
	stream.setup("Music", -2.0, SR, 0.4)
	stream.fill_func = _fill
	stream.start()
	for i in 4:
		_voices.append(_make_voice(i))
	_refresh_profile()

func _make_voice(idx: int) -> Dictionary:
	var ranges := [[90.0, 200.0], [160.0, 340.0], [260.0, 540.0], [430.0, 900.0]]
	var r: Array = ranges[idx]
	return {
		"wave": idx % 3, "lo": r[0], "hi": r[1], "ph": 0.0, "inc": 0.0, "env": 0.0, "st": 0,
		"t": randf_range(1.0, 9.0), "atk": randf_range(2.5, 5.0), "hold": randf_range(2.0, 6.0),
		"rel": randf_range(4.0, 8.0), "wmin": 14.0, "wmax": 42.0,
		"prob": randf_range(0.4, 0.8), "amp": randf_range(0.10, 0.16),
	}

func set_enabled(on: bool) -> void:
	_enabled = on

func set_scale(game_scale: int) -> void:
	_game_scale = game_scale
	_refresh_profile()

func set_night(d: float) -> void:
	_night = clampf(d, 0.0, 1.0)

func set_storm(s: float) -> void:
	_storm = clampf(s, 0.0, 1.0)

func _refresh_profile() -> void:
	match _game_scale:
		GameState.Scale.GALAXY, GameState.Scale.SYSTEM:
			_root = 330.0
			_scale = [0, 2, 4, 7, 9]
		GameState.Scale.PLANET:
			_root = 247.0
			_scale = [0, 2, 4, 5, 7, 9]
		_:  # SURFACE
			_scale = [0, 2, 3, 5, 7, 8, 10] if _night > 0.5 else [0, 2, 4, 5, 7, 9]

func _process(dt: float) -> void:
	if _game_scale == GameState.Scale.SURFACE:
		_root = lerpf(220.0, 160.0, _night)   # assombrissement continu jour->nuit
	_update_discovery(dt)
	for v in _voices:
		_update_voice(v, dt)

func _update_discovery(dt: float) -> void:
	_disc_t -= dt
	if _disc_t <= 0.0:
		_disc_t = 0.5
		_disc.on = false
		if _game_scale == GameState.Scale.SURFACE:
			if _surface_view == null or not is_instance_valid(_surface_view):
				var scene := get_tree().current_scene
				_surface_view = scene.find_child("SurfaceView", true, false) if scene else null
			if _surface_view and _surface_view.has_method("nearest_poi"):
				var p: Dictionary = _surface_view.nearest_poi()
				if p.name != "" and float(p.distance) < 36.0:
					_disc.on = true
	_disc.env = move_toward(_disc.env, 1.0 if _disc.on else 0.0, dt / 4.0)
	_disc.inc = TAU * (_root * 1.5) / SR        # quinte au-dessus de la racine

func _update_voice(v: Dictionary, dt: float) -> void:
	match int(v.st):
		0:   # attente
			v.t -= dt
			if v.t <= 0.0:
				if randf() < v.prob:
					_trigger(v)
				else:
					v.t = randf_range(v.wmin, v.wmax)
		1:   # attaque
			v.env = minf(v.env + dt / v.atk, 1.0)
			if v.env >= 1.0:
				v.st = 2
				v.t = v.hold
		2:   # tenue
			v.t -= dt
			if v.t <= 0.0:
				v.st = 3
		3:   # release
			v.env = maxf(v.env - dt / v.rel, 0.0)
			if v.env <= 0.0:
				v.st = 0
				v.t = randf_range(v.wmin, v.wmax)

func _trigger(v: Dictionary) -> void:
	var semis: int = _scale[randi() % _scale.size()]
	if _storm > 0.5 and randf() < 0.25:
		semis += 1                              # tension (seconde mineure) en orage
	var f: float = _root * pow(2.0, float(semis) / 12.0)
	while f < v.lo:
		f *= 2.0
	while f > v.hi:
		f *= 0.5
	v.inc = TAU * f / SR
	v.env = 0.0
	v.st = 1
	v.atk = randf_range(2.5, 5.0)
	v.rel = randf_range(4.0, 8.0)

func _fill(buf: PackedVector2Array, frames: int) -> void:
	for i in frames:
		buf[i] = Vector2.ZERO
	if not _enabled:
		return
	for v in _voices:
		if v.env <= 0.0001:
			continue
		var ph: float = v.ph
		var inc: float = v.inc
		var env: float = v.env
		var amp: float = v.amp
		var wave: int = int(v.wave)
		for i in frames:
			ph += inc
			if ph >= TAU:
				ph -= TAU
			var s := sin(ph)
			if wave == 1:
				s = 4.0 * absf(ph / TAU - 0.5) - 1.0
			elif wave == 2:
				s = (ph / PI - 1.0) * 0.5
			var val := s * env * amp
			buf[i] = buf[i] + Vector2(val, val)
		v.ph = ph
	if float(_disc.env) > 0.0001:
		var ph: float = _disc.ph
		var dinc: float = _disc.inc
		var denv: float = _disc.env
		for i in frames:
			ph += dinc
			if ph >= TAU:
				ph -= TAU
			var val := sin(ph) * denv * 0.12
			buf[i] = buf[i] + Vector2(val, val)
		_disc.ph = ph
