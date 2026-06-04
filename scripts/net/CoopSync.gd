extends Node
## Coop CP2 — synchro des JOUEURS : tête + 2 mains + arme, publiées/reçues en coordonnées PLANÈTE (positions
## sur la sphère = frame ABSOLU partagé, INDÉPENDANT du rebase d'origine flottante de chaque client) puis
## INTERPOLÉES. Conversion : planète = M⁻¹·rendu (à la publication) ; rendu = M·planète (à l'affichage), où
## M = ChunkManager.root_transform() (l'aplatissement courant, propre à CHAQUE client). Publie ~22 Hz.
## RPC sur l'autoload (même path /root/CoopSync des 2 côtés). ACTIF seulement en session réseau + en SURFACE
## ⇒ INERTE en solo (zéro régression). Autoload : CoopSync.

const SEND_HZ := 22.0
const SEND_INTERVAL := 1.0 / SEND_HZ
const RAVATAR := preload("res://scripts/net/RemoteAvatar.gd")

var _avatars := {}     # peer_id -> RemoteAvatar
var _buf := {}         # peer_id -> {prev, cur, elapsed} (interpolation)
var _send_t := 0.0
# Refs locales (cache, ré-acquises si invalides).
var _surface: Node = null
var _cm: Node = null
var _player: Node = null
var _lc: Node3D = null
var _rc: Node3D = null

func _ready() -> void:
	NetworkManager.peer_joined.connect(_on_peer_joined)
	NetworkManager.peer_left.connect(_on_peer_left)
	NetworkManager.session_ended.connect(_clear_all)

func _on_peer_joined(id: int) -> void:
	_spawn_avatar(id)

func _on_peer_left(id: int) -> void:
	_remove_avatar(id)

func _clear_all() -> void:
	for id in _avatars.keys():
		_remove_avatar(id)

# Positions MONDE des têtes des pairs (pour la menace partagée des drones côté hôte). id -> Vector3.
func peer_heads() -> Dictionary:
	var out := {}
	for id in _avatars:
		var av = _avatars[id]
		if is_instance_valid(av) and av.head != null:
			out[id] = av.head.global_transform.origin
	return out

func _spawn_avatar(id: int) -> void:
	if _avatars.has(id):
		return
	var sc := get_tree().current_scene
	if sc == null:
		return
	var av = RAVATAR.new()
	sc.add_child(av)
	_avatars[id] = av

func _remove_avatar(id: int) -> void:
	if _avatars.has(id):
		if is_instance_valid(_avatars[id]):
			_avatars[id].queue_free()
		_avatars.erase(id)
	_buf.erase(id)

func _acquire() -> void:
	var sc := get_tree().current_scene
	if sc == null:
		return
	if _surface == null or not is_instance_valid(_surface):
		_surface = sc.find_child("SurfaceView", true, false)
	if _surface and _surface.has_method("get_chunk_manager") and (_cm == null or not is_instance_valid(_cm)):
		_cm = _surface.get_chunk_manager()
	if _surface and _surface.has_method("get_player") and (_player == null or not is_instance_valid(_player)):
		_player = _surface.get_player()
	if _lc == null or not is_instance_valid(_lc):
		_lc = sc.find_child("LeftController", true, false)
	if _rc == null or not is_instance_valid(_rc):
		_rc = sc.find_child("RightController", true, false)

func _process(dt: float) -> void:
	if not NetworkManager.is_active():
		return
	if GameState.current_scale != GameState.Scale.SURFACE:
		for id in _avatars:               # hors surface : pas de monde partagé en MVP => masque
			if is_instance_valid(_avatars[id]):
				_avatars[id].visible = false
		return
	_acquire()
	# Élague les avatars dont le nœud a été libéré (changement de scène) => respawn au prochain état reçu.
	for id in _avatars.keys():
		if not is_instance_valid(_avatars[id]):
			_avatars.erase(id)
			_buf.erase(id)
	if _cm == null or not _cm.has_method("root_transform"):
		return
	var m: Transform3D = _cm.root_transform()
	# 1. Publier l'état local (throttle ~22 Hz).
	_send_t += dt
	if _send_t >= SEND_INTERVAL:
		_send_t = 0.0
		_publish(m)
	# 2. Placer les avatars distants : interpolation planète + conversion planète->rendu via M LOCAL.
	for id in _avatars:
		var av = _avatars[id]
		if not is_instance_valid(av):
			continue
		var b = _buf.get(id)
		if b == null:
			av.visible = false
			continue
		av.visible = true
		b.elapsed += dt
		var t := clampf(b.elapsed / SEND_INTERVAL, 0.0, 1.0)
		var hp: Transform3D = (b.prev.head as Transform3D).interpolate_with(b.cur.head, t)
		av.head.global_transform = m * hp
		if b.cur.hands:
			av.set_hands_visible(true)
			var lp: Transform3D = (b.prev.lh as Transform3D).interpolate_with(b.cur.lh, t)
			var rp: Transform3D = (b.prev.rh as Transform3D).interpolate_with(b.cur.rh, t)
			av.lhand.global_transform = m * lp
			av.rhand.global_transform = m * rp
			av.weapon.global_transform = (m * rp).translated_local(Vector3(0.0, 0.0, -0.13))
			av.set_weapon(int(b.cur.weapon))
		else:
			av.set_hands_visible(false)

func _publish(m: Transform3D) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var minv := m.affine_inverse()
	var head_p: Transform3D = minv * cam.global_transform
	var hands: bool = GameState.xr_active and _lc != null and _rc != null and is_instance_valid(_lc) and is_instance_valid(_rc)
	var lh_p := Transform3D.IDENTITY
	var rh_p := Transform3D.IDENTITY
	if hands:
		lh_p = minv * (_lc as Node3D).global_transform
		rh_p = minv * (_rc as Node3D).global_transform
	rpc("_net_state", head_p, lh_p, rh_p, hands, _local_weapon_id())

func _local_weapon_id() -> int:
	if _player == null or not is_instance_valid(_player) or not _player.has_method("active_weapon_name"):
		return -1
	match String(_player.active_weapon_name()):
		"Blaster": return 0
		"Plasma": return 1
		"Grenade": return 2
	return -1

# Reçu d'un pair : son état tête/mains/arme en espace-PLANÈTE. Bufferisé pour interpolation (prev->cur).
@rpc("any_peer", "unreliable_ordered", "call_remote")
func _net_state(head_p: Transform3D, lh_p: Transform3D, rh_p: Transform3D, hands: bool, weapon: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not _avatars.has(id):
		_spawn_avatar(id)
	var cur := {"head": head_p, "lh": lh_p, "rh": rh_p, "hands": hands, "weapon": weapon}
	var b = _buf.get(id)
	if b == null:
		_buf[id] = {"prev": cur, "cur": cur, "elapsed": 0.0}
		print("[Coop] 1er état reçu du pair %d (planète head.origin=%s)" % [id, str(head_p.origin)])
	else:
		b.prev = b.cur
		b.cur = cur
		b.elapsed = 0.0
