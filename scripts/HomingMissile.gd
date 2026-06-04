extends Node3D
## Missile à tête chercheuse — tir SECONDAIRE du plasma (munitions lootées). Lancé vers un drone VERROUILLÉ, il
## braque progressivement vers lui et le DÉTRUIT au contact (gros dégât). Cible perdue (déjà morte) => vol droit
## puis auto-destruction (LIFE). Coop : `take_damage` sur un drone-fantôme rapporte le coup à l'hôte (validé).
## AUTO-CONTENU, auto-libéré.

const SPEED := 28.0
const TURN := 4.5          # réactivité du braquage (plus haut = vire plus serré vers la cible)
const LIFE := 5.0
const HIT_DIST := 1.6      # m : distance d'impact (drone ~2.4 m)

var _vel := Vector3.ZERO
var _target: Node3D
var _dmg := 200.0
var _life := LIFE

# À appeler AVANT add_child.
func setup(from: Vector3, target: Node3D, dmg: float) -> void:
	global_position = from
	_target = target
	_dmg = dmg
	var dir := Vector3.FORWARD
	if is_instance_valid(target):
		var t := (target as Node3D).global_position - from
		if t.length() > 0.01:
			dir = t.normalized()
	_vel = dir * SPEED

func _ready() -> void:
	var body := MeshInstance3D.new()
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bm := BoxMesh.new()
	bm.size = Vector3(0.13, 0.13, 0.5)   # ogive allongée sur Z (axe de vol après look_at)
	body.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.55, 1.0, 0.62)
	body.material_override = mat
	add_child(body)
	# Lueur de réacteur (additif, à l'arrière).
	var glow := MeshInstance3D.new()
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gm := SphereMesh.new()
	gm.radius = 0.16
	gm.height = 0.32
	gm.radial_segments = 8
	gm.rings = 4
	glow.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gmat.albedo_color = Color(0.5, 1.0, 0.6, 0.85)
	glow.material_override = gmat
	glow.position = Vector3(0.0, 0.0, 0.28)   # +Z = arrière (le vol est vers -Z)
	add_child(glow)
	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 1.0, 0.6)
	light.omni_range = 4.5
	light.light_energy = 2.4
	light.shadow_enabled = false
	add_child(light)
	# Traînée : particules additives qui restent dans le MONDE (local_coords=false) => sillage derrière l'ogive.
	var trail := GPUParticles3D.new()
	trail.amount = 28
	trail.lifetime = 0.5
	trail.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 0.0, 1.0)   # émission vers l'ARRIÈRE (le vol est vers -Z)
	pm.spread = 6.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var grad := Gradient.new()
	grad.set_color(0, Color(0.6, 1.0, 0.7, 0.55))
	grad.set_color(1, Color(0.4, 0.85, 0.6, 0.0))   # fondu en transparence sur la durée de vie
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	trail.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.22, 0.22)
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	tmat.vertex_color_use_as_albedo = true
	tmat.albedo_color = Color(0.5, 1.0, 0.6)
	qm.material = tmat
	trail.draw_pass_1 = qm
	add_child(trail)

func _process(delta: float) -> void:
	if GameState.options_open:
		return
	_life -= delta
	if is_instance_valid(_target):
		var to := (_target as Node3D).global_position - global_position
		var dist := to.length()
		if dist <= HIT_DIST:
			_hit()
			return
		# Braquage : on tourne le vecteur vitesse vers la cible (tête chercheuse).
		var nd := _vel.normalized().lerp(to.normalized(), clampf(TURN * delta, 0.0, 1.0))
		if nd.length() > 0.001:
			_vel = nd.normalized() * SPEED
	global_position += _vel * delta
	var d := _vel.normalized()
	if absf(d.dot(Vector3.UP)) < 0.98:
		look_at(global_position + _vel, Vector3.UP)   # oriente l'ogive dans le sens du vol
	if _life <= 0.0:
		_explode()
		queue_free()

func _hit() -> void:
	if is_instance_valid(_target) and _target.has_method("take_damage"):
		_target.take_damage(_dmg, global_position)   # solo : détruit ; coop invité : rapporte le coup à l'hôte
	_explode()
	queue_free()

func _explode() -> void:
	var sc := get_tree().current_scene
	if sc:
		var ex = preload("res://scripts/Explosion.gd").new()
		sc.add_child(ex)
		ex.global_position = global_position
		ex.play(1.1)
	AudioEngine.play_impact(global_position, 0.85)
