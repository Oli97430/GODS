extends MultiMeshInstance3D
## Rais de lumière sous-marins (god rays) : grands quads verticaux additifs, orientés vers la caméra (CPU,
## N petit), suspendus autour du joueur (player-relative, top_level => insensible au rebase). Visibles
## seulement SOUS L'EAU et de JOUR ; s'estompent en profondeur. AUTO-CONTENU. Piloté par SurfaceView.

const N := 10
const RADIUS := 13.0      # m : rayon du semis autour du joueur
const CENTER_Y := 3.0     # m : centre vertical (un peu au-dessus du joueur, vers la surface)

var _offsets: PackedVector3Array
var _rng := RandomNumberGenerator.new()
var _mat: ShaderMaterial

func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rng.randomize()
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _shaft_mesh()
	multimesh.instance_count = N
	_offsets = PackedVector3Array()
	_offsets.resize(N)
	for i in N:
		var ang := _rng.randf() * TAU
		var rad := sqrt(_rng.randf()) * RADIUS
		_offsets[i] = Vector3(cos(ang) * rad, CENTER_Y + _rng.randf_range(-1.5, 1.5), sin(ang) * rad)
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/light_shaft.gdshader")
	material_override = _mat
	visible = false

func _shaft_mesh() -> ArrayMesh:
	# Quad vertical face +Z : largeur ~3.2 m (x ±1.6), hauteur ~18 m (y ±9). UV.y : 0 bas -> 1 haut (surface).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := 1.6
	var hh := 9.0
	var a := Vector3(-hw, -hh, 0.0)
	var b := Vector3(hw, -hh, 0.0)
	var c := Vector3(hw, hh, 0.0)
	var d := Vector3(-hw, hh, 0.0)
	st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(a)
	st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(b)
	st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(c)
	st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(a)
	st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(c)
	st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(d)
	return st.commit()

# center = joueur ; cam_pos = caméra (orientation) ; sun_up01 = jour 0..1 ; submerged, depth01 0..1.
func update(center: Vector3, cam_pos: Vector3, sun_up01: float, submerged: float, depth01: float, _delta: float) -> void:
	var intensity := sun_up01 * submerged * (1.0 - 0.75 * depth01)
	if intensity < 0.02:
		if visible:
			visible = false
		return
	visible = true
	global_transform = Transform3D(Basis(), center)
	_mat.set_shader_parameter("intensity", intensity)
	for i in N:
		var lp := _offsets[i]
		var fwd := cam_pos - (center + lp)
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
		var x := Vector3.UP.cross(fwd).normalized()   # quad face +Z = fwd, up = Y monde
		multimesh.set_instance_transform(i, Transform3D(Basis(x, Vector3.UP, fwd), lp))
