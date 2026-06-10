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
const PLANTED_SCAN_CAP := 48   # plafond de candidats d'abattage retournés/scan (borne le coût même avec bcp d'arbres plantés)
const GRIP_DELETE_TIME := 0.5   # s : maintien du grip VR (sur une pièce visée) pour SUPPRIMER (appui court = déplacer)
const GRID := 1.0   # m : pas de grille des blocs cubiques (pose alignée + empilage face-à-face façon Minecraft)

# Pièces qui reçoivent un MESH DÉDIÉ (composé de primitives, CP-CRAFT polish) au lieu d'une simple boîte.
# La collision reste la boîte englobante (PIECES.size) — seul le visuel change. Les autres pièces (planches,
# murs, blocs, dalles, lumières émissives…) restent des boîtes (déjà lisibles comme dalles/blocs).
const DEDICATED_MESH := {
	"table_wood": true, "chair_wood": true, "shelf_wood": true, "chest_wood": true, "barrel_wood": true,
	"bed_wood": true, "column_stone": true, "statue_stone": true, "fence_wood": true, "ladder_wood": true,
	"stairs_wood": true, "window_wood": true, "raft_wood": true,
}

# Pièces POSÉES SUR L'EAU (pas sur le sol) : la visée croise le niveau de mer LOCAL courbé au lieu du
# raycast physique terrain (l'eau n'a pas de collider). La pièce flotte, bas de boîte au ras de l'eau.
const WATER_PIECES := {"raft_wood": true}
const RAFT_MIN_DEPTH := 0.5   # m : le sol doit être sous la mer d'au moins ça au point visé (= vraie eau)

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
	"block_copper":{"size": Vector3.ONE, "color": Color(0.72, 0.48, 0.30), "metallic": 0.60, "roughness": 0.38, "cube": true},
	"block_gold":  {"size": Vector3.ONE, "color": Color(0.92, 0.76, 0.32), "metallic": 0.85, "roughness": 0.18, "cube": true},
	# Construction étendue (CP-CRAFT) — pièces posables (boîtes simples ; meshes dédiés = CP polish).
	"beam_wood":   {"size": Vector3(0.22, 0.22, 3.0), "color": Color(0.50, 0.36, 0.20), "metallic": 0.0, "roughness": 0.85},
	"fence_wood":  {"size": Vector3(2.0, 1.0, 0.10),  "color": Color(0.54, 0.39, 0.22), "metallic": 0.0, "roughness": 0.85},
	"ladder_wood": {"size": Vector3(0.8, 2.6, 0.10),  "color": Color(0.56, 0.41, 0.24), "metallic": 0.0, "roughness": 0.85},
	"stairs_wood": {"size": Vector3(1.4, 1.0, 1.4),   "color": Color(0.52, 0.38, 0.21), "metallic": 0.0, "roughness": 0.85},
	"window_wood": {"size": Vector3(1.3, 1.3, 0.10),  "color": Color(0.60, 0.46, 0.28), "metallic": 0.0, "roughness": 0.70},
	"floor_stone": {"size": Vector3(2.0, 0.12, 2.0),  "color": Color(0.50, 0.49, 0.46), "metallic": 0.0, "roughness": 0.92},
	# Mobilier / déco (CP-CRAFT).
	"table_wood":  {"size": Vector3(1.4, 0.85, 0.9),  "color": Color(0.55, 0.40, 0.23), "metallic": 0.0, "roughness": 0.82},
	"chair_wood":  {"size": Vector3(0.6, 1.0, 0.6),   "color": Color(0.55, 0.40, 0.23), "metallic": 0.0, "roughness": 0.82},
	"shelf_wood":  {"size": Vector3(1.6, 1.8, 0.4),   "color": Color(0.52, 0.38, 0.22), "metallic": 0.0, "roughness": 0.84},
	"chest_wood":  {"size": Vector3(1.0, 0.7, 0.7),   "color": Color(0.48, 0.34, 0.18), "metallic": 0.0, "roughness": 0.80},
	"barrel_wood": {"size": Vector3(0.8, 1.0, 0.8),   "color": Color(0.50, 0.36, 0.20), "metallic": 0.0, "roughness": 0.82},
	"bed_wood":    {"size": Vector3(1.2, 0.5, 2.2),   "color": Color(0.46, 0.40, 0.30), "metallic": 0.0, "roughness": 0.85},
	"column_stone":{"size": Vector3(0.5, 2.5, 0.5),   "color": Color(0.55, 0.54, 0.50), "metallic": 0.0, "roughness": 0.90},
	"statue_stone":{"size": Vector3(0.8, 2.2, 0.8),   "color": Color(0.58, 0.57, 0.53), "metallic": 0.0, "roughness": 0.90},
	"rug_leaf":    {"size": Vector3(2.0, 0.05, 1.4),  "color": Color(0.45, 0.30, 0.32), "metallic": 0.0, "roughness": 0.95},
	"banner_leaf": {"size": Vector3(1.0, 1.6, 0.06),  "color": Color(0.40, 0.50, 0.62), "metallic": 0.0, "roughness": 0.90},
	# Lumière (CP-CRAFT) : émissives + lumière (comme lamp_gold).
	"torch_wood":    {"size": Vector3(0.12, 0.9, 0.12), "color": Color(0.40, 0.28, 0.16), "metallic": 0.0,  "roughness": 0.80,
					  "emission": Color(1.0, 0.62, 0.25), "emission_energy": 2.4, "light": true},
	"brazier_stone": {"size": Vector3(0.6, 0.8, 0.6),   "color": Color(0.50, 0.48, 0.46), "metallic": 0.0,  "roughness": 0.88,
					  "emission": Color(1.0, 0.55, 0.20), "emission_energy": 2.8, "light": true},
	"lantern_iron":  {"size": Vector3(0.3, 0.5, 0.3),   "color": Color(0.58, 0.60, 0.64), "metallic": 0.70, "roughness": 0.30,
					  "emission": Color(0.9, 0.92, 1.0), "emission_energy": 1.8, "light": true},
	# Radeau (CP-PÊCHE) : plateforme de rondins posée SUR L'EAU (cf. WATER_PIECES). Boîte de collision plate
	# (bas au ras de la mer) → on marche dessus ; mesh dédié = rondins liés + traverses.
	"raft_wood":     {"size": Vector3(2.6, 0.40, 2.6),  "color": Color(0.52, 0.38, 0.22), "metallic": 0.0,  "roughness": 0.85},
}

# Apparence visuelle par graine (couleur canopée + échelle adulte).
static var SEED_LOOK := {
	"seed_deciduous": {"canopy": Color(0.28, 0.50, 0.22), "scale": 2.8},
	"seed_palm":      {"canopy": Color(0.30, 0.55, 0.24), "scale": 3.2},
	"seed_conifer":   {"canopy": Color(0.16, 0.32, 0.18), "scale": 3.5},
	"seed_twisted":   {"canopy": Color(0.42, 0.28, 0.42), "scale": 2.4},
}

var _player: Node = null
var _chunks = null            # ChunkManager (poussé par SurfaceView.update) : ground_height_at pour valider l'eau
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
var _sapling_mat: StandardMaterial3D   # repli si le matériau de végétation partagé n'est pas fourni
var _veg_wind_mat: Material = null     # matériau de vent PARTAGÉ (= arbres semés) : balancement + biolum cohérents
var _saplings: Array = []      # [{node: MeshInstance3D, timer: float, max_scale: float, seed_id, grown}]

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
		_piece_meshes[id] = _build_piece_mesh(String(id), p)
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
func update(delta: float, chunks = null) -> void:
	if chunks != null:
		_chunks = chunks   # ChunkManager : nécessaire pour valider la pose du radeau au-dessus de l'eau
	# Faire pousser les arbustes plantés (indépendant du mode construction actif).
	_grow_saplings(delta)
	if _player == null:
		return
	# Hors mode placement : ÉDITION des pièces déjà posées (viser → supprimer / déplacer).
	if not _active:
		_edit_update(delta)
		return
	# Annulation si le joueur sort une arme, un outil ou la canne à pêche.
	if _player.has_method("is_armed") and _player.is_armed():
		stop(); return
	if _player.has_method("active_tool") and _player.active_tool() != "":
		stop(); return
	if _player.has_method("is_fishing") and _player.is_fishing():
		stop(); return
	# Rotation (bureau : Q/E).
	if Input.is_key_pressed(KEY_Q):
		_yaw += ROT_SPEED * delta
	if Input.is_key_pressed(KEY_E):
		_yaw -= ROT_SPEED * delta
	# Ghost : suit le raycast caméra. Pièces normales = posées au sol ; blocs cubiques = grille + empilage ;
	# radeau (pièce d'EAU) = croisement du niveau de mer local (l'eau n'a pas de collider physique).
	var hit := _aim_water_surf() if _is_water(_item) else _aim_ground()
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

func _is_water(item: String) -> bool:
	return bool(WATER_PIECES.get(item, false))

# Visée pour une pièce posée SUR L'EAU (radeau) : croisement du rayon caméra avec le niveau de mer LOCAL
# courbé (= PlayerController.sea_level_at, même formule que le shader d'eau). Valide « eau » si le sol au
# point visé est immergé d'au moins RAFT_MIN_DEPTH (sinon c'est la plage / la terre). Renvoie un hit au ras
# de la mer ; _place_center (pièce non-cube) recentre la boîte en hauteur → bas du radeau au niveau de l'eau.
func _aim_water_surf() -> Dictionary:
	var cam = _player.get_active_camera() if _player.has_method("get_active_camera") else null
	if cam == null or not _player.has_method("sea_level_at"):
		return {"valid": false}
	var from: Vector3 = cam.global_position
	var dir: Vector3 = -cam.global_transform.basis.z
	if dir.y > -0.05:
		return {"valid": false}                                # il faut viser vers le bas (l'eau)
	var sea0: float = _player.sea_level_at(from.x, from.z)
	var t := (sea0 - from.y) / dir.y                           # dir.y < 0 garanti
	if t <= 0.0 or t > AIM_RANGE * 2.0:
		return {"valid": false}
	var p := from + dir * t
	p.y = _player.sea_level_at(p.x, p.z)                       # recale sur la mer courbée au point visé
	if _chunks != null and _chunks.has_method("ground_height_at"):
		if _chunks.ground_height_at(p) > p.y - RAFT_MIN_DEPTH:
			return {"valid": false}                            # pas assez d'eau ici (plage / haut-fond)
	return {"valid": true, "pos": p, "normal": Vector3.UP, "on_piece": false, "collider": null}

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

# Matériau de végétation PARTAGÉ (depuis la VegetationLibrary du ChunkManager) : les arbres PLANTÉS
# balancent au vent, suivent la météo et s'illuminent la nuit EXACTEMENT comme les arbres semés.
func set_vegetation_material(mat: Material) -> void:
	_veg_wind_mat = mat

# ─── Plantation de graine ────────────────────────────────────────────────────
func _place_sapling(ground: Vector3) -> void:
	Inventory.consume_resource(_plant_seed, 1)
	var look: Dictionary = SEED_LOOK.get(_plant_seed, {"canopy": Color(0.30, 0.50, 0.22), "scale": 2.8})
	var max_sc: float = float(look["scale"])
	var node := MeshInstance3D.new()
	node.mesh = _sapling_mesh
	node.material_override = _veg_wind_mat if _veg_wind_mat != null else _sapling_mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(node)
	node.global_position = ground
	node.rotation = Vector3(0.0, _yaw, 0.0)
	node.scale = Vector3.ONE * 0.18   # commence petit
	# seed_id : retenu pour l'ABATTAGE (espèce → rendement bois) ; grown : adulte (collision posée).
	_saplings.append({"node": node, "timer": 0.0, "max_scale": max_sc, "seed_id": _plant_seed, "grown": false})
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
		if bool(s.get("grown", false)):
			i += 1; continue   # arbre adulte : croissance finie, mais TOUJOURS suivi (abattable)
		s["timer"] = float(s["timer"]) + delta
		var t := clampf(float(s["timer"]) / GROW_TIME, 0.0, 1.0)
		var sc: float = lerpf(0.18, float(s["max_scale"]), t)
		n.scale = Vector3.ONE * sc
		if t >= 1.0:
			# Arbre adulte : ajouter une collision cylindrique (tronc), UNE fois. On le GARDE dans
			# _saplings (désormais récoltable comme tout arbre — abattage par HarvestManager).
			var body := StaticBody3D.new()
			var col := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.3 * sc
			cyl.height = 1.5 * sc
			col.shape = cyl
			body.add_child(col)
			n.add_child(body)
			body.position = Vector3(0.0, cyl.height * 0.5, 0.0)
			s["grown"] = true
		i += 1

# ─── Récolte : arbres PLANTÉS abattables (tous les arbres peuvent être coupés) ──
# Les arbres issus de graines plantées par le joueur sont des arbres à part entière : HarvestManager
# les cible et les abat exactement comme les arbres semés (rendement bois selon l'espèce de la graine).

# Arbres plantés proches d'une position MONDE (pour le ciblage d'abattage). Lecture seule.
# Retourne [{ "node": Node3D, "pos": Vector3 (MONDE, pied), "species": int }].
func planted_trees_near(world_pos: Vector3, radius: float) -> Array:
	var out: Array = []
	var r2 := radius * radius
	for s in _saplings:
		if out.size() >= PLANTED_SCAN_CAP:
			break   # plafond : HarvestManager ne vise que le plus proche => inutile d'en collecter plus
		if not bool(s.get("grown", false)):
			continue   # un semis encore en croissance n'est PAS un arbre abattable (pas de bois plein)
		var n: MeshInstance3D = s.get("node") as MeshInstance3D
		if not is_instance_valid(n):
			continue
		var p := n.global_position
		if p.distance_squared_to(world_pos) <= r2:
			out.append({"node": n, "pos": p, "species": _species_of_seed(String(s.get("seed_id", "")))})
	return out

# Abat un arbre planté (par node) : le retire du suivi + libère le node, renvoie le rendement bois
# { "wood": id, "qty": int, "seed": id } (ou {} si introuvable).
func chop_planted_tree(node: Node3D) -> Dictionary:
	for i in _saplings.size():
		if _saplings[i].get("node") == node:
			var sp := _species_of_seed(String(_saplings[i].get("seed_id", "")))
			var yld := HL.species_yield(sp)
			_saplings.remove_at(i)
			if is_instance_valid(node):
				node.queue_free()
			return {
				"wood": String(yld.get("wood", "")),
				"qty": randi_range(HL.WOOD_PER_TREE_MIN, HL.WOOD_PER_TREE_MAX),
				"seed": String(yld.get("seed", "")),
			}
	return {}

# Espèce (SpeciesLibrary.Species) correspondant à une graine plantable (repli = feuillu).
static func _species_of_seed(seed_id: String) -> int:
	match seed_id:
		"seed_palm": return SpeciesLibrary.Species.PALM
		"seed_conifer": return SpeciesLibrary.Species.CONIFER
		"seed_twisted": return SpeciesLibrary.Species.TWISTED
	return SpeciesLibrary.Species.DECIDUOUS

# ─── Meshes DÉDIÉS des pièces (mobilier / déco) ─────────────────────────────
# Compose des primitives (BoxMesh / CylinderMesh) en UNE surface via SurfaceTool.append_from : normales et
# winding garantis corrects (pas de mesh manuel). Repère LOCAL centré sur la boîte englobante (sol en y=-sz.y/2),
# cohérent avec _place_center qui pose la pièce centrée en hauteur. Les pièces non dédiées restent des boîtes.
func _build_piece_mesh(id: String, p: Dictionary) -> Mesh:
	var sz: Vector3 = p["size"] as Vector3
	if not DEDICATED_MESH.has(id):
		var bm := BoxMesh.new()
		bm.size = sz
		return bm
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var g := -sz.y * 0.5   # niveau du sol dans le repère local
	match id:
		"table_wood":   _mk_table(st, sz, g)
		"chair_wood":   _mk_chair(st, sz, g)
		"shelf_wood":   _mk_shelf(st, sz, g)
		"chest_wood":   _mk_chest(st, sz, g)
		"barrel_wood":  _mk_barrel(st, sz, g)
		"bed_wood":     _mk_bed(st, sz, g)
		"column_stone": _mk_column(st, sz, g)
		"statue_stone": _mk_statue(st, sz, g)
		"fence_wood":   _mk_fence(st, sz, g)
		"ladder_wood":  _mk_ladder(st, sz, g)
		"stairs_wood":  _mk_stairs(st, sz, g)
		"window_wood":  _mk_window(st, sz, g)
		"raft_wood":    _mk_raft(st, sz, g)
	return st.commit()

# Ajoute une boîte (centre + dimensions) à la surface en cours.
func _part_box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var b := BoxMesh.new()
	b.size = size
	st.append_from(b, 0, Transform3D(Basis(), center))

# Ajoute un cylindre vertical (centre + rayon + hauteur) à la surface en cours.
func _part_cyl(st: SurfaceTool, center: Vector3, radius: float, height: float, segs: int = 12) -> void:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segs
	c.rings = 0
	st.append_from(c, 0, Transform3D(Basis(), center))

func _mk_table(st: SurfaceTool, sz: Vector3, g: float) -> void:
	_part_box(st, Vector3(0, sz.y * 0.5 - 0.06, 0), Vector3(sz.x, 0.12, sz.z))          # plateau
	var lh := sz.y - 0.12                                                                # pieds
	var lx := sz.x * 0.5 - 0.1
	var lz := sz.z * 0.5 - 0.1
	for sx in [-1.0, 1.0]:
		for sz2 in [-1.0, 1.0]:
			_part_box(st, Vector3(lx * sx, g + lh * 0.5, lz * sz2), Vector3(0.1, lh, 0.1))

func _mk_chair(st: SurfaceTool, sz: Vector3, g: float) -> void:
	var seat_y := g + 0.46
	_part_box(st, Vector3(0, seat_y, 0), Vector3(sz.x, 0.08, sz.z))                      # assise
	_part_box(st, Vector3(0, seat_y + 0.31, -sz.z * 0.5 + 0.04), Vector3(sz.x, 0.62, 0.08))  # dossier
	var lx := sz.x * 0.5 - 0.06
	var lz := sz.z * 0.5 - 0.06
	for sx in [-1.0, 1.0]:
		for sz2 in [-1.0, 1.0]:
			_part_box(st, Vector3(lx * sx, g + 0.23, lz * sz2), Vector3(0.08, 0.46, 0.08))

func _mk_shelf(st: SurfaceTool, sz: Vector3, g: float) -> void:
	_part_box(st, Vector3(0, 0, -sz.z * 0.5 + 0.03), Vector3(sz.x, sz.y, 0.06))          # fond
	for sx in [-1.0, 1.0]:
		_part_box(st, Vector3((sz.x * 0.5 - 0.04) * sx, 0, 0), Vector3(0.08, sz.y, sz.z))  # montants
	for ty in [g + 0.1, 0.0, sz.y * 0.5 - 0.1]:                                          # tablettes
		_part_box(st, Vector3(0, ty, 0), Vector3(sz.x - 0.16, 0.05, sz.z - 0.06))

func _mk_chest(st: SurfaceTool, sz: Vector3, g: float) -> void:
	_part_box(st, Vector3(0, g + 0.25, 0), Vector3(sz.x, 0.5, sz.z))                     # caisse
	_part_box(st, Vector3(0, g + 0.5 + 0.1, 0), Vector3(sz.x - 0.04, 0.2, sz.z - 0.04))  # couvercle

func _mk_barrel(st: SurfaceTool, sz: Vector3, _g: float) -> void:
	_part_cyl(st, Vector3.ZERO, sz.x * 0.46, sz.y)                                       # fût
	for ty in [-sz.y * 0.3, sz.y * 0.3]:                                                 # cerclages
		_part_cyl(st, Vector3(0, ty, 0), sz.x * 0.49, 0.08)

func _mk_bed(st: SurfaceTool, sz: Vector3, g: float) -> void:
	_part_box(st, Vector3(0, g + 0.18, 0), Vector3(sz.x, 0.22, sz.z))                    # sommier
	_part_box(st, Vector3(0, g + 0.34, 0.1), Vector3(sz.x - 0.1, 0.12, sz.z - 0.2))      # matelas
	_part_box(st, Vector3(0, g + 0.45, -sz.z * 0.5 + 0.06), Vector3(sz.x, 0.7, 0.12))    # tête de lit

func _mk_column(st: SurfaceTool, sz: Vector3, g: float) -> void:
	_part_cyl(st, Vector3.ZERO, sz.x * 0.36, sz.y)                                       # fût
	_part_box(st, Vector3(0, g + 0.1, 0), Vector3(sz.x, 0.2, sz.z))                      # socle
	_part_box(st, Vector3(0, sz.y * 0.5 - 0.1, 0), Vector3(sz.x, 0.2, sz.z))             # chapiteau

func _mk_statue(st: SurfaceTool, sz: Vector3, g: float) -> void:
	_part_box(st, Vector3(0, g + 0.2, 0), Vector3(sz.x, 0.4, sz.z))                      # socle
	_part_box(st, Vector3(0, g + 0.4 + 0.6, 0), Vector3(sz.x * 0.5, 1.2, sz.z * 0.4))    # corps
	_part_box(st, Vector3(0, g + 0.4 + 1.2 + 0.18, 0), Vector3(sz.x * 0.32, 0.34, sz.z * 0.32))  # tête

func _mk_fence(st: SurfaceTool, sz: Vector3, g: float) -> void:
	for sx in [-1.0, 1.0]:
		_part_box(st, Vector3((sz.x * 0.5 - 0.06) * sx, 0, 0), Vector3(0.12, sz.y, sz.z))  # poteaux
	for ty in [g + 0.3, g + sz.y - 0.25]:                                                # lisses
		_part_box(st, Vector3(0, ty, 0), Vector3(sz.x, 0.12, sz.z * 0.8))

func _mk_ladder(st: SurfaceTool, sz: Vector3, g: float) -> void:
	for sx in [-1.0, 1.0]:
		_part_box(st, Vector3((sz.x * 0.5 - 0.05) * sx, 0, 0), Vector3(0.1, sz.y, sz.z))   # rails
	var rungs := 5
	for i in rungs:
		var ry := g + 0.3 + (sz.y - 0.6) * float(i) / float(rungs - 1)
		_part_box(st, Vector3(0, ry, 0), Vector3(sz.x - 0.18, 0.07, sz.z))                 # barreaux

func _mk_stairs(st: SurfaceTool, sz: Vector3, g: float) -> void:
	var steps := 4
	var d := sz.z / float(steps)
	for i in steps:
		var h := sz.y * float(i + 1) / float(steps)
		var zc := -sz.z * 0.5 + d * (float(i) + 0.5)
		_part_box(st, Vector3(0, g + h * 0.5, zc), Vector3(sz.x, h, d))                    # marche

func _mk_window(st: SurfaceTool, sz: Vector3, g: float) -> void:
	_part_box(st, Vector3(0, sz.y * 0.5 - 0.1, 0), Vector3(sz.x, 0.2, sz.z))             # linteau
	_part_box(st, Vector3(0, g + 0.1, 0), Vector3(sz.x, 0.2, sz.z))                      # appui
	for sx in [-1.0, 1.0]:
		_part_box(st, Vector3((sz.x * 0.5 - 0.1) * sx, 0, 0), Vector3(0.2, sz.y, sz.z))  # montants
	_part_box(st, Vector3(0, 0, 0), Vector3(0.06, sz.y, sz.z))                           # meneau vertical
	_part_box(st, Vector3(0, 0, 0), Vector3(sz.x, 0.06, sz.z))                           # traverse horizontale

# Radeau : rondins jointifs (cylindres COUCHÉS le long de Z) + 2 traverses sur le dessus (cordage/poutres).
# Les rondins remplissent la boîte englobante (bas au ras de l'eau, dessus = pont où l'on marche).
func _mk_raft(st: SurfaceTool, sz: Vector3, _g: float) -> void:
	var n := 5
	var step := sz.x / float(n)
	var lr := step * 0.5 * 0.96                                                          # rayon d'un rondin
	var bz := Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0))                              # cylindre couché → axe Z
	for i in n:
		var lx := -sz.x * 0.5 + (float(i) + 0.5) * step
		var c := CylinderMesh.new()
		c.top_radius = lr
		c.bottom_radius = lr
		c.height = sz.z * 0.98
		c.radial_segments = 10
		c.rings = 0
		st.append_from(c, 0, Transform3D(bz, Vector3(lx, 0.0, 0.0)))                     # rondin centré en Y
	for cz in [-sz.z * 0.32, sz.z * 0.32]:                                              # traverses sur le pont
		_part_box(st, Vector3(0.0, lr * 0.85, cz), Vector3(sz.x * 0.98, 0.08, 0.14))

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
