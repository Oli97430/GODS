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

# Active/désactive la musique générative (toggle montre).
func set_music_enabled(on: bool) -> void:
	if _music:
		_music.set_enabled(on)
