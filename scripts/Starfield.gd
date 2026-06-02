class_name Starfield
extends MultiMeshInstance3D
## Ciel de nuit. Trois couches sur une dome lointaine centrée sur le joueur, tournée par la rotation
## planète (TimeOfDay) dans le MÊME repère B que le soleil au sol => ciel cohérent jour/nuit :
##   1) Étoiles "réelles" = autres systèmes de la galaxie projetés depuis le système courant (brillantes).
##   2) Champ d'étoiles de fond dense + bande de Voie lactée (étoiles concentrées + lueur diffuse).
##   3) Galaxies lointaines (spirales/elliptiques procédurales, billboards additifs).
## Les couches 2-3 = univers lointain FIXE (seed constant) : même fond partout, déterministe.

const STAR_SHADER := preload("res://shaders/starfield.gdshader")
const GALAXY_SHADER := preload("res://shaders/galaxy.gdshader")
const DOME_RADIUS := 3000.0   # < far (4000) ; au-delà du terrain (2048) => occlusion horizon OK
const STAR_BASE := 7.0        # taille de base d'une étoile-système (m) sur la dome
const MAX_STARS := 400        # garde-fou systèmes (≈ nb de systèmes)
const BG_STARS := 2400        # étoiles de fond procédurales (champ dense)
const MW_STARS := 900         # étoiles concentrées dans la bande Voie lactée
const MW_GLOW := 70           # lueurs diffuses (grosses, très faibles) de la bande
const GALAXIES := 10          # galaxies lointaines
const BG_SEED := 1779033703   # univers lointain fixe (déterministe)
const MW_AXIS := Vector3(0.35, 0.55, 0.76)   # normale du plan de la Voie lactée (bande inclinée)
const METEOR_SHADER := preload("res://shaders/meteor.gdshader")
const METEOR_COUNT := 4        # étoiles filantes simultanées max
const METEOR_LEN := 420.0      # longueur de la traînée (m sur la dome)
const METEOR_WID := 7.0        # largeur de la traînée
const METEOR_DUR := 1.3        # durée d'une traînée (s)
const METEOR_GAP := Vector2(2.5, 10.0)   # délai aléatoire min/max entre deux apparitions (s)

var _player: Node3D
var _landing_dir := Vector3.UP
var _mat: ShaderMaterial
var _gal_mat: ShaderMaterial
var _galaxies: MultiMeshInstance3D
# Étoiles filantes : pool de traînées (apparitions périodiques aléatoires, visibles la nuit).
var _meteors: Array[MeshInstance3D] = []
var _met_mat: Array[ShaderMaterial] = []
var _met_t: Array[float] = []        # progression 0..1 (>1 = inactive, en attente)
var _met_next: Array[float] = []     # instant de prochaine apparition (s)
var _met_a: Array[Vector3] = []      # direction de départ
var _met_b: Array[Vector3] = []      # direction d'arrivée
var _met_rng := RandomNumberGenerator.new()

# Bâtit les trois couches du ciel. La projection en repère local (rotation planète) se fait chaque frame.
func setup(systems: Array, current_pos: Vector3, landing_dir: Vector3, player: Node3D) -> void:
	_player = player
	_landing_dir = landing_dir.normalized()
	_mat = ShaderMaterial.new()
	_mat.shader = STAR_SHADER
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var rng := RandomNumberGenerator.new()
	rng.seed = BG_SEED
	var dirs: Array[Vector3] = []
	var cols: Array[Color] = []
	var sizes: Array[float] = []

	# 1) Systèmes de la galaxie (les plus brillants) — directions inertielles depuis le système courant.
	var max_d := 0.0001
	var sd: Array[Vector3] = []
	var sc: Array[Color] = []
	var sdist: Array[float] = []
	for s in systems:
		var off: Vector3 = s.position - current_pos
		var d := off.length()
		if d < 0.001:
			continue
		sd.append(off / d)
		sc.append(GalaxyGenerator.star_color(s.star_type))
		sdist.append(d)
		max_d = maxf(max_d, d)
		if sd.size() >= MAX_STARS:
			break
	for i in sd.size():
		var near := 1.0 - clampf(sdist[i] / max_d, 0.0, 1.0)
		dirs.append(sd[i])
		cols.append(sc[i])
		sizes.append(STAR_BASE * (0.7 + 0.7 * near))

	# 2a) Champ d'étoiles de fond (réparti uniformément sur la dome).
	for i in BG_STARS:
		dirs.append(_rand_dir(rng))
		cols.append(_star_color(rng))
		sizes.append(rng.randf_range(1.5, 4.0))
	# 2b) Voie lactée : étoiles concentrées vers le plan MW_AXIS (plus petites/nombreuses).
	var axis := MW_AXIS.normalized()
	for i in MW_STARS:
		dirs.append(_band_dir(rng, axis, 0.14))
		cols.append(_star_color(rng) * 0.85)
		sizes.append(rng.randf_range(1.0, 2.6))
	# 2c) Lueur diffuse de la bande : grosses billboards très faibles (additif => luminosité douce).
	for i in MW_GLOW:
		dirs.append(_band_dir(rng, axis, 0.10))
		cols.append(_star_color(rng) * 0.10)
		sizes.append(rng.randf_range(45.0, 110.0))

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = dirs.size()
	for i in dirs.size():
		var t := Transform3D(Basis().scaled(Vector3(sizes[i], sizes[i], sizes[i])), dirs[i] * DOME_RADIUS)
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, cols[i])
	multimesh = mm
	visible = true

	# 3) Galaxies lointaines (couche séparée : shader procédural spirale/elliptique).
	_build_galaxies(rng)
	# 4) Étoiles filantes (traînées additives périodiques).
	_build_meteors()

func _build_galaxies(rng: RandomNumberGenerator) -> void:
	_galaxies = MultiMeshInstance3D.new()
	_gal_mat = ShaderMaterial.new()
	_gal_mat.shader = GALAXY_SHADER
	_galaxies.material_override = _gal_mat
	_galaxies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var gmm := MultiMesh.new()
	gmm.transform_format = MultiMesh.TRANSFORM_3D
	gmm.use_colors = true
	gmm.use_custom_data = true
	gmm.mesh = quad
	gmm.instance_count = GALAXIES
	for i in GALAXIES:
		var dir := _rand_dir(rng)
		var sz := rng.randf_range(120.0, 320.0)
		var t := Transform3D(Basis().scaled(Vector3(sz, sz, sz)), dir * (DOME_RADIUS * 0.98))
		gmm.set_instance_transform(i, t)
		gmm.set_instance_color(i, _galaxy_tint(rng))
		var is_spiral := 1.0 if rng.randf() < 0.6 else 0.0
		gmm.set_instance_custom_data(i, Color(rng.randf_range(0.0, TAU), rng.randf(), is_spiral, rng.randf()))
	_galaxies.multimesh = gmm
	add_child(_galaxies)

# --- Helpers procéduraux (déterministes via rng) ---

# Direction uniforme sur la sphère.
func _rand_dir(rng: RandomNumberGenerator) -> Vector3:
	var z := rng.randf_range(-1.0, 1.0)
	var a := rng.randf_range(0.0, TAU)
	var r := sqrt(maxf(0.0, 1.0 - z * z))
	return Vector3(r * cos(a), z, r * sin(a))

# Direction concentrée vers le plan perpendiculaire à 'axis' (bande). spread petit => bande fine.
func _band_dir(rng: RandomNumberGenerator, axis: Vector3, spread: float) -> Vector3:
	var d := _rand_dir(rng)
	var along := d.dot(axis)
	d = (d - axis * along * (1.0 - spread)).normalized()
	return d

# Couleur d'étoile : majorité blanc-bleu, quelques jaunes/orangées ; luminosité (magnitude additive) variée.
func _star_color(rng: RandomNumberGenerator) -> Color:
	var t := rng.randf()
	var base := Color(0.90, 0.93, 1.0)
	if t > 0.85:
		base = Color(1.0, 0.82, 0.68)
	elif t > 0.6:
		base = Color(1.0, 0.96, 0.86)
	var b := rng.randf_range(0.22, 0.95)
	if rng.randf() < 0.05:
		b = rng.randf_range(1.0, 1.6)   # quelques étoiles vives
	return base * b

# Teinte de galaxie (faible : objets lointains diffus) — palette variée bleutée/dorée/rosée.
func _galaxy_tint(rng: RandomNumberGenerator) -> Color:
	var t := rng.randf()
	var base := Color(0.66, 0.74, 0.95)   # bleutée (majorité)
	if t > 0.8:
		base = Color(0.96, 0.74, 0.78)    # rosée (rare)
	elif t > 0.55:
		base = Color(0.95, 0.84, 0.66)    # dorée
	elif t > 0.4:
		base = Color(0.90, 0.90, 0.86)    # blanchâtre
	return base * rng.randf_range(0.42, 0.72)

func _now() -> float:
	return float(Time.get_ticks_msec()) * 0.001

# Crée le pool de traînées (quads additifs orientés par frame le long du mouvement).
func _build_meteors() -> void:
	_met_rng.randomize()
	for i in METEOR_COUNT:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1.0, 1.0)
		mi.mesh = q
		var m := ShaderMaterial.new()
		m.shader = METEOR_SHADER
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_meteors.append(mi)
		_met_mat.append(m)
		_met_t.append(2.0)   # inactive au départ
		_met_next.append(_now() + _met_rng.randf_range(METEOR_GAP.x, METEOR_GAP.y))
		_met_a.append(Vector3.UP)
		_met_b.append(Vector3.UP)

# Anime les traînées : avance les actives, en (re)lance de nouvelles à intervalles aléatoires (nuit).
func _update_meteors(delta: float, night: float) -> void:
	var now := _now()
	for i in _meteors.size():
		if _met_t[i] <= 1.0:
			_met_t[i] += delta / METEOR_DUR
			if _met_t[i] > 1.0:
				_meteors[i].visible = false
				_met_next[i] = now + _met_rng.randf_range(METEOR_GAP.x, METEOR_GAP.y)
				continue
			var t: float = _met_t[i]
			var dir := _met_a[i].lerp(_met_b[i], t).normalized()
			var nrm := -dir                                   # face le centre (joueur)
			var motion: Vector3 = _met_b[i] - _met_a[i]
			var fwd := (motion - nrm * motion.dot(nrm)).normalized()   # tangent (sens du mouvement)
			if fwd.length() < 0.01:
				fwd = nrm.cross(Vector3.UP).normalized()
			var side := nrm.cross(fwd).normalized()
			var basis := Basis(fwd * METEOR_LEN, side * METEOR_WID, nrm)
			_meteors[i].transform = Transform3D(basis, dir * (DOME_RADIUS * 0.995))
			var env := smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.7, 1.0, t))
			_met_mat[i].set_shader_parameter("alpha", env * night)
			_meteors[i].visible = true
		elif night > 0.25 and now >= _met_next[i]:
			var a := _rand_dir(_met_rng)
			a.y = absf(a.y) * 0.8 + 0.15   # plutôt au-dessus de l'horizon
			a = a.normalized()
			var tang := a.cross(_rand_dir(_met_rng)).normalized()
			_met_a[i] = a
			_met_b[i] = (a + tang * _met_rng.randf_range(0.35, 0.75)).normalized()
			_met_t[i] = 0.0

func _process(_dt: float) -> void:
	if GameState.current_scale != GameState.Scale.SURFACE:
		return   # node de surface : ne pas animer (météores/RNG/matrices) hors-surface
	if multimesh == null or _player == null or _mat == null:
		return
	# Même repère B que le soleil : inertiel -> ciel local tourné par la rotation planète.
	var p := TimeOfDay.spin_basis() * _landing_dir
	var b := FloatingOrigin.tangent_basis(p).inverse()
	global_transform = Transform3D(b, _player.global_position)   # dome centrée sur le joueur
	# Visibilité fondue avec l'obscurité du ciel (même seuil que SkyManager).
	var alt := TimeOfDay.get_sun_altitude(_landing_dir)
	var night := 1.0 - smoothstep(-0.05, 0.18, alt)
	_mat.set_shader_parameter("night", night)
	if _gal_mat:
		_gal_mat.set_shader_parameter("night", night)
	visible = night > 0.01
	_update_meteors(_dt, night)
