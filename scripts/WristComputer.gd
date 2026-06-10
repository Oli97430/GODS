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
# Libellé FR d'une catégorie d'inventaire (en-têtes de groupe du Sac détaillé, CP-INV2).
const BAG_KIND_LABEL := {
	"fruit": "Fruits", "food": "Cuisine", "fish": "Poisson", "seed": "Graines", "leaf": "Feuillage",
	"wood": "Bois", "stone": "Pierre", "ore": "Minerai", "gem": "Gemmes", "metal": "Lingots",
	"build": "Construction", "gear": "Équipement",
}
var _speed_button: Button
var _skip_button: Button
var _weather_button: Button
var _lamp_button: Button   # lampe nocturne du joueur (univers sous-marin / nuit)
var _weapon_button: Button   # revolver du joueur (mode combat opt-in)
var _plasma_button: Button   # fusil à plasma du joueur
var _grenade_button: Button  # lance-grenades du joueur
var _res_label: Label        # inventaire de récolte (résumé par catégorie)
# Onglet Bâtir data-driven (CP-CRAFT) : sélecteur de catégorie + liste de recettes (CraftLibrary).
var _craft_cat := CraftLibrary.CAT_BUILD
var _recipe_vbox: VBoxContainer        # conteneur des boutons de recette (repeuplé au changement de catégorie)
var _recipe_buttons: Array = []        # [{btn:Button, recipe:Dictionary}] pour rafraîchir l'accessibilité (coût)
var _bag_vbox: VBoxContainer           # liste détaillée du Sac par catégorie (CP-INV2), reconstruite sur Inventory.changed
var _coop_label: Label       # coop (CP4) : statut réseau
var _coop_host_btn: Button
var _coop_join_btn: Button
var _coop_leave_btn: Button
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
	_subviewport.render_target_update_mode = SubViewport.UPDATE_DISABLED   # perf : pas de rendu tant que la montre est cachée
	_ht = get_node_or_null(hand_tracking_path)
	_left_ctrl = get_node_or_null(left_controller_path)
	_right_ctrl = get_node_or_null(right_controller_path)
	_cam = get_node_or_null(camera_path)
	_vm = get_node_or_null(view_manager_path)
	_surface_view = get_node_or_null(surface_view_path)
	action_pressed.connect(_on_action)

# Construit l'arbre Control dans le SubViewport (extensible : ajouter ici labels/boutons).
func _build_ui() -> void:
	# Crispness : on dessine l'UI dans un repère DESIGN fixe (300×580) puis on la met à l'échelle pour remplir
	# le SubViewport HAUTE RÉSOLUTION (540×1044) => texte net, mise en page inchangée, zéro retouche de police.
	# (Le poke 3D→2D utilise la taille du SubViewport => reste correct, Godot pique l'input à travers l'échelle.)
	var design := Vector2(300.0, 580.0)
	var root := Panel.new()
	root.size = design
	root.scale = Vector2(_subviewport.size) / design
	root.theme = _make_theme()                    # thème cohérent (boutons arrondis, onglets, contraste)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.045, 0.065, 0.105, 0.96)
	sb.set_corner_radius_all(20)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.30, 0.78, 0.98, 0.85)
	sb.shadow_color = Color(0.10, 0.55, 0.85, 0.35)
	sb.shadow_size = 6
	root.add_theme_stylebox_override("panel", sb)
	_subviewport.add_child(root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 14)
	root.add_child(margin)

	# Pile : en-tête + TabContainer (contrôles rangés par thème) + bouton contextuel TOUJOURS visible dessous.
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# En-tête : pastille d'accent + titre + filet lumineux dessous (lisibilité + cachet « ordinateur »).
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vbox.add_child(head)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(10, 10)
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(0.35, 0.95, 0.75)
	dsb.set_corner_radius_all(5)
	dot.add_theme_stylebox_override("panel", dsb)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(dot)
	var title := _add_label(head, "ORDINATEUR DE BORD", 17, Color(0.66, 0.88, 1.0))
	title.autowrap_mode = TextServer.AUTOWRAP_OFF   # titre sur une seule ligne
	var rule := Panel.new()
	rule.custom_minimum_size = Vector2(0, 2)
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0.30, 0.78, 0.98, 0.55)
	rule.add_theme_stylebox_override("panel", rsb)
	vbox.add_child(rule)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 15)   # libellés d'onglets lisibles sur écran étroit
	tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	vbox.add_child(tabs)

	# --- Onglet SONDE : lectures (échelle / planète / coords / seed / heure / météo / combat) ---
	var t_probe := _make_tab(tabs, "Sonde")
	_scale_label = _add_label(t_probe, "—", 20, Color.WHITE)
	_planet_label = _add_label(t_probe, "—", 18, Color(0.85, 0.90, 1.0))
	_coords_label = _add_label(t_probe, "—", 16, Color(0.80, 0.85, 0.90))
	_seed_label = _add_label(t_probe, "—", 14, Color(0.60, 0.70, 0.80))
	_time_label = _add_label(t_probe, "—", 16, Color(1.0, 0.85, 0.55))   # heure + vitesse (phase 12)
	_weather_label = _add_label(t_probe, "—", 15, Color(0.70, 0.82, 0.95))   # météo (phase 13)
	_combat_label = _add_label(t_probe, "", 16, Color(1.0, 0.62, 0.55))      # combat (phase 26 CP3)

	# --- Onglet TEMPS : vitesse du temps / saut de phase / forçage météo + lampe ---
	var t_time := _make_tab(tabs, "Temps")
	var ctrl_row := HBoxContainer.new()
	ctrl_row.add_theme_constant_override("separation", 8)
	t_time.add_child(ctrl_row)
	_speed_button = _mk_tool_button("", _on_speed, 16, 48)
	ctrl_row.add_child(_speed_button)
	_skip_button = _mk_tool_button("", _on_skip, 16, 48)
	ctrl_row.add_child(_skip_button)
	_weather_button = _mk_tool_button("", _on_weather, 16, 48)
	ctrl_row.add_child(_weather_button)
	_refresh_time_buttons()
	_lamp_button = _mk_tool_button("Lampe OFF", _on_lamp, 18, 50)
	t_time.add_child(_lamp_button)

	# --- Onglet SAC (CP-INV2) : en-tête compact + outil + actions rapides (auto) + LISTE DÉTAILLÉE défilante
	# par catégorie (pastille couleur + nom ×N + actions PAR OBJET : Manger / →Graine / Planter / Poser). ---
	var t_bag := _make_tab(tabs, "Sac")
	_res_label = _add_label(t_bag, "Sac : vide", 14, Color(0.78, 0.92, 0.72))
	var tool_btn := _mk_tool_button("⛏ Outil (hache / pioche)", _on_tool, 14, 40)
	t_bag.add_child(tool_btn)
	var food_row := HBoxContainer.new()
	food_row.add_theme_constant_override("separation", 6)
	t_bag.add_child(food_row)
	food_row.add_child(_mk_tool_button("🍴 Manger", _on_eat, 14, 36))          # auto : mange le plus nourrissant
	food_row.add_child(_mk_tool_button("🌱 → Graines", _on_decompose, 14, 36)) # auto : décompose un fruit
	# Liste détaillée : un groupe par catégorie (KIND_ORDER), une ligne par objet, actions contextuelles.
	var bag_scroll := ScrollContainer.new()
	bag_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bag_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	t_bag.add_child(bag_scroll)
	_bag_vbox = VBoxContainer.new()
	_bag_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bag_vbox.add_theme_constant_override("separation", 3)
	bag_scroll.add_child(_bag_vbox)
	_populate_bag()
	if not Inventory.changed.is_connected(_populate_bag):
		Inventory.changed.connect(_populate_bag)

	# --- Onglet BÂTIR (CP-CRAFT) : catalogue de craft DATA-DRIVEN (CraftLibrary). Sélecteur de catégorie
	# en haut, liste de recettes (nom + coût, grisé si non finançable) défilante dessous, jardinage en bas. ---
	var t_build := _make_tab(tabs, "Bâtir")
	var cat_grid := GridContainer.new()
	cat_grid.columns = 3
	cat_grid.add_theme_constant_override("h_separation", 4)
	cat_grid.add_theme_constant_override("v_separation", 4)
	t_build.add_child(cat_grid)
	for cat in CraftLibrary.CATEGORIES:
		cat_grid.add_child(_mk_tool_button(cat, _on_pick_cat.bind(cat), 12, 30))
	var recipe_scroll := ScrollContainer.new()
	recipe_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recipe_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	t_build.add_child(recipe_scroll)
	_recipe_vbox = VBoxContainer.new()
	_recipe_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_vbox.add_theme_constant_override("separation", 4)
	recipe_scroll.add_child(_recipe_vbox)
	t_build.add_child(_mk_tool_button("🌱 Planter une graine", _on_plant, 13, 36))
	_populate_recipes()
	if not Inventory.changed.is_connected(_refresh_recipe_affordability):
		Inventory.changed.connect(_refresh_recipe_affordability)

	# --- Onglet COOP : multijoueur + changement de système + armes (combat opt-in) ---
	var t_coop := _make_tab(tabs, "Coop")
	_coop_label = _add_label(t_coop, "Coop : hors-ligne", 15, Color(0.62, 0.80, 1.0))
	var coop_row := HBoxContainer.new()
	coop_row.add_theme_constant_override("separation", 6)
	t_coop.add_child(coop_row)
	_coop_host_btn = _mk_coop_button("Héberger", _on_coop_host)
	coop_row.add_child(_coop_host_btn)
	_coop_join_btn = _mk_coop_button("Rejoindre", _on_coop_join)
	coop_row.add_child(_coop_join_btn)
	_coop_leave_btn = _mk_coop_button("Quitter", _on_coop_leave)
	coop_row.add_child(_coop_leave_btn)
	var sys_btn := _mk_tool_button("↩ Changer de système", _on_change_system, 16, 50)
	t_coop.add_child(sys_btn)
	_add_label(t_coop, "— Armes (combat) —", 13, Color(0.85, 0.62, 0.55))
	var weapon_row := HBoxContainer.new()
	weapon_row.add_theme_constant_override("separation", 6)
	t_coop.add_child(weapon_row)
	_weapon_button = _mk_coop_button("Revolver", _on_weapon)
	weapon_row.add_child(_weapon_button)
	_plasma_button = _mk_coop_button("Plasma", _on_plasma)
	weapon_row.add_child(_plasma_button)
	_grenade_button = _mk_coop_button("Grenade", _on_grenade)
	weapon_row.add_child(_grenade_button)

	# Bouton contextuel TOUJOURS visible sous les onglets (remonter d'échelle / atterrir...).
	_action_button = Button.new()
	_action_button.text = "—"
	_action_button.add_theme_font_size_override("font_size", 20)
	_action_button.custom_minimum_size = Vector2(0, 52)
	_action_button.disabled = true
	_action_button.pressed.connect(_on_action_btn)
	vbox.add_child(_action_button)

# Thème cohérent de l'ordinateur de poignet : palette sombre + accent cyan, boutons arrondis avec états
# (survol / pressé / désactivé) et onglets nets. Centralise l'esthétique => tous les onglets en bénéficient.
func _make_theme() -> Theme:
	var accent := Color(0.32, 0.80, 0.98)
	var accent_dim := Color(0.18, 0.42, 0.56)
	var card := Color(0.12, 0.17, 0.25)
	var card_hi := Color(0.18, 0.27, 0.38)
	var text := Color(0.90, 0.94, 0.98)
	var text_dim := Color(0.58, 0.68, 0.80)
	var th := Theme.new()
	# --- Boutons : carte arrondie + liseré, survol éclairci, pressé accentué, désactivé estompé ---
	th.set_stylebox("normal", "Button", _btn_box(card, accent_dim, 1))
	th.set_stylebox("hover", "Button", _btn_box(card_hi, accent, 2))
	th.set_stylebox("pressed", "Button", _btn_box(accent_dim, accent, 2))
	th.set_stylebox("disabled", "Button", _btn_box(Color(0.08, 0.10, 0.13, 0.7), Color(0.16, 0.20, 0.26), 1))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())   # pas d'anneau de focus (poke VR)
	th.set_color("font_color", "Button", text)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color.WHITE)
	th.set_color("font_disabled_color", "Button", Color(0.44, 0.52, 0.62))
	# --- Onglets : sélectionné en carte haute + accent, inactifs estompés, contenu en panneau arrondi ---
	th.set_stylebox("tab_selected", "TabContainer", _tab_box(card_hi, accent))
	th.set_stylebox("tab_unselected", "TabContainer", _tab_box(Color(0.07, 0.10, 0.15, 0.5), Color(0, 0, 0, 0)))
	th.set_stylebox("tab_hovered", "TabContainer", _tab_box(card, accent_dim))
	th.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	var panel_box := StyleBoxFlat.new()
	panel_box.bg_color = Color(0.06, 0.09, 0.14, 0.85)
	panel_box.set_corner_radius_all(10)
	panel_box.set_content_margin_all(8)
	th.set_stylebox("panel", "TabContainer", panel_box)
	th.set_color("font_selected_color", "TabContainer", accent)
	th.set_color("font_unselected_color", "TabContainer", text_dim)
	th.set_color("font_hovered_color", "TabContainer", text)
	th.set_color("font_color", "Label", text)
	return th

# Boîte de bouton arrondie (fond + liseré + marges internes confortables pour le poke).
func _btn_box(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(9)
	s.set_border_width_all(bw)
	s.border_color = border
	s.content_margin_left = 8.0
	s.content_margin_right = 8.0
	s.content_margin_top = 5.0
	s.content_margin_bottom = 5.0
	return s

# Boîte d'onglet : coins SUPÉRIEURS arrondis + soulignement d'accent (état sélectionné).
func _tab_box(bg: Color, underline: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.border_width_bottom = 3 if underline.a > 0.01 else 0
	s.border_color = underline
	s.content_margin_left = 9.0
	s.content_margin_right = 9.0
	s.content_margin_top = 5.0
	s.content_margin_bottom = 5.0
	return s

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
	var on: bool = _alpha > 0.01
	_screen.visible = on
	# Perf : ne rend la texture du SubViewport (Panel + ~25 widgets) QUE quand la montre est visible (sinon à 90 Hz pour rien).
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED

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
	if _res_label:
		_res_label.text = _res_summary()
	_update_coop()

# --- Coop (CP4) : statut + héberger/rejoindre/quitter à la montre (IP réglée au bureau via Settings.coop_ip) ---
func _mk_coop_button(txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_size_override("font_size", 15)
	b.custom_minimum_size = Vector2(0, 46)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.pressed.connect(cb)
	return b

# Bouton pleine largeur pour les onglets (libellé + callback + taille). clip_text : pas de débordement.
func _mk_tool_button(txt: String, cb: Callable, font_size: int, height: int) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_size_override("font_size", font_size)
	b.custom_minimum_size = Vector2(0, height)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.pressed.connect(cb)
	return b

# Crée un onglet (marge + VBox) dans le TabContainer ; le NOM du conteneur = libellé de l'onglet.
func _make_tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var mc := MarginContainer.new()
	mc.name = title
	mc.add_theme_constant_override("margin_left", 8)
	mc.add_theme_constant_override("margin_right", 8)
	mc.add_theme_constant_override("margin_top", 12)
	mc.add_theme_constant_override("margin_bottom", 8)
	tabs.add_child(mc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	mc.add_child(vb)
	return vb

func _update_coop() -> void:
	if _coop_label == null:
		return
	if not NetworkManager.is_active():
		_coop_label.text = "Coop : hors-ligne"
	elif NetworkManager.is_host():
		_coop_label.text = "Coop : HÔTE — %d invité(s)" % NetworkManager.peers().size()
	else:
		_coop_label.text = "Coop : invité (connecté)"
	var active: bool = NetworkManager.is_active()
	if _coop_host_btn:
		_coop_host_btn.disabled = active
		_coop_join_btn.disabled = active
		_coop_leave_btn.disabled = not active

func _on_coop_host() -> void:
	NetworkManager.host()

func _on_coop_join() -> void:
	NetworkManager.join(Settings.coop_ip)

func _on_coop_leave() -> void:
	NetworkManager.leave()

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

# Bouton « Changer de système » : rouvre l'écran de départ (teardown propre vers la galaxie).
func _on_change_system() -> void:
	ui_confirm.emit()
	if _vm != null and _vm.has_method("return_to_start_menu"):
		_vm.return_to_start_menu()

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

# Outil de récolte UNIQUE (hache+pioche) — équipe / range (exclusif avec les armes côté PlayerController).
func _on_tool() -> void:
	ui_confirm.emit()
	var p = _player_ref()
	if p != null and p.has_method("toggle_tool"):
		p.toggle_tool()

# En-tête compact du Sac : total d'objets + nombre de types (le détail est dans la liste défilante).
func _res_summary() -> String:
	var total := 0
	var types := 0
	for id in Inventory.resources:
		var n := int(Inventory.resources[id])
		if n > 0:
			total += n
			types += 1
	if total == 0:
		return "Sac : vide"
	return "Sac : %d objets · %d types" % [total, types]

# Manger : consomme le fruit comestible le plus nourrissant en stock => soin du joueur.
func _on_eat() -> void:
	ui_confirm.emit()
	var best := ""
	var best_heal := 0.0
	for id in Inventory.resources:
		var h := HarvestLibrary.item_heal(id)
		if h > best_heal:
			best_heal = h
			best = id
	if best == "" or best_heal <= 0.0:
		return
	if Inventory.consume_resource(best, 1):
		var p = _player_ref()
		if p != null and p.has_method("eat"):
			p.eat(best_heal)

# Décomposer : transforme un fruit en stock en SA graine (alternative à Manger — au choix du joueur).
func _on_decompose() -> void:
	ui_confirm.emit()
	var fruit := ""
	for id in Inventory.resources:
		if HarvestLibrary.item_kind(id) == HarvestLibrary.KIND_FRUIT and int(Inventory.resources[id]) > 0:
			fruit = id
			break
	if fruit == "":
		return
	var seed_id := HarvestLibrary.seed_for_fruit(fruit)
	if seed_id == "":
		return
	if Inventory.consume_resource(fruit, 1):
		Inventory.add_resource(seed_id, 1)

# --- Sac DÉTAILLÉ (CP-INV2) : reconstruit la liste à plat, groupée par catégorie, avec actions par objet ---

# (Re)construit la liste du Sac : un en-tête par catégorie (KIND_ORDER), une ligne par objet trié par quantité
# décroissante. Reconstruit à l'ouverture du panneau ET sur Inventory.changed (récolte / craft / consommation).
func _populate_bag() -> void:
	if _bag_vbox == null:
		return
	for c in _bag_vbox.get_children():
		c.queue_free()
	var by_kind := {}
	for id in Inventory.resources:
		if int(Inventory.resources[id]) <= 0:
			continue
		var k := HarvestLibrary.item_kind(id)
		if not by_kind.has(k):
			by_kind[k] = []
		(by_kind[k] as Array).append(id)
	if by_kind.is_empty():
		var empty := _add_label(_bag_vbox, "Sac vide — récolte des ressources dans le monde (hache / pioche).", 12, Color(0.62, 0.70, 0.62))
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	for k in HarvestLibrary.KIND_ORDER:
		if not by_kind.has(k):
			continue
		var ids: Array = by_kind[k]
		ids.sort_custom(func(a, b): return int(Inventory.resources[a]) > int(Inventory.resources[b]))
		_bag_vbox.add_child(_bag_category_header(k))
		for id in ids:
			_bag_vbox.add_child(_bag_item_row(String(id)))

# En-tête de catégorie (libellé FR en capitales, ton sourd).
func _bag_category_header(kind: String) -> Label:
	var l := Label.new()
	l.text = String(BAG_KIND_LABEL.get(kind, kind)).to_upper()
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.58, 0.72, 0.60))
	return l

# Ligne d'objet : pastille couleur + « Nom ×N » + boutons d'action CONTEXTUELS (selon la catégorie).
func _bag_item_row(id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var sw := ColorRect.new()
	sw.color = HarvestLibrary.item_color(id)
	sw.custom_minimum_size = Vector2(15, 15)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sw)
	var name_l := Label.new()
	name_l.text = "%s ×%d" % [HarvestLibrary.item_name(id), int(Inventory.resources[id])]
	name_l.add_theme_font_size_override("font_size", 13)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	row.add_child(name_l)
	var kind := HarvestLibrary.item_kind(id)
	if HarvestLibrary.item_heal(id) > 0.0:                                   # comestible (fruit / plat) -> soin
		row.add_child(_mk_bag_action("🍴", _bag_eat.bind(id)))
	if kind == HarvestLibrary.KIND_FRUIT and HarvestLibrary.seed_for_fruit(id) != "":
		row.add_child(_mk_bag_action("🌱", _bag_decompose.bind(id)))         # fruit -> sa graine
	if kind == HarvestLibrary.KIND_SEED and HarvestLibrary.is_plantable(id):
		row.add_child(_mk_bag_action("Planter", _bag_plant.bind(id)))        # graine -> mode plantation
	if kind == HarvestLibrary.KIND_BUILD:
		row.add_child(_mk_bag_action("Poser", _bag_place.bind(id)))          # pièce construite -> mode pose
	if kind == HarvestLibrary.KIND_GEAR:
		row.add_child(_mk_bag_action("Équiper", _bag_equip.bind(id)))        # équipement -> en main
	return row

# Petit bouton d'action d'une ligne d'objet (compact).
func _mk_bag_action(txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_size_override("font_size", 12)
	b.custom_minimum_size = Vector2(0, 26)
	b.clip_text = true
	b.pressed.connect(cb)
	return b

# Actions PAR OBJET (id précis) : manger / décomposer / planter / poser. Inventory.changed -> liste reconstruite.
func _bag_eat(id: String) -> void:
	ui_confirm.emit()
	var h := HarvestLibrary.item_heal(id)
	if h <= 0.0:
		return
	if Inventory.consume_resource(id, 1):
		var p = _player_ref()
		if p != null and p.has_method("eat"):
			p.eat(h)

func _bag_decompose(id: String) -> void:
	ui_confirm.emit()
	var seed_id := HarvestLibrary.seed_for_fruit(id)
	if seed_id == "":
		return
	if Inventory.consume_resource(id, 1):
		Inventory.add_resource(seed_id, 1)

func _bag_plant(id: String) -> void:
	ui_confirm.emit()
	if Inventory.resource_count(id) > 0 and _surface_view != null and _surface_view.has_method("start_plant"):
		_surface_view.start_plant(id)

func _bag_place(id: String) -> void:
	ui_confirm.emit()
	_enter_build(id)

# Équipe un équipement porté (CP-PÊCHE : la canne à pêche → mode pêche). Toggle via la même action.
func _bag_equip(id: String) -> void:
	ui_confirm.emit()
	var p = _player_ref()
	if p == null:
		return
	if id == "fishing_rod" and p.has_method("toggle_rod"):
		p.toggle_rod()

# --- Onglet Bâtir DATA-DRIVEN (CP-CRAFT) : catégorie → liste de recettes (CraftLibrary) → dispatch ---

# Change la catégorie affichée puis repeuple la liste de recettes.
func _on_pick_cat(cat: String) -> void:
	ui_confirm.emit()
	_craft_cat = cat
	_populate_recipes()

# (Re)génère les boutons de recette de la catégorie courante (un bouton par recette de CraftLibrary).
func _populate_recipes() -> void:
	if _recipe_vbox == null:
		return
	for c in _recipe_vbox.get_children():
		c.queue_free()
	_recipe_buttons.clear()
	for r in CraftLibrary.recipes_for(_craft_cat):
		var label := "%s  (%s)" % [String(r.name), CraftLibrary.cost_text(r)]
		var b := _mk_tool_button(label, _craft_recipe.bind(r), 13, 34)
		_recipe_vbox.add_child(b)
		_recipe_buttons.append({"btn": b, "recipe": r})
	_refresh_recipe_affordability()

# Grise les recettes non finançables (appelé au peuplement + sur Inventory.changed).
func _refresh_recipe_affordability() -> void:
	for e in _recipe_buttons:
		var b: Button = e.btn
		if is_instance_valid(b):
			b.disabled = not _can_afford(e.recipe)

# Vrai si l'inventaire couvre le coût d'une recette (catégorie de ressource OU id exact).
func _can_afford(r: Dictionary) -> bool:
	var need := int(r.qty)
	if bool(r.by_kind):
		var total := 0
		for id in Inventory.resources:
			if HarvestLibrary.item_kind(id) == String(r.src):
				total += int(Inventory.resources[id])
		return total >= need
	return Inventory.resource_count(String(r.src)) >= need

# Exécute une recette via les helpers de craft : consomme l'entrée, produit la sortie, et entre en
# mode POSE si « place ». (Helpers _craft_single/_consume/_batch/_batch_id + _enter_build inchangés.)
func _craft_recipe(r: Dictionary) -> void:
	ui_confirm.emit()
	var out_n := int(r.get("out_n", 1))
	var out_id := String(r.id)
	if bool(r.by_kind):
		if out_n > 1:
			_craft_batch(String(r.src), int(r.qty), out_id, out_n)
		else:
			_craft_consume(String(r.src), int(r.qty), out_id)
	else:
		if out_n > 1:
			_craft_batch_id(String(r.src), int(r.qty), out_id, out_n)
		else:
			_craft_single(String(r.src), int(r.qty), out_id)
	if bool(r.place):
		_enter_build(out_id)
	_refresh_recipe_affordability()

# --- Jardinage : replanter une graine ---
func _on_plant() -> void:
	ui_confirm.emit()
	var seed_id := ""
	for id in Inventory.resources:
		if HarvestLibrary.item_kind(id) == HarvestLibrary.KIND_SEED and int(Inventory.resources[id]) > 0:
			seed_id = id
			break
	if seed_id == "":
		return
	if _surface_view != null and _surface_view.has_method("start_plant"):
		_surface_view.start_plant(seed_id)

# Entre en mode construction si on a du stock de l'item demandé.
func _enter_build(item: String) -> void:
	if Inventory.resource_count(item) > 0 and _surface_view != null and _surface_view.has_method("start_build"):
		_surface_view.start_build(item)

# Consomme `n` d'un item SPÉCIFIQUE (id exact), produit 1 `output`. Pas assez → skip.
func _craft_single(item_id: String, n: int, output: String) -> void:
	if Inventory.resource_count(item_id) >= n:
		Inventory.consume_resource(item_id, n)
		Inventory.add_resource(output, 1)

# Consomme `n` unités de n'importe quel item de la catégorie `kind`, puis ajoute 1 `output`. Pas assez → skip.
func _craft_consume(kind: String, n: int, output: String) -> void:
	var total := 0
	for id in Inventory.resources:
		if HarvestLibrary.item_kind(id) == kind:
			total += int(Inventory.resources[id])
	if total < n:
		return
	var left := n
	for id in Inventory.resources.keys():
		if left <= 0:
			break
		if HarvestLibrary.item_kind(id) == kind:
			var have := int(Inventory.resources[id])
			var take := mini(have, left)
			Inventory.consume_resource(id, take)
			left -= take
	Inventory.add_resource(output, 1)

# Lot : consomme `n_in` unités de la catégorie `kind` et produit `n_out` `output`. Pas assez → skip.
func _craft_batch(kind: String, n_in: int, output: String, n_out: int) -> void:
	var total := 0
	for id in Inventory.resources:
		if HarvestLibrary.item_kind(id) == kind:
			total += int(Inventory.resources[id])
	if total < n_in:
		return
	var left := n_in
	for id in Inventory.resources.keys():
		if left <= 0:
			break
		if HarvestLibrary.item_kind(id) == kind:
			var take := mini(int(Inventory.resources[id]), left)
			Inventory.consume_resource(id, take)
			left -= take
	Inventory.add_resource(output, n_out)

# Lot par id EXACT : consomme `n_in` de `item_id`, produit `n_out` `output`. Pas assez → skip.
func _craft_batch_id(item_id: String, n_in: int, output: String, n_out: int) -> void:
	if Inventory.resource_count(item_id) >= n_in:
		Inventory.consume_resource(item_id, n_in)
		Inventory.add_resource(output, n_out)

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
