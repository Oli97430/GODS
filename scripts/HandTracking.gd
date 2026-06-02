class_name HandTracking
extends Node3D
## Accès au hand tracking OpenXR (extension activée dans project.godot). Expose la
## disponibilité par main + les transforms de joints en ESPACE MONDE, et un pointeur
## d'index droit unifié. Node enfant de XROrigin3D AVEC transform local identité : son
## global_transform == celui de l'origine XR, et les poses XRHandTracker étant exprimées
## en espace de suivi (relatif à l'origine), monde = global_transform * pose_joint.
##
## Fallback : si le runtime ne fournit pas de hand tracking (manettes, pas de casque),
## les trackers sont absents => is_active() = false et les appelants gardent les manettes.

enum Hand { LEFT, RIGHT }

var _left: XRHandTracker
var _right: XRHandTracker

func _ready() -> void:
	_acquire_trackers()

# Récupère les trackers de main (peuvent apparaître après le démarrage du runtime).
func _acquire_trackers() -> void:
	_left = XRServer.get_tracker("/user/hand_tracker/left") as XRHandTracker
	_right = XRServer.get_tracker("/user/hand_tracker/right") as XRHandTracker

func _tracker(hand: int) -> XRHandTracker:
	var t: XRHandTracker = _right if hand == Hand.RIGHT else _left
	if t == null:
		_acquire_trackers()   # ré-essai : trackers enregistrés après coup
		t = _right if hand == Hand.RIGHT else _left
	return t

# Vrai si la main donnée est actuellement suivie (données valides ce frame).
func is_hand_active(hand: int) -> bool:
	var t := _tracker(hand)
	return t != null and t.has_tracking_data

# Vrai si AU MOINS une main est suivie (=> on bascule en mode mains).
func is_active() -> bool:
	return is_hand_active(Hand.LEFT) or is_hand_active(Hand.RIGHT)

# Transform MONDE d'un joint (Transform3D() si la main n'est pas suivie).
func joint_world(hand: int, joint: int) -> Transform3D:
	var t := _tracker(hand)
	if t == null or not t.has_tracking_data:
		return Transform3D()
	return global_transform * t.get_hand_joint_transform(joint)

# Rayon (mètres) d'un joint, pour dimensionner les sphères de visualisation.
func joint_radius(hand: int, joint: int) -> float:
	var t := _tracker(hand)
	return t.get_hand_joint_radius(joint) if t != null else 0.0

func right_index_tip_transform() -> Transform3D:
	return joint_world(Hand.RIGHT, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP)

func left_wrist_transform() -> Transform3D:
	return joint_world(Hand.LEFT, XRHandTracker.HAND_JOINT_WRIST)

# Pointeur d'index droit (monde) : origine = pointe du doigt, direction = le long du doigt
# (proximale -> pointe). { valid:false } si la main droite n'est pas suivie => fallback manette.
func right_index_pointer() -> Dictionary:
	if not is_hand_active(Hand.RIGHT):
		return {"valid": false}
	var tip := joint_world(Hand.RIGHT, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP).origin
	var prox := joint_world(Hand.RIGHT, XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL).origin
	var dir := (tip - prox)
	if dir.length() < 0.001:
		return {"valid": false}
	return {"valid": true, "origin": tip, "dir": dir.normalized()}
