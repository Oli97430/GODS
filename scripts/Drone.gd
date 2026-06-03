extends Area3D
## Drone ennemi (niveau 1) : vaisseau (GLB « luminaris ») qui approche/orbite le joueur et tire des bolts. PV +
## destruction (explosion) au blaster. Area3D => touché par le raycast du blaster (collide_with_areas). Spawné
## en VAGUES par WaveManager. AUTO-CONTENU. Vise le joueur chaque frame => se recale tout seul au rebase.

signal died(pos)

const SHIP_MODEL := "res://models/luminaris_starship.glb"   # GLB instancié (scène) — auto-échelle + centré
const SHIP_SIZE := 2.4            # m : envergure cible (auto-échelle)
const SHIP_ROT_DEG := Vector3(0.0, 0.0, 0.0)   # alignement visuel (à ajuster si le vaisseau vole « à l'envers »)
const ORBIT_DIST := 7.5    # m : distance d'orbite (plus proche du joueur) — variée par drone
const SPEED := 8.0
const HP_BASE := 3.0
const CHARGE_TIME := 0.5   # s : « télégraphe » (glow chaud) avant chaque tir => le joueur peut réagir
const FRONT_HALF := 1.5708   # rad (90°) : demi-angle du cône AVANT où évoluent les drones (cône total 180°)
const SWAY_AMP := 0.38       # rad (~22°) : amplitude du balancement dans le cône
const SWAY_SPEED := 0.5      # vitesse du balancement
const KNOCKBACK := 2.5       # m/s par point de dégât : impulsion de recul à l'impact (revolver léger, plasma/grenade lourds)

var hp := HP_BASE
var _player: Node3D
var _vel := Vector3.ZERO
var _base_ang := 0.0   # azimut de base du drone DANS le cône avant (réparti au spawn)
var _phase := 0.0      # déphasage du balancement
var _orbit := ORBIT_DIST   # distance d'orbite propre à ce drone (variée)
var _alt := 10.0
var _fire_cd := 1.5
var _fire_interval := 2.6
var _t := 0.0
var _flash_t := 0.0
var _dead := false
var _spawn_t := 0.35              # apparition : pop d'échelle (télégraphe d'arrivée)
var _target_scale := Vector3.ONE
var _visual: Node3D
var _glow: OmniLight3D   # lueur rouge d'ennemi : flash de dégât + télégraphe — ALLUMÉE seulement quand pertinent
var _core: MeshInstance3D       # cœur émissif rouge : tell d'ennemi permanent (additif, SANS lumière => coût nul)
var _core_mat: StandardMaterial3D
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
	_base_ang = _rng.randf_range(-1.0, 1.0) * FRONT_HALF * 0.85   # réparti dans le cône avant
	_phase = _rng.randf() * TAU
	_orbit = ORBIT_DIST + _rng.randf_range(-1.5, 3.5)   # certains s'approchent à ~6 m, d'autres ~11 m
	_fire_cd = 1.0 + _rng.randf() * 1.5
	# Visuel : scène GLB instanciée (luminaris) — auto-échelle (envergure SHIP_SIZE) + centrée + ombres off.
	_visual = Node3D.new()
	var scene = load(SHIP_MODEL)
	if scene != null:
		var inst = scene.instantiate()
		_visual.add_child(inst)
		CombatUtil.disable_shadows(inst)
		var r := CombatUtil.scene_aabb(inst, Transform3D.IDENTITY)
		if r.has and r.box.size.length() > 0.0001:
			var ab: AABB = r.box
			var longest: float = maxf(maxf(ab.size.x, ab.size.y), ab.size.z)
			var s: float = SHIP_SIZE / maxf(longest, 0.0001)
			(inst as Node3D).position = -ab.get_center()   # centre le modèle (avant la mise à l'échelle du conteneur)
			_visual.scale = Vector3(s, s, s)
		_visual.rotation = Vector3(deg_to_rad(SHIP_ROT_DEG.x), deg_to_rad(SHIP_ROT_DEG.y), deg_to_rad(SHIP_ROT_DEG.z))
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.6, 0.6, 2.0)
		mi.mesh = bm
		_visual.add_child(mi)
	add_child(_visual)
	# Lueur d'ennemi (rouge) : lisibilité + flash de dégât + télégraphe — indépendante des matériaux GLB.
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.3, 0.2)
	_glow.omni_range = SHIP_SIZE * 1.8
	_glow.light_energy = 0.0          # éteinte au repos : ne s'allume QUE en charge/flash (peu de lights simultanées)
	_glow.shadow_enabled = false
	_glow.visible = false
	add_child(_glow)
	# Cœur émissif rouge : tell d'ennemi TOUJOURS visible, additif, SANS lumière dynamique => coût nul en lights.
	_core = MeshInstance3D.new()
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cs := SphereMesh.new()
	cs.radius = SHIP_SIZE * 0.12
	cs.height = SHIP_SIZE * 0.24
	cs.radial_segments = 8
	cs.rings = 4
	_core.mesh = cs
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_core_mat.albedo_color = Color(1.0, 0.3, 0.2, 0.55)
	_core.material_override = _core_mat
	add_child(_core)
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
	# Position dans un CÔNE de 180° DEVANT le joueur : forward joueur + azimut de base (réparti) + balancement.
	var fwd := CombatUtil.front_dir(_player)
	var ang := clampf(_base_ang + sin(_t * SWAY_SPEED + _phase) * SWAY_AMP, -FRONT_HALF, FRONT_HALF)
	var dir := fwd.rotated(Vector3.UP, ang)
	var target := p + dir * _orbit + Vector3.UP * (_alt + sin(_t * 1.3) * 1.5)
	var desired := target - global_position
	if desired.length() > 0.01:
		_vel = _vel.lerp(desired.normalized() * SPEED, clampf(2.0 * delta, 0.0, 1.0))
	global_position += _vel * delta
	# Face le joueur (sauf si à la verticale => éviter le look_at dégénéré).
	var flat := Vector2(p.x - global_position.x, p.z - global_position.z)
	if flat.length() > 0.5:
		look_at(p, Vector3.UP)
	# Tell visuel : cœur additif TOUJOURS visible (coût nul) ; lumière dynamique SEULEMENT en flash/charge
	# (=> peu de lights simultanées même en grosse vague). lit = intensité « chaude » 0..1.
	var lit := 0.0
	var warm := Color(1.0, 0.3, 0.2)
	if _flash_t > 0.0:
		_flash_t -= delta
		lit = clampf(_flash_t / 0.12, 0.0, 1.0)
		warm = Color(1.0, 0.3, 0.2).lerp(Color(1.0, 0.9, 0.7), lit)
	else:
		lit = clampf(1.0 - _fire_cd / CHARGE_TIME, 0.0, 1.0) if _fire_cd < CHARGE_TIME else 0.0
		warm = Color(1.0, 0.3, 0.2).lerp(Color(1.0, 0.55, 0.2), lit)
	if _core_mat:
		_core_mat.albedo_color = Color(warm.r, warm.g, warm.b, 0.45 + 0.5 * lit)
	if _glow:
		var glow_on := lit > 0.05
		_glow.visible = glow_on
		if glow_on:
			_glow.light_color = warm
			_glow.light_energy = 5.5 * lit
	# Tir vers le joueur.
	_fire_cd -= delta
	if _fire_cd <= 0.0:
		_fire_cd = _fire_interval
		if fire_cb.is_valid():
			fire_cb.call(global_position, p + Vector3.UP * 1.3)

# Appelé par PlayerController quand le blaster touche ce drone (raycast). amount = dégâts, pos = point d'impact.
func take_damage(amount: float, pos: Vector3) -> void:
	if _dead:
		return
	hp -= amount
	_flash_t = 0.12
	# Étincelles à l'impact (le drone « encaisse » visiblement).
	var sp = preload("res://scripts/HitSpark.gd").new()
	sp.play(pos)
	get_parent().add_child(sp)
	# Recul : le drone est repoussé dans l'axe joueur→drone (+ léger vers le haut), puis l'IA le ramène en orbite.
	if _player:
		var push := global_position - _player.global_position
		push.y = 0.0
		push = push.normalized() if push.length() > 0.01 else Vector3.FORWARD
		var kb := minf(amount, 4.0) * KNOCKBACK   # plafonné => pas de propulsion incontrôlée
		_vel += push * kb + Vector3.UP * (kb * 0.35)
		if _vel.length() > 22.0:
			_vel = _vel.normalized() * 22.0
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
