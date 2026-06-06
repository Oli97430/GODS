class_name Footsteps
extends Node
## Phase 22 — pas synthétisés, adaptés au BIOME sous le joueur. Écoute le signal `step` du
## PlayerController (cadence = distance parcourue). Burst court positionnel aux pieds, volume bas,
## micro-variation par foulée (pitch/volume + alternance G/D) pour éviter l'effet machine.
## 5 timbres : herbe (pink HP), pierre (white HP + clic), sable (brown LP), neige (white LP long), mouillé (+sine grave).

var _player: Node             # PlayerController
var _surface_view: Node       # SurfaceView (pour biome_at + get_player)
var _left := false

const VARIANTS := 3           # nombre de bursts pré-rendus par biome (garde du grain sans figer une seule forme)
var _step_cache := {}         # biome:int -> Array[AudioStreamWAV] : zéro synthèse en jeu après la 1re foulée

func _process(_dt: float) -> void:
	if GameState.current_scale != GameState.Scale.SURFACE:
		return
	if _player == null or not is_instance_valid(_player):
		_acquire()

func _acquire() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	_surface_view = scene.find_child("SurfaceView", true, false)
	if _surface_view and _surface_view.has_method("get_player"):
		var p = _surface_view.get_player()
		if p != null and p.has_signal("step") and not p.step.is_connected(_on_step):
			_player = p
			p.step.connect(_on_step)

func _on_step(world_pos: Vector3) -> void:
	_left = not _left
	var biome := PlanetGenerator.Biome.PLAINS
	if _surface_view and _surface_view.has_method("biome_at"):
		biome = _surface_view.biome_at(world_pos)
	var ae := get_parent()
	if ae and ae.has_method("play_3d"):
		# Banque de bursts pré-rendus par biome : la 1re foulée sur un biome inédit en synthétise VARIANTS d'un coup,
		# ensuite on réutilise (pitch/volume aléatoires conservent la variation). Plus de synthèse à chaque pas.
		var bank: Array = _step_cache.get(biome)
		if bank == null:
			bank = []
			for k in VARIANTS:
				bank.append(_synth(biome))
			_step_cache[biome] = bank
		var wav: AudioStreamWAV = bank[randi() % bank.size()]
		var pitch := randf_range(0.92, 1.08) * (1.02 if _left else 0.98)
		ae.play_3d(wav, world_pos + Vector3(0, 0.05, 0), randf_range(-9.0, -5.0), pitch, "SFX")

# Synthétise un burst de pas selon le biome (timbre + filtre + durée + release).
func _synth(biome: int) -> AudioStreamWAV:
	var dur := 0.11
	var kind := SynthNoise.Kind.PINK
	var ftype := Biquad.Type.HIGHPASS
	var cut := 1300.0
	var rel := 0.07
	var wet := false
	var click := false
	match biome:
		PlanetGenerator.Biome.ROCK:
			kind = SynthNoise.Kind.WHITE; ftype = Biquad.Type.HIGHPASS; cut = 950.0; dur = 0.09; rel = 0.05; click = true
		PlanetGenerator.Biome.SNOW:
			kind = SynthNoise.Kind.WHITE; ftype = Biquad.Type.LOWPASS; cut = 1600.0; dur = 0.17; rel = 0.13
		PlanetGenerator.Biome.BEACH:
			kind = SynthNoise.Kind.BROWN; ftype = Biquad.Type.LOWPASS; cut = 820.0; dur = 0.13; rel = 0.09; wet = true
		_:  # PLAINS / FOREST / repli
			kind = SynthNoise.Kind.PINK; ftype = Biquad.Type.HIGHPASS; cut = 1300.0; dur = 0.11; rel = 0.07
	var buf := SfxSynth.make_buffer(dur)
	var n := buf.size()
	var sr := float(SfxSynth.SR)
	var nz := SynthNoise.new(kind)
	var filt := Biquad.new(sr)
	filt.set_params(ftype, cut, 0.7)
	for i in n:
		var s := filt.process(nz.next()) * 0.7
		if click and i < 5:
			s += 0.7 * (1.0 - float(i) / 5.0)         # transient sec (pierre)
		buf[i] = s
	SfxSynth.apply_ar(buf, 0.002 if click else 0.005, rel)
	# Corps grave bref = POIDS du pas (toutes surfaces) : sine basse dosée par biome (pas de normalisation pour
	# garder le contraste de force neige↔roche). Remplace l'ancien « smack » mouillé en le généralisant.
	var body_f := 108.0
	var body_amp := 0.30
	match biome:
		PlanetGenerator.Biome.ROCK:
			body_f = 132.0; body_amp = 0.28
		PlanetGenerator.Biome.SNOW:
			body_f = 78.0; body_amp = 0.15
		PlanetGenerator.Biome.BEACH:
			body_f = 92.0; body_amp = 0.36
	var bph := 0.0
	var bn := mini(int(0.06 * sr), n)
	for i in bn:
		bph += TAU * body_f / sr
		buf[i] += sin(bph) * body_amp * (1.0 - float(i) / float(bn))
	return SfxSynth.to_wav(buf)
