extends Node3D
## Indicateur directionnel de dégâts (VR + bureau) : flèche rouge tête-bloquée à la périphérie du champ de
## vision, pointant vers la PROVENANCE du dernier tir encaissé (tourne-toi vers elle pour parer/riposter).
## S'estompe vite. top_level => suit la caméra. Piloté chaque frame par PlayerController.place(). AUTO-CONTENU.

const RING := 0.22    # décalage du marqueur autour du centre (repère caméra)
const FWD := 0.5      # distance devant la caméra (m)

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D

func _ready() -> void:
	top_level = true
	_mesh = MeshInstance3D.new()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.mesh = _arrow_mesh()
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.no_depth_test = true
	_mat.albedo_color = Color(1.0, 0.2, 0.15, 0.0)
	_mesh.material_override = _mat
	add_child(_mesh)
	visible = false

# dir = direction MONDE d'où vient le tir (vers le tireur). t = intensité 0..1 (gérée par le joueur).
func place(cam: Camera3D, dir: Vector3, t: float) -> void:
	if t <= 0.01 or cam == null or dir.length() < 0.001:
		if visible:
			visible = false
		return
	visible = true
	var b := cam.global_transform.basis
	var local := b.inverse() * dir.normalized()   # menace en repère caméra
	var az := atan2(local.x, -local.z)             # 0 = devant, + = droite, ±π = derrière
	var lp := Vector3(sin(az) * RING, cos(az) * RING, -FWD)
	# Place le marqueur à la périphérie et l'oriente vers l'extérieur (pointe vers la menace).
	global_transform = Transform3D(b * Basis(Vector3(0.0, 0.0, 1.0), -az), cam.global_position + b * lp)
	_mat.albedo_color = Color(1.0, 0.2, 0.15, clampf(t, 0.0, 1.0) * 0.9)

func clear() -> void:
	if visible:
		visible = false

# Triangle plein pointant vers +Y (= vers l'extérieur après rotation azimutale).
func _arrow_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.add_vertex(Vector3(0.0, 0.075, 0.0))    # pointe
	st.add_vertex(Vector3(-0.045, 0.0, 0.0))
	st.add_vertex(Vector3(0.045, 0.0, 0.0))
	return st.commit()
