extends Node
## Vagues d'ennemis (façon Space Pirate Trainer) : spawn des drones autour du joueur, vague après vague,
## difficulté croissante (nombre + cadence de tir). ACTIF seulement quand le joueur est ARMÉ (combat opt-in)
## ET en SURFACE. Quand le joueur dégaine (ou quitte la surface) => nettoie tout. AUTO-CONTENU.

const WAVE_GAP := 4.0       # s entre deux vagues (une fois la précédente nettoyée)
const FIRST_DELAY := 2.5    # s avant la 1re vague (le temps de se préparer)

var _player: Node3D
var _drones: Array = []
var _wave := 0
var _timer := 0.0
var _active := false
var _awaiting_clear := false   # une vague est en cours : son nettoyage déclenchera un soin
var _rng := RandomNumberGenerator.new()

func setup(player: Node3D) -> void:
	_player = player
	_rng.randomize()

func _process(delta: float) -> void:
	var armed: bool = GameState.current_scale == GameState.Scale.SURFACE and _player != null \
		and _player.has_method("is_armed") and _player.is_armed()
	# Désarmé OU mort => on nettoie la session ; à la réapparition elle redémarre à la vague 1.
	if not armed or GameState.combat_dead:
		if _active:
			_clear()
		return
	if not _active:
		_active = true
		_wave = 0
		_timer = FIRST_DELAY
		_awaiting_clear = false
		GameState.combat_score = 0
		GameState.combat_wave = 0
		GameState.combat_result_wave = 0
		GameState.combat_result_score = 0
	_drones = _drones.filter(func(d): return is_instance_valid(d))
	if _drones.is_empty():
		if _awaiting_clear:   # vague précédente entièrement nettoyée => soin de récupération
			_awaiting_clear = false
			if _player.has_method("heal"):
				_player.heal(25.0)
		_timer -= delta
		if _timer <= 0.0:
			_start_wave()

func _start_wave() -> void:
	_wave += 1
	GameState.combat_wave = _wave
	AudioEngine.play_wave_start()   # sting « ça commence »
	var n := 2 + _wave   # 3, 4, 5, ... drones par vague
	for i in n:
		_spawn_drone()
	_timer = WAVE_GAP
	_awaiting_clear = true   # cette vague nettoyée => soin

func _spawn_drone() -> void:
	if _player == null:
		return
	var ang := _rng.randf() * TAU
	var dist := 26.0 + _rng.randf() * 12.0
	var pos := _player.global_position + Vector3(cos(ang) * dist, _rng.randf_range(7.0, 18.0), sin(ang) * dist)
	var d = preload("res://scripts/Drone.gd").new()
	d.setup(_player, pos, _wave)
	d.fire_cb = _on_drone_fire
	d.died.connect(_on_drone_died)
	add_child(d)
	_drones.append(d)

func _on_drone_fire(from: Vector3, toward: Vector3) -> void:
	var b = preload("res://scripts/EnemyBolt.gd").new()
	b.setup(from, toward, _player, _on_bolt_hit)
	b.dmg = clampf(7.0 + float(_wave), 7.0, 16.0)   # un peu plus mordant à mesure que les vagues montent
	add_child(b)
	AudioEngine.play_enemy_shot(from)   # zap grave spatialisé => on entend d'où vient le tir

func _on_bolt_hit(_pos: Vector3, dmg: float, vel: Vector3) -> void:
	if _player != null and _player.has_method("enemy_hit"):
		_player.enemy_hit(dmg, -vel)   # -vel = direction d'où vient le tir (vers le tireur)

func _on_drone_died(_pos: Vector3) -> void:
	GameState.combat_score += 1   # +1 drone détruit
	if _player != null and _player.has_method("on_kill"):
		_player.on_kill()          # confirmation (tic brillant + haptique) côté joueur

func _clear() -> void:
	_active = false
	_awaiting_clear = false
	for c in get_children():
		c.queue_free()   # drones + bolts
	_drones.clear()
	GameState.combat_wave = 0
