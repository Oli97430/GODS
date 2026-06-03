extends MultiMeshInstance3D
## Nuée d'oiseaux : boids (cohésion / alignement / séparation) volant en troupeau dans le ciel autour du
## joueur. AUTO-CONTENU. Visible le JOUR (complète les lucioles nocturnes). top_level => le volume suit le
## joueur (positions player-RELATIVES => insensible au rebase FloatingOrigin). Pilotée par SurfaceView.
## ~42 boids, sim O(N²) négligeable. Vie ambiante, non déterministe (comme les météores).

const N := 42
const RADIUS := 38.0      # m : rayon horizontal du volume (player-relative)
const ALT_MIN := 9.0      # m : plancher de vol
const ALT_MAX := 26.0     # m : plafond de vol
const SPEED := 7.0        # m/s vitesse de croisière visée
const MAX_SPEED := 10.0
const W_COH := 0.6        # cohésion (vers le centre du troupeau)
const W_ALI := 0.8        # alignement (vers la vitesse moyenne)
const W_SEP := 1.4        # séparation (s'écarter des trop proches)
const SEP_DIST := 3.0
const W_BOUND := 1.2      # rappel dans le volume

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
	multimesh.instance_count = N
	_pos = PackedVector3Array()
	_pos.resize(N)
	_vel = PackedVector3Array()
	_vel.resize(N)
	for i in N:
		var ang := _rng.randf() * TAU
		var rad := _rng.randf() * RADIUS * 0.5
		_pos[i] = Vector3(cos(ang) * rad, _rng.randf_range(ALT_MIN, ALT_MAX), sin(ang) * rad)
		var d := Vector3(_rng.randf() * 2.0 - 1.0, 0.0, _rng.randf() * 2.0 - 1.0)
		_vel[i] = (d.normalized() if d.length() > 0.01 else Vector3.FORWARD) * SPEED
		multimesh.set_instance_custom_data(i, Color(_rng.randf(), 0.0, 0.0, 0.0))   # .x = phase de battement
	var smat := ShaderMaterial.new()
	smat.shader = preload("res://shaders/bird.gdshader")
	material_override = smat
	visible = false

func _bird_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Chevron ~0.9 m d'envergure : tête (+Z), bouts d'aile (±X), queue (-Z). 2 triangles.
	var head := Vector3(0.0, 0.0, 0.30)
	var lw := Vector3(-0.45, 0.0, -0.18)
	var rw := Vector3(0.45, 0.0, -0.18)
	var tail := Vector3(0.0, 0.0, -0.42)
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
	for i in N:
		centroid += _pos[i]
		avgv += _vel[i]
	centroid /= float(N)
	avgv /= float(N)
	for i in N:
		var p := _pos[i]
		var a := (centroid - p) * W_COH + (avgv - _vel[i]) * W_ALI
		# Séparation : s'écarter des voisins trop proches.
		for j in N:
			if j == i:
				continue
			var dd := p - _pos[j]
			var dl := dd.length()
			if dl > 0.001 and dl < SEP_DIST:
				a += (dd / (dl * dl)) * W_SEP
		# Rappel dans le volume (cylindre player-relative).
		var horiz := Vector3(p.x, 0.0, p.z)
		if horiz.length() > RADIUS:
			a += -horiz.normalized() * W_BOUND * SPEED
		if p.y < ALT_MIN:
			a.y += W_BOUND * SPEED
		elif p.y > ALT_MAX:
			a.y -= W_BOUND * SPEED
		# Intègre + clamp de vitesse (croisière).
		var v := _vel[i] + a * dt
		var sp := v.length()
		if sp > MAX_SPEED:
			v = v / sp * MAX_SPEED
		elif sp < SPEED * 0.5 and sp > 0.001:
			v = v / sp * (SPEED * 0.6)
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
