class_name WristComputer
extends Node3D
## Ordinateur de poignet : une UI 2D (Control dans un SubViewport) rendue sur un quad
## worldspace. Ancré au poignet gauche (étape 5), interagissable au doigt (étape 6),
## contenu contextuel (étape 7). Conçu pour être ÉTENDU facilement (ajouter labels/boutons).

signal action_pressed   # bouton contextuel pressé (câblé par l'extérieur, ex. ViewManager)
# Phase 22 : feedback sonore (UIClicks). ui_poke = toucher écran ; ui_confirm = action contextuelle.
signal ui_poke
signal ui_confirm
signal ui_cancel        # réservé (pas d'action « annuler » dans cette UI ; WAV prêt côté audio)

# --- Ancrage poignet gauche + affichage "montre" (étape 5) ---
@export var hand_tracking_path: NodePath
@export var left_controller_path: NodePath
@export var right_controller_path: NodePath   # pour le finger-poke fallback (rayon + gâchette)
@export var camera_path: NodePath
@export var view_manager_path: NodePath       # contenu + actions contextuelles (étape 7)
@export var surface_view_path: NodePath       # coordonnées espace-planète en SURFACE
const POKE_HOVER_FRONT := 0.05   # m : profondeur de survol devant l'écran
const POKE_HOVER_BACK := 0.04    # m : tolérance derrière
const POKE_TOUCH_Z := 0.008      # m : la pointe touche/traverse => clic
const SHOW_DOT := 0.62        # cos seuil : la face de la montre regarde la caméra => afficher
const HIDE_DOT := 0.45        # hystérésis : masquer en dessous (anti-clignotement)
const FADE_SPEED := 8.0       # vitesse du fondu
const WATCH_FLIP := 1.0       # 1 / -1 : côté de la montre (dorsal). À flipper si côté paume au casque.
const NORMAL_OFFSET := 0.02   # m : au-dessus de la surface du poignet
const FWD_OFFSET := 0.03      # m : décalage vers les doigts
const J_WRIST := XRHandTracker.HAND_JOINT_WRIST
const J_INDEX_MC := XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL
const J_MIDDLE_MC := XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL
const J_PINKY_MC := XRHandTracker.HAND_JOINT_PINKY_FINGER_METACARPAL

var _ht: HandTracking
var _left_ctrl: XRController3D
var _right_ctrl: XRController3D
var _cam: Camera3D
var _vm: Node            # ViewManager (untyped : pas de class_name + évite le couplage)
var _surface_view: Node
var _alpha := 0.0
var _showing := false
var _ui_pressed := false
var _last_pixel := Vector2.ZERO

@onready var _subviewport: SubViewport = $SubViewport
@onready var _screen: MeshInstance3D = $Screen

var _mat: StandardMaterial3D
var _scale_label: Label
var _planet_label: Label
var _coords_label: Label
var _seed_label: Label
var _time_label: Label
var _weather_label: Label
var _combat_label: Label   # lecture combat (PV/vague/score) — visible seulement arme équipée
var _action_button: Button
# Contrôle du temps (phase 12) : cycle de time_scale + saut de phase du jour.
const SPEED_PRESETS := [0.0, 1.0, 10.0, 60.0, 600.0]
const SKIP_FRACS := [0.25, 0.5, 0.75, 0.0]
const SKIP_NAMES := ["Aube", "Midi", "Soir", "Minuit"]
var _speed_button: Button
var _skip_button: Button
var _weather_button: Button
var _lamp_button: Button   # lampe nocturne du joueur (univers sous-marin / nuit)
var _weapon_button: Button   # revolver du joueur (mode combat opt-in)
var _plasma_button: Button   # fusil à plasma du joueur
var _grenade_button: Button  # lance-grenades du joueur
var _speed_idx := 1   # démarre à ×1 (cohérent avec le défaut TimeOfDay = 1.0 ; presets : pause/1/10/60/600)
var _skip_idx := 0

func _ready() -> void:
	_build_ui()
	# Le quad affiche la texture du SubViewport (UI 2D). Non éclairé + alpha (pour le fade).
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_texture = _subviewport.get_texture()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_screen.material_override = _mat
	_screen.visible = false   # masquée tant qu'on ne regarde pas son poignet
	_ht = get_node_or_null(hand_tracking_path)
	_left_ctrl = get_node_or_null(left_controller_path)
	_right_ctrl = get_node_or_null(right_controller_path)
	_cam = get_node_or_null(camera_path)
	_vm = get_node_or_null(view_manager_path)
	_surface_view = get_node_or_null(surface_view_path)
	action_pressed.connect(_on_action)

# Construit l'arbre Control dans le SubViewport (extensible : ajouter ici labels/boutons).
func _build_ui() -> void:
	var root := Panel.new()
	root.size = Vector2(_subviewport.size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.10, 0.92)
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(3)
	sb.border_color = Color(0.30, 0.60, 0.90, 0.9)
	root.add_theme_stylebox_override("panel", sb)
	_subviewport.add_child(root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	root.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	_add_label(vbox, "ORDINATEUR", 26, Color(0.60, 0.85, 1.0))
	_scale_label = _add_label(vbox, "—", 20, Color.WHITE)
	_planet_label = _add_label(vbox, "—", 18, Color(0.85, 0.90, 1.0))
	_coords_label = _add_label(vbox, "—", 16, Color(0.80, 0.85, 0.90))
	_seed_label = _add_label(vbox, "—", 14, Color(0.60, 0.70, 0.80))
	_time_label = _add_label(vbox, "—", 16, Color(1.0, 0.85, 0.55))   # heure + vitesse (phase 12)
	_weather_label = _add_label(vbox, "—", 15, Color(0.70, 0.82, 0.95))   # météo (phase 13)
	_combat_label = _add_label(vbox, "", 16, Color(1.0, 0.62, 0.55))      # combat (phase 26 CP3)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Contrôle du temps (phase 12) : poke-routé comme tout Button du SubViewport.
	var ctrl_row := HBoxContainer.new()
	ctrl_row.add_theme_constant_override("separation", 8)
	vbox.add_child(ctrl_row)
	_speed_button = Button.new()
	_speed_button.add_theme_font_size_override("font_size", 16)
	_speed_button.custom_minimum_size = Vector2(0, 46)
	_speed_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed_button.pressed.connect(_on_speed)
	ctrl_row.add_child(_speed_button)
	_skip_button = Button.new()
	_skip_button.add_theme_font_size_override("font_size", 16)
	_skip_button.custom_minimum_size = Vector2(0, 46)
	_skip_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skip_button.pressed.connect(_on_skip)
	ctrl_row.add_child(_skip_button)
	# Bouton de forçage météo (phase 13) : Auto -> Couvert -> Pluie -> Orage.
	_weather_button = Button.new()
	_weather_button.add_theme_font_size_override("font_size", 16)
	_weather_button.custom_minimum_size = Vector2(0, 46)
	_weather_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weather_button.pressed.connect(_on_weather)
	ctrl_row.add_child(_weather_button)
	_refresh_time_buttons()

	# Lampe nocturne : bascule la lampe du joueur (spot main droite / caméra). Le texte reflète l'état.
	_lamp_button = Button.new()
	_lamp_button.text = "Lampe OFF"
	_lamp_button.add_theme_font_size_override("font_size", 18)
	_lamp_button.custom_minimum_size = Vector2(0, 48)
	_lamp_button.pressed.connect(_on_lamp)
	vbox.add_child(_lamp_button)

	# Armes (mode combat opt-in) : revolver / plasma / grenade CÔTE À CÔTE (ré-appui sur l'arme active = dégainer).
	var weapon_row := HBoxContainer.new()
	weapon_row.add_theme_constant_override("separation", 6)
	vbox.add_child(weapon_row)
	_weapon_button = Button.new()
	_weapon_button.text = "Revolver"
	_weapon_button.add_theme_font_size_override("font_size", 15)
	_weapon_button.custom_minimum_size = Vector2(0, 50)
	_weapon_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weapon_button.clip_text = true
	_weapon_button.pressed.connect(_on_weapon)
	weapon_row.add_child(_weapon_button)
	_plasma_button = Button.new()
	_plasma_button.text = "Plasma"
	_plasma_button.add_theme_font_size_override("font_size", 15)
	_plasma_button.custom_minimum_size = Vector2(0, 50)
	_plasma_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plasma_button.clip_text = true
	_plasma_button.pressed.connect(_on_plasma)
	weapon_row.add_child(_plasma_button)
	_grenade_button = Button.new()
	_grenade_button.text = "Grenade"
	_grenade_button.add_theme_font_size_override("font_size", 15)
	_grenade_button.custom_minimum_size = Vector2(0, 50)
	_grenade_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grenade_button.clip_text = true
	_grenade_button.pressed.connect(_on_grenade)
	weapon_row.add_child(_grenade_button)

	_action_button = Button.new()
	_action_button.text = "—"
	_action_button.add_theme_font_size_override("font_size", 20)
	_action_button.custom_minimum_size = Vector2(0, 56)
	_action_button.disabled = true
	_action_button.pressed.connect(_on_action_btn)
	vbox.add_child(_action_button)

func _add_label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l

# --- API de contenu (étape 7) ---
func set_content(scale_text: String, planet_text: String, coords_text: String, seed_text: String) -> void:
	if _scale_label:
		_scale_label.text = scale_text
		_planet_label.text = planet_text
		_coords_label.text = coords_text
		_seed_label.text = seed_text

func set_action(text: String, enabled: bool) -> void:
	if _action_button:
		_action_button.text = text
		_action_button.disabled = not enabled

# --- Fade (étape 5) ---
func set_screen_alpha(a: float) -> void:
	if _mat:
		_mat.albedo_color.a = a

# Taille du SubViewport (pour convertir un impact 3D en coordonnée 2D, étape 6).
func viewport_size() -> Vector2:
	return Vector2(_subviewport.size)

# Injecte un évènement d'entrée synthétique dans l'UI (étape 6 : finger-poke / rayon manette).
func push_ui_event(event: InputEvent) -> void:
	_subviewport.push_input(event)

# --- Ancrage + affichage type montre (étape 5) ---

func _process(dt: float) -> void:
	var frame := _left_watch_frame()
	if not frame.valid:
		_fade_to(0.0, dt)
		return
	_screen.global_transform = frame.transform
	# "Regarder sa montre" : la face de la montre (normale) pointe vers la caméra.
	var facing := 0.0
	if _cam:
		var to_cam: Vector3 = _cam.global_position - frame.transform.origin
		if to_cam.length() > 0.001:
			facing = frame.normal.dot(to_cam.normalized())
	if _showing and facing < HIDE_DOT:
		_showing = false
	elif not _showing and facing > SHOW_DOT:
		_showing = true
	_fade_to(1.0 if _showing else 0.0, dt)
	if _alpha > 0.01:
		_update_content()   # perf : reconstruire le contenu (lunes/anneau/POI/texte) SEULEMENT si la montre est visible
	if _alpha > 0.5:
		_process_poke()   # interaction seulement quand la montre est visible
	elif _ui_pressed:
		_push_button(_last_pixel, false)
		_ui_pressed = false

func _fade_to(target: float, dt: float) -> void:
	_alpha = move_toward(_alpha, target, FADE_SPEED * dt)
	set_screen_alpha(_alpha)
	_screen.visible = _alpha > 0.01

# Repère MONDE de la montre (origine + base ; +Z = face de la montre = normale). Source :
# poignet gauche du hand tracking (frame dérivée des joints, robuste à la convention), sinon
# manette gauche (fallback). { valid, transform, normal }.
func _left_watch_frame() -> Dictionary:
	if _ht != null and _ht.is_hand_active(HandTracking.Hand.LEFT):
		var w := _ht.joint_world(HandTracking.Hand.LEFT, J_WRIST).origin
		var mid := _ht.joint_world(HandTracking.Hand.LEFT, J_MIDDLE_MC).origin
		var idx := _ht.joint_world(HandTracking.Hand.LEFT, J_INDEX_MC).origin
		var pky := _ht.joint_world(HandTracking.Hand.LEFT, J_PINKY_MC).origin
		var fwd := mid - w                       # poignet -> doigts
		var across := pky - idx                  # à travers la main (index -> auriculaire)
		if fwd.length() < 0.001 or across.length() < 0.001:
			return {"valid": false}
		fwd = fwd.normalized()
		var normal := fwd.cross(across.normalized()).normalized() * WATCH_FLIP   # perpendiculaire au plan de la main (dorsal)
		if normal.length() < 0.5:
			return {"valid": false}
		var origin := w + normal * NORMAL_OFFSET + fwd * FWD_OFFSET
		return {"valid": true, "transform": _face_transform(origin, normal, fwd), "normal": normal}
	if _left_ctrl != null and _left_ctrl.get_is_active():
		var t: Transform3D = _left_ctrl.global_transform
		var normal: Vector3 = (t.basis.y.normalized()) * WATCH_FLIP   # dos du poignet ~ +Y grip
		var fwd: Vector3 = (-t.basis.z).normalized()                   # vers les doigts ~ -Z grip
		var origin: Vector3 = t.origin - fwd * 0.07 + normal * 0.03    # un peu en arrière (poignet) + au-dessus
		return {"valid": true, "transform": _face_transform(origin, normal, fwd), "normal": normal}
	return {"valid": false}

# Construit une base orthonormée : +Z = face (normale), +Y ~ up_hint (vers les doigts).
func _face_transform(origin: Vector3, normal: Vector3, up_hint: Vector3) -> Transform3D:
	var z := normal
	var y := up_hint - z * up_hint.dot(z)
	if y.length() < 0.001:
		y = Vector3.UP - z * Vector3.UP.dot(z)
	y = y.normalized()
	var x := y.cross(z).normalized()
	return Transform3D(Basis(x, y, z), origin)

# --- Finger-poke (étape 6) : pointe de l'index droit (ou rayon manette) -> UI ---

func _process_poke() -> void:
	var hit := _poke_target()
	if not hit.valid:
		if _ui_pressed:
			_push_button(_last_pixel, false)   # relâche si on quitte la surface en appuyant
			_ui_pressed = false
		return
	_last_pixel = hit.pixel
	_push_motion(hit.pixel)   # survol (hover) sur l'élément visé
	if hit.pressing and not _ui_pressed:
		_push_button(hit.pixel, true)
		_ui_pressed = true
	elif not hit.pressing and _ui_pressed:
		_push_button(hit.pixel, false)   # relâche => le Button émet "pressed"
		_ui_pressed = false

# Cible courante du poke : { valid, pixel, pressing }. Index droit (hand tracking) en
# priorité, sinon rayon manette droite + gâchette (fallback).
func _poke_target() -> Dictionary:
	if _ht != null and _ht.is_hand_active(HandTracking.Hand.RIGHT):
		var tip := _ht.right_index_tip_transform().origin
		var pr := _project_to_pixel(tip)
		if pr.valid and pr.depth > -POKE_HOVER_BACK and pr.depth < POKE_HOVER_FRONT:
			return {"valid": true, "pixel": pr.pixel, "pressing": pr.depth < POKE_TOUCH_Z}
		return {"valid": false}
	if _right_ctrl != null and _right_ctrl.get_is_active():
		var o := _right_ctrl.global_position
		var d := -_right_ctrl.global_transform.basis.z
		var n := _screen.global_transform.basis.z
		var denom := d.dot(n)
		if absf(denom) > 0.001:
			var tt := (_screen.global_transform.origin - o).dot(n) / denom
			if tt > 0.0:
				var pr := _project_to_pixel(o + d * tt)
				if pr.valid:
					return {"valid": true, "pixel": pr.pixel, "pressing": _right_ctrl.get_float("trigger") > 0.6}
	return {"valid": false}

# Projette un point MONDE sur le quad -> coordonnée 2D du SubViewport (+ profondeur signée
# le long de la normale). { valid:false } hors des bords du quad. (Math testable.)
func _project_to_pixel(world: Vector3) -> Dictionary:
	var p: Vector3 = _screen.global_transform.affine_inverse() * world
	var size: Vector2 = (_screen.mesh as QuadMesh).size
	if absf(p.x) > size.x * 0.5 or absf(p.y) > size.y * 0.5:
		return {"valid": false}
	var pixel := Vector2(p.x / size.x + 0.5, 0.5 - p.y / size.y) * viewport_size()
	return {"valid": true, "pixel": pixel, "depth": p.z}

func _push_motion(pixel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pixel
	e.global_position = pixel
	push_ui_event(e)

func _push_button(pixel: Vector2, pressed: bool) -> void:
	if pressed:
		ui_poke.emit()   # phase 22 : feedback sonore doux au toucher de l'écran montre
		BHaptics.ui_tick()   # gilet X40 : tic léger de confirmation au toucher
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pixel
	e.global_position = pixel
	push_ui_event(e)

# --- Contenu + action contextuelle (étape 7) ---

func _update_content() -> void:
	var seed_txt := "Seed global : %d" % GameState.global_seed
	var planet_txt := ""
	var coords_txt := ""
	var action_txt := "—"
	var action_on := false
	match GameState.current_scale:
		GameState.Scale.SURFACE:
			if _vm:
				planet_txt = _planet_label_text()
			coords_txt = _surface_coords_text()
			# Phase 20 couche C : nom du POI notable proche (discret, n'apparaît qu'à l'approche).
			var poi := _nearest_poi_text()
			if poi != "":
				coords_txt += "\n" + poi
			action_txt = "Remonter (orbite)"
			action_on = true
		GameState.Scale.PLANET:
			if _vm:
				planet_txt = _planet_label_text()
			action_txt = "Remonter (système)"
			action_on = true
		GameState.Scale.SYSTEM:
			# Phase 19.5 : nom propre du système courant (discret), repli « Vue système ».
			var sname: String = _vm.get_current_system_name() if (_vm and _vm.has_method("get_current_system_name")) else ""
			planet_txt = ("Système : " + sname) if sname != "" else "Vue système"
			action_txt = "Remonter (galaxie)"
			action_on = true
		GameState.Scale.GALAXY:
			planet_txt = "Vue galaxie"
	set_content("Échelle : " + _scale_name(GameState.current_scale), planet_txt, coords_txt, seed_txt)
	set_action(action_txt, action_on)
	if _time_label:
		_time_label.text = "Temps : " + _time_phase()
	if _weather_label:
		if WeatherSystem.is_configured():
			var cov := int(round(WeatherSystem.get_cloud_coverage() * 100.0))
			var pr := int(round(WeatherSystem.get_precipitation() * 100.0))
			var st := int(round(WeatherSystem.get_storm() * 100.0))
			_weather_label.text = "Météo %s — n%d p%d o%d" % [WeatherSystem.force_mode_name(), cov, pr, st]
			if _weather_button:
				_weather_button.text = WeatherSystem.force_mode_name()
		else:
			_weather_label.text = "Météo : —"
	if _combat_label:
		if GameState.combat_active:
			if GameState.combat_dead:
				_combat_label.text = "⚔ ÉLIMINÉ — V%d Score %d" % [GameState.combat_result_wave, GameState.combat_result_score]
			else:
				_combat_label.text = "⚔ PV %d/%d  V%d  Score %d" % [int(round(GameState.combat_hp)), int(round(GameState.combat_hp_max)), GameState.combat_wave, GameState.combat_score]
		else:
			_combat_label.text = ""

# Cache lunes/anneau par seed planète : _planet_label_text tourne CHAQUE frame où la montre est visible
# (90×/s au casque) — sans cache, generate_moons() reconstruisait un tableau de lunes par frame.
var _moon_cache_seed := 9223372036854775807
var _moon_cache_n := 0
var _moon_cache_ring := false

# Texte planète : nom propre (phase 19.5) + nombre de lunes + présence d'anneau (phase 14).
func _planet_label_text() -> String:
	if _vm == null:
		return ""
	var pseed: int = _vm.get_current_planet_seed()
	if pseed != _moon_cache_seed:   # recalcul SEULEMENT au changement de planète
		_moon_cache_seed = pseed
		_moon_cache_n = MoonsGenerator.generate_moons(pseed).size()
		_moon_cache_ring = MoonsGenerator.generate_ring(pseed) != null
	# Nom propre en tête (ton contemplatif) ; repli « Planète » si non disponible.
	var pname: String = _vm.get_current_planet_name() if _vm.has_method("get_current_planet_name") else ""
	var head: String = pname if pname != "" else "Planète"
	return "%s (%d lune%s%s)" % [head, _moon_cache_n, "s" if _moon_cache_n > 1 else "", " + anneau" if _moon_cache_ring else ""]

func _surface_coords_text() -> String:
	if _surface_view != null and _surface_view.has_method("player_planet_coord"):
		var c: Dictionary = _surface_view.player_planet_coord()
		if c.valid:
			return "Coord : (%d, %d)" % [c.coord.x, c.coord.y]
	return "Coord : —"

# Nom du POI notable le plus proche (phase 20 couche C), ou "" si aucun dans le rayon d'affichage.
func _nearest_poi_text() -> String:
	if _surface_view != null and _surface_view.has_method("nearest_poi"):
		var p: Dictionary = _surface_view.nearest_poi()
		if p.name != "":
			return "◆ " + p.name
	return ""

func _scale_name(s: int) -> String:
	match s:
		GameState.Scale.GALAXY:
			return "Galaxie"
		GameState.Scale.SYSTEM:
			return "Système"
		GameState.Scale.PLANET:
			return "Planète"
		GameState.Scale.SURFACE:
			return "Surface"
	return "—"

# Phase 22 : pression du bouton contextuel => son de confirmation (UIClicks) + action.
func _on_action_btn() -> void:
	ui_confirm.emit()
	action_pressed.emit()

# Action du bouton contextuel (câblée à action_pressed) : REMONTER d'une échelle
# (SURFACE -> PLANET -> SYSTEM -> GALAXY). Sans effet en GALAXY.
func _on_action() -> void:
	if _vm == null:
		return
	_vm.ascend_one_scale()

# --- Contrôle du temps (phase 12) ---

# Phase du jour (depuis l'altitude réelle du soleil au sol si dispo, sinon le % de cycle) + vitesse.
func _time_phase() -> String:
	var phase := ""
	if GameState.current_scale == GameState.Scale.SURFACE and _surface_view != null and _surface_view.has_method("sun_altitude"):
		var alt: float = _surface_view.sun_altitude()
		if alt > 0.25:
			phase = "Jour"
		elif alt > -0.05:
			phase = "Aube" if TimeOfDay.day_fraction() < 0.5 else "Crépuscule"
		else:
			phase = "Nuit"
	else:
		phase = "%d%% cycle" % int(TimeOfDay.day_fraction() * 100.0)
	var spd: float = TimeOfDay.time_scale
	return "%s · %s" % [phase, ("pause" if spd == 0.0 else "%d×" % int(spd))]

# Cycle des presets de vitesse (pause / 1× / 60× / 600×).
func _on_speed() -> void:
	_speed_idx = (_speed_idx + 1) % SPEED_PRESETS.size()
	TimeOfDay.time_scale = SPEED_PRESETS[_speed_idx]
	_refresh_time_buttons()

# Saute à la prochaine phase du jour (aube -> midi -> soir -> minuit -> ...).
func _on_skip() -> void:
	TimeOfDay.set_day_fraction(SKIP_FRACS[_skip_idx])
	_skip_idx = (_skip_idx + 1) % SKIP_FRACS.size()
	_refresh_time_buttons()

func _refresh_time_buttons() -> void:
	if _speed_button:
		var s: float = SPEED_PRESETS[_speed_idx]
		_speed_button.text = "Pause" if s == 0.0 else "%d×" % int(s)
	if _skip_button:
		_skip_button.text = "→ " + SKIP_NAMES[_skip_idx]
	if _weather_button:
		_weather_button.text = WeatherSystem.force_mode_name() if WeatherSystem.is_configured() else "Météo"

# Cycle le forçage météo (Auto -> Couvert -> Pluie -> Orage) — phase 13, pour la validation.
func _on_weather() -> void:
	WeatherSystem.set_force_mode((WeatherSystem.get_force_mode() + 1) % 4)
	_refresh_time_buttons()

# Lampe nocturne : bascule la lampe du joueur (univers sous-marin / nuit) via SurfaceView.get_player().
func _on_lamp() -> void:
	ui_confirm.emit()
	var p = _player_ref()
	if p != null and p.has_method("toggle_lamp"):
		var on: bool = p.toggle_lamp()
		if _lamp_button:
			_lamp_button.text = "Lampe ON" if on else "Lampe OFF"

# Blaster (mode combat opt-in) : équipe / dégaine l'arme du joueur via SurfaceView.get_player().
func _on_weapon() -> void:
	ui_confirm.emit()
	var p = _player_ref()
	if p != null and p.has_method("toggle_weapon"):
		p.toggle_weapon()
	_refresh_weapon_buttons()

func _on_plasma() -> void:
	ui_confirm.emit()
	var p = _player_ref()
	if p != null and p.has_method("toggle_plasma"):
		p.toggle_plasma()
	_refresh_weapon_buttons()

func _on_grenade() -> void:
	ui_confirm.emit()
	var p = _player_ref()
	if p != null and p.has_method("toggle_grenade"):
		p.toggle_grenade()
	_refresh_weapon_buttons()

# Surligne (modulate vert) le bouton de l'arme active ; les autres restent blancs.
func _refresh_weapon_buttons() -> void:
	var n := ""
	var pp = _player_ref()
	if pp != null and pp.has_method("active_weapon_name"):
		n = pp.active_weapon_name()
	var on := Color(0.5, 1.0, 0.6)
	var off := Color(1, 1, 1)
	if _weapon_button:
		_weapon_button.modulate = on if n == "Blaster" else off
	if _plasma_button:
		_plasma_button.modulate = on if n == "Plasma" else off
	if _grenade_button:
		_grenade_button.modulate = on if n == "Grenade" else off

func _player_ref():
	if _surface_view != null and _surface_view.has_method("get_player"):
		return _surface_view.get_player()
	return null
