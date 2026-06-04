extends Node3D
## Cratère d'atterrissage de PUISSANCE : marque laissée AU SOL là où le joueur s'écrase lourdement (Iron Man).
## Décalque « bol » (crater.gdshader : fond sombre → bourrelet d'éjecta → rayons) posé au ras du sol, orienté à
## la NORMALE de pente ; couronne de DÉBRIS soulevés (terre déplacée) + quelques éclats au fond ; bref FLASH
## chaud d'impact. Taille ∝ force. Se fond / se tasse après LIFE puis se libère. AUTO-CONTENU.
## NB : le terrain streamé n'est PAS réellement creusé (décalque + relief — coût ~nul, compatible streaming/rebase
## pour sa courte vie). Spawné par SurfaceView sur le signal `impact` du joueur.

const LIFE := 32.0          # s : durée de vie avant disparition
const FADE_IN := 0.3        # s : apparition (la poussière du burst la couvre)
const FADE_OUT := 6.0       # s : fondu / tassement de fin
const GLOW_TIME := 0.8      # s : durée du flash chaud d'impact
const RIM_ROCKS := 22       # cailloux de la couronne (terre déplacée)
const INNER_ROCKS := 7      # éclats épars au fond du cratère

var _strength := 1.0
var _radius := 2.0
var _disc_mat: ShaderMaterial
var _rim: MultiMeshInstance3D
var _rim_mat: StandardMaterial3D
var _glow: OmniLight3D
var _t := 0.0
var _pending_pos := Vector3.ZERO
var _pending_up := Vector3.UP
var _rng := RandomNumberGenerator.new()

# À appeler AVANT add_child : point d'impact au sol, normale du sol, force 0..1.
func setup(world_pos: Vector3, normal: Vector3, strength: float) -> void:
	_pending_pos = world_pos
	_pending_up = normal.normalized() if normal.length() > 0.01 else Vector3.UP
	_strength = clampf(strength, 0.0, 1.0)
	_radius = 1.6 + 2.2 * _strength   # ~2.6 .. 3.8 m

func _ready() -> void:
	_rng.randomize()
	# Orientation : le disque (PlaneMesh, normale +Y) suit la pente du sol au point d'impact.
	global_transform = Transform3D(_basis_from_up(_pending_up), _pending_pos + _pending_up * 0.05)
	# Disque « bol » (décalque, shader profil de cratère).
	var disc := MeshInstance3D.new()
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := PlaneMesh.new()
	pm.size = Vector2(_radius * 2.0, _radius * 2.0)
	disc.mesh = pm
	_disc_mat = ShaderMaterial.new()
	_disc_mat.shader = load("res://shaders/crater.gdshader")
	_disc_mat.set_shader_parameter("fade", 0.0)
	disc.material_override = _disc_mat
	add_child(disc)
	# Débris : couronne (terre déplacée) + quelques éclats au fond — cailloux OPAQUES (pas d'artefact de tri).
	_rim = MultiMeshInstance3D.new()
	_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 0.7, 1.0)
	mm.mesh = bm
	mm.instance_count = RIM_ROCKS + INNER_ROCKS
	_rim.multimesh = mm
	_rim_mat = StandardMaterial3D.new()
	_rim_mat.albedo_color = Color(0.20, 0.17, 0.14)
	_rim_mat.roughness = 1.0
	_rim.material_override = _rim_mat
	for i in RIM_ROCKS:   # couronne : gros cailloux sur le pourtour (bourrelet d'éjecta)
		var a := TAU * float(i) / float(RIM_ROCKS) + _rng.randf_range(-0.12, 0.12)
		var rr := _radius * _rng.randf_range(0.82, 1.02)
		var p := Vector3(cos(a) * rr, _rng.randf_range(0.0, 0.14), sin(a) * rr)
		var s := (0.13 + _rng.randf() * 0.18) * (0.7 + _strength)
		var rot := Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU))
		mm.set_instance_transform(i, Transform3D(rot.scaled(Vector3(s, s, s)), p))
	for j in INNER_ROCKS:   # fond : petits éclats épars
		var a2 := _rng.randf() * TAU
		var rr2 := _radius * _rng.randf_range(0.15, 0.7)
		var p2 := Vector3(cos(a2) * rr2, _rng.randf_range(0.0, 0.05), sin(a2) * rr2)
		var s2 := (0.06 + _rng.randf() * 0.08) * (0.7 + _strength)
		var rot2 := Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU))
		mm.set_instance_transform(RIM_ROCKS + j, Transform3D(rot2.scaled(Vector3(s2, s2, s2)), p2))
	add_child(_rim)
	# Flash chaud d'impact (la violence du choc) : OmniLight orange qui s'éteint vite.
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.55, 0.25)
	_glow.omni_range = _radius * 2.2
	_glow.light_energy = 3.0 + 4.0 * _strength
	_glow.shadow_enabled = false
	_glow.position = Vector3(0.0, 0.3, 0.0)
	add_child(_glow)

func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	var fin := clampf(_t / FADE_IN, 0.0, 1.0)
	var fout := clampf((LIFE - _t) / FADE_OUT, 0.0, 1.0)
	if _disc_mat:
		_disc_mat.set_shader_parameter("fade", fin * fout)
	if _rim:
		_rim.scale = Vector3.ONE * (0.25 + 0.75 * fout)   # fin de vie : les débris se tassent (cailloux opaques)
	# Flash d'impact : décroît sur GLOW_TIME puis s'éteint.
	if _glow:
		if _t < GLOW_TIME:
			_glow.light_energy = (3.0 + 4.0 * _strength) * (1.0 - _t / GLOW_TIME)
		elif _glow.visible:
			_glow.visible = false

# Base orthonormée dont l'axe Y suit `up` (oriente le disque selon la pente du sol).
func _basis_from_up(up: Vector3) -> Basis:
	var y := up.normalized()
	var x := Vector3.RIGHT
	if absf(y.dot(x)) > 0.99:
		x = Vector3.FORWARD
	var z := x.cross(y).normalized()
	x = y.cross(z).normalized()
	return Basis(x, y, z)
