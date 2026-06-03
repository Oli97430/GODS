extends Node3D
## Arme VR (mode combat OPT-IN) — PARAMÉTRABLE (revolver « blaster » OU fusil à plasma) : modèle GLB tenu en
## main droite (XR) / viewmodel (bureau). Régler les `var` d'arme AVANT add_child (cf. PlayerController).
## • VISÉE (raycast) depuis une bouche FIGÉE `_muzzle` => tir précis, stable, non perturbé par le recul.
## • BOLT (tracer) + FLASH émanent du BOUT DU CANON VISIBLE (suit le recul) => le projectile part toujours
##   du canon, dans toutes les directions. • RECUL VISUEL. • Tir SECONDAIRE chargé (précision) + zoom.

const RANGE := 200.0
const GRIP_ANCHOR := Vector3(0.5, 0.5, 0.5)   # 0.5 = centré dans la main
const MUZZLE_FWD := -0.01
const RECOIL_KICK := 0.025
const RECOIL_PITCH := 8.0
const RECOIL_RECOVER := 0.12
const TRACER_LIFE := 0.06

# --- Configuration d'ARME (défauts = revolver « blaster ») : à surcharger AVANT add_child ---
var weapon_name := "Blaster"
var model_path := "res://models/revolver.glb"
var model_rot_deg := Vector3(0.0, 180.0, 0.0)   # canon du modèle le long de +Z => 180° Y vers l'avant (-Z)
var model_length := 0.26
var muzzle_up_frac := 0.11
var bolt_color := Color(0.4, 0.9, 1.0)          # cyan
var charged_color := Color(0.75, 0.5, 1.0)      # violet (tir secondaire)
var fire_interval := 0.16                        # s entre tirs (primaire)
var fire_interval_ads := 0.42                    # s (tir secondaire, plus lent)
var zoom_fov := 16.0                             # ° retirés au FOV en visée (bureau)
var dmg := 1.0                                   # dégâts par tir primaire
var dmg_charged := 2.0                            # dégâts tir secondaire

var _visual: Node3D
var _visual_base := Transform3D.IDENTITY
var _model: Node3D
var _muzzle: Node3D
var _flash: OmniLight3D
var _tracer: MeshInstance3D
var _tracer_mat: StandardMaterial3D
var _tracer_to := Vector3.ZERO
var _tracer_col := Color(0.4, 0.9, 1.0)
var _tracer_width := 0.05
var _spark: OmniLight3D
var _recoil := 0.0
var _flash_t := 0.0
var _tracer_t := 0.0
var _spark_t := 0.0
# Viseur par arme (world-space => valable VR + bureau) : réticule au point visé + fin laser depuis le canon.
var _reticle: MeshInstance3D
var _reticle_mat: StandardMaterial3D
var _laser: MeshInstance3D
var _laser_mat: StandardMaterial3D

func _ready() -> void:
	_build_gun()

func _build_gun() -> void:
	_tracer_col = bolt_color
	_visual = Node3D.new()
	add_child(_visual)
	if ResourceLoader.exists(model_path):
		var scene = load(model_path)
		if scene:
			_model = scene.instantiate()
			_visual.add_child(_model)
			var r := _scene_aabb(_model, Transform3D.IDENTITY)
			if r.has and r.box.size.length() > 0.0001:
				var longest: float = maxf(maxf(r.box.size.x, r.box.size.y), r.box.size.z)
				var s: float = model_length / maxf(longest, 0.0001)
				var bb: AABB = r.box
				var grip := bb.position + Vector3(GRIP_ANCHOR.x * bb.size.x, GRIP_ANCHOR.y * bb.size.y, GRIP_ANCHOR.z * bb.size.z)
				_model.position = -grip
				_visual.scale = Vector3(s, s, s)
			_visual.rotation = Vector3(deg_to_rad(model_rot_deg.x), deg_to_rad(model_rot_deg.y), deg_to_rad(model_rot_deg.z))
			_disable_shadows(_model)
	if _model == null:
		_build_procedural()
	_visual_base = _visual.transform
	# Bouche FIGÉE (aim) : sous le ROOT, à la pointe du canon (offset déterministe, tourne avec l'arme).
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0.0, model_length * muzzle_up_frac, -model_length * 0.5 + MUZZLE_FWD)
	add_child(_muzzle)
	# Bout du canon VISIBLE : flash sous _visual (même point local) => suit le recul ; origine du tracer.
	_flash = OmniLight3D.new()
	_flash.light_color = bolt_color
	_flash.omni_range = 4.0
	_flash.light_energy = 0.0
	_flash.shadow_enabled = false
	_visual.add_child(_flash)
	_flash.position = _visual_base.affine_inverse() * _muzzle.position
	# Tracer (bolt) : top_level, ré-étiré chaque frame depuis _flash vers la cible.
	_tracer = MeshInstance3D.new()
	_tracer.top_level = true
	_tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tm := BoxMesh.new()
	tm.size = Vector3(1.0, 1.0, 1.0)
	_tracer.mesh = tm
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.albedo_color = bolt_color
	_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_tracer.material_override = _tracer_mat
	_tracer.visible = false
	add_child(_tracer)
	# Étincelle d'impact.
	_spark = OmniLight3D.new()
	_spark.top_level = true
	_spark.light_color = bolt_color
	_spark.omni_range = 3.0
	_spark.light_energy = 0.0
	_spark.shadow_enabled = false
	add_child(_spark)
	# Viseur (par arme) : réticule anneau + point posé au point visé (face caméra, taille angulaire ~constante).
	_reticle = MeshInstance3D.new()
	_reticle.top_level = true
	_reticle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_reticle.mesh = _reticle_mesh()
	_reticle_mat = StandardMaterial3D.new()
	_reticle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_reticle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_reticle_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_reticle_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_reticle_mat.albedo_color = bolt_color
	_reticle.material_override = _reticle_mat
	_reticle.visible = false
	add_child(_reticle)
	# Fin laser depuis le bout du canon visible jusqu'au point visé (relie l'arme au réticule, lisible en VR).
	_laser = MeshInstance3D.new()
	_laser.top_level = true
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lm := BoxMesh.new()
	lm.size = Vector3(1.0, 1.0, 1.0)
	_laser.mesh = lm
	_laser_mat = StandardMaterial3D.new()
	_laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_laser_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_laser_mat.albedo_color = Color(bolt_color.r, bolt_color.g, bolt_color.b, 0.22)
	_laser.material_override = _laser_mat
	_laser.visible = false
	add_child(_laser)

func _build_procedural() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.12, 0.13, 0.16)
	metal.metallic = 0.7
	metal.roughness = 0.4
	var accent := StandardMaterial3D.new()
	accent.albedo_color = bolt_color
	accent.emission_enabled = true
	accent.emission = bolt_color
	accent.emission_energy_multiplier = 3.0
	_add_box(Vector3(0.045, 0.06, 0.18), Vector3(0.0, 0.0, -0.02), metal)
	_add_box(Vector3(0.03, 0.03, 0.16), Vector3(0.0, 0.01, -0.16), metal)
	_add_box(Vector3(0.04, 0.10, 0.05), Vector3(0.0, -0.07, 0.04), metal)
	_add_box(Vector3(0.05, 0.012, 0.10), Vector3(0.0, 0.035, -0.05), accent)

func _add_box(size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(mi)

func _scene_aabb(node: Node, xf: Transform3D) -> Dictionary:
	var cur := xf
	if node is Node3D:
		cur = xf * (node as Node3D).transform
	var box := AABB()
	var has := false
	if node is VisualInstance3D:
		box = _xform_aabb(cur, (node as VisualInstance3D).get_aabb())
		has = true
	for c in node.get_children():
		var r := _scene_aabb(c, cur)
		if r.has:
			box = box.merge(r.box) if has else r.box
			has = true
	return {"box": box, "has": has}

func _xform_aabb(t: Transform3D, a: AABB) -> AABB:
	var mn := t * a.position
	var mx := mn
	for i in range(1, 8):
		var corner := a.position + Vector3(a.size.x * float(i & 1), a.size.y * float((i >> 1) & 1), a.size.z * float((i >> 2) & 1))
		var p := t * corner
		mn = mn.min(p)
		mx = mx.max(p)
	return AABB(mn, mx - mn)

func _disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		_disable_shadows(c)

func muzzle_world() -> Vector3:
	return _flash.global_position if _flash else global_position

func fire(exclude: Array, charged := false) -> Dictionary:
	var mt := _muzzle.global_transform
	var from := mt.origin
	var dir := -mt.basis.z.normalized()
	var to := from + dir * RANGE
	var result := {"hit": false, "pos": to, "collider": null, "charged": charged}
	var space := get_world_3d().direct_space_state
	if space:
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = exclude
		q.collide_with_areas = true   # toucher les drones (Area3D), pas seulement le terrain
		var h := space.intersect_ray(q)
		if not h.is_empty():
			result.hit = true
			result.pos = h.position
			result.collider = h.collider
	var col: Color = charged_color if charged else bolt_color
	_tracer_to = result.pos
	_tracer_col = col
	_tracer_width = 0.10 if charged else 0.05
	_tracer_t = TRACER_LIFE
	_flash.light_color = col
	_flash.light_energy = 9.0 if charged else 6.0
	_flash_t = 0.06 if charged else 0.05
	_spark.light_color = col
	_spark.global_position = result.pos
	_spark.light_energy = 7.0 if charged else 5.0
	_spark_t = 0.12 if charged else 0.09
	_recoil = 1.0
	return result

func _look_basis(fwd: Vector3) -> Basis:
	var up := Vector3.UP
	if absf(fwd.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var x := up.cross(fwd).normalized()
	var y := fwd.cross(x).normalized()
	return Basis(x, y, fwd)

# Réticule = anneau fin + point central, dans le plan XY local (rayon unité), orienté face caméra à l'usage.
func _reticle_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 28
	var r_out := 1.0
	var r_in := 0.74
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var o0 := Vector3(cos(a0) * r_out, sin(a0) * r_out, 0.0)
		var o1 := Vector3(cos(a1) * r_out, sin(a1) * r_out, 0.0)
		var i0 := Vector3(cos(a0) * r_in, sin(a0) * r_in, 0.0)
		var i1 := Vector3(cos(a1) * r_in, sin(a1) * r_in, 0.0)
		st.add_vertex(i0); st.add_vertex(o0); st.add_vertex(o1)
		st.add_vertex(i0); st.add_vertex(o1); st.add_vertex(i1)
	var rc := 0.16   # point central
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(cos(a0) * rc, sin(a0) * rc, 0.0))
		st.add_vertex(Vector3(cos(a1) * rc, sin(a1) * rc, 0.0))
	return st.commit()

func _recoil_xform() -> Transform3D:
	if _recoil <= 0.001:
		return Transform3D.IDENTITY
	var rot := Basis(Vector3.RIGHT, deg_to_rad(RECOIL_PITCH) * _recoil)
	return Transform3D(rot, Vector3(0.0, 0.0, RECOIL_KICK * _recoil))

func _process(delta: float) -> void:
	if _recoil > 0.0:
		_recoil = maxf(_recoil - delta / RECOIL_RECOVER, 0.0)
	if _visual:
		_visual.transform = _recoil_xform() * _visual_base
	if _tracer_t > 0.0:
		_tracer_t -= delta
		if _tracer_t > 0.0 and _flash:
			var from := _flash.global_position
			var dir := _tracer_to - from
			var len := dir.length()
			if len > 0.001:
				dir /= len
				var mid := (from + _tracer_to) * 0.5
				_tracer.global_transform = Transform3D(_look_basis(dir).scaled(Vector3(_tracer_width, _tracer_width, len)), mid)
				var a := clampf(_tracer_t / TRACER_LIFE, 0.0, 1.0)
				_tracer_mat.albedo_color = Color(_tracer_col.r, _tracer_col.g, _tracer_col.b, 0.9 * a)
				_tracer.visible = true
			else:
				_tracer.visible = false
		else:
			_tracer.visible = false
	if _flash_t > 0.0:
		_flash_t -= delta
		_flash.light_energy = lerpf(_flash.light_energy, 0.0, clampf(14.0 * delta, 0.0, 1.0))
		if _flash_t <= 0.0:
			_flash.light_energy = 0.0
	if _spark_t > 0.0:
		_spark_t -= delta
		_spark.light_energy = lerpf(_spark.light_energy, 0.0, clampf(12.0 * delta, 0.0, 1.0))
		if _spark_t <= 0.0:
			_spark.light_energy = 0.0
	_update_sight()

# Viseur : raycast depuis la bouche FIGÉE (= là où le tir partira) → pose le réticule au point d'impact (face
# caméra, taille angulaire ~constante) et étire le laser du canon visible jusqu'à ce point. Masqué si dégainé.
func _update_sight() -> void:
	if not visible or _muzzle == null:
		if _reticle:
			_reticle.visible = false
		if _laser:
			_laser.visible = false
		return
	var mt := _muzzle.global_transform
	var from := mt.origin
	var dir := -mt.basis.z.normalized()
	var hit_pos := from + dir * RANGE
	var space := get_world_3d().direct_space_state
	if space:
		var q := PhysicsRayQueryParameters3D.create(from, hit_pos)
		q.collide_with_areas = true   # même portée que fire() => le réticule prédit exactement l'impact
		var h := space.intersect_ray(q)
		if not h.is_empty():
			hit_pos = h.position
	var cam := get_viewport().get_camera_3d()
	if cam != null and _reticle:
		var look := cam.global_position - hit_pos
		if look.length() > 0.001:
			var d := from.distance_to(hit_pos)
			var rs := clampf(d, 1.0, RANGE) * 0.012   # taille angulaire ~constante
			var rpos := hit_pos + look.normalized() * 0.03   # léger décalage anti-z-fight
			_reticle.global_transform = Transform3D(_look_basis(look.normalized()).scaled(Vector3(rs, rs, rs)), rpos)
			_reticle.visible = true
	if _laser:
		var lfrom := _flash.global_position if _flash else from
		var seg := hit_pos - lfrom
		var llen := seg.length()
		if llen > 0.02:
			var lmid := (lfrom + hit_pos) * 0.5
			_laser.global_transform = Transform3D(_look_basis(seg / llen).scaled(Vector3(0.004, 0.004, llen)), lmid)
			_laser.visible = true
		else:
			_laser.visible = false
