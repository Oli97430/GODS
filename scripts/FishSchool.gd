extends MultiMeshInstance3D
## Banc de poissons SOUS-MARIN : boids nageant en banc autour du joueur. AUTO-CONTENU et PARAMÉTRABLE
## (plusieurs espèces : taille / couleur / nombre / vitesse / bande de profondeur) => SurfaceView en sème
## plusieurs. Visible seulement SOUS L'EAU ; bande verticale re-bornée pour rester sous la surface. top_level
## => volume player-RELATIF (insensible au rebase). Vie ambiante, non déterministe. Sim O(N²) négligeable.
##
## Réglages d'ESPÈCE à fixer AVANT add_child : count, radius, y_low, y_high, speed, fish_scale,
## body_color (Vector3), wiggle_speed.

const SEA_Y := 0.0          # Y monde de la surface de mer (DEFAULT_SEA_LEVEL=0)
const SURFACE_MARGIN := 0.8 # m : les poissons restent au moins si loin sous la surface
const W_COH := 0.7
const W_ALI := 0.9
const W_SEP := 1.5
const SEP_DIST := 2.2
const W_BOUND := 1.4

# Espèce (défauts = petit banc argenté).
var count := 34
var radius := 20.0
var y_low := -3.5
var y_high := 7.0
var speed := 3.0
var max_speed := 4.8
var fish_scale := 1.0
var body_color := Vector3(0.55, 0.62, 0.72)
var wiggle_speed := 6.0

var _pos: PackedVector3Array
var _vel: PackedVector3Array
var _rng := RandomNumberGenerator.new()
var _ymax := 7.0

func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rng.randomize()
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = _fish_mesh()
	multimesh.instance_count = count
	_pos = PackedVector3Array(); _pos.resize(count)
	_vel = PackedVector3Array(); _vel.resize(count)
	for i in count:
		var ang := _rng.randf() * TAU
		var rad := _rng.randf() * radius * 0.5
		_pos[i] = Vector3(cos(ang) * rad, _rng.randf_range(y_low, y_high * 0.4), sin(ang) * rad)
		var d := Vector3(_rng.randf() * 2.0 - 1.0, 0.0, _rng.randf() * 2.0 - 1.0)
		_vel[i] = (d.normalized() if d.length() > 0.01 else Vector3.FORWARD) * speed
		multimesh.set_instance_custom_data(i, Color(_rng.randf(), 0.0, 0.0, 0.0))   # .x = phase d'ondulation
	var smat := ShaderMaterial.new()
	smat.shader = preload("res://shaders/fish.gdshader")
	smat.set_shader_parameter("body", body_color)
	smat.set_shader_parameter("wiggle_speed", wiggle_speed)
	material_override = smat
	visible = false

func _fish_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := fish_scale
	# Silhouette plate (plan Y-Z, fine en X), tête +Z, queue -Z. cull_disabled => double face.
	var nose := Vector3(0.0, 0.0, 0.28) * s
	var top := Vector3(0.0, 0.11, 0.0) * s
	var bot := Vector3(0.0, -0.11, 0.0) * s
	var tail_base := Vector3(0.0, 0.0, -0.16) * s
	var tail_top := Vector3(0.0, 0.15, -0.30) * s
	var tail_bot := Vector3(0.0, -0.15, -0.30) * s
	for v in [nose, top, tail_base, nose, tail_base, bot, tail_base, tail_top, tail_bot]:
		st.add_vertex(v)
	st.generate_normals()
	return st.commit()

# center = position joueur ; submerged 0..1 (les poissons n'apparaissent que sous l'eau) ; delta.
func update(center: Vector3, submerged: float, delta: float) -> void:
	if submerged < 0.08:
		if visible:
			visible = false
		return
	visible = true
	global_transform = Transform3D(Basis(), center)
	_ymax = minf(y_high, (SEA_Y - SURFACE_MARGIN) - center.y)   # rester sous la surface (player-relative)
	if _ymax < y_low + 1.0:
		_ymax = y_low + 1.0
	_step(minf(delta, 0.05))

func _step(dt: float) -> void:
	var centroid := Vector3.ZERO
	var avgv := Vector3.ZERO
	for i in count:
		centroid += _pos[i]
		avgv += _vel[i]
	centroid /= float(count)
	avgv /= float(count)
	for i in count:
		var p := _pos[i]
		var a := (centroid - p) * W_COH + (avgv - _vel[i]) * W_ALI
		for j in count:
			if j == i:
				continue
			var dd := p - _pos[j]
			var dl := dd.length()
			if dl > 0.001 and dl < SEP_DIST:
				a += (dd / (dl * dl)) * W_SEP
		var horiz := Vector3(p.x, 0.0, p.z)
		if horiz.length() > radius:
			a += -horiz.normalized() * W_BOUND * speed
		if p.y < y_low:
			a.y += W_BOUND * speed
		elif p.y > _ymax:
			a.y -= W_BOUND * speed
		var v := _vel[i] + a * dt
		var sp := v.length()
		if sp > max_speed:
			v = v / sp * max_speed
		elif sp < speed * 0.5 and sp > 0.001:
			v = v / sp * (speed * 0.6)
		_vel[i] = v
		_pos[i] = p + v * dt
		multimesh.set_instance_transform(i, Transform3D(_look_basis(v), _pos[i]))

func _look_basis(v: Vector3) -> Basis:
	var fwd := v.normalized() if v.length() > 0.001 else Vector3.FORWARD
	var up := Vector3.UP
	if absf(fwd.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var x := up.cross(fwd).normalized()
	var y := fwd.cross(x).normalized()
	return Basis(x, y, fwd)
