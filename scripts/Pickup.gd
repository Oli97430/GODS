extends Node3D
## LOOT de combat : un drone abattu lâche (avec une chance) une AMÉLIORATION ramassable. Le butin DESCEND en
## douceur jusqu'au-dessus du sol (raycast vers le bas chaque frame => robuste au terrain qui se charge / au
## rebase d'origine flottante), FLOTTE en tournant + brille (cristal + faisceau visible de loin), puis se fait
## ATTIRER vers le joueur à courte distance (aimant) et se RAMASSE par proximité. Couleur = type d'amélioration.
## AUTO-CONTENU. Spawné + nettoyé par WaveManager (enfant => le loot du run disparaît à la fin du combat).

# Types d'amélioration (int partagé avec WaveManager._roll_pickup_kind et PlayerController.apply_pickup).
const KIND_HEAL := 0      # +vie
const KIND_DAMAGE := 1    # dégâts ×
const KIND_RAPID := 2     # cadence de tir ×
const KIND_SHIELD := 3    # bouclier (PV en sus)

const HOVER := 0.7            # m : hauteur de flottaison au-dessus du sol
const BOB_AMP := 0.20         # m : amplitude du ballotement vertical
const BOB_SPEED := 2.2
const SPIN_SPEED := 1.4       # rad/s : rotation sur place
const SETTLE_LERP := 4.0      # vitesse de descente/lissage vers la hauteur cible
const FALL_NOGROUND := 6.0    # m/s : descente si aucun sol trouvé (rare)
const COLLECT_RADIUS := 1.4   # m : ramassage (distance 3D au joueur)
const MAGNET_RADIUS := 3.2    # m : attraction douce vers le joueur
const MAGNET_SPEED := 6.0     # m/s
const LIFETIME := 30.0        # s avant disparition (fondu sur la dernière seconde)

var _player: Node3D
var _kind := KIND_HEAL
var _col := Color(0.3, 1.0, 0.45)
var _t := 0.0
var _life := 0.0
var _pending := Vector3.ZERO
var _core_mat: StandardMaterial3D
var _light: OmniLight3D
var _collected := false
var net_id := 0       # coop : id réseau (assigné par CoopCombat côté hôte ; 0 = solo)
var remote := false   # coop : true = GHOST (invité) — visuel seul, position pilotée par CoopCombat

# Couleur par type (statique => réutilisable pour le feedback côté joueur).
static func kind_color(kind: int) -> Color:
	match kind:
		KIND_DAMAGE: return Color(1.0, 0.4, 0.2)    # rouge-orange
		KIND_RAPID: return Color(1.0, 0.9, 0.25)    # jaune
		KIND_SHIELD: return Color(0.35, 0.8, 1.0)   # cyan
		_: return Color(0.3, 1.0, 0.45)             # vert (soin)

# À appeler AVANT add_child : joueur (cible/aimant), type, position monde du drone abattu.
func setup(player: Node3D, kind: int, world_pos: Vector3) -> void:
	_player = player
	_kind = kind
	_pending = world_pos
	_col = kind_color(kind)

func _ready() -> void:
	global_position = _pending
	# Cristal lumineux additif (couleur = type).
	var core := MeshInstance3D.new()
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gm := SphereMesh.new()
	gm.radius = 0.16
	gm.height = 0.32
	gm.radial_segments = 8
	gm.rings = 4
	core.mesh = gm
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_core_mat.albedo_color = Color(_col.r, _col.g, _col.b, 0.9)
	core.material_override = _core_mat
	add_child(core)
	# Faisceau vertical (repère visible de loin).
	var beam := MeshInstance3D.new()
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.06
	cyl.height = 6.0
	cyl.radial_segments = 8
	beam.mesh = cyl
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bmat.albedo_color = Color(_col.r, _col.g, _col.b, 0.10)
	beam.material_override = bmat
	beam.position = Vector3(0.0, 3.0, 0.0)
	add_child(beam)
	# Lumière douce (lisibilité de nuit).
	_light = OmniLight3D.new()
	_light.light_color = _col
	_light.omni_range = 4.5
	_light.light_energy = 2.4
	_light.shadow_enabled = false
	add_child(_light)

func _process(delta: float) -> void:
	if _collected:
		return
	_t += delta
	_life += delta
	if _life >= LIFETIME:
		if not remote and net_id != 0 and NetworkManager.is_active() and NetworkManager.is_host():
			CoopCombat.host_remove_pickup(net_id)   # coop : retire le ghost partout
		queue_free()
		return
	# Coop : GHOST (invité) = visuel seul, position pilotée par CoopCombat (sync planète->rendu).
	if remote:
		rotate_y(SPIN_SPEED * delta)
		_update_fade()
		return
	var gp := global_position
	# Hauteur : descend/flotte au-dessus du sol trouvé par raycast (robuste terrain/rebase).
	var ground := _find_ground(gp)
	if ground != INF:
		var target_y := ground + HOVER + (sin(_t * BOB_SPEED) * 0.5 + 0.5) * BOB_AMP
		gp.y = lerpf(gp.y, target_y, clampf(SETTLE_LERP * delta, 0.0, 1.0))
	else:
		gp.y -= FALL_NOGROUND * delta
	# Cible aimant/ramassage : solo = _player ; coop HÔTE = joueur le plus proche (hôte OU invité, autorité).
	if NetworkManager.is_active() and NetworkManager.is_host():
		var n: Dictionary = CoopCombat.coop_nearest_player(gp)
		if n.get("has", false):
			if float(n.dist) <= COLLECT_RADIUS:
				global_position = gp
				_collect_coop(bool(n.is_host), int(n.id))
				return
			if float(n.dist) <= MAGNET_RADIUS:
				gp = _magnet_toward(gp, n.pos, delta)
	elif _player != null and is_instance_valid(_player):
		var dist := _player.global_position.distance_to(gp)
		if dist <= COLLECT_RADIUS:
			global_position = gp
			_collect()
			return
		if dist <= MAGNET_RADIUS:
			gp = _magnet_toward(gp, _player.global_position, delta)
	global_position = gp
	rotate_y(SPIN_SPEED * delta)
	_update_fade()

func _magnet_toward(gp: Vector3, target: Vector3, delta: float) -> Vector3:
	var flat := Vector2(target.x - gp.x, target.z - gp.z)
	if flat.length() > 0.01:
		var mv := flat.normalized() * MAGNET_SPEED * delta
		gp.x += mv.x
		gp.z += mv.y
	return gp

func _update_fade() -> void:
	var fade := clampf(LIFETIME - _life, 0.0, 1.0)
	if _core_mat:
		var pulse := 0.7 + 0.3 * sin(_t * 4.0)
		_core_mat.albedo_color = Color(_col.r, _col.g, _col.b, 0.9 * fade * pulse)
	if _light:
		_light.light_energy = 2.4 * fade

# Raycast court vers le bas pour trouver le sol sous le butin. INF si rien (terrain pas encore chargé).
func _find_ground(from_pos: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return INF
	var from := from_pos + Vector3.UP * 2.0
	var to := from_pos + Vector3.DOWN * 40.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var h := space.intersect_ray(q)
	if h.is_empty():
		return INF
	return h.position.y

func _collect() -> void:
	if _collected:
		return
	_collected = true
	_spawn_collect_flash()
	if _player != null and _player.has_method("apply_pickup"):
		_player.apply_pickup(_kind)
	queue_free()

# Coop (hôte) : ramassé par le joueur le plus proche => CoopCombat applique le bonus au bon joueur + retire partout.
func _collect_coop(is_host: bool, id: int) -> void:
	if _collected:
		return
	_collected = true
	_spawn_collect_flash()
	CoopCombat.host_award_pickup(net_id, is_host, id, _kind)
	queue_free()

func _spawn_collect_flash() -> void:
	# Flash de ramassage (bref, couleur du type).
	var fl := OmniLight3D.new()
	fl.light_color = _col
	fl.omni_range = 4.0
	fl.light_energy = 7.0
	fl.shadow_enabled = false
	get_parent().add_child(fl)
	fl.global_position = global_position
	get_tree().create_timer(0.12).timeout.connect(fl.queue_free)
