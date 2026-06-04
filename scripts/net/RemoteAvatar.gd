extends Node3D
## Avatar d'un joueur DISTANT (coop) : MODÈLE GLB (corps) posé DEBOUT à la position de tête synchronisée +
## arme tenue. `head`/`lhand`/`rhand`/`weapon` restent l'interface pilotée par CoopSync (global_transform en
## espace-rendu, anti-rebase) ; `head` est une ANCRE invisible, le corps la suit (position + lacet, JAMAIS le
## tangage/roulis => le corps reste droit même quand le partenaire regarde en l'air). AUTO-CONTENU.

const AVATAR_MODEL_PATH := "res://models/calibur_vgdc.glb"
const TARGET_HEIGHT := 1.75    # m : hauteur visée du modèle (auto-échelle quelle que soit la taille du GLB)
const MODEL_EULER_DEG := Vector3(0.0, 180.0, 0.0)   # correction d'orientation du modèle (repère LOCAL, degrés) — réglable

var head: MeshInstance3D       # ANCRE invisible (pilotée par CoopSync) — donne position + orientation de la tête
var lhand: MeshInstance3D
var rhand: MeshInstance3D
var weapon: MeshInstance3D
var _body: Node3D              # le modèle GLB, top_level, repositionné chaque frame d'après `head`
var _body_scale := 1.0
var _head_top := TARGET_HEIGHT # distance origine-du-modèle -> sommet de la tête (après échelle), pour aligner
var _weapon_id := -2

func _ready() -> void:
	head = _make(_capsule(0.12, 0.30), Color(0.55, 0.68, 0.95))
	lhand = _make(_sphere(0.05), Color(0.85, 0.74, 0.62))
	rhand = _make(_sphere(0.05), Color(0.85, 0.74, 0.62))
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.06, 0.26)
	weapon = _make(bm, Color(0.4, 0.7, 1.0))
	weapon.visible = false
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

# Auto-échelle : mesure l'AABB combinée du modèle (à l'échelle 1) et la ramène à TARGET_HEIGHT.
func _fit_body() -> void:
	var aabb := _model_aabb()
	var h: float = maxf(aabb.size.y, 0.001)
	_body_scale = TARGET_HEIGHT / h
	_head_top = (aabb.position.y + aabb.size.y) * _body_scale   # sommet (tête) au-dessus de l'origine, à l'échelle

func _model_aabb() -> AABB:
	var out := AABB()
	var first := true
	for n in _descendants(_body):
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var wa: AABB = (n as MeshInstance3D).global_transform * (n as MeshInstance3D).get_aabb()
			if first:
				out = wa
				first = false
			else:
				out = out.merge(wa)
	if first:
		out = AABB(Vector3(-0.3, 0.0, -0.3), Vector3(0.6, TARGET_HEIGHT, 0.6))   # repli si pas de mesh trouvé
	return out

func _descendants(n: Node) -> Array:
	var o := [n]
	for c in n.get_children():
		o += _descendants(c)
	return o

func _process(_dt: float) -> void:
	if _body == null or not is_instance_valid(_body):
		return
	var ht := head.global_transform
	# Lacet uniquement : le corps reste vertical (l'avatar ne se couche pas quand le partenaire regarde en l'air).
	var fwd := -ht.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var b := Basis.looking_at(fwd, Vector3.UP)   # debout, -Z orienté vers fwd
	b = b * Basis.from_euler(Vector3(deg_to_rad(MODEL_EULER_DEG.x), deg_to_rad(MODEL_EULER_DEG.y), deg_to_rad(MODEL_EULER_DEG.z)))   # correction d'axe du modèle
	# La TÊTE du modèle (origine + _head_top) doit coïncider avec la position de tête trackée => on descend l'origine.
	var origin := ht.origin - Vector3.UP * _head_top
	_body.global_transform = Transform3D(b.scaled(Vector3.ONE * _body_scale), origin)

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

# Le modèle a ses propres mains => seules l'arme tenue (re)devient visible selon l'état combat de l'autre joueur.
func set_hands_visible(v: bool) -> void:
	if _body == null:                 # repli capsule : on montre aussi les mains-sphères
		lhand.visible = v
		rhand.visible = v
	weapon.visible = v and _weapon_id >= 0

func set_weapon(id: int) -> void:
	if id == _weapon_id:
		return
	_weapon_id = id
	weapon.visible = id >= 0
	if id >= 0:
		var cols := [Color(0.4, 0.9, 1.0), Color(0.45, 1.0, 0.55), Color(1.0, 0.6, 0.15)]   # revolver / plasma / grenade
		(weapon.material_override as StandardMaterial3D).albedo_color = cols[clampi(id, 0, 2)]
