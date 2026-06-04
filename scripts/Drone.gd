extends Area3D
## Drone ennemi (niveau 1) : vaisseau (GLB « luminaris ») qui approche/orbite le joueur et tire des bolts. PV +
## destruction (explosion) au blaster. Area3D => touché par le raycast du blaster (collide_with_areas). Spawné
## en VAGUES par WaveManager. AUTO-CONTENU. Vise le joueur chaque frame => se recale tout seul au rebase.

signal died(pos)

const SHIP_MODEL := "res://models/luminaris_starship.glb"   # GLB détaillé (lourd/bouclier/boss) — auto-échelle + centré
const SHIP_MODEL_LIGHT := "res://models/spaceship/SpaceShip Free low-poly 3D model.obj"   # mesh LOW-POLY (perf) pour les drones COURANTS
const SHIP_SIZE := 2.4            # m : envergure cible (auto-échelle)
const SHIP_ROT_DEG := Vector3(0.0, 0.0, 0.0)   # alignement visuel (à ajuster si le vaisseau vole « à l'envers »)
const ORBIT_DIST := 7.5    # m : distance d'orbite (plus proche du joueur) — variée par drone
const SPEED := 8.0
const HP_BASE := 4.0
const HP_PER_WAVE := 2.0   # PV ajoutés par vague : compense le plafond de drones simultanés (robustesse vs nombre)
const CHARGE_TIME := 0.5   # s : « télégraphe » (glow chaud) avant chaque tir => le joueur peut réagir
const FRONT_HALF := 1.5708   # rad (90°) : demi-angle du cône AVANT où évoluent les drones (cône total 180°)
const SWAY_AMP := 0.38       # rad (~22°) : amplitude du balancement dans le cône
const SWAY_SPEED := 0.5      # vitesse du balancement
const KNOCKBACK := 2.5       # m/s par point de dégât : impulsion de recul à l'impact (revolver léger, plasma/grenade lourds)
# Archétypes d'ennemis (variété de combat). BOSS = un seul drone géant à fenêtres de vulnérabilité.
const ARCH_STANDARD := 0
const ARCH_HEAVY := 1        # lourd : gros, lent, très résistant
const ARCH_DARTER := 2       # rapide : petit, vif, esquive (balancement ample), peu de PV
const ARCH_SHIELDED := 3     # bouclier frontal : bloque le hitscan de face (tourne LENTEMENT => flanquable) ; missile traverse
const ARCH_BOSS := 4         # BOSS : géant blindé ; vulnérable seulement pendant sa CHARGE (télégraphe) ; missile traverse
const BOSS_ORBIT_TIME := 7.0 # s : phase orbite (blindé)
const BOSS_VULN_TIME := 2.5  # s : fenêtre de vulnérabilité (charge télégraphée)
const BOSS_ARMOR := 0.22     # multiplicateur de dégât hitscan hors fenêtre (blindage)
const PEN_DMG := 100.0       # dégât >= ce seuil (= missile) => TRAVERSE bouclier/blindage (marche aussi en coop : montant rapporté)
const TURN_SLOW_RATE := 1.2  # vitesse de rotation des ennemis « lents » (SHIELDED/BOSS) — permet de les flanquer

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
var net_id := 0                 # coop : id réseau (assigné par CoopCombat côté hôte ; 0 = solo)
var remote := false             # coop : true = drone-FANTÔME (invité) — pas d'IA, positionné par CoopCombat
var _rng := RandomNumberGenerator.new()
# Archétype + modulateurs dérivés.
var archetype := ARCH_STANDARD
var _scale_mult := 1.0
var _speed_mult := 1.0
var _hp_mult := 1.0
var _fire_mult := 1.0
var _sway_mult := 1.0
var _turn_slow := false
var _tint := Color(1.0, 0.3, 0.2)
var _hp_max := HP_BASE
# Bouclier frontal (SHIELDED).
var _shield_vis: MeshInstance3D
var _shield_flash := 0.0
# Boss.
var _boss := false
var _vulnerable := false
var _boss_t := BOSS_ORBIT_TIME
var _boss_bar: Label3D
var _boss_bar_pct := -1        # dernier % affiché (n'écrit le Label3D qu'au CHANGEMENT => pas de re-layout/frame)
var _boss_bar_vuln := false

# Appelé par le WaveManager AVANT add_child : position de spawn + niveau (difficulté).
func setup(player: Node3D, spawn_pos: Vector3, level: int, arch := 0) -> void:
	_player = player
	_pending_pos = spawn_pos
	archetype = arch
	_apply_archetype()
	var base_hp: float = (HP_BASE + float(level - 1) * HP_PER_WAVE) * _hp_mult
	hp = base_hp
	_hp_max = base_hp
	_fire_interval = maxf((2.6 - float(level - 1) * 0.25) * _fire_mult, 0.8)

# Dérive les modulateurs (échelle, vitesse, PV, cadence, teinte, comportement) de l'archétype.
func _apply_archetype() -> void:
	match archetype:
		ARCH_HEAVY:
			_scale_mult = 1.6; _speed_mult = 0.6; _hp_mult = 3.0; _fire_mult = 1.6; _sway_mult = 0.5
			_tint = Color(0.95, 0.2, 0.45)
		ARCH_DARTER:
			_scale_mult = 0.7; _speed_mult = 1.8; _hp_mult = 0.5; _fire_mult = 0.7; _sway_mult = 2.0
			_tint = Color(1.0, 0.6, 0.1)
		ARCH_SHIELDED:
			_scale_mult = 1.1; _speed_mult = 0.8; _hp_mult = 1.5; _fire_mult = 1.1; _turn_slow = true
			_tint = Color(0.3, 0.7, 1.0)
		ARCH_BOSS:
			_scale_mult = 3.5; _speed_mult = 0.5; _hp_mult = 14.0; _fire_mult = 1.4; _sway_mult = 0.4
			_tint = Color(1.0, 0.25, 0.15); _boss = true; _turn_slow = true
		_:
			pass

# Dôme-bouclier frontal (SHIELDED) : additif, bloque le hitscan de face.
func _build_shield() -> void:
	_shield_vis = MeshInstance3D.new()
	_shield_vis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := SphereMesh.new()
	sm.radius = SHIP_SIZE * 0.6 * _scale_mult
	sm.height = SHIP_SIZE * 1.2 * _scale_mult
	sm.is_hemisphere = true
	sm.radial_segments = 16
	sm.rings = 6
	_shield_vis.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.3, 0.7, 1.0, 0.22)
	_shield_vis.material_override = mat
	_shield_vis.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)   # dôme (+Y) tourné vers l'AVANT (-Z)
	_shield_vis.position = Vector3(0.0, 0.0, -SHIP_SIZE * 0.3 * _scale_mult)
	add_child(_shield_vis)

# Barre de PV du boss (Label3D billboard au-dessus).
func _build_boss_bar() -> void:
	_boss_bar = Label3D.new()
	_boss_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_boss_bar.no_depth_test = true
	_boss_bar.fixed_size = true
	_boss_bar.pixel_size = 0.0016
	_boss_bar.modulate = Color(1.0, 0.4, 0.3)
	_boss_bar.outline_size = 14
	_boss_bar.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	_boss_bar.position = Vector3(0.0, SHIP_SIZE * 0.95 * _scale_mult, 0.0)
	_boss_bar.text = "BOSS"
	add_child(_boss_bar)

# Modèle selon l'archétype : low-poly léger pour les drones COURANTS, GLB détaillé pour lourd/bouclier/boss.
func _model_path() -> String:
	if archetype == ARCH_HEAVY or archetype == ARCH_SHIELDED or _boss:
		return SHIP_MODEL
	return SHIP_MODEL_LIGHT if ResourceLoader.exists(SHIP_MODEL_LIGHT) else SHIP_MODEL

# Fit (centre + plus grande dimension) d'un modèle, calculé UNE SEULE FOIS par chemin puis mis en CACHE (statique
# => partagé par tous les drones) : évite la marche d'AABB récursive à chaque spawn.
static var _fit_cache := {}
func _model_fit(path: String, inst: Node3D) -> Dictionary:
	if _fit_cache.has(path):
		return _fit_cache[path]
	var r := CombatUtil.scene_aabb(inst, Transform3D.IDENTITY)
	var fit := {"center": Vector3.ZERO, "longest": 1.0}
	if r.has and r.box.size.length() > 0.0001:
		var ab: AABB = r.box
		fit.center = ab.get_center()
		fit.longest = maxf(maxf(ab.size.x, ab.size.y), ab.size.z)
	_fit_cache[path] = fit
	return fit
var _pending_pos := Vector3.ZERO

func _ready() -> void:
	add_to_group("drone")   # cible pour le verrou missile (réel ET fantôme coop)
	_rng.randomize()
	global_position = _pending_pos
	if _player:
		_alt = _pending_pos.y - _player.global_position.y
	_base_ang = _rng.randf_range(-1.0, 1.0) * FRONT_HALF * 0.85   # réparti dans le cône avant
	_phase = _rng.randf() * TAU
	_orbit = ORBIT_DIST + _rng.randf_range(-1.5, 3.5)   # certains s'approchent à ~6 m, d'autres ~11 m
	_fire_cd = 1.0 + _rng.randf() * 1.5
	# Visuel : modèle auto-échelle (envergure SHIP_SIZE) + centré + ombres off. Drones COURANTS = mesh LOW-POLY léger
	# (perf), lourd/bouclier/boss = GLB détaillé. Le fit (centre+taille) est calculé UNE FOIS par modèle (cache statique).
	_visual = Node3D.new()
	var path := _model_path()
	var model = load(path)
	var inst: Node3D = null
	if model is PackedScene:
		inst = (model as PackedScene).instantiate()
	elif model is Mesh:
		var lm := MeshInstance3D.new()
		lm.mesh = model
		inst = lm
	if inst != null:
		_visual.add_child(inst)
		CombatUtil.disable_shadows(inst)
		var fit := _model_fit(path, inst)
		var s: float = (SHIP_SIZE * _scale_mult) / maxf(fit.longest, 0.0001)
		inst.position = -(fit.center as Vector3)   # centre le modèle (avant la mise à l'échelle du conteneur)
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
	_glow.light_color = _tint
	_glow.omni_range = SHIP_SIZE * 1.8 * _scale_mult
	_glow.light_energy = 0.0          # éteinte au repos : ne s'allume QUE en charge/flash (peu de lights simultanées)
	_glow.shadow_enabled = false
	_glow.visible = false
	add_child(_glow)
	# Cœur émissif rouge : tell d'ennemi TOUJOURS visible, additif, SANS lumière dynamique => coût nul en lights.
	_core = MeshInstance3D.new()
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cs := SphereMesh.new()
	cs.radius = SHIP_SIZE * 0.12 * _scale_mult
	cs.height = SHIP_SIZE * 0.24 * _scale_mult
	cs.radial_segments = 8
	cs.rings = 4
	_core.mesh = cs
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_core_mat.albedo_color = Color(_tint.r, _tint.g, _tint.b, 0.55)
	_core.material_override = _core_mat
	add_child(_core)
	# Collision (sphère) pour le raycast du blaster.
	var col := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = SHIP_SIZE * 0.55 * _scale_mult
	col.shape = sh
	add_child(col)
	# Archétype : bouclier frontal (SHIELDED) + barre de PV + orbite plus large (BOSS).
	if archetype == ARCH_SHIELDED:
		_build_shield()
	if _boss:
		_orbit = 16.0
		_alt += 4.0
		_build_boss_bar()
	# Apparition : pop d'échelle + bref flash lumineux (télégraphe « un drone arrive »).
	_target_scale = _visual.scale
	_visual.scale = _target_scale * 0.08
	if remote:   # drone-fantôme (invité) : pleine échelle immédiate, pas de pop ni de flash d'apparition (déjà fait chez l'hôte)
		_spawn_t = 0.0
		_visual.scale = _target_scale
		return
	var spawn_fl := OmniLight3D.new()
	spawn_fl.light_color = Color(1.0, 0.5, 0.4)
	spawn_fl.omni_range = 6.0
	spawn_fl.light_energy = 8.0
	spawn_fl.shadow_enabled = false
	add_child(spawn_fl)
	get_tree().create_timer(0.18).timeout.connect(spawn_fl.queue_free)

func _process(delta: float) -> void:
	if remote:
		return   # drone-fantôme : positionné par CoopCombat (aucune IA locale)
	if GameState.options_open:
		return   # menu ouvert => combat en pause (cohérent avec le gel du joueur)
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
	# Boss : cycle ORBITE (blindé) -> CHARGE (vulnérable, télégraphe) -> salve, en boucle.
	var boss_charging := false
	if _boss:
		_boss_t -= delta
		if _boss_t <= 0.0:
			if _vulnerable:
				_vulnerable = false
				_boss_t = BOSS_ORBIT_TIME
				_boss_volley(p)          # fin de charge => grosse salve
			else:
				_vulnerable = true
				_boss_t = BOSS_VULN_TIME
		boss_charging = _vulnerable
	# Position dans un CÔNE de 180° DEVANT le joueur : forward joueur + azimut de base (réparti) + balancement.
	var fwd := CombatUtil.front_dir(_player)
	var ang := clampf(_base_ang + sin(_t * SWAY_SPEED + _phase) * SWAY_AMP * _sway_mult, -FRONT_HALF, FRONT_HALF)
	var dir := fwd.rotated(Vector3.UP, ang)
	var target := p + dir * _orbit + Vector3.UP * (_alt + sin(_t * 1.3) * 1.5)
	var desired := target - global_position
	var spd := SPEED * _speed_mult * (0.15 if boss_charging else 1.0)   # le boss se fige quasiment pendant sa charge
	if desired.length() > 0.01:
		_vel = _vel.lerp(desired.normalized() * spd, clampf(2.0 * delta, 0.0, 1.0))
	global_position += _vel * delta
	# Orientation vers le joueur. Ennemis « lents » (SHIELDED/BOSS) : virage PROGRESSIF => FLANQUABLES.
	var flat := Vector2(p.x - global_position.x, p.z - global_position.z)
	if flat.length() > 0.5:
		var tb := global_transform.looking_at(p, Vector3.UP).basis
		var rate := TURN_SLOW_RATE if _turn_slow else 99.0
		global_transform.basis = global_transform.basis.slerp(tb, clampf(rate * delta, 0.0, 1.0)).orthonormalized()
	# Tell visuel : cœur additif TOUJOURS visible ; lumière dynamique seulement en flash/charge. Teinte = archétype.
	var lit := 0.0
	var warm := _tint
	if _flash_t > 0.0:
		_flash_t -= delta
		lit = clampf(_flash_t / 0.12, 0.0, 1.0)
		warm = _tint.lerp(Color(1.0, 0.9, 0.7), lit)
	elif boss_charging:
		lit = 1.0                                   # fenêtre de vulnérabilité : blanc-chaud (tape ICI / ou missile)
		warm = Color(1.0, 0.95, 0.85)
	else:
		lit = clampf(1.0 - _fire_cd / CHARGE_TIME, 0.0, 1.0) if _fire_cd < CHARGE_TIME else 0.0
		warm = _tint.lerp(Color(1.0, 0.55, 0.2), lit)
	if _core_mat:
		_core_mat.albedo_color = Color(warm.r, warm.g, warm.b, 0.45 + 0.5 * lit)
	if _glow:
		var glow_on := lit > 0.05
		_glow.visible = glow_on
		if glow_on:
			_glow.light_color = warm
			_glow.light_energy = (8.5 if _boss else 5.5) * lit
	# Bouclier frontal : flash bleu à l'interception (décroît).
	if _shield_vis:
		_shield_flash = maxf(_shield_flash - delta, 0.0)
		var sa := 0.22 + 0.6 * clampf(_shield_flash / 0.2, 0.0, 1.0)
		(_shield_vis.material_override as StandardMaterial3D).albedo_color = Color(0.3, 0.7, 1.0, sa)
	# Barre de PV du boss.
	if _boss_bar:
		var pct := int(clampf(hp / maxf(_hp_max, 0.001), 0.0, 1.0) * 100.0)
		if pct != _boss_bar_pct or boss_charging != _boss_bar_vuln:   # ne reconstruit le texte qu'au changement
			_boss_bar_pct = pct
			_boss_bar_vuln = boss_charging
			_boss_bar.text = ("BOSS  %d%%  - VULNERABLE" % pct) if boss_charging else ("BOSS  %d%%" % pct)
	# Tir vers le joueur (cadence normale ; le boss ajoute ses salves en fin de charge).
	_fire_cd -= delta
	if _fire_cd <= 0.0:
		_fire_cd = _fire_interval
		if fire_cb.is_valid():
			fire_cb.call(global_position, p + Vector3.UP * 1.3)

# Salve lourde du boss (4 bolts en éventail) tirée à la fin de sa fenêtre de charge.
func _boss_volley(p: Vector3) -> void:
	if not fire_cb.is_valid():
		return
	for off in [-0.3, -0.1, 0.1, 0.3]:
		var d := (p + Vector3.UP * 1.3) - global_position
		if d.length() < 0.01:
			continue
		d = d.normalized().rotated(Vector3.UP, off)
		fire_cb.call(global_position, global_position + d * 40.0)

# Le tir vient-il de l'AVANT du drone (pour le bouclier frontal) ? (drone face -Z ; tourne lentement => flanquable)
func _is_frontal() -> bool:
	if _player == null:
		return false
	var front := -global_transform.basis.z
	front.y = 0.0
	var to_p := _player.global_position - global_position
	to_p.y = 0.0
	if front.length() < 0.01 or to_p.length() < 0.01:
		return false
	return front.normalized().dot(to_p.normalized()) > 0.45   # ~63° d'arc frontal

# Appelé par PlayerController quand le blaster touche ce drone (raycast). amount = dégâts, pos = point d'impact.
func take_damage(amount: float, pos: Vector3) -> void:
	if _dead:
		return
	if remote:   # drone-fantôme : rapporte le coup à l'HÔTE (autorité) + étincelle locale ; pas de PV/mort local
		var sp0 = preload("res://scripts/HitSpark.gd").new()
		sp0.play(pos)
		get_parent().add_child(sp0)
		CoopCombat.client_report_hit(net_id, amount)
		return
	var pen := amount >= PEN_DMG   # missile (gros dégât) => TRAVERSE bouclier/blindage (montant préservé même en coop)
	# Bouclier frontal : intercepte le hitscan venu de l'AVANT (=> flanquer le drone, ou lui envoyer un missile).
	if archetype == ARCH_SHIELDED and not pen and _is_frontal():
		_shield_flash = 0.2
		var spb = preload("res://scripts/HitSpark.gd").new()
		spb.play(pos)
		get_parent().add_child(spb)
		AudioEngine.play_impact(pos, 0.3)   # « clink » d'interception
		return
	# Boss : BLINDÉ hors fenêtre de vulnérabilité (le hitscan ne fait presque rien) => taper pendant sa CHARGE, ou missile.
	if _boss and not pen and not _vulnerable:
		amount *= BOSS_ARMOR
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
	died.emit(global_position)   # le WaveManager lit `archetype` directement (drone encore valide) via .bind(self)
	queue_free()
