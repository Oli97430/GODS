extends Node3D
## Avatar d'un joueur DISTANT (coop) : MODÈLE GLB (corps) posé DEBOUT à la position de tête synchronisée, avec
## bras qui SUIVENT les mains trackées (IK simple) + ARME RÉELLE tenue + ÉTIQUETTE de nom. `head`/`lhand`/`rhand`/
## `weapon` restent l'interface pilotée par CoopSync (global_transform en espace-rendu, anti-rebase). `head` est une
## ANCRE invisible ; le corps la suit (position + lacet, jamais le tangage => reste droit). AUTO-CONTENU.

const AVATAR_MODEL_PATH := "res://models/calibur_vgdc.glb"
const TARGET_HEIGHT := 1.75    # m : hauteur visée du modèle (auto-échelle quelle que soit la taille du GLB)
const MODEL_EULER_DEG := Vector3(0.0, 180.0, 0.0)   # correction d'orientation du modèle (repère LOCAL, degrés)
# IK des bras : les os du modèle suivent les mains trackées. ⏳ À VALIDER EN COOP (2 casques) ; mettre false pour
# revenir aux bras au repos si la convention d'axe des os ne colle pas (twist).
const ARM_IK := true
const WEAPON_PATHS := {0: "res://models/revolver.glb", 1: "res://models/plasma_gun.glb", 2: "res://models/grenade_launcher.glb"}
const WEAPON_LEN := 0.30       # m : longueur visée du modèle d'arme tenu

var head: MeshInstance3D        # ANCRE invisible (pilotée par CoopSync) — donne position + orientation de la tête
var lhand: MeshInstance3D
var rhand: MeshInstance3D
var weapon: MeshInstance3D      # ANCRE de l'arme (sans mesh) ; les modèles GLB d'arme sont ses enfants
var _body: Node3D               # le modèle GLB, top_level, repositionné chaque frame d'après `head`
var _body_scale := 1.0
var _head_top := TARGET_HEIGHT  # distance origine-du-modèle -> sommet de la tête (après échelle), pour aligner
var _weapon_id := -2
var _hands_on := false          # mains trackées visibles (partenaire armé/tracké)
var peer_id := 0
# Squelette + IK
var _skel: Skeleton3D = null
var _b_upper_l := -1
var _b_upper_r := -1
var _b_hand_l := -1
var _b_hand_r := -1
# Modèles d'arme tenus (chargés paresseusement) + étiquette de nom.
var _wmodels := {}              # id -> Node3D
var _name_tag: Label3D = null
# IK : poses de repos mises en CACHE (constantes => calculées une fois dans _setup_skeleton, jamais par frame).
var _arm_ur := {}       # upper_idx -> pose de repos GLOBALE de l'épaule (Transform3D)
var _arm_pinv := {}     # upper_idx -> inverse de la pose de repos globale du PARENT (Transform3D)
var _rest_pose := {}    # bone_idx -> pose de repos LOCALE (Transform3D)
var _arms_resting := false

func _ready() -> void:
	head = _make(_capsule(0.12, 0.30), Color(0.55, 0.68, 0.95))
	lhand = _make(_sphere(0.05), Color(0.85, 0.74, 0.62))
	rhand = _make(_sphere(0.05), Color(0.85, 0.74, 0.62))
	weapon = MeshInstance3D.new()   # ancre nue (les modèles d'arme s'y attachent)
	weapon.top_level = true
	weapon.visible = false
	add_child(weapon)
	# Corps = modèle GLB chargé À L'EXÉCUTION (le script compile même si l'import n'est pas prêt). Repli capsule sinon.
	var ps: Resource = load(AVATAR_MODEL_PATH) if ResourceLoader.exists(AVATAR_MODEL_PATH) else null
	if ps is PackedScene:
		_body = (ps as PackedScene).instantiate()
		_body.top_level = true
		add_child(_body)
		head.visible = false   # modèle OK => masque la capsule + les sphères-mains (le modèle a tête + mains)
		lhand.visible = false
		rhand.visible = false
		_fit_body()
		_setup_skeleton()
	_make_name_tag()

# Auto-échelle : mesure l'AABB combinée du modèle (helper partagé) et la ramène à TARGET_HEIGHT.
func _fit_body() -> void:
	var r := CombatUtil.scene_aabb(_body, Transform3D.IDENTITY)
	var aabb: AABB = r.box if r.has else AABB(Vector3(-0.3, 0.0, -0.3), Vector3(0.6, TARGET_HEIGHT, 0.6))
	var h: float = maxf(aabb.size.y, 0.001)
	_body_scale = TARGET_HEIGHT / h
	_head_top = (aabb.position.y + aabb.size.y) * _body_scale   # sommet (tête) au-dessus de l'origine, à l'échelle

# Cache le squelette + les indices des os de bras/mains (par PRÉFIXE de nom, robuste aux suffixes type "_09").
func _setup_skeleton() -> void:
	_skel = _find_skel(_body)
	if _skel == null:
		return
	var ap = _find_anim(_body)
	if ap:
		ap.active = false   # coupe une éventuelle anim d'idle qui se battrait avec nos overrides
	for i in _skel.get_bone_count():
		var nm := _skel.get_bone_name(i)
		if nm.begins_with("UpperArm.L"):
			_b_upper_l = i
		elif nm.begins_with("UpperArm.R"):
			_b_upper_r = i
		elif nm.begins_with("Hand.L"):
			_b_hand_l = i
		elif nm.begins_with("Hand.R"):
			_b_hand_r = i

	# Pré-calcule les poses de repos CONSTANTES : épaules globales + inverse parent (aim), repos local (repos).
	for ub in [_b_upper_l, _b_upper_r]:
		if ub >= 0:
			_arm_ur[ub] = _skel.get_bone_global_rest(ub)
			var par := _skel.get_bone_parent(ub)
			_arm_pinv[ub] = (_skel.get_bone_global_rest(par) if par >= 0 else Transform3D.IDENTITY).affine_inverse()
	for bb in [_b_upper_l, _b_upper_r, _b_hand_l, _b_hand_r]:
		if bb >= 0:
			_rest_pose[bb] = _skel.get_bone_rest(bb)

func _find_skel(n: Node):
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r = _find_skel(c)
		if r:
			return r
	return null

func _find_anim(n: Node):
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r = _find_anim(c)
		if r:
			return r
	return null

func _process(_dt: float) -> void:
	if _body == null or not is_instance_valid(_body):
		_update_name_tag()
		return
	var ht := head.global_transform
	# Lacet uniquement : le corps reste vertical (l'avatar ne se couche pas quand le partenaire regarde en l'air).
	var fwd := -ht.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var b := Basis.looking_at(fwd, Vector3.UP)   # debout, -Z orienté vers fwd
	b = b * Basis.from_euler(Vector3(deg_to_rad(MODEL_EULER_DEG.x), deg_to_rad(MODEL_EULER_DEG.y), deg_to_rad(MODEL_EULER_DEG.z)))
	var origin := ht.origin - Vector3.UP * _head_top
	_body.global_transform = Transform3D(b.scaled(Vector3.ONE * _body_scale), origin)
	if ARM_IK and _skel != null:
		_update_arms()
	_update_name_tag()

# --- IK des bras : place les mains (os racine) sur les mains trackées + oriente les hauts de bras vers elles ---
func _update_arms() -> void:
	if not _hands_on:
		if not _arms_resting:   # ne replace les bras au repos qu'UNE fois (transition armé -> désarmé)
			_rest_arm(_b_upper_l)
			_rest_arm(_b_hand_l)
			_rest_arm(_b_upper_r)
			_rest_arm(_b_hand_r)
			_arms_resting = true
		return
	_arms_resting = false
	var inv := _skel.global_transform.affine_inverse()
	_aim_arm(_b_upper_l, _b_hand_l, lhand, inv)
	_aim_arm(_b_upper_r, _b_hand_r, rhand, inv)

func _aim_arm(upper: int, hand_b: int, hand_node: MeshInstance3D, inv: Transform3D) -> void:
	if hand_b < 0 or hand_node == null:
		return
	# Poignet : os RACINE (parent=-1) => pose locale = pose en espace-squelette. Placement EXACT sur la main trackée.
	var hl := inv * hand_node.global_transform
	_skel.set_bone_pose_position(hand_b, hl.origin)
	_skel.set_bone_pose_rotation(hand_b, hl.basis.orthonormalized().get_rotation_quaternion())
	if upper < 0:
		return
	# Haut de bras : +Y (axe long de l'os, convention Blender) pointe vers la main. Poses de repos en CACHE.
	var ur: Transform3D = _arm_ur[upper]
	var dir := hl.origin - ur.origin
	if dir.length() < 0.001:
		return
	dir = dir.normalized()
	var ref := Vector3.RIGHT if absf(dir.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var xv := ref.cross(dir).normalized()
	var zv := xv.cross(dir).normalized()
	var gb := Basis(xv, dir, zv)   # colonne Y = dir
	var loc := (_arm_pinv[upper] as Transform3D) * Transform3D(gb, ur.origin)
	_skel.set_bone_pose_rotation(upper, loc.basis.orthonormalized().get_rotation_quaternion())

func _rest_arm(b: int) -> void:
	if b < 0 or not _rest_pose.has(b):
		return
	var r: Transform3D = _rest_pose[b]
	_skel.set_bone_pose_position(b, r.origin)
	_skel.set_bone_pose_rotation(b, r.basis.get_rotation_quaternion())

# --- Étiquette de nom (Label3D billboard au-dessus de l'avatar) ---
func _make_name_tag() -> void:
	_name_tag = Label3D.new()
	_name_tag.top_level = true
	_name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_tag.no_depth_test = true
	_name_tag.fixed_size = true
	_name_tag.pixel_size = 0.0012
	_name_tag.modulate = Color(0.72, 0.9, 1.0)
	_name_tag.outline_size = 10
	_name_tag.outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	_name_tag.text = _tag_text()
	add_child(_name_tag)

func _tag_text() -> String:
	return "JOUEUR %d" % peer_id if peer_id > 0 else "JOUEUR"

func _update_name_tag() -> void:
	if _name_tag == null:
		return
	if head != null and is_instance_valid(head):
		_name_tag.global_position = head.global_transform.origin + Vector3.UP * 0.32

func set_peer_id(id: int) -> void:
	peer_id = id
	if _name_tag:
		_name_tag.text = _tag_text()

func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	return m

func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 8
	m.rings = 4
	return m

func _make(mesh: Mesh, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.top_level = true   # global_transform piloté directement (espace-rendu)
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.65
	mi.material_override = m
	add_child(mi)
	return mi

# Le modèle a ses propres mains => seule l'arme tenue (re)devient visible selon l'état combat de l'autre joueur.
func set_hands_visible(v: bool) -> void:
	_hands_on = v
	if _body == null:                 # repli capsule : on montre aussi les mains-sphères
		lhand.visible = v
		rhand.visible = v
	weapon.visible = v and _weapon_id >= 0

func set_weapon(id: int) -> void:
	if id == _weapon_id:
		return
	_weapon_id = id
	for k in _wmodels:
		_wmodels[k].visible = false
	if id >= 0:
		var mdl = _ensure_weapon_model(id)
		if mdl:
			mdl.visible = true
	weapon.visible = _hands_on and id >= 0

# Charge + prépare paresseusement le modèle GLB d'arme `id` (barillet +Z dans le GLB => 180° Y vers -Z, auto-échelle).
func _ensure_weapon_model(id: int):
	if _wmodels.has(id):
		return _wmodels[id]
	if not WEAPON_PATHS.has(id):
		return null
	var path: String = WEAPON_PATHS[id]
	if not ResourceLoader.exists(path):
		return null
	var ps = load(path)
	if not (ps is PackedScene):
		return null
	var inst = (ps as PackedScene).instantiate()
	weapon.add_child(inst)
	var r := CombatUtil.scene_aabb(inst, Transform3D.IDENTITY)
	var aabb: AABB = r.box if r.has else AABB(Vector3(-0.1, -0.1, -0.1), Vector3(0.2, 0.2, 0.2))
	var longest: float = maxf(maxf(aabb.size.x, aabb.size.y), aabb.size.z)
	var s := 1.0 if longest < 0.001 else (WEAPON_LEN / longest)
	var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(180.0), 0.0)).scaled(Vector3.ONE * s)
	var center := aabb.position + aabb.size * 0.5
	inst.transform = Transform3D(basis, -(basis * center))   # centré sur l'ancre, orienté, mis à l'échelle
	_wmodels[id] = inst
	return inst
