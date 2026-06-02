class_name HandVisualizer
extends Node3D
## Visualisation des mains 100% PAR CODE (aucun modèle importé) : une sphère par joint
## OpenXR + un cylindre par "os" (joints connectés), positionnés en espace MONDE depuis
## HandTracking. Masque le visuel des manettes (rayon de visée) quand les mains sont
## actives, et inversement (fallback manettes). Enfant de XROrigin3D.

@export var hand_tracking_path: NodePath
@export var aim_ray_path: NodePath        # visuel manette droite (rayon) à masquer en mode mains

const JOINT_COUNT := 26                    # = XRHandTracker.HAND_JOINT_MAX
# Os = paires de joints connectés (poignet -> métacarpiens, puis 5 doigts).
const BONES := [
	[1, 2], [1, 6], [1, 11], [1, 16], [1, 21],   # poignet -> métacarpiens (paume)
	[2, 3], [3, 4], [4, 5],                        # pouce
	[6, 7], [7, 8], [8, 9], [9, 10],               # index
	[11, 12], [12, 13], [13, 14], [14, 15],        # majeur
	[16, 17], [17, 18], [18, 19], [19, 20],        # annulaire
	[21, 22], [22, 23], [23, 24], [24, 25],        # auriculaire
]
const BONE_RADIUS := 0.007

var _ht: HandTracking
var _aim_ray: Node3D
var _joint_mi := {}    # hand -> Array[MeshInstance3D] (sphères)
var _bone_mi := {}     # hand -> Array[MeshInstance3D] (cylindres)
var _ctrl_hand := {}   # hand -> Node3D : main procédurale attachée à la manette (fallback sans hand-tracking)
var _sphere_mesh: SphereMesh
var _bone_mesh: CylinderMesh
var _mat: StandardMaterial3D

func _ready() -> void:
	_ht = get_node_or_null(hand_tracking_path)
	_aim_ray = get_node_or_null(aim_ray_path)

	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.72, 0.85, 1.0)
	_mat.roughness = 0.6
	_mat.emission_enabled = true                  # légère émission : mains visibles dans l'espace sombre
	_mat.emission = Color(0.2, 0.3, 0.45)

	_sphere_mesh = SphereMesh.new()
	_sphere_mesh.radius = 1.0
	_sphere_mesh.height = 2.0
	_sphere_mesh.radial_segments = 8
	_sphere_mesh.rings = 4
	_bone_mesh = CylinderMesh.new()
	_bone_mesh.top_radius = 1.0
	_bone_mesh.bottom_radius = 1.0
	_bone_mesh.height = 1.0                        # centré ; mis à l'échelle (r, longueur, r)
	_bone_mesh.radial_segments = 6

	for hand in [HandTracking.Hand.LEFT, HandTracking.Hand.RIGHT]:
		_build_hand(hand)

	# Mains procédurales attachées aux MANETTES (fallback visible quand le hand-tracking est inactif).
	var lc := get_node_or_null("../LeftController")
	var rc := get_node_or_null("../RightController")
	if lc:
		_ctrl_hand[HandTracking.Hand.LEFT] = _build_controller_hand(lc, true)
	if rc:
		_ctrl_hand[HandTracking.Hand.RIGHT] = _build_controller_hand(rc, false)

func _build_hand(hand: int) -> void:
	var joints: Array[MeshInstance3D] = []
	for j in JOINT_COUNT:
		joints.append(_make_mi(_sphere_mesh))
	_joint_mi[hand] = joints
	var bones: Array[MeshInstance3D] = []
	for b in BONES.size():
		bones.append(_make_mi(_bone_mesh))
	_bone_mi[hand] = bones

func _make_mi(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func _process(_dt: float) -> void:
	if _ht == null:
		return
	var hands := _ht.is_active()
	if _aim_ray:
		_aim_ray.visible = not hands   # manette : rayon visible seulement sans mains
	# Mains-manette visibles en XR uniquement quand le hand-tracking est inactif (fallback manettes).
	var show_ctrl: bool = GameState.xr_active and not hands
	for h in _ctrl_hand:
		_ctrl_hand[h].visible = show_ctrl
	_update_hand(HandTracking.Hand.LEFT)
	_update_hand(HandTracking.Hand.RIGHT)

func _update_hand(hand: int) -> void:
	var joints: Array = _joint_mi[hand]
	var bones: Array = _bone_mi[hand]
	if not _ht.is_hand_active(hand):
		for mi in joints:
			mi.visible = false
		for mi in bones:
			mi.visible = false
		return
	# Sphères aux joints (échelle = rayon du joint).
	for j in JOINT_COUNT:
		var w := _ht.joint_world(hand, j)
		var r := maxf(_ht.joint_radius(hand, j), 0.004)
		var mi: MeshInstance3D = joints[j]
		mi.global_transform = Transform3D(w.basis.scaled(Vector3(r, r, r)), w.origin)
		mi.visible = true
	# Cylindres entre joints connectés.
	for bi in BONES.size():
		var a := _ht.joint_world(hand, BONES[bi][0]).origin
		var b := _ht.joint_world(hand, BONES[bi][1]).origin
		_orient_bone(bones[bi], a, b)

# Oriente/échelle un cylindre unité (axe Y, hauteur 1, rayon 1) pour relier a -> b.
func _orient_bone(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		mi.visible = false
		return
	var up := d / l
	var ref := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := ref.cross(up).normalized()
	var z := x.cross(up).normalized()
	var basis := Basis(x, up, z).scaled(Vector3(BONE_RADIUS, l, BONE_RADIUS))
	mi.global_transform = Transform3D(basis, (a + b) * 0.5)
	mi.visible = true

# Main procédurale simple attachée à une manette (paume + 4 doigts repliés + pouce). 'is_left' = miroir.
# Enfant de la manette => suit sa pose physique. Orientée vers -Z (avant de la manette).
func _build_controller_hand(parent: Node3D, is_left: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "ControllerHand"
	parent.add_child(root)
	var sx := -1.0 if is_left else 1.0
	_hand_box(root, Vector3(0.075, 0.028, 0.10), Vector3(0.0, 0.0, 0.03))          # paume
	for i in 4:                                                                     # 4 doigts vers l'avant
		_hand_box(root, Vector3(0.014, 0.015, 0.055), Vector3(-0.027 + i * 0.018, -0.004, -0.045))
	_hand_box(root, Vector3(0.018, 0.016, 0.045), Vector3(sx * 0.045, 0.006, 0.01))  # pouce (côté)
	return root

func _hand_box(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

# Diagnostic : nombre total de MeshInstance3D créés (joints + os, 2 mains).
func mesh_count() -> int:
	return JOINT_COUNT * 2 + BONES.size() * 2
