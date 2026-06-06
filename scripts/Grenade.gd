extends Node3D
## Grenade explosive (lance-grenades) : projectile BALISTIQUE (soumis à la gravité) lancé depuis la bouche.
## Explose au 1er impact (terrain/drone, via raycast de trajet) OU à la fin du fusible (airburst) => dégâts de
## ZONE aux drones dans le rayon (atténués par la distance). FX explosion + boom. AUTO-CONTENU, auto-libéré.

const SPIN := 9.0   # rad/s : rotation visuelle de l'obus

var _vel := Vector3.ZERO
var _gravity := 22.0
var _life := 3.0        # fusible (s) — explose en l'air si rien touché
var _dmg := 5.0
var _blast := 6.0       # m : rayon de dégâts de zone
var _exclude: Array = []
var _dead := false
var _visual: MeshInstance3D
var _glow: OmniLight3D
var _pending_from := Vector3.ZERO

# Appelé par le lance-grenades AVANT add_child : départ + direction + balistique + dégâts/zone + exclusion (joueur).
func setup(from: Vector3, dir: Vector3, speed: float, gravity: float, fuse: float, dmg: float, blast: float, exclude: Array) -> void:
	_pending_from = from
	_vel = (dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD) * speed
	_gravity = gravity
	_life = fuse
	_dmg = dmg
	_blast = blast
	_exclude = exclude

func _ready() -> void:
	global_position = _pending_from
	_visual = MeshInstance3D.new()
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	sm.radial_segments = 8
	sm.rings = 4
	_visual.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.11, 0.08)
	mat.metallic = 0.6
	mat.roughness = 0.5
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.12)
	mat.emission_energy_multiplier = 1.6
	_visual.material_override = mat
	add_child(_visual)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.5, 0.2)
	_glow.omni_range = 2.2
	_glow.light_energy = 1.4
	_glow.shadow_enabled = false
	add_child(_glow)

func _process(delta: float) -> void:
	# Combat terminé (désarmement) ou sortie de surface : on retire l'ordnance EN VOL au lieu de la laisser
	# active hors-session (elle n'est parentée qu'à current_scene, que WaveManager._clear ne nettoie pas).
	if not GameState.combat_active or GameState.current_scale != GameState.Scale.SURFACE:
		queue_free()
		return
	if _dead:
		return
	var prev := global_position
	_vel += Vector3.DOWN * _gravity * delta
	var nxt := prev + _vel * delta
	# Impact : raycast du segment parcouru (terrain OU drone Area3D). Exclut le joueur (pas d'explosion au canon).
	var space := get_world_3d().direct_space_state
	if space:
		var q := PhysicsRayQueryParameters3D.create(prev, nxt)
		q.exclude = _exclude
		q.collide_with_areas = true
		var h := space.intersect_ray(q)
		if not h.is_empty():
			global_position = h.position
			_explode()
			return
	global_position = nxt
	if _visual:
		_visual.rotate_x(SPIN * delta)
	_life -= delta
	if _life <= 0.0:
		_explode()

func _explode() -> void:
	if _dead:
		return
	_dead = true
	var ex = preload("res://scripts/Explosion.gd").new()
	get_parent().add_child(ex)
	ex.global_position = global_position
	ex.play(1.7)   # boom plus gros que la destruction d'un drone
	AudioEngine.play_impact(global_position, 1.0)
	# Dégâts de ZONE : sphère de recouvrement => drones (Area3D) dans le rayon, atténués par la distance.
	var space := get_world_3d().direct_space_state
	if space:
		var shape := SphereShape3D.new()
		shape.radius = _blast
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = shape
		params.transform = Transform3D(Basis(), global_position)
		params.collide_with_areas = true
		params.collide_with_bodies = false   # seulement les drones (Area3D) ; pas d'auto-dégât joueur
		var hits := space.intersect_shape(params, 32)
		var done := {}
		for hit in hits:
			var col = hit.collider
			if col != null and col.has_method("take_damage") and not done.has(col):
				done[col] = true
				var cpos: Vector3 = col.global_position
				var d := global_position.distance_to(cpos)
				var f := clampf(1.0 - d / maxf(_blast, 0.01), 0.3, 1.0)
				col.take_damage(_dmg * f, global_position)
	queue_free()
