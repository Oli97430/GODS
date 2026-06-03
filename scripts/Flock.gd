extends MultiMeshInstance3D
## Nuée d'oiseaux : boids (cohésion / alignement / séparation) volant en troupeau dans le ciel autour du
## joueur. AUTO-CONTENU et PARAMÉTRABLE (plusieurs espèces : taille / couleur / altitude / vitesse / nombre)
## => SurfaceView en sème plusieurs, variées. Visible le JOUR (complète les lucioles nocturnes). top_level
## => volume player-RELATIF (insensible au rebase). Vie ambiante, non déterministe. Sim O(N²) négligeable.
##
## Réglages d'ESPÈCE à fixer AVANT add_child (lus dans _ready) : count, radius, alt_lo, alt_hi, speed,
## bird_scale, body_color (Vector3), flap_speed.

# Comportement partagé (toutes espèces).
const W_COH := 0.6
const W_ALI := 0.8
const W_SEP := 1.4
const SEP_DIST := 3.0
const W_BOUND := 1.2

# Espèce (défauts = nuée d'origine) — surchargés par SurfaceView avant add_child.
var count := 42
var radius := 38.0
var alt_lo := 9.0
var alt_hi := 26.0
var speed := 7.0
var max_speed := 10.0
var bird_scale := 1.0
var body_color := Vector3(0.06, 0.07, 0.09)
var flap_speed := 7.0

var _pos: PackedVector3Array
var _vel: PackedVector3Array
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rng.randomize()
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = _bird_mesh()
	multimesh.instance_count = count
	_pos = PackedVector3Array(); _pos.resize(count)
	_vel = PackedVector3Array(); _vel.resize(count)
	for i in count:
		var ang := _rng.randf() * TAU
		var rad := _rng.randf() * radius * 0.5
		_pos[i] = Vector3(cos(ang) * rad, _rng.randf_range(alt_lo, alt_hi), sin(ang) * rad)
		var d := Vector3(_rng.randf() * 2.0 - 1.0, 0.0, _rng.randf() * 2.0 - 1.0)
		_vel[i] = (d.normalized() if d.length() > 0.01 else Vector3.FORWARD) * speed
		multimesh.set_instance_custom_data(i, Color(_rng.randf(), 0.0, 0.0, 0.0))   # .x = phase de battement
	var smat := ShaderMaterial.new()
	smat.shader = preload("res://shaders/bird.gdshader")
	smat.set_shader_parameter("body", body_color)
	smat.set_shader_parameter("flap_speed", flap_speed)
	material_override = smat
	visible = false

func _bird_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Chevron (envergure ∝ bird_scale) : tête (+Z), bouts d'aile (±X), queue (-Z). 2 triangles.
	var s := bird_scale
	var head := Vector3(0.0, 0.0, 0.30) * s
	var lw := Vector3(-0.45, 0.0, -0.18) * s
	var rw := Vector3(0.45, 0.0, -0.18) * s
	var tail := Vector3(0.0, 0.0, -0.42) * s
	for v in [head, lw, tail, head, tail, rw]:
		st.add_vertex(v)
	st.generate_normals()
	return st.commit()

# center = position joueur ; day 0..1 (les oiseaux volent le jour) ; delta.
func update(center: Vector3, day: float, delta: float) -> void:
	if day < 0.12:
		if visible:
			visible = false
		return
	visible = true
	global_transform = Transform3D(Basis(), center)
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
		if p.y < alt_lo:
			a.y += W_BOUND * speed
		elif p.y > alt_hi:
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

# Base orientée : +Z (avant du mesh) le long de la vitesse.
func _look_basis(v: Vector3) -> Basis:
	var fwd := v.normalized() if v.length() > 0.001 else Vector3.FORWARD
	var up := Vector3.UP
	if absf(fwd.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var x := up.cross(fwd).normalized()
	var y := fwd.cross(x).normalized()
	return Basis(x, y, fwd)
