extends Node
## Orchestre les échelles par TRANSITIONS ABSTRAITES (sélection / caméra) — SANS vaisseau.
## On démarre sur l'hologramme galaxie ; on s'enfonce d'échelle en échelle par sélection :
##   GALAXY --(sélection système)--> SYSTEM --(sélection planète)--> PLANET (orbite)
##   PLANET --(descente)--> SURFACE (à pied) ; retours par Échap / bouton à chaque échelle.
## TimeOfDay / WeatherSystem / lunes continuent normalement. Les vues (galaxy/system/planet/
## surface) gèrent leur propre rendu ; ViewManager ne fait que les afficher + caler l'échelle.

@onready var galaxy_view = $"../GalaxyView"
@onready var system_view = $"../SystemView"
@onready var planet_view = $"../PlanetView"
@onready var surface_view = $"../SurfaceView"
@onready var nav = $"../NavigationController"
@onready var xr_origin = $"../XROrigin3D"
@onready var xr_camera = $"../XROrigin3D/XRCamera3D"
@onready var left_controller = $"../XROrigin3D/LeftController"
@onready var right_controller = $"../XROrigin3D/RightController"
@onready var hand_tracking = $"../XROrigin3D/HandTracking"
@onready var desktop_camera = $"../DesktopCamera"

const START_LAND_MARGIN := 0.08   # élévation min au-dessus du niveau de mer (descente sur terre ferme)
const PLANET_PROMPT_SUFFIX := " — Clic gauche : atterrir · Clic droit : tourner · Molette : zoom · Échap : retour"

var _transitioning := false
var _current_planet_seed := 0   # seed planète orbite/surface courante
var _current_planet_name := ""  # phase 19.5 : nom propre de la planète orbite/surface courante
var _current_system = null      # StarSystem courant (étoiles de nuit au sol)
var _current_system_index := -1
var _orbit_planet_index := -1
var _current_landing_dir := Vector3.ZERO   # point (dir unité) d'atterrissage de la surface courante (coop CP1)
# Phase 23 : carte hydrologique de la planète courante (érosion + rivières + lacs), générée
# OFF-THREAD au 1er accès planète, cachée tant que la planète est courante, libérée en quittant l'orbite.
var _current_flow_map: PlanetFlowMap = null
var _flow_seed := 0                       # seed de la FlowMap courante / en cours
var _flow_task_id := -1                   # tâche WorkerThreadPool en cours (-1 = aucune)
var _flow_pending: PlanetFlowMap = null   # résultat en construction (worker -> main)
var _flow_drain: Array[int] = []          # tâches supersédées (planète changée) à libérer

func is_transitioning() -> bool:
	return _transitioning

# Lève le verrou de transition à l'idle suivant : couvre toute la transition synchrone (+ le bloc flow-map
# bloquant) sans risque de rester collé sur un return précoce. Empêche le double-déclenchement même-frame
# (2 clics/events bufferisés dans la même frame d'input).
func _clear_transition() -> void:
	_transitioning = false

func get_current_planet_seed() -> int:
	return _current_planet_seed

# Phase 23 : FlowMap de la planète courante (null tant que pas prête). Consommée par la sphère
# orbitale (cp3/cp4) et la surface (cp5/cp6).
func get_current_flow_map() -> PlanetFlowMap:
	return _current_flow_map

# Phase 19.5 : nom propre de la planète courante (orbite/surface) pour l'affichage HUD/montre.
func get_current_planet_name() -> String:
	return _current_planet_name

# Phase 19.5 : nom propre du système courant (héritage palette régionale) pour l'affichage.
func get_current_system_name() -> String:
	return _current_system.name if _current_system != null else ""

# Prompt PLANET : nom propre de la planète en tête (ton contemplatif) + rappel des commandes.
func _planet_prompt() -> String:
	var head: String = _current_planet_name if _current_planet_name != "" else "Planète"
	return head + PLANET_PROMPT_SUFFIX

# ----------------------- GALAXY <-> SYSTEM -----------------------

# GALAXY -> SYSTEM : sélection d'un système -> hologramme système (planètes en orbite).
func enter_system(galaxy_index: int) -> void:
	if _transitioning or galaxy_index < 0 or galaxy_index >= galaxy_view.data.systems.size():
		return
	_transitioning = true
	call_deferred("_clear_transition")
	var sys = galaxy_view.data.systems[galaxy_index]
	_current_system = sys
	_current_system_index = galaxy_index
	# Phase 19.5 : palette régionale + nom déjà portés par le StarSystem (calculés à la génération
	# galaxie depuis la POSITION) => planètes/lunes héritent de la palette régionale du système.
	var sdata = SystemGenerator.generate(sys.seed_local, sys.star_type, sys.palette_id, sys.name)
	system_view.build(sdata)
	galaxy_view.visible = false
	planet_view.visible = false
	system_view.visible = true
	GameState.current_scale = GameState.Scale.SYSTEM
	nav.set_active_view(system_view, GameState.Scale.SYSTEM, true)
	print("[ViewManager] Entrée système (seed_local=", sys.seed_local, ", planètes=", sdata.planets.size(), ").")

# SYSTEM -> GALAXY : retour à l'hologramme galaxie (état préservé).
func exit_to_galaxy() -> void:
	if _transitioning:
		return
	_transitioning = true
	call_deferred("_clear_transition")
	_park_xr_rig_at_home()
	system_view.visible = false
	planet_view.visible = false
	galaxy_view.visible = true
	GameState.current_scale = GameState.Scale.GALAXY
	nav.set_active_view(galaxy_view, GameState.Scale.GALAXY, false)
	_release_flow_map()   # phase 23 : libère la carte hydrologique (sécurité)
	print("[ViewManager] Sortie vers galaxie.")

# ----------------------- SYSTEM <-> PLANET -----------------------

# SYSTEM -> PLANET : sélection d'une planète -> vue orbite (planète qui tourne via TimeOfDay).
func enter_planet(planet_index: int) -> void:
	if _transitioning or planet_index < 0 or system_view.data == null:
		return
	if planet_index >= system_view.data.planets.size():
		return
	_transitioning = true
	call_deferred("_clear_transition")
	var planet = system_view.data.planets[planet_index]
	_current_planet_seed = planet.seed_local
	_current_planet_name = planet.name   # phase 19.5 : retenu pour le HUD/montre PLANET & SURFACE
	_orbit_planet_index = planet_index
	planet_view.build(planet.seed_local)
	# Placée comme un HOLOGRAMME (réduite + devant l'utilisateur en XR ; à l'origine en bureau où
	# la caméra fixe la cadre) — sinon en VR la caméra roomscale est À L'INTÉRIEUR de la planète
	# pleine échelle (rayon 30) à l'origine => écran noir.
	nav.set_active_view(planet_view, GameState.Scale.PLANET, true)   # planète = vue manipulée (rotation + zoom) en orbite
	system_view.visible = false
	planet_view.visible = true
	GameState.current_scale = GameState.Scale.PLANET
	nav.set_prompt(_planet_prompt())
	_begin_flow_map(planet.seed_local)   # phase 23 : génère la carte hydrologique OFF-THREAD
	print("[ViewManager] Orbite planète (seed_local=", planet.seed_local, ").")

# PLANET -> SYSTEM : retour à l'hologramme système.
func exit_to_system() -> void:
	if _transitioning:
		return
	_transitioning = true
	call_deferred("_clear_transition")
	_park_xr_rig_at_home()
	planet_view.visible = false
	system_view.visible = true
	GameState.current_scale = GameState.Scale.SYSTEM
	nav.set_active_view(system_view, GameState.Scale.SYSTEM, false)
	_orbit_planet_index = -1
	_release_flow_map()   # phase 23 : on quitte l'orbite => libère la carte hydrologique
	print("[ViewManager] Retour système.")

# ----------------------- PLANET <-> SURFACE (à pied) -----------------------

# PLANET -> SURFACE : descente au sol À PIED (terrain streamé suivant le marcheur).
func enter_surface(landing_dir: Vector3 = Vector3.ZERO) -> void:
	if _transitioning or GameState.current_scale != GameState.Scale.PLANET:
		return
	_transitioning = true
	call_deferred("_clear_transition")
	var atmo := PlanetAtmosphere.atmosphere_color_for(_current_planet_seed)
	_ensure_flow_map_ready()   # phase 23 : hydrologie prête AVANT la résolution (côte/relief érodés cohérents)
	# Point d'atterrissage = EXACTEMENT le point cliqué si fourni (terre ferme => exact ; océan => côte
	# la plus proche du clic, pour rester praticable) ; sinon point déterministe sur terre (touche Entrée
	# / rayon ayant manqué la planète).
	var ld: Vector3
	if landing_dir.length() > 0.01:
		ld = _resolve_landing(landing_dir.normalized(), _current_planet_seed, _current_flow_map)
	else:
		ld = _find_landing_dir(_current_planet_seed, _current_flow_map)
	_current_landing_dir = ld   # mémorisé pour la coop (l'hôte l'envoie aux invités)
	var star_systems := []
	var system_pos := Vector3.ZERO
	if _current_system != null:
		star_systems = galaxy_view.data.systems
		system_pos = _current_system.position
	# build() (chemin marchant) spawn + gèle le joueur (anti-chute) jusqu'à sol prêt.
	# Phase 20 couche C : palette régionale du système -> nommage des POI notables au sol.
	var pal: int = _current_system.palette_id if _current_system != null else 0
	surface_view.build(_current_planet_seed, ld, atmo, star_systems, system_pos, pal, _current_flow_map)
	planet_view.visible = false
	surface_view.visible = true
	GameState.current_scale = GameState.Scale.SURFACE
	var player = surface_view.get_player()
	if player == null:
		return   # build a échoué : évite un null-deref (surface posée, mais pas de crash)
	if GameState.xr_active:
		player.enter_xr(xr_origin, xr_camera, left_controller, right_controller)
		xr_camera.environment = surface_view.get_environment()
	else:
		player.enter_desktop()
		player.get_active_camera().environment = surface_view.get_environment()
	nav.set_prompt("")
	print("[ViewManager] Descente surface (système ", _current_system_index, ", seed=", _current_planet_seed, ").")
	_send_world_context(0)   # coop : emmène les invités DÉJÀ connectés sur CETTE surface (robuste à l'ordre hôte/invité)

# SURFACE -> PLANET : remontée en orbite (décharge le terrain, rend la caméra à l'hologramme).
func exit_to_planet() -> void:
	if _transitioning or GameState.current_scale != GameState.Scale.SURFACE:
		return
	_transitioning = true
	call_deferred("_clear_transition")
	surface_view.shutdown_streaming()
	surface_view.visible = false
	var player = surface_view.get_player()
	if not GameState.xr_active:
		player.get_active_camera().environment = null
	player.exit()
	_park_xr_rig_at_home()   # rends le rig XR à Main (enter_xr l'avait collé sous le joueur en surface)
	xr_camera.environment = null
	# Replace la planète en HOLOGRAMME devant l'utilisateur (cf. enter_planet : anti écran noir VR).
	nav.set_active_view(planet_view, GameState.Scale.PLANET, true)   # planète = vue manipulée (rotation + zoom) en orbite
	planet_view.visible = true
	GameState.current_scale = GameState.Scale.PLANET
	if not GameState.xr_active:
		desktop_camera.current = true
	nav.set_prompt(_planet_prompt())
	print("[ViewManager] Remontée en orbite.")

# Remonte d'une échelle (utilisé par la montre poignet) : SURFACE->PLANET->SYSTEM->GALAXY.
func ascend_one_scale() -> void:
	match GameState.current_scale:
		GameState.Scale.SURFACE:
			exit_to_planet()
		GameState.Scale.PLANET:
			exit_to_system()
		GameState.Scale.SYSTEM:
			exit_to_galaxy()

# ----------------------- Helpers -----------------------

# Gare le rig XR à Main, à l'origine (idempotent). À appeler à CHAQUE remontée vers un hologramme :
# enter_xr (descente surface) reparente le rig SOUS le joueur, et PlayerController.exit() ne le défait
# pas — sans ce parking le rig reste à la position terrain et les hologrammes (galaxie/système/planète,
# placés à l'origine/devant) sont hors champ => écran noir au retour. No-op en bureau.
func _park_xr_rig_at_home() -> void:
	if not GameState.xr_active:
		return
	if xr_origin.get_parent() != get_parent():
		xr_origin.reparent(get_parent(), false)
	xr_origin.transform = Transform3D.IDENTITY

# Direction-planète SUR TERRE FERME pour la descente. Déterministe par seed (même planète =>
# même point de descente). Repli après 64 essais (planète quasi-océan) : direction quelconque.
func _find_landing_dir(seed_local: int, flow_map: PlanetFlowMap = null) -> Vector3:
	var pg := PlanetGenerator.new()
	pg.configure(seed_local)
	pg.set_flow_map(flow_map)   # phase 23 : point de descente sur le relief érodé
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_local
	for attempt in 64:
		var d := _rand_dir(rng)
		if pg.sample_elevation(d) > PlanetGenerator.DEFAULT_SEA_LEVEL + START_LAND_MARGIN:
			return d
	return _rand_dir(rng)

func _rand_dir(rng: RandomNumberGenerator) -> Vector3:
	var v := Vector3(rng.randf() * 2.0 - 1.0, rng.randf() * 2.0 - 1.0, rng.randf() * 2.0 - 1.0)
	if v.length() < 0.01:
		v = Vector3(1.0, 0.0, 0.0)
	return v.normalized()

# Résout le point d'atterrissage depuis le point CLIQUÉ : terre ferme => exact ; océan => terre la plus
# proche AUTOUR du clic (anneaux croissants) pour rester praticable ; rien de proche => garde le clic.
func _resolve_landing(dir: Vector3, seed_local: int, flow_map: PlanetFlowMap = null) -> Vector3:
	var pg := PlanetGenerator.new()
	pg.configure(seed_local)
	pg.set_flow_map(flow_map)   # phase 23 : snap océan→côte sur la côte ÉRODÉE
	var thresh := PlanetGenerator.DEFAULT_SEA_LEVEL + START_LAND_MARGIN
	if pg.sample_elevation(dir) > thresh:
		return dir                                  # terre ferme : atterrissage EXACT au clic
	for ring in [0.04, 0.08, 0.14, 0.22, 0.32]:     # océan : cherche la côte la plus proche du clic
		for a in 12:
			var cand := _offset_dir(dir, a / 12.0 * TAU, ring)
			if pg.sample_elevation(cand) > thresh:
				return cand
	return dir                                      # rien de proche : on assume le clic (océan)

# Direction obtenue en décalant 'dir' dans son plan tangent (angle 'ang', amplitude 'amount').
func _offset_dir(dir: Vector3, ang: float, amount: float) -> Vector3:
	var b := FloatingOrigin.tangent_basis(dir)
	return (dir + (b.x * cos(ang) + b.z * sin(ang)) * amount).normalized()

# ----------------------- Phase 23 : carte hydrologique OFF-THREAD -----------------------

# Démarre la génération OFF-THREAD de la FlowMap pour `seed_local` (no-op si déjà courante / en cours).
func _begin_flow_map(seed_local: int) -> void:
	if seed_local == 0:
		return
	if seed_local == _flow_seed and (_current_flow_map != null or _flow_task_id != -1):
		return                                  # déjà en cache ou en cours pour ce seed
	# Supersède une tâche en cours (planète changée avant la fin) : à drainer, sans l'adopter.
	if _flow_task_id != -1:
		_flow_drain.append(_flow_task_id)
		_flow_task_id = -1
	_flow_seed = seed_local
	_current_flow_map = null
	var fm := PlanetFlowMap.new()
	_flow_pending = fm
	# fm + seed sont LIÉS à la tâche (pas de lecture de membre côté worker => pas de course).
	_flow_task_id = WorkerThreadPool.add_task(_gen_flow_map.bind(fm, seed_local), false, "PlanetFlowMap")
	_set_flow_indicator(true)

# Exécutée sur un thread worker : pur calcul (PlanetGenerator + érosion), ne touche pas l'arbre/rendu.
func _gen_flow_map(fm: PlanetFlowMap, seed_local: int) -> void:
	fm.generate(seed_local, PlanetFlowMap.DEFAULT_W, PlanetFlowMap.DEFAULT_H, PlanetGenerator.DEFAULT_SEA_LEVEL, {})
	# Bake aussi le mesh orbital ÉRODÉ dans CE worker (off-thread) => zéro hitch main-thread à la bascule.
	fm.orbital_mesh = PlanetGenerator.generate(seed_local, PlanetGenerator.DEFAULT_SUBDIVISIONS, PlanetGenerator.DEFAULT_AMPLITUDE, PlanetGenerator.DEFAULT_SEA_LEVEL, PlanetGenerator.DEFAULT_NOISE_FREQ, PlanetGenerator.DEFAULT_RADIUS, fm)

# Attend la fin de la génération FlowMap (≤ ~1,6 s) si encore en cours, pour que la SURFACE en dispose
# toujours. Appelé à la descente (transition déjà « chargement » + gel anti-chute) : un court bloc est OK.
func _ensure_flow_map_ready() -> void:
	if _flow_task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_flow_task_id)
		_flow_task_id = -1
		_current_flow_map = _flow_pending
		_flow_pending = null
		_set_flow_indicator(false)

# Libère la FlowMap (sortie d'orbite) + draine une éventuelle tâche en cours.
func _release_flow_map() -> void:
	if _flow_task_id != -1:
		_flow_drain.append(_flow_task_id)
		_flow_task_id = -1
	_current_flow_map = null
	_flow_pending = null
	_flow_seed = 0
	_set_flow_indicator(false)

# Indicateur DISCRET pendant le calcul : suffixe au prompt PLANET (seulement en orbite, sans écraser
# le prompt surface).
func _set_flow_indicator(generating: bool) -> void:
	if GameState.current_scale != GameState.Scale.PLANET:
		return
	nav.set_prompt(_planet_prompt() + (" · hydrologie…" if generating else ""))

# Poll des tâches : adopte la FlowMap courante quand prête, draine les supersédées.
func _process(_dt: float) -> void:
	for i in range(_flow_drain.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_flow_drain[i]):
			WorkerThreadPool.wait_for_task_completion(_flow_drain[i])
			_flow_drain.remove_at(i)
	if _flow_task_id != -1 and WorkerThreadPool.is_task_completed(_flow_task_id):
		WorkerThreadPool.wait_for_task_completion(_flow_task_id)
		_flow_task_id = -1
		_current_flow_map = _flow_pending
		_flow_pending = null
		_set_flow_indicator(false)
		_on_flow_map_ready()

# Crochet « FlowMap prête » : cp3/cp4 rebâtiront ici la sphère orbitale érodée. Pour l'instant : log.
func _on_flow_map_ready() -> void:
	if _current_flow_map == null:
		return
	if GameState.current_scale != GameState.Scale.PLANET:
		return   # ceinture+bretelles : ne rebâtir la sphère orbitale érodée que si on est encore en orbite
	planet_view.apply_flow_map(_current_flow_map)   # rebâtit la sphère orbitale érodée + rivières/lacs
	print("[ViewManager] FlowMap prête (seed=", _flow_seed, ", max_flow=", _current_flow_map.max_flow, ").")

# ----------------------- COOP (multijoueur CP1 : handshake monde) -----------------------

func _ready() -> void:
	NetworkManager.peer_joined.connect(_on_net_peer_joined)
	# Entrée DEV (test sans UI) : --auto-surface => descend direct sur (système 0, planète 0) au boot ;
	# + --auto-arm => équipe une arme (active le combat) ~2 s après l'atterrissage.
	var ua := OS.get_cmdline_user_args()
	if ua.has("--auto-surface"):
		get_tree().create_timer(0.6).timeout.connect(_dev_auto_surface.bind(ua.has("--auto-arm")))

func _dev_auto_surface(auto_arm: bool) -> void:
	goto_surface(0, 0, Vector3.ZERO)
	if auto_arm:
		get_tree().create_timer(2.0).timeout.connect(_dev_auto_arm)

func _dev_auto_arm() -> void:
	var p = surface_view.get_player()
	if p == null:
		return
	if p.has_method("toggle_plasma"):
		p.toggle_plasma()         # plasma équipé (test du tir SECONDAIRE missile à tête chercheuse)
	if p.has_method("dev_load_missiles"):
		p.dev_load_missiles(8)    # munitions de test (en jeu réel : lootées sur les drones abattus)

# HÔTE : un pair vient de rejoindre. Si on est en SURFACE, on lui envoie le contexte monde (seed + index
# système + index planète + point d'atterrissage) pour qu'il atterrisse sur LA MÊME surface (déterminisme).
# Envoie le contexte monde aux invités. to_id == 0 => TOUS les pairs ; sinon un pair précis. Hôte + SURFACE seulement.
func _send_world_context(to_id: int) -> void:
	if not NetworkManager.is_host() or GameState.current_scale != GameState.Scale.SURFACE:
		return
	var sd := GameState.global_seed
	var si := _current_system_index
	var pi := _orbit_planet_index
	var ld := _current_landing_dir
	var sim := TimeOfDay.simulated_seconds
	var wm := WeatherSystem.get_force_mode()
	if to_id == 0:
		rpc("_rpc_world_context", sd, si, pi, ld, sim, wm)
	else:
		rpc_id(to_id, "_rpc_world_context", sd, si, pi, ld, sim, wm)

func _on_net_peer_joined(id: int) -> void:
	_send_world_context(id)   # un pair arrive : si l'hôte est DÉJÀ en surface, on l'y emmène tout de suite

# INVITÉ : reçoit le contexte de l'hôte => adopte son seed (reconstruit la galaxie si différent) puis saute
# sur la même surface. @rpc authority => seul l'hôte (id 1) peut l'appeler chez les invités.
@rpc("authority", "call_remote", "reliable")
func _rpc_world_context(seed_val: int, system_index: int, planet_index: int, landing_dir: Vector3, sim_seconds: float, force_mode: int) -> void:
	print("[ViewManager] contexte coop reçu (seed=", seed_val, ", sys=", system_index, ", planet=", planet_index, ").")
	if GameState.global_seed != seed_val:
		GameState.global_seed = seed_val
		galaxy_view.rebuild()
	goto_surface(system_index, planet_index, landing_dir)
	# Coop : adopte l'horloge + la météo forcée de l'hôte (sinon jour/nuit, soleil & météo divergent entre clients).
	TimeOfDay.simulated_seconds = sim_seconds
	WeatherSystem.set_force_mode(force_mode)

# Saut DIRECT vers une surface (système -> planète -> sol) en UNE transition. Réplique enter_system +
# enter_planet + enter_surface sans leurs gardes individuels. Sert à la coop (invité) et au dev (--auto-surface).
func goto_surface(system_index: int, planet_index: int, landing_dir: Vector3) -> void:
	if _transitioning or galaxy_view.data == null:
		return
	if system_index < 0 or system_index >= galaxy_view.data.systems.size():
		return
	# 1. Système — on génère AVANT toute mutation pour valider l'index planète (sinon état mi-transition).
	var sys = galaxy_view.data.systems[system_index]
	var sdata = SystemGenerator.generate(sys.seed_local, sys.star_type, sys.palette_id, sys.name)
	if planet_index < 0 or planet_index >= sdata.planets.size():
		return   # index invalide => RIEN n'a été muté (la galaxie reste l'état courant cohérent)
	_transitioning = true
	call_deferred("_clear_transition")
	_current_system = sys
	_current_system_index = system_index
	system_view.build(sdata)
	# 2. Planète
	var planet = sdata.planets[planet_index]
	_current_planet_seed = planet.seed_local
	_current_planet_name = planet.name
	_orbit_planet_index = planet_index
	planet_view.build(planet.seed_local)
	_begin_flow_map(planet.seed_local)
	# 3. Surface
	var atmo := PlanetAtmosphere.atmosphere_color_for(_current_planet_seed)
	_ensure_flow_map_ready()
	var ld: Vector3 = landing_dir.normalized() if landing_dir.length() > 0.01 else _find_landing_dir(_current_planet_seed, _current_flow_map)
	_current_landing_dir = ld
	surface_view.build(_current_planet_seed, ld, atmo, galaxy_view.data.systems, sys.position, sys.palette_id, _current_flow_map)
	galaxy_view.visible = false
	system_view.visible = false
	planet_view.visible = false
	surface_view.visible = true
	GameState.current_scale = GameState.Scale.SURFACE
	var player = surface_view.get_player()
	if player == null:
		return   # build a échoué : évite un null-deref (surface posée, mais pas de crash)
	if GameState.xr_active:
		player.enter_xr(xr_origin, xr_camera, left_controller, right_controller)
		xr_camera.environment = surface_view.get_environment()
	else:
		player.enter_desktop()
		player.get_active_camera().environment = surface_view.get_environment()
	nav.set_prompt("")
	print("[ViewManager] goto_surface (sys=", system_index, ", planet=", planet_index, ", seed=", _current_planet_seed, ").")
	_send_world_context(0)   # coop : idem (si hôte ; no-op chez l'invité qui exécute aussi goto_surface)
