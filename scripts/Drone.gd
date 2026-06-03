extends Area3D
## Drone ennemi (niveau 1) : vaisseau low-poly (OBJ) qui approche/orbite le joueur et tire des bolts. PV +
## destruction (explosion) au blaster. Area3D => touché par le raycast du blaster (collide_with_areas). Spawné
## en VAGUES par WaveManager. AUTO-CONTENU. Vise le joueur chaque frame => se recale tout seul au rebase.

signal died(pos)

const SHIP_MODEL := "res://models/spaceship/SpaceShip Free low-poly 3D model.obj"
const SHIP_ALBEDO := "res://models/spaceship/mat0_c.jpg"
const SHIP_SIZE := 2.0            # m : envergure cible (auto-échelle)
const SHIP_ROT_DEG := Vector3(0.0, 0.0, 0.0)   # alignement visuel (à ajuster si le vaisseau vole « à l'envers »)
const ORBIT_DIST := 7.5    # m : distance d'orbite (plus proche du joueur) — variée par drone
const SPEED := 8.0
const HP_BASE := 3.0
const CHARGE_TIME := 0.5   # s : « télégraphe » (glow chaud) avant chaque tir => le joueur peut réagir

var hp := HP_BASE
var _player: Node3D
var _vel := Vector3.ZERO
var _ang := 0.0
var _orbit := ORBIT_DIST   # distance d'orbite propre à ce drone (variée)
var _alt := 10.0
var _fire_cd := 1.5
var _fire_interval := 2.6
var _t := 0.0
var _flash_t := 0.0
var _dead := false
var _spawn_t := 0.35              # apparition : pop d'échelle (télégraphe d'arrivée)
var _target_scale := Vector3.ONE
var _visual: MeshInstance3D
var _mat: StandardMaterial3D
var fire_cb := Callable()       # WaveManager fournit : fire_cb.call(from, toward) => spawn un bolt
var _rng := RandomNumberGenerator.new()

# Appelé par le WaveManager AVANT add_child : position de spawn + niveau (difficulté).
func setup(player: Node3D, spawn_pos: Vector3, level: int) -> void:
	_player = player
	_pending_pos = spawn_pos
	hp = HP_BASE + float(level - 1)
	_fire_interval = maxf(2.6 - float(level - 1) * 0.25, 1.2)
var _pending_pos := Vector3.ZERO

func _ready() -> void:
	_rng.randomize()
	global_position = _pending_pos
	if _player:
		_alt = _pending_pos.y - _player.global_position.y
	_ang = _rng.randf() * TAU
	_orbit = ORBIT_DIST + _rng.randf_range(-1.5, 3.5)   # certains s'approchent à ~6 m, d'autres ~11 m
	_fire_cd = 1.0 + _rng.randf() * 1.5
	# Visuel : mesh OBJ + albedo (+ légère émission rouge => lisible comme ennemi), auto-échelle + centré.
	_visual = MeshInstance3D.new()
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m = load(SHIP_MODEL)
	if m != null:
		_visual.mesh = m
		_mat = StandardMaterial3D.new()
		var tex = load(SHIP_ALBEDO)
		if tex != null:
			_mat.albedo_texture = tex
		_mat.emission_enabled = true
		_mat.emission = Color(0.35, 0.05, 0.05)
		_mat.emission_energy_multiplier = 0.5
		_visual.material_override = _mat
		var ab: AABB = m.get_aabb()
		var longest: float = maxf(maxf(ab.size.x, ab.size.y), ab.size.z)
		var s: float = SHIP_SIZE / maxf(longest, 0.0001)
		_visual.scale = Vector3(s, s, s)
		_visual.position = -ab.get_center() * s
		_visual.rotation = Vector3(deg_to_rad(SHIP_ROT_DEG.x), deg_to_rad(SHIP_ROT_DEG.y), deg_to_rad(SHIP_ROT_DEG.z))
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3(1.6, 0.6, 2.0)
		_visual.mesh = bm
	add_child(_visual)
	# Collision (sphère) pour le raycast du blaster.
	var col := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = SHIP_SIZE * 0.55
	col.shape = sh
	add_child(col)
	# Apparition : pop d'échelle + bref flash lumineux (télégraphe « un drone arrive »).
	_target_scale = _visual.scale
	_visual.scale = _target_scale * 0.08
	var spawn_fl := OmniLight3D.new()
	spawn_fl.light_color = Color(1.0, 0.5, 0.4)
	spawn_fl.omni_range = 6.0
	spawn_fl.light_energy = 8.0
	spawn_fl.shadow_enabled = false
	add_child(spawn_fl)
	get_tree().create_timer(0.18).timeout.connect(spawn_fl.queue_free)

func _process(delta: float) -> void:
	if _spawn_t > 0.0 and _visual:   # pop d'apparition (indépendant du joueur)
		_spawn_t = maxf(_spawn_t - delta, 0.0)
		var k := clampf(1.0 - _spawn_t / 0.35, 0.0, 1.0)
		_visual.scale = _target_scale * lerpf(0.08, 1.0, k)
	if _dead:
		return
	if _player == null or not is_instance_valid(_player):
		return
	_t += delta
	var p := _player.global_position
	# Orbite lente autour du joueur, à ORBIT_DIST, altitude _alt + léger bob.
	_ang += delta * 0.45
	var target := p + Vector3(cos(_ang) * _orbit, _alt + sin(_t * 1.3) * 1.5, sin(_ang) * _orbit)
	var desired := target - global_position
	if desired.length() > 0.01:
		_vel = _vel.lerp(desired.normalized() * SPEED, clampf(2.0 * delta, 0.0, 1.0))
	global_position += _vel * delta
	# Face le joueur (sauf si à la verticale => éviter le look_at dégénéré).
	var flat := Vector2(p.x - global_position.x, p.z - global_position.z)
	if flat.length() > 0.5:
		look_at(p, Vector3.UP)
	# Flash de dégât (prioritaire) OU télégraphe de tir (glow chaud montant avant de tirer).
	if _flash_t > 0.0 and _mat:
		_flash_t -= delta
		_mat.emission = Color(0.35, 0.05, 0.05).lerp(Color(1.0, 0.6, 0.3), clampf(_flash_t / 0.12, 0.0, 1.0))
		_mat.emission_energy_multiplier = 0.5 + 1.8 * clampf(_flash_t / 0.12, 0.0, 1.0)
	elif _mat:
		var charge := clampf(1.0 - _fire_cd / CHARGE_TIME, 0.0, 1.0) if _fire_cd < CHARGE_TIME else 0.0
		_mat.emission = Color(0.35, 0.05, 0.05).lerp(Color(1.0, 0.35, 0.1), charge)
		_mat.emission_energy_multiplier = 0.5 + 2.6 * charge
	# Tir vers le joueur.
	_fire_cd -= delta
	if _fire_cd <= 0.0:
		_fire_cd = _fire_interval
		if fire_cb.is_valid():
			fire_cb.call(global_position, p + Vector3.UP * 1.3)

# Appelé par PlayerController quand le blaster touche ce drone (raycast). amount = dégâts.
func take_damage(amount: float, _pos: Vector3) -> void:
	if _dead:
		return
	hp -= amount
	_flash_t = 0.12
	if hp <= 0.0:
		_die()

func _die() -> void:
	if _dead:
		return
	_dead = true
	var ex = preload("res://scripts/Explosion.gd").new()
	get_parent().add_child(ex)
	ex.global_position = global_position
	ex.play(1.0)
	AudioEngine.play_impact(global_position, 0.7)   # boom de destruction
	died.emit(global_position)
	queue_free()
