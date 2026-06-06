class_name Creature
extends Node3D
## Une créature procédurale (phase 19) : node enfant d'un chunk de terrain. Assemble corps/tête/pattes
## (meshes partagés de FaunaLibrary) en NODES, animés EN CODE chaque frame (pas de Skeleton3D).
## Machine à états IDLE / WANDER / FLEE / REST. Se déplace dans le repère LOCAL du chunk ; suit le sol
## via FaunaGround (sample_elevation, pas de raycast). Réagit au joueur (fuite), au cycle jour/nuit et
## à l'orage (repos). LOD : gèle IA + animation au-delà d'un rayon serré. AUCUNE hostilité.

enum State { IDLE, WANDER, FLEE, REST }

const TURN_RATE := 3.0        # rad/s : vitesse de rotation vers la direction visée
const ARRIVE_DIST := 0.7      # m : distance d'arrivée à la cible WANDER
const WANDER_MIN := 3.0       # m : distance d'errance min/max
const WANDER_MAX := 13.0
const LEG_SWING := 0.5        # rad : amplitude d'oscillation des pattes en marche
const BOB_AMP := 0.05         # m : amplitude du bobbing vertical du corps
const GROUND_LERP := 12.0     # réactivité du collage au sol

const FLEE_SPEED_MULT := 1.9  # la fuite est plus rapide que l'errance
const FLEE_EXIT_MULT := 1.7   # sort de FLEE quand dist(joueur) > flee_radius * ce facteur
const FLEE_MIN_TIME := 0.8    # s : durée minimale de fuite (évite le yo-yo)
const REST_STAND_MULT := 0.5  # le corps s'abaisse au repos (se couche)
const REST_LERP := 5.0        # réactivité du lever/coucher

const NOTICE_RADIUS := 22.0   # m : en deçà et à l'arrêt, la créature tourne la tête vers le joueur
const HEAD_YAW_MAX := 1.2     # rad : débattement max du cou en lacet (~70°)
const HEAD_PITCH_MAX := 0.5   # rad : débattement max en tangage
const HEAD_LERP := 6.0        # réactivité du suivi de tête
const GROUND_RESAMPLE := 0.25 # m : ne ré-échantillonne le sol qu'après ce déplacement (perf)

const ACTIVE_RADIUS := 75.0          # m : au-delà, IA + animation gelées (LOD)
const ACTIVE_RADIUS_RESUME := 66.0   # m : hystérésis de réactivation (rentrer plus près)
const VISIBLE_RADIUS := 140.0        # m : au-delà, non rendu (cull draw calls) ; entre ACTIVE et ça = posé immobile
const LOD_CHECK_INTERVAL := 0.25     # s : cadence du test de distance LOD (+ jitter par créature)
const REST_CHECK_INTERVAL := 0.4     # s : cadence d'évaluation jour-nuit/orage (+ jitter)

var species: Dictionary = {}
var _player: Node3D
var _ground: FaunaGround
var _parts: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _chunk: Node3D              # parent (chunk) — repère de 'position' + conversion monde→local

var _tod                       # autoload TimeOfDay (Variant ; appels dynamiques ; null hors-jeu)
var _weather                   # autoload WeatherSystem (Variant ; null hors-jeu)
var _planet_dir := Vector3.UP  # direction-planète du chunk (altitude solaire locale)

var _state := State.IDLE
var _state_t := 0.0
var _idle_dur := 2.0
var _target := Vector3.ZERO   # destination locale (repère chunk)
var _flee_dir := Vector3.FORWARD
var _flee_t := 0.0
var _walk_phase := 0.0
var _walk_speed := 1.5
var _stand := 1.0
var _body_h := 1.0

# Traits d'espèce mis en cache.
var _flee_radius := 10.0
var _storm_sens := 0.6
var _activity := PlanetFaunaRoster.Activity.DIURNAL
# Phase 22 : voix (appels audio). Params DÉTERMINISTES par espèce ; timing via RNG GLOBAL pour ne PAS
# perturber la séquence du RNG seedé de l'IA (mouvement reste reproductible).
var _voice: Dictionary = {}
var _call_t := 4.0
var _ae: Node

# LOD + repos (throttle).
var _active := true
var _lod_t := 0.0
var _rest_t := 0.0
var _should_rest := false
var _head_yaw := 0.0
var _head_pitch := 0.0
var _g_x := 0.0   # cache du dernier échantillonnage de sol (évite sample_elevation à l'arrêt)
var _g_z := 0.0
var _g_y := 0.0

# Nodes assemblés.
const TORTUE_MODEL := "res://models/tortue.glb"   # remplace l'assemblage procédural (les mobs = tortues)
var _body: Node3D
var _head: MeshInstance3D
var _legs: Array[MeshInstance3D] = []

# Installe l'espèce + assemble les nodes. 'spawn_seed' rend déterministes la 1re durée d'idle + jitters.
func setup(sp: Dictionary, parts: Dictionary, mat: Material, player: Node3D, ground: FaunaGround, spawn_seed: int) -> void:
	species = sp
	_parts = parts
	_player = player
	_ground = ground
	_chunk = get_parent() as Node3D
	_stand = parts.stand_height
	_body_h = _stand
	_walk_speed = sp.get("walk_speed", 1.5)
	_flee_radius = sp.get("flee_radius", 10.0)
	_storm_sens = sp.get("storm_sensitivity", 0.6)
	_activity = int(sp.get("activity", PlanetFaunaRoster.Activity.DIURNAL))
	_rng.seed = spawn_seed
	_idle_dur = _rng.randf_range(1.5, 5.0)
	# Décale les throttles par créature (évite que toutes testent la même frame).
	_lod_t = _rng.randf_range(0.0, LOD_CHECK_INTERVAL)
	_rest_t = _rng.randf_range(0.0, REST_CHECK_INTERVAL)
	_tod = get_node_or_null("/root/TimeOfDay")
	_weather = get_node_or_null("/root/WeatherSystem")
	_ae = get_node_or_null("/root/AudioEngine")
	_voice = CreatureVoice.voice_params(int(sp.get("key", spawn_seed)))   # phase 22 : timbre par espèce
	_call_t = randf_range(2.0, 8.0)
	if _ground:
		_planet_dir = _ground.planet_dir()
	_build_nodes(mat)
	_snap_to_ground()
	set_process(true)

func _build_nodes(mat: Material) -> void:
	# Visuel = modèle TORTUE (GLB), un seul node auto-échelle, à la place de l'assemblage corps/tête/pattes.
	# L'IA/déplacement reste identique ; pas de pattes animées (léger bob conservé). _head/_legs restent vides.
	_body = Node3D.new()
	_body.position = Vector3(0.0, _stand, 0.0)
	add_child(_body)
	var res = load(TORTUE_MODEL)
	var inst: Node3D = null
	if res is PackedScene:
		inst = (res as PackedScene).instantiate()
	if inst != null:
		_body.add_child(inst)
		inst.rotation.y = PI   # le modèle tortue regarde +Z ; le sens de marche est -Z => demi-tour (sinon recule)
		CombatUtil.disable_shadows(inst)
		var r := CombatUtil.scene_aabb(inst, Transform3D.IDENTITY)
		var target := maxf(_stand * 1.8, 0.7)   # envergure cible ∝ stature de l'espèce
		if r.has and (r.box as AABB).size.length() > 0.0001:
			var ab: AABB = r.box
			var longest: float = maxf(maxf(ab.size.x, ab.size.y), ab.size.z)
			var sc: float = target / maxf(longest, 0.0001)
			# centre le modèle + pose-le AU SOL (le corps est à y=_stand, on redescend la tortue d'autant).
			inst.position = (-ab.get_center() * sc) + Vector3(0.0, -_stand + ab.size.y * sc * 0.5, 0.0)
			inst.scale = Vector3(sc, sc, sc)
	else:
		var mi := MeshInstance3D.new()   # repli : ancien corps procédural si le GLB manque
		mi.mesh = _parts.body
		mi.material_override = mat
		_body.add_child(mi)
	_head = null
	_legs.clear()

func _process(dt: float) -> void:
	# LOD : gèle IA + animation au-delà du rayon serré (test de distance throttlé).
	_lod_t -= dt
	if _lod_t <= 0.0:
		_lod_t = LOD_CHECK_INTERVAL
		_update_active()
	if not _active:
		return
	_state_t += dt
	# Priorité 1 : fuite du joueur (interrompt errance/repos).
	_update_flee_trigger()
	# Priorité 2 : repos selon jour-nuit + orage (évalué périodiquement).
	_rest_t -= dt
	if _rest_t <= 0.0:
		_rest_t = REST_CHECK_INTERVAL
		_update_rest_decision()
	_apply_rest_transition()
	match _state:
		State.IDLE:
			_update_idle()
		State.WANDER:
			_update_wander(dt)
		State.FLEE:
			_update_flee(dt)
		State.REST:
			pass  # immobile ; le corps se couche dans _animate()
	var moving := _state == State.WANDER or _state == State.FLEE
	var cadence := 1.6
	if _state == State.FLEE:
		cadence = _walk_speed * 4.0
	elif _state == State.WANDER:
		cadence = _walk_speed * 3.0
	_walk_phase += dt * cadence
	_follow_ground(dt)
	_animate(moving, dt)
	_update_head(dt)
	_maybe_call(dt)

# Phase 22 : appel audio occasionnel. SILENCIEUX en FUITE et REPOS (=> respecte le cycle d'activité,
# car REST = espèce inactive). Positionnel à la créature, dans un rayon audible. RNG GLOBAL (n'altère
# pas l'IA seedée). Proba par espèce (call_chance dérivé du seed).
func _maybe_call(dt: float) -> void:
	if _ae == null or _player == null or _state == State.FLEE or _state == State.REST:
		return
	_call_t -= dt
	if _call_t > 0.0:
		return
	_call_t = randf_range(4.0, 9.0)
	if global_position.distance_to(_player.global_position) > 50.0:
		return
	if randf() < float(_voice.get("call_chance", 0.2)) and _ae.has_method("creature_call"):
		_ae.creature_call(global_position, _voice)

# --- LOD ---

func _update_active() -> void:
	if _player == null:
		_active = true
		visible = true
		return
	var d := global_position.distance_to(_player.global_position)
	visible = d <= VISIBLE_RADIUS    # cull du rendu au-delà (borne les draw calls)
	var was := _active
	if _active:
		_active = d <= ACTIVE_RADIUS
	else:
		_active = d <= ACTIVE_RADIUS_RESUME
	if was and not _active:
		_freeze_pose()               # fige une posture neutre (pas de patte en plein élan)

# Repose les membres + le corps en posture stable — une créature gelée ne reste pas en plein pas.
func _freeze_pose() -> void:
	for leg in _legs:
		leg.rotation.x = 0.0
	var base := _stand * (REST_STAND_MULT if _state == State.REST else 1.0)
	_body_h = base
	if _body:
		_body.position.y = base

# --- États ---

func _update_idle() -> void:
	if _state_t >= _idle_dur:
		_pick_wander_target()
		_state = State.WANDER
		_state_t = 0.0

func _update_wander(dt: float) -> void:
	var to := _target - position
	to.y = 0.0
	var d := to.length()
	if d < ARRIVE_DIST:
		_state = State.IDLE
		_state_t = 0.0
		_idle_dur = _rng.randf_range(2.0, 6.0)
		return
	var dir := to / d
	_face(dir, dt)
	position += dir * _walk_speed * dt

func _pick_wander_target() -> void:
	var ang := _rng.randf() * TAU
	var dist := _rng.randf_range(WANDER_MIN, WANDER_MAX)
	_target = position + Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)

# --- Fuite (step 7) : la créature s'éloigne du joueur quand il s'approche trop ---

func _update_flee_trigger() -> void:
	if _player == null or _state == State.FLEE:
		return
	var pl := _player_local()
	var dx := position.x - pl.x
	var dz := position.z - pl.z
	if dx * dx + dz * dz < _flee_radius * _flee_radius:
		_enter_flee(pl)

func _enter_flee(player_local: Vector3) -> void:
	var away := position - player_local
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3(cos(_walk_phase), 0.0, sin(_walk_phase))  # dégénéré : cap arbitraire
	_flee_dir = away.normalized()
	_state = State.FLEE
	_state_t = 0.0
	_flee_t = 0.0

func _update_flee(dt: float) -> void:
	_flee_t += dt
	var pl := _player_local()
	var to_p := pl - position
	to_p.y = 0.0
	var d := to_p.length()
	# Sort de la fuite (hystérésis + durée mini) quand le joueur est assez loin.
	if _flee_t > FLEE_MIN_TIME and d > _flee_radius * FLEE_EXIT_MULT:
		_state = State.IDLE
		_state_t = 0.0
		_idle_dur = _rng.randf_range(1.0, 3.0)
		return
	if d > 0.01:
		_flee_dir = -to_p / d  # recalcule à l'opposé du joueur (qui bouge)
	_face(_flee_dir, dt)
	position += _flee_dir * _walk_speed * FLEE_SPEED_MULT * dt

# Position du joueur dans le repère LOCAL du chunk (même espace que 'position').
func _player_local() -> Vector3:
	if _chunk == null or _player == null:
		return position + Vector3(0.0, 0.0, 1000.0)  # « très loin » : pas de fuite
	return _chunk.to_local(_player.global_position)

# --- Repos (step 8) : cycle d'activité jour/nuit + mise à l'abri par gros orage ---

func _update_rest_decision() -> void:
	var rest := false
	if _weather != null and _weather.get_storm() > _storm_sens:
		rest = true  # orage au-delà de la tolérance de l'espèce -> se met à l'abri
	elif _tod != null:
		var alt = _tod.get_sun_altitude(_planet_dir)  # SUN·up : >0 jour, <0 nuit
		match _activity:
			PlanetFaunaRoster.Activity.NOCTURNAL:
				rest = alt > 0.05            # dort le jour
			PlanetFaunaRoster.Activity.CREPUSCULAR:
				rest = absf(alt) > 0.55      # actif au crépuscule ; dort en plein jour / nuit profonde
			_:  # DIURNAL
				rest = alt < -0.05           # dort la nuit
	_should_rest = rest

func _apply_rest_transition() -> void:
	if _state == State.FLEE:
		return  # la fuite prime toujours sur le repos
	if _should_rest and _state != State.REST:
		_state = State.REST
		_state_t = 0.0
	elif not _should_rest and _state == State.REST:
		_state = State.IDLE
		_state_t = 0.0
		_idle_dur = _rng.randf_range(1.0, 3.0)

# Oriente le lacet vers une direction locale horizontale (le nez de la créature = -Z).
func _face(dir: Vector3, dt: float) -> void:
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = _approach_angle(rotation.y, target_yaw, TURN_RATE * dt)

# Step 10 : à l'arrêt (IDLE/REST) et joueur proche, la tête se tourne vers lui (cou borné) ;
# sinon elle revient doucement face à l'avant. Donne une présence « consciente » sans coût notable.
func _update_head(dt: float) -> void:
	if _head == null:
		return
	var want_yaw := 0.0
	var want_pitch := 0.0
	if (_state == State.IDLE or _state == State.REST) and _player != null:
		var dp := _player_local() - position
		if dp.length() < NOTICE_RADIUS:
			var local := transform.basis.inverse() * dp   # direction du joueur en repère créature
			var horiz := Vector2(local.x, local.z).length()
			if horiz > 0.001:
				want_yaw = clampf(atan2(-local.x, -local.z), -HEAD_YAW_MAX, HEAD_YAW_MAX)
				want_pitch = clampf(atan2(local.y, horiz), -HEAD_PITCH_MAX, HEAD_PITCH_MAX)
	var k := clampf(HEAD_LERP * dt, 0.0, 1.0)
	_head_yaw = lerpf(_head_yaw, want_yaw, k)
	_head_pitch = lerpf(_head_pitch, want_pitch, k)
	_head.rotation.y = _head_yaw
	_head.rotation.x = _head_pitch

# --- Sol + animation ---

func _snap_to_ground() -> void:
	if _ground:
		_g_x = position.x
		_g_z = position.z
		_g_y = _ground.local_ground_y(position.x, position.z)
		position.y = _g_y

func _follow_ground(dt: float) -> void:
	if _ground == null:
		return
	# Ne ré-échantillonne le sol que si la créature a bougé : les immobiles (IDLE/REST) ne coûtent
	# plus aucun sample_elevation par frame (gros gain quand beaucoup de créatures sont actives).
	if absf(position.x - _g_x) > GROUND_RESAMPLE or absf(position.z - _g_z) > GROUND_RESAMPLE:
		_g_x = position.x
		_g_z = position.z
		_g_y = _ground.local_ground_y(position.x, position.z)
	position.y = lerpf(position.y, _g_y, clampf(GROUND_LERP * dt, 0.0, 1.0))

# Animation procédurale : pattes en oscillation sinusoïdale déphasée (marche), bobbing du corps,
# abaissement progressif au repos (se couche).
func _animate(moving: bool, dt: float) -> void:
	var swing := LEG_SWING if moving else 0.0
	for i in _legs.size():
		# Déphasage : alterne un côté sur deux + décalage avant/arrière => démarche lisible.
		var phase := _walk_phase + (PI if (i % 2) == 1 else 0.0) + float(i / 2) * 0.6
		_legs[i].rotation.x = sin(phase) * swing
	var resting := _state == State.REST
	var base := _stand * (REST_STAND_MULT if resting else 1.0)
	_body_h = lerpf(_body_h, base, clampf(REST_LERP * dt, 0.0, 1.0))
	var bob_amp := 0.0
	if moving:
		bob_amp = BOB_AMP
	elif not resting:
		bob_amp = BOB_AMP * 0.35
	_body.position.y = _body_h + sin(_walk_phase * 2.0) * bob_amp

# Rapproche un angle 'a' de 'b' d'au plus 'max_step' (gère le wrap ±π).
static func _approach_angle(a: float, b: float, max_step: float) -> float:
	var diff := wrapf(b - a, -PI, PI)
	if absf(diff) <= max_step:
		return b
	return a + signf(diff) * max_step
