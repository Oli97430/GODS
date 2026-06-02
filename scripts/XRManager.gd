extends Node3D
## Initialise OpenXR de façon CONDITIONNELLE et choisit la caméra active.
##
## OpenXR est activé dans project.godot : le moteur tente de démarrer le runtime
## au boot. S'il y parvient (runtime + casque présents), on bascule le rendu vers
## le casque. Sinon, fallback automatique sur la caméra bureau plein écran, ce qui
## permet de développer sans matériel XR.

@onready var desktop_camera: Camera3D = $DesktopCamera
@onready var xr_origin: XROrigin3D = $XROrigin3D
@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D

var xr_interface: XRInterface

# Retry d'init OpenXR : permet de lancer en bureau puis d'enfiler le casque APRÈS
# (l'init moteur au boot est unique). Dès qu'OpenXR démarre, on recharge la scène
# pour repartir proprement en XR (évite tout état hybride bureau/XR).
const XR_RETRY_DURATION := 20.0   # durée max de tentative après lancement (s)
const XR_RETRY_INTERVAL := 1.0    # intervalle entre tentatives (s)
var _retry_elapsed := 0.0
var _retry_accum := 0.0

func _enter_tree() -> void:
	# Détection au plus tôt : _enter_tree du parent s'exécute avant le _ready des
	# enfants, donc GameState.xr_active est fiable quand NavigationController se
	# configure. is_initialized() est vrai uniquement si le runtime a démarré ET
	# qu'un casque a été détecté au boot.
	xr_interface = XRServer.find_interface("OpenXR")
	GameState.xr_active = xr_interface != null and xr_interface.is_initialized()

func _ready() -> void:
	if GameState.xr_active:
		_enable_xr_mode()
	else:
		_enable_desktop_mode()
	# Passe d'immersion graphique (PCVR) : anti-crénelage MSAA + post-traitement de l'environnement
	# espace (tonemap/glow/SSAO/SSIL). La surface reçoit la même passe via SurfaceView.
	ImmersionFX.setup_viewport(get_viewport())
	var we := get_node_or_null("WorldEnvironment")
	if we != null and we.environment != null:
		ImmersionFX.apply(we.environment)
	# Menu Options : BUREAU = overlay plat (Tab) ; CASQUE = panneau worldspace (bouton ≡), MÊME UI (OptionsUI).
	if GameState.xr_active:
		var panel := preload("res://scripts/OptionsPanelXR.gd").new()
		panel.camera_path = NodePath("../XRCamera3D")
		panel.left_controller_path = NodePath("../LeftController")
		panel.right_controller_path = NodePath("../RightController")
		panel.hand_tracking_path = NodePath("../HandTracking")
		xr_origin.add_child(panel)   # _ready résout les NodePaths une fois dans l'arbre
	else:
		add_child(preload("res://scripts/OptionsMenu.gd").new())
	# Boussole HUD (échelle SURFACE : sur une planète + en vol).
	var hud := get_node_or_null("HUD")
	if hud != null:
		hud.add_child(preload("res://scripts/Compass.gd").new())

# Rendu vers le casque.
func _enable_xr_mode() -> void:
	get_viewport().use_xr = true
	# Le compositeur XR pilote sa propre synchro : on coupe la v-sync fenêtre.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	xr_origin.visible = true  # rig XR + rayon de visée visibles
	xr_camera.current = true
	desktop_camera.current = false
	set_process(false)  # déjà en XR : inutile de retenter l'init
	print("[XRManager] OpenXR actif → rendu casque XR.")

# Fallback bureau (aucun runtime/casque). Le rig XR reste dans l'arbre, inactif,
# pour conserver l'architecture commune aux phases suivantes.
func _enable_desktop_mode() -> void:
	get_viewport().use_xr = false
	desktop_camera.current = true
	desktop_camera.look_at(Vector3.ZERO, Vector3.UP)
	xr_camera.current = false
	xr_origin.visible = false  # masque le rig XR (rayon, manettes) hors XR
	print("[XRManager] OpenXR indisponible → mode bureau (fallback).")
	# Retente l'init OpenXR : si le casque est enfilé après le lancement, bascule auto.
	_retry_elapsed = 0.0
	_retry_accum = 0.0
	set_process(true)

# Tant qu'on est en bureau, on retente l'init OpenXR à intervalle régulier. Dès
# qu'il démarre (casque détecté après coup), on recharge la scène pour repartir en XR.
func _process(delta: float) -> void:
	if GameState.xr_active or xr_interface == null:
		set_process(false)
		return
	_retry_elapsed += delta
	if _retry_elapsed > XR_RETRY_DURATION:
		set_process(false)  # abandon : on reste en bureau
		return
	_retry_accum += delta
	if _retry_accum < XR_RETRY_INTERVAL:
		return
	_retry_accum = 0.0
	if not xr_interface.is_initialized():
		xr_interface.initialize()
	if xr_interface.is_initialized():
		print("[XRManager] Casque détecté après lancement → redémarrage en XR.")
		get_tree().reload_current_scene()
