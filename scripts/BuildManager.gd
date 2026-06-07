extends Node3D
## Mode construction (CP4) : fabriquer et placer des éléments dans le monde.
## — Pièces de CONSTRUCTION (planches, murs, toits, piliers, portes, lanternes)
## — PLANTATION de graines (arbuste qui pousse en arbre au fil du temps)
## — ÉDITION : viser une pièce déjà posée pour la SUPPRIMER (récupère le matériau) ou la DÉPLACER.
## Ghost (aperçu transparent) suit le raycast caméra. Q/E = rotation. Clic = poser. Escape = annuler.
## Bureau : X = supprimer la pièce visée, G = la déplacer. Casque : grip court = déplacer, grip long = supprimer.

const AIM_RANGE := 12.0     # m : portée de visée
const ROT_SPEED := 2.5      # rad/s : rotation Q/E
const GROW_TIME := 180.0    # s : temps de pousse d'un arbuste planté → arbre adulte
const GRIP_DELETE_TIME := 0.5   # s : maintien du grip VR (sur une pièce visée) pour SUPPRIMER (appui court = déplacer)
const GRID := 1.0   # m : pas de grille des blocs cubiques (pose alignée + empilage face-à-face façon Minecraft)

const HL := preload("res://scripts/HarvestLibrary.gd")   # noms FR des matériaux (rendus dans les invites)

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
	# Blocs cubiques 1 m (façon Minecraft) : « cube » => pose alignée sur grille + empilage sur la face visée.
	"block_wood":  {"size": Vector3.ONE, "color": Color(0.55, 0.40, 0.24), "metallic": 0.0,  "roughness": 0.85, "cube": true},
	"block_stone": {"size": Vector3.ONE, "color": Color(0.52, 0.52, 0.55), "metallic": 0.0,  "roughness": 0.92, "cube": true},
	"block_leaf":  {"size": Vector3.ONE, "color": Color(0.26, 0.50, 0.24), "metallic": 0.0,  "roughness": 0.80, "cube": true},
	"block_iron":  {"size": Vector3.ONE, "color": Color(0.62, 0.64, 0.68), "metallic": 0.70, "roughness": 0.35, "cube": true},
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

# Édition des constructions posées (viser → supprimer / déplacer).
var _placed: Array = []        # [{body: StaticBody3D, mi: MeshInstance3D, item: String, yaw: float}]
var _edit_label: Label3D       # invite « Suppr / Déplacer » au-dessus de la pièce visée
var _hi_mat: StandardMaterial3D # surbrillance (material_overlay) de la pièce visée
var _hi_mi: MeshInstance3D      # pièce actuellement surlignée (pour restaurer l'overlay)
var _del_prev := false          # front touche X (bureau)
var _mov_prev := false          # front touche G (bureau)
var _grip_prev := false         # état grip VR (frame précédente)
var _grip_hold := 0.0           # durée de maintien du grip VR (distingue déplacer/supprimer)
var _grip_used := false         # grip déjà « consommé » par une suppression (ignore le relâchement)

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
	# Édition : surbrillance (overlay translucide cyan) appliquée à la pièce visée, + étiquette d'invite.
	_hi_mat = StandardMaterial3D.new()
	_hi_mat.albedo_color = Color(0.35, 0.95, 1.0, 0.30)
	_hi_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hi_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hi_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_edit_label = Label3D.new()
	_edit_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_edit_label.no_depth_test = true
	_edit_label.fixed_size = true
	_edit_label.pixel_size = 0.0009
	_edit_label.font_size = 36
	_edit_label.outline_size = 12
	_edit_label.modulate = Color(0.8, 0.97, 1.0)
	_edit_label.outline_modulate = Color(0, 0, 0, 0.85)
	_edit_label.visible = false
	add_child(_edit_label)

# ─── Modes ───────────────────────────────────────────────────────────────────
func start(item: String) -> void:
	_clear_edit()
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
	_clear_edit()
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
	if _player == null:
		return
	# Hors mode placement : ÉDITION des pièces déjà posées (viser → supprimer / déplacer).
	if not _active:
		_edit_update(delta)
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
	# Ghost : suit le raycast caméra. Pièces normales = posées au sol ; blocs cubiques = grille + empilage.
	var hit := _aim_ground()
	if hit.valid:
		_ghost.visible = true
		if _plant_mode:
			_ghost.global_position = hit.pos as Vector3
			_ghost.rotation = Vector3(0.0, _yaw, 0.0)
		else:
			_ghost.global_position = _place_center(hit)
			_ghost.rotation = Vector3(0.0, (0.0 if _is_cube(_item) else _yaw), 0.0)
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
			_place_piece(_place_center(hit), (0.0 if _is_cube(_item) else _yaw))
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
	var col = result.get("collider")
	var on_piece := col != null and (col is Node) and (col as Node).is_in_group("build_piece")
	return {"valid": true, "pos": result.position, "normal": result.get("normal", Vector3.UP), "on_piece": on_piece, "collider": col}

# Centre MONDE final où poser la pièce courante, selon le type.
# — Bloc cubique : sur une PIÈCE visée => cellule voisine flush (face) ; sur le TERRAIN => grille X/Z + base au sol.
# — Pièce normale : posée au sol, centrée en hauteur (comportement d'origine).
func _place_center(hit: Dictionary) -> Vector3:
	var pos: Vector3 = hit.pos
	if not PIECES.has(_item):
		return pos
	var sz: Vector3 = PIECES[_item]["size"] as Vector3
	if _is_cube(_item):
		var n: Vector3 = hit.get("normal", Vector3.UP)
		var col = hit.get("collider")
		if bool(hit.get("on_piece", false)) and col != null and col is Node3D:
			return (col as Node3D).global_position + n * GRID   # voisin flush de la pièce visée (empilage net)
		return Vector3(_grid1(pos.x), pos.y + sz.y * 0.5, _grid1(pos.z))   # 1er bloc : grille X/Z, base au sol
	return pos + Vector3.UP * sz.y * 0.5

func _is_cube(item: String) -> bool:
	return PIECES.has(item) and bool(PIECES[item].get("cube", false))

# Centre de cellule de grille le plus proche sur un axe (cellules [k, k+1) centrées en k+0.5).
func _grid1(v: float) -> float:
	return (floor(v / GRID) + 0.5) * GRID

# ─── Pose de pièce de construction (center = centre MONDE déjà résolu ; yaw = lacet) ─────────
func _place_piece(center: Vector3, yaw: float) -> void:
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
	body.global_position = center
	body.rotation = Vector3(0.0, yaw, 0.0)
	# Suivi pour l'édition (visée → supprimer / déplacer).
	body.add_to_group("build_piece")
	_placed.append({"body": body, "mi": mi, "item": _item, "yaw": yaw})
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

# ─── Édition des pièces posées (viser → supprimer / déplacer) ───────────────
# Active hors mode placement : on vise une construction posée, on la surligne et on l'édite.
func _edit_update(delta: float) -> void:
	# Garde-fous : il faut des pièces, mains libres (pas d'arme/outil), aucun menu ouvert.
	if _placed.is_empty():
		_clear_edit(); return
	if _player.has_method("is_armed") and _player.is_armed():
		_clear_edit(); return
	if _player.has_method("active_tool") and _player.active_tool() != "":
		_clear_edit(); return
	if GameState.options_open or GameState.start_menu_open:
		_clear_edit(); return
	var entry = _aim_piece()
	if entry == null:
		_clear_edit(); return
	var body: StaticBody3D = entry["body"]
	_set_highlight(entry["mi"] as MeshInstance3D)
	_edit_label.global_position = body.global_position + Vector3.UP * 0.5
	if GameState.xr_active:
		_edit_label.text = "Grip court : déplacer\nGrip long : supprimer"
	else:
		_edit_label.text = "X : supprimer   ·   G : déplacer"
	_edit_label.visible = true
	_handle_edit_input(entry, delta)

# Entrées d'édition : bureau (X = supprimer, G = déplacer) ; casque (grip court = déplacer, long = supprimer).
func _handle_edit_input(entry: Dictionary, delta: float) -> void:
	if GameState.xr_active:
		var grip := 0.0
		if _player.has_method("build_edit_grip"):
			grip = float(_player.build_edit_grip())
		var held := grip > 0.6
		if held and not _grip_prev:
			_grip_hold = 0.0
			_grip_used = false
		if held:
			_grip_hold += delta
			if _grip_hold >= GRIP_DELETE_TIME and not _grip_used:
				_grip_used = true
				_delete_piece(entry)        # maintien long → supprimer
		elif _grip_prev and not _grip_used:
			_move_piece(entry)              # relâché avant le seuil → déplacer
		_grip_prev = held
	else:
		var del := Input.is_physical_key_pressed(KEY_X)
		if del and not _del_prev:
			_delete_piece(entry)
		_del_prev = del
		var mov := Input.is_physical_key_pressed(KEY_G)
		if mov and not _mov_prev:
			_move_piece(entry)
		_mov_prev = mov

# Raycast caméra → renvoie l'entrée de la pièce de construction visée (ou null).
func _aim_piece():
	var space := get_world_3d().direct_space_state
	if space == null:
		return null
	var cam = _player.get_active_camera() if _player.has_method("get_active_camera") else null
	if cam == null:
		return null
	var from: Vector3 = cam.global_position
	var to: Vector3 = from - cam.global_transform.basis.z * AIM_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	var result := space.intersect_ray(query)
	if result.is_empty():
		return null
	var col = result.get("collider")
	if col == null or not (col is Node) or not (col as Node).is_in_group("build_piece"):
		return null
	return _entry_for(col)

func _entry_for(body):
	for e in _placed:
		if e["body"] == body:
			return e
	return null

# Surbrillance (overlay) de la pièce visée — restaure proprement l'ancienne.
func _set_highlight(mi: MeshInstance3D) -> void:
	if mi == _hi_mi:
		return
	if _hi_mi != null and is_instance_valid(_hi_mi):
		_hi_mi.material_overlay = null
	_hi_mi = mi
	if _hi_mi != null and is_instance_valid(_hi_mi):
		_hi_mi.material_overlay = _hi_mat

# Quitte l'état d'édition : enlève la surbrillance, masque l'invite, réarme les fronts d'entrée.
func _clear_edit() -> void:
	_set_highlight(null)
	if _edit_label != null:
		_edit_label.visible = false
	_del_prev = false
	_mov_prev = false
	_grip_prev = false
	_grip_hold = 0.0
	_grip_used = false

# SUPPRIME une pièce posée et REND son matériau à l'inventaire.
func _delete_piece(entry: Dictionary) -> void:
	if not _placed.has(entry):
		return   # déjà traitée cette frame (anti double-action)
	var body = entry.get("body")
	var item := String(entry.get("item", ""))
	_set_highlight(null)
	_placed.erase(entry)
	if is_instance_valid(body):
		body.queue_free()
	if item != "":
		Inventory.add_resource(item, 1)   # récupère le matériau
	if _player.has_method("harvest_feedback"):
		_player.harvest_feedback()
	if _edit_label != null:
		_edit_label.visible = false

# DÉPLACE une pièce : la retire, rend le matériau, puis ré-entre en placement (la repose la reconsomme).
func _move_piece(entry: Dictionary) -> void:
	if not _placed.has(entry):
		return   # déjà traitée cette frame (anti double-action)
	var body = entry.get("body")
	var item := String(entry.get("item", ""))
	var yaw := float(entry.get("yaw", 0.0))
	if item == "" or not PIECES.has(item):
		return
	_set_highlight(null)
	_placed.erase(entry)
	if is_instance_valid(body):
		body.queue_free()
	Inventory.add_resource(item, 1)   # rendu en stock : la repose la reconsomme (déplacement net = zéro coût)
	start(item)                       # ré-entre en placement avec ce type de pièce
	_yaw = yaw                         # conserve l'orientation d'origine
	if _player.has_method("harvest_feedback"):
		_player.harvest_feedback()
