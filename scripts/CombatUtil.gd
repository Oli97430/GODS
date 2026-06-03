class_name CombatUtil
extends RefCounted
## Helpers PARTAGÉS du combat (phase 26) — évite la duplication entre Blaster / BoltVisual / HitSpark / Drone /
## WaveManager. Fonctions PURES statiques (aucun état), bodies repris à l'identique des copies d'origine.

# Base orientée : +Z = fwd (pour étirer un mesh le long d'une direction, billboard manuel d'un tracer, etc.).
static func look_basis(fwd: Vector3) -> Basis:
	var up := Vector3.UP
	if absf(fwd.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var x := up.cross(fwd).normalized()
	var y := fwd.cross(x).normalized()
	return Basis(x, y, fwd)

# Direction « devant le joueur » (horizontale) = forward de la caméra active du joueur, aplati ; repli sur le corps.
static func front_dir(player: Node3D) -> Vector3:
	if player and player.has_method("get_active_camera"):
		var cam = player.get_active_camera()
		if cam:
			var f: Vector3 = -cam.global_transform.basis.z
			f.y = 0.0
			if f.length() > 0.01:
				return f.normalized()
	if player:
		var bf := -player.global_transform.basis.z
		bf.y = 0.0
		if bf.length() > 0.01:
			return bf.normalized()
	return Vector3.FORWARD

# AABB d'une scène instanciée (récursif, transforms appliqués) — pour l'auto-échelle de modèles GLB.
static func scene_aabb(node: Node, xf: Transform3D) -> Dictionary:
	var cur := xf
	if node is Node3D:
		cur = xf * (node as Node3D).transform
	var box := AABB()
	var has := false
	if node is VisualInstance3D:
		box = xform_aabb(cur, (node as VisualInstance3D).get_aabb())
		has = true
	for c in node.get_children():
		var r := scene_aabb(c, cur)
		if r.has:
			box = box.merge(r.box) if has else r.box
			has = true
	return {"box": box, "has": has}

static func xform_aabb(t: Transform3D, a: AABB) -> AABB:
	var mn := t * a.position
	var mx := mn
	for i in range(1, 8):
		var corner := a.position + Vector3(a.size.x * float(i & 1), a.size.y * float((i >> 1) & 1), a.size.z * float((i >> 2) & 1))
		var p := t * corner
		mn = mn.min(p)
		mx = mx.max(p)
	return AABB(mn, mx - mn)

static func disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		disable_shadows(c)
