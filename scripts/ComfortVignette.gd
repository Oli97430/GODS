extends MeshInstance3D
## Vignette de CONFORT VR : sphère inversée tête-bloquée, transparente dans un cône avant, sombre autour ;
## le cône se resserre avec la vitesse => tunnel-vision anti-nausée (vection). Marche bureau ET casque.
## Pilotée chaque frame par PlayerController.place(cam, amount, delta). top_level => suit la caméra.

var _amount := 0.0
var _mat: ShaderMaterial

func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sph := SphereMesh.new()
	sph.radius = 2.0
	sph.height = 4.0
	sph.radial_segments = 24
	sph.rings = 12
	mesh = sph
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/vignette.gdshader")
	material_override = _mat
	visible = false

# amount cible 0..1 (piloté par la vitesse). Lissage temporel pour éviter tout flash brusque.
func place(cam: Camera3D, amount: float, delta: float) -> void:
	_amount = move_toward(_amount, clampf(amount, 0.0, 1.0), delta * 2.5)
	if _amount < 0.01 or cam == null:
		visible = false
		return
	visible = true
	global_transform = Transform3D(cam.global_transform.basis, cam.global_position)
	_mat.set_shader_parameter("amount", _amount)

# Coupe net (appelé quand on quitte la surface — sinon la vignette resterait figée à l'écran).
func clear() -> void:
	_amount = 0.0
	visible = false
