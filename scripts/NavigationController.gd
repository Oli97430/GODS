extends Node
## Couche d'entrée UNIQUE : mappe l'entrée bureau (souris) OU XR (manettes) vers la transform de
## la VUE ACTIVE (galaxie à GALAXY, système à SYSTEM) et déclenche la sélection / les transitions.
## Navigation ABSTRAITE (sans vaisseau) : on s'enfonce d'échelle en échelle par sélection, on remonte
## par Échap / bouton B. À PLANET : molette/stick = zoom, clic droit/grip = tourner, Entrée/gâchette = descendre.
## À SURFACE la souris/locomotion appartient au PlayerController ; on ne garde que le retour (Échap/B).
##
## Bureau : clic droit = orbite, molette = zoom, clic milieu = pan, survol = sélection,
##          double-clic / Entrée = confirmer, Échap = remonter d'une échelle.
## XR     : grip = attraper/tourner (6DOF), stick = zoom, rayon = visée, gâchette = confirmer, B = retour.

@onready var galaxy_view: GalaxyView = $"../GalaxyView"
@onready var system_view = $"../SystemView"
@onready var planet_view = $"../PlanetView"
@onready var view_manager = $"../ViewManager"
@onready var desktop_camera: Camera3D = $"../DesktopCamera"
@onready var left_controller: XRController3D = $"../XROrigin3D/LeftController"
@onready var right_controller: XRController3D = $"../XROrigin3D/RightController"
@onready var hand_tracking: HandTracking = $"../XROrigin3D/HandTracking"
@onready var info_label: Label = $"../HUD/InfoLabel"
@onready var info_panel_3d: Label3D = $"../InfoPanel3D"

# --- Réglages bureau ---
const ORBIT_SENS := 0.008
const PAN_SENS := 0.04
const ZOOM_IN_STEP := 1.1
const ZOOM_OUT_STEP := 0.9
const DESKTOP_SCALE_MIN := 0.3
const DESKTOP_SCALE_MAX := 5.0
const DESKTOP_PAN_LIMIT := Vector3(80, 80, 80)

# --- Réglages XR ---
const XR_HOME_POS := Vector3(0.0, 1.3, -0.7)
const XR_HOME_SCALE := 0.012
const XR_SCALE_MIN := 0.004
const XR_SCALE_MAX := 0.06
# Galaxie : échelle de DÉPART/retour — on commence IMMERGÉ au cœur (les étoiles enveloppent le joueur) plutôt
# que face à un disque lointain. On peut ensuite dézoomer (stick) pour voir tout le disque.
const GALAXY_XR_HOME_SCALE := 0.05
const GALAXY_DESKTOP_HOME_SCALE := 1.7
const GRIP_THRESHOLD := 0.6
const TRIGGER_THRESHOLD := 0.6
const STICK_DEADZONE := 0.15
const XR_ZOOM_SPEED := 1.5
const PANEL_OFFSET := Vector3(0.0, 0.03, 0.0)

# --- Zoom borné à l'échelle PLANET (orbite) : « un peu » autour du cadrage maison ---
const PLANET_DESKTOP_SCALE_MIN := 0.55
const PLANET_DESKTOP_SCALE_MAX := 1.4
const PLANET_XR_SCALE_MIN := 0.008
const PLANET_XR_SCALE_MAX := 0.020

# Vue actuellement manipulée (GalaxyView ou SystemView) : les deux exposent
# select_nearest / selected_index / get_selection_text / get_selection_world_position.
var active_view = null

# Transform décomposée de la vue active.
var _rot := Basis.IDENTITY
var _scale := 1.0
var _pos := Vector3.ZERO
var _scale_min := DESKTOP_SCALE_MIN
var _scale_max := DESKTOP_SCALE_MAX

# État souris (bureau).
var _orbiting := false
var _panning := false

# État XR.
var _grabbing := false
var _grab_controller: XRController3D
var _last_grab_tf := Transform3D.IDENTITY
var _trigger_was_pressed := false
var _b_was_pressed := false
var _surf_back_was_pressed := false   # front du Y GAUCHE (remontée surface) — distinct du B droit (qui sert au vol Iron Man)

func _ready() -> void:
	info_label.visible = not GameState.xr_active
	info_panel_3d.visible = false
	set_active_view(galaxy_view, GameState.Scale.GALAXY, true)

# Transform « maison » d'une vue selon le mode (bureau plein cadre / hologramme XR).
func get_home_transform(scale_kind) -> Transform3D:
	# Galaxie : on démarre IMMERGÉ au cœur (échelle agrandie). Les autres échelles gardent leur cadrage maison.
	var galaxy: bool = scale_kind == GameState.Scale.GALAXY
	if GameState.xr_active:
		var s: float = GALAXY_XR_HOME_SCALE if galaxy else XR_HOME_SCALE
		return Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), XR_HOME_POS)
	var ds: float = GALAXY_DESKTOP_HOME_SCALE if galaxy else 1.0
	return Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * ds), Vector3.ZERO)

# Désigne la vue manipulée. reset_home=true repose la vue à son home ; sinon conserve sa transform.
func set_active_view(view, scale_kind, reset_home: bool) -> void:
	active_view = view
	if reset_home:
		view.transform = get_home_transform(scale_kind)
	var t: Transform3D = view.transform
	_pos = t.origin
	_scale = t.basis.get_scale().x
	_rot = t.basis.orthonormalized()
	var planet: bool = scale_kind == GameState.Scale.PLANET
	if GameState.xr_active:
		_scale_min = PLANET_XR_SCALE_MIN if planet else XR_SCALE_MIN
		_scale_max = PLANET_XR_SCALE_MAX if planet else XR_SCALE_MAX
	else:
		_scale_min = PLANET_DESKTOP_SCALE_MIN if planet else DESKTOP_SCALE_MIN
		_scale_max = PLANET_DESKTOP_SCALE_MAX if planet else DESKTOP_SCALE_MAX
	# Réinitialise les états de manip transitoires (évite qu'un drag/grab « colle » au changement de vue).
	_orbiting = false
	_panning = false
	_grabbing = false
	_grab_controller = null
	_refresh_selection_display()

# Affiche un texte d'invite (PLANET/SURFACE n'ont pas de survol).
func set_prompt(text: String) -> void:
	if GameState.xr_active:
		info_panel_3d.visible = false
	else:
		info_label.text = text

func _apply_transform() -> void:
	active_view.transform = Transform3D(_rot.scaled(Vector3.ONE * _scale), _pos)

# ----------------------- BUREAU (souris) -----------------------

func _unhandled_input(event: InputEvent) -> void:
	if GameState.options_open or GameState.start_menu_open:
		return
	if GameState.xr_active or view_manager.is_transitioning():
		return
	# Les touches (Échap = retour, Entrée = confirmer, A = toggle ciel) sont toujours traitées.
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)
		return
	# SURFACE : souris au PlayerController (regard FPS).
	if GameState.current_scale == GameState.Scale.SURFACE:
		return
	# PLANET : CLIC GAUCHE = atterrir au point visé ; CLIC DROIT glissé = tourner la planète ; MOLETTE = zoom (borné).
	if GameState.current_scale == GameState.Scale.PLANET:
		if event is InputEventMouseButton:
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					if event.pressed:
						_descend_at(desktop_camera.project_ray_origin(event.position), desktop_camera.project_ray_normal(event.position))
				MOUSE_BUTTON_RIGHT:
					_orbiting = event.pressed
				MOUSE_BUTTON_WHEEL_UP:
					if event.pressed:
						_zoom(ZOOM_IN_STEP)
				MOUSE_BUTTON_WHEEL_DOWN:
					if event.pressed:
						_zoom(ZOOM_OUT_STEP)
		elif event is InputEventMouseMotion and _orbiting:
			_orbit(event.relative)
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_desktop_hover_select(event.position)   # sélectionne l'astre sous le clic
				_confirm()                              # puis entre dedans (système / orbite planète)
		MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
		MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_zoom(ZOOM_IN_STEP)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_zoom(ZOOM_OUT_STEP)

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _orbiting:
		_orbit(event.relative)
	elif _panning:
		_pan(event.relative)
	else:
		_desktop_hover_select(event.position)

# Entrée = confirmer (descendre d'une échelle) ; Échap = remonter ; A = toggle atmosphère.
func _handle_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			_confirm()
		KEY_ESCAPE:
			_exit_scale()
		KEY_A:
			GameState.atmosphere_enabled = not GameState.atmosphere_enabled

func _orbit(rel: Vector2) -> void:
	var cam := desktop_camera.global_transform.basis
	_rot = Basis(Vector3.UP, -rel.x * ORBIT_SENS) * _rot
	_rot = Basis(cam.x.normalized(), -rel.y * ORBIT_SENS) * _rot
	_apply_transform()

func _pan(rel: Vector2) -> void:
	var cam := desktop_camera.global_transform.basis
	_pos += (-cam.x * rel.x + cam.y * rel.y) * PAN_SENS * _scale
	_pos = _pos.clamp(-DESKTOP_PAN_LIMIT, DESKTOP_PAN_LIMIT)
	_apply_transform()

func _zoom(factor: float) -> void:
	_scale = clamp(_scale * factor, _scale_min, _scale_max)
	_apply_transform()

# ----------------------- XR (manettes) -----------------------

func _process(delta: float) -> void:
	if GameState.options_open or GameState.start_menu_open:
		return
	if not GameState.xr_active or view_manager.is_transitioning():
		return
	match GameState.current_scale:
		GameState.Scale.SURFACE:
			_process_surface_back_xr()   # locomotion au PlayerController ; ici juste retour (B)
		GameState.Scale.PLANET:
			_process_planet_xr(delta)    # grip = tourner · stick = zoom · gâchette = descendre · B = retour
		_:
			# GALAXY / SYSTEM : navigation hologramme complète.
			_process_grab()
			_process_stick_zoom(delta)
			_process_xr_hover()
			_process_xr_buttons()
			_follow_panel_to_selection()

# XR à PLANET : grip = attraper pour tourner/rapprocher la planète (6DOF) ; stick = zoom (borné) ;
# gâchette (front montant) = descendre au point visé ; B = retour système.
func _process_planet_xr(delta: float) -> void:
	_process_grab()              # grip = tourner/déplacer la planète (mêmes 6DOF que galaxie/système)
	_process_stick_zoom(delta)   # stick vertical = zoom (clampé aux bornes PLANET)
	if not right_controller.get_is_active():
		return
	var trig := right_controller.get_float("trigger") > TRIGGER_THRESHOLD
	if trig and not _trigger_was_pressed:
		# Atterrir EXACTEMENT au point VISÉ par le pointeur droit (rayon -> direction locale planète).
		var p := _right_pointer()
		if p.valid:
			_descend_at(p.origin, p.dir)
		else:
			view_manager.enter_surface()
	_trigger_was_pressed = trig
	var b := right_controller.is_button_pressed("by_button")
	if b and not _b_was_pressed:
		_exit_scale()
	_b_was_pressed = b

# XR à SURFACE : bouton Y GAUCHE (front montant) = remonter en orbite. ⚠️ PAS le B droit : celui-ci
# sert au toggle vol Iron Man (PlayerController) — c'était le conflit « B remonte au lieu de voler ».
# (La remontée reste aussi accessible via la montre au poignet → « Remonter ».)
func _process_surface_back_xr() -> void:
	if not left_controller.get_is_active():
		return
	var y := left_controller.is_button_pressed("by_button")
	if y and not _surf_back_was_pressed:
		_exit_scale()
	_surf_back_was_pressed = y

# Grip enfoncé => la vue suit rigidement la main (rotation + translation 6DOF).
func _process_grab() -> void:
	var grabber := _pick_grab_controller()
	if grabber and not _grabbing:
		_grabbing = true
		_grab_controller = grabber
		_last_grab_tf = grabber.global_transform
	elif _grabbing and grabber == null:
		_grabbing = false
		_grab_controller = null
	elif _grabbing:
		var cur := _grab_controller.global_transform
		var d := cur * _last_grab_tf.affine_inverse()
		_pos = d * _pos
		_rot = (d.basis.orthonormalized() * _rot).orthonormalized()
		_last_grab_tf = cur
		_apply_transform()

func _pick_grab_controller() -> XRController3D:
	if _grab_controller and _grab_controller.get_float("grip") > GRIP_THRESHOLD:
		return _grab_controller
	if right_controller.get_is_active() and right_controller.get_float("grip") > GRIP_THRESHOLD:
		return right_controller
	if left_controller.get_is_active() and left_controller.get_float("grip") > GRIP_THRESHOLD:
		return left_controller
	return null

func _process_stick_zoom(delta: float) -> void:
	if not right_controller.get_is_active():
		return
	var stick := right_controller.get_vector2("primary")
	if absf(stick.y) < STICK_DEADZONE:
		return
	_scale = clamp(_scale * (1.0 + stick.y * XR_ZOOM_SPEED * delta), _scale_min, _scale_max)
	_apply_transform()

# ----------------------- SÉLECTION + AFFICHAGE -----------------------

func _desktop_hover_select(mouse_pos: Vector2) -> void:
	var origin := desktop_camera.project_ray_origin(mouse_pos)
	var dir := desktop_camera.project_ray_normal(mouse_pos)
	_update_selection_display(active_view.select_nearest(origin, dir))

# Source UNIFIÉE du rayon droit : index droit (hand tracking) sinon manette droite.
func _right_pointer() -> Dictionary:
	if hand_tracking != null and hand_tracking.is_hand_active(HandTracking.Hand.RIGHT):
		var p := hand_tracking.right_index_pointer()
		if p.valid:
			return p
	if right_controller.get_is_active():
		return {"valid": true, "origin": right_controller.global_position, "dir": -right_controller.global_transform.basis.z}
	return {"valid": false}

func _process_xr_hover() -> void:
	var p := _right_pointer()
	if not p.valid:
		return
	_update_selection_display(active_view.select_nearest(p.origin, p.dir))

# XR GALAXY/SYSTEM : gâchette (front montant) = confirmer ; bouton B (front montant) = remonter.
func _process_xr_buttons() -> void:
	if not right_controller.get_is_active():
		return
	var trig := right_controller.get_float("trigger") > TRIGGER_THRESHOLD
	if trig and not _trigger_was_pressed:
		_confirm()
	_trigger_was_pressed = trig
	var b := right_controller.is_button_pressed("by_button")
	if b and not _b_was_pressed:
		_exit_scale()
	_b_was_pressed = b

func _follow_panel_to_selection() -> void:
	if info_panel_3d.visible and active_view.selected_index >= 0:
		info_panel_3d.global_position = active_view.get_selection_world_position(active_view.selected_index) + PANEL_OFFSET

func _refresh_selection_display() -> void:
	_update_selection_display(active_view.selected_index)

func _empty_prompt() -> String:
	match GameState.current_scale:
		GameState.Scale.SYSTEM:
			return "Survolez une planète"
		_:
			return "Survolez un système"

func _update_selection_display(index: int) -> void:
	if index < 0:
		if GameState.xr_active:
			info_panel_3d.visible = false
		else:
			info_label.text = _empty_prompt()
		return
	var txt: String = active_view.get_selection_text(index)
	if GameState.xr_active:
		info_panel_3d.text = txt
		info_panel_3d.global_position = active_view.get_selection_world_position(index) + PANEL_OFFSET
		info_panel_3d.visible = true
	else:
		info_label.text = txt

# ----------------------- CONFIRMATION / RETOUR (routage par échelle) -----------------------

# Descente à PLANET vers le POINT VISÉ : intersection rayon-sphère (PlanetView) -> direction LOCALE
# (point fixe à la surface, spin dé-roté) qui devient le point d'atterrissage. Vector3.ZERO si le rayon
# manque la planète => enter_surface choisit un point par défaut sur terre ferme.
func _descend_at(origin: Vector3, dir: Vector3) -> void:
	view_manager.enter_surface(planet_view.get_landing_direction(origin, dir))

# Descendre d'une échelle : entrer système (GALAXY) / orbiter planète (SYSTEM) / descendre (PLANET).
func _confirm() -> void:
	match GameState.current_scale:
		GameState.Scale.GALAXY:
			if active_view != null:
				view_manager.enter_system(active_view.selected_index)
		GameState.Scale.SYSTEM:
			if active_view != null:
				view_manager.enter_planet(active_view.selected_index)
		GameState.Scale.PLANET:
			view_manager.enter_surface()

# Remonter d'une échelle : SURFACE -> PLANET -> SYSTEM -> GALAXY (sans effet en GALAXY).
func _exit_scale() -> void:
	match GameState.current_scale:
		GameState.Scale.SYSTEM:
			view_manager.exit_to_galaxy()
		GameState.Scale.PLANET:
			view_manager.exit_to_system()
		GameState.Scale.SURFACE:
			view_manager.exit_to_planet()
