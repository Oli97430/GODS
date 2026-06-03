extends MeshInstance3D
## Bouclier d'énergie (mode combat, façon Space Pirate Trainer) : panneau translucide CURVÉ tenu en main
## GAUCHE, déployé EN MÊME TEMPS que le blaster. AUTO-CONTENU (mesh courbé + shader énergie). PlayerController
## le montre/masque avec l'arme et le fait suivre la main gauche. La face bombée (+normale) pointe vers
## l'AVANT (-Z) = vers l'ennemi. (En CP3 il bloquera les tirs ennemis venant de face.)

const WIDTH := 0.44
const HEIGHT := 0.56
const CURVE := 0.075    # m : profondeur de l'arc (bombe vers l'avant -Z)
const NX := 10
const NY := 12

var _mat: ShaderMaterial
var _flash := 0.0   # intensité du flash d'interception (0..1), décroît dans _process

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = _shield_mesh()
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/energy_shield.gdshader")
	material_override = _mat
	visible = false

# Flash d'interception (appelé par PlayerController quand le bouclier bloque un tir).
func flash() -> void:
	_flash = 1.0

func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta / 0.18, 0.0)
		if _mat:
			_mat.set_shader_parameter("hit_flash", _flash)

func _shield_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in NY - 1:
		for i in NX - 1:
			var p00 := _vert(i, j)
			var p10 := _vert(i + 1, j)
			var p11 := _vert(i + 1, j + 1)
			var p01 := _vert(i, j + 1)
			var u0 := float(i) / float(NX - 1)
			var u1 := float(i + 1) / float(NX - 1)
			var v0 := float(j) / float(NY - 1)
			var v1 := float(j + 1) / float(NY - 1)
			st.set_uv(Vector2(u0, v0)); st.add_vertex(p00)
			st.set_uv(Vector2(u1, v0)); st.add_vertex(p10)
			st.set_uv(Vector2(u1, v1)); st.add_vertex(p11)
			st.set_uv(Vector2(u0, v0)); st.add_vertex(p00)
			st.set_uv(Vector2(u1, v1)); st.add_vertex(p11)
			st.set_uv(Vector2(u0, v1)); st.add_vertex(p01)
	st.generate_normals()
	return st.commit()

func _vert(i: int, j: int) -> Vector3:
	var fx := float(i) / float(NX - 1) - 0.5   # -0.5 .. 0.5
	var fy := float(j) / float(NY - 1) - 0.5
	var z := -CURVE * (1.0 - pow(2.0 * fx, 2.0))   # bombe vers l'avant (-Z), plat aux bords
	return Vector3(fx * WIDTH, fy * HEIGHT, z)
