extends Node3D
## Lunette VR — ZOOM OPTIQUE RÉEL pour le plasma. Le FOV d'une XRCamera3D est IGNORÉ par le runtime OpenXR
## (la projection vient du casque), donc on ne peut pas « zoomer » la vue principale. Solution : rendre la
## scène une 2e fois via un SubViewport doté de SA PROPRE Camera3D à FOV étroit (= grossissement), affiché sur
## un quad « verre » monté sur l'arme (shaders/scope_lens.gdshader : masque rond + réticule + tube).
##
## PERF (raison du report initial) : le 2e rendu ne tourne QUE pendant la visée (grip), en BASSE résolution.
## Hors visée => render_target_update_mode = DISABLED (le SubViewport ne re-rend pas => coût ~nul). XR seulement
## (le bureau garde son zoom de FOV caméra). No-op gracieux si la lunette n'est pas active.

const SCOPE_RES := 320           # px : résolution (mono) du rendu lunette — basse => peu coûteuse
const SCOPE_FOV := 17.0          # ° : FOV étroit du rendu (~2.6× vs ~45°) => grossissement
const LENS_SIZE := 0.040         # m : diamètre du verre (quad)

var _sub: SubViewport
var _cam: Camera3D
var _lens: MeshInstance3D
var _lens_mat: ShaderMaterial
var _active := false

# À appeler APRÈS add_child (le SubViewport doit être dans l'arbre pour fournir sa texture). world = World3D de
# la scène (rendu de la VRAIE scène) ; tint = couleur du réticule (= couleur du projectile de l'arme).
func setup(world: World3D, tint: Color) -> void:
	_sub = SubViewport.new()
	_sub.size = Vector2i(SCOPE_RES, SCOPE_RES)
	_sub.world_3d = world                       # PARTAGE le monde de la scène => rend la vraie scène
	_sub.own_world_3d = false
	_sub.transparent_bg = false
	_sub.msaa_3d = Viewport.MSAA_DISABLED        # cheap
	_sub.positional_shadow_atlas_size = 0
	_sub.render_target_update_mode = SubViewport.UPDATE_DISABLED   # rien tant que pas en visée
	add_child(_sub)
	# Caméra du rendu lunette : FOV étroit ; top_level => transform pilotée librement chaque frame.
	_cam = Camera3D.new()
	_cam.fov = SCOPE_FOV
	_cam.top_level = true
	_cam.current = true
	_cam.near = 0.05
	_cam.far = 800.0
	_sub.add_child(_cam)
	# Verre = quad (normale +Z local = vers l'arrière de l'arme = vers l'œil) texturé par le rendu lunette.
	_lens = MeshInstance3D.new()
	_lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var qm := QuadMesh.new()
	qm.size = Vector2(LENS_SIZE, LENS_SIZE)
	_lens.mesh = qm
	_lens_mat = ShaderMaterial.new()
	_lens_mat.shader = load("res://shaders/scope_lens.gdshader")
	_lens_mat.set_shader_parameter("scope_tex", _sub.get_texture())
	_lens_mat.set_shader_parameter("reticle_color", Color(tint.r, tint.g, tint.b, 1.0))
	_lens.material_override = _lens_mat
	add_child(_lens)
	set_active(false)

# Active/désactive le RENDU (perf) + la visibilité du verre.
func set_active(on: bool) -> void:
	_active = on
	if _sub:
		_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if _lens:
		_lens.visible = on

func is_active() -> bool:
	return _active

# Place la caméra lunette le long de l'axe de visée. origin = bouche, dir = -muzzle.z (avant), up = muzzle.y
# (roulis de l'arme => l'image de la lunette tourne avec le fusil, naturel). No-op si inactive.
func update_view(origin: Vector3, dir: Vector3, up: Vector3) -> void:
	if not _active or _cam == null or dir.length() < 0.001:
		return
	var u := up
	if u.length() < 0.001 or absf(dir.normalized().dot(u.normalized())) > 0.99:
		u = Vector3.UP
	_cam.global_transform = Transform3D(Basis.IDENTITY, origin).looking_at(origin + dir, u)
