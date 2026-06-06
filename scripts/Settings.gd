extends Node
## Réglages persistants (user://settings.cfg) + application : graphismes, résolution/fenêtre, audio,
## haptique bHaptics. Autoload. Les DÉFAUTS = comportement d'origine (mix audio approuvé inchangé, MSAA
## 4×, etc.) — une install neuve ne modifie rien. L'UI OptionsMenu écrit ces champs puis appelle apply_*.

const PATH := "user://settings.cfg"

# Choix exposés à l'UI.
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const MSAA_MODES := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X]
const MSAA_LABELS := ["Désactivé", "2×", "4×", "8×"]
const FPS_VALUES := [0, 30, 60, 72, 90, 120, 144]
const FPS_LABELS := ["Illimité", "30", "60", "72", "90", "120", "144"]
const WINDOW_LABELS := ["Fenêtré", "Plein écran", "Sans bordure"]

# Défauts = baseline. msaa_index 2 = 4× (réglage ImmersionFX d'origine) ; volumes 1.0 = mix approuvé.
const DEF := {
	"render_scale": 1.0, "msaa_index": 2, "vsync": true, "window_mode": 0,
	"resolution_index": 2, "fps_index": 0,
	"fx_glow": true, "fx_ssao": true, "fx_ssil": true,
	"vol_master": 1.0, "vol_ambient": 1.0, "vol_sfx": 1.0,
	"haptics_enabled": true, "haptics_intensity": 1.0,
	"vignette_on": true, "vignette_strength": 0.6, "turn_mode": 0, "snap_angle": 30.0,
	"coop_ip": "127.0.0.1",
	"smartplug_enabled": true, "smartplug_ip": "", "smartplug_name": "",
	"start_last_seed": -1, "start_last_system": -1,
}

var render_scale: float = DEF.render_scale
var msaa_index: int = DEF.msaa_index
var vsync: bool = DEF.vsync
var window_mode: int = DEF.window_mode
var resolution_index: int = DEF.resolution_index
var fps_index: int = DEF.fps_index
var fx_glow: bool = DEF.fx_glow
var fx_ssao: bool = DEF.fx_ssao
var fx_ssil: bool = DEF.fx_ssil
var vol_master: float = DEF.vol_master
var vol_ambient: float = DEF.vol_ambient
var vol_sfx: float = DEF.vol_sfx
var haptics_enabled: bool = DEF.haptics_enabled
var haptics_intensity: float = DEF.haptics_intensity
var vignette_on: bool = DEF.vignette_on
var vignette_strength: float = DEF.vignette_strength
var turn_mode: int = DEF.turn_mode          # 0 = snap (par cran, confort), 1 = continue (smooth)
var snap_angle: float = DEF.snap_angle      # degrés par cran de snap-turn
var coop_ip: String = DEF.coop_ip           # coop : dernière IP d'hôte saisie (réutilisée par le menu COOP / la montre)
var smartplug_enabled: bool = DEF.smartplug_enabled   # prise Kasa HS-110 : ventilateur ON en vol, OFF à la marche
var smartplug_ip: String = DEF.smartplug_ip           # IP fixe de la prise ("" = découverte auto par broadcast)
var smartplug_name: String = DEF.smartplug_name       # nom (alias Kasa) ciblé ("" = 1re prise Kasa trouvée)
var start_last_seed: int = DEF.start_last_seed         # écran de départ : dernier seed lancé (-1 = aucun) → « Continuer »
var start_last_system: int = DEF.start_last_system     # écran de départ : dernier index système lancé (-1 = aucun)

var _has_file := false

func _ready() -> void:
	load_settings()
	# Appliqué APRÈS le _ready de la scène : XRManager/ImmersionFX règlent le viewport au boot, on passe ensuite.
	apply_all.call_deferred()

func apply_all() -> void:
	apply_graphics()
	apply_fx()
	apply_audio()
	apply_haptics()
	apply_smartplug()
	if _has_file:
		apply_window()   # ne force fenêtre/résolution QUE si un réglage explicite existe (sinon défaut moteur)

# --- Application ---

func apply_graphics() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_scale = clampf(render_scale, 0.5, 2.0)
		vp.msaa_3d = MSAA_MODES[clampi(msaa_index, 0, MSAA_MODES.size() - 1)]
	Engine.max_fps = FPS_VALUES[clampi(fps_index, 0, FPS_VALUES.size() - 1)]
	# La v-sync est pilotée par le compositeur en XR (XRManager la coupe) : on n'y touche qu'en bureau.
	if not GameState.xr_active:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)

func apply_window() -> void:
	if GameState.xr_active:
		return   # en XR le compositeur gère l'affichage : pas de gestion de fenêtre
	match window_mode:
		1:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			var res: Vector2i = RESOLUTIONS[clampi(resolution_index, 0, RESOLUTIONS.size() - 1)]
			DisplayServer.window_set_size(res)
			var sc := DisplayServer.window_get_current_screen()
			DisplayServer.window_set_position(DisplayServer.screen_get_position(sc) + (DisplayServer.screen_get_size(sc) - res) / 2)

func apply_fx() -> void:
	# Post-FX (glow / SSAO / SSIL) ON-OFF, centralisé par ImmersionFX (espace + surface, en direct).
	ImmersionFX.set_post_fx(fx_glow, fx_ssao, fx_ssil)

func apply_audio() -> void:
	# Scale RELATIF au baseline approuvé (1.0 = mix d'origine). Ambiance pilote World + Weather ensemble.
	AudioEngine.set_bus_scale("Master", vol_master)
	AudioEngine.set_bus_scale("Ambient_World", vol_ambient)
	AudioEngine.set_bus_scale("Ambient_Weather", vol_ambient)
	AudioEngine.set_bus_scale("SFX", vol_sfx)

func apply_haptics() -> void:
	BHaptics.set_enabled(haptics_enabled)
	BHaptics.set_intensity(haptics_intensity)

func apply_smartplug() -> void:
	SmartPlug.configure(smartplug_enabled, smartplug_ip, smartplug_name)

func reset_defaults() -> void:
	render_scale = DEF.render_scale
	msaa_index = DEF.msaa_index
	vsync = DEF.vsync
	window_mode = DEF.window_mode
	resolution_index = DEF.resolution_index
	fps_index = DEF.fps_index
	fx_glow = DEF.fx_glow
	fx_ssao = DEF.fx_ssao
	fx_ssil = DEF.fx_ssil
	vol_master = DEF.vol_master
	vol_ambient = DEF.vol_ambient
	vol_sfx = DEF.vol_sfx
	haptics_enabled = DEF.haptics_enabled
	haptics_intensity = DEF.haptics_intensity
	vignette_on = DEF.vignette_on
	vignette_strength = DEF.vignette_strength
	turn_mode = DEF.turn_mode
	snap_angle = DEF.snap_angle
	coop_ip = DEF.coop_ip
	smartplug_enabled = DEF.smartplug_enabled
	smartplug_ip = DEF.smartplug_ip
	smartplug_name = DEF.smartplug_name
	apply_graphics()
	apply_fx()
	apply_audio()
	apply_haptics()
	apply_smartplug()
	apply_window()
	save_settings()

# --- Persistance ---

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return   # aucun fichier => défauts
	_has_file = true
	render_scale = float(cfg.get_value("graphics", "render_scale", render_scale))   # coercition défensive (cfg ancien/corrompu)
	# int() défensif sur les champs-INDEX : un .cfg ancien/corrompu peut stocker 0.0 -> redevenu float,
	# ce qui casse clampi()/indexation/match. Cast explicite à la relecture.
	msaa_index = int(cfg.get_value("graphics", "msaa_index", msaa_index))
	vsync = cfg.get_value("graphics", "vsync", vsync)
	window_mode = int(cfg.get_value("graphics", "window_mode", window_mode))
	resolution_index = int(cfg.get_value("graphics", "resolution_index", resolution_index))
	fps_index = int(cfg.get_value("graphics", "fps_index", fps_index))
	fx_glow = cfg.get_value("graphics", "fx_glow", fx_glow)
	fx_ssao = cfg.get_value("graphics", "fx_ssao", fx_ssao)
	fx_ssil = cfg.get_value("graphics", "fx_ssil", fx_ssil)
	vol_master = cfg.get_value("audio", "master", vol_master)
	vol_ambient = cfg.get_value("audio", "ambient", vol_ambient)
	vol_sfx = cfg.get_value("audio", "sfx", vol_sfx)
	haptics_enabled = cfg.get_value("haptics", "enabled", haptics_enabled)
	haptics_intensity = cfg.get_value("haptics", "intensity", haptics_intensity)
	vignette_on = cfg.get_value("comfort", "vignette_on", vignette_on)
	turn_mode = int(cfg.get_value("comfort", "turn_mode", turn_mode))
	snap_angle = float(cfg.get_value("comfort", "snap_angle", snap_angle))
	vignette_strength = float(cfg.get_value("comfort", "vignette_strength", vignette_strength))
	coop_ip = str(cfg.get_value("coop", "ip", coop_ip))
	smartplug_enabled = cfg.get_value("smartplug", "enabled", smartplug_enabled)
	smartplug_ip = str(cfg.get_value("smartplug", "ip", smartplug_ip))
	smartplug_name = str(cfg.get_value("smartplug", "name", smartplug_name))
	start_last_seed = int(cfg.get_value("start", "last_seed", start_last_seed))
	start_last_system = int(cfg.get_value("start", "last_system", start_last_system))

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "render_scale", render_scale)
	cfg.set_value("graphics", "msaa_index", msaa_index)
	cfg.set_value("graphics", "vsync", vsync)
	cfg.set_value("graphics", "window_mode", window_mode)
	cfg.set_value("graphics", "resolution_index", resolution_index)
	cfg.set_value("graphics", "fps_index", fps_index)
	cfg.set_value("graphics", "fx_glow", fx_glow)
	cfg.set_value("graphics", "fx_ssao", fx_ssao)
	cfg.set_value("graphics", "fx_ssil", fx_ssil)
	cfg.set_value("audio", "master", vol_master)
	cfg.set_value("audio", "ambient", vol_ambient)
	cfg.set_value("audio", "sfx", vol_sfx)
	cfg.set_value("haptics", "enabled", haptics_enabled)
	cfg.set_value("haptics", "intensity", haptics_intensity)
	cfg.set_value("comfort", "vignette_on", vignette_on)
	cfg.set_value("comfort", "vignette_strength", vignette_strength)
	cfg.set_value("comfort", "turn_mode", turn_mode)
	cfg.set_value("comfort", "snap_angle", snap_angle)
	cfg.set_value("coop", "ip", coop_ip)
	cfg.set_value("smartplug", "enabled", smartplug_enabled)
	cfg.set_value("smartplug", "ip", smartplug_ip)
	cfg.set_value("smartplug", "name", smartplug_name)
	cfg.set_value("start", "last_seed", start_last_seed)
	cfg.set_value("start", "last_system", start_last_system)
	cfg.save(PATH)
	_has_file = true
