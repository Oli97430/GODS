class_name FishingRod
extends Node3D
## Canne à pêche (CP-PÊCHE) — modèle PROCÉDURAL tenu en main droite (comme l'outil de récolte / une arme).
## Visuel seul : poignée + moulinet + tige effilée pointant vers l'avant (-Z). Le nœud `tip` marque le bout
## de la canne (origine du fil) ; la LOGIQUE de pêche (lancer/touche/ferrage) est dans Fishing.gd.

var tip: Node3D   # bout de la tige (où s'attache le fil de pêche)

func _ready() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.50, 0.36, 0.20)
	wood.roughness = 0.7
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.18, 0.18, 0.20)
	dark.metallic = 0.4
	dark.roughness = 0.5
	# Poignée (cylindre court le long de l'avant-bras).
	var grip := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.018
	gm.bottom_radius = 0.022
	gm.height = 0.16
	grip.mesh = gm
	grip.material_override = wood
	grip.rotation_degrees = Vector3(-90.0, 0.0, 0.0)   # axe Y du cylindre -> avant (-Z)
	grip.position = Vector3(0.0, 0.0, -0.08)
	grip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grip)
	# Moulinet (petit disque sous la poignée).
	var reel := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.032
	rm.bottom_radius = 0.032
	rm.height = 0.03
	reel.mesh = rm
	reel.material_override = dark
	reel.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	reel.position = Vector3(0.0, -0.035, -0.12)
	reel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(reel)
	# Tige effilée (s'amincit vers le bout).
	var shaft := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.004      # bout (avant, -Z)
	sm.bottom_radius = 0.016   # base (vers la poignée)
	sm.height = 1.3
	sm.radial_segments = 6
	shaft.mesh = sm
	shaft.material_override = wood
	shaft.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	shaft.position = Vector3(0.0, 0.0, -0.16 - 0.65)   # base juste après la poignée, s'étend jusqu'à z=-1.46
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shaft)
	# Bout de canne (origine du fil).
	tip = Node3D.new()
	tip.position = Vector3(0.0, 0.0, -1.46)
	add_child(tip)
