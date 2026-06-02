class_name POIAudio
extends Node
## Phase 22 — audio d'ambiance des POI. Un petit pool de voix continues POSITIONNELLES (SynthStream3D)
## est assigné par PROXIMITÉ aux POI audibles autour du joueur (crossfade in/out par distance). Chaque
## voix synthétise un MODE selon la catégorie du POI (paramètres « résonance » dérivés du seed POI) :
##   HISS (geyser/source chaude) · DRONE subharmonique (monolithe/cercle) · ÉTHÉRÉ (cristal/bosquet/
##   cascade gelée) · VENT (dune/cheminée/orgues/arbre/arche naturelle, couplé à WeatherSystem.wind) ·
##   SOUFFLE (arche en ruines/autel). Le reste (cairn, balise…) reste SILENCIEUX.

const SR := 44100.0
const VOICES := 3
const AUDIBLE := 45.0       # m : rayon d'audibilité d'un POI
const FADE := 1.4           # gain de crossfade / s
const SCAN := 0.4           # s entre deux ré-assignations

enum Mode { SILENT, HISS, DRONE, ETHEREAL, WIND, BREATH }

var _voices: Array = []
var _surface_view: Node
var _cm: Node               # ChunkManager
var _scan_t := 0.0

func _ready() -> void:
	for i in VOICES:
		var st := SynthStream3D.new()
		add_child(st)
		st.setup("Ambient_World", -2.0, SR, 0.3)
		var v := _new_voice(st)
		st.fill_func = _fill.bind(v)
		st.start()
		_voices.append(v)

func _new_voice(st: SynthStream3D) -> Dictionary:
	return {
		"stream": st, "category": -1, "mode": Mode.SILENT, "seed": 0,
		"gain": 0.0, "target": 0.0, "pos": Vector3.ZERO, "matched": false,
		"ph1": 0.0, "ph2": 0.0, "inc1": 0.0, "inc2": 0.0, "lp": 0.0, "brown": 0.0,
		"lfo": 0.0, "linc": TAU * 0.06 / SR, "center": 600.0,
		"bp": Biquad.new(SR), "evt": 0.0, "tone_ph": 0.0, "tone_inc": 0.0, "tone_env": 0.0,
	}

func _process(dt: float) -> void:
	if GameState.current_scale != GameState.Scale.SURFACE:
		for v in _voices:
			v.target = 0.0
	else:
		_scan_t -= dt
		if _scan_t <= 0.0:
			_scan_t = SCAN
			_reassign()
	for v in _voices:
		v.gain = move_toward(v.gain, v.target, FADE * dt)
		if v.category >= 0:
			v.stream.global_position = v.pos

# Ré-assigne les voix aux POI audibles les plus proches (continuité : garde une voix sur son POI).
func _reassign() -> void:
	if _cm == null or not is_instance_valid(_cm):
		_acquire()
	if _cm == null or _surface_view == null or not _surface_view.has_method("get_player"):
		return
	var player = _surface_view.get_player()
	if player == null:
		return
	var pl: Vector3 = player.global_position
	var cand := []
	if _cm.has_method("pois_near"):
		for p in _cm.pois_near(pl, AUDIBLE):
			var m := _mode_for(p.category)
			if m == Mode.SILENT:
				continue
			cand.append({"category": p.category, "seed": p.seed, "pos": p.pos, "mode": m, "dist": pl.distance_to(p.pos)})
	cand.sort_custom(func(a, b): return a.dist < b.dist)
	if cand.size() > VOICES:
		cand = cand.slice(0, VOICES)
	var used := {}
	for c in cand:
		c["matched"] = false
		for v in _voices:
			if used.has(v):
				continue
			if v.category == c.category and v.pos.distance_to(c.pos) < 4.0 and v.gain > 0.001:
				v.target = _dist_gain(c.dist)
				v.pos = c.pos
				used[v] = true
				c.matched = true
				break
	for c in cand:
		if c.matched:
			continue
		var v := _free_voice(used)
		if v == null:
			continue
		_configure(v, c)
		used[v] = true
	for v in _voices:
		if not used.has(v):
			v.target = 0.0

func _acquire() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	_surface_view = scene.find_child("SurfaceView", true, false)
	if _surface_view and _surface_view.has_method("get_chunk_manager"):
		_cm = _surface_view.get_chunk_manager()

func _dist_gain(d: float) -> float:
	return clampf(1.0 - d / AUDIBLE, 0.0, 1.0)

func _free_voice(used: Dictionary) -> Dictionary:
	var best = null
	for v in _voices:
		if used.has(v):
			continue
		if best == null or v.gain < best.gain:
			best = v
	return best

# Configure une voix pour un POI : mode + paramètres « résonance » déterministes (seed POI).
func _configure(v: Dictionary, c: Dictionary) -> void:
	v.category = c.category
	v.mode = c.mode
	v.seed = c.seed
	v.pos = c.pos
	v.target = _dist_gain(c.dist)
	var rng := RandomNumberGenerator.new()
	rng.seed = c.seed * 2654435761 + 1313
	match c.mode:
		Mode.DRONE:
			var f: float = rng.randf_range(38.0, 62.0)   # subharmonique mystérieuse (seed POI)
			v.inc1 = TAU * f / SR
			v.inc2 = TAU * f * 1.5 / SR                   # quinte légère
		Mode.HISS:
			v.center = rng.randf_range(300.0, 700.0)
			v.bp.set_params(Biquad.Type.LOWPASS, v.center, 0.8)
		Mode.ETHEREAL:
			v.tone_inc = TAU * rng.randf_range(900.0, 2200.0) / SR
		Mode.WIND:
			v.center = rng.randf_range(380.0, 820.0)
			v.bp.set_params(Biquad.Type.BANDPASS, v.center, 1.0)
		Mode.BREATH:
			v.center = rng.randf_range(220.0, 480.0)
			v.bp.set_params(Biquad.Type.LOWPASS, v.center, 0.7)

func _mode_for(category: int) -> int:
	match category:
		POILibrary.Category.GEYSER, POILibrary.Category.HOT_SPRING:
			return Mode.HISS
		POILibrary.Category.MONOLITH, POILibrary.Category.STONE_CIRCLE:
			return Mode.DRONE
		POILibrary.Category.CRYSTAL_FOREST, POILibrary.Category.BIOLUM_GROVE, POILibrary.Category.FROZEN_WATERFALL:
			return Mode.ETHEREAL
		POILibrary.Category.LONE_DUNE, POILibrary.Category.HOODOO, POILibrary.Category.BASALT_COLUMNS, POILibrary.Category.GIANT_TREE, POILibrary.Category.NATURAL_ARCH:
			return Mode.WIND
		POILibrary.Category.RUINED_ARCH, POILibrary.Category.ALTAR:
			return Mode.BREATH
	return Mode.SILENT

# --- Synthèse par mode (état dans la voix, copié en locaux pour le hot loop) ---

func _fill(buf: PackedVector2Array, frames: int, v: Dictionary) -> void:
	var g: float = v.gain
	if g < 0.0008 or v.mode == Mode.SILENT:
		for i in frames:
			buf[i] = Vector2.ZERO
		return
	match v.mode:
		Mode.DRONE:
			_fill_drone(buf, frames, v, g)
		Mode.HISS:
			_fill_hiss(buf, frames, v, g)
		Mode.ETHEREAL:
			_fill_ethereal(buf, frames, v, g)
		Mode.WIND:
			_fill_wind(buf, frames, v, g)
		Mode.BREATH:
			_fill_breath(buf, frames, v, g)

func _fill_drone(buf: PackedVector2Array, frames: int, v: Dictionary, g: float) -> void:
	var ph1: float = v.ph1
	var ph2: float = v.ph2
	var lfo: float = v.lfo
	var inc1: float = v.inc1
	var inc2: float = v.inc2
	var linc: float = v.linc
	for i in frames:
		ph1 += inc1
		if ph1 >= TAU: ph1 -= TAU
		ph2 += inc2
		if ph2 >= TAU: ph2 -= TAU
		lfo += linc
		if lfo >= TAU: lfo -= TAU
		var amp := 0.8 + 0.2 * sin(lfo)
		var s := (sin(ph1) * 0.6 + sin(ph2) * 0.25) * amp * g * 0.5
		buf[i] = Vector2(s, s)
	v.ph1 = ph1
	v.ph2 = ph2
	v.lfo = lfo

func _fill_hiss(buf: PackedVector2Array, frames: int, v: Dictionary, g: float) -> void:
	var lp: float = v.lp
	var lfo: float = v.lfo
	var linc: float = v.linc
	var bp: Biquad = v.bp
	for i in frames:
		lfo += linc * 1.3
		if lfo >= TAU: lfo -= TAU
		var swell := 0.6 + 0.4 * (0.5 + 0.5 * sin(lfo))
		lp += (bp.process(randf() * 2.0 - 1.0) - lp) * 0.5
		var s := lp * swell * g * 0.6
		buf[i] = Vector2(s, s)
	v.lp = lp
	v.lfo = lfo

func _fill_ethereal(buf: PackedVector2Array, frames: int, v: Dictionary, g: float) -> void:
	var ph: float = v.tone_ph
	var env: float = v.tone_env
	var evt: float = v.evt
	var inc: float = v.tone_inc
	for i in frames:
		evt -= 1.0 / SR
		if evt <= 0.0:
			evt = randf_range(4.0, 11.0)
			env = 1.0
		env = maxf(env - 1.0 / (SR * 6.0), 0.0)   # décroissance ~6 s
		ph += inc
		if ph >= TAU: ph -= TAU
		var s := sin(ph) * env * env * g * 0.10
		buf[i] = Vector2(s, s)
	v.tone_ph = ph
	v.tone_env = env
	v.evt = evt

func _fill_wind(buf: PackedVector2Array, frames: int, v: Dictionary, g: float) -> void:
	var wind := 0.25
	if WeatherSystem.is_configured():
		wind = WeatherSystem.get_wind()
	var lp: float = v.lp
	var lfo: float = v.lfo
	var linc: float = v.linc
	var bp: Biquad = v.bp
	var amt := (0.25 + 0.75 * wind) * g
	for i in frames:
		lfo += linc
		if lfo >= TAU: lfo -= TAU
		var gust := 0.7 + 0.3 * sin(lfo * 1.6)
		lp += (bp.process(randf() * 2.0 - 1.0) - lp) * 0.6
		var s := lp * amt * gust * 0.55
		buf[i] = Vector2(s, s)
	v.lp = lp
	v.lfo = lfo

func _fill_breath(buf: PackedVector2Array, frames: int, v: Dictionary, g: float) -> void:
	var wind := 0.2
	if WeatherSystem.is_configured():
		wind = WeatherSystem.get_wind()
	var lp: float = v.lp
	var lfo: float = v.lfo
	var linc: float = v.linc
	var bp: Biquad = v.bp
	var amt := (0.12 + 0.4 * wind) * g
	for i in frames:
		lfo += linc * 0.6
		if lfo >= TAU: lfo -= TAU
		var breath := 0.5 + 0.5 * sin(lfo)
		lp += (bp.process(randf() * 2.0 - 1.0) - lp) * 0.4
		var s := lp * amt * breath * 0.4
		buf[i] = Vector2(s, s)
	v.lp = lp
	v.lfo = lfo
