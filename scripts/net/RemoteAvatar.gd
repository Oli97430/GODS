extends Node3D
## Avatar d'un joueur DISTANT (coop CP2) : tête (capsule) + 2 mains (sphères) + arme tenue (boîte colorée).
## Les parties sont `top_level` : leur global_transform est piloté DIRECTEMENT par CoopSync, qui convertit
## l'état reçu en espace-PLANÈTE → espace-rendu local via la transform d'aplatissement courante (anti-rebase).
## Meshes simples (perf). AUTO-CONTENU.

var head: MeshInstance3D
var lhand: MeshInstance3D
var rhand: MeshInstance3D
var weapon: MeshInstance3D
var _weapon_id := -2

func _ready() -> void:
	head = _make(_capsule(0.12, 0.30), Color(0.55, 0.68, 0.95))
	lhand = _make(_sphere(0.05), Color(0.85, 0.74, 0.62))
	rhand = _make(_sphere(0.05), Color(0.85, 0.74, 0.62))
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.06, 0.26)
	weapon = _make(bm, Color(0.4, 0.7, 1.0))
	weapon.visible = false

func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	return m

func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 8
	m.rings = 4
	return m

func _make(mesh: Mesh, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.top_level = true   # global_transform piloté directement (espace-rendu)
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.65
	mi.material_override = m
	add_child(mi)
	return mi

func set_hands_visible(v: bool) -> void:
	lhand.visible = v
	rhand.visible = v
	weapon.visible = v and _weapon_id >= 0

func set_weapon(id: int) -> void:
	if id == _weapon_id:
		return
	_weapon_id = id
	weapon.visible = id >= 0
	if id >= 0:
		var cols := [Color(0.4, 0.9, 1.0), Color(0.45, 1.0, 0.55), Color(1.0, 0.6, 0.15)]   # revolver / plasma / grenade
		(weapon.material_override as StandardMaterial3D).albedo_color = cols[clampi(id, 0, 2)]
