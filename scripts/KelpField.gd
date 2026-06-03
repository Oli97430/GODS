extends MultiMeshInstance3D
## Champ de kelp (algues) : lames enracinées sur le FOND MARIN autour du joueur, ondulant via shader.
## Visible seulement sous l'eau. Positions en ESPACE MONDE (conformes au sol, contrairement aux lucioles
## player-relatives) : re-semé quand le joueur s'éloigne (>RESEED_DIST) OU au rebase FloatingOrigin (détecté
## par un saut de position). Échantillonne la VRAIE hauteur du fond via ChunkManager.seafloor_height_at
## (non bornée au niveau de mer). AUTO-CONTENU. Vie ambiante, non déterministe.

const SEA_Y := 0.0          # Y monde de la surface de mer (DEFAULT_SEA_LEVEL=0)
const N := 100
const RADIUS := 18.0        # m : rayon du champ autour du joueur
const RESEED_DIST := 8.0    # m : re-sème quand le joueur s'éloigne du centre du patch
const MIN_DEPTH := 1.2      # m : kelp uniquement là où le fond est au moins si profond SOUS la mer
const REBASE_JUMP := 60.0   # m : saut de position en une frame => rebase => re-sème (coords monde invalidées)

var _rng := RandomNumberGenerator.new()
var _center := Vector3.ZERO
var _last_player := Vector3.ZERO
var _seeded := false

func _ready() -> void:
	top_level = true   # instances en coords MONDE (on écrit global_transform = IDENTITY dans update)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rng.randomize()
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = _kelp_mesh()
	multimesh.instance_count = N
	for i in N:
		_hide_instance(i)
		multimesh.set_instance_custom_data(i, Color(_rng.randf(), 0.0, 0.0, 0.0))   # .x = phase d'ondulation
	var smat := ShaderMaterial.new()
	smat.shader = preload("res://shaders/kelp.gdshader")
	material_override = smat
	visible = false

# center = position joueur ; submerged 0..1 ; chunks = ChunkManager (hauteur du fond).
func update(player_pos: Vector3, submerged: float, chunks) -> void:
	if submerged < 0.05 or chunks == null:
		if visible:
			visible = false
		return
	visible = true
	global_transform = Transform3D.IDENTITY   # les instances portent des coords MONDE
	var jumped := _seeded and player_pos.distance_to(_last_player) > REBASE_JUMP
	if not _seeded or jumped or player_pos.distance_to(_center) > RESEED_DIST:
		_reseed(player_pos, chunks)
	_last_player = player_pos

# Re-sème les lames sur le fond marin dans un disque autour du joueur (uniquement là où c'est assez profond).
func _reseed(player_pos: Vector3, chunks) -> void:
	_center = player_pos
	for i in N:
		var ang := _rng.randf() * TAU
		var rad := sqrt(_rng.randf()) * RADIUS   # disque uniforme
		var x := player_pos.x + cos(ang) * rad
		var z := player_pos.z + sin(ang) * rad
		var gh: float = chunks.seafloor_height_at(Vector3(x, 0.0, z))
		if gh < SEA_Y - MIN_DEPTH:
			var sc := _rng.randf_range(0.7, 1.6)
			var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(sc, sc, sc))
			multimesh.set_instance_transform(i, Transform3D(b, Vector3(x, gh, z)))
		else:
			_hide_instance(i)   # trop peu profond / hors de l'eau => pas de kelp ici
	_seeded = true

func _hide_instance(i: int) -> void:
	multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0.0, SEA_Y + 1000.0, 0.0)))

func _kelp_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 4
	var height := 2.4
	var halfw := 0.10
	# 2 lames croisées (yaw 0 et 70°) pour du volume ; chaque lame = ruban vertical à `segs` segments
	# (la courbure d'ondulation est lisse). UV.y = hauteur normalisée (0 base ancrée -> 1 sommet).
	for blade in 2:
		var yaw := 0.0 if blade == 0 else deg_to_rad(70.0)
		var dx := cos(yaw) * halfw
		var dz := sin(yaw) * halfw
		for s in segs:
			var y0 := height * float(s) / float(segs)
			var y1 := height * float(s + 1) / float(segs)
			var v0 := float(s) / float(segs)
			var v1 := float(s + 1) / float(segs)
			var w0 := 1.0 - 0.6 * v0   # léger effilement vers le haut
			var w1 := 1.0 - 0.6 * v1
			var a := Vector3(-dx * w0, y0, -dz * w0)
			var b := Vector3(dx * w0, y0, dz * w0)
			var c := Vector3(dx * w1, y1, dz * w1)
			var d := Vector3(-dx * w1, y1, -dz * w1)
			st.set_uv(Vector2(0.0, v0)); st.add_vertex(a)
			st.set_uv(Vector2(1.0, v0)); st.add_vertex(b)
			st.set_uv(Vector2(1.0, v1)); st.add_vertex(c)
			st.set_uv(Vector2(0.0, v0)); st.add_vertex(a)
			st.set_uv(Vector2(1.0, v1)); st.add_vertex(c)
			st.set_uv(Vector2(0.0, v1)); st.add_vertex(d)
	st.generate_normals()
	return st.commit()
