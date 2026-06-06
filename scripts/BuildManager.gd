extends Node3D
## Mode construction (CP4) : fabriquer et placer des éléments dans le monde.
## — Pièces de CONSTRUCTION (planches, murs, toits, piliers, portes, lanternes)
## — PLANTATION de graines (arbuste qui pousse en arbre au fil du temps)
## Ghost (aperçu transparent) suit le raycast caméra. Q/E = rotation. Clic = poser. Escape = annuler.

const AIM_RANGE := 12.0     # m : portée de visée
const ROT_SPEED := 2.5      # rad/s : rotation Q/E
const GROW_TIME := 180.0    # s : temps de pousse d'un arbuste planté → arbre adulte

# Table des pièces constructibles : taille, couleur, propriétés matériau.
# « emission » et « light » = optionnels (lanterne dorée uniquement).
static var PIECES := {
	"plank":       {"size": Vector3(2.0, 0.08, 1.0), "color": Color(0.55, 0.38, 0.22), "metallic": 0.0,  "roughness": 0.82},
	"wall_stone":  {"size": Vector3(2.0, 1.5, 0.25), "color": Color(0.48, 0.46, 0.42), "metallic": 0.0,  "roughness": 0.92},
	"roof_thatch": {"size": Vector3(2.2, 0.06, 1.2), "color": Color(0.42, 0.52, 0.28), "metallic": 0.0,  "roughness": 0.90},
	"pillar_iron": {"size": Vector3(0.25, 2.0, 0.25),"color": Color(0.38, 0.36, 0.34), "metallic": 0.72, "roughness": 0.35},
	"door_copper": {"size": Vector3(1.0, 2.0, 0.08), "color": Color(0.65, 0.42, 0.28), "metallic": 0.60, "roughness": 0.42},
	"lamp_gold":   {"size": Vector3(0.3, 0.5, 0.3),  "color": Color(0.85, 0.70, 0.30), "metallic": 0.80, "roughness": 0.18,
					"emission": Color(1.0, 0.85, 0.5), "emission_energy": 2.0, "light": true},
}

# Apparence visuelle par graine (couleur canopée + échelle adulte).
static var SEED_LOOK := {
	"seed_deciduous": {"canopy": Color(0.28, 0.50, 0.22), "scale": 2.8},
	"seed_palm":      {"canopy": Color(0.30, 0.55, 0.24), "scale": 3.2},
	"seed_conifer":   {"canopy": Color(0.16, 0.32, 0.18), "scale": 3.5},
	"seed_twisted":   {"canopy": Color(0.42, 0.28, 0.42), "scale": 2.4},
}

var _player: Node = null
var _active := false
var _item := ""               # id de la pièce ("plank", "wall_stone"…) — vide si plant_mode
var _plant_mode := false       # vrai si on plante (graine → arbuste)
var _plant_seed := ""          # id de la graine en cours de plantation
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _yaw := 0.0
var _place_prev := false

# Meshes et matériaux pré-construits par type de pièce (clé = item id).
var _piece_meshes := {}        # item_id -> BoxMesh
var _piece_mats := {}          # item_id -> StandardMaterial3D

# Plantation : mesh d'arbuste + matériau + suivi pousse des arbustes plantés.
var _sapling_mesh: ArrayMesh
var _sapling_mat: StandardMaterial3D
var _saplings: Array = []      # [{node: MeshInstance3D, timer: float, max_scale: float}]

# ─── Setup ───────────────────────────────────────────────────────────────────
func setup(player: Node) -> void:
	_player = player
	top_level = true
	# Ghost (aperçu semi-transparent vert).
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.albedo_color = Color(0.3, 0.9, 0.4, 0.35)
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost = MeshInstance3D.new()
	_ghost.material_override = _ghost_mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)
	# Pré-construire meshes et matériaux de chaque pièce depuis la table PIECES.
	for id in PIECES:
		var p: Dictionary = PIECES[id]
		var bm := BoxMesh.new()
		bm.size = p["size"] as Vector3
		_piece_meshes[id] = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = p["color"] as Color
		mat.metallic = float(p["metallic"])
		mat.roughness = float(p["roughness"])
		if p.has("emission"):
			mat.emission_enabled = true
			mat.emission = p["emission"] as Color
			mat.emission_energy_multiplier = float(p["emission_energy"])
		_piece_mats[id] = mat
	# Mesh d'arbuste par défaut (tronc + canopée octaèdre). Remplacé dynamiquement par start_plant.
	_sapling_mat = StandardMaterial3D.new()
	_sapling_mat.vertex_color_use_as_albedo = true
	_sapling_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_sapling_mesh = _make_sapling(Color(0.30, 0.50, 0.22))

# ─── Modes ───────────────────────────────────────────────────────────────────
func start(item: String) -> void:
	_item = item
	_plant_mode = false
	_plant_seed = ""
	_active = true
	GameState.build_active = true
	# Range l'outil de récolte si équipé (exclusif).
	if _player.has_method("active_tool") and _player.active_tool() != "":
		_player.toggle_tool()
	_ghost.mesh = _piece_meshes.get(item)
	_ghost.material_override = _ghost_mat
	_ghost.visible = true

func start_plant(seed_id: String) -> void:
	_plant_mode = true
	_plant_seed = seed_id
	_item = ""
	_active = true
	GameState.build_active = true
	if _player.has_method("active_tool") and _player.active_tool() != "":
		_player.toggle_tool()
	var look: Dictionary = SEED_LOOK.get(seed_id, {"canopy": Color(0.30, 0.50, 0.22), "scale": 2.8})
	_sapling_mesh = _make_sapling(look["canopy"] as Color)
	_ghost.mesh = _sapling_mesh
	_ghost.material_override = _ghost_mat
	_ghost.visible = true

func stop() -> void:
	_active = false
	_item = ""
	_plant_mode = false
	_plant_seed = ""
	_ghost.visible = false
	GameState.build_active = false

func is_active() -> bool:
	return _active

# ─── Update (appelé chaque frame par SurfaceView) ───────────────────────────
func update(delta: float) -> void:
	# Faire pousser les arbustes plantés (indépendant du mode construction actif).
	_grow_saplings(delta)
	if not _active or _player == null:
		return
	# Annulation si le joueur sort une arme ou un outil.
	if _player.has_method("is_armed") and _player.is_armed():
		stop(); return
	if _player.has_method("active_tool") and _player.active_tool() != "":
		stop(); return
	# Rotation (bureau : Q/E).
	if Input.is_key_pressed(KEY_Q):
		_yaw += ROT_SPEED * delta
	if Input.is_key_pressed(KEY_E):
		_yaw -= ROT_SPEED * delta
	# Ghost : suit le raycast caméra → terrain.
	var hit := _aim_ground()
	if hit.valid:
		_ghost.visible = true
		var half_y := 0.0
		if not _plant_mode and PIECES.has(_item):
			half_y = (PIECES[_item]["size"] as Vector3).y * 0.5
		_ghost.global_position = (hit.pos as Vector3) + Vector3.UP * half_y
		_ghost.rotation = Vector3(0.0, _yaw, 0.0)
	else:
		_ghost.visible = false
	# Poser : clic / gâchette (front montant).
	var pressed: bool = _player.has_method("harvest_pressed") and _player.harvest_pressed()
	var edge := pressed and not _place_prev
	_place_prev = pressed
	if edge and hit.valid:
		if _plant_mode:
			if Inventory.resource_count(_plant_seed) > 0:
				_place_sapling(hit.pos as Vector3)
		elif Inventory.resource_count(_item) > 0:
			_place_piece(hit.pos as Vector3)
	# Annuler : Escape.
	if Input.is_action_just_pressed("ui_cancel"):
		stop()

# ─── Raycast caméra → sol ────────────────────────────────────────────────────
func _aim_ground() -> Dictionary:
	var space := get_world_3d().direct_space_state
	if space == null:
		return {"valid": false}
	var cam = _player.get_active_camera() if _player.has_method("get_active_camera") else null
	if cam == null:
		return {"valid": false}
	var from: Vector3 = cam.global_position
	var to: Vector3 = from - cam.global_transform.basis.z * AIM_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	var result := space.intersect_ray(query)
	if result.is_empty():
		return {"valid": false}
	return {"valid": true, "pos": result.position}

# ─── Pose de pièce de construction ───────────────────────────────────────────
func _place_piece(ground: Vector3) -> void:
	Inventory.consume_resource(_item, 1)
	if not PIECES.has(_item):
		return
	var p: Dictionary = PIECES[_item]
	var sz: Vector3 = p["size"] as Vector3
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _piece_meshes[_item]
	mi.material_override = _piece_mats[_item]
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = sz
	col.shape = shape
	body.add_child(col)
	# Lanterne dorée : lumière ponctuelle chaude.
	if p.get("light", false):
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.88, 0.55)
		light.light_energy = 1.8
		light.omni_range = 8.0
		light.omni_attenuation = 1.5
		light.shadow_enabled = false
		body.add_child(light)
	add_child(body)
	body.global_position = ground + Vector3.UP * sz.y * 0.5
	body.rotation = Vector3(0.0, _yaw, 0.0)
	if _player.has_method("harvest_feedback"):
		_player.harvest_feedback()
	# Plus de stock → quitter le mode construction.
	if Inventory.resource_count(_item) <= 0:
		stop()

# ─── Plantation de graine ────────────────────────────────────────────────────
func _place_sapling(ground: Vector3) -> void:
	Inventory.consume_resource(_plant_seed, 1)
	var look: Dictionary = SEED_LOOK.get(_plant_seed, {"canopy": Color(0.30, 0.50, 0.22), "scale": 2.8})
	var max_sc: float = float(look["scale"])
	var node := MeshInstance3D.new()
	node.mesh = _sapling_mesh
	node.material_override = _sapling_mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(node)
	node.global_position = ground
	node.rotation = Vector3(0.0, _yaw, 0.0)
	node.scale = Vector3.ONE * 0.18   # commence petit
	_saplings.append({"node": node, "timer": 0.0, "max_scale": max_sc})
	if _player.has_method("harvest_feedback"):
		_player.harvest_feedback()
	if Inventory.resource_count(_plant_seed) <= 0:
		stop()

# Fait pousser les arbustes plantés (scale linéaire de 0.18 → max_scale sur GROW_TIME).
func _grow_saplings(delta: float) -> void:
	var i := 0
	while i < _saplings.size():
		var s: Dictionary = _saplings[i]
		var n: MeshInstance3D = s["node"] as MeshInstance3D
		if not is_instance_valid(n):
			_saplings.remove_at(i); continue
		s["timer"] = float(s["timer"]) + delta
		var t := clampf(float(s["timer"]) / GROW_TIME, 0.0, 1.0)
		var sc: float = lerpf(0.18, float(s["max_scale"]), t)
		n.scale = Vector3.ONE * sc
		if t >= 1.0:
			# Arbre adulte : ajouter une collision cylindrique (tronc).
			var body := StaticBody3D.new()
			var col := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.3 * sc
			cyl.height = 1.5 * sc
			col.shape = cyl
			body.add_child(col)
			n.add_child(body)
			body.position = Vector3(0.0, cyl.height * 0.5, 0.0)
			_saplings.remove_at(i); continue
		i += 1

# ─── Mesh procédural d'arbuste (tronc cylindrique + canopée octaèdre) ───────
func _make_sapling(canopy_color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_col := Color(0.35, 0.24, 0.14)
	var trunk_h := 1.0
	var trunk_r := 0.06
	var segs := 5
	# Tronc (cylindre).
	for s in segs:
		var a0 := float(s) / segs * TAU
		var a1 := float(s + 1) / segs * TAU
		var b0 := Vector3(cos(a0) * trunk_r, 0.0, sin(a0) * trunk_r)
		var b1 := Vector3(cos(a1) * trunk_r, 0.0, sin(a1) * trunk_r)
		var t0 := b0 + Vector3.UP * trunk_h
		var t1 := b1 + Vector3.UP * trunk_h
		st.set_color(trunk_col)
		st.add_vertex(b0); st.add_vertex(t0); st.add_vertex(b1)
		st.add_vertex(b1); st.add_vertex(t0); st.add_vertex(t1)
	# Canopée (octaèdre simplifié — 8 faces, aspect buissonnant).
	var cy := trunk_h + 0.45
	var cr := 0.55
	var verts: Array[Vector3] = [
		Vector3(0, cy + cr, 0), Vector3(0, cy - cr, 0),
		Vector3(cr, cy, 0), Vector3(-cr, cy, 0),
		Vector3(0, cy, cr), Vector3(0, cy, -cr),
	]
	var tris := [0,2,4, 0,4,3, 0,3,5, 0,5,2, 1,4,2, 1,3,4, 1,5,3, 1,2,5]
	st.set_color(canopy_color)
	for ti in range(0, tris.size(), 3):
		st.add_vertex(verts[tris[ti]])
		st.add_vertex(verts[tris[ti + 1]])
		st.add_vertex(verts[tris[ti + 2]])
	st.generate_normals()
	return st.commit()
