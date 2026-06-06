extends Node3D
## Écran de DÉPART « Choisir un système ». Au lancement, le joueur choisit un SEED (l'univers) et un
## SYSTÈME dans une liste, puis démarre DIRECTEMENT dans la vue système choisie. Fonctionne au BUREAU
## (overlay plein écran) ET au CASQUE (panneau worldspace dans un SubViewport, interaction rayon/poke
## exactement comme OptionsPanelXR). Gèle la navigation galaxie via GameState.start_menu_open tant qu'il
## est ouvert ; se libère après le démarrage. Bypassé par le flag dev --auto-surface.
##
## Déterminisme : la liste vient de GalaxyGenerator.generate(seed, …) (déjà bâtie par GalaxyView). Changer
## le seed reconstruit la galaxie (GalaxyView.rebuild) ; les index proposés indexent data.systems → l'appel
## ViewManager.enter_system(index) reste cohérent.

@export var galaxy_view_path: NodePath
@export var view_manager_path: NodePath
@export var camera_path: NodePath              # XRCamera3D (ancrage du panneau au casque)
@export var left_controller_path: NodePath
@export var right_controller_path: NodePath
@export var hand_tracking_path: NodePath

var skip_dev_bypass := false   # true quand l'écran est ROUVERT en jeu (« changer de système ») : ignore les flags dev

const FEATURED := 16                # nombre de systèmes proposés par tirage (échantillon des 400)
const VP_SIZE := Vector2i(820, 860) # px du SubViewport (casque)
const QUAD_SIZE := Vector2(0.82, 0.86)
const OPEN_DIST := 1.15             # m devant la caméra
const POKE_FRONT := 0.05
const POKE_BACK := 0.04
const POKE_TOUCH := 0.008
const HILITE := Color(0.45, 0.85, 1.0)   # surlignage de la ligne sélectionnée
const FADE_DELAY := 2.0                   # s : laisse le logo GODS respirer avant d'afficher le menu
const FADE_DUR := 0.8                     # s : durée du fondu d'entrée du menu

var _galaxy: GalaxyView
var _vm
var _cam: Camera3D
var _left: XRController3D
var _right: XRController3D
var _ht: HandTracking

var _seed: int = 0
var _featured: Array[int] = []      # index (dans data.systems) des systèmes proposés
var _selected := 0
var _populated := false

# UI (commune bureau/casque)
var _seed_edit: LineEdit
var _rows: Array[Button] = []
var _detail: Label
var _row_group: ButtonGroup
var _preview: SystemPreview

# Bureau
var _overlay: CanvasLayer
# Casque
var _vp: SubViewport
var _screen: MeshInstance3D
var _mat: StandardMaterial3D
var _ui_pressed := false
var _last_pixel := Vector2.ZERO
var _anchor_ticks := 0
var _galaxy_pick := -1   # index galaxie ciblé en POINTANT une étoile (-1 = utiliser la sélection de la liste)
var _trig_prev := false  # front montant de la gâchette (verrou de l'étoile visée)
var _pick_label: Label
var _fade_t := 0.0       # temps écoulé pour le fondu d'entrée du menu
var _desktop_root: Control   # racine de l'overlay bureau (pour le fondu)

func _ready() -> void:
	# Bypass dev : --auto-surface descend direct au sol (ViewManager) => pas d'écran de départ.
	# (Ignoré quand l'écran est ROUVERT en jeu via « changer de système ».)
	if not skip_dev_bypass and OS.get_cmdline_user_args().has("--auto-surface"):
		queue_free()
		return
	_galaxy = get_node_or_null(galaxy_view_path)
	_vm = get_node_or_null(view_manager_path)
	_cam = get_node_or_null(camera_path)
	_left = get_node_or_null(left_controller_path)
	_right = get_node_or_null(right_controller_path)
	_ht = get_node_or_null(hand_tracking_path)
	# Démarre sur le DERNIER seed exploré s'il existe (« Continuer »), sinon le seed courant.
	_seed = Settings.start_last_seed if Settings.start_last_seed >= 0 else GameState.global_seed
	GameState.start_menu_open = true   # gèle la navigation galaxie tant que l'écran est ouvert
	var content := _build_content()
	if GameState.xr_active:
		_mount_vr(content)
	else:
		_mount_desktop(content)
	if skip_dev_bypass:
		_fade_t = FADE_DELAY   # rouvert en jeu (pas de logo) : fondu immédiat (0,8 s), sans le délai du logo
	set_process(true)

func _process(dt: float) -> void:
	_apply_fade(dt)
	# 1er tick : GalaxyView.data est prête (son _ready a eu lieu) -> remplit la liste.
	if not _populated:
		if _galaxy != null and _galaxy.data != null:
			_populate()
		return
	if not GameState.xr_active:
		return
	# --- Casque : interaction rayon/poke -> évènements souris synthétiques dans le SubViewport. ---
	if _anchor_ticks < 6:   # ré-ancre les 1ers ticks (caméra XR en cours de stabilisation) puis fige
		_anchor_vr()
		_anchor_ticks += 1
	var hit := _poke_target()
	if not hit.valid:
		if _ui_pressed:
			_push_button(_last_pixel, false)
			_ui_pressed = false
		_hover_galaxy()   # pas sur le panneau => on vise la galaxie derrière pour cibler une étoile
		return
	_trig_prev = false    # sur le panneau : on n'arme pas la visée galaxie
	_last_pixel = hit.pixel
	_push_motion(hit.pixel)
	if hit.pressing and not _ui_pressed:
		_push_button(hit.pixel, true)
		_ui_pressed = true
	elif not hit.pressing and _ui_pressed:
		_push_button(hit.pixel, false)
		_ui_pressed = false

# Fondu d'entrée : le menu apparaît en douceur après un court délai (le logo GODS a son moment).
func _apply_fade(dt: float) -> void:
	if _fade_t >= FADE_DELAY + FADE_DUR:
		return
	_fade_t += dt
	var a := clampf((_fade_t - FADE_DELAY) / FADE_DUR, 0.0, 1.0)
	if _desktop_root != null:
		_desktop_root.modulate.a = a
	if _mat != null:
		_mat.albedo_color.a = a

# --- Construction de l'UI (commune) -----------------------------------------------------------------

func _build_content() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "CHOISIR UN SYSTÈME"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	v.add_child(title)

	# « Continuer » : reprend le dernier système exploré (si déjà joué).
	if Settings.start_last_seed >= 0:
		var cont := Button.new()
		cont.text = "▶  Continuer la dernière exploration"
		cont.custom_minimum_size = Vector2(0, 46)
		cont.pressed.connect(_continue)
		v.add_child(cont)

	# Ligne SEED : champ + ◀ ▶ + 🎲 + Copier (le champ est tapable au bureau ; au casque on utilise les boutons).
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	var sl := Label.new()
	sl.text = "Seed"
	sl.custom_minimum_size.x = 56
	srow.add_child(sl)
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(_seed)
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.custom_minimum_size = Vector2(120, 48)
	_seed_edit.text_submitted.connect(func(t): _apply_seed_text(t))
	_seed_edit.focus_exited.connect(func(): _apply_seed_text(_seed_edit.text))
	srow.add_child(_seed_edit)
	srow.add_child(_mk_btn("◀", func(): _nudge_seed(-1), 52))
	srow.add_child(_mk_btn("▶", func(): _nudge_seed(1), 52))
	srow.add_child(_mk_btn("🎲", _random_seed, 52))
	var copy := Button.new()
	copy.text = "⧉ Copier"
	copy.custom_minimum_size.y = 48
	copy.pressed.connect(func(): _copy_seed(copy))
	srow.add_child(copy)
	v.add_child(srow)

	# Deux colonnes : liste des systèmes (gauche, extensible) | aperçu + infos (droite, fixe).
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)

	_row_group = ButtonGroup.new()
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	_rows.clear()
	for i in FEATURED:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = _row_group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 40)
		b.text = "…"
		b.toggled.connect(_on_row_toggled.bind(i))
		_rows.append(b)
		list.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	cols.add_child(scroll)

	var rightcol := VBoxContainer.new()
	rightcol.add_theme_constant_override("separation", 10)
	rightcol.custom_minimum_size.x = 260
	cols.add_child(rightcol)
	_preview = SystemPreview.new()
	_preview.custom_minimum_size = Vector2(252, 252)
	rightcol.add_child(_preview)
	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.modulate = Color(1, 1, 1, 0.85)
	_detail.text = ""
	rightcol.add_child(_detail)

	_pick_label = Label.new()
	_pick_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pick_label.modulate = Color(0.55, 0.85, 1.0)
	_pick_label.text = ""
	rightcol.add_child(_pick_label)

	# Astuce visée galaxie (casque) : pointer une étoile derrière le panneau.
	if GameState.xr_active:
		var ph := Label.new()
		ph.text = "🌌 Astuce : vise une étoile dans la galaxie + gâchette pour la cibler (hors liste)."
		ph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ph.modulate = Color(1, 1, 1, 0.5)
		rightcol.add_child(ph)

	var start := Button.new()
	start.text = "▶  DÉMARRER"
	start.custom_minimum_size = Vector2(0, 56)
	start.add_theme_font_size_override("font_size", 24)
	start.pressed.connect(_start)
	v.add_child(start)

	return v

# Petit bouton utilitaire (texte + callback + largeur min facultative).
func _mk_btn(txt: String, cb: Callable, min_w: float) -> Button:
	var b := Button.new()
	b.text = txt
	if min_w > 0.0:
		b.custom_minimum_size.x = min_w
	b.custom_minimum_size.y = 48
	b.pressed.connect(cb)
	return b

func _mount_desktop(content: Control) -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 120
	add_child(_overlay)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.modulate.a = 0.0   # fondu d'entrée (résorbé par _apply_fade, le logo respire d'abord)
	_desktop_root = root
	_overlay.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 780)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 22)
	panel.add_child(margin)
	margin.add_child(content)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _mount_vr(content: Control) -> void:
	_vp = SubViewport.new()
	_vp.size = VP_SIZE
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var panel := Panel.new()
	panel.size = Vector2(VP_SIZE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.10, 0.97)
	sb.set_corner_radius_all(20)
	sb.set_border_width_all(3)
	sb.border_color = Color(0.30, 0.60, 0.90, 0.9)
	panel.add_theme_stylebox_override("panel", sb)
	_vp.add_child(panel)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 26)
	panel.add_child(margin)
	margin.add_child(content)
	# Quad worldspace affichant la texture du SubViewport, ancré devant la caméra.
	_screen = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = QUAD_SIZE
	_screen.mesh = q
	_screen.top_level = true
	_screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_texture = _vp.get_texture()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.albedo_color = Color(1, 1, 1, 0.0)   # fondu d'entrée (résorbé par _apply_fade)
	_screen.material_override = _mat
	add_child(_screen)
	# L'ancrage devant la caméra se fait sur les premiers ticks de _process (caméra XR stabilisée).

# --- Logique : tirage / sélection / démarrage ------------------------------------------------------

func _populate() -> void:
	_populated = true
	# Si on boote sur un seed mémorisé différent de celui bâti par GalaxyView, on reconstruit d'abord.
	if _seed != GameState.global_seed:
		GameState.global_seed = _seed
		_galaxy.rebuild()
	_pick_featured()
	_refresh_rows()
	_select(0)
	print("[StartMenu] écran de départ — %d systèmes proposés (seed=%d)." % [_featured.size(), _seed])
	# Dev / lancement rapide : --start-system démarre direct le 1er système proposé (saute l'interaction).
	if not skip_dev_bypass and OS.get_cmdline_user_args().has("--start-system"):
		call_deferred("_start")

# Échantillonne FEATURED index répartis sur l'ensemble des systèmes (variété de noms/régions).
func _pick_featured() -> void:
	_featured.clear()
	var n: int = _galaxy.data.systems.size()
	if n <= 0:
		return
	var step: int = maxi(1, int(float(n) / float(FEATURED)))
	var i := 0
	while i < n and _featured.size() < FEATURED:
		_featured.append(i)
		i += step

func _refresh_rows() -> void:
	for r in _rows.size():
		var b := _rows[r]
		if r < _featured.size():
			var sys = _galaxy.data.systems[_featured[r]]
			var nm: String = sys.name if sys.name != "" else "Système"
			b.text = "  %s    ·  %s" % [nm, GalaxyGenerator.star_type_letter(sys.star_type)]
			b.icon = _chip(GalaxyGenerator.star_color(sys.star_type))   # pastille couleur = classe d'étoile
			b.disabled = false
			b.visible = true
		else:
			b.visible = false

# Petite pastille de couleur (texture unie) servant d'icône de ligne.
func _chip(col: Color) -> ImageTexture:
	var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	img.fill(col)
	return ImageTexture.create_from_image(img)

func _on_row_toggled(pressed: bool, index: int) -> void:
	if pressed:
		_select(index)

func _select(index: int) -> void:
	if index < 0 or index >= _featured.size():
		return
	_selected = index
	_galaxy_pick = -1                       # la liste reprend la main sur une éventuelle visée galaxie
	if _pick_label != null:
		_pick_label.text = ""
	for r in _rows.size():
		_rows[r].modulate = HILITE if r == index else Color.WHITE
	if index < _rows.size() and not _rows[index].button_pressed:
		_rows[index].button_pressed = true
	_show_system_info(_galaxy.data.systems[_featured[index]])

# Met à jour le détail + l'aperçu pour un StarSystem (sélection liste OU visée galaxie). Cheap : planètes seules.
func _show_system_info(sys) -> void:
	var sdata = SystemGenerator.generate(sys.seed_local, sys.star_type, sys.palette_id, sys.name)
	var moons := 0
	var rings := false
	for p in sdata.planets:
		moons += p.moons.size()
		if p.ring != null:
			rings = true
	var letter := GalaxyGenerator.star_type_letter(sys.star_type)
	var tags: Array = []
	if rings:
		tags.append("anneaux")
	if sdata.planets.size() >= 5:
		tags.append("riche")
	elif sdata.planets.size() <= 2:
		tags.append("modeste")
	var tagstr := ""
	if not tags.is_empty():
		tagstr = "\n[ %s ]" % " · ".join(PackedStringArray(tags))
	_detail.text = "%s\nÉtoile %s — %s\n%d planètes · %d lunes%s" % [sys.name, letter, _star_desc(letter), sdata.planets.size(), moons, tagstr]
	if _preview != null:
		_preview.set_system(GalaxyGenerator.star_color(sys.star_type), sdata.planets)

# Descripteur lisible de la classe spectrale (ton contemplatif).
func _star_desc(letter: String) -> String:
	match letter:
		"O": return "bleue, très chaude"
		"B": return "bleu-blanche"
		"A": return "blanche"
		"F": return "blanc-jaune"
		"G": return "jaune, type Soleil"
		"K": return "orange"
		"M": return "naine rouge"
	return "étoile"

func _apply_seed_text(t: String) -> void:
	var s := t.strip_edges()
	if s.is_valid_int():
		_apply_seed(int(s))
	else:
		# Seed « mot » : on dérive un entier déterministe du hash (univers partageable par un mot).
		_apply_seed(int(hash(s)) & 0x7fffffff)

func _apply_seed(s: int) -> void:
	s = maxi(0, s)
	if s == GameState.global_seed and _populated:
		return
	GameState.global_seed = s
	_seed = s
	if _seed_edit != null:
		_seed_edit.text = str(s)
	if _galaxy != null:
		_galaxy.rebuild()       # reconstruit la galaxie pour ce seed (data + multimesh cohérents)
	_pick_featured()
	_refresh_rows()
	_select(0)

func _nudge_seed(d: int) -> void:
	_apply_seed(maxi(0, GameState.global_seed + d))

func _random_seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_apply_seed(rng.randi_range(1, 999_999))

func _start() -> void:
	if _galaxy_pick >= 0:   # une étoile visée dans la galaxie a priorité sur la liste
		_start_index(_galaxy_pick)
		return
	if _featured.is_empty():
		return
	_start_index(_featured[_selected])

# Casque : vise une étoile dans la galaxie (rayon manette droite). Survol = surlignage ; gâchette = cible.
func _hover_galaxy() -> void:
	if _right == null or not _right.get_is_active() or _galaxy == null or _galaxy.data == null:
		_trig_prev = false
		return
	var o := _right.global_position
	var d := -_right.global_transform.basis.z
	var gi := _galaxy.select_nearest(o, d)   # surligne l'étoile visée + renvoie l'index (-1 si aucune)
	var trig := _right.get_float("trigger") > 0.6
	if gi >= 0 and trig and not _trig_prev:   # front montant gâchette => cible cette étoile
		_galaxy_pick = gi
		_refresh_galaxy_pick()
		BHaptics.ui_tick()
	_trig_prev = trig

func _refresh_galaxy_pick() -> void:
	if _galaxy_pick < 0 or _galaxy_pick >= _galaxy.data.systems.size():
		return
	var sys = _galaxy.data.systems[_galaxy_pick]
	_show_system_info(sys)
	for r in _rows.size():   # la liste n'a plus la sélection visible : c'est la visée galaxie qui prime
		_rows[r].modulate = Color.WHITE
	if _pick_label != null:
		_pick_label.text = "🌌 Système visé : %s" % sys.name

# Démarre dans le système d'index galaxie `gi` (mémorise seed+système pour « Continuer »).
func _start_index(gi: int) -> void:
	AudioEngine.play_ui_confirm()       # ambiance : ping de confirmation doux au départ
	GameState.start_menu_open = false   # libère la navigation AVANT d'entrer dans le système
	Settings.start_last_seed = GameState.global_seed
	Settings.start_last_system = gi
	Settings.save_settings()
	if _vm != null:
		_vm.enter_system(gi)
	# Bureau : souris laissée VISIBLE (la sélection de planète en vue système se fait au survol).
	queue_free()

# « Continuer » : reprend le dernier seed + système mémorisés (reconstruit la galaxie si besoin).
func _continue() -> void:
	var ls: int = Settings.start_last_seed
	if ls >= 0 and ls != GameState.global_seed:
		GameState.global_seed = ls
		_galaxy.rebuild()
	var n: int = _galaxy.data.systems.size()
	_start_index(clampi(Settings.start_last_system, 0, maxi(0, n - 1)))

# Copie le seed courant dans le presse-papier (partage d'univers).
func _copy_seed(btn: Button) -> void:
	DisplayServer.clipboard_set(str(_seed))
	btn.text = "Copié ✓"
	get_tree().create_timer(1.2).timeout.connect(_revert_copy.bind(btn))

func _revert_copy(btn: Button) -> void:
	if is_instance_valid(btn):
		btn.text = "⧉ Copier"

# --- Casque : ancrage + visée -> pixel (miroir d'OptionsPanelXR) -----------------------------------

func _anchor_vr() -> void:
	if _cam == null or _screen == null:
		return
	var c := _cam.global_transform
	var fwd := -c.basis.z
	var pos := c.origin + Vector3(fwd.x, fwd.y * 0.4, fwd.z).normalized() * OPEN_DIST
	_screen.global_transform = _face(pos, c.origin)

func _face(pos: Vector3, cam_pos: Vector3) -> Transform3D:
	var z := (cam_pos - pos)
	if z.length() < 0.001:
		z = Vector3.BACK
	z = z.normalized()
	var y := Vector3.UP - z * Vector3.UP.dot(z)
	if y.length() < 0.001:
		y = Vector3.RIGHT
	y = y.normalized()
	var x := y.cross(z).normalized()
	return Transform3D(Basis(x, y, z), pos)

func _poke_target() -> Dictionary:
	if _ht != null and _ht.is_hand_active(HandTracking.Hand.RIGHT):
		var tip := _ht.right_index_tip_transform().origin
		var pr := _project_to_pixel(tip)
		if pr.valid and pr.depth > -POKE_BACK and pr.depth < POKE_FRONT:
			return {"valid": true, "pixel": pr.pixel, "pressing": pr.depth < POKE_TOUCH}
		return {"valid": false}
	if _right != null and _right.get_is_active():
		var o := _right.global_position
		var d := -_right.global_transform.basis.z
		var n := _screen.global_transform.basis.z
		var denom := d.dot(n)
		if absf(denom) > 0.001:
			var tt := (_screen.global_transform.origin - o).dot(n) / denom
			if tt > 0.0:
				var pr := _project_to_pixel(o + d * tt)
				if pr.valid:
					return {"valid": true, "pixel": pr.pixel, "pressing": _right.get_float("trigger") > 0.6}
	return {"valid": false}

func _project_to_pixel(world: Vector3) -> Dictionary:
	var p: Vector3 = _screen.global_transform.affine_inverse() * world
	var size: Vector2 = (_screen.mesh as QuadMesh).size
	if absf(p.x) > size.x * 0.5 or absf(p.y) > size.y * 0.5:
		return {"valid": false}
	var pixel := Vector2(p.x / size.x + 0.5, 0.5 - p.y / size.y) * Vector2(VP_SIZE)
	return {"valid": true, "pixel": pixel, "depth": p.z}

func _push_motion(pixel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pixel
	e.global_position = pixel
	_vp.push_input(e)

func _push_button(pixel: Vector2, pressed: bool) -> void:
	if pressed:
		BHaptics.ui_tick()
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pixel
	e.global_position = pixel
	_vp.push_input(e)
