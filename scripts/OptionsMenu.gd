class_name OptionsMenu
extends CanvasLayer
## Menu Options (overlay BUREAU) : cadre + onglets construits par OptionsUI (builder PARTAGÉ). TAB ouvre/
## ferme (Échap ferme aussi). Bloque l'entrée jeu via GameState.options_open (PAS de pause => sûr en XR).
## Au CASQUE c'est OptionsPanelXR (panneau worldspace) qui réutilise le MÊME OptionsUI — donc tout réglage
## ajouté dans OptionsUI apparaît des deux côtés sans duplication.

var _root: Control
var _status: Label
var _open := false
var _prev_mouse := Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	layer = 128
	_build()
	_root.visible = false

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_TAB:
		_set_open(not _open)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _open:
		_set_open(false)
		get_viewport().set_input_as_handled()

func _set_open(v: bool) -> void:
	_open = v
	_root.visible = v
	GameState.options_open = v
	if v:
		_status.text = OptionsUI.status_text()
		_prev_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = _prev_mouse

# --- Construction UI (cadre bureau ; les onglets viennent d'OptionsUI) ---

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # modal : capte les clics hors panneau
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(700, 600)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 22)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	var title := Label.new()
	title.text = "OPTIONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	col.add_child(title)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(tabs)
	_status = OptionsUI.build_tabs(tabs)   # onglets PARTAGÉS (bureau + casque)

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 10)
	col.add_child(foot)
	var reset := Button.new()
	reset.text = "Réinitialiser"
	reset.pressed.connect(_on_reset)
	foot.add_child(reset)
	var close := Button.new()
	close.text = "Fermer  (Tab)"
	close.pressed.connect(_set_open.bind(false))
	foot.add_child(close)

func _on_reset() -> void:
	Settings.reset_defaults()
	_root.queue_free()
	_build()
	_root.visible = true
