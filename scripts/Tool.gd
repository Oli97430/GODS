class_name HarvestTool
extends Node3D
## Outil de récolte (hache / pioche) — MÊME modèle GLB pour les deux (demandé). Visuel seul : la logique de
## coup est dans HarvestManager. Attaché à la main droite par PlayerController (comme une arme). `kind` sert
## juste d'étiquette ("axe"/"pickaxe"). Auto-échelle + centré (comme les vaisseaux drones), ombres off.

const MODEL := "res://models/pioche_hache.glb"
const LENGTH := 1.0                       # m : longueur cible (auto-échelle) — outil ×2
const ROT_DEG := Vector3(0.0, 45.0, 0.0)   # pivot 45° sur Y (la prise tombe bien dans la main)

var kind := "axe"

func _ready() -> void:
	var res = load(MODEL)
	var inst: Node3D = null
	if res is PackedScene:
		inst = (res as PackedScene).instantiate()
	if inst == null:
		# Repli si le GLB manque : boîte allongée (manche).
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, LENGTH, 0.10)
		mi.mesh = bm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		return
	add_child(inst)
	CombatUtil.disable_shadows(inst)
	# Fit : centre + auto-échelle à LENGTH (le GLB peut avoir une échelle/origine quelconque).
	var r := CombatUtil.scene_aabb(inst, Transform3D.IDENTITY)
	if r.has and (r.box as AABB).size.length() > 0.0001:
		var ab: AABB = r.box
		var longest: float = maxf(maxf(ab.size.x, ab.size.y), ab.size.z)
		var sc: float = LENGTH / maxf(longest, 0.0001)
		inst.position = Vector3(-ab.get_center().x * sc, -ab.position.y * sc, -ab.get_center().z * sc)   # tenu PAR LE BAS (min Y à la main)
		inst.scale = Vector3(sc, sc, sc)
	inst.rotation = Vector3(deg_to_rad(ROT_DEG.x), deg_to_rad(ROT_DEG.y), deg_to_rad(ROT_DEG.z))
