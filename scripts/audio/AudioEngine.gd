extends Node
## Phase 21 — AudioEngine (autoload) : crée les bus audio (par code), instancie les couches d'ambiance
## procédurales et pilote leurs CROSSFADES selon GameState.current_scale (POLLING — aucune modif des
## phases 1-20). Les modulations météo/temps sont poussées aux couches chaque frame. Mixage BAS.
##
## NB : le bus Music est réservé (phase 22) et muet (la musique existante de MusicPlayer joue sur
## Master, inchangée).

const BUS_NAMES := ["Master", "Music", "Ambient_World", "Ambient_Weather", "SFX"]

# Couches d'ambiance (crossfade par échelle).
var _galaxy: AmbientGalaxy
var _system: AmbientSystem
var _planet: AmbientPlanet
var _surface: AmbientSurface
var _layers: Array = []         # couches crossfadées par échelle
# Couches météo / eau (non crossfadées : pilotées par WeatherSystem / proximité, actives en SURFACE).
var _rain: RainAudio
var _thunder: ThunderAudio
var _water: AmbientWater
var _last_scale := -99
var _vm: Node                   # ViewManager (trouvé dans l'arbre) — pour le seed planète
var _surface_view: Node         # SurfaceView — pour la position joueur (eau)
var _planet_seed := -1
# --- Phase 22 : diégétique (one-shots) + musique générative ---
const SFX3D_POOL := 8
const SFX2D_POOL := 4
var _sfx3d: Array[AudioStreamPlayer3D] = []
var _sfx2d: Array[AudioStreamPlayer] = []
var _transition: TransitionCue
var _footsteps: Footsteps
var _ui_clicks: UIClicks
var _poi_audio: POIAudio
var _music: GenerativeMusic
const SEA_HEIGHT := 0.0         # niveau de mer en espace-surface (DEFAULT_SEA_LEVEL = 0)
const WATER_BAND := 12.0        # m : sous cette altitude au-dessus de la mer => clapotis audible

# Univers sous-marin (CP3) : passe-bas sur Master pour étouffer le son sous l'eau (créé dans _setup_buses).
var _lowpass: AudioEffectLowPassFilter
var _lowpass_idx := -1
var _uw_on := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # l'ambiance continue même en pause
	_setup_buses()
	_create_layers()
	_apply_scale(GameState.current_scale, true)

# --- Bus ---

func _setup_buses() -> void:
	AudioServer.set_bus_count(BUS_NAMES.size())
	for i in BUS_NAMES.size():
		AudioServer.set_bus_name(i, BUS_NAMES[i])
		if i > 0:
			AudioServer.set_bus_send(i, "Master")
	# Volumes de base volontairement BAS (le silence relatif est contemplatif).
	_bus_db("Master", 0.0)
	_bus_db("Music", 0.0)
	AudioServer.set_bus_mute(_bus("Music"), true)   # réservé phase 22 — muet
	_bus_db("Ambient_World", 2.0)
	_bus_db("Ambient_Weather", 0.0)
	_bus_db("SFX", 4.0)
	# Reverb légère sur Ambient_World : sentiment d'espace.
	var rv := AudioEffectReverb.new()
	rv.room_size = 0.85
	rv.damping = 0.45
	rv.wet = 0.20
	rv.dry = 0.88
	rv.spread = 1.0
	AudioServer.add_bus_effect(_bus("Ambient_World"), rv)
	# Univers sous-marin (CP3) : passe-bas sur Master, étouffe TOUT le son sous l'eau. DÉSACTIVÉ par défaut
	# (=> zéro régression hors de l'eau) ; SurfaceView l'active + module le cutoff selon l'immersion.
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(_bus("Master"), _lowpass)
	_lowpass_idx = AudioServer.get_bus_effect_count(_bus("Master")) - 1
	AudioServer.set_bus_effect_enabled(_bus("Master"), _lowpass_idx, false)

# Univers sous-marin (CP3) : étouffe le son sous l'eau (passe-bas Master). f01 = immersion 0..1.
# Activé uniquement quand immergé (f01>0) => hors de l'eau l'effet est bypassé (mix approuvé intact).
func set_underwater(f01: float) -> void:
	if _lowpass == null or _lowpass_idx < 0:
		return
	var b := _bus("Master")
	if f01 < 0.01:
		if _uw_on:
			AudioServer.set_bus_effect_enabled(b, _lowpass_idx, false)
			_uw_on = false
		return
	if not _uw_on:
		AudioServer.set_bus_effect_enabled(b, _lowpass_idx, true)
		_uw_on = true
	_lowpass.cutoff_hz = lerpf(18000.0, 650.0, clampf(f01, 0.0, 1.0))   # plus immergé => plus étouffé

func _bus(n: String) -> int:
	return AudioServer.get_bus_index(n)

func _bus_db(n: String, db: float) -> void:
	var i := _bus(n)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, db)

# Volume maître (0..1 linéaire) — pour de futurs sliders (montre, phase 21 option).
func set_master_volume(linear: float) -> void:
	_bus_db("Master", linear_to_db(clampf(linear, 0.0, 1.0)))

func set_bus_volume(bus_name: String, linear: float) -> void:
	_bus_db(bus_name, linear_to_db(clampf(linear, 0.0, 1.0)))

# dB de BASE = mix APPROUVÉ au casque. Un slider scale RELATIVEMENT : à s01=1.0 le mix d'origine est
# exactement préservé (zéro régression), en dessous on atténue. NE PAS poser de dB absolu via les options.
# Music: -15 = niveau réellement appliqué au bus diégétique (cohérent si un slider musique est ajouté un jour).
const BASE_DB := {"Master": 0.0, "Music": -15.0, "Ambient_World": 2.0, "Ambient_Weather": 0.0, "SFX": 4.0}

func set_bus_scale(bus_name: String, s01: float) -> void:
	var base: float = BASE_DB.get(bus_name, 0.0)
	_bus_db(bus_name, base + linear_to_db(clampf(s01, 0.0008, 1.0)))

# --- Couches ---

func _create_layers() -> void:
	_galaxy = AmbientGalaxy.new()
	_system = AmbientSystem.new()
	_planet = AmbientPlanet.new()
	_surface = AmbientSurface.new()
	for l in [_galaxy, _system, _planet, _surface]:
		add_child(l)
		_layers.append(l)
	# Météo + eau (actives en SURFACE, niveau piloté par WeatherSystem / proximité).
	_rain = RainAudio.new()
	_thunder = ThunderAudio.new()
	_water = AmbientWater.new()
	add_child(_rain)
	add_child(_thunder)
	add_child(_water)
	_create_sfx_pools()      # phase 22 : pools de lecteurs one-shot
	_create_diegetic()       # phase 22 : transition / pas / clics / POI / musique

func _process(_dt: float) -> void:
	var sc: int = GameState.current_scale
	if sc != _last_scale:
		_apply_scale(sc, false)
	# En PLANÈTE / SURFACE : palette planète (déterministe par seed) + modulation jour/nuit.
	var night := _darkness()
	if sc == GameState.Scale.PLANET or sc == GameState.Scale.SURFACE:
		_update_planet_palette()
		_planet.set_night(night)
		_surface.set_night(night)
	if _music != null:
		_music.set_night(night)
		_music.set_storm(WeatherSystem.get_storm() if (sc == GameState.Scale.SURFACE and WeatherSystem.is_configured()) else 0.0)
	_update_weather(sc)

# Active la couche de l'échelle courante, désactive les autres (crossfade doux géré par les couches).
func _apply_scale(sc: int, initial: bool) -> void:
	var prev := _last_scale
	_last_scale = sc
	var active := _layer_for(sc)
	for l in _layers:
		l.set_active(l == active)
	# Phase 22 : cue de transition (sens selon descente/remontée) + bascule d'échelle musicale.
	if not initial and _transition != null and prev >= 0:
		_transition.trigger(prev, sc)
		BHaptics.transition_swell(sc > prev)   # gilet X40 : houle de transition (descente d'échelle = on plonge)
	if _music != null:
		_music.set_scale(sc)

# Couche d'ambiance « de fond » d'une échelle (SURFACE réutilise le drone planète pour l'instant ;
# la couche surface dédiée + vent arrive à l'étape suivante).
func _layer_for(sc: int) -> AmbientLayer:
	match sc:
		GameState.Scale.GALAXY:
			return _galaxy
		GameState.Scale.SYSTEM:
			return _system
		GameState.Scale.PLANET:
			return _planet
		GameState.Scale.SURFACE:
			return _surface
	return _galaxy

# Reconfigure la palette de la planète courante (seed récupéré du ViewManager) quand elle change.
func _update_planet_palette() -> void:
	if _vm == null or not is_instance_valid(_vm):
		_vm = _find_view_manager()
	if _vm == null or not _vm.has_method("get_current_planet_seed"):
		return
	var seed_val: int = _vm.get_current_planet_seed()
	if seed_val != _planet_seed and seed_val != 0:
		_planet_seed = seed_val
		_planet.configure(seed_val)
		_surface.configure(seed_val)

# Météo : pluie/tonnerre/vent suivent WeatherSystem en SURFACE, silence ailleurs. Eau par proximité.
func _update_weather(sc: int) -> void:
	if sc == GameState.Scale.SURFACE and WeatherSystem.is_configured():
		_surface.set_wind(WeatherSystem.get_wind())
		_rain.set_amount(WeatherSystem.get_precipitation())
		_thunder.set_storm(WeatherSystem.get_storm())
		_update_water()
	else:
		_surface.set_wind(0.0)
		_rain.set_amount(0.0)
		_thunder.set_storm(0.0)
		_water.set_proximity(0.0)

# Clapotis : audible quand le joueur est en zone BASSE près du niveau de mer (proxy de côte). Place le
# son au niveau de la mer sous le joueur (positionnel).
func _update_water() -> void:
	if _surface_view == null or not is_instance_valid(_surface_view):
		_surface_view = _find_surface_view()
	if _surface_view == null or not _surface_view.has_method("get_player"):
		_water.set_proximity(0.0)
		return
	var player = _surface_view.get_player()
	if player == null:
		_water.set_proximity(0.0)
		return
	var pos: Vector3 = player.global_position
	var above := pos.y - SEA_HEIGHT
	var prox := 1.0
	if above > 0.0:
		prox = clampf(1.0 - above / WATER_BAND, 0.0, 1.0)
	_water.global_position = Vector3(pos.x, SEA_HEIGHT, pos.z)
	_water.set_proximity(prox)

func _find_surface_view() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.find_child("SurfaceView", true, false)

func _find_view_manager() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.find_child("ViewManager", true, false)

# Obscurité courante [0..1] depuis l'heure simulée (0 = midi, 1 = minuit). Proxy global, sans couplage.
func _darkness() -> float:
	return 0.5 + 0.5 * cos(TimeOfDay.day_fraction() * TAU)

# --- Phase 22 : pools one-shot + diégétique + musique ---

func _create_sfx_pools() -> void:
	for i in SFX3D_POOL:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.max_distance = 60.0
		p.unit_size = 6.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_sfx3d.append(p)
	for i in SFX2D_POOL:
		var q := AudioStreamPlayer.new()
		q.bus = "SFX"
		add_child(q)
		_sfx2d.append(q)

# Démute le bus Music (la playlist MP3 reste désactivée côté MusicPlayer) + crée les systèmes phase 22.
func _create_diegetic() -> void:
	AudioServer.set_bus_mute(_bus("Music"), false)
	_bus_db("Music", -15.0)
	_transition = TransitionCue.new()
	_footsteps = Footsteps.new()
	_ui_clicks = UIClicks.new()
	_poi_audio = POIAudio.new()
	_music = GenerativeMusic.new()
	add_child(_transition)
	add_child(_footsteps)
	add_child(_ui_clicks)
	add_child(_poi_audio)
	add_child(_music)

# Joue un WAV synthétisé à une position MONDE (positionnel ; pitch/volume optionnels).
func play_3d(wav: AudioStreamWAV, world_pos: Vector3, volume_db := -12.0, pitch := 1.0, p_bus := "SFX") -> void:
	if wav == null:
		return
	var p := _free_3d()
	if p == null:
		return
	p.stream = wav
	p.global_position = world_pos
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.bus = p_bus
	p.play()

# Joue un WAV synthétisé NON spatialisé (2D : clics UI, cue de transition).
func play_2d(wav: AudioStreamWAV, volume_db := -18.0, pitch := 1.0, p_bus := "SFX") -> void:
	if wav == null:
		return
	var p := _free_2d()
	if p == null:
		return
	p.stream = wav
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.bus = p_bus
	p.play()

func _free_3d() -> AudioStreamPlayer3D:
	for p in _sfx3d:
		if not p.playing:
			return p
	return _sfx3d[0] if not _sfx3d.is_empty() else null

func _free_2d() -> AudioStreamPlayer:
	for p in _sfx2d:
		if not p.playing:
			return p
	return _sfx2d[0] if not _sfx2d.is_empty() else null

# Appel de faune positionnel (déclenché par Creature via /root/AudioEngine).
func creature_call(world_pos: Vector3, v: Dictionary) -> void:
	play_3d(CreatureVoice.synth(v), world_pos, float(v.get("volume_db", -7.0)), 1.0, "SFX")

# Atterrissage de PUISSANCE (Iron Man / Hulk) : « boom » grave synthétisé UNE fois (cache) puis joué à
# l'impact. strength 0..1 (force de la chute) module le volume + le grave (pitch). Positionnel (suit donc
# le passe-bas sous-marin si on s'écrase immergé).
var _impact_wav: AudioStreamWAV

func play_impact(world_pos: Vector3, strength: float) -> void:
	if _impact_wav == null:
		_impact_wav = _synth_impact()
	var s := clampf(strength, 0.0, 1.0)
	play_3d(_impact_wav, world_pos, lerpf(-7.0, 1.5, s), lerpf(1.06, 0.82, s), "SFX")

# Impact lourd : sub-thump sinus descendant (le poids) + corps de bruit brun passe-bas (le « whump ») +
# crack bref de bruit blanc passe-haut (le sol qui se fend). ~0.55 s.
func _synth_impact() -> AudioStreamWAV:
	var dur := 0.55
	var buf := SfxSynth.make_buffer(dur)
	var n := buf.size()
	var sr := float(SfxSynth.SR)
	var ph := 0.0
	var ph2 := 0.0
	for i in n:
		var t := float(i) / sr
		var f := lerpf(95.0, 40.0, clampf(t / 0.35, 0.0, 1.0))   # sinus descendant 95 -> 40 Hz (le poids)
		ph += TAU * f / sr
		ph2 += TAU * (f * 0.5) / sr                              # sous-octave => plus de corps
		buf[i] = (sin(ph) * 0.8 + sin(ph2) * 0.4) * exp(-t * 7.0)
	var nz := SynthNoise.new(SynthNoise.Kind.BROWN)
	var lp := Biquad.new(sr)
	lp.set_params(Biquad.Type.LOWPASS, 500.0, 0.9)
	var bn := mini(int(0.25 * sr), n)
	for i in bn:
		var t := float(i) / sr
		buf[i] += lp.process(nz.next()) * 0.85 * exp(-t * 10.0)   # « whump » de corps
	var wn := SynthNoise.new(SynthNoise.Kind.WHITE)
	var hp := Biquad.new(sr)
	hp.set_params(Biquad.Type.HIGHPASS, 2500.0, 0.7)
	var cn := mini(int(0.05 * sr), n)
	for i in cn:
		var t := float(i) / sr
		buf[i] += hp.process(wn.next()) * 0.5 * exp(-t * 45.0)   # crack sec du tout début
	for i in n:
		buf[i] = buf[i] / (1.0 + absf(buf[i]) * 0.5)             # soft-clip doux => cohésion + punch
	SfxSynth.apply_ar(buf, 0.001, 0.14)
	SfxSynth.normalize_peak(buf, 0.88)
	return SfxSynth.to_wav(buf)

# Blaster (mode combat) : « pew » laser — onde carrée descendante + éclat de bruit. Synthétisé une fois.
var _blaster_wav: AudioStreamWAV

func play_blaster(world_pos: Vector3) -> void:
	if _blaster_wav == null:
		_blaster_wav = _synth_blaster()
	play_3d(_blaster_wav, world_pos, -6.0, randf_range(0.95, 1.08), "SFX")

func _synth_blaster() -> AudioStreamWAV:
	# « Pew » d'énergie DENSE : 2 saws détunés balayés + sub bref + air bandpass résonant + click, soft-clippé.
	var dur := 0.18
	var buf := SfxSynth.make_buffer(dur)
	var n := buf.size()
	var sr := float(SfxSynth.SR)
	var o1 := Osc.new(SfxSynth.SR, 1500.0, Osc.Wave.SAW)
	var o2 := Osc.new(SfxSynth.SR, 1509.0, Osc.Wave.SAW)   # détune => épaisseur
	var sub := Osc.new(SfxSynth.SR, 180.0, Osc.Wave.SINE)
	var nz := SynthNoise.new(SynthNoise.Kind.WHITE)
	var cnz := SynthNoise.new(SynthNoise.Kind.WHITE)
	var bp := Biquad.new(SfxSynth.SR)
	for i in n:
		var t := float(i) / sr
		var k := clampf(t / dur, 0.0, 1.0)
		var f := lerpf(1500.0, 420.0, pow(k, 0.5))     # zap qui « retombe »
		o1.set_freq(f)
		o2.set_freq(f * 1.006)
		sub.set_freq(lerpf(180.0, 90.0, k))
		var body := (o1.next() * 0.5 + o2.next() * 0.5) * exp(-t * 13.0)
		var subv := sub.next() * 0.5 * exp(-t * 22.0)
		bp.set_params(Biquad.Type.BANDPASS, lerpf(3200.0, 900.0, k), 1.4)
		var air := bp.process(nz.next()) * 0.5 * exp(-t * 16.0)
		var click := 0.0
		if t < 0.008:
			click = cnz.next() * 0.6 * (1.0 - t / 0.008)
		var s := (body + subv + air + click) * 0.9
		buf[i] = s / (1.0 + absf(s))                    # soft-clip => chaleur
	SfxSynth.apply_ar(buf, 0.001, 0.05)
	SfxSynth.normalize_peak(buf, 0.6)
	return SfxSynth.to_wav(buf)

var _enemy_shot_wav: AudioStreamWAV

# Tir de drone ennemi : zap GRAVE descendant (plus menaçant + distinct du blaster joueur). Spatialisé => on
# entend d'où vient le tir. Appelé par WaveManager à chaque tir de drone, à la position du drone.
func play_enemy_shot(world_pos: Vector3) -> void:
	if _enemy_shot_wav == null:
		_enemy_shot_wav = _synth_enemy_shot()
	play_3d(_enemy_shot_wav, world_pos, -9.0, randf_range(0.92, 1.05), "SFX")

func _synth_enemy_shot() -> AudioStreamWAV:
	# Zap GRAVE et grognant (distinct du blaster joueur) : 2 saws bas détunés + sub + lowpass résonant, soft-clippé.
	var dur := 0.24
	var buf := SfxSynth.make_buffer(dur)
	var n := buf.size()
	var sr := float(SfxSynth.SR)
	var o1 := Osc.new(SfxSynth.SR, 700.0, Osc.Wave.SAW)
	var o2 := Osc.new(SfxSynth.SR, 705.0, Osc.Wave.SAW)
	var sub := Osc.new(SfxSynth.SR, 120.0, Osc.Wave.SINE)
	var nz := SynthNoise.new(SynthNoise.Kind.WHITE)
	var cnz := SynthNoise.new(SynthNoise.Kind.WHITE)
	var lp := Biquad.new(SfxSynth.SR)
	for i in n:
		var t := float(i) / sr
		var k := clampf(t / dur, 0.0, 1.0)
		var f := lerpf(700.0, 150.0, pow(k, 0.6))
		o1.set_freq(f)
		o2.set_freq(f * 1.008)
		sub.set_freq(lerpf(120.0, 60.0, k))
		var body := (o1.next() * 0.5 + o2.next() * 0.5) * exp(-t * 9.0)
		var subv := sub.next() * 0.55 * exp(-t * 13.0)
		lp.set_params(Biquad.Type.LOWPASS, lerpf(2000.0, 420.0, k), 3.0)   # résonant => grognement menaçant
		var grit := lp.process(nz.next()) * 0.5 * exp(-t * 10.0)
		var click := 0.0
		if t < 0.006:
			click = cnz.next() * 0.4 * (1.0 - t / 0.006)
		var s := (body + subv + grit + click) * 0.9
		buf[i] = s / (1.0 + absf(s))
	SfxSynth.apply_ar(buf, 0.001, 0.06)
	SfxSynth.normalize_peak(buf, 0.5)
	return SfxSynth.to_wav(buf)

var _hit_confirm_wav: AudioStreamWAV
var _kill_confirm_wav: AudioStreamWAV

# Confirmation de tir joueur sur un drone : « tic » sec et aigu (2D, non spatialisé => net). killed = drone
# détruit => version plus brillante/montante. Appelé par PlayerController au toucher / à la destruction.
func play_hit_confirm(killed: bool) -> void:
	if killed:
		if _kill_confirm_wav == null:
			_kill_confirm_wav = _synth_confirm(true)
		play_2d(_kill_confirm_wav, -10.0, randf_range(0.98, 1.04), "SFX")
	else:
		if _hit_confirm_wav == null:
			_hit_confirm_wav = _synth_confirm(false)
		play_2d(_hit_confirm_wav, -17.0, randf_range(0.97, 1.06), "SFX")

func _synth_confirm(killed: bool) -> AudioStreamWAV:
	# « Blip » de confirmation : fondamentale + octave (timbre de cloche) + tick de bruit ; kill => monte + plus brillant.
	var dur := 0.14 if killed else 0.06
	var buf := SfxSynth.make_buffer(dur)
	var n := buf.size()
	var sr := float(SfxSynth.SR)
	var f0 := 1500.0 if killed else 2000.0
	var o := Osc.new(SfxSynth.SR, f0, Osc.Wave.SINE)
	var oh := Osc.new(SfxSynth.SR, f0 * 2.0, Osc.Wave.SINE)
	var nz := SynthNoise.new(SynthNoise.Kind.WHITE)
	for i in n:
		var t := float(i) / sr
		var k := clampf(t / dur, 0.0, 1.0)
		var rise := (1.0 + 0.5 * k) if killed else 1.0
		o.set_freq(f0 * rise)
		oh.set_freq(f0 * 2.0 * rise)
		var dec := exp(-t * (22.0 if killed else 52.0))
		var tone := (o.next() * 0.6 + oh.next() * 0.25) * dec
		var tick := 0.0
		if t < 0.004:
			tick = nz.next() * 0.4 * (1.0 - t / 0.004)
		var s := (tone + tick) * 0.8
		buf[i] = s / (1.0 + absf(s))
	SfxSynth.apply_ar(buf, 0.0005, 0.02)
	SfxSynth.normalize_peak(buf, 0.4)
	return SfxSynth.to_wav(buf)

var _wave_start_wav: AudioStreamWAV

# Sting de début de vague : deux paliers (grave → quinte) en carré, « ça commence ». 2D. Appelé par WaveManager.
func play_wave_start() -> void:
	if _wave_start_wav == null:
		_wave_start_wav = _synth_wave_start()
	play_2d(_wave_start_wav, -11.0, 1.0, "SFX")

func _synth_wave_start() -> AudioStreamWAV:
	# Sting « ça commence » : 2 notes (montée d'une quinte) en saws détunés + sub, riser de bruit, bloom soft-clippé.
	var dur := 0.6
	var buf := SfxSynth.make_buffer(dur)
	var n := buf.size()
	var sr := float(SfxSynth.SR)
	var half := dur * 0.5
	var o1 := Osc.new(SfxSynth.SR, 146.0, Osc.Wave.SAW)
	var o2 := Osc.new(SfxSynth.SR, 147.0, Osc.Wave.SAW)
	var sub := Osc.new(SfxSynth.SR, 73.0, Osc.Wave.SINE)
	var nz := SynthNoise.new(SynthNoise.Kind.WHITE)
	var bp := Biquad.new(SfxSynth.SR)
	for i in n:
		var t := float(i) / sr
		var second := t >= half
		var root := 220.0 if second else 146.0       # 2e palier = quinte au-dessus (montée = tension)
		o1.set_freq(root)
		o2.set_freq(root * 1.007)
		sub.set_freq(root * 0.5)
		var lt := fmod(t, half)
		var env := (1.0 - exp(-lt * 30.0)) * exp(-lt * 4.0)   # attaque douce + descente (bloom par note)
		var body := (o1.next() * 0.5 + o2.next() * 0.5 + sub.next() * 0.5) * env
		var riser := 0.0
		if not second:
			var rk := clampf(t / half, 0.0, 1.0)
			bp.set_params(Biquad.Type.BANDPASS, lerpf(400.0, 3000.0, rk), 1.0)
			riser = bp.process(nz.next()) * 0.3 * rk          # bruit qui monte vers la 2e note
		var s := (body + riser) * 0.85
		buf[i] = s / (1.0 + absf(s))
	SfxSynth.apply_ar(buf, 0.005, 0.08)
	SfxSynth.normalize_peak(buf, 0.32)
	return SfxSynth.to_wav(buf)

var _plasma_wav: AudioStreamWAV
var _plasma_hit_wav: AudioStreamWAV

# Tir plasma : son DENSE et chaud (2 saws détunés + octave grave + sub punch + bruit passe-bas résonant balayé,
# le tout soft-clippé) — fini le « laser carré » cheap. charged => plus grave et lourd (tir secondaire).
func play_plasma(world_pos: Vector3, charged := false) -> void:
	if _plasma_wav == null:
		_plasma_wav = _synth_plasma()
	var pitch := randf_range(0.96, 1.05)
	if charged:
		pitch *= 0.82
	play_3d(_plasma_wav, world_pos, -3.0 if charged else -4.0, pitch, "SFX")

func _synth_plasma() -> AudioStreamWAV:
	var dur := 0.34
	var buf := SfxSynth.make_buffer(dur)
	var n := buf.size()
	var sr := float(SfxSynth.SR)
	var o1 := Osc.new(SfxSynth.SR, 540.0, Osc.Wave.SAW)
	var o2 := Osc.new(SfxSynth.SR, 545.0, Osc.Wave.SAW)    # détune => épaisseur (battements)
	var o3 := Osc.new(SfxSynth.SR, 270.0, Osc.Wave.SINE)   # octave grave (corps)
	var sub := Osc.new(SfxSynth.SR, 92.0, Osc.Wave.SINE)
	var nz := SynthNoise.new(SynthNoise.Kind.WHITE)
	var lp := Biquad.new(SfxSynth.SR)
	for i in n:
		var t := float(i) / sr
		var k := clampf(t / dur, 0.0, 1.0)
		var f := lerpf(560.0, 150.0, pow(k, 0.55))         # balayage vers le grave
		o1.set_freq(f)
		o2.set_freq(f * 1.01)
		o3.set_freq(f * 0.5)
		sub.set_freq(lerpf(96.0, 52.0, k))
		var body := (o1.next() * 0.5 + o2.next() * 0.5 + o3.next() * 0.4) * exp(-t * 6.5)
		var subv := sub.next() * 0.7 * exp(-t * 10.0)
		lp.set_params(Biquad.Type.LOWPASS, lerpf(4200.0, 600.0, k), 2.2)   # « énergie » filtrée balayée
		var fizz := lp.process(nz.next()) * 0.45 * exp(-t * 8.0)
		var click := nz.next() * 0.5 * (1.0 - t / 0.014) if t < 0.014 else 0.0
		var s := (body + subv + fizz + click) * 0.9
		buf[i] = s / (1.0 + absf(s))                        # soft-clip => chaleur + densité
	SfxSynth.apply_ar(buf, 0.002, 0.11)
	return SfxSynth.to_wav(buf)

# Impact plasma (le bolt touche) : éclaboussure d'énergie — tone descendant + bruit bandpass qui grésille.
func play_plasma_hit(world_pos: Vector3) -> void:
	if _plasma_hit_wav == null:
		_plasma_hit_wav = _synth_plasma_hit()
	play_3d(_plasma_hit_wav, world_pos, -7.0, randf_range(0.95, 1.08), "SFX")

func _synth_plasma_hit() -> AudioStreamWAV:
	var dur := 0.18
	var buf := SfxSynth.make_buffer(dur)
	var n := buf.size()
	var sr := float(SfxSynth.SR)
	var nz := SynthNoise.new(SynthNoise.Kind.WHITE)
	var bp := Biquad.new(SfxSynth.SR)
	var o := Osc.new(SfxSynth.SR, 420.0, Osc.Wave.SINE)
	for i in n:
		var t := float(i) / sr
		var k := clampf(t / dur, 0.0, 1.0)
		o.set_freq(lerpf(440.0, 120.0, k))
		var tone := o.next() * 0.4 * exp(-t * 16.0)
		bp.set_params(Biquad.Type.BANDPASS, lerpf(2600.0, 700.0, k), 1.2)
		var sizzle := bp.process(nz.next()) * 0.8 * exp(-t * 13.0)
		var s := (tone + sizzle) * 0.9
		buf[i] = s / (1.0 + absf(s))
	SfxSynth.apply_ar(buf, 0.001, 0.05)
	return SfxSynth.to_wav(buf)

var _grenade_launch_wav: AudioStreamWAV

# Lancement de grenade : « pomf » grave (bruit brun + sinus descendant), distinct des lasers. Spatialisé.
func play_grenade_launch(world_pos: Vector3) -> void:
	if _grenade_launch_wav == null:
		_grenade_launch_wav = _synth_grenade_launch()
	play_3d(_grenade_launch_wav, world_pos, -5.0, randf_range(0.95, 1.05), "SFX")

func _synth_grenade_launch() -> AudioStreamWAV:
	var dur := 0.18
	var buf := SfxSynth.make_buffer(dur)
	var n := buf.size()
	var sr := float(SfxSynth.SR)
	var nz := SynthNoise.new(SynthNoise.Kind.BROWN)
	var ph := 0.0
	for i in n:
		var t := float(i) / sr
		var f := lerpf(170.0, 65.0, clampf(t / dur, 0.0, 1.0))   # « thunk » grave descendant
		ph += TAU * f / sr
		var tone := sin(ph) * 0.45 * exp(-t * 20.0)
		var noise := nz.next() * 0.5 * exp(-t * 24.0)              # souffle du tube
		buf[i] = tone + noise
	SfxSynth.apply_ar(buf, 0.001, 0.05)
	return SfxSynth.to_wav(buf)

# Pré-génère TOUS les WAV de combat (sinon le 1er usage de chacun synthétise EN JEU => micro-hitch, gênant en
# VR). Appelé une fois à l'équipement d'une arme. Idempotent (chaque synth ne tourne que si le cache est vide).
func warmup_combat() -> void:
	if _blaster_wav == null: _blaster_wav = _synth_blaster()
	if _plasma_wav == null: _plasma_wav = _synth_plasma()
	if _plasma_hit_wav == null: _plasma_hit_wav = _synth_plasma_hit()
	if _grenade_launch_wav == null: _grenade_launch_wav = _synth_grenade_launch()
	if _enemy_shot_wav == null: _enemy_shot_wav = _synth_enemy_shot()
	if _hit_confirm_wav == null: _hit_confirm_wav = _synth_confirm(false)
	if _kill_confirm_wav == null: _kill_confirm_wav = _synth_confirm(true)
	if _wave_start_wav == null: _wave_start_wav = _synth_wave_start()
	if _impact_wav == null: _impact_wav = _synth_impact()

# Active/désactive la musique générative (toggle montre).
func set_music_enabled(on: bool) -> void:
	if _music:
		_music.set_enabled(on)
