extends MeshInstance3D
## Surcouche COMBAT tête-bloquée (VR + bureau) : sphère inversée teintée rouge autour de la tête.
## • Bref FLASH rouge vif à l'encaissement d'un tir. • Assombrissement rouge SOUTENU à la mort.
## • Voile rouge LÉGER et permanent quand les PV sont bas (sans chiffres => lisible au casque).
## top_level => suit la caméra active. Pilotée chaque frame par PlayerController.place(). AUTO-CONTENU.

var _mat: StandardMaterial3D
var _hurt := 0.0   # flash d'encaissement lissé (0..1)
var _dead := 0.0   # voile de mort lissé (0..1)
var _low := 0.0    # alerte PV bas lissée (0..1)
var _heal := 0.0   # pulse de soin lissé (0..1, vert)

func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sph := SphereMesh.new()
	sph.radius = 1.5
	sph.height = 3.0
	sph.radial_segments = 16
	sph.rings = 8
	sph.flip_faces = true   # normales vers l'intérieur => on voit la face interne depuis la tête
	mesh = sph
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.no_depth_test = true        # toujours par-dessus la scène
	_mat.disable_receive_shadows = true
	_mat.albedo_color = Color(0.7, 0.0, 0.0, 0.0)
	material_override = _mat
	visible = false

# Pilotage par PlayerController : hurt/dead/low/heal en cibles 0..1 (lissées). cam = caméra active.
func place(cam: Camera3D, hurt: float, dead: float, low: float, heal: float, delta: float) -> void:
	_hurt = move_toward(_hurt, clampf(hurt, 0.0, 1.0), delta * 4.5)
	_dead = move_toward(_dead, clampf(dead, 0.0, 1.0), delta * 2.5)
	_low = move_toward(_low, clampf(low, 0.0, 1.0), delta * 2.0)
	_heal = move_toward(_heal, clampf(heal, 0.0, 1.0), delta * 3.0)
	var a_red: float = maxf(maxf(_hurt * 0.38, _dead * 0.62), _low * 0.20)
	var a_green := _heal * 0.30
	var a: float
	var col: Color
	if a_green > a_red:
		a = a_green
		col = Color(0.15, 0.85, 0.35)   # soin : vert
	else:
		a = a_red
		col = Color(0.85, 0.06, 0.05).lerp(Color(0.22, 0.0, 0.0), _dead)   # rouge → rouge sombre à la mort
	if a < 0.01 or cam == null:
		if visible:
			visible = false
		return
	visible = true
	global_transform = Transform3D(cam.global_transform.basis, cam.global_position)
	_mat.albedo_color = Color(col.r, col.g, col.b, a)

# Coupe net (sortie de surface / désarmement) — sinon le voile resterait figé.
func clear() -> void:
	_hurt = 0.0
	_dead = 0.0
	_low = 0.0
	_heal = 0.0
	visible = false
