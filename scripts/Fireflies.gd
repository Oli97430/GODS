extends MultiMeshInstance3D
## Lucioles / spores nocturnes : nuée de petites lueurs additives qui dérivent autour du joueur la nuit.
## AUTO-CONTENU (ne touche à rien d'existant) : top_level => suit le joueur ; la dérive + le scintillement
## sont faits DANS le shader (firefly.gdshader) => zéro CPU par frame. Densité visible pilotée par le
## facteur nuit (SurfaceView.update). S'efface le jour. Vie ambiante, non déterministe (comme les météores).

const N := 90            # nombre de lucioles dans la nuée
const RADIUS := 11.0     # m : rayon horizontal de la nuée autour du joueur
const Y_MIN := 0.3       # m : hauteur basse
const Y_MAX := 4.5       # m : hauteur haute

var _mat: ShaderMaterial
var _amount := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rng.randomize()
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)   # le shader met à l'échelle par INSTANCE_CUSTOM.z
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = N
	for i in N:
		var ang := _rng.randf() * TAU
		var rad := sqrt(_rng.randf()) * RADIUS   # sqrt => répartition uniforme en disque
		var pos := Vector3(cos(ang) * rad, _rng.randf_range(Y_MIN, Y_MAX), sin(ang) * rad)
		mm.set_instance_transform(i, Transform3D(Basis(), pos))
		# .x phase scintillement · .y phase dérive · .z échelle · .w teinte (vert<->ambre)
		mm.set_instance_custom_data(i, Color(_rng.randf(), _rng.randf(), _rng.randf(), _rng.randf()))
	multimesh = mm
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/firefly.gdshader")
	material_override = _mat
	visible = false

# center = position joueur ; night 0..1 (densité visible). Lissage doux (fondu crépuscule).
func update(center: Vector3, night: float, delta: float) -> void:
	_amount = move_toward(_amount, clampf(night, 0.0, 1.0), delta * 1.2)
	if _amount < 0.01:
		if visible:
			visible = false
		return
	visible = true
	global_transform = Transform3D(Basis(), center)
	_mat.set_shader_parameter("amount", _amount)
