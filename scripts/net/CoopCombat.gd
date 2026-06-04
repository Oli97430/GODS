extends Node
## Coop CP3 — combat HOST-AUTORITAIRE. L'HÔTE fait tourner les vagues (WaveManager) ; CoopCombat réplique chaque
## drone aux invités : CRÉATION (+ late-join) + POSITION en espace-PLANÈTE ~15 Hz (anti-rebase) + DESTRUCTION.
## Arbitrage des dégâts : un invité qui tire sur un drone-FANTÔME rapporte le coup à l'hôte (RPC), qui applique
## les dégâts au VRAI drone et décide de la mort. Les invités n'ont aucune IA de drone (fantômes positionnés).
## ACTIF seulement en session ⇒ INERTE en solo (zéro régression). Autoload : CoopCombat (après NetworkManager).
## CP3b : tirs ennemis répartis (PV des 2 joueurs) + soin coop. Loot : pickups host-autoritaires répliqués (ghosts).

const DRONE := preload("res://scripts/Drone.gd")
const PICKUP := preload("res://scripts/Pickup.gd")
const SYNC_HZ := 15.0
const SYNC_INTERVAL := 1.0 / SYNC_HZ

var _host_drones := {}      # HÔTE : net_id -> VRAI drone (WaveManager). JAMAIS libéré par CoopCombat.
var _ghosts := {}           # INVITÉ : net_id -> drone-FANTÔME (créé/libéré par CoopCombat).
var _gtargets := {}         # INVITÉ : net_id -> {prev: Vector3, cur: Vector3, elapsed: float} (interp planète)
var _host_pickups := {}     # HÔTE : net_id -> VRAI pickup (WaveManager).
var _ghost_pickups := {}    # INVITÉ : net_id -> pickup-FANTÔME (visuel, position synchronisée).
var _ptargets := {}         # INVITÉ : net_id -> {prev, cur, elapsed} (interp planète des pickups)
var _next_id := 1
var _send_t := 0.0
var _cm = null              # ChunkManager (cache, pour M = root_transform)

func _ready() -> void:
	NetworkManager.peer_joined.connect(_on_peer_joined)
	NetworkManager.session_ended.connect(_on_session_ended)

# --- HÔTE ---

# Appelé par WaveManager quand l'hôte fait apparaître un drone. Assigne un id réseau + réplique aux invités.
func host_register_drone(d) -> void:
	if not NetworkManager.is_host() or d == null:
		return
	var nid := _next_id
	_next_id += 1
	d.net_id = nid
	_host_drones[nid] = d
	d.died.connect(_host_on_died.bind(nid))
	rpc("_rpc_spawn", nid)

func _host_on_died(_pos: Vector3, nid: int) -> void:
	_host_drones.erase(nid)
	if NetworkManager.is_active():
		rpc("_rpc_remove", nid)

# Late-join : un invité arrive => on lui envoie les drones DÉJÀ présents (apparus avant sa connexion).
func _on_peer_joined(id: int) -> void:
	if NetworkManager.is_host():
		for nid in _host_drones:
			rpc_id(id, "_rpc_spawn", nid)

# L'hôte désarme / meurt => WaveManager nettoie ses drones : on retire les fantômes des invités SILENCIEUSEMENT
# (pas une mort en combat, juste une fin de session de vagues).
func host_clear_all() -> void:
	if not NetworkManager.is_host():
		return
	_host_drones.clear()
	rpc("_rpc_clear_all")

func _host_sync() -> void:
	var m = _get_m()
	if m == null:
		return
	var minv: Transform3D = (m as Transform3D).affine_inverse()
	var ids := PackedInt32Array()
	var xs := PackedVector3Array()
	for nid in _host_drones:
		var d = _host_drones[nid]
		if not is_instance_valid(d):
			continue
		ids.append(nid)
		xs.append(minv * d.global_position)   # rendu -> planète (frame absolu partagé)
	if ids.size() > 0:
		rpc("_rpc_sync", ids, xs)
	# Pickups : mêmes positions planète (M⁻¹·rendu).
	var pids := PackedInt32Array()
	var pxs := PackedVector3Array()
	for nid in _host_pickups:
		var pk = _host_pickups[nid]
		if not is_instance_valid(pk):
			continue
		pids.append(nid)
		pxs.append(minv * pk.global_position)
	if pids.size() > 0:
		rpc("_rpc_pickup_sync", pids, pxs)

# --- INVITÉ : appelé par un drone-fantôme touché (Drone.take_damage en mode remote) ---

func client_report_hit(nid: int, dmg: float) -> void:
	if NetworkManager.is_active():
		rpc_id(1, "_rpc_hit", nid, dmg)   # vers l'hôte (id 1)

# --- HÔTE : menace partagée (bolts) + soin de vague (CP3b) ---

# Cible d'un tir de drone : hôte OU un invité (réparti ~50/50). {is_host: bool, id: int, head: Vector3 (monde)}.
func host_pick_bolt_target() -> Dictionary:
	var host_head := Vector3.ZERO
	var p = _get_player()
	if p != null:
		host_head = p.global_position + Vector3.UP * 1.4
	var heads: Dictionary = CoopSync.peer_heads()
	var ids := heads.keys()
	if ids.is_empty() or randf() < 0.5:
		return {"is_host": true, "id": 0, "head": host_head}
	var id = ids[randi() % ids.size()]
	return {"is_host": false, "id": int(id), "head": heads[id]}

# Tire un bolt vers un INVITÉ : envoyé en espace-planète ; l'invité le fait voyager + s'auto-touche localement.
func host_fire_bolt_at(id: int, from: Vector3, aim: Vector3, dmg: float) -> void:
	var m = _get_m()
	if m == null:
		return
	var minv: Transform3D = (m as Transform3D).affine_inverse()
	rpc_id(id, "_rpc_enemy_bolt", minv * from, minv * aim, dmg)

# Soin de fin de vague : l'hôte soigne aussi tous les invités.
func host_heal_all(amount: float) -> void:
	if NetworkManager.is_host():
		rpc("_rpc_heal", amount)

# --- HÔTE : loot partagé (pickups répliqués, ramassage par le plus proche) ---

# Enregistre un pickup spawné par l'hôte : id réseau + réplique un GHOST aux invités (type + position planète).
func host_register_pickup(pk, kind: int) -> void:
	if not NetworkManager.is_host() or pk == null:
		return
	var nid := _next_id
	_next_id += 1
	pk.net_id = nid
	_host_pickups[nid] = pk
	var planet := Vector3.ZERO
	var m = _get_m()
	if m != null:
		planet = (m as Transform3D).affine_inverse() * pk.global_position
	rpc("_rpc_pickup_spawn", nid, kind, planet)

func host_remove_pickup(nid: int) -> void:
	_host_pickups.erase(nid)
	if NetworkManager.is_active():
		rpc("_rpc_pickup_remove", nid)

# Le pickup hôte a été ramassé par le joueur le plus proche => applique le bonus au bon joueur + retire partout.
func host_award_pickup(nid: int, is_host: bool, id: int, kind: int) -> void:
	if not NetworkManager.is_host():
		return
	if is_host:
		var p = _get_player()
		if p != null and p.has_method("apply_pickup"):
			p.apply_pickup(kind)
	else:
		rpc_id(id, "_rpc_apply_pickup", kind)
	_host_pickups.erase(nid)
	rpc("_rpc_pickup_remove", nid)

# Joueur (hôte OU invité) le plus proche d'une position monde. {has, dist, is_host, id, pos}.
func coop_nearest_player(world_pos: Vector3) -> Dictionary:
	var best := {"has": false, "dist": 1.0e20}
	var p = _get_player()
	if p != null:
		best = {"has": true, "dist": world_pos.distance_to(p.global_position), "is_host": true, "id": 0, "pos": p.global_position}
	var heads: Dictionary = CoopSync.peer_heads()
	for id in heads:
		var hpos: Vector3 = heads[id]
		var d := world_pos.distance_to(hpos)
		if d < float(best.dist):
			best = {"has": true, "dist": d, "is_host": false, "id": int(id), "pos": hpos}
	return best

# --- RPC ---

@rpc("any_peer", "reliable", "call_remote")
func _rpc_hit(nid: int, dmg: float) -> void:
	if not NetworkManager.is_host():
		return
	var d = _host_drones.get(nid)
	if d != null and is_instance_valid(d):
		d.take_damage(dmg, d.global_position)   # autorité : applique les dégâts au vrai drone

# INVITÉ : reçoit un bolt ennemi (espace-planète) => le fait voyager localement vers SON joueur (auto-touche).
@rpc("authority", "reliable", "call_remote")
func _rpc_enemy_bolt(from_p: Vector3, aim_p: Vector3, dmg: float) -> void:
	var m = _get_m()
	if m == null:
		return
	var mt := (m as Transform3D)
	var p = _get_player()
	if p == null:
		return
	var b = preload("res://scripts/EnemyBolt.gd").new()
	b.setup(mt * from_p, mt * aim_p, p, _client_bolt_hit)
	b.dmg = dmg
	var sc := get_tree().current_scene
	if sc:
		sc.add_child(b)
	print("[CoopCombat] bolt ennemi reçu (dmg=%.0f)" % dmg)

func _client_bolt_hit(_pos: Vector3, dmg: float, vel: Vector3) -> void:
	var p = _get_player()
	if p != null and p.has_method("enemy_hit"):
		p.enemy_hit(dmg, -vel)

@rpc("authority", "reliable", "call_remote")
func _rpc_heal(amount: float) -> void:
	var p = _get_player()
	if p != null and p.has_method("heal"):
		p.heal(amount)

# INVITÉ : on m'accorde un butin (ramassé chez moi, arbitré par l'hôte) => applique le bonus à MON joueur.
@rpc("authority", "reliable", "call_remote")
func _rpc_apply_pickup(kind: int) -> void:
	var p = _get_player()
	if p != null and p.has_method("apply_pickup"):
		p.apply_pickup(kind)

# INVITÉ : crée un pickup-FANTÔME (visuel ; position pilotée par _rpc_pickup_sync).
@rpc("authority", "reliable", "call_remote")
func _rpc_pickup_spawn(nid: int, kind: int, planet: Vector3) -> void:
	if _ghost_pickups.has(nid):
		return
	var sc := get_tree().current_scene
	if sc == null:
		return
	var pk = PICKUP.new()
	pk.remote = true            # AVANT add_child => fantôme (visuel seul, pas de ramassage local)
	pk.setup(null, kind, Vector3.ZERO)
	sc.add_child(pk)
	pk.net_id = nid
	_ghost_pickups[nid] = pk
	_ptargets[nid] = {"prev": planet, "cur": planet, "elapsed": 0.0}

@rpc("authority", "reliable", "call_remote")
func _rpc_pickup_remove(nid: int) -> void:
	var pk = _ghost_pickups.get(nid)
	if pk != null and is_instance_valid(pk):
		pk.queue_free()
	_ghost_pickups.erase(nid)
	_ptargets.erase(nid)

@rpc("authority", "unreliable_ordered", "call_remote")
func _rpc_pickup_sync(ids: PackedInt32Array, xs: PackedVector3Array) -> void:
	for i in ids.size():
		var nid := ids[i]
		var t = _ptargets.get(nid)
		if t == null:
			_ptargets[nid] = {"prev": xs[i], "cur": xs[i], "elapsed": 0.0}
		else:
			t.prev = t.cur
			t.cur = xs[i]
			t.elapsed = 0.0

@rpc("authority", "reliable", "call_remote")
func _rpc_spawn(nid: int) -> void:
	if _ghosts.has(nid):
		return
	var sc := get_tree().current_scene
	if sc == null:
		return
	var g = DRONE.new()
	g.remote = true            # AVANT add_child => _ready se configure en fantôme (pleine échelle, pas d'IA)
	sc.add_child(g)
	g.net_id = nid
	_ghosts[nid] = g
	print("[CoopCombat] drone-fantôme %d créé" % nid)

@rpc("authority", "reliable", "call_remote")
func _rpc_remove(nid: int) -> void:
	var g = _ghosts.get(nid)
	if g != null and is_instance_valid(g):
		var sc := get_tree().current_scene
		if sc:
			var ex = preload("res://scripts/Explosion.gd").new()
			sc.add_child(ex)
			ex.global_position = g.global_position
			ex.play(1.0)
		AudioEngine.play_impact(g.global_position, 0.7)
		g.queue_free()
	_ghosts.erase(nid)
	_gtargets.erase(nid)

@rpc("authority", "reliable", "call_remote")
func _rpc_clear_all() -> void:
	for nid in _ghosts.keys():
		if is_instance_valid(_ghosts[nid]):
			_ghosts[nid].queue_free()
	_ghosts.clear()
	_gtargets.clear()

@rpc("authority", "unreliable_ordered", "call_remote")
func _rpc_sync(ids: PackedInt32Array, xs: PackedVector3Array) -> void:
	for i in ids.size():
		var nid := ids[i]
		var planet_pos := xs[i]
		var t = _gtargets.get(nid)
		if t == null:
			_gtargets[nid] = {"prev": planet_pos, "cur": planet_pos, "elapsed": 0.0}
		else:
			t.prev = t.cur
			t.cur = planet_pos
			t.elapsed = 0.0

# --- Boucle ---

func _process(dt: float) -> void:
	if not NetworkManager.is_active():
		return
	if NetworkManager.is_host():
		_send_t += dt
		if _send_t >= SYNC_INTERVAL:
			_send_t = 0.0
			_host_sync()
		return
	# INVITÉ : positionne les fantômes (interp planète -> rendu via M LOCAL).
	var m = _get_m()
	if m == null:
		return
	for nid in _ghosts:
		var g = _ghosts[nid]
		var t = _gtargets.get(nid)
		if g == null or not is_instance_valid(g) or t == null:
			continue
		t.elapsed += dt
		var k := clampf(t.elapsed / SYNC_INTERVAL, 0.0, 1.0)
		var planet_pos: Vector3 = (t.prev as Vector3).lerp(t.cur, k)
		g.global_position = (m as Transform3D) * planet_pos
	# Pickups-fantômes : même interpolation planète -> rendu via M LOCAL.
	for nid in _ghost_pickups:
		var pk = _ghost_pickups[nid]
		var pt = _ptargets.get(nid)
		if pk == null or not is_instance_valid(pk) or pt == null:
			continue
		pt.elapsed += dt
		var pk_k := clampf(pt.elapsed / SYNC_INTERVAL, 0.0, 1.0)
		var ppos: Vector3 = (pt.prev as Vector3).lerp(pt.cur, pk_k)
		pk.global_position = (m as Transform3D) * ppos

func _on_session_ended() -> void:
	for nid in _ghosts.keys():
		if is_instance_valid(_ghosts[nid]):
			_ghosts[nid].queue_free()
	for nid in _ghost_pickups.keys():
		if is_instance_valid(_ghost_pickups[nid]):
			_ghost_pickups[nid].queue_free()
	_ghosts.clear()
	_gtargets.clear()
	_ghost_pickups.clear()
	_ptargets.clear()
	_host_pickups.clear()
	_host_drones.clear()
	_next_id = 1

func _get_m():
	var sc := get_tree().current_scene
	if sc == null:
		return null
	if _cm == null or not is_instance_valid(_cm):
		var sv = sc.find_child("SurfaceView", true, false)
		if sv and sv.has_method("get_chunk_manager"):
			_cm = sv.get_chunk_manager()
	if _cm and _cm.has_method("root_transform"):
		return _cm.root_transform()
	return null

func _get_player():
	var sc := get_tree().current_scene
	if sc == null:
		return null
	var sv = sc.find_child("SurfaceView", true, false)
	if sv and sv.has_method("get_player"):
		return sv.get_player()
	return null
