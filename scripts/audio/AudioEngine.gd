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
	for i in n:
		var t := float(i) / sr
		var f := lerpf(95.0, 40.0, clampf(t / 0.35, 0.0, 1.0))   # sinus descendant 95 -> 40 Hz
		ph += TAU * f / sr
		buf[i] = sin(ph) * 0.95 * exp(-t * 7.0)
	var nz := SynthNoise.new(SynthNoise.Kind.BROWN)
	var lp := Biquad.new(sr)
	lp.set_params(Biquad.Type.LOWPASS, 500.0, 0.7)
	var bn := mini(int(0.25 * sr), n)
	for i in bn:
		var t := float(i) / sr
		buf[i] += lp.process(nz.next()) * 0.8 * exp(-t * 10.0)
	var wn := SynthNoise.new(SynthNoise.Kind.WHITE)
	var hp := Biquad.new(sr)
	hp.set_params(Biquad.Type.HIGHPASS, 2500.0, 0.7)
	var cn := mini(int(0.05 * sr), n)
	for i in cn:
		var t := float(i) / sr
		buf[i] += hp.process(wn.next()) * 0.5 * exp(-t * 45.0)   # transient sec du tout début
	SfxSynth.apply_ar(buf, 0.001, 0.14)
	return SfxSynth.to_wav(buf)

# Blaster (mode combat) : « pew » laser — onde carrée descendante + éclat de bruit. Synthétisé une fois.
var _blaster_wav: AudioStreamWAV

func play_blaster(world_pos: Vector3) -> void:
	if _blaster_wav == null:
		_blaster_wav = _synth_blaster()
	play_3d(_blaster_wav, world_pos, -6.0, randf_range(0.95, 1.08), "SFX")

func _synth_blaster() -> AudioStreamWAV:
	var dur := 0.16
	var buf := SfxSynth.make_buffer(dur)
	var n := buf.size()
	var sr := float(SfxSynth.SR)
	var ph := 0.0
	for i in n:
		var t := float(i) / sr
		var f := lerpf(1400.0, 280.0, clampf(t / dur, 0.0, 1.0))   # zap descendant
		ph += TAU * f / sr
		var sq := 1.0 if sin(ph) > 0.0 else -1.0                   # carré => plus « laser »
		buf[i] = sq * 0.5 * exp(-t * 16.0)
	var nz := SynthNoise.new(SynthNoise.Kind.WHITE)
	var cn := mini(int(0.02 * sr), n)
	for i in cn:
		buf[i] += nz.next() * 0.3 * (1.0 - float(i) / float(cn))   # éclat sec au départ
	SfxSynth.apply_ar(buf, 0.001, 0.04)
	return SfxSynth.to_wav(buf)

var _enemy_shot_wav: AudioStreamWAV

# Tir de drone ennemi : zap GRAVE descendant (plus menaçant + distinct du blaster joueur). Spatialisé => on
# entend d'où vient le tir. Appelé par WaveManager à chaque tir de drone, à la position du drone.
func play_enemy_shot(world_pos: Vector3) -> void:
	if _enemy_shot_wav == null:
		_enemy_shot_wav = _synth_enemy_shot()
	play_3d(_enemy_shot_wav, world_pos, -9.0, randf_range(0.92, 1.05), "SFX")

func _synth_enemy_shot() -> AudioStreamWAV:
	var dur := 0.22
	var buf := SfxSynth.make_buffer(dur)
	var n := buf.size()
	var sr := float(SfxSynth.SR)
	var ph := 0.0
	for i in n:
		var t := float(i) / sr
		var f := lerpf(620.0, 130.0, clampf(t / dur, 0.0, 1.0))   # grave => menaçant
		ph += TAU * f / sr
		var sq := 1.0 if sin(ph) > 0.0 else -1.0
		buf[i] = sq * 0.42 * exp(-t * 11.0)
	var nz := SynthNoise.new(SynthNoise.Kind.WHITE)
	var cn := mini(int(0.03 * sr), n)
	for i in cn:
		buf[i] += nz.next() * 0.22 * (1.0 - float(i) / float(cn))
	SfxSynth.apply_ar(buf, 0.001, 0.05)
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
	var dur := 0.12 if killed else 0.05
	var buf := SfxSynth.make_buffer(dur)
	var n := buf.size()
	var sr := float(SfxSynth.SR)
	var f0 := 1600.0 if killed else 2100.0
	var ph := 0.0
	for i in n:
		var t := float(i) / sr
		var rise := 0.5 * clampf(t / dur, 0.0, 1.0) if killed else 0.0   # kill : monte (résolution)
		var f := f0 * (1.0 + rise)
		ph += TAU * f / sr
		buf[i] = sin(ph) * 0.4 * exp(-t * (24.0 if killed else 55.0))
	SfxSynth.apply_ar(buf, 0.001, 0.02)
	return SfxSynth.to_wav(buf)

var _wave_start_wav: AudioStreamWAV

# Sting de début de vague : deux paliers (grave → quinte) en carré, « ça commence ». 2D. Appelé par WaveManager.
func play_wave_start() -> void:
	if _wave_start_wav == null:
		_wave_start_wav = _synth_wave_start()
	play_2d(_wave_start_wav, -11.0, 1.0, "SFX")

func _synth_wave_start() -> AudioStreamWAV:
	var dur := 0.5
	var buf := SfxSynth.make_buffer(dur)
	var n := buf.size()
	var sr := float(SfxSynth.SR)
	var ph := 0.0
	for i in n:
		var t := float(i) / sr
		var f := 330.0 if t < dur * 0.5 else 495.0   # deux paliers (quinte)
		ph += TAU * f / sr
		var env := exp(-fmod(t, dur * 0.5) * 6.0)     # ré-attaque à chaque palier
		buf[i] = (1.0 if sin(ph) > 0.0 else -1.0) * 0.28 * env
	SfxSynth.apply_ar(buf, 0.004, 0.06)
	return SfxSynth.to_wav(buf)

# Active/désactive la musique générative (toggle montre).
func set_music_enabled(on: bool) -> void:
	if _music:
		_music.set_enabled(on)
