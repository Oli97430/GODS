class_name OptionsUI
extends Object
## Constructeur PARTAGÉ des contrôles d'options — utilisé par OptionsMenu (overlay BUREAU) ET
## OptionsPanelXR (panneau worldspace CASQUE). 100% STATIC, branché directement sur l'autoload Settings
## (aucun état d'instance). Le CONTENEUR fournit le cadre (panneau/titre/TabContainer/pied) puis appelle
## build_tabs(tabs) : un nouveau réglage ajouté ICI apparaît AUTOMATIQUEMENT au bureau ET au casque.

# Ajoute les 4 onglets câblés sur Settings ; renvoie le Label d'état du gilet (à rafraîchir à l'ouverture).
static func build_tabs(tabs: TabContainer) -> Label:
	_build_graphics(_tab(tabs, "Graphismes"))
	_build_comfort(_tab(tabs, "Confort"))
	_build_audio(_tab(tabs, "Audio"))
	return _build_haptics(_tab(tabs, "Haptique"))

static func status_text() -> String:
	if BHaptics.is_player_connected():
		return "Gilet X40 : CONNECTÉ ✓"
	return "Gilet X40 : non détecté — lance le bHaptics Player"

# Un SEUL handler générique : Settings.set + apply ciblé + save. Sans état => statique, lié via .bind().
static func _on_value(value: Variant, field: String, category: String) -> void:
	Settings.set(field, value)
	match category:
		"graphics": Settings.apply_graphics()
		"window": Settings.apply_window()
		"audio": Settings.apply_audio()
		"haptics": Settings.apply_haptics()
		"fx": Settings.apply_fx()
	Settings.save_settings()

# --- Onglets ---

static func _tab(tabs: TabContainer, tab_name: String) -> VBoxContainer:
	var mc := MarginContainer.new()
	mc.name = tab_name
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(m, 16)
	tabs.add_child(mc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	mc.add_child(v)
	return v

static func _build_graphics(v: VBoxContainer) -> void:
	_slider(v, "Échelle de rendu", 0.5, 1.5, 0.05, Settings.render_scale, _pct, "render_scale", "graphics")
	_option(v, "Anticrénelage (MSAA)", Settings.MSAA_LABELS, Settings.msaa_index, "msaa_index", "graphics")
	_option(v, "Mode fenêtre", Settings.WINDOW_LABELS, Settings.window_mode, "window_mode", "window")
	var res_labels := []
	for r in Settings.RESOLUTIONS:
		res_labels.append("%d × %d" % [r.x, r.y])
	_option(v, "Résolution (fenêtré)", res_labels, Settings.resolution_index, "resolution_index", "window")
	_option(v, "Images/s max", Settings.FPS_LABELS, Settings.fps_index, "fps_index", "graphics")
	_check(v, "V-Sync", Settings.vsync, "vsync", "graphics")
	_check(v, "Glow / bloom", Settings.fx_glow, "fx_glow", "fx")
	_check(v, "Occlusion ambiante (SSAO)", Settings.fx_ssao, "fx_ssao", "fx")
	_check(v, "Lumière indirecte (SSIL)", Settings.fx_ssil, "fx_ssil", "fx")

static func _build_comfort(v: VBoxContainer) -> void:
	_check(v, "Vignette de confort", Settings.vignette_on, "vignette_on", "comfort")
	_slider(v, "Intensité vignette", 0.0, 1.0, 0.05, Settings.vignette_strength, _pct, "vignette_strength", "comfort")
	_option(v, "Rotation (XR)", ["Par cran (snap)", "Continue (smooth)"], Settings.turn_mode, "turn_mode", "comfort")
	_slider(v, "Angle de snap", 15.0, 45.0, 5.0, Settings.snap_angle, _deg, "snap_angle", "comfort")
	var hint := Label.new()
	hint.text = "La vignette réduit le flux périphérique pendant le vol/glisse rapides (anti-mal des transports). Le snap-turn tourne par crans (plus confortable au casque)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.6)
	v.add_child(hint)

static func _build_audio(v: VBoxContainer) -> void:
	_slider(v, "Volume général", 0.0, 1.0, 0.01, Settings.vol_master, _pct, "vol_master", "audio")
	_slider(v, "Ambiance / météo", 0.0, 1.0, 0.01, Settings.vol_ambient, _pct, "vol_ambient", "audio")
	_slider(v, "Effets (SFX)", 0.0, 1.0, 0.01, Settings.vol_sfx, _pct, "vol_sfx", "audio")

static func _build_haptics(v: VBoxContainer) -> Label:
	var status := Label.new()
	status.text = status_text()
	v.add_child(status)
	_check(v, "Gilet activé", Settings.haptics_enabled, "haptics_enabled", "haptics")
	_slider(v, "Intensité gilet", 0.0, 1.5, 0.05, Settings.haptics_intensity, _pct, "haptics_intensity", "haptics")
	var hint := Label.new()
	hint.text = "Le gilet vibre aussi en mode bureau (atterrissage, vol, pluie, transitions d'échelle…)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.6)
	v.add_child(hint)
	return status

# --- Formatteurs de valeur ---

static func _pct(x: float) -> String:
	return "%d%%" % round(x * 100.0)

static func _deg(x: float) -> String:
	return "%d°" % int(round(x))

# --- Helpers de ligne (un contrôle + son label) ---

static func _slider(box: VBoxContainer, label: String, lo: float, hi: float, step: float, val: float, vfmt: Callable, field: String, category: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 210
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size.x = 260
	row.add_child(s)
	var vl := Label.new()
	vl.custom_minimum_size.x = 64
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vl.text = vfmt.call(val)
	row.add_child(vl)
	s.value_changed.connect(func(x): vl.text = vfmt.call(x))
	s.value_changed.connect(_on_value.bind(field, category))
	box.add_child(row)

static func _option(box: VBoxContainer, label: String, items: Array, sel: int, field: String, category: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 210
	row.add_child(l)
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.selected = clampi(sel, 0, items.size() - 1)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(o)
	o.item_selected.connect(_on_value.bind(field, category))
	box.add_child(row)

static func _check(box: VBoxContainer, label: String, val: bool, field: String, category: String) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 210
	row.add_child(l)
	var c := CheckButton.new()
	c.button_pressed = val
	row.add_child(c)
	c.toggled.connect(_on_value.bind(field, category))
	box.add_child(row)
