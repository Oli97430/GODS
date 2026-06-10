class_name SkyManager
extends Node
## Pilote, à la SURFACE, tout ce qui dépend de la position du soleil, depuis l'UNIQUE
## source de temps (TimeOfDay) : orientation + énergie/teinte de la lumière directionnelle,
## ciel dynamique (sky_dynamic.gdshader), brouillard et ambiant. Aucun timer local : tout
## vient de get_sun_direction_local(landing_dir) — le point d'atterrissage est une lat/long fixe.

const SKY_SHADER := "res://shaders/sky_dynamic.gdshader"

const DAY_ENERGY := 1.25                        # énergie soleil en plein jour
const SUN_DAY_COLOR := Color(1.0, 0.97, 0.90)   # teinte neutre/chaude au zénith
const SUN_DUSK_COLOR := Color(1.0, 0.58, 0.34)  # teinte chaude rasante (lever/coucher)
const NIGHT_FOG := Color(0.03, 0.04, 0.09)      # brouillard nocturne (bleu profond)
const DAY_AMBIENT := 1.0                         # intensité ambiante de jour
const NIGHT_AMBIENT := 0.10                      # plancher ambiant de nuit (pas tout noir)
const PRECIP_FOG_MULT := 3.0                     # densité de fog ×(1+ceci) sous pluie maximale
const OVERCAST_FOG := Color(0.55, 0.57, 0.62)    # teinte de fog gris quand couvert
const FLASH_AMBIENT := 2.6                       # pic d'ambiant pendant un éclair (illumine jour ET nuit)
const FLASH_SUN := 2.2                           # appoint directionnel d'éclair (de jour seulement)
# Univers sous-marin (CP1a) : ambiance appliquée quand la tête passe sous le niveau de mer (Y0).
const UNDERWATER_FOG := Color(0.02, 0.16, 0.22)  # brume sous-marine bleu-vert profond
const UNDERWATER_DENSITY := 0.045                # densité fog immergé (visibilité ~20-40 m, eau trouble)
const UNDERWATER_AMBIENT_MULT := 0.5             # ambiant ×0.5 sous l'eau (pénombre filtrée d'en haut)
# CP3 — profondeur : plus on descend, plus c'est sombre/dense/bleu (les rais de lumière s'estompent en bas).
const UNDERWATER_FOG_DEEP := Color(0.01, 0.06, 0.11)  # bleu sombre des profondeurs
const UNDERWATER_DENSITY_DEEP := 0.085                # eau plus trouble en profondeur (visibilité réduite)
const UNDERWATER_AMBIENT_DEEP := 0.22                 # pénombre marquée au fond

var _sun: DirectionalLight3D
var _landing_dir := Vector3.UP
var _env: Environment
var _atmo := Color(0.4, 0.6, 0.9)
var _sky_mat: ShaderMaterial
var _base_fog_density := 0.0   # densité de fog de base (phase 7) ; la météo la module
var _lightning: LightningEffect   # planificateur d'éclairs (flash appliqué ici)
var _dome = null                  # SkyDome (addon Sky3D) si présent : on lui pousse soleil + couverture
# Aurores (variété/confort) : présence + teintes déterministes par seed planète (~40% des planètes).
var _aurora_strength := 0.0
var _aurora_color := Color(0.12, 1.0, 0.45)
var _aurora_color2 := Color(0.25, 0.55, 1.0)
var _submerged := 0.0   # 0 = au-dessus de l'eau, 1 = tête immergée (CP1a : piloté par SurfaceView)
var _depth01 := 0.0     # 0 = à la surface, 1 = profondeur pleine (CP3 : assombrit/épaissit le fog)

# Branche le manager sur la lumière, le point d'atterrissage, l'environnement et la teinte
# d'atmosphère de la planète, et installe le ciel dynamique.
func setup(sun: DirectionalLight3D, landing_dir: Vector3, env: Environment, atmo: Color, seed_local: int = 0) -> void:
	_sun = sun
	_landing_dir = landing_dir.normalized()
	_env = env
	_atmo = atmo
	_base_fog_density = env.fog_density if env else 0.0
	_submerged = 0.0   # nouvel environnement => repart au-dessus de l'eau
	_compute_aurora(seed_local)
	if _sun:
		# Ombres dynamiques du soleil (PCVR) : LE plus gros gain visuel au sol — arbres/rochers/constructions
		# ancrés par leur ombre, relief du terrain lisible. Réglage CONSERVATEUR (2 splits, 120 m, fondu) :
		# coût mesuré faible sur la cible RTX 3090. (Une passe Quest pourra le recouper en un seul point.)
		_sun.shadow_enabled = true
		_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		_sun.directional_shadow_max_distance = 120.0     # au-delà, la perspective aérienne prend le relais
		_sun.directional_shadow_split_1 = 0.18           # split proche serré => ombres nettes à portée de main
		_sun.directional_shadow_fade_start = 0.75        # fondu doux avant la limite (pas de bord d'ombre sec)
		_sun.directional_shadow_blend_splits = true      # transition invisible entre les 2 cascades
		_sun.shadow_blur = 1.2                           # pénombre douce (anti-aliasing d'ombre, pas de scintillement VR)
		_sun.light_angular_distance = 0.5                # taille angulaire du soleil => pénombre physique douce
	_build_sky()
	_update(0.0)

# Aurores déterministes par seed : ~40% des planètes en ont, avec force + palette variées (vert/teal/magenta).
func _compute_aurora(seed_local: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_local + 0xA0A0   # salt aurore (déterministe, indépendant des autres features)
	if rng.randf() >= 0.42:
		_aurora_strength = 0.0   # planète sans aurore
		return
	_aurora_strength = rng.randf_range(0.5, 1.1)
	var r := rng.randf()
	if r < 0.55:                                # vert classique surmonté de bleu
		_aurora_color = Color(0.12, 1.0, 0.45)
		_aurora_color2 = Color(0.25, 0.55, 1.0)
	elif r < 0.82:                              # teal surmonté de violet
		_aurora_color = Color(0.20, 0.95, 0.78)
		_aurora_color2 = Color(0.62, 0.28, 0.96)
	else:                                       # magenta (rare) surmonté de bleu
		_aurora_color = Color(0.85, 0.30, 0.85)
		_aurora_color2 = Color(0.30, 0.45, 1.0)

# Crée le ShaderMaterial de ciel et l'installe sur l'environnement (remplace le ciel statique).
func _build_sky() -> void:
	var shader := load(SKY_SHADER)
	if shader == null or _env == null:
		return
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = shader
	_sky_mat.set_shader_parameter("atmo_tint", Vector3(_atmo.r, _atmo.g, _atmo.b))
	_sky_mat.set_shader_parameter("sun_color", Vector3(SUN_DAY_COLOR.r, SUN_DAY_COLOR.g, SUN_DAY_COLOR.b))
	# Aurores (statiques par planète) : poussées une fois ici.
	_sky_mat.set_shader_parameter("aurora_strength", _aurora_strength)
	_sky_mat.set_shader_parameter("aurora_color", Vector3(_aurora_color.r, _aurora_color.g, _aurora_color.b))
	_sky_mat.set_shader_parameter("aurora_color2", Vector3(_aurora_color2.r, _aurora_color2.g, _aurora_color2.b))
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	_env.sky = sky
	_env.background_mode = Environment.BG_SKY
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY

# Branche le planificateur d'éclairs (flash appliqué au ciel + ambiant chaque frame).
func set_lightning(l: LightningEffect) -> void:
	_lightning = l

# Branche le dôme Sky3D (addon) : SkyManager lui pousse la position solaire (depuis TimeOfDay => cohérent
# orbite↔sol) + la couverture nuageuse (depuis WeatherSystem) à chaque frame.
func set_dome(d) -> void:
	_dome = d

# Rebase à origine flottante : le repère monde est ré-ancré sur la position-planète COURANTE du joueur.
# SurfaceView pousse ici la nouvelle ancre pour que le soleil + le ciel restent alignés avec le sol
# (sinon le soleil dérive jusqu'à ~11° par rebase, seuil 600 m).
func set_landing_dir(dir: Vector3) -> void:
	_landing_dir = dir.normalized()

# Univers sous-marin (CP1a) : facteur 0..1 d'immersion de la tête (caméra sous le niveau de mer Y0),
# poussé chaque frame par SurfaceView. _update fond le fog/ambient vers l'ambiance sous-marine quand >0.
func set_submerged(f: float, depth01: float = 0.0) -> void:
	_submerged = clampf(f, 0.0, 1.0)
	_depth01 = clampf(depth01, 0.0, 1.0)

func _process(_dt: float) -> void:
	if GameState.current_scale != GameState.Scale.SURFACE:
		return   # ⚠️ hors-surface, _update écrirait _sun.basis/fog/ambient chaque frame ET entrerait en
		         # CONFLIT avec PlanetView qui oriente _sun en orbite (écriture concurrente, ordre-dépendante)
	_update(0.0)

# Recalcule l'état d'éclairage (soleil + ciel + fog + ambiant) pour l'instant courant.
func _update(_dt: float) -> void:
	if _sun == null:
		return
	var sun_local := TimeOfDay.get_sun_direction_local(_landing_dir)  # vers le soleil, +Y = up
	_orient_sun(sun_local)
	var alt := sun_local.y   # sin(altitude) : >0 jour, <0 nuit
	var day := smoothstep(-0.08, 0.18, alt)
	var twilight := smoothstep(0.0, 0.18, alt + 0.18) * (1.0 - smoothstep(0.0, 0.36, alt))

	# Météo (phase 13) : couverture nuageuse + précipitation modulent lumière/ciel/fog/ambiant.
	var coverage := 0.0
	var precip := 0.0
	if WeatherSystem.is_configured():
		coverage = WeatherSystem.get_cloud_coverage()
		precip = WeatherSystem.get_precipitation()

	# Éclair (phase 13) : flash bref déterministe, illumine ciel + ambiant (marche jour ET nuit).
	var flash := 0.0
	if _lightning:
		flash = _lightning.current_flash()

	# Lumière directionnelle : atténuée par nuages + pluie ; appoint d'éclair de jour seulement
	# (le soleil est sous l'horizon la nuit — l'éclair nocturne passe par l'ambiant + le ciel).
	_sun.light_energy = DAY_ENERGY * day * (1.0 - coverage * 0.6) * (1.0 - precip * 0.4) + flash * FLASH_SUN * day
	_sun.light_color = SUN_DAY_COLOR.lerp(SUN_DUSK_COLOR, 1.0 - smoothstep(0.04, 0.42, alt))
	_sun.visible = day > 0.001 and _sun.light_energy > 0.001

	# Ciel : direction du soleil + couverture nuageuse + flash d'éclair (blanchiment bref).
	if _sky_mat:
		_sky_mat.set_shader_parameter("sun_dir", sun_local)
		_sky_mat.set_shader_parameter("cloud_coverage", coverage)
		_sky_mat.set_shader_parameter("lightning", flash)
		_sky_mat.set_shader_parameter("clouds_on", 1.0 if GameState.atmosphere_enabled else 0.0)
	# Globaux d'occlusion : étoiles/galaxies/lunes (géométrie du dôme) s'estompent là où un nuage passe devant
	# (le ciel — donc les nuages — est dessiné DERRIÈRE la géométrie ; on recalcule la transmittance côté dôme).
	RenderingServer.global_shader_parameter_set("cloud_coverage_g", coverage)
	RenderingServer.global_shader_parameter_set("clouds_on_g", 1.0 if GameState.atmosphere_enabled else 0.0)

	# Sky3D (addon) : pousse le soleil (depuis sun_local => cohérent avec l'orbite) + la couverture météo.
	if _dome != null:
		_dome.sun_altitude = acos(clampf(sun_local.y, -1.0, 1.0))   # angle polaire depuis le zénith
		_dome.sun_azimuth = atan2(sun_local.x, sun_local.z)
		_dome.cumulus_coverage = clampf(0.34 + coverage * 0.5, 0.0, 0.92)   # qq nuages toujours, + si couvert

	# Brouillard + ambiant : jour=atmo, crépuscule=chaud, nuit=sombre, couvert=gris, pluie=dense,
	# + pic d'ambiant pendant l'éclair (illumine le sol omnidirectionnellement).
	if _env:
		var fog_col := _atmo.lerp(SUN_DUSK_COLOR, twilight * 0.7)
		fog_col = fog_col.lerp(NIGHT_FOG, (1.0 - day) * 0.85)
		fog_col = fog_col.lerp(OVERCAST_FOG, coverage * 0.4)
		_env.fog_light_color = fog_col
		_env.ambient_light_energy = lerpf(NIGHT_AMBIENT, DAY_AMBIENT, day) * (1.0 - coverage * 0.3) + flash * FLASH_AMBIENT
		_env.fog_density = _base_fog_density * (1.0 + precip * PRECIP_FOG_MULT)
		# Univers sous-marin (CP1a) : tête sous le niveau de mer => brume bleu-vert dense + pénombre.
		# _update recalcule fog/ambient depuis la base CHAQUE frame => _submerged=0 ⇒ no-op exact (zéro
		# régression au-dessus de l'eau, zéro fuite d'état au retour en surface).
		if _submerged > 0.001:
			# Teinte / densité / pénombre dépendent de la PROFONDEUR (CP3) : surface claire -> fond sombre.
			var uw_fog := UNDERWATER_FOG.lerp(UNDERWATER_FOG_DEEP, _depth01)
			var uw_density := lerpf(UNDERWATER_DENSITY, UNDERWATER_DENSITY_DEEP, _depth01)
			var uw_amb := lerpf(UNDERWATER_AMBIENT_MULT, UNDERWATER_AMBIENT_DEEP, _depth01)
			_env.fog_light_color = _env.fog_light_color.lerp(uw_fog, _submerged)
			_env.fog_density = lerpf(_env.fog_density, uw_density, _submerged)
			_env.ambient_light_energy *= 1.0 - (1.0 - uw_amb) * _submerged
			# Color grade sous-marin (CP3 polish) : l'eau absorbe les couleurs => désaturation + léger
			# assombrissement, accentués en profondeur. Désactivé hors de l'eau (rendu d'origine intact).
			_env.adjustment_enabled = true
			_env.adjustment_saturation = lerpf(1.0, 0.68, _submerged * (0.6 + 0.4 * _depth01))
			_env.adjustment_brightness = lerpf(1.0, 0.88, _submerged)
		elif _env.adjustment_enabled:
			_env.adjustment_enabled = false   # hors de l'eau : pas de color grade (rendu d'origine intact)

# Oriente la lumière pour que basis.z = direction VERS le soleil (elle éclaire en -z).
func _orient_sun(toward_sun: Vector3) -> void:
	var z := toward_sun.normalized()
	var x := Vector3.UP.cross(z)
	if x.length() < 0.01:
		x = Vector3.RIGHT.cross(z)
	x = x.normalized()
	_sun.basis = Basis(x, z.cross(x).normalized(), z)
