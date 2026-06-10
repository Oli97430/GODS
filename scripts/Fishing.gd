class_name Fishing
extends Node3D
## Pêche depuis la CÔTE (CP-PÊCHE) : avec la canne ÉQUIPÉE, viser l'eau + gâchette = LANCER ; un bobber se
## pose sur la mer relié au bout de la canne par un fil. Après un délai aléatoire => TOUCHE (le bobber plonge
## + haptique) : re-gâchette dans la fenêtre = on FERRE et on remonte un poisson (ajouté à l'inventaire).
## Gâchette avant la touche = on remonte la ligne (rien). Détection d'eau : croisement du rayon de visée avec
## le niveau de mer LOCAL (courbé, = PlayerController.sea_level_at), validé « eau » si le sol y est immergé.

const CAST_RANGE := 24.0      # m : portée max du lancer
const CAST_MIN_DOWN := 0.05   # composante -Y mini de la visée (il faut viser vers le bas, l'eau)
const BITE_MIN := 3.5         # s : délai mini avant la touche
const BITE_MAX := 10.0        # s : délai maxi
const BITE_WINDOW := 2.4      # s : fenêtre pour ferrer après la touche
const WATER_DEPTH_MIN := 0.3  # m : le sol doit être sous la mer d'au moins ça (= vraie eau, pas la plage)
const DEEP_WATER_DEPTH := 4.0 # m : au-delà de cette profondeur au bobber = EAU PROFONDE (large / radeau) →
                              # table de prises enrichie (plus de grosses & rares, presque pas de déchet)

enum { IDLE, WAITING, BITE }

var _player: Node = null
var _chunks = null
var _state := IDLE
var _bob: MeshInstance3D
var _line: MeshInstance3D
var _bob_pos := Vector3.ZERO   # ancre du bobber sur l'eau (Y monde)
var _timer := 0.0
var _phase := 0.0
var _trig_prev := false

func setup(player: Node) -> void:
	_player = player
	top_level = true
	# Bobber (flotteur rouge/blanc).
	_bob = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	sm.radial_segments = 10
	sm.rings = 6
	_bob.mesh = sm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.90, 0.22, 0.20)
	bmat.roughness = 0.5
	_bob.material_override = bmat
	_bob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bob.visible = false
	add_child(_bob)
	# Fil (cylindre fin, orienté chaque frame entre le bout de la canne et le bobber).
	_line = MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.004
	lm.bottom_radius = 0.004
	lm.height = 1.0
	lm.radial_segments = 4
	_line.mesh = lm
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.92, 0.95, 1.0, 0.55)
	lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line.material_override = lmat
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_line.visible = false
	add_child(_line)

func update(delta: float, chunks) -> void:
	_chunks = chunks
	if _player == null or not _player.has_method("is_fishing") or not _player.is_fishing():
		_reset()
		return
	var trig: bool = _player.rod_pressed() if _player.has_method("rod_pressed") else false
	var edge := trig and not _trig_prev
	_trig_prev = trig
	var tip: Vector3 = _player.rod_tip_world() if _player.has_method("rod_tip_world") else _player.global_position
	match _state:
		IDLE:
			if edge:
				var p = _aim_water(tip)
				if p != null:
					_bob_pos = p
					_state = WAITING
					_timer = randf_range(BITE_MIN, BITE_MAX)
					_phase = 0.0
					_bob.visible = true
					_line.visible = true
					_bob.global_position = _bob_pos
					AudioEngine.play_impact(_bob_pos, 0.25)   # « plouf » du lancer
					if _player.has_method("harvest_feedback"):
						_player.harvest_feedback()
		WAITING:
			_timer -= delta
			_phase += delta
			_bob.global_position = _bob_pos + Vector3.UP * sin(_phase * 2.0) * 0.04   # flotte doucement
			if edge:
				_reset()                                       # on remonte trop tôt : rien
			elif _timer <= 0.0:
				_state = BITE
				_timer = BITE_WINDOW
				_phase = 0.0
				AudioEngine.play_impact(_bob_pos, 0.4)         # remous de la touche
				if _player.has_method("bite_feedback"):
					_player.bite_feedback()                    # haptique « ça mord »
		BITE:
			_timer -= delta
			_phase += delta
			_bob.global_position = _bob_pos + Vector3.DOWN * (0.06 + 0.04 * sin(_phase * 28.0))   # plonge + frétille
			if edge:
				_catch()
				_reset()
			elif _timer <= 0.0:
				_reset()                                       # raté (hors fenêtre)
	if _bob.visible:
		_update_line(tip, _bob.global_position)

# Point d'eau visé (ou null) : croisement du rayon de visée de la canne avec le niveau de mer local.
func _aim_water(tip: Vector3):
	var dir := Vector3.FORWARD
	if _player.has_method("rod_aim_dir"):
		dir = _player.rod_aim_dir()
	if dir.y > -CAST_MIN_DOWN:
		return null                                            # il faut viser vers le bas (l'eau)
	var sea0: float = _player.sea_level_at(tip.x, tip.z)
	var t := (sea0 - tip.y) / dir.y                            # dir.y < 0 garanti
	if t <= 0.0 or t > CAST_RANGE:
		return null
	var p := tip + dir * t
	p.y = _player.sea_level_at(p.x, p.z)                       # recale sur la mer courbée au point visé
	if tip.distance_to(p) > CAST_RANGE:
		return null
	# Valide « eau » : le sol au point visé doit être SOUS la mer (sinon c'est la plage / la terre).
	if _chunks != null and _chunks.has_method("ground_height_at"):
		if _chunks.ground_height_at(p) > p.y - WATER_DEPTH_MIN:
			return null
	return p

# Tire un poisson (pondéré). En eau PROFONDE (large / depuis un radeau) la table s'enrichit : bien plus de
# grosses prises et de rares, presque pas de déchet — la récompense de gagner le large sur un radeau.
func _catch() -> void:
	var r := randf()
	var fish := "fish_small"
	if _is_deep_water():
		if r < 0.02:
			fish = "trinket_kelp"
		elif r < 0.20:
			fish = "fish_rare"
		elif r < 0.55:
			fish = "fish_large"
		elif r < 0.85:
			fish = "fish_medium"
	else:
		if r < 0.05:
			fish = "trinket_kelp"
		elif r < 0.10:
			fish = "fish_rare"
		elif r < 0.32:
			fish = "fish_large"
		elif r < 0.62:
			fish = "fish_medium"
	Inventory.add_resource(fish, 1)
	AudioEngine.play_impact(_bob_pos, 0.5)
	if _player.has_method("catch_feedback"):
		_player.catch_feedback()

# Eau profonde au bobber ? (profondeur sol↔mer ≥ DEEP_WATER_DEPTH). Repli prudent = false si on ne peut
# pas sonder (pas de chunks / pas de sea_level_at) → table côtière par défaut, zéro régression.
func _is_deep_water() -> bool:
	if _chunks == null or not _chunks.has_method("ground_height_at"):
		return false
	if _player == null or not _player.has_method("sea_level_at"):
		return false
	var sea: float = _player.sea_level_at(_bob_pos.x, _bob_pos.z)
	return sea - _chunks.ground_height_at(_bob_pos) >= DEEP_WATER_DEPTH

# Oriente le fil (cylindre de hauteur 1) entre le bout de la canne `a` et le bobber `b`.
func _update_line(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var ln := d.length()
	if ln < 0.001:
		return
	var y := d / ln
	var x := Vector3.RIGHT
	if absf(y.dot(x)) > 0.99:
		x = Vector3.FORWARD
	var z := x.cross(y).normalized()
	x = y.cross(z).normalized()
	_line.global_transform = Transform3D(Basis(x, y * ln, z), (a + b) * 0.5)

func _reset() -> void:
	_state = IDLE
	if _bob:
		_bob.visible = false
	if _line:
		_line.visible = false
