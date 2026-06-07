class_name PlayerController
extends CharacterBody3D
## Contrôleur joueur double mode pour l'échelle SURFACE (up = +Y monde, gravité
## droite — PAS de gravité sphérique).
##   BUREAU : WASD + souris (yaw corps / pitch caméra) + saut.
##   XR     : rig XROrigin reparenté sous le corps, locomotion stick relative à la
##            tête, snap-turn (confort), roomscale (le corps suit le casque).
## Inactif hors SURFACE (activé par ViewManager via enter_desktop/enter_xr).

signal step(world_pos: Vector3)   # phase 22 : émis à chaque foulée (audio de pas, cadence = vitesse)
signal impact(world_pos: Vector3, strength: float)   # atterrissage de PUISSANCE (chute rapide) : gerbe de débris + onde de choc

const SPEED := 4.5
const STRIDE := 1.7               # m parcourus entre deux foulées
const JUMP_VELOCITY := 5.0
const POWER_LAND_SPEED := 11.0   # m/s de chute (vers le bas) au-delà desquels l'atterrissage devient un IMPACT de puissance
const PLUG_FALL_SPEED := 7.0     # m/s de chute au-delà desquels la prise s'allume aussi (plongeon/saut de falaise) — sentir le souffle avant l'impact
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
const WIND_DIR := Vector3(1.0, 0.0, 0.4)   # direction MONDE de la dérive
var _wind_dir_n := Vector3(1.0, 0.0, 0.4).normalized()   # précalculée une fois (évite un sqrt par frame de plané)
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
# --- Nage sous-marine (univers sous-marin) : corps immergé => gravité OFF + flottabilité + mouvement 3D ---
const SEA_Y := 0.0             # Y monde de la surface de mer (= PlanetGenerator.sea_level_height, DEFAULT_SEA_LEVEL=0)
const SWIM_SPEED := 3.6        # m/s — nage de croisière (lente, contemplative)
const SWIM_BOOST := 1.8        # multiplicateur de nage rapide (Maj / boost)
const SWIM_ACCEL := 3.0        # réactivité aquatique (drag : on glisse jusqu'à l'arrêt en lâchant)
const BUOYANCY := 1.2          # m/s² — flottabilité douce : on remonte tout seul, tête vers la surface
const SWIM_ENTER_DEPTH := 1.4  # m d'eau au-dessus des pieds pour passer en nage (~hauteur de poitrine)
const SWIM_EXIT_DEPTH := 1.0   # m : sous ce seuil + pieds au fond => on repose le pied et on remarche (bord/plage)

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
var _swimming := false  # nage sous-marine : corps immergé (poitrine) => gravité OFF + flottabilité (exclusif marche)
var _fly_prev := false  # front montant du toggle vol (touche F / bouton B XR)
var _repulsor: OmniLight3D   # lueur de repulseur (armure invisible) : éclaire le sol sous le joueur en vol
var _speed_streaks   # lignes de vitesse Iron Man (SpeedStreaks.gd) — non typé : appel dynamique de update_streaks
var _vignette        # vignette de confort VR (ComfortVignette.gd) — se resserre avec la vitesse (anti-nausée)
var _lamp: SpotLight3D   # lampe nocturne : suit la caméra (bureau) / la main droite (XR) ; activable montre ou touche L
var _lamp_on := false
var _lamp_prev := false  # front montant de la touche L (bureau)
# Combat OPT-IN (mode FPS VR) : armes équipables (revolver + plasma). Dégainé => zéro effet (contemplatif).
var _revolver             # Blaster.gd configuré en revolver « blaster » (cyan)
var _plasma               # Blaster.gd configuré en fusil à plasma (vert, zoom avancé)
var _grenade              # Blaster.gd en mode PROJECTILE : lance-grenades (explosif, dégâts de zone)
var _harvest_tool         # HarvestTool : outil de récolte UNIQUE (abat les arbres ET casse les rochers)
var _tool = null          # outil équipé (node) ou null — EXCLUSIF avec les armes
var _tool_prev := false   # front touche H (bureau)
var _blaster              # arme ACTIVE (= _revolver / _plasma / _grenade ; null = dégainé)
var _plasma_scope         # ScopeView.gd : lunette VR (zoom optique SubViewport) montée sur le plasma
var _armed := false       # une arme est équipée
var _dprompt_yes_prev := false   # front de la réponse OUI au prompt « mode Drone »
var _dprompt_no_prev := false    # front de la réponse NON au prompt « mode Drone »
# Holster VR : zones de saisie sur le corps (repère tête + lacet). Main droite + grip près d'une zone => (dé)gaine.
const HOLSTER_RADIUS := 0.20   # m : rayon de saisie autour d'un point d'arme
var _grip_prev := false        # front montant du grip droit (évite la répétition tant que le grip reste tenu)
var _fire_cd := 0.0       # cooldown de tir
var _arm_prev := false    # front montant touche B (revolver)
var _plasma_prev := false # front montant touche V (plasma)
var _grenade_prev := false # front montant touche N (lance-grenades)
var _shield               # Shield.gd : bouclier d'énergie main gauche (déployé avec le blaster)
const SHIELD_BLOCK_RADIUS := 0.62   # m : rayon d'interception d'un bolt par le bouclier (suit la taille du bouclier)
const HP_MAX := 100.0
var _hp := HP_MAX         # PV joueur (combat opt-in) ; restauré à plein au (ré)équipement
var _hurt_t := 0.0        # minuterie de flash d'encaissement (s)
var _invuln_t := 0.0      # brève invulnérabilité (équipement / réapparition)
var _dead := false        # éliminé : locomotion gelée le temps de la réapparition
var _respawn_t := 0.0     # compte à rebours de réapparition (s)
var _combat_overlay       # CombatOverlay.gd : voile rouge tête-bloquée (flash/mort/PV bas), VR + bureau
var _hit_indicator        # HitIndicator.gd : flèche directionnelle « d'où vient le tir » (VR + bureau)
var _combat_readout       # CombatReadout.gd : lecture VAGUE/PV/Score tête-bloquée (VR — le HUD plat est masqué en XR)
var _hit_dir := Vector3.ZERO   # direction monde du dernier tir encaissé (vers le tireur)
var _hit_dir_t := 0.0     # minuterie d'affichage de la flèche directionnelle (s)
var _heal_t := 0.0        # minuterie du pulse de soin vert (s)
var _dmg_mult := 1.0      # x dégâts (améliorations ramassées, portée RUN)
var _firerate_mult := 1.0 # x cadence de tir (améliorations)
var _overshield := 0.0    # PV de bouclier en sus (améliorations), absorbés avant les PV
var _pickup_msg := ""     # annonce brève de ramassage (affichée sur le readout)
var _pickup_msg_t := 0.0  # minuterie de l'annonce de ramassage (s)
# Missile à tête chercheuse (tir SECONDAIRE du plasma, munitions LOOTÉES) : verrou À MAINTENIR + tir vers un drone.
const MISSILE_DMG := 200.0          # gros dégât (= plafond RPC coop) => détruit tout drone réaliste
const MISSILE_LOCK_ANGLE := 16.0    # ° : demi-cône de verrouillage autour de l'axe du canon plasma
const MISSILE_LOCK_RANGE := 70.0    # m : portée de verrouillage
const MISSILE_LOCK_DWELL := 0.4     # s : durée à garder la cible dans le cône avant que le verrou accroche
var _missile_ammo := 0              # munitions missile (= miroir de Inventory.missiles, source persistante)
var _lock_candidate: Node3D = null  # drone dans le cône (verrouillage EN COURS)
var _lock_target: Node3D = null     # drone VERROUILLÉ (cible du prochain missile ; null tant que pas accroché)
var _lock_t := 0.0                  # minuterie de maintien du verrou
var _locked := false                # verrou accroché ?
var _lock_spin := 0.0               # rotation de l'anneau de verrou
var _missile_prev := false          # front du tir secondaire (gâchette gauche VR / clic-molette bureau)
var _lock_ring: MeshInstance3D = null
# Holster VR : repères visuels révélés à l'approche de la main + tic haptique à l'entrée de zone.
const HOLSTER_REVEAL := 0.45        # m : distance à laquelle le repère de holster commence à apparaître
const HOLSTER_MARK_SIZE := 0.05     # m : rayon du repère (sphère) au plus proche
var _holster_marks: Array = []      # 3 MeshInstance3D (hanche D / hanche G / épaule)
var _holster_in := [false, false, false, false]   # main DANS chaque zone de saisie (pour le tic d'entrée)
var _stuck_t := 0.0   # anti-blocage : temps passé à "vouloir marcher sans avancer" (enfoncé/coincé)
# Retour haptique XR (no-op en bureau) — état de suivi des différents pulses.
var _step_foot := 1      # alterne le tic de foulée gauche/droite
var _was_air := false    # suivi air->sol pour le "thump" d'atterrissage (marche)
var _air_vy := 0.0       # vitesse verticale mémorisée en l'air (intensité du thump)
var _fall_vy := 0.0      # impact de puissance : vitesse de chute la plus forte depuis le décollage (la plus négative)
var _impact_was_air := false   # suivi air->sol pour l'impact de puissance (indépendant du thump de marche)
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
	# Surcouche combat (voile rouge tête-bloquée : encaissement / mort / PV bas) — VR + bureau.
	_combat_overlay = preload("res://scripts/CombatOverlay.gd").new()
	add_child(_combat_overlay)
	# Indicateur directionnel « d'où vient le tir » (flèche tête-bloquée) — VR + bureau.
	_hit_indicator = preload("res://scripts/HitIndicator.gd").new()
	add_child(_hit_indicator)
	# Lecture combat tête-bloquée (VR) : VAGUE / PV / Score toujours visible pendant le combat.
	_combat_readout = preload("res://scripts/CombatReadout.gd").new()
	add_child(_combat_readout)
	# Lampe nocturne : spot orientable, éteint par défaut. Suit la caméra (bureau) ou la main droite (XR).
	_lamp = SpotLight3D.new()
	_lamp.light_color = Color(1.0, 0.96, 0.85)
	_lamp.light_energy = 6.0
	_lamp.spot_range = 34.0
	_lamp.spot_angle = 33.0
	_lamp.spot_angle_attenuation = 1.1
	_lamp.shadow_enabled = false
	_lamp.visible = false
	add_child(_lamp)
	# Armes (combat opt-in) : revolver + fusil à plasma, créés masqués sous le joueur ; l'arme active est
	# parentée à la main à l'équipement (_equip). Le plasma surcharge la config (modèle, couleur, zoom avancé).
	_revolver = preload("res://scripts/Blaster.gd").new()
	_revolver.visible = false
	add_child(_revolver)
	_plasma = preload("res://scripts/Blaster.gd").new()
	_plasma.weapon_name = "Plasma"
	_plasma.model_path = "res://models/plasma_gun.glb"
	_plasma.model_length = 0.42
	_plasma.muzzle_up_frac = 0.05
	_plasma.bolt_color = Color(0.45, 1.0, 0.55)
	_plasma.charged_color = Color(0.7, 1.0, 0.4)
	_plasma.fire_interval = 0.34
	_plasma.fire_interval_ads = 0.7
	_plasma.zoom_fov = 38.0          # zoom AVANCÉ (bureau)
	_plasma.dmg = 2.0
	_plasma.dmg_charged = 4.0
	# Ressenti renforcé : bolt visuel qui voyage, gros flash de bouche, recul + haptique appuyés.
	_plasma.bolt_travel = true
	_plasma.bolt_speed = 130.0
	_plasma.muzzle_energy = 10.0
	_plasma.recoil_kick = 0.045
	_plasma.recoil_pitch = 13.0
	_plasma.fire_haptic = 0.75
	_plasma.fire_haptic_ads = 0.95
	_plasma.vest_recoil = 0.7         # recul gilet moyen (arme à énergie)
	_plasma.visible = false
	add_child(_plasma)
	# Lance-grenades : Blaster en mode PROJECTILE (balistique + explosion de zone). Canon +Z comme les autres.
	_grenade = preload("res://scripts/Blaster.gd").new()
	_grenade.weapon_name = "Grenade"
	_grenade.model_path = "res://models/grenade_launcher.glb"
	_grenade.model_length = 0.40
	_grenade.muzzle_up_frac = 0.06
	_grenade.bolt_color = Color(1.0, 0.6, 0.15)       # orange explosif
	_grenade.charged_color = Color(1.0, 0.82, 0.3)
	_grenade.fire_interval = 0.9                       # arme lourde : cadence lente
	_grenade.fire_interval_ads = 1.1
	_grenade.zoom_fov = 8.0
	_grenade.projectile_mode = true
	_grenade.grenade_speed = 26.0
	_grenade.grenade_gravity = 22.0
	_grenade.grenade_fuse = 3.0
	_grenade.grenade_damage = 5.0
	_grenade.grenade_blast = 6.0
	_grenade.vest_recoil = 1.0         # recul gilet lourd (lance-grenades)
	_grenade.visible = false
	add_child(_grenade)
	# Outil de récolte UNIQUE (hache+pioche, même GLB) — attaché à la main à l'équipement (comme les armes).
	_harvest_tool = preload("res://scripts/Tool.gd").new()
	_harvest_tool.visible = false
	add_child(_harvest_tool)
	_blaster = null
	# Bouclier d'énergie main gauche (déployé avec le blaster).
	_shield = preload("res://scripts/Shield.gd").new()
	_shield.visible = false
	add_child(_shield)
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
	_attach_weapon_to(_shield, _eyes, Transform3D(Basis(), Vector3(-0.16, -0.12, -0.34)))    # viewmodel bouclier (gauche) — l'arme s'attache à l'équipement
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
	# Bouclier RIGIDEMENT solidaire de la main gauche (l'arme active s'attache à la main droite à l'équipement).
	_attach_weapon_to(_shield, _left, Transform3D(Basis(), Vector3(0.0, 0.0, -0.08)))
	set_physics_process(true)
	set_process_unhandled_input(false)

# Désactive le contrôleur. Le retour du rig XR à Main est géré par ViewManager.
func exit() -> void:
	_active = false
	if _gliding:
		_stow()
	_flying = false
	_swimming = false
	_lamp_on = false
	if _lamp:
		_lamp.visible = false
	_armed = false
	_blaster = null
	for g in [_revolver, _plasma, _grenade]:
		if g:
			g.visible = false
			_attach_weapon_to(g, self, Transform3D.IDENTITY)
	if _plasma_scope:
		_plasma_scope.set_active(false)   # coupe le rendu lunette (sinon le SubViewport continuerait de rendre)
	if _plasma:
		_plasma.sight_enabled = true
	if _shield:
		_shield.visible = false
		_attach_weapon_to(_shield, self, Transform3D.IDENTITY)
	_fly_prev = false
	_deploy_prev = false
	# Reset des suivis air->sol : sinon un futur re-spawn (sans repasser par build) émettrait un "thump"/impact fantôme.
	_was_air = false
	_impact_was_air = false
	_air_vy = 0.0
	_fall_vy = 0.0
	_stuck_t = 0.0
	_frozen = false   # ne pas laisser un gel zombie : un futur re-spawn qui ne repasse pas par build() figerait le joueur
	if _vignette:
		_vignette.clear()   # sinon la vignette resterait figée à l'écran hors-surface
	if _combat_overlay:
		_combat_overlay.clear()
	if _combat_readout:
		_combat_readout.clear()
	# Combat polish : masque l'anneau de verrou + les repères de holster en quittant la surface.
	_locked = false
	_lock_candidate = null
	if _lock_ring:
		_lock_ring.visible = false
	for m in _holster_marks:
		if is_instance_valid(m):
			m.visible = false
	_holster_in = [false, false, false, false]
	_dead = false
	_hp = HP_MAX
	_hurt_t = 0.0
	_respawn_t = 0.0
	GameState.combat_active = false
	GameState.combat_dead = false
	_eyes.rotation.z = 0.0
	_eyes.current = false
	if not _xr:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_physics_process(false)
	set_process_unhandled_input(false)

func get_active_camera() -> Camera3D:
	return _xr_camera if _xr else _eyes

# Lampe nocturne : bascule on/off (appelée par la montre XR ou la touche L bureau). Retourne le nouvel état.
func toggle_lamp() -> bool:
	_lamp_on = not _lamp_on
	if _lamp:
		_lamp.visible = _lamp_on
	_haptic(0.2, 0.05, 0.0, 0)
	return _lamp_on

# Combat opt-in : équipe / dégaine le blaster (appelé par la montre XR ou la touche B bureau). Retourne l'état.
func toggle_weapon() -> bool:
	_equip(null if _blaster == _revolver else _revolver)
	return _armed

# Équipe / dégaine le fusil à plasma (montre XR / touche V bureau).
func toggle_plasma() -> bool:
	_equip(null if _blaster == _plasma else _plasma)
	return _armed

# Équipe / dégaine le lance-grenades (montre XR / touche N bureau).
func toggle_grenade() -> bool:
	_equip(null if _blaster == _grenade else _grenade)
	return _armed

# --- Outil de récolte UNIQUE (hache+pioche) : équipe / range. EXCLUSIF avec les armes. ---
func toggle_tool() -> bool:
	_equip_tool(null if _tool == _harvest_tool else _harvest_tool)
	return _tool != null

func active_tool() -> String:
	return "tool" if _tool != null else ""

func _equip_tool(t) -> void:
	if t != null and _armed:
		_equip(null)   # une seule chose en main droite : range l'arme d'abord
	_holster_tool()
	_tool = t
	if t != null:
		t.visible = true
		_attach_weapon_to(t, _weapon_target(), _tool_offset())
	_haptic(0.3, 0.06, 0.0, 1)

func _holster_tool() -> void:
	if _harvest_tool:
		_harvest_tool.visible = false
		_attach_weapon_to(_harvest_tool, self, Transform3D.IDENTITY)
	_tool = null

func _tool_offset() -> Transform3D:
	return Transform3D.IDENTITY if _xr else Transform3D(Basis(), Vector3(0.12, -0.10, -0.25))

# Sort l'arme `w` (ou null = dégainer) : range les deux armes, attache la nouvelle à la main, montre le bouclier.
func _equip(w) -> void:
	var was_armed := _armed   # pour distinguer une SORTIE fraîche (désarmé->armé) d'un CHANGEMENT d'arme (armé->arme)
	if w != null and _tool != null:
		_holster_tool()   # une arme en main => range l'outil de récolte (exclusif)
	for g in [_revolver, _plasma, _grenade]:
		if g:
			g.visible = false
			_attach_weapon_to(g, self, Transform3D.IDENTITY)
	if w == null:
		_blaster = null
		_armed = false
	else:
		_blaster = w
		_armed = true
		w.visible = true
		_attach_weapon_to(w, _weapon_target(), _weapon_offset())
		AudioEngine.warmup_combat()   # pré-génère les WAV de combat => pas de hitch au 1er tir/impact/vague
		# Lunette VR : créée à la 1re sortie du plasma (monde prêt), montée sur l'arme (suit son parentage).
		if w == _plasma and _plasma_scope == null:
			_plasma_scope = preload("res://scripts/ScopeView.gd").new()
			_plasma.add_child(_plasma_scope)
			_plasma_scope.position = Vector3(0.0, 0.055, 0.05)   # au-dessus/arrière du canon, verre vers l'œil
			_plasma_scope.setup(get_world_3d(), _plasma.bolt_color)
	# Lunette éteinte tant qu'on n'est pas plasma+visée (rallumée par _update_weapon) ; réticule flottant rétabli.
	if _plasma:
		_plasma.sight_enabled = true
	if _plasma_scope and _blaster != _plasma:
		_plasma_scope.set_active(false)
	# Combat opt-in : on (ré)initialise le RUN (PV pleins + brève grâce + buffs remis à zéro) UNIQUEMENT sur une
	# SORTIE d'arme fraîche (désarmé->armé) ou un dégainage (->désarmé). Un CHANGEMENT d'arme en plein combat
	# (armé->autre arme) CONSERVE le run : PV, améliorations ramassées et progression des vagues INCHANGÉS
	# (ni soin gratuit, ni invulnérabilité gratuite en switchant d'arme).
	var fresh_draw := _armed and not was_armed
	if fresh_draw or not _armed:
		_hp = HP_MAX
		_dead = false
		_hurt_t = 0.0
		_respawn_t = 0.0
		_invuln_t = 1.5 if _armed else 0.0
		_reset_buffs()   # améliorations ramassées = portée RUN (réinit. à la sortie fraîche / au dégainage)
		GameState.combat_hp = _hp
		GameState.combat_hp_max = HP_MAX
		GameState.combat_dead = false
		_hit_dir_t = 0.0
		_heal_t = 0.0
	GameState.combat_active = _armed
	# Mode Drone (vagues) opt-in : à chaque SORTIE d'arme FRAÎCHE on DEMANDE avant de lancer les ennemis ; un simple
	# changement d'arme ne redemande pas ; le rangement réinitialise. (Invité coop : rejoint direct la session de l'hôte.)
	if fresh_draw:
		if NetworkManager.is_active() and not NetworkManager.is_host():
			GameState.drone_mode_prompt = false
			GameState.drone_mode_on = true
		else:
			GameState.drone_mode_prompt = true
			GameState.drone_mode_on = false
	elif not _armed:
		GameState.drone_mode_prompt = false
		GameState.drone_mode_on = false
	if not _armed:
		if _combat_overlay:
			_combat_overlay.clear()
		if _hit_indicator:
			_hit_indicator.clear()
	if _shield:
		_shield.visible = _armed
	_haptic(0.3, 0.07, 0.0, 1)

func _weapon_target() -> Node3D:
	return _right if (_xr and _right != null) else _eyes

func _weapon_offset() -> Transform3D:
	return Transform3D.IDENTITY if _xr else Transform3D(Basis(), Vector3(0.12, -0.10, -0.20))

# Combat : le joueur est-il armé (une arme équipée) ? Lu par le WaveManager (ennemis opt-in).
func is_armed() -> bool:
	return _armed

# --- Récolte (CP2) : point de la main droite (VR) / devant la caméra (bureau), entrée de cueillette, retour ---
func tool_hand_point() -> Vector3:
	if _xr and _right != null and is_instance_valid(_right):
		return _right.global_position
	var cam := get_active_camera()
	if cam != null:
		return cam.global_position - cam.global_transform.basis.z * 0.7
	return global_position

# Vrai si le joueur essaie de cueillir MAINTENANT (mains nues = NON armé ; gâchette droite VR / clic gauche bureau).
func harvest_pressed() -> bool:
	if _armed or _dead:
		return false
	if _xr:
		return _right != null and _right.get_is_active() and _right.get_float("trigger") > 0.6
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

# Retour sensoriel d'une cueillette réussie (petit « plop » + pulse haptique main droite).
func harvest_feedback() -> void:
	_haptic(0.35, 0.06, 0.0, 1)
	AudioEngine.play_ui_confirm()

# Édition des constructions (CP4) : valeur du grip droit VR (0..1) quand mains libres ; 0 sinon / au bureau.
# Utilisé par BuildManager pour « grip court = déplacer / grip long = supprimer » la pièce visée.
func build_edit_grip() -> float:
	if _xr and not _armed and not _dead and _right != null and _right.get_is_active():
		return _right.get_float("grip")
	return 0.0

# Prompt « lancer le mode Drone ? » à la sortie d'arme : OUI = gâchette DROITE (VR) / touche Y (bureau),
# NON = gâchette GAUCHE (VR) / touche N (bureau). Le tir reste suspendu tant qu'on n'a pas répondu (cf. _update_weapon).
func _update_drone_prompt() -> void:
	if not GameState.drone_mode_prompt:
		_dprompt_yes_prev = false
		_dprompt_no_prev = false
		return
	if GameState.current_scale != GameState.Scale.SURFACE:
		GameState.drone_mode_prompt = false   # hors surface : pas de mode Drone
		return
	var yes := false
	var no := false
	if _xr:
		yes = _right != null and _right.get_is_active() and _right.get_float("trigger") > 0.6
		no = _left != null and _left.get_is_active() and _left.get_float("trigger") > 0.6
	else:
		yes = Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_Y)
		no = Input.is_key_pressed(KEY_BACKSPACE)   # PAS Échap (ui_cancel) ni N (lance-grenades)
	var yes_edge := yes and not _dprompt_yes_prev
	var no_edge := no and not _dprompt_no_prev
	_dprompt_yes_prev = yes
	_dprompt_no_prev = no
	if yes_edge:
		GameState.drone_mode_prompt = false
		GameState.drone_mode_on = true
		AudioEngine.play_wave_start()       # confirme : les vagues démarrent
		_haptic(0.5, 0.10, 0.0, 1)
	elif no_edge:
		GameState.drone_mode_prompt = false
		GameState.drone_mode_on = false
		_haptic(0.2, 0.05, 0.0, 0)

# Nom de l'arme active ("Blaster" / "Plasma" / "" si dégainé) — pour l'UI montre.
func active_weapon_name() -> String:
	return _blaster.weapon_name if _blaster != null else ""

# Holster VR : main DROITE près d'une zone du corps + grip (front montant) => (dé)gaine l'arme mappée. Équiper
# arme directement le joueur (is_armed) => le combat démarre sans passer par la montre. Zones relatives à la tête.
func _update_holster() -> void:
	if _xr_camera == null or _right == null or not _right.get_is_active():
		return
	var ht := _xr_camera.global_transform
	var fwd := -ht.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)   # droite horizontale du corps (depuis le lacet de la tête)
	var hp := ht.origin
	var rp := _right.global_position
	# Zones de saisie (position, id arme, couleur du repère). Hanches plus bas ; épaule plus haut + en arrière.
	var zones := [
		[hp + right * 0.20 + Vector3.DOWN * 0.62 + fwd * 0.04, 0, Color(0.4, 0.9, 1.0)],   # hanche D -> revolver
		[hp - right * 0.20 + Vector3.DOWN * 0.62 + fwd * 0.04, 2, Color(1.0, 0.6, 0.15)],  # hanche G -> grenade
		[hp + right * 0.17 + Vector3.DOWN * 0.06 - fwd * 0.14, 1, Color(0.45, 1.0, 0.55)], # épaule D -> plasma
		[hp - right * 0.17 + Vector3.DOWN * 0.06 - fwd * 0.14, 3, Color(0.6, 0.45, 0.25)], # épaule G -> outil de récolte
	]
	_ensure_holster_markers()
	var best := -1
	var bd := HOLSTER_RADIUS
	for zi in zones.size():
		var z = zones[zi]
		var zp: Vector3 = z[0]
		var d: float = rp.distance_to(zp)
		# Repère : révélé / agrandi / illuminé à mesure que la main approche (anti-clutter quand on explore).
		var near01 := clampf(1.0 - d / HOLSTER_REVEAL, 0.0, 1.0)
		var m: MeshInstance3D = _holster_marks[zi]
		m.visible = near01 > 0.02
		if m.visible:
			m.global_position = zp
			m.scale = Vector3.ONE * (lerpf(0.5, 1.3, near01) * HOLSTER_MARK_SIZE)
			var c: Color = z[2]
			c.a = lerpf(0.1, 0.9, near01)
			(m.material_override as StandardMaterial3D).albedo_color = c
		# Tic haptique au FRANCHISSEMENT (entrée) de la zone de saisie.
		var inside := d < HOLSTER_RADIUS
		if inside and not _holster_in[zi]:
			_haptic(0.3, 0.05, 0.0, 1)
		_holster_in[zi] = inside
		if d < bd:
			bd = d
			best = z[1]
	# Saisie au FRONT du grip droit (dégainer / rengainer selon la zone la plus proche).
	var grip: bool = _right.get_float("grip") > 0.6
	var edge: bool = grip and not _grip_prev
	_grip_prev = grip
	if not edge:
		return
	if best == 0:
		toggle_weapon()
	elif best == 1:
		toggle_plasma()
	elif best == 2:
		toggle_grenade()
	elif best == 3:
		toggle_tool()
	if best >= 0:
		_haptic(0.5, 0.1, 0.0, 1)   # retour de saisie (manette droite)

# Crée paresseusement les 3 repères de holster (sphères additives top_level, masquées par défaut).
func _ensure_holster_markers() -> void:
	if not _holster_marks.is_empty():
		return
	for i in 4:
		var m := MeshInstance3D.new()
		m.top_level = true
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 10
		sm.rings = 6
		m.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
		m.material_override = mat
		m.visible = false
		add_child(m)
		_holster_marks.append(m)

# --- Missile à tête chercheuse (tir SECONDAIRE du plasma) ---
# Actif uniquement plasma dégainé. Verrou auto sur le drone le plus aligné avec le canon (cône), tir au front
# de la gâchette GAUCHE (VR) / clic-molette (bureau) si munitions. Coop : le missile frappe la cible (réelle ou
# fantôme) via take_damage -> l'invité rapporte le coup à l'hôte (validé ≤ MISSILE_DMG).
const MISSILE_SCAN_INTERVAL := 0.1   # s : période de re-scan du candidat de verrou (pas à chaque frame)
var _lock_scan_t := 0.0              # accumulateur de throttle du re-scan
var _scan_best: Node3D = null        # dernier candidat trouvé (réutilisé entre deux scans)
func _update_missile(delta: float) -> void:
	if _blaster != _plasma or _plasma == null or _dead or not _armed or GameState.drone_mode_prompt:
		_lock_candidate = null
		_lock_target = null
		_locked = false
		_lock_t = 0.0
		_update_lock_ring()
		return
	# Candidat = drone le plus aligné avec le canon (cône, à portée). Re-scan THROTTLÉ (~0.1 s) : la recherche
	# de groupe + boucle O(n drones) ne tourne plus à chaque frame physique (le verrou tolère 0,1 s de latence).
	_lock_scan_t -= delta
	if _lock_scan_t <= 0.0:
		_lock_scan_t = MISSILE_SCAN_INTERVAL
		_scan_best = _scan_lock_candidate()
	if not is_instance_valid(_scan_best):
		_scan_best = null
	var best: Node3D = _scan_best
	# Verrou À MAINTENIR : garder le MÊME candidat dans le cône pendant MISSILE_LOCK_DWELL pour accrocher.
	if best != _lock_candidate:
		_lock_candidate = best
		_lock_t = 0.0
		_locked = false
	if _lock_candidate != null:
		if not _locked:
			_lock_t += delta
			if _lock_t >= MISSILE_LOCK_DWELL:
				_locked = true
				AudioEngine.play_missile_lock()   # bip d'acquisition
				_haptic(0.4, 0.06, 0.0, 1)
	else:
		_locked = false
		_lock_t = 0.0
	_lock_target = _lock_candidate if _locked else null
	_update_lock_ring()
	if _missile_fire_edge() and _locked and _lock_target != null and _missile_ammo > 0:
		_fire_missile()

func _missile_fire_edge() -> bool:
	var pressed := false
	if _xr:
		pressed = _left != null and _left.get_is_active() and _left.get_float("trigger") > 0.6
	else:
		pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	var edge := pressed and not _missile_prev
	_missile_prev = pressed
	return edge

func _fire_missile() -> void:
	Inventory.consume_missile()        # décrémente le STOCK persistant (sauvegardé)
	_missile_ammo = Inventory.missiles
	var mt: Transform3D = _plasma.aim_transform()
	var m = preload("res://scripts/HomingMissile.gd").new()
	m.setup(mt.origin, _lock_target, MISSILE_DMG)
	var sc := get_tree().current_scene
	if sc != null:
		sc.add_child(m)
	AudioEngine.play_missile_launch(mt.origin)   # whoosh de lancement DÉDIÉ (≠ pomf de grenade)
	_haptic(0.6, 0.13, 0.0, 1)
	BHaptics.weapon_recoil(0.6)
	_pickup_msg = "MISSILE LANCÉ"
	_pickup_msg_t = 0.7

# Cherche le drone le plus aligné avec le canon du plasma (cône, à portée). Extrait pour throttler le scan.
func _scan_lock_candidate() -> Node3D:
	var mt: Transform3D = _plasma.aim_transform()
	var origin := mt.origin
	var fwd := -mt.basis.z
	var best: Node3D = null
	var best_dot: float = cos(deg_to_rad(MISSILE_LOCK_ANGLE))
	for d in get_tree().get_nodes_in_group("drone"):
		if not is_instance_valid(d):
			continue
		var to: Vector3 = (d as Node3D).global_position - origin
		var dist := to.length()
		if dist > MISSILE_LOCK_RANGE or dist < 0.5:
			continue
		var dot := fwd.dot(to / dist)
		if dot > best_dot:
			best_dot = dot
			best = d as Node3D
	return best

# Anneau de verrouillage : créé paresseusement, posé (top_level) sur le drone verrouillé, tournoie ; masqué sinon.
func _update_lock_ring() -> void:
	if _lock_candidate == null or not is_instance_valid(_lock_candidate):
		if _lock_ring != null:
			_lock_ring.visible = false
		return
	if _lock_ring == null:
		_lock_ring = MeshInstance3D.new()
		_lock_ring.top_level = true
		_lock_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var tm := TorusMesh.new()
		tm.inner_radius = 1.0
		tm.outer_radius = 1.22
		_lock_ring.mesh = tm
		var rmat := StandardMaterial3D.new()
		rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_lock_ring.material_override = rmat
		add_child(_lock_ring)
	_lock_ring.visible = true
	var pos := (_lock_candidate as Node3D).global_position
	# Face-caméra : l'axe du tore (Y) pointe vers l'œil ; l'anneau se RESSERRE pendant le verrouillage.
	var cam: Node3D = _xr_camera if (_xr and _xr_camera != null) else _eyes
	var to_cam := Vector3.UP
	if cam != null:
		var dd := cam.global_position - pos
		if dd.length() > 0.001:
			to_cam = dd.normalized()
	_lock_spin += 0.06
	var b := Basis(Quaternion(Vector3.UP, to_cam)) * Basis(Vector3.UP, _lock_spin)
	var ring_sc := 1.0 if _locked else lerpf(1.7, 1.05, clampf(_lock_t / MISSILE_LOCK_DWELL, 0.0, 1.0))
	_lock_ring.global_transform = Transform3D(b.scaled(Vector3.ONE * ring_sc), pos)
	# Jaune pendant le verrouillage, VERT une fois accroché.
	var col := Color(0.5, 1.0, 0.6, 0.9) if _locked else Color(1.0, 0.85, 0.2, 0.8)
	(_lock_ring.material_override as StandardMaterial3D).albedo_color = col

# DEV : dote en munitions missile (flag --auto-arm) pour tester le tir secondaire sans avoir à looter.
func dev_load_missiles(n: int) -> void:
	Inventory.set_missiles(n)
	_missile_ammo = Inventory.missiles

# Touché par un tir ennemi : applique les dégâts, flash + flèche directionnelle + haptique, mort si PV ≤ 0.
# from_dir = direction monde d'où venait le tir (vers le tireur), pour l'indicateur directionnel.
func enemy_hit(amount: float = 9.0, from_dir: Vector3 = Vector3.ZERO) -> void:
	if _dead or _invuln_t > 0.0:
		return
	# Bouclier en sus (améliorations ramassées) : absorbe d'abord les dégâts.
	if _overshield > 0.0:
		var absorb := minf(_overshield, amount)
		_overshield -= absorb
		amount -= absorb
		GameState.combat_overshield = _overshield
	_hp = maxf(_hp - amount, 0.0)
	_hurt_t = 0.5
	if from_dir.length() > 0.001:
		_hit_dir = from_dir.normalized()
		_hit_dir_t = 1.3
	GameState.combat_hp = _hp
	_haptic(0.8, 0.18, 0.0, 0)
	# Gilet X40 : encaissement DIRECTIONNEL — la secousse part de la face/du côté d'où vient le tir.
	var cam = get_active_camera()
	var ldir := Vector3(0.0, 0.0, -1.0)
	if cam and from_dir.length() > 0.001:
		ldir = cam.global_transform.basis.inverse() * from_dir.normalized()
	BHaptics.damage_hit(ldir, clampf(amount / 12.0, 0.25, 1.0))
	AudioEngine.play_impact(get_active_camera().global_position, 0.4)
	if _hp <= 0.0:
		_die_combat()

# Soin (vague nettoyée) : restaure des PV + pulse vert. Sans effet si mort ou dégainé.
func heal(amount: float) -> void:
	if _dead or not _armed:
		return
	_hp = minf(_hp + amount, HP_MAX)
	GameState.combat_hp = _hp
	_heal_t = 0.6
	_haptic(0.25, 0.1, 0.0, 0)
	BHaptics.heal_pulse(clampf(amount / 25.0, 0.0, 1.0))   # gilet : nappe douce et chaude qui monte

# Confirmation de destruction d'un drone (appelée par WaveManager) : tic brillant + pulse manette droite.
func on_kill() -> void:
	AudioEngine.play_hit_confirm(true)
	_haptic(0.55, 0.09, 0.0, 1)
	BHaptics.kill_confirm()   # gilet : petit tap sec mi-poitrine

# Ramassage d'une amélioration lâchée par un drone abattu (appelé par Pickup). Effet de PORTÉE RUN (réinit. à
# l'équipement / la mort) + juice (son + haptique + gilet + flash vert + annonce brève sur le readout).
func apply_pickup(kind: int) -> void:
	if _dead or not _armed:
		return
	Inventory.collect(kind)   # accumule dans l'inventaire PERSISTANT (sauvegardé) — les bonus sont CONSERVÉS
	match kind:
		0:
			_hp = minf(_hp + 35.0, HP_MAX)   # soin : effet INSTANTANÉ (auto-appliqué) ; +1 soin aussi mis en stock
			GameState.combat_hp = _hp
			_pickup_msg = "+VIE"
		1:
			_pickup_msg = "DGT x%.2f" % Inventory.damage_mult()
		2:
			_pickup_msg = "CAD x%.2f" % Inventory.firerate_mult()
		3:
			_overshield = Inventory.shield_cap()   # bouclier rempli à la nouvelle capacité persistante
			_pickup_msg = "BOUCLIER %d" % int(_overshield)
		4:
			_pickup_msg = "+2 MISSILES"
	_sync_buffs_from_inventory()   # re-dérive dégâts/cadence/missiles persistants + pousse au blackboard (_overshield déjà à jour)
	_pickup_msg_t = 1.8
	AudioEngine.play_hit_confirm(true)   # carillon montant de récompense
	_haptic(0.5, 0.12, 0.0, 1)
	BHaptics.heal_pulse(0.55)
	_heal_t = 0.6   # réutilise le pulse vert de la surcouche comme « flash positif »

# Suffixe compact des améliorations actives (pour le readout). Vide si aucune.
func _buff_suffix() -> String:
	var s := ""
	if _locked and _missile_ammo > 0:
		s += "🎯LOCK  "
	if _missile_ammo > 0:
		s += "🚀%d  " % _missile_ammo
	if _dmg_mult > 1.001:
		s += "DGT x%.1f  " % _dmg_mult
	if _firerate_mult > 1.001:
		s += "CAD x%.1f" % _firerate_mult
	return s.strip_edges()

# Charge le LOADOUT PERSISTANT depuis l'inventaire (à l'équipement/dégaine et à la réapparition). Les bonus ne se
# réinitialisent PLUS à zéro : ils sont CONSERVÉS + sauvegardés (le bouclier est rempli à sa capacité au départ).
func _reset_buffs() -> void:
	_overshield = Inventory.shield_cap()   # bouclier rempli à la capacité persistante au début du run
	_sync_buffs_from_inventory()
	_lock_target = null
	_pickup_msg_t = 0.0

# Dérive les bonus persistants (dégâts/cadence/missiles) de l'inventaire + pousse l'état combat au blackboard.
# Partagé par apply_pickup (ramassage) et _reset_buffs (début de run). Le bouclier (_overshield) est géré par l'appelant.
func _sync_buffs_from_inventory() -> void:
	_dmg_mult = Inventory.damage_mult()
	_firerate_mult = Inventory.firerate_mult()
	_missile_ammo = Inventory.missiles
	GameState.combat_overshield = _overshield
	GameState.combat_dmg_mult = _dmg_mult
	GameState.combat_firerate_mult = _firerate_mult

# Le bouclier intercepte-t-il un projectile en `world_pos` ? (déployé, dans le rayon, côté face avant.)
# Si OUI : feedback (haptique gauche + clink + étincelle) puis retourne true => le bolt meurt sans dégâts.
func shield_intercept(world_pos: Vector3) -> bool:
	if not _armed or _shield == null or not _shield.visible:
		return false
	var sx: Transform3D = _shield.global_transform
	var d := world_pos - sx.origin
	if d.length() > SHIELD_BLOCK_RADIUS:
		return false
	var fwd := -sx.basis.z.normalized()   # face bombée du bouclier (pointe vers l'ennemi)
	if d.dot(fwd) < -0.05:                 # bolt déjà passé derrière le bouclier => non bloqué
		return false
	_haptic(0.7, 0.13, 0.0, -1)            # pulse main gauche (bras du bouclier)
	BHaptics.shield_block()                # gilet : buzz poitrine GAUCHE (côté bouclier)
	AudioEngine.play_impact(world_pos, 0.3)
	_spawn_block_spark(world_pos)
	if _shield.has_method("flash"):
		_shield.flash()                    # le bouclier s'illumine brièvement
	return true

# Étincelle cyan brève au point de blocage (auto-libérée).
func _spawn_block_spark(world_pos: Vector3) -> void:
	var fl := OmniLight3D.new()
	fl.light_color = Color(0.5, 0.9, 1.0)
	fl.omni_range = 3.5
	fl.light_energy = 6.0
	fl.shadow_enabled = false
	get_tree().current_scene.add_child(fl)
	fl.global_position = world_pos
	get_tree().create_timer(0.12).timeout.connect(fl.queue_free)

func _die_combat() -> void:
	if _dead:
		return
	_dead = true
	_respawn_t = 2.4
	GameState.combat_result_wave = GameState.combat_wave    # fige le résultat pour l'écran de fin de run
	GameState.combat_result_score = GameState.combat_score
	GameState.combat_hp = 0.0
	GameState.combat_dead = true
	_haptic(1.0, 0.45, 0.0, 0)
	BHaptics.combat_death()   # gilet : gros choc plein gilet (avant + arrière)
	AudioEngine.play_impact(get_active_camera().global_position, 1.0)

func _respawn() -> void:
	_dead = false
	_hp = HP_MAX
	_invuln_t = 2.0   # brève grâce après réapparition
	velocity = Vector3.ZERO
	GameState.combat_hp = _hp
	GameState.combat_dead = false
	_reset_buffs()   # la mort termine le run => améliorations remises à zéro
	_haptic(0.4, 0.2, 0.0, 0)

# Minuteries combat + miroir vers GameState + pilotage de la surcouche. Retourne true si le joueur est mort
# (le _physics_process gèle alors la locomotion le temps de la réapparition). Appelé chaque frame physique.
func _update_combat(delta: float) -> bool:
	if _hurt_t > 0.0:
		_hurt_t = maxf(_hurt_t - delta, 0.0)
	if _invuln_t > 0.0:
		_invuln_t = maxf(_invuln_t - delta, 0.0)
	if _heal_t > 0.0:
		_heal_t = maxf(_heal_t - delta, 0.0)
	if _hit_dir_t > 0.0:
		_hit_dir_t = maxf(_hit_dir_t - delta, 0.0)
	if _pickup_msg_t > 0.0:
		_pickup_msg_t = maxf(_pickup_msg_t - delta, 0.0)
	GameState.combat_active = _armed
	GameState.combat_hp = _hp
	GameState.combat_hp_max = HP_MAX
	GameState.combat_dead = _dead
	if _dead:
		_respawn_t -= delta
		if _respawn_t <= 0.0:
			_respawn()
	var cam := get_active_camera()
	if _combat_overlay:
		var hurt01 := _hurt_t / 0.5
		var dead01 := 1.0 if _dead else 0.0
		var ratio := (_hp / HP_MAX) if HP_MAX > 0.0 else 1.0
		var low01 := clampf((0.4 - ratio) / 0.4, 0.0, 1.0) if (_armed and not _dead) else 0.0
		var heal01 := _heal_t / 0.6
		_combat_overlay.place(cam, hurt01, dead01, low01, heal01, delta)
	if _hit_indicator:
		var dir_t := (_hit_dir_t / 1.3) if (_armed and not _dead) else 0.0
		_hit_indicator.place(cam, _hit_dir, dir_t)
	if _combat_readout:
		var rtxt := ""
		if _armed:
			if GameState.drone_mode_prompt:
				rtxt = "MODE DRONE ?\nGâchette D = OUI     ·     Gâchette G = NON"
			elif _dead:
				rtxt = "ÉLIMINÉ"
			else:
				var pv := "PV %d" % int(round(_hp))
				if _overshield > 0.0:
					pv += "+%d" % int(round(_overshield))   # PV de bouclier en sus
				rtxt = "VAGUE %d     %s     Score %d" % [GameState.combat_wave, pv, GameState.combat_score]
				var bf := _buff_suffix()
				if bf != "":
					rtxt += "     " + bf
				if _pickup_msg_t > 0.0:
					rtxt += "     " + _pickup_msg   # annonce brève du dernier ramassage
		_combat_readout.place(cam, _armed and _xr, rtxt)   # VR seulement (le HUD plat couvre le bureau)
	return _dead

# Parente l'arme/bouclier à un nœud (manette/caméra) avec un offset local => rigidement solidaire (pas de
# copie de transform par frame => zéro décalage physique↔rendu en VR). Appelé à l'activation / la sortie.
func _attach_weapon_to(node: Node, target: Node, local: Transform3D) -> void:
	if node == null or target == null:
		return
	if node.get_parent() != target:
		node.reparent(target, false)
	(node as Node3D).transform = local

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
	if _xr:
		_update_holster()   # dégainer/rengainer à la manette (zones holster sur le corps), sans passer par la montre
	_update_missile(delta)   # plasma : verrou auto + tir secondaire (missile à tête chercheuse)
	if _update_combat(delta):   # mort : locomotion gelée le temps de la réapparition
		velocity = Vector3.ZERO
		return
	_update_swim_state()   # bascule nage<->marche selon la profondeur d'eau (hystérésis)
	if _flying:
		_fly(delta)
	elif _swimming:
		_swim(delta)
	elif _gliding:
		_glide(delta)
	elif _xr:
		_physics_xr(delta)
	else:
		_physics_desktop(delta)
	# Prise connectée : ventilo ON en vol/parapente OU en chute rapide (plongeon, saut de falaise) ; OFF sinon.
	var falling_fast := not is_on_floor() and not _swimming and get_real_velocity().y < -PLUG_FALL_SPEED
	SmartPlug.set_airborne(_flying or _gliding or falling_fast)
	# Son de réacteurs (vol armure Iron Man) : intensité ∝ vitesse réelle.
	AudioEngine.set_thrusters(_flying, clampf(get_real_velocity().length() / FLY_SPEED, 0.0, 1.0), delta)
	_update_steps(delta)
	_update_paraglider(delta)
	_update_impact(delta)   # atterrissage de puissance (chute rapide) — tous modes sauf nage
	_update_drone_prompt()  # prompt « mode Drone ? » à la sortie d'arme (suspend le tir tant qu'on n'a pas répondu)
	_update_weapon(delta)   # blaster (combat opt-in) : suivi main + tir
	if not _flying and not _gliding and not _swimming:
		_anti_stuck(delta)
		_update_landing()
	# Vignette de confort : se resserre ∝ vitesse réelle (vol/glisse rapides = vection max => anti-nausée).
	if _vignette:
		var amt := (Settings.vignette_strength * smoothstep(4.0, 18.0, get_real_velocity().length())) if Settings.vignette_on else 0.0
		_vignette.place(get_active_camera(), amt, delta)
	# Lampe nocturne : suit la caméra (bureau) ou la main droite (XR), pointe vers l'avant (-Z).
	if _lamp_on and _lamp:
		var src: Node3D = _eyes
		if _xr:
			src = _right if (_right != null and _right.get_is_active()) else _xr_camera
		if src:
			_lamp.global_transform = src.global_transform

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

# Atterrissage de PUISSANCE (Iron Man / Hulk) : suit la vitesse de chute en l'air ; à la reprise de contact
# au sol au-delà de POWER_LAND_SPEED, émet `impact` (gerbe de débris + onde de choc, jouée par SurfaceView)
# + un gros pulse haptique. Marche pour la chute libre, le piqué en armure, ou après avoir replié la voile en
# altitude. Inactif sous l'eau (on n'atterrit pas en nageant — c'est l'éclaboussure qui gère).
func _update_impact(_delta: float) -> void:
	if _swimming:
		_fall_vy = 0.0
		_impact_was_air = false
		return
	if not is_on_floor():
		_fall_vy = minf(_fall_vy, get_real_velocity().y)   # vitesse de chute réelle la plus forte (la plus négative)
		_impact_was_air = true
		return
	if _impact_was_air:
		var spd := -_fall_vy   # vitesse de chute à l'impact (m/s, >0)
		if spd > POWER_LAND_SPEED:
			var strength := clampf((spd - POWER_LAND_SPEED) / 20.0, 0.0, 1.0)
			impact.emit(global_position, 0.45 + 0.55 * strength)
			_haptic(0.7 + 0.3 * strength, 0.2, 0.0, 0)   # gros choc deux mains
			BHaptics.landing(1.0)                         # gilet X40 : impact plein
			_flying = false   # impact de puissance => on POSE (pose Hulk), pas de vol stationnaire collé au sol
	_impact_was_air = false
	_fall_vy = 0.0

# Blaster (combat opt-in) : suit la main droite (XR) / viewmodel (bureau) ; tir gâchette droite (XR) / clic
# gauche (bureau), cadence limitée, recul haptique + son. Dégainé => return immédiat (aucun effet).
func _update_weapon(delta: float) -> void:
	if not _armed or _blaster == null:
		return
	# Position de l'arme/bouclier : assurée par PARENTAGE à la manette/caméra (enter_xr/enter_desktop) =>
	# rigidement solidaires, AUCUN décalage physique↔rendu en VR (le bolt part toujours du bout du canon).
	# Visée / tir SECONDAIRE : grip droit (XR) / clic droit (bureau). En visée => zoom léger (bureau) + tir
	# de PRÉCISION « chargé » (bolt violet plus gros, cadence plus lente, recul renforcé).
	var aiming := false
	if _xr:
		aiming = _right != null and _right.get_is_active() and _right.get_float("grip") > 0.6
	else:
		aiming = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	# (FOV de visée ADS centralisé dans _update_paraglider : un seul écrit FOV par frame => plus de conflit
	# avec le FOV de vitesse, le zoom atteint donc bien sa cible.)
	_fire_cd = maxf(_fire_cd - delta, 0.0)
	var firing := false
	if _xr:
		firing = _right != null and _right.get_is_active() and _right.get_float("trigger") > 0.6
	else:
		firing = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if GameState.drone_mode_prompt:
		firing = false   # tir suspendu tant qu'on n'a pas répondu au prompt « mode Drone »
	if firing and _fire_cd <= 0.0:
		_fire_cd = (_blaster.fire_interval_ads if aiming else _blaster.fire_interval) / maxf(_firerate_mult, 0.05)
		var shot = _blaster.fire([get_rid()], aiming)   # hitscan (retour { hit,pos,collider,charged })
		if shot.hit and shot.collider != null and shot.collider.has_method("take_damage"):
			shot.collider.take_damage((_blaster.dmg_charged if aiming else _blaster.dmg) * _dmg_mult, shot.pos)   # drone touché
			AudioEngine.play_hit_confirm(false)   # tic de confirmation au toucher
		_haptic(_blaster.fire_haptic_ads if aiming else _blaster.fire_haptic, 0.09 if aiming else 0.06, 0.0, 1)
		BHaptics.weapon_recoil(_blaster.vest_recoil)   # gilet : « coup » de recul dans la poitrine (∝ poids arme)
		if _blaster.projectile_mode:
			AudioEngine.play_grenade_launch(_blaster.muzzle_world())
		elif _blaster.weapon_name == "Plasma":
			AudioEngine.play_plasma(_blaster.muzzle_world(), aiming)
		else:
			AudioEngine.play_blaster(_blaster.muzzle_world())
	# Lunette VR plasma : zoom optique RÉEL (SubViewport-loupe) — UNIQUEMENT plasma + visée (grip) en XR. Ne
	# rend qu'en visée (perf), le bureau garde son zoom de FOV caméra.
	if _plasma_scope:
		var scope_on: bool = _xr and _blaster == _plasma and aiming
		_plasma_scope.set_active(scope_on)
		_plasma.sight_enabled = not scope_on   # la lunette remplace le réticule/laser flottants
		if scope_on:
			var mt: Transform3D = _plasma.aim_transform()
			_plasma_scope.update_view(mt.origin, -mt.basis.z, mt.basis.y)

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
	# Lampe nocturne (bureau) : touche L (front montant). En XR, bascule depuis la montre (bouton Lampe).
	if not _xr:
		var lamp_pressed := Input.is_physical_key_pressed(KEY_L)
		if lamp_pressed and not _lamp_prev:
			toggle_lamp()
		_lamp_prev = lamp_pressed
		var arm_pressed := Input.is_physical_key_pressed(KEY_B)   # revolver (combat opt-in)
		if arm_pressed and not _arm_prev:
			toggle_weapon()
		_arm_prev = arm_pressed
		var plasma_pressed := Input.is_physical_key_pressed(KEY_V)   # fusil à plasma
		if plasma_pressed and not _plasma_prev:
			toggle_plasma()
		_plasma_prev = plasma_pressed
		var grenade_pressed := Input.is_physical_key_pressed(KEY_N)   # lance-grenades
		if grenade_pressed and not _grenade_prev:
			toggle_grenade()
		_grenade_prev = grenade_pressed
		var tool_pressed := Input.is_physical_key_pressed(KEY_H)   # outil de récolte (hache+pioche)
		if tool_pressed and not _tool_prev:
			toggle_tool()
		_tool_prev = tool_pressed
	if not _flying and not _swimming:
		_update_deploy()   # parapente (E) — désactivé pendant le vol Iron Man ET la nage (pas de voile sous l'eau)

# Phase 22 : accumule la distance horizontale parcourue au sol ; émet `step` chaque STRIDE mètres
# (=> cadence proportionnelle à la vitesse, naturelle). Émis aux pieds (global_position, y aux pieds).
var _stride_accum := 0.0
func _update_steps(delta: float) -> void:
	if _swimming:
		return   # pas de foulées sous l'eau (on nage)
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

	# 4) Rotation confort (stick droit horizontal) : snap (cran) ou smooth, selon les Options (cf. _apply_comfort_turn).
	_apply_comfort_turn(delta)

# Rotation confort XR (stick droit horizontal) : par CRAN (snap, défaut) ou CONTINUE (smooth), au choix dans
# les Options. Partagée par la marche ET la nage (même ressenti de virage sous l'eau). Le snap-turn est le
# plus confortable au casque ; la rotation continue convient aux joueurs aguerris (moins saccadé, + de vection).
func _apply_comfort_turn(delta: float) -> void:
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

# --- Nage sous-marine (univers sous-marin) ---

# Bascule nage<->marche selon la profondeur d'eau au-dessus des pieds (surface = SEA_Y=0). Hystérésis
# (entrée ~poitrine 1.4 m, sortie 1.0 m au fond) => pas de clignotement au bord. L'armure Iron Man prime
# (on vole même sous l'eau). Entrer en nage replie le parapente (splash) et freine la vitesse d'entrée.
func _update_swim_state() -> void:
	if _flying:
		if _swimming:
			_swimming = false
		return
	var depth := SEA_Y - global_position.y   # profondeur d'eau au-dessus des pieds (>0 = pieds immergés)
	if _swimming:
		if is_on_floor() and depth < SWIM_EXIT_DEPTH:
			_set_swimming(false)
	elif depth > SWIM_ENTER_DEPTH:
		_set_swimming(true)

func _set_swimming(v: bool) -> void:
	if v == _swimming:
		return
	_swimming = v
	if v:
		if _gliding:
			_stow()           # on ne plane pas sous l'eau : repli (splash)
		velocity *= 0.3       # résistance de l'eau : la vitesse d'entrée (chute/saut) est freinée net
		_haptic(0.5, 0.12, 0.0, 0)   # éclaboussure d'entrée
		BHaptics.soft_tap(40.0)
	else:
		_haptic(0.25, 0.07, 0.0, 0)  # on repose le pied (sortie de l'eau)

# Nage : déplacement 3D libre dans la direction du regard + flottabilité douce (remonte tout seul) + drag
# aquatique (on glisse jusqu'à l'arrêt en lâchant). BUREAU : WASD relatif caméra (viser haut = monter) +
# Espace (haut) / C (bas) / Maj (boost). XR : stick gauche (3D relatif tête) + stick droit Y (vertical) + turn.
func _swim(delta: float) -> void:
	# Roomscale XR : le corps suit le casque en XZ (comme la marche) => leaning/roomscale cohérent sous l'eau.
	if _xr and _xr_camera:
		var off := Vector3(_xr_camera.global_position.x - global_position.x, 0.0, _xr_camera.global_position.z - global_position.z)
		global_position += off
		_xr_origin.global_position -= off
	var wish := Vector3.ZERO
	var boost := 1.0
	if _xr:
		if _left and _left.get_is_active():
			var s := _left.get_vector2("primary")
			if s.length() > STICK_DEADZONE:
				var hb := _xr_camera.global_transform.basis
				wish += -hb.z * s.y + hb.x * s.x   # 3D relatif tête : on nage là où on regarde
		if _right and _right.get_is_active():
			var ry := _right.get_vector2("primary").y
			if absf(ry) > STICK_DEADZONE:
				wish += Vector3.UP * ry            # monter / descendre
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
			boost = SWIM_BOOST
	var target := Vector3.ZERO
	if wish.length() > 0.05:
		target = wish.normalized() * SWIM_SPEED * boost
	# Drag aquatique : la vitesse tend (lentement) vers la cible => sensation d'eau, glisse à l'arrêt.
	velocity = velocity.lerp(target, clampf(SWIM_ACCEL * delta, 0.0, 1.0))
	# Flottabilité : seulement AU REPOS (aucune commande) + tête sous la surface => légère poussée vers le
	# haut (on remonte doucement vers la surface en lâchant tout). Nager dans n'importe quelle direction tient
	# la profondeur (on ne lutte pas contre la flottabilité). Neutre dès que la tête perce la surface.
	if wish.length() < 0.05 and global_position.y + 1.4 < SEA_Y:
		velocity.y += BUOYANCY * delta
	move_and_slide()
	if _xr:
		_apply_comfort_turn(delta)

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
		wind = _wind_dir_n * (WeatherSystem.get_wind() * WIND_DRIFT)
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
		# FOV bureau CENTRALISÉ ici (un seul écrit/frame) : la visée ADS (clic droit, arme équipée) PRIME sur le
		# FOV de vitesse et atteint donc sa cible ; sinon FOV de vitesse (repos = _base_fov).
		if _armed and _blaster != null and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_eyes.fov = lerpf(_eyes.fov, _base_fov - _blaster.zoom_fov, clampf(10.0 * delta, 0.0, 1.0))
		else:
			_eyes.fov = lerpf(_eyes.fov, _base_fov + add_fov, clampf(3.0 * delta, 0.0, 1.0))
	# Repulseur Iron Man : s'éteint en douceur dès qu'on ne vole plus (XR compris).
	if _repulsor and not _flying:
		_repulsor.light_energy = lerpf(_repulsor.light_energy, 0.0, clampf(6.0 * delta, 0.0, 1.0))
	# Lignes de vitesse : s'estompent quand on ne vole plus (XR compris).
	if _speed_streaks and not _flying:
		_speed_streaks.update_streaks(get_active_camera(), Vector3.ZERO, 0.0, delta)
