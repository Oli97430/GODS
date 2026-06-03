class_name SurfaceView
extends Node3D
## Vue SURFACE : terrain STREAMÉ (ChunkManager) cohérent avec l'orbite, ciel teinté
## par l'atmosphère du seed, soleil directionnel, et brouillard réglé pour masquer le
## bord de chargement (plus de mur de bordure : le terrain est quasi-infini). Le joueur
## (PlayerController) est gelé au spawn tant que le chunk + sa collision sous lui ne
## sont pas prêts (anti-chute). PAS de gravité sphérique : up local = +Y monde —
## l'aplatissement de ChunkManager suit la courbure sans physique sphérique.

@onready var _sun: DirectionalLight3D = $SunLight
@onready var _player: PlayerController = $Player
# Vestiges de la phase 6 (patch borné + murs) : rendus inertes en mode streaming.
@onready var _terrain: MeshInstance3D = $Terrain
@onready var _terrain_body: StaticBody3D = $TerrainBody
@onready var _walls: Node3D = $Walls
@onready var _border_label: Label3D = $BorderLabel

var _chunks: ChunkManager
var _ocean: SurfaceOcean
var _inland_water_mat: ShaderMaterial   # phase 23 : eau rivière/lac (créée par seed/atmo, maj chaque frame)
var _surface_env: Environment
var _sky: SkyManager
var _sky3d: Sky3D   # addon Sky3D : dôme de ciel + nuages volumétriques (ciel de surface)
var _starfield: Starfield
var _fireflies   # lucioles/spores nocturnes (Fireflies.gd) — vie ambiante autour du joueur la nuit
var _rain: RainEffect
var _lightning: LightningEffect
var _surface_moons: SurfaceMoons   # phase 14 : lunes dans le ciel
var _landing_dir := Vector3.UP   # lat/long fixe du point d'atterrissage (jour/nuit)
var _waiting_ground := false
var _ground_wait_elapsed := 0.0
# Gilet bHaptics — cadences de l'ambiance surface (pluie / vent / cœur au calme).
var _rain_t := 0.0
var _wind_t := 0.0
var _idle_t := 0.0
var _heart_t := 0.0
const GROUND_WAIT_MAX := 6.0   # s : au-delà, re-cale le joueur sur le sol analytique et RÉ-attend (jamais de dégel dans le vide)

func _ready() -> void:
	# Neutralise le patch borné de la phase 6 (aucun mur, aucune collision résiduelle).
	_terrain.visible = false
	_border_label.visible = false
	# Gestionnaire de streaming planétaire (porte ses propres chunks sous un PlanetRoot).
	_chunks = ChunkManager.new()
	add_child(_chunks)
	# Océan de surface (phase 11) : plan d'eau au niveau de mer, suit le joueur.
	_ocean = SurfaceOcean.new()
	add_child(_ocean)
	# Cycle jour/nuit (phase 12) : pilote soleil + ciel + fog depuis TimeOfDay.
	_sky = SkyManager.new()
	add_child(_sky)
	# Éclairs (phase 13) : planificateur déterministe, flash appliqué par SkyManager.
	_lightning = LightningEffect.new()
	add_child(_lightning)
	_sky.set_lightning(_lightning)
	# Lunes dans le ciel (phase 14) : meshes sur la dôme, éclairées par l'étoile (phases).
	_surface_moons = SurfaceMoons.new()
	add_child(_surface_moons)
	# Étoiles de nuit (phase 12) : autres systèmes de la galaxie projetés.
	_starfield = Starfield.new()
	add_child(_starfield)
	# Pluie (phase 13) : GPU particles worldspace autour du joueur, pilotée par WeatherSystem.
	_rain = RainEffect.new()
	add_child(_rain)
	_rain.setup(_player)
	# Lucioles/spores nocturnes (vie ambiante) : nuée additive qui dérive autour du joueur la nuit.
	_fireflies = preload("res://scripts/Fireflies.gd").new()
	add_child(_fireflies)

# Met en place le terrain streamé + ciel + brouillard pour une planète et un point
# d'atterrissage donnés, place le joueur au spawn et le gèle jusqu'à sol prêt.
func build(seed_local: int, landing_dir: Vector3, atmo_color: Color, star_systems: Array = [], system_pos: Vector3 = Vector3.ZERO, palette_id: int = 0, flow_map: PlanetFlowMap = null) -> void:
	_landing_dir = landing_dir.normalized()
	WeatherSystem.set_location(_landing_dir)   # point d'échantillonnage météo (lat/long fixe)
	_chunks.setup(seed_local, landing_dir, palette_id, flow_map)   # palette_id : POI ; flow_map : hydrologie phase 23
	_chunks.player = _player
	_player.spawn_at(_chunks.spawn_world_pos())
	_player.set_frozen(true)   # anti-chute : libéré quand le sol sous le joueur est prêt
	_waiting_ground = true
	_ground_wait_elapsed = 0.0   # ⚠️ RESET : sinon la valeur du 1er atterrissage reste => timeout prématuré au 2e => chute
	_setup_environment(atmo_color)
	# Soleil + ciel + fog dynamiques pilotés par TimeOfDay (point d'atterrissage fixe).
	_sky.setup(_sun, _landing_dir, _surface_env, atmo_color, seed_local)   # seed => aurores déterministes
	# (Sky3D désactivé : non instanciable proprement par code — voir _setup_sky3d. Ciel = sky_dynamic.)
	_lightning.configure(seed_local)   # éclairs déterministes par seed
	# Océan : niveau de mer + teinte partagés avec l'orbite (même seed) ; ciel = atmo_color.
	_ocean.setup(seed_local, _sun, _player, SurfaceGenerator.DEFAULT_VERTICAL_SCALE, SurfaceGenerator.DEFAULT_PLANET_PHYS_RADIUS, atmo_color)
	# Eau inland (phase 23) : rivières + lacs, MÊME shader que l'océan mais SANS courbure de mer (déjà
	# portée par la transform du chunk) + vagues réduites. Matériau PARTAGÉ par tous les chunks, maj/frame.
	_inland_water_mat = ShaderMaterial.new()
	_inland_water_mat.shader = SurfaceOcean.WATER_SHADER
	_inland_water_mat.set_shader_parameter("water_color", PlanetGenerator.water_color(seed_local))
	_inland_water_mat.set_shader_parameter("sky_tint", Vector3(atmo_color.r, atmo_color.g, atmo_color.b))
	_inland_water_mat.set_shader_parameter("planet_radius", 1.0e9)   # drop≈0 : pas de double courbure
	_inland_water_mat.set_shader_parameter("wave_height", 0.08)      # rivières/lacs : rides douces (calme mais pas plat)
	_chunks.set_inland_water_material(_inland_water_mat)
	# Étoiles de nuit : autres systèmes de la galaxie projetés depuis le système courant.
	_starfield.setup(star_systems, system_pos, _landing_dir, _player)
	# Lunes dans le ciel (mêmes seeds que l'orbite => cohérence tri-échelle).
	_surface_moons.setup(MoonsGenerator.generate_moons(seed_local), _landing_dir, _player)

# Accès au ChunkManager (pour l'audio des POI de proximité).
func get_chunk_manager() -> ChunkManager:
	return _chunks

# Info sol sous 'from' via raycast physique vers le bas (collision terrain). { hit, point,
# normal, distance } — sert à valider que le sol est prêt avant le spawn (descente à pied).
func ground_info(from: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	if space == null:
		return {"hit": false, "distance": 9999.0}
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 8000.0)
	if _player:
		q.exclude = [_player.get_rid()]   # ne jamais confondre la capsule du joueur avec le sol
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {"hit": false, "distance": 9999.0}
	return {"hit": true, "point": hit.position, "normal": hit.normal, "distance": from.distance_to(hit.position)}

# Ciel dégradé + brouillard teintés par la couleur d'atmosphère ; soleil = l'étoile.
# Le brouillard est réglé pour masquer l'apparition/disparition des chunks au bord.
func _setup_environment(atmo_color: Color) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = atmo_color.darkened(0.35)
	sky_mat.sky_horizon_color = atmo_color.lightened(0.35)
	sky_mat.ground_horizon_color = atmo_color.lightened(0.1)
	sky_mat.ground_bottom_color = atmo_color.darkened(0.55)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	_surface_env = Environment.new()
	_surface_env.background_mode = Environment.BG_SKY
	_surface_env.sky = sky
	_surface_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_surface_env.fog_enabled = true
	_surface_env.fog_light_color = atmo_color
	# Densité ~ -ln(0.1)/D : brouillard quasi-opaque (~90%) à la distance D du bord de
	# chargement (rayon visuel en chunks * taille) => le bord reste invisible, sans mur.
	var edge := float(ChunkManager.VISUAL_RADIUS) * ChunkManager.CHUNK_SIZE
	_surface_env.fog_density = 2.3 / maxf(edge, 1.0)
	# Post-traitement d'immersion (tonemap AgX / glow / SSAO / SSIL) — partagé avec l'environnement espace.
	ImmersionFX.apply(_surface_env)

	# Le soleil (orientation/énergie/teinte) est désormais piloté par SkyManager (phase 12).

# Environment du ciel surface (appliqué à la caméra active par ViewManager).
func get_environment() -> Environment:
	return _surface_env

# Sky3D (addon) = source du matériau de ciel + nuages volumétriques pour la surface. Lumières & fog de
# Sky3D DÉSACTIVÉS (le projet garde son soleil _sun + brouillard) ; cycle interne en PAUSE — soleil &
# couverture sont poussés chaque frame par SkyManager depuis TimeOfDay/WeatherSystem (cohérence orbite↔sol).
# Détaché de l'arbre hors-surface (shutdown_streaming) pour ne pas concurrencer le WorldEnvironment espace.
func _setup_sky3d() -> void:
	if _sky3d == null:
		_sky3d = Sky3D.new()
		add_child(_sky3d)
		_sky3d.lights_enabled = false
		_sky3d.fog_enabled = false
		_sky3d.clouds_enabled = true
		_sky3d.game_time_enabled = false
		_sky3d.editor_time_enabled = false
		_sky3d.pause()
		if _sky3d.sky:
			_sky3d.sky.cumulus_intensity = 0.7
			_sky3d.sky.wind_speed = 2.0
	elif _sky3d.get_parent() != self:
		add_child(_sky3d)
	if _sky3d.environment and _sky3d.environment.sky:
		_surface_env.sky = _sky3d.environment.sky   # ciel de surface = dôme Sky3D (nuages compris)
	_sky.set_dome(_sky3d.sky)

# Gilet bHaptics — ambiance SURFACE (pluie, vent, battement de cœur au calme). No-op sans gilet.
func _update_ambient_haptics(delta: float) -> void:
	# La vue SURFACE persiste (visible=false) hors-surface : ne JAMAIS jouer l'ambiance en orbite/galaxie.
	if GameState.current_scale != GameState.Scale.SURFACE:
		return
	if _waiting_ground or _player == null or not BHaptics.is_suit_connected():
		return
	var precip := WeatherSystem.get_precipitation() if WeatherSystem.is_configured() else 0.0
	var wind := WeatherSystem.get_wind() if WeatherSystem.is_configured() else 0.0
	var storm := WeatherSystem.get_storm() if WeatherSystem.is_configured() else 0.0
	if precip > 0.25:   # pluie : gouttes éparses, cadence ∝ intensité
		_rain_t += delta
		if _rain_t >= lerpf(0.32, 0.10, clampf(precip, 0.0, 1.0)):
			_rain_t = 0.0
			BHaptics.rain(precip)
	if wind > 0.30:     # vent : bouffées lentes qui enveloppent
		_wind_t += delta
		if _wind_t >= 1.2:
			_wind_t = 0.0
			BHaptics.wind(wind)
	# Battement de cœur : SEULEMENT à l'arrêt prolongé ET par temps calme (immersion contemplative).
	if _player.is_on_floor() and _player.get_real_velocity().length() < 0.6 and storm < 0.25 and precip < 0.4:
		_idle_t += delta
	else:
		_idle_t = 0.0
	if _idle_t > 3.0:
		_heart_t += delta
		if _heart_t >= 1.15:
			_heart_t = 0.0
			BHaptics.heartbeat()

func get_player() -> PlayerController:
	return _player

# Gel anti-chute du joueur (débarquement phase 18) : on GÈLE le pilote au spawn jusqu'à ce que le
# chunk + SA COLLISION sous lui soient prêts (sinon il traverse le sol). Levé par _process via
# is_ground_ready (même mécanisme que le spawn du build marchant phase 6/7).
func begin_ground_wait() -> void:
	if _player:
		_player.set_frozen(true)
		_waiting_ground = true
		_ground_wait_elapsed = 0.0

# Sinus d'altitude du soleil au point d'atterrissage (pour l'ordinateur de poignet).
func sun_altitude() -> float:
	return TimeOfDay.get_sun_altitude(_landing_dir)

# Coord ESPACE-PLANÈTE sous le joueur (pour l'ordinateur de poignet). { valid, coord }.
func player_planet_coord() -> Dictionary:
	if _chunks:
		return _chunks.player_coord()
	return {"valid": false, "coord": Vector2i.ZERO}

# Rayon (m) sous lequel le nom d'un POI notable proche s'affiche au WristComputer (phase 20 couche C).
const POI_NAME_RADIUS := 130.0

# POI notable le plus proche du joueur dans le rayon d'affichage. { name:String (""=aucun), distance }.
func nearest_poi() -> Dictionary:
	if _chunks and _player:
		return _chunks.nearest_poi_name(_player.global_position, POI_NAME_RADIUS)
	return {"name": "", "distance": 0.0}

# Phase 22 : biome sous une position MONDE (pour l'audio de pas).
func biome_at(world_pos: Vector3) -> int:
	if _chunks:
		return _chunks.biome_at_world(world_pos)
	return PlanetGenerator.Biome.PLAINS

# Arrêt propre du streaming (au décollage) : attend les workers, décharge tout.
func shutdown_streaming() -> void:
	_waiting_ground = false
	if _chunks:
		_chunks.shutdown()

# Libère le joueur dès que le chunk (avec collision) sous lui est prêt (anti-chute).
func _process(delta: float) -> void:
	if GameState.current_scale != GameState.Scale.SURFACE:
		return   # SurfaceView masquée hors-surface (visible=false) mais _process tourne : on coupe tout le par-frame
	# Eau inland (phase 23) : vagues animées (temps monde) + spéculaire suivant le soleil (jour/nuit).
	if _inland_water_mat:
		_inland_water_mat.set_shader_parameter("wave_time", float(Time.get_ticks_msec()) * 0.001)
		if _sun:
			_inland_water_mat.set_shader_parameter("sun_direction", _sun.global_transform.basis.z)
			_inland_water_mat.set_shader_parameter("sun_up", smoothstep(-0.08, 0.15, _sun.global_transform.basis.z.y))   # jour/nuit
	if _waiting_ground:
		# Sonde la collision RÉELLE sous le joueur (raycast, exclut le joueur).
		var gi := ground_info(_player.global_position + Vector3.UP * 1.0)
		_ground_wait_elapsed += delta
		# Sol confirmé JUSTE sous le joueur (la porte `< 8.0` suppose un spawn à ~ground+3, cf.
		# ChunkManager.spawn_world_pos — si cet offset change, ajuster ce seuil) => on POSE le joueur
		# EXACTEMENT dessus (au lieu de le lâcher ~3 m au-dessus) PUIS on libère. Poser sur le point
		# d'impact supprime la fenêtre de traversée si la collision du chunk est re-bâtie juste après.
		if gi.hit and gi.distance < 8.0:
			# Sol confirmé JUSTE sous le joueur => on POSE le joueur EXACTEMENT dessus puis on libère.
			_player.spawn_at((gi.point as Vector3) + Vector3.UP * 0.05)
			_player.set_frozen(false)
			_waiting_ground = false
		elif _ground_wait_elapsed > GROUND_WAIT_MAX:
			# Timeout : si la collision est FINALEMENT là (raycast) => POSER dessus (anti-chute) ; sinon
			# re-caler sur le sol ANALYTIQUE et libérer (jamais gelé à vie). ⚠️ `_ground_wait_elapsed`
			# est remis à 0 dans build() — sinon le 2e atterrissage hérite du chrono du 1er => timeout
			# prématuré => chute (bug corrigé).
			if gi.hit:
				_player.spawn_at((gi.point as Vector3) + Vector3.UP * 0.05)
			else:
				var p := _player.global_position
				_player.spawn_at(Vector3(p.x, _chunks.ground_height_at(p) + 1.0, p.z))
			_player.set_frozen(false)
			_waiting_ground = false
	# Lucioles nocturnes (vie ambiante) : nuée ∝ nuit autour du joueur (même seuil que SkyManager).
	if _fireflies:
		_fireflies.update(_player.global_position, 1.0 - smoothstep(-0.05, 0.18, sun_altitude()), delta)
	_update_ambient_haptics(delta)
