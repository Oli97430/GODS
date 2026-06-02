extends Node3D
## Splash de démarrage du logo « GODS VR ». Rastérise TitleLogo dans un SubViewport transparent,
## puis l'affiche en FONDU (apparition → maintien → disparition) au lancement, à la fois en BUREAU
## (TextureRect plein écran sur un CanvasLayer) ET au CASQUE (quad non éclairé devant la caméra XR).
## Se libère tout seul à la fin. Aucune dépendance : mode-agnostique (les deux affichages coexistent,
## chacun n'est visible que dans son mode).

const FADE_IN := 0.6
const HOLD := 3.4
const FADE_OUT := 1.6
const VP_SIZE := Vector2i(1024, 512)

var _vp: SubViewport
var _rect: TextureRect            # bureau
var _quad: MeshInstance3D         # casque (enfant de la caméra XR -> libéré explicitement)
var _quad_mat: StandardMaterial3D
var _t := 0.0
var _ready_displays := false

func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = VP_SIZE
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_vp.add_child(preload("res://scripts/TitleLogo.gd").new())

func _process(dt: float) -> void:
	# 1er tick : la caméra XR / xr_active sont prêtes (Main._ready a eu lieu) -> construit l'affichage.
	if not _ready_displays:
		_ready_displays = true
		_build_displays()
		return
	_t += dt
	var a := 1.0
	if _t < FADE_IN:
		a = _t / FADE_IN
	elif _t < FADE_IN + HOLD:
		a = 1.0
	elif _t < FADE_IN + HOLD + FADE_OUT:
		a = 1.0 - (_t - FADE_IN - HOLD) / FADE_OUT
	else:
		if is_instance_valid(_quad):
			_quad.queue_free()
		queue_free()
		return
	if _rect != null:
		_rect.modulate.a = a
	if _quad_mat != null:
		_quad_mat.albedo_color.a = a

func _build_displays() -> void:
	var tex := _vp.get_texture()
	# --- Bureau : TextureRect plein écran centré (gardé proportionnel) ---
	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	_rect = TextureRect.new()
	_rect.texture = tex
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.modulate.a = 0.0
	cl.add_child(_rect)
	# --- Casque : quad non éclairé devant la caméra XR ---
	var cam := get_node_or_null("../XROrigin3D/XRCamera3D")
	if cam != null:
		_quad = MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1.2, 0.6)
		_quad.mesh = qm
		_quad_mat = StandardMaterial3D.new()
		_quad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_quad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_quad_mat.albedo_texture = tex
		_quad_mat.albedo_color = Color(1, 1, 1, 0)
		_quad_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_quad_mat.no_depth_test = true
		_quad.material_override = _quad_mat
		cam.add_child(_quad)
		_quad.position = Vector3(0.0, 0.0, -1.5)
