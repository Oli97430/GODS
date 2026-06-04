extends CanvasLayer
## Coop CP4 — overlay BUREAU (touche F2) pour héberger / rejoindre / quitter une session coop SANS flags de
## ligne de commande : saisie IP au clavier (persistée via Settings.coop_ip) + statut en direct. En VR, la coop
## se pilote à la MONTRE (rangée COOP) ; cet overlay est pensé pour le bureau. Autoload : CoopMenu.
## INERTE tant qu'il n'est pas ouvert (caché au boot ; ne capture l'entrée que visible). Réutilise le gel
## GameState.options_open (libère la souris + fige la locomotion, comme le menu Options — SANS pause).

const PORT := 7711

var _panel: Panel
var _status: Label
var _ip_edit: LineEdit
var _host_btn: Button
var _join_btn: Button
var _leave_btn: Button
var _open := false
var _prev_mouse := Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	NetworkManager.session_started.connect(_on_started)
	NetworkManager.session_ended.connect(_on_ended)
	NetworkManager.connection_failed_.connect(_on_failed)
	NetworkManager.peer_joined.connect(_on_peer_changed)
	NetworkManager.peer_left.connect(_on_peer_changed)

func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE   # n'avale pas les clics hors panneau
	add_child(center)

	_panel = Panel.new()
	_panel.custom_minimum_size = Vector2(440, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.11, 0.97)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.30, 0.62, 0.92, 0.95)
	sb.set_content_margin_all(22)
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_panel.add_child(v)

	var title := Label.new()
	title.text = "COOP — multijoueur"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.62, 0.86, 1.0))
	v.add_child(title)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 16)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(396, 0)
	v.add_child(_status)

	var ip_row := HBoxContainer.new()
	ip_row.add_theme_constant_override("separation", 8)
	v.add_child(ip_row)
	var ip_lbl := Label.new()
	ip_lbl.text = "IP hôte :"
	ip_lbl.add_theme_font_size_override("font_size", 16)
	ip_row.add_child(ip_lbl)
	_ip_edit = LineEdit.new()
	_ip_edit.text = Settings.coop_ip
	_ip_edit.placeholder_text = "127.0.0.1"
	_ip_edit.custom_minimum_size = Vector2(240, 38)
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_edit.text_changed.connect(_on_ip_changed)
	ip_row.add_child(_ip_edit)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	v.add_child(btn_row)
	_host_btn = _mk_button("Héberger", _on_host)
	btn_row.add_child(_host_btn)
	_join_btn = _mk_button("Rejoindre", _on_join)
	btn_row.add_child(_join_btn)

	_leave_btn = _mk_button("Quitter la session", _on_leave)
	v.add_child(_leave_btn)

	var hint := Label.new()
	hint.text = "F2 ferme · même PC : 127.0.0.1 · LAN : IP de l'hôte · l'hôte descend sur une planète, l'invité suit"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(396, 0)
	v.add_child(hint)

	_refresh()

func _mk_button(txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size = Vector2(0, 48)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F2:
		if GameState.xr_active:
			return   # en VR, la coop se pilote à la montre (pas d'overlay 2D head-locked)
		_set_open(not _open)
		get_viewport().set_input_as_handled()
	elif _open and e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		_set_open(false)
		get_viewport().set_input_as_handled()

func _set_open(v: bool) -> void:
	if v == _open:
		return
	_open = v
	visible = v
	GameState.options_open = v   # gèle la locomotion + libère la souris (même mécanisme que le menu Options)
	if v:
		_prev_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_ip_edit.text = Settings.coop_ip
		_refresh()
	else:
		Input.mouse_mode = _prev_mouse

func _on_ip_changed(t: String) -> void:
	Settings.coop_ip = t.strip_edges()
	Settings.save_settings()

func _on_host() -> void:
	NetworkManager.host(PORT)
	_refresh()

func _on_join() -> void:
	var ip := _ip_edit.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	Settings.coop_ip = ip
	Settings.save_settings()
	NetworkManager.join(ip, PORT)
	_refresh()

func _on_leave() -> void:
	NetworkManager.leave()
	_refresh()

func _on_started(_is_host: bool) -> void:
	_refresh()

func _on_ended() -> void:
	_refresh()

func _on_peer_changed(_id: int) -> void:
	_refresh()

func _on_failed() -> void:
	if _status:
		_status.text = "Connexion échouée — vérifie l'IP, le port (7711) et le pare-feu."
		_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
	if _host_btn:
		_host_btn.disabled = false
		_join_btn.disabled = false
		_leave_btn.disabled = true

func _refresh() -> void:
	if _status == null:
		return
	_status.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	if not NetworkManager.is_active():
		_status.text = "Hors-ligne. Héberge, ou saisis l'IP de l'hôte puis Rejoindre."
	elif NetworkManager.is_host():
		_status.text = "HÔTE — %d invité(s) connecté(s). Descends sur une planète : tes invités te suivent." % NetworkManager.peers().size()
	else:
		_status.text = "Connecté à l'hôte. Tu le rejoins dès qu'il est sur une surface."
	var active: bool = NetworkManager.is_active()
	_host_btn.disabled = active
	_join_btn.disabled = active
	_leave_btn.disabled = not active
