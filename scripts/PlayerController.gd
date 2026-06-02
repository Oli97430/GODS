class_name PlayerController
extends CharacterBody3D
## Contrôleur joueur double mode pour l'échelle SURFACE (up = +Y monde, gravité
## droite — PAS de gravité sphérique).
##   BUREAU : WASD + souris (yaw corps / pitch caméra) + saut.
##   XR     : rig XROrigin reparenté sous le corps, locomotion stick relative à la
##            tête, snap-turn (confort), roomscale (le corps suit le casque).
## Inactif hors SURFACE (activé par ViewManager via enter_desktop/enter_xr).

signal step(world_pos: Vector3)   # phase 22 : émis à chaque foulée (audio de pas, cadence = vitesse)

const SPEED := 4.5
const STRIDE := 1.7               # m parcourus entre deux foulées
const JUMP_VELOCITY := 5.0
const MOUSE_SENS := 0.0025
const PITCH_LIMIT := 1.4
# XR
const XR_SPEED := 3.0
const SNAP_TURN_DEG := 30.0           # défaut (l'angle réel est lu dans Settings.snap_angle)
const SMOOTH_TURN_DEG_PER_S := 90.0   # °/s en rotation continue (smooth) si choisie dans les options
const STICK_DEADZONE := 0.3
# --- Parapente (vol plané ; déployable EN L'AIR, atterrissage = retour marche) ---
const GLIDE_SPEED := 13.0       # vitesse-air de croisière (m/s)
const GLIDE_SPEED_MIN := 8.0    # freiné (proche décrochage)
const GLIDE_SPEED_MAX := 20.0   # accéléré (piqué)
const GLIDE_RATIO := 8.0        # finesse : chute = vitesse / finesse
const GLIDE_TURN_RATE := 0.8    # rad/s en virage plein
const GLIDE_ACCEL := 6.0        # m/s² lissage de la vitesse-air vers la cible
const WIND_DRIFT := 0.7         # m/s de dérive par unité de WeatherSystem.get_wind()
const WIND_DIR := Vector3(1.0, 0.0, 0.4)   # direction MONDE de la dérive (normalisée à l'usage)
const LEAN_DEADZONE := 0.06     # m : zone morte du transfert de poids (XR)
const LEAN_STEER_GAIN := 5.0    # XR : lean latéral (m) -> virage
const LEAN_PITCH_GAIN := 4.0    # XR : lean avant/arrière (m) -> vitesse/frein
const CAMERA_ROLL := 0.35       # rad : roulis caméra BUREAU en virage (confort ; nul en XR)
const THERMAL_LIFT := 2.6       # m/s de portance max dans une ascendance (spiraler => reprendre de l'altitude)
const GLIDE_FOV_ADD := 12.0     # ° de FOV ajoutés à pleine vitesse en vol (sensation de vitesse, BUREAU)
const FLY_FOV_ADD := 16.0       # ° de FOV ajoutés à pleine vitesse en armure Iron Man (impression de vitesse, BUREAU ; discret)
# --- Armure Iron Man (2e équipement) : vol libre type repulseurs, sans gravité, INVISIBLE (aucun modèle) ---
const FLY_SPEED := 24.0         # m/s — vol Iron Man (rapide mais maîtrisable)
const FLY_BOOST := 2.3          # multiplicateur de boost (Maj / gâchette)
const FLY_ACCEL := 7.0          # réactivité : lerp de la vitesse vers la cible (inertie légère)

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _active := false
var _frozen := false   # gel anti-chute : gravité/locomotion suspendues (sol pas encore prêt)
var _xr := false
var _pitch := 0.0
var _snap_armed := true
# Parapente
var _gliding := false
var _glide_speed := 0.0
var _bank := 0.0                  # virage courant lissé (-1..1) : visuel voile + roulis caméra
var _glide_time := 0.0            # temps écoulé depuis le déploiement (grâce anti-repli immédiat)
var _deploy_prev := false         # front montant de la commande déployer/replier
var _lean_neutral := Vector3.ZERO # XR : position tête (repère corps) au déploiement = neutre transfert de poids
var _paraglider: Paraglider
var _base_fov := 75.0   # FOV caméra bureau au repos (élargi en vol pour la sensation de vitesse)
var _flying := false    # armure Iron Man : vol libre sans gravité (exclusif avec le parapente)
var _fly_prev := false  # front montant du toggle vol (touche F / bouton B XR)
var _repulsor: OmniLight3D   # lueur de repulseur (armure invisible) : éclaire le sol sous le joueur en vol
var _speed_streaks   # lignes de vitesse Iron Man (SpeedStreaks.gd) — non typé : appel dynamique de update_streaks
var _vignette        # vignette de confort VR (ComfortVignette.gd) — se resserre avec la vitesse (anti-nausée)
var _stuck_t := 0.0   # anti-blocage : temps passé à "vouloir marcher sans avancer" (enfoncé/coincé)
# Retour haptique XR (no-op en bureau) — état de suivi des différents pulses.
var _step_foot := 1      # alterne le tic de foulée gauche/droite
var _was_air := false    # suivi air->sol pour le "thump" d'atterrissage (marche)
var _air_vy := 0.0       # vitesse verticale mémorisée en l'air (intensité du thump)
var _fly_buzz_t := 0.0   # throttle du rumble continu des repulseurs (vol Iron Man)
var _therm_buzz_t := 0.0 # throttle du frisson haptique en ascendance (parapente)

var _collision: CollisionShape3D
var _eyes: Camera3D        # caméra bureau (yeux)
var _xr_anchor: Node3D     # point de reparentage du rig XR (aux pieds)
var _xr_origin: Node3D         # rig XR reparenté (mode XR)
var _xr_camera: Camera3D       # XRCamera3D du rig
var _left: XRController3D      # manette gauche (locomotion)
var _right: XRController3D     # manette droite (snap-turn)

func _ready() -> void:
	# Marche : autorise des pentes plus raides (jusqu'à 60° au lieu de 45°) => on ne reste pas bloqué au
	# fond d'une cuvette ou au pied d'un relief un peu raide ; au-delà (vraies falaises) reste infranchissable.
	floor_max_angle = deg_to_rad(60.0)
	# Capsule humaine (~1.7 m), pieds à y=0.
	_collision = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	_collision.shape = cap
	_collision.position = Vector3(0, 0.85, 0)
	add_child(_collision)
	# Caméra bureau (yeux ~1.6 m).
	_eyes = Camera3D.new()
	_eyes.position = Vector3(0, 1.6, 0)
	_eyes.current = false
	add_child(_eyes)
	# Ancre du rig XR (aux pieds).
	_xr_anchor = Node3D.new()
	add_child(_xr_anchor)
	# Parapente : voilure procédurale au-dessus des épaules, masquée tant que non déployée.
	_paraglider = Paraglider.new()
	_paraglider.position = Vector3(0.0, 1.5, 0.0)
	add_child(_paraglider)
	# Repulseur Iron Man : lueur bleutée qui éclaire le sol sous le joueur pendant le vol (éteinte sinon).
	_repulsor = OmniLight3D.new()
	_repulsor.light_color = Color(0.6, 0.78, 1.0)
	_repulsor.omni_range = 28.0
	_repulsor.light_energy = 0.0
	_repulsor.shadow_enabled = false
	_repulsor.position = Vector3(0.0, 0.6, 0.0)
	add_child(_repulsor)
	# Lignes de vitesse "Iron Man" (impression de vitesse en vol libre) — preload pour éviter le cache de classe.
	_speed_streaks = preload("res://scripts/SpeedStreaks.gd").new()
	add_child(_speed_streaks)
	# Vignette de confort VR (tunnel-vision anti-nausée pilotée par la vitesse).
	_vignette = preload("res://scripts/ComfortVignette.gd").new()
	add_child(_vignette)
	set_physics_process(false)
	set_process_unhandled_input(false)

# --- Activation (ViewManager) ---

func spawn_at(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO

# Gel anti-chute : tant que gelé, ni gravité ni locomotion (le joueur reste au spawn
# le temps que le chunk + sa collision sous lui soient prêts). Levé par SurfaceView.
func set_frozen(frozen: bool) -> void:
	_frozen = frozen
	if frozen:
		velocity = Vector3.ZERO

# Mode bureau : caméra FPS courante + souris capturée.
func enter_desktop() -> void:
	_active = true
	_xr = false
	_eyes.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	set_physics_process(true)
	set_process_unhandled_input(true)

# Mode XR : reparente le rig sous l'ancre (aux pieds) et active la locomotion.
func enter_xr(xr_origin: Node3D, xr_camera: Camera3D, left: XRController3D, right: XRController3D) -> void:
	_active = true
	_xr = true
	_xr_origin = xr_origin
	_xr_camera = xr_camera
	_left = left
	_right = right
	_xr_origin.reparent(_xr_anchor, false)
	_xr_origin.transform = Transform3D.IDENTITY
	set_physics_process(true)
	set_process_unhandled_input(false)

# Désactive le contrôleur. Le retour du rig XR à Main est géré par ViewManager.
func exit() -> void:
	_active = false
	if _gliding:
		_stow()
	_flying = false
	_fly_prev = false
	_deploy_prev = false
	_frozen = false   # ne pas laisser un gel zombie : un futur re-spawn qui ne repasse pas par build() figerait le joueur
	if _vignette:
		_vignette.clear()   # sinon la vignette resterait figée à l'écran hors-surface
	_eyes.rotation.z = 0.0
	_eyes.current = false
	if not _xr:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_physics_process(false)
	set_process_unhandled_input(false)

func get_active_camera() -> Camera3D:
	return _xr_camera if _xr else _eyes

# --- Retour haptique XR (no-op en bureau) ---
# Pulse sur les manettes via l'action OpenXR "haptic". amp 0..1, durée s, freq Hz (0 = défaut runtime).
# which : -1 gauche, +1 droite, 0 = les deux. Ignore une manette non active (mains nues / non suivie).
func _haptic(amp: float, dur: float, freq: float = 0.0, which: int = 0) -> void:
	if not _xr:
		return
	amp = clampf(amp, 0.0, 1.0)
	if which <= 0 and _left != null and _left.get_is_active():
		_left.trigger_haptic_pulse("haptic", freq, amp, dur, 0.0)
	if which >= 0 and _right != null and _right.get_is_active():
		_right.trigger_haptic_pulse("haptic", freq, amp, dur, 0.0)

# --- Bureau : souris (yaw corps, pitch caméra) ---
func _unhandled_input(event: InputEvent) -> void:
	if not _active or _xr:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENS, -PITCH_LIMIT, PITCH_LIMIT)
		_eyes.rotation.x = _pitch

func _physics_process(delta: float) -> void:
	if not _active or _frozen:
		return
	if GameState.options_open:   # menu Options ouvert : gèle la locomotion (pas d'entrée jeu)
		if _vignette:
			_vignette.place(get_active_camera(), 0.0, delta)   # résorbe la vignette (sinon figée derrière le menu si ouvert en vol)
		return
	_update_equipment()
	if _flying:
		_fly(delta)
	elif _gliding:
		_glide(delta)
	elif _xr:
		_physics_xr(delta)
	else:
		_physics_desktop(delta)
	_update_steps(delta)
	_update_paraglider(delta)
	if not _flying and not _gliding:
		_anti_stuck(delta)
		_update_landing()
	# Vignette de confort : se resserre ∝ vitesse réelle (vol/glisse rapides = vection max => anti-nausée).
	if _vignette:
		var amt := (Settings.vignette_strength * smoothstep(4.0, 18.0, get_real_velocity().length())) if Settings.vignette_on else 0.0
		_vignette.place(get_active_camera(), amt, delta)

# Anti-blocage universel (marche) : si on POUSSE pour avancer mais qu'on n'avance pas (capsule enfoncée
# dans le relief après un atterrissage rapide), on s'extrait vers la surface du sol après ~1 s. Ne fait
# rien quand on bute juste contre un mur en surface (le sol n'est pas au-dessus des pieds).
func _anti_stuck(delta: float) -> void:
	var trying := Vector2(velocity.x, velocity.z).length() > 1.0
	var rv := get_real_velocity()
	var moving := Vector2(rv.x, rv.z).length() > 0.3
	if trying and not moving:
		_stuck_t += delta
	else:
		_stuck_t = 0.0
		return
	if _stuck_t < 1.0:
		return
	_stuck_t = 0.0
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var from := global_position + Vector3.UP * 4.0
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 14.0)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		global_position.y += 3.0   # pas de sol trouvé sous nous => on remonte (anti-enfoncement profond)
	elif (hit.position as Vector3).y > global_position.y - 0.4:
		global_position = (hit.position as Vector3) + Vector3.UP * 0.1   # sol au-dessus des pieds => enfoncé => extraire
	velocity = Vector3.ZERO

# Thump d'atterrissage (marche) : à la reprise de contact avec le sol après une phase en l'air, pulse les
# deux manettes proportionnellement à la vitesse d'impact (saut, fin de chute). No-op en bureau.
func _update_landing() -> void:
	var on_floor := is_on_floor()
	if not on_floor:
		_air_vy = velocity.y                              # mémorise la vitesse de chute tant qu'on est en l'air
	elif _was_air:
		var impact := clampf(-_air_vy / 8.0, 0.0, 1.0)    # ~8 m/s de chute => thump plein
		if impact > 0.05:
			_haptic(0.3 + 0.55 * impact, 0.11, 0.0, 0)
			BHaptics.landing(impact)   # gilet X40 : secousse d'atterrissage (pondérée bas du torse)
	_was_air = not on_floor

# Équipements : touche F / bouton B (XR) = armure Iron Man (vol libre invisible) ; touche E / bouton A
# (XR) = parapente. EXCLUSIFS : enfiler l'armure replie le parapente ; le parapente est inactif en vol.
func _update_equipment() -> void:
	var fly_pressed := false
	if _xr:
		fly_pressed = _right != null and _right.get_is_active() and _right.is_button_pressed("by_button")
	else:
		fly_pressed = Input.is_physical_key_pressed(KEY_F)
	if fly_pressed and not _fly_prev:
		_toggle_fly()
	_fly_prev = fly_pressed
	if not _flying:
		_update_deploy()   # parapente (E) — désactivé pendant le vol Iron Man

# Phase 22 : accumule la distance horizontale parcourue au sol ; émet `step` chaque STRIDE mètres
# (=> cadence proportionnelle à la vitesse, naturelle). Émis aux pieds (global_position, y aux pieds).
var _stride_accum := 0.0
func _update_steps(delta: float) -> void:
	if not is_on_floor():
		return
	var hv := Vector2(velocity.x, velocity.z).length()
	if hv < 0.6:
		_stride_accum = STRIDE * 0.5   # repart « à mi-pas » à l'arrêt (1er pas rapide au redémarrage)
		return
	_stride_accum += hv * delta
	if _stride_accum >= STRIDE:
		_stride_accum = 0.0
		step.emit(global_position)
		_step_foot = -_step_foot
		_haptic(0.18, 0.03, 0.0, _step_foot)   # foulée : petit tic alterné gauche/droite (XR)

# Bureau : WASD (touches physiques => pas de dépendance à l'InputMap), saut, gravité.
func _physics_desktop(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_physical_key_pressed(KEY_SPACE):
		velocity.y = JUMP_VELOCITY

	var ix := 0.0
	var iz := 0.0
	if Input.is_physical_key_pressed(KEY_D):
		ix += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		ix -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		iz += 1.0
	if Input.is_physical_key_pressed(KEY_W):
		iz -= 1.0
	var dir := (transform.basis * Vector3(ix, 0.0, iz)).normalized()
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	move_and_slide()

# XR : roomscale (corps suit le casque) + locomotion stick relative à la tête +
# gravité. Le snap-turn est géré séparément (front montant du stick droit).
func _physics_xr(delta: float) -> void:
	# 1) Roomscale : déplace le corps sous le casque, et contre-déplace le rig pour
	#    que la tête reste au même endroit dans le monde (puis la collision agit).
	if _xr_camera:
		var off := Vector3(_xr_camera.global_position.x - global_position.x, 0.0, _xr_camera.global_position.z - global_position.z)
		global_position += off
		_xr_origin.global_position -= off

	# 2) Gravité + SAUT (A droit) — permet de décoller pour déployer le parapente au casque (miroir d'Espace au bureau).
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif _right and _right.get_is_active() and _right.is_button_pressed("ax_button"):
		velocity.y = JUMP_VELOCITY
	else:
		velocity.y = 0.0

	# 3) Locomotion fluide : stick gauche, relatif à l'orientation de la TÊTE (confort).
	var move := Vector3.ZERO
	if _left and _left.get_is_active():
		var stick := _left.get_vector2("primary")
		if stick.length() > STICK_DEADZONE:
			var hb := _xr_camera.global_transform.basis
			var fwd := Vector3(hb.z.x, 0.0, hb.z.z).normalized()   # -fwd = avant ; voir signe ci-dessous
			var right := Vector3(hb.x.x, 0.0, hb.x.z).normalized()
			# stick.y > 0 (poussée avant) => avancer (vers -z tête) ; stick.x => latéral.
			move = (right * stick.x - fwd * stick.y) * XR_SPEED
	velocity.x = move.x
	velocity.z = move.z

	move_and_slide()

	# 4) Rotation confort (stick droit horizontal) : par CRAN (snap, défaut) ou CONTINUE (smooth), au choix
	#    dans les Options. Le snap-turn est le plus confortable au casque ; la rotation continue convient
	#    aux joueurs aguerris (moins de saccades, mais plus de vection).
	if _right and _right.get_is_active():
		var turn := _right.get_vector2("primary").x
		if Settings.turn_mode == 1:        # rotation CONTINUE (smooth)
			if absf(turn) > STICK_DEADZONE:
				_rotate_around_camera(deg_to_rad(-turn * SMOOTH_TURN_DEG_PER_S * delta))
		else:                              # rotation PAR CRAN (snap)
			if _snap_armed and absf(turn) > 0.7:
				_rotate_around_camera(deg_to_rad(-signf(turn) * Settings.snap_angle))
				_snap_armed = false
				_haptic(0.22, 0.04, 0.0, 0)   # tic de confirmation du snap-turn (confort)
			elif absf(turn) < 0.3:
				_snap_armed = true

# Fait pivoter le corps autour de la position du casque (la tête reste fixe).
func _rotate_around_camera(angle: float) -> void:
	var pivot := _xr_camera.global_position
	var rot := Basis(Vector3.UP, angle)
	var o := global_transform.origin - pivot
	global_transform = Transform3D(rot * global_transform.basis, rot * o + pivot)

# --- Parapente ---

# Déploiement/repli (front montant : touche E bureau / bouton A manette droite XR). Déploiement
# UNIQUEMENT en l'air (saute d'une hauteur d'abord) ; repli à tout moment ; atterrissage = repli auto.
func _update_deploy() -> void:
	var pressed := false
	if _xr:
		pressed = _left != null and _left.get_is_active() and _left.is_button_pressed("ax_button")   # parapente = X gauche (saut = A droit)
	else:
		pressed = Input.is_physical_key_pressed(KEY_E)
	if pressed and not _deploy_prev:
		if _gliding:
			_stow()
		elif not is_on_floor():
			_deploy()
	_deploy_prev = pressed

# Vol plané : vitesse-air vers l'avant + chute douce (finesse) + virage. Pilotage par transfert de
# poids en XR (lean), souris/clavier en bureau, stick en secours. Atterrissage (sol) = repli auto.
func _glide(delta: float) -> void:
	_glide_time += delta
	var steer := 0.0
	var trim := 0.0
	if _xr:
		if _xr_camera:
			# Décalage tête vs neutre, repère corps. INVARIANT au yaw de virage (on tourne autour de la tête).
			var hl := to_local(_xr_camera.global_position) - _lean_neutral
			steer = _lean_axis(hl.x, LEAN_STEER_GAIN)     # pencher à droite => virer à droite
			trim = _lean_axis(-hl.z, LEAN_PITCH_GAIN)     # pencher en avant (-z) => accélérer
		if _left and _left.get_is_active():               # stick gauche en secours
			var s := _left.get_vector2("primary")
			if absf(s.x) > STICK_DEADZONE:
				steer = s.x
			if absf(s.y) > STICK_DEADZONE:
				trim = s.y
	else:
		if Input.is_physical_key_pressed(KEY_D):
			steer += 1.0
		if Input.is_physical_key_pressed(KEY_A):
			steer -= 1.0
		if Input.is_physical_key_pressed(KEY_W):
			trim += 1.0
		if Input.is_physical_key_pressed(KEY_S):
			trim -= 1.0
	steer = clampf(steer, -1.0, 1.0)
	trim = clampf(trim, -1.0, 1.0)

	# Virage : en XR on pivote autour de la tête (elle reste fixe => confort) ; en bureau, simple yaw.
	var turn := steer * GLIDE_TURN_RATE * delta
	if _xr:
		_rotate_around_camera(-turn)
	else:
		rotate_y(-turn)
	_bank = lerpf(_bank, steer, clampf(5.0 * delta, 0.0, 1.0))

	# Vitesse-air pilotée par le trim (frein <-> piqué).
	var target_speed := GLIDE_SPEED
	if trim >= 0.0:
		target_speed = lerpf(GLIDE_SPEED, GLIDE_SPEED_MAX, trim)
	else:
		target_speed = lerpf(GLIDE_SPEED, GLIDE_SPEED_MIN, -trim)
	_glide_speed = move_toward(_glide_speed, target_speed, GLIDE_ACCEL * delta)

	# Taux de chute : finesse + pénalité de virage + décrochage si trop freiné.
	var sink := _glide_speed / GLIDE_RATIO + absf(steer) * 1.2
	if trim < -0.6:
		sink += (-trim - 0.6) * 5.0
	# Ascendances : patches de portance (champ lent en XZ monde) ; en plein dedans la chute s'annule voire
	# devient montée => on peut spiraler pour reprendre de l'altitude (vol contemplatif).
	var th := sin(global_position.x * 0.0019 + global_position.z * 0.0007) * sin(global_position.z * 0.0023 - global_position.x * 0.0005)
	var lift := smoothstep(0.35, 0.9, th)
	sink -= lift * THERMAL_LIFT
	# Frisson haptique léger en ascendance (sentir le thermique pour spiraler) — throttle ~0.12 s.
	_therm_buzz_t += delta
	if lift > 0.25 and _therm_buzz_t >= 0.12:
		_therm_buzz_t = 0.0
		_haptic(0.06 + 0.12 * lift, 0.05, 0.0, 0)

	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var wind := Vector3.ZERO
	if WeatherSystem.is_configured():
		wind = WIND_DIR.normalized() * (WeatherSystem.get_wind() * WIND_DRIFT)
	velocity = fwd * _glide_speed + Vector3.UP * (-sink) + wind
	move_and_slide()
	# Atterrissage = repli (retour marche). ANTICIPÉ : dès que le sol est proche (raycast ~2 m) on se replie
	# AVANT l'impact => pas d'enfoncement dans une pente raide (crête de cratère / flanc de volcan). Filets de
	# sécurité : contact sol/paroi, ou fortement bloqué. Grâce de 0.25 s pour ne pas se replier au déploiement.
	if _glide_time > 0.25 and (is_on_floor() or is_on_wall() or _ground_near(2.0) or get_real_velocity().length() < _glide_speed * 0.4):
		_stow()

# Vrai si le sol (collision) est à moins de `dist` sous les pieds (raycast, exclut sa propre capsule).
# Sert à anticiper l'atterrissage en parapente avant l'impact.
func _ground_near(dist: float) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var from := global_position + Vector3.UP * 0.3
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (dist + 0.3))
	q.exclude = [get_rid()]
	return not space.intersect_ray(q).is_empty()

# Axe de transfert de poids (XR) : décalage (m) -> commande -1..1 avec zone morte.
func _lean_axis(v: float, gain: float) -> float:
	if absf(v) <= LEAN_DEADZONE:
		return 0.0
	return clampf((v - signf(v) * LEAN_DEADZONE) * gain, -1.0, 1.0)

func _deploy() -> void:
	_gliding = true
	_glide_time = 0.0
	_glide_speed = maxf(Vector2(velocity.x, velocity.z).length(), GLIDE_SPEED * 0.85)
	_bank = 0.0
	if _xr and _xr_camera:
		_lean_neutral = to_local(_xr_camera.global_position)
	if _paraglider:
		_paraglider.deploy()
	_haptic(0.7, 0.18, 0.0, 0)   # ouverture de voile : à-coup ferme sur les deux mains
	BHaptics.deploy()            # gilet X40 : à-coup épaules/poitrine (la sellette tire)

func _stow() -> void:
	if not _gliding:
		return
	_gliding = false
	if _paraglider:
		_paraglider.stow()
	_haptic(0.35, 0.09, 0.0, 0)   # repli de la voile / pieds au sol
	BHaptics.soft_tap(28.0)       # gilet X40 : repli en douceur
	_was_air = false              # évite un "thump" parasite à la reprise de la marche
	# Atterrissage PROPRE : si le sol est proche, on repose les pieds dessus (anti-enfoncement après un
	# plané rapide dans une pente) et on coupe la vitesse => repart à la marche sans rester coincé.
	# Repli en altitude (G manuel) : aucun sol proche => pas de snap, la gravité reprend normalement.
	var space := get_world_3d().direct_space_state
	if space:
		var from := global_position + Vector3.UP * 2.0
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 8.0)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			global_position = (hit.position as Vector3) + Vector3.UP * 0.03
			velocity = Vector3.ZERO

# Enfile / retire l'armure Iron Man. Enfiler : replie le parapente + démarre en stationnaire (gravité OFF).
# Retirer : la gravité reprend (chute si en l'air — ré-enfiler pour se rattraper).
func _toggle_fly() -> void:
	_flying = not _flying
	_was_air = false
	if _flying:
		if _gliding:
			_stow()
		velocity = Vector3.ZERO
		_fly_buzz_t = 0.0
		_haptic(0.6, 0.14, 0.0, 0)   # armure : enclenchement des repulseurs
		BHaptics.armor_on()          # gilet X40 : mise sous tension de l'armure
	else:
		_haptic(0.3, 0.08, 0.0, 0)   # armure : extinction
		BHaptics.soft_tap(26.0)      # gilet X40 : extinction

# Vol "Iron Man" (armure invisible) : déplacement libre SANS gravité, dans la direction du regard,
# stationnaire au repos. BUREAU : WASD relatif caméra (3D : viser haut = monter) + Espace (haut) /
# C (bas) / Maj (boost) + souris (viser). XR : stick gauche (3D relatif tête) + stick droit Y (vertical).
func _fly(delta: float) -> void:
	var wish := Vector3.ZERO
	var boost := 1.0
	if _xr:
		if _left and _left.get_is_active():
			var s := _left.get_vector2("primary")
			if s.length() > STICK_DEADZONE:
				var hb := _xr_camera.global_transform.basis
				wish += -hb.z * s.y + hb.x * s.x   # 3D relatif tête (viser haut + pousser = monter)
		if _right and _right.get_is_active():
			var ry := _right.get_vector2("primary").y
			if absf(ry) > STICK_DEADZONE:
				wish += Vector3.UP * ry
	else:
		var cb := _eyes.global_transform.basis
		if Input.is_physical_key_pressed(KEY_W):
			wish += -cb.z
		if Input.is_physical_key_pressed(KEY_S):
			wish += cb.z
		if Input.is_physical_key_pressed(KEY_D):
			wish += cb.x
		if Input.is_physical_key_pressed(KEY_A):
			wish += -cb.x
		if Input.is_physical_key_pressed(KEY_SPACE):
			wish += Vector3.UP
		if Input.is_physical_key_pressed(KEY_C):
			wish += Vector3.DOWN
		if Input.is_physical_key_pressed(KEY_SHIFT):
			boost = FLY_BOOST
	var target := Vector3.ZERO
	if wish.length() > 0.05:
		target = wish.normalized() * FLY_SPEED * boost   # au repos => cible nulle => vol stationnaire
	velocity = velocity.lerp(target, clampf(FLY_ACCEL * delta, 0.0, 1.0))
	# Lueur du repulseur : base en vol, plus forte à la poussée / au boost.
	if _repulsor:
		var tgt_e := 0.6 + 1.8 * clampf(wish.length(), 0.0, 1.0)
		if boost > 1.0:
			tgt_e += 1.2
		_repulsor.light_energy = lerpf(_repulsor.light_energy, tgt_e, clampf(6.0 * delta, 0.0, 1.0))
	# Rumble continu des repulseurs (throttle ~0.06 s) : intensité selon la poussée + le boost.
	_fly_buzz_t += delta
	if _fly_buzz_t >= 0.06:
		_fly_buzz_t = 0.0
		var wl := clampf(wish.length(), 0.0, 1.0)
		var rb := 0.08 + 0.22 * wl
		var fi := wl
		if boost > 1.0:
			rb += 0.15
			fi = minf(1.0, wl + 0.3)
		_haptic(rb, 0.07, 0.0, 0)
		BHaptics.flight_rumble(fi)   # gilet X40 : grondement continu des repulseurs (poitrine/dos)
	move_and_slide()
	if _speed_streaks:               # lignes de vitesse ∝ vitesse de vol
		_speed_streaks.update_streaks(get_active_camera(), velocity, clampf(velocity.length() / FLY_SPEED, 0.0, 1.0), delta)
	# Atterrissage AUTO : posé au sol, stabilisé, sans poussée vers le haut => l'armure se désactive pour
	# la marche (sinon on reste "en vol" collé au sol, à pousser dans le terrain => "ne bouge plus").
	var up_held := Input.is_physical_key_pressed(KEY_SPACE)
	if _xr:
		up_held = _right != null and _right.get_is_active() and _right.get_vector2("primary").y > STICK_DEADZONE
	if is_on_floor() and not up_held and get_real_velocity().length() < 1.2:
		_flying = false
		velocity = Vector3.ZERO
		_haptic(0.35, 0.09, 0.0, 0)   # posé en douceur (fin de vol)
		BHaptics.soft_tap(30.0)       # gilet X40 : posé en douceur

# Attitude de la voile (roll/pitch) + roulis caméra bureau (confort : nul en XR).
func _update_paraglider(delta: float) -> void:
	if _paraglider and _gliding:
		var pitch := clampf((_glide_speed - GLIDE_SPEED) / 12.0, -0.4, 0.4)
		_paraglider.set_attitude(_bank, pitch, delta)
	if not _xr:
		var target := (-_bank * CAMERA_ROLL) if _gliding else 0.0
		_eyes.rotation.z = lerpf(_eyes.rotation.z, target, clampf(8.0 * delta, 0.0, 1.0))
		# Sensation de vitesse : FOV élargi avec la vitesse (parapente ou armure), revient au repos au sol.
		var add_fov := 0.0
		if _gliding:
			add_fov = GLIDE_FOV_ADD * clampf((_glide_speed - GLIDE_SPEED_MIN) / (GLIDE_SPEED_MAX - GLIDE_SPEED_MIN), 0.0, 1.0)
		elif _flying:
			add_fov = FLY_FOV_ADD * clampf(velocity.length() / FLY_SPEED, 0.0, 1.0)   # punch FOV armure = + marqué
		_eyes.fov = lerpf(_eyes.fov, _base_fov + add_fov, clampf(3.0 * delta, 0.0, 1.0))
	# Repulseur Iron Man : s'éteint en douceur dès qu'on ne vole plus (XR compris).
	if _repulsor and not _flying:
		_repulsor.light_energy = lerpf(_repulsor.light_energy, 0.0, clampf(6.0 * delta, 0.0, 1.0))
	# Lignes de vitesse : s'estompent quand on ne vole plus (XR compris).
	if _speed_streaks and not _flying:
		_speed_streaks.update_streaks(get_active_camera(), Vector3.ZERO, 0.0, delta)
