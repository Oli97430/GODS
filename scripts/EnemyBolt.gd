extends Node3D
## Bolt ennemi (tir de drone) : projectile rouge lent qui file vers la position du joueur au moment du tir
## (esquivable). À l'arrivée près du joueur => callback de toucher (haptique en CP2 ; dégâts en CP3). Le
## bouclier le bloquera en CP3. AUTO-CONTENU, auto-libéré.

const SPEED := 16.0
const LIFE := 4.0
const HIT_DIST := 0.8

var _vel := Vector3.ZERO
var _life := LIFE
var _player: Node3D
var _hit_cb: Callable
var dmg := 9.0   # dégâts infligés au joueur (réglés par WaveManager selon la vague)

func setup(from: Vector3, toward: Vector3, player: Node3D, hit_cb: Callable) -> void:
	global_position = from
	var dir := toward - from
	_vel = (dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD) * SPEED
	_player = player
	_hit_cb = hit_cb

func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.25, 0.2, 0.95)
	mi.material_override = mat
	add_child(mi)
	var gl := OmniLight3D.new()
	gl.light_color = Color(1.0, 0.3, 0.2)
	gl.omni_range = 2.0
	gl.light_energy = 1.5
	gl.shadow_enabled = false
	add_child(gl)

func _process(delta: float) -> void:
	if GameState.options_open:
		return   # menu ouvert => combat en pause (cohérent avec le gel du joueur)
	var prev := global_position
	global_position += _vel * delta
	_life -= delta
	# Occlusion terrain : le bolt ne traverse pas le décor (pas de tir « à travers la colline »).
	var space := get_world_3d().direct_space_state
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(prev, global_position)
		q.collide_with_areas = false   # ignore drones (Area3D) + bouclier (géré à part) : seul le terrain bloque
		if _player != null and is_instance_valid(_player) and _player is CollisionObject3D:
			q.exclude = [(_player as CollisionObject3D).get_rid()]
		if not space.intersect_ray(q).is_empty():
			queue_free()
			return
	if _player != null and is_instance_valid(_player):
		# Le bouclier intercepte-t-il ce bolt ? (déployé + interposé devant la tête) => détruit sans dégâts.
		if _player.has_method("shield_intercept") and _player.shield_intercept(global_position):
			queue_free()
			return
		var head := _player.global_position + Vector3.UP * 1.4
		if global_position.distance_to(head) < HIT_DIST:
			if _hit_cb.is_valid():
				_hit_cb.call(global_position, dmg, _vel)   # _vel => sens du tir (indicateur directionnel)
			queue_free()
			return
	if _life <= 0.0:
		queue_free()
