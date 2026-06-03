extends Node3D
## Lecture COMBAT tête-bloquée (VR) : « VAGUE N · PV · Score » flottant en bas du champ de vision, TOUJOURS
## visible tant qu'une arme est équipée. Complète le HUD plat (bureau, masqué en XR) qui, lui, n'apparaît pas
## dans le casque. top_level => suit la caméra active. Pilotée chaque frame par PlayerController.place(). AUTO-CONTENU.

var _label: Label3D

func _ready() -> void:
	top_level = true
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED   # fait toujours face au joueur
	_label.no_depth_test = true                            # par-dessus la scène
	_label.fixed_size = true                               # taille écran constante
	_label.pixel_size = 0.0008
	_label.font_size = 56
	_label.outline_size = 14
	_label.modulate = Color(1.0, 0.86, 0.45)
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	_label.position = Vector3(0.0, -0.30, -1.0)            # bas-centre, ~1 m devant la tête
	add_child(_label)
	visible = false

# Piloté par PlayerController : active = afficher, text = contenu. cam = caméra active (tête-bloquée).
func place(cam: Camera3D, active: bool, text: String) -> void:
	if not active or cam == null:
		if visible:
			visible = false
		return
	visible = true
	global_transform = Transform3D(cam.global_transform.basis, cam.global_position)
	if _label.text != text:
		_label.text = text

func clear() -> void:
	if visible:
		visible = false
