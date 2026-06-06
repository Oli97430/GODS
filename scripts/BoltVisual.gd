extends Node3D
## Bolt VISUEL d'arme hitscan (ressenti « projectile ») : orbe lumineux qui file de la bouche jusqu'au point
## d'impact, avec une traînée additive, puis éclate (flash) à l'arrivée. Les dégâts sont déjà appliqués par le
## hitscan — ce bolt est PUREMENT visuel. Couleur/largeur/vitesse par arme. AUTO-CONTENU, auto-libéré.

const TRAIL_LEN := 1.6   # m : longueur de la traînée derrière l'orbe

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _col := Color(0.5, 1.0, 0.6)
var _speed := 130.0
var _width := 0.12
var _dir := Vector3.FORWARD
var _dist := 0.0
var _travelled := 0.0
var _core: MeshInstance3D
var _trail: MeshInstance3D
var _trail_mat: StandardMaterial3D
var _light: OmniLight3D

# Appelé AVANT add_child : départ (bout du canon) → arrivée (point d'impact hitscan) + couleur/vitesse/largeur.
func setup(from: Vector3, to: Vector3, col: Color, speed: float, width: float) -> void:
	_from = from
	_to = to
	_col = col
	_speed = speed
	_width = width
	var d := to - from
	_dist = d.length()
	_dir = d / _dist if _dist > 0.001 else Vector3.FORWARD

func _ready() -> void:
	global_position = _from
	# Orbe (cœur plus blanc, additif).
	_core = MeshInstance3D.new()
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := SphereMesh.new()
	sm.radius = _width
	sm.height = _width * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	_core.mesh = sm
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	cm.albedo_color = _col.lerp(Color(1, 1, 1, 1), 0.55)
	_core.material_override = cm
	add_child(_core)
	# Traînée (box étirée, additive, top_level => repère monde).
	_trail = MeshInstance3D.new()
	_trail.top_level = true
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 1, 1)
	_trail.mesh = bm
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_trail_mat.albedo_color = Color(_col.r, _col.g, _col.b, 0.5)
	_trail.material_override = _trail_mat
	add_child(_trail)
	# Lueur qui suit l'orbe.
	_light = OmniLight3D.new()
	_light.light_color = _col
	_light.omni_range = 3.2
	_light.light_energy = 4.0
	_light.shadow_enabled = false
	add_child(_light)

func _process(delta: float) -> void:
	# Sortie de surface / fin de combat : on retire le bolt en vol (parenté à current_scene, non nettoyé par WaveManager).
	if not GameState.combat_active or GameState.current_scale != GameState.Scale.SURFACE:
		queue_free()
		return
	_travelled += _speed * delta
	if _travelled >= _dist:
		_impact()
		return
	var pos := _from + _dir * _travelled
	global_position = pos
	var tail_len := minf(TRAIL_LEN, _travelled)
	if tail_len > 0.01:
		var tail := pos - _dir * tail_len
		var mid := (tail + pos) * 0.5
		_trail.global_transform = Transform3D(CombatUtil.look_basis(_dir).scaled(Vector3(_width * 0.9, _width * 0.9, tail_len)), mid)
		_trail.visible = true
	else:
		_trail.visible = false

func _impact() -> void:
	var fl := OmniLight3D.new()
	fl.light_color = _col
	fl.omni_range = 3.6
	fl.light_energy = 6.0
	fl.shadow_enabled = false
	get_parent().add_child(fl)
	fl.global_position = _to
	get_tree().create_timer(0.1).timeout.connect(fl.queue_free)
	AudioEngine.play_plasma_hit(_to)   # grésillement d'énergie à l'impact (bolt = arme à énergie / plasma)
	queue_free()
