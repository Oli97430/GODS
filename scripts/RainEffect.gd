class_name RainEffect
extends GPUParticles3D
## Pluie en GPU particles 3D, en WORLDSPACE (les gouttes tombent droit même quand l'émetteur
## suit le joueur). Densité = WeatherSystem.precipitation (via amount_ratio, plafonné), incliné
## par le vent. Cohérent stéréo (positions monde réelles + billboard particules). Suit l'origine
## flottante car l'émetteur se recentre sur le joueur chaque frame.

const MAX_PARTICLES := 2000     # plafond (budget PCVR)
const BOX_RADIUS := 14.0        # demi-étendue horizontale autour du joueur
const BOX_HEIGHT := 16.0        # hauteur d'émission au-dessus du joueur
const FALL_SPEED := 18.0        # vitesse de chute (m/s)
const WIND_DIR := Vector3(1.0, 0.0, 0.35)   # direction horizontale du vent
const WIND_PUSH := 14.0         # poussée latérale à wind=1

var _player: Node3D
var _proc: ParticleProcessMaterial

func setup(player: Node3D) -> void:
	_player = player
	amount = MAX_PARTICLES
	lifetime = (BOX_HEIGHT + 4.0) / FALL_SPEED
	local_coords = false   # worldspace : chute droite indépendante du mouvement de l'émetteur
	randomness = 1.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# AABB de visibilité (sinon culling agressif des particules worldspace).
	visibility_aabb = AABB(Vector3(-BOX_RADIUS, -BOX_HEIGHT, -BOX_RADIUS), Vector3(BOX_RADIUS * 2.0, BOX_HEIGHT * 2.0, BOX_RADIUS * 2.0))

	_proc = ParticleProcessMaterial.new()
	_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_proc.emission_box_extents = Vector3(BOX_RADIUS, 1.0, BOX_RADIUS)
	_proc.direction = Vector3(0.0, -1.0, 0.0)
	_proc.spread = 0.0
	_proc.initial_velocity_min = FALL_SPEED * 0.9
	_proc.initial_velocity_max = FALL_SPEED * 1.1
	_proc.gravity = Vector3(0.0, -2.0, 0.0)
	process_material = _proc

	# Strie de pluie : quad fin et allongé, billboard particules, pâle et semi-transparent.
	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.55)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.albedo_color = Color(0.7, 0.8, 0.9, 0.35)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	draw_pass_1 = quad
	emitting = false

func _process(_dt: float) -> void:
	# Pas de pluie quand la surface n'est pas affichée (évite d'émettre hors-vue).
	if _player == null or not is_visible_in_tree():
		emitting = false
		return
	# Émetteur centré au-dessus du joueur (worldspace).
	global_position = _player.global_position + Vector3(0.0, BOX_HEIGHT, 0.0)
	var precip := 0.0
	var wind := 0.0
	if WeatherSystem.is_configured():
		precip = WeatherSystem.get_precipitation()
		wind = WeatherSystem.get_wind()
	apply_state(precip, wind)

# Applique densité (amount_ratio) + inclinaison (gravity latérale) à partir des paramètres météo.
func apply_state(precip: float, wind: float) -> void:
	emitting = precip > 0.02
	amount_ratio = precip   # densité proportionnelle à la pluie (0 => rien)
	if _proc:
		_proc.gravity = WIND_DIR * (wind * WIND_PUSH) + Vector3(0.0, -2.0, 0.0)
