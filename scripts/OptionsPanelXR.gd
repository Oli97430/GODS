class_name OptionsPanelXR
extends Node3D
## Panneau Options WORLDSPACE (casque) : la MÊME UI d'options (OptionsUI) rendue dans un SubViewport sur un
## quad flottant devant le joueur. Ouvre/ferme via le bouton ≡ (menu) gauche. Interaction = rayon manette
## droite + gâchette (ou pointe de l'index), réinjectés dans le SubViewport — exactement comme la montre
## (WristComputer). Pose GameState.options_open => bloque l'entrée jeu SANS pause (sûr en XR).

@export var camera_path: NodePath
@export var left_controller_path: NodePath
@export var right_controller_path: NodePath
@export var hand_tracking_path: NodePath

const VP_SIZE := Vector2i(760, 680)        # px du SubViewport
const QUAD_SIZE := Vector2(0.76, 0.68)     # m (≈ 1 px/mm) — grand panneau lisible
const OPEN_DIST := 1.1                      # m devant la caméra à l'ouverture
const POKE_FRONT := 0.05                    # m : survol devant l'écran
const POKE_BACK := 0.04                     # m : tolérance derrière
const POKE_TOUCH := 0.008                   # m : la pointe touche => clic

var _cam: Camera3D
var _left: XRController3D
var _right: XRController3D
var _ht: HandTracking
var _vp: SubViewport
var _screen: MeshInstance3D
var _mat: StandardMaterial3D
var _root: Panel
var _status: Label
var _open := false
var _menu_prev := false
var _ui_pressed := false
var _last_pixel := Vector2.ZERO

func _ready() -> void:
	_cam = get_node_or_null(camera_path)
	_left = get_node_or_null(left_controller_path)
	_right = get_node_or_null(right_controller_path)
	_ht = get_node_or_null(hand_tracking_path)
	_vp = SubViewport.new()
	_vp.size = VP_SIZE
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED   # rendu UNIQUEMENT panneau ouvert (cf. _set_open) — pas de gaspillage GPU fermé
	add_child(_vp)
	_build_ui()
	# Quad affichant la texture du SubViewport. top_level => ancré en MONDE devant la caméra à l'ouverture.
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
	_screen.material_override = _mat
	add_child(_screen)
	_screen.visible = false

func _build_ui() -> void:
	_root = Panel.new()
	_root.size = Vector2(VP_SIZE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.10, 0.96)
	sb.set_corner_radius_all(20)
	sb.set_border_width_all(3)
	sb.border_color = Color(0.30, 0.60, 0.90, 0.9)
	_root.add_theme_stylebox_override("panel", sb)
	_vp.add_child(_root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 24)
	_root.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	var title := Label.new()
	title.text = "OPTIONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	col.add_child(title)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(tabs)
	_status = OptionsUI.build_tabs(tabs)   # onglets PARTAGÉS avec le menu bureau

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 10)
	col.add_child(foot)
	var reset := Button.new()
	reset.text = "Réinitialiser"
	reset.custom_minimum_size = Vector2(0, 52)
	reset.pressed.connect(_on_reset)
	foot.add_child(reset)
	var close := Button.new()
	close.text = "Fermer  (≡)"
	close.custom_minimum_size = Vector2(0, 52)
	close.pressed.connect(_set_open.bind(false))
	foot.add_child(close)

# --- Ouverture/fermeture (bouton ≡ gauche) + interaction par frame ---

func _process(_dt: float) -> void:
	# Bascule via le bouton menu (≡) de la manette gauche (front montant).
	if _left and _left.get_is_active():
		var m := _left.is_button_pressed("menu_button")
		if m and not _menu_prev:
			_set_open(not _open)
		_menu_prev = m
	if not _open:
		return
	# Interaction rayon/poke -> évènements souris synthétiques dans le SubViewport.
	var hit := _poke_target()
	if not hit.valid:
		if _ui_pressed:
			_push_button(_last_pixel, false)
			_ui_pressed = false
		return
	_last_pixel = hit.pixel
	_push_motion(hit.pixel)
	if hit.pressing and not _ui_pressed:
		_push_button(hit.pixel, true)
		_ui_pressed = true
	elif not hit.pressing and _ui_pressed:
		_push_button(hit.pixel, false)
		_ui_pressed = false

func _set_open(v: bool) -> void:
	_open = v
	_screen.visible = v
	GameState.options_open = v
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if v else SubViewport.UPDATE_DISABLED  # rendu seulement ouvert
	if v:
		if _status:
			_status.text = OptionsUI.status_text()
		# Ancre le panneau devant la caméra, face à l'utilisateur (figé : on peut tourner la tête autour).
		if _cam:
			var c := _cam.global_transform
			var fwd := -c.basis.z
			var pos := c.origin + Vector3(fwd.x, fwd.y * 0.4, fwd.z).normalized() * OPEN_DIST
			_screen.global_transform = _face(pos, c.origin)
	else:
		_ui_pressed = false   # pas de relâche fantôme à la réouverture si on ferme en plein appui

# Base orientée : +Z (face de la texture) vers la caméra ; +Y ~ monde haut.
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

func _on_reset() -> void:
	Settings.reset_defaults()
	_root.queue_free()
	_build_ui()

# --- Visée -> pixel (miroir de WristComputer) ---

func _poke_target() -> Dictionary:
	# Pointe de l'index droit (hand tracking) en priorité, sinon rayon manette droite + gâchette.
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
		BHaptics.ui_tick()   # tic léger de confirmation au clic
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pixel
	e.global_position = pixel
	_vp.push_input(e)
