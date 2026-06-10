extends Node3D
## Récolte (CP2 cueillette + CP3 outils). Pour les arbres/rochers proches du joueur :
##  • MAINS NUES : des FRUITS cueillables poussent sur les arbres ; le plus proche de la main se surligne ;
##    cueillette (approche + gâchette droite VR / clic gauche bureau) => fruit à l'inventaire + repousse.
##  • HACHE équipée : abat l'ARBRE le plus proche (geste physique VR / clic bureau) en N coups => BOIS + graine,
##    l'arbre DISPARAÎT (instance MultiMesh masquée) puis repousse.
##  • PIOCHE équipée : casse le ROCHER le plus proche => PIERRE (+ parfois MINERAI), même logique.
##
## On ne touche PAS au semis (déterminisme intact) : on AJOUTE des fruits + on masque/restaure des instances +
## on tient un état de récolte par instance (id = chunk+variante+index). Piloté par SurfaceView.update().

const HL := preload("res://scripts/HarvestLibrary.gd")

const SCAN_CD := 0.25       # s : période de re-scan des récoltables proches
const SCAN_RADIUS := 9.0    # m : rayon de recherche
# Arbre géant (POI) : un colosse => beaucoup de coups, gros rendement, portée d'abattage élargie (tronc large).
const GIANT_FELL_HITS := 14
const GIANT_WOOD_MIN := 18
const GIANT_WOOD_MAX := 30
const GIANT_REACH := 5.0    # m : portée d'abattage de l'arbre géant (le tronc est massif)
const MAX_TREES := 10       # arbres fruitiers suivis (fruits visibles)
const MAX_FRUIT := 30       # plafond de fruits visibles (taille du pool)
const FRUIT_H := 1.55       # m : hauteur (atteignable) des fruits autour du tronc
const FRUIT_R := 0.6        # m : rayon d'accroche
const BASE_SCALE := 0.14    # échelle de base d'un fruit

var _player: Node = null       # PlayerController
var _build: Node = null        # BuildManager — arbres PLANTÉS par le joueur (abattables aussi)
var _cm: Node = null           # ChunkManager (passé chaque frame)
var _scan_t := 0.0
var _cands: Array = []         # récoltables du dernier scan : { pos, variant, kind, index, coord }
# Cueillette (fruits)
var _state := {}               # id -> { count:int, rt:float, cap:int } : fruits par arbre
var _fruits: Array = []        # fruits visibles : { id, item, pos, mi }
var _pool: Array = []          # MeshInstance3D recyclés
var _sphere: SphereMesh
var _target := -1              # index du fruit visé
var _pick_prev := false
# Outils (abattage / minage)
var _hits := {}                # id -> coups portés (en cours)
var _depleted := {}            # id -> { rt:float, coord, variant, index } : abattu/cassé, en repousse
var _prev_hand := Vector3.ZERO
var _have_prev_hand := false
var _swing_cd := 0.0
var _hit_prev := false
var _tool_target := {}         # candidat outil visé (ou {})
var _tool_txt := ""            # invite outil (« Hacher 2/5 »)
var _tool_pos := Vector3.ZERO
# Étiquette / toast partagés
var _label: Label3D
var _msg := ""
var _msg_t := 0.0

func setup(player: Node) -> void:
	_player = player

# Réf. au BuildManager : permet d'abattre les arbres PLANTÉS (graines du joueur), pas seulement les semés.
func set_build_manager(build: Node) -> void:
	_build = build

func _ready() -> void:
	top_level = true
	_sphere = SphereMesh.new()
	_sphere.radius = 0.5
	_sphere.height = 1.0
	_sphere.radial_segments = 8
	_sphere.rings = 5
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0009
	_label.font_size = 40
	_label.outline_size = 12
	_label.modulate = Color(0.92, 1.0, 0.72)
	_label.outline_modulate = Color(0, 0, 0, 0.85)
	_label.visible = false
	add_child(_label)

# Piloté chaque frame par SurfaceView (joueur au sol). cm = ChunkManager courant.
func update(delta: float, cm: Node) -> void:
	_cm = cm
	if _player == null or not is_instance_valid(_player):
		return
	# Mode construction : seuls les timers de repousse tournent (pas d'interaction récolte).
	if GameState.build_active:
		_tick_regrow(delta)
		_tick_depletion(delta)
		return
	var armed: bool = _player.has_method("is_armed") and _player.is_armed()
	var tool: String = _player.active_tool() if _player.has_method("active_tool") else ""
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_CD
		_rescan()
	_tick_regrow(delta)
	_tick_depletion(delta)
	_tool_txt = ""
	if tool != "":
		_target = -1            # outil en main : pas de cueillette
		_update_tool(delta)
	elif not armed:
		_update_target()        # mains nues : cueillette
		_handle_pick()
		_tool_target = {}
		_have_prev_hand = false
	else:
		_target = -1
		_tool_target = {}
		_have_prev_hand = false
	if _msg_t > 0.0:
		_msg_t = maxf(_msg_t - delta, 0.0)
	_update_label()

# --- Scan des récoltables proches (throttlé) ---
func _rescan() -> void:
	if _cm == null or not _cm.has_method("harvestables_near"):
		return
	var pp: Vector3 = (_player as Node3D).global_position
	_cands = _cm.harvestables_near(pp, SCAN_RADIUS)
	# Arbres PLANTÉS par le joueur : ajoutés aux candidats d'abattage (mêmes outils, même geste).
	if _build != null and _build.has_method("planted_trees_near"):
		for pt in _build.planted_trees_near(pp, SCAN_RADIUS):
			_cands.append({"pos": pt.pos, "kind": "tree", "planted": true, "node": pt.node, "species": int(pt.species)})
	# Fruits (visuels) : seulement sur les arbres SEMÉS proches (variante connue) — pas les plantés ni l'arbre géant.
	var trees: Array = []
	for h in _cands:
		if String(h.get("kind", "")) == "tree" and not h.get("planted", false) and not h.get("poi", false):
			trees.append(h)
	trees.sort_custom(func(a, b): return (a.pos as Vector3).distance_squared_to(pp) < (b.pos as Vector3).distance_squared_to(pp))
	if trees.size() > MAX_TREES:
		trees.resize(MAX_TREES)
	_rebuild_fruits(trees)
	_apply_depletion()   # ré-applique le masquage des instances abattues (après un éventuel rebuild de chunk)

func _rebuild_fruits(trees: Array) -> void:
	for f in _fruits:
		_recycle(f.mi)
	_fruits.clear()
	for h in trees:
		var id: String = _id_of(h)
		if _depleted.has(id):
			continue   # arbre abattu (en repousse) => pas de fruits
		var v: int = int(h.variant)
		var species: int = v / VegetationLibrary.TREE_VARIANTS_PER
		var yld: Dictionary = HL.species_yield(species)
		var item: String = String(yld.get("fruit", ""))
		if item == "":
			continue
		var cap: int = int(yld.get("fruit_cap", 3))
		var st = _state.get(id)
		if st == null:
			st = {"count": cap, "rt": 0.0, "cap": cap}
			_state[id] = st
		var col: Color = HL.item_color(item)
		var n: int = mini(int(st.count), cap)
		for s in n:
			if _fruits.size() >= MAX_FRUIT:
				return
			var ang := _slot_angle(id, s, cap)
			var fp: Vector3 = (h.pos as Vector3) + Vector3.UP * FRUIT_H + Vector3(cos(ang), 0.0, sin(ang)) * FRUIT_R
			var mi := _take_pool(col)
			mi.global_transform = Transform3D(Basis().scaled(Vector3(BASE_SCALE, BASE_SCALE, BASE_SCALE)), fp)
			mi.visible = true
			_fruits.append({"id": id, "item": item, "pos": fp, "mi": mi})

# --- Cueillette mains nues : cible + surbrillance + ramassage ---
func _update_target() -> void:
	var hp: Vector3 = _player.tool_hand_point() if _player.has_method("tool_hand_point") else (_player as Node3D).global_position
	var best := -1
	var best_d := HL.PICK_REACH * HL.PICK_REACH
	for i in _fruits.size():
		var d: float = (_fruits[i].pos as Vector3).distance_squared_to(hp)
		if d < best_d:
			best_d = d
			best = i
	_target = best
	var pulse := 1.0 + 0.3 * sin(float(Time.get_ticks_msec()) * 0.012)
	for i in _fruits.size():
		var sc := BASE_SCALE * (pulse if i == best else 1.0)
		(_fruits[i].mi as MeshInstance3D).global_transform = Transform3D(Basis().scaled(Vector3(sc, sc, sc)), _fruits[i].pos)

func _handle_pick() -> void:
	var pressed: bool = _player.has_method("harvest_pressed") and _player.harvest_pressed()
	var edge := pressed and not _pick_prev
	_pick_prev = pressed
	if edge and _target >= 0 and _target < _fruits.size():
		_pick(_target)

func _pick(i: int) -> void:
	var f = _fruits[i]
	var st = _state.get(String(f.id))
	if st != null:
		st.count = maxi(0, int(st.count) - 1)
		if float(st.rt) <= 0.0:
			st.rt = HL.REGROW_FRUIT
	Inventory.add_resource(String(f.item), 1)
	if _player.has_method("harvest_feedback"):
		_player.harvest_feedback()
	_msg = "+ " + HL.item_name(String(f.item))
	_msg_t = 1.2
	_recycle(f.mi)
	_fruits.remove_at(i)
	_target = -1

# --- Outils : abattage (hache->arbre) / minage (pioche->rocher) ---
func _update_tool(delta: float) -> void:
	_swing_cd = maxf(_swing_cd - delta, 0.0)
	var hp: Vector3 = _player.tool_hand_point() if _player.has_method("tool_hand_point") else (_player as Node3D).global_position
	# Cible = ARBRE ou ROCHER le plus proche de la main, dans SA portée, non épuisé (l'outil fait les deux).
	# L'arbre géant (POI) a une portée élargie (tronc massif → on l'atteint d'un peu plus loin).
	var best := {}
	var best_d := INF
	for h in _cands:
		if _depleted.has(_id_of(h)):
			continue
		var reach: float = GIANT_REACH if h.get("poi", false) else HL.TOOL_REACH
		var d: float = (h.pos as Vector3).distance_squared_to(hp)
		if d <= reach * reach and d < best_d:
			best_d = d
			best = h
	_tool_target = best
	if not best.is_empty():
		var id := _id_of(best)
		var need := _need_for(best)
		var n := int(_hits.get(id, 0))
		_tool_txt = ("Hacher %d/%d" % [n, need]) if String(best.get("kind", "")) == "tree" else ("Miner %d/%d" % [n, need])
		_tool_pos = (best.pos as Vector3) + Vector3.UP * 1.3
		# Détection de coup : VR = geste (vitesse de main) ; bureau = clic gauche (front).
		var hit := false
		# Coup FIABLE : gâchette droite (VR) / clic gauche (bureau) = un coup à chaque pression.
		var pressed: bool = _player.has_method("harvest_pressed") and _player.harvest_pressed()
		if pressed and not _hit_prev and _swing_cd <= 0.0:
			hit = true
		_hit_prev = pressed
		# + en VR, un GESTE physique rapide compte aussi (immersion).
		if not hit and GameState.xr_active and _have_prev_hand and _swing_cd <= 0.0:
			var speed := (hp - _prev_hand).length() / maxf(delta, 0.0001)
			if speed > HL.SWING_SPEED:
				hit = true
		if hit:
			_swing_cd = HL.SWING_COOLDOWN
			_strike(best)
	_prev_hand = hp
	_have_prev_hand = true

func _need_for(h: Dictionary) -> int:
	if h.get("poi", false):
		return GIANT_FELL_HITS                       # arbre géant : colosse
	if String(h.get("kind", "")) == "tree":
		if h.get("planted", false):
			return int(HL.species_yield(int(h.get("species", 0))).get("fell_hits", 5))
		var species := int(h.variant) / VegetationLibrary.TREE_VARIANTS_PER
		return int(HL.species_yield(species).get("fell_hits", 5))
	return int(HL.rock_yield_for(int(h.variant)).get("mine_hits", 5))

func _strike(h: Dictionary) -> void:
	var id := _id_of(h)
	var n := int(_hits.get(id, 0)) + 1
	_hits[id] = n
	if _player.has_method("harvest_feedback"):
		_player.harvest_feedback()
	# Éclats visuels à chaque coup d'outil (copeaux projetés depuis le point d'impact).
	var is_rock := String(h.get("kind", "")) == "rock"
	var chip_h := 0.5 if is_rock else 1.0
	var chip_col := _chip_color(int(h.variant)) if is_rock else Color(0.52, 0.36, 0.20)
	_spawn_chips((h.pos as Vector3) + Vector3.UP * chip_h, chip_col)
	if n >= _need_for(h):
		_hits.erase(id)
		_fell(h)

func _fell(h: Dictionary) -> void:
	var id := _id_of(h)
	# Arbre PLANTÉ par le joueur : abattu via BuildManager (retiré définitivement, pas de repousse).
	if h.get("planted", false):
		_fell_planted(h)
		return
	# Arbre GÉANT (POI) : gros rendement, masqué + repousse (réutilise le timer de repousse d'arbre).
	if h.get("poi", false):
		_fell_giant(h, id)
		return
	if String(h.get("kind", "")) == "tree":
		var species := int(h.variant) / VegetationLibrary.TREE_VARIANTS_PER
		var yld := HL.species_yield(species)
		var wood := String(yld.get("wood", ""))
		var qty := randi_range(HL.WOOD_PER_TREE_MIN, HL.WOOD_PER_TREE_MAX)
		Inventory.add_resource(wood, qty)
		Inventory.add_resource(String(yld.get("seed", "")), 1)   # bonus : une graine à replanter
		_msg = "+ %d %s" % [qty, HL.item_name(wood)]
		_depleted[id] = {"rt": HL.REGROW_TREE, "coord": h.coord, "variant": int(h.variant), "index": int(h.index)}
	else:
		var ry := HL.rock_yield_for(int(h.variant))   # rendement SELON le type de rocher (cuivre/or/cristal/commun)
		var stone := String(ry.get("stone", "stone"))
		var qty := randi_range(HL.STONE_PER_ROCK_MIN, HL.STONE_PER_ROCK_MAX)
		Inventory.add_resource(stone, qty)
		var extra := ""
		if randf() < float(ry.get("ore_chance", HL.ORE_CHANCE)):
			var ores: Array = ry.get("ores", [])
			if not ores.is_empty():
				var ore := String(ores[randi() % ores.size()])
				var oqr: Vector2i = ry.get("ore_qty", Vector2i(1, 1))
				var oq := randi_range(oqr.x, oqr.y)
				Inventory.add_resource(ore, oq)
				extra = " + %d %s" % [oq, HL.item_name(ore)]
		_msg = "+ %d %s%s" % [qty, HL.item_name(stone), extra]
		_depleted[id] = {"rt": HL.REGROW_ROCK, "coord": h.coord, "variant": int(h.variant), "index": int(h.index)}
	_msg_t = 1.8
	_tool_target = {}
	_set_chunk_hidden(h.coord, int(h.variant), int(h.index), true)   # l'instance disparaît

# Abat un arbre PLANTÉ par le joueur : BuildManager retire le node et renvoie le rendement bois.
# Définitif (pas de repousse) — le joueur replante avec la graine récupérée.
func _fell_planted(h: Dictionary) -> void:
	if _build == null or not _build.has_method("chop_planted_tree"):
		return
	var y: Dictionary = _build.chop_planted_tree(h.get("node"))
	var wood := String(y.get("wood", ""))
	var qty := int(y.get("qty", 0))
	if wood != "" and qty > 0:
		Inventory.add_resource(wood, qty)
	var seed := String(y.get("seed", ""))
	if seed != "":
		Inventory.add_resource(seed, 1)   # bonus : une graine à replanter
	_msg = "+ %d %s" % [qty, HL.item_name(wood)]
	_msg_t = 1.8
	_tool_target = {}

# Abat l'arbre GÉANT (POI) : gros rendement de bois + graines ; masqué via le chunk + repousse (REGROW_TREE).
func _fell_giant(h: Dictionary, id: String) -> void:
	var qty := randi_range(GIANT_WOOD_MIN, GIANT_WOOD_MAX)
	Inventory.add_resource("wood_oak", qty)        # colosse feuillu => bois de pommier (essence du feuillu)
	Inventory.add_resource("seed_deciduous", 2)    # 2 graines (c'est un géant)
	_msg = "+ %d %s" % [qty, HL.item_name("wood_oak")]
	_msg_t = 2.2
	_tool_target = {}
	_depleted[id] = {"rt": HL.REGROW_TREE, "poi": true, "coord": h.coord}
	_set_poi_hidden(h.coord, true)                 # le POI disparaît (l'anneau ne le reconstruit pas)

# --- Épuisement / repousse ---
func _apply_depletion() -> void:
	# Ré-applique le masquage des instances épuisées présentes dans le scan (après rebuild de chunk).
	for h in _cands:
		if not _depleted.has(_id_of(h)):
			continue
		if h.get("poi", false):
			_set_poi_hidden(h.coord, true)           # arbre géant abattu : reste masqué
		elif not h.get("planted", false):
			# Les arbres PLANTÉS ne sont jamais dans _depleted (retrait définitif côté BuildManager) :
			# seuls les arbres/rochers SEMÉS (chunk) repoussent => masquage MultiMesh.
			_set_chunk_hidden(h.coord, int(h.variant), int(h.index), true)

func _tick_depletion(delta: float) -> void:
	var done: Array = []
	for id in _depleted:
		var e = _depleted[id]
		e.rt = float(e.rt) - delta
		if e.rt <= 0.0:
			done.append(id)
	for id in done:
		var e = _depleted[id]
		if e.get("poi", false):
			_set_poi_hidden(e.coord, false)   # repousse de l'arbre géant : l'anneau le reconstruit
		else:
			_set_chunk_hidden(e.coord, int(e.variant), int(e.index), false)   # repousse : l'instance réapparaît
		_depleted.erase(id)

func _set_chunk_hidden(coord, variant: int, index: int, hidden: bool) -> void:
	if _cm != null and _cm.has_method("set_veg_instance_hidden"):
		_cm.set_veg_instance_hidden(coord, variant, index, hidden)

# Masque/restaure l'arbre géant (POI) abattu d'un chunk (l'anneau ne le reconstruit pas tant que masqué).
func _set_poi_hidden(coord, hidden: bool) -> void:
	if _cm != null and _cm.has_method("set_poi_harvested"):
		_cm.set_poi_harvested(coord, hidden)

func _tick_regrow(delta: float) -> void:
	for id in _state:
		var st = _state[id]
		if int(st.count) < int(st.cap) and float(st.rt) > 0.0:
			st.rt = float(st.rt) - delta
			if st.rt <= 0.0:
				st.count = int(st.count) + 1
				st.rt = HL.REGROW_FRUIT if int(st.count) < int(st.cap) else 0.0

# --- Étiquette : toast prioritaire, sinon invite outil, sinon « Cueillir » ---
func _update_label() -> void:
	var cam = _player.get_active_camera() if _player.has_method("get_active_camera") else null
	if _msg_t > 0.0 and cam != null:
		_label.text = _msg
		_label.global_position = cam.global_position - cam.global_transform.basis.z * 1.2
		_label.visible = true
	elif _tool_txt != "":
		_label.text = _tool_txt
		_label.global_position = _tool_pos
		_label.visible = true
	elif _target >= 0 and _target < _fruits.size():
		_label.text = "Cueillir"
		_label.global_position = (_fruits[_target].pos as Vector3) + Vector3.UP * 0.28
		_label.visible = true
	elif _label.visible:
		_label.visible = false

# --- Pool de fruits ---
func _take_pool(col: Color) -> MeshInstance3D:
	var mi: MeshInstance3D
	if _pool.is_empty():
		mi = MeshInstance3D.new()
		mi.mesh = _sphere
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.roughness = 0.5
		mi.material_override = m
		add_child(mi)
	else:
		mi = _pool.pop_back()
	var mat := mi.material_override as StandardMaterial3D
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col * 0.25
	return mi

func _recycle(mi: MeshInstance3D) -> void:
	if mi == null:
		return
	mi.visible = false
	_pool.append(mi)

# Id stable d'un récoltable (invariant au rebase et au rechargement de chunk).
func _id_of(h: Dictionary) -> String:
	if h.get("planted", false):
		var n = h.get("node")
		return "planted:%d" % (n.get_instance_id() if is_instance_valid(n) else 0)
	if h.get("poi", false):
		var cp: Vector2i = h.get("coord", Vector2i.ZERO)
		return "poi:%d,%d" % [cp.x, cp.y]
	var c: Vector2i = h.get("coord", Vector2i.ZERO)
	return "%d,%d,%d,%d" % [c.x, c.y, int(h.variant), int(h.index)]

func _slot_angle(id: String, slot: int, cap: int) -> float:
	return float(hash(id)) * 0.000123 + float(slot) * TAU / float(maxi(cap, 1))

# Couleur des éclats de roche selon la variante (copeaux visuels au minage).
func _chip_color(variant: int) -> Color:
	match variant:
		VegetationLibrary.V_ROCK_COPPER: return Color(0.65, 0.42, 0.25)
		VegetationLibrary.V_ROCK_GOLD:   return Color(0.90, 0.75, 0.25)
		VegetationLibrary.V_ROCK_CRYSTAL: return Color(0.55, 0.80, 0.95)
	return Color(0.50, 0.48, 0.45)

# Éclats visuels : burst one-shot de petits fragments projetés depuis le point d'impact (roche ou bois).
func _spawn_chips(pos: Vector3, color: Color) -> void:
	var gp := GPUParticles3D.new()
	gp.emitting = true
	gp.one_shot = true
	gp.amount = 6
	gp.lifetime = 0.55
	gp.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 55.0
	pm.initial_velocity_min = 1.8
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3(0.0, -9.8, 0.0)
	pm.scale_min = 0.04
	pm.scale_max = 0.10
	pm.angular_velocity_min = -180.0
	pm.angular_velocity_max = 180.0
	pm.damping_min = 1.5
	pm.damping_max = 3.0
	pm.color = color
	gp.process_material = pm
	var chip := BoxMesh.new()
	chip.size = Vector3(0.06, 0.04, 0.05)
	gp.draw_pass_1 = chip
	add_child(gp)
	gp.global_position = pos
	gp.finished.connect(gp.queue_free)
