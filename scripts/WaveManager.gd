extends Node
## Vagues d'ennemis (façon Space Pirate Trainer) : spawn des drones autour du joueur, vague après vague,
## difficulté croissante (nombre + cadence de tir). ACTIF seulement quand le joueur est ARMÉ (combat opt-in)
## ET en SURFACE. Quand le joueur dégaine (ou quitte la surface) => nettoie tout. AUTO-CONTENU.

const WAVE_GAP := 4.0       # s entre deux vagues (une fois la précédente nettoyée)
const FIRST_DELAY := 2.5    # s avant la 1re vague (le temps de se préparer)
const SPAWN_STAGGER := 0.12 # s entre deux apparitions de drone (spawn ÉCHELONNÉ => pas de pic de frame)
const DROP_CHANCE := 0.5    # probabilité qu'un drone abattu lâche une amélioration ramassable
const MAX_DRONES := 4       # plafond de drones SIMULTANÉS (rythme = + de PV par drone, pas + de nombre)
const ARM_GRACE := 0.6      # tolérance de désarmement BREF (changement d'arme) avant de réinitialiser la session
# Archétypes (ints partagés avec Drone.gd) + cadence des vagues-boss.
const ARCH_STANDARD := 0
const ARCH_HEAVY := 1
const ARCH_DARTER := 2
const ARCH_SHIELDED := 3
const ARCH_BOSS := 4
const BOSS_EVERY := 5       # une vague-BOSS (un seul drone géant) toutes les 5 vagues

var _player: Node3D
var _drones: Array = []
var _wave := 0
var _timer := 0.0
var _active := false
var _awaiting_clear := false   # une vague est en cours : son nettoyage déclenchera un soin
var _to_spawn := 0             # drones restant à faire apparaître pour la vague en cours (échelonné)
var _spawn_cd := 0.0           # minuterie d'échelonnement des apparitions
var _disarm_t := 0.0           # temps écoulé désarmé (grâce anti-reset lors d'un changement d'arme)
var _rng := RandomNumberGenerator.new()
var _spawn_queue: Array = []   # archétypes restant à faire apparaître pour la vague en cours

func setup(player: Node3D) -> void:
	_player = player
	_rng.randomize()

func _process(delta: float) -> void:
	# Coop : sur un INVITÉ, les vagues sont pilotées par l'HÔTE (drones répliqués via CoopCombat) => inerte ici.
	if NetworkManager.is_active() and not NetworkManager.is_host():
		return
	# Menu ouvert => combat EN PAUSE (le joueur est figé ; drones/bolts le sont aussi) : cohérent, pas de reset.
	if GameState.options_open:
		return
	var on_surface: bool = GameState.current_scale == GameState.Scale.SURFACE
	# Plus en surface OU mort => nettoyage IMMÉDIAT (quitter la surface n'est PAS un changement d'arme : pas de grâce).
	if not on_surface or GameState.combat_dead:
		if _active:
			_clear()
		return
	# « Mode Drone » opt-in : les vagues ne démarrent QUE si le joueur a accepté le prompt (cf. PlayerController).
	var weapon_out: bool = _player != null and _player.has_method("is_armed") and _player.is_armed() and GameState.drone_mode_on
	# En surface mais arme rangée : on TOLÈRE un bref désarmement (le temps d'un changement d'arme) via une grâce —
	# la session ne se réinitialise QUE si l'arme reste rangée au-delà de ARM_GRACE (= vrai dégainage).
	if not weapon_out:
		if _active:
			_disarm_t += delta
			if _disarm_t >= ARM_GRACE:
				_clear()
		return
	_disarm_t = 0.0   # armé (ou ré-armé pendant la grâce) => la session continue, vagues/score INCHANGÉS
	if not _active:
		_active = true
		_wave = 0
		_timer = FIRST_DELAY
		_awaiting_clear = false
		_to_spawn = 0
		GameState.combat_score = 0
		GameState.combat_wave = 0
		GameState.combat_result_wave = 0
		GameState.combat_result_score = 0
	# Apparition ÉCHELONNÉE de la vague (1 drone par SPAWN_STAGGER) — évite d'instancier n GLB en une frame.
	if _to_spawn > 0:
		_spawn_cd -= delta
		if _spawn_cd <= 0.0:
			_spawn_cd = SPAWN_STAGGER
			_spawn_drone()
			_to_spawn -= 1
		return
	_drones = _drones.filter(func(d): return is_instance_valid(d))
	if _drones.is_empty():
		if _awaiting_clear:   # vague précédente entièrement nettoyée => soin de récupération
			_awaiting_clear = false
			if _player.has_method("heal"):
				_player.heal(25.0)
			if NetworkManager.is_active() and NetworkManager.is_host():
				CoopCombat.host_heal_all(25.0)   # coop : soigne aussi les invités
		_timer -= delta
		if _timer <= 0.0:
			_start_wave()

func _start_wave() -> void:
	_wave += 1
	GameState.combat_wave = _wave
	AudioEngine.play_wave_start()   # sting « ça commence »
	# Toutes les BOSS_EVERY vagues : un seul drone GÉANT. Sinon, un mélange d'archétypes (variété croissante).
	if _wave % BOSS_EVERY == 0:
		_spawn_queue = [ARCH_BOSS]
	else:
		_spawn_queue = _roll_composition()
	_to_spawn = _spawn_queue.size()   # apparition ÉCHELONNÉE dans _process
	_spawn_cd = 0.0         # le 1er sort immédiatement
	_timer = WAVE_GAP
	_awaiting_clear = true   # cette vague nettoyée => soin

# Composition d'une vague normale : surtout des standards, avec rapides/lourds/boucliers débloqués par paliers.
func _roll_composition() -> Array:
	var n := mini(2 + _wave, MAX_DRONES)
	var out: Array = []
	for i in n:
		var r := _rng.randf()
		var a := ARCH_STANDARD
		if _wave >= 4 and r < 0.18:
			a = ARCH_SHIELDED
		elif _wave >= 3 and r < 0.38:
			a = ARCH_HEAVY
		elif _wave >= 2 and r < 0.60:
			a = ARCH_DARTER
		out.append(a)
	return out

func _spawn_drone() -> void:
	if _player == null:
		return
	var arch := ARCH_STANDARD
	if not _spawn_queue.is_empty():
		arch = _spawn_queue.pop_front()
	var boss := arch == ARCH_BOSS
	var fwd := CombatUtil.front_dir(_player)
	var ang := _rng.randf_range(-1.0, 1.0) * deg_to_rad(35.0 if boss else 85.0)   # boss plus centré ; autres dans le cône avant
	var dir := fwd.rotated(Vector3.UP, ang)
	var dist := (40.0 if boss else 26.0) + _rng.randf() * (6.0 if boss else 12.0)
	var pos := _player.global_position + dir * dist + Vector3.UP * _rng.randf_range(5.0 if boss else 3.0, 14.0 if boss else 12.0)
	var d = preload("res://scripts/Drone.gd").new()
	d.setup(_player, pos, _wave, arch)
	d.fire_cb = _on_drone_fire
	d.died.connect(_on_drone_died.bind(d))   # bind le drone : le handler lit son archetype (signal `died` minimal)
	add_child(d)
	_drones.append(d)
	if NetworkManager.is_active() and NetworkManager.is_host():
		CoopCombat.host_register_drone(d)   # coop : réplique ce drone aux invités (autorité hôte)

func _on_drone_fire(from: Vector3, toward: Vector3) -> void:
	var dmg := clampf(7.0 + float(_wave), 7.0, 16.0)   # un peu plus mordant à mesure que les vagues montent
	# Coop : l'hôte répartit la menace entre tous les joueurs. Un bolt visant un INVITÉ est RÉPLIQUÉ (le client le
	# fait voyager + s'auto-touche). Solo / cible = hôte : bolt local (inchangé).
	if NetworkManager.is_active() and NetworkManager.is_host():
		var tgt := CoopCombat.host_pick_bolt_target()
		if not tgt.is_host:
			CoopCombat.host_fire_bolt_at(int(tgt.id), from, tgt.head, dmg)
			AudioEngine.play_enemy_shot(from)
			return
		toward = tgt.head   # cible = hôte : bolt local visant la tête de l'hôte
	var b = preload("res://scripts/EnemyBolt.gd").new()
	b.setup(from, toward, _player, _on_bolt_hit)
	b.dmg = dmg
	add_child(b)
	AudioEngine.play_enemy_shot(from)   # zap grave spatialisé => on entend d'où vient le tir

func _on_bolt_hit(_pos: Vector3, dmg: float, vel: Vector3) -> void:
	if _player != null and _player.has_method("enemy_hit"):
		_player.enemy_hit(dmg, -vel)   # -vel = direction d'où vient le tir (vers le tireur)

func _on_drone_died(pos: Vector3, d) -> void:
	var arch: int = d.archetype   # drone encore valide (queue_free différé) => lecture directe de l'archétype
	GameState.combat_score += (10 if arch == ARCH_BOSS else 1)   # le boss vaut gros
	if _player != null and _player.has_method("on_kill"):
		_player.on_kill()          # confirmation (tic brillant + haptique) côté joueur
	if arch == ARCH_BOSS:
		AudioEngine.play_wave_start()                 # fanfare de victoire (réutilise le sting)
		_drop_pickup(pos, 4)                          # butin GARANTI : missiles
		_drop_pickup(pos + Vector3.RIGHT * 1.5, 0)    # + soin
	elif _rng.randf() < DROP_CHANCE:
		_drop_pickup(pos, _roll_pickup_kind())

# Lâche une amélioration ramassable (enfant => nettoyée au _clear) + réplication coop côté hôte.
func _drop_pickup(pos: Vector3, kind: int) -> void:
	var p = preload("res://scripts/Pickup.gd").new()
	p.setup(_player, kind, pos)
	add_child(p)
	if NetworkManager.is_active() and NetworkManager.is_host():
		CoopCombat.host_register_pickup(p, kind)   # coop : réplique le butin aux invités (autorité hôte)

# Tirage pondéré du type d'amélioration : soin un peu plus fréquent, puis dégâts / cadence / bouclier.
func _roll_pickup_kind() -> int:
	var r := _rng.randf()
	if r < 0.28:
		return 0    # KIND_HEAL
	elif r < 0.48:
		return 1    # KIND_DAMAGE
	elif r < 0.66:
		return 2    # KIND_RAPID
	elif r < 0.84:
		return 3    # KIND_SHIELD
	return 4        # KIND_MISSILE (~16 %)

func _clear() -> void:
	if NetworkManager.is_active() and NetworkManager.is_host():
		CoopCombat.host_clear_all()   # coop : retire les drones-fantômes chez les invités
	_active = false
	_awaiting_clear = false
	_to_spawn = 0
	_disarm_t = 0.0
	for c in get_children():
		c.queue_free()   # drones + bolts
	_drones.clear()
	GameState.combat_wave = 0
