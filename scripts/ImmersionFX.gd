class_name ImmersionFX
extends RefCounted
## Passe d'immersion graphique (PCVR) — réglages CENTRALISÉS appliqués à TOUTES les scènes (espace +
## surface) pour un rendu cinématique cohérent. Post-traitement ADDITIF : ne touche NI au background,
## NI au ciel/ambient/fog propres à chaque environnement — il n'ajoute que :
##   • Tonemap AgX + exposition  (gère les HDR : soleil/étoiles brillent sans cramer)
##   • Bloom / glow              (émissifs — soleil, étoiles, accents — qui rayonnent)
##   • SSAO                      (occlusion ambiante : profondeur, contact, relief)
##   • SSIL                      (lumière indirecte écran : rebonds doux — PCVR)
## + Réglage viewport : MSAA (anti-crénelage = gain de netteté ÉNORME en VR), sans FXAA/TAA (flou/ghosting).
## Cible RTX 3090. Un mode Quest-safe pourra couper SSAO/SSIL/glow plus tard (un seul point à toucher).

# Toggles post-FX (réglables via le menu Options) — défaut ON (= rendu d'origine). Lus par apply() et
# appliqués EN DIRECT aux environnements déjà créés via set_post_fx().
static var glow_on := true
static var ssao_on := true
static var ssil_on := true
static var _envs: Array = []   # WeakRef vers les Environment gérés (pour rafraîchir les toggles à chaud)

# Applique le post-traitement à un Environment (espace OU surface). Idempotent.
static func apply(env: Environment) -> void:
	if env == null:
		return
	# Tonemap cinématique + exposition.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 8.0
	# Bloom / glow.
	env.glow_enabled = glow_on
	env.glow_intensity = 0.85
	env.glow_strength = 1.0
	env.glow_bloom = 0.12
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	env.set("glow_levels/2", 1.0)
	env.set("glow_levels/3", 1.0)
	env.set("glow_levels/4", 1.0)
	env.set("glow_levels/5", 0.6)
	# Occlusion ambiante.
	env.ssao_enabled = ssao_on
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.0
	env.ssao_power = 1.5
	env.ssao_detail = 0.5
	# Lumière indirecte écran (PCVR).
	env.ssil_enabled = ssil_on
	env.ssil_intensity = 0.8
	env.ssil_radius = 4.0
	_register(env)

static func _register(env: Environment) -> void:
	# Dédupe + purge les WeakRef morts (envs surface détruits entre visites) => pas de croissance.
	var alive: Array = []
	var found := false
	for w in _envs:
		var e = w.get_ref()
		if e == null:
			continue
		alive.append(w)
		if e == env:
			found = true
	if not found:
		alive.append(weakref(env))
	_envs = alive

# Active/coupe les post-FX (menu Options) : maj des flags + application IMMÉDIATE aux environnements vivants.
static func set_post_fx(glow: bool, ssao: bool, ssil: bool) -> void:
	glow_on = glow
	ssao_on = ssao
	ssil_on = ssil
	var alive: Array = []
	for w in _envs:
		var e = w.get_ref()
		if e != null:
			e.glow_enabled = glow_on
			e.ssao_enabled = ssao_on
			e.ssil_enabled = ssil_on
			alive.append(w)
	_envs = alive

# Réglage du viewport : anti-crénelage MSAA (essentiel en VR), sans FXAA/TAA (flou/ghosting stéréo).
static func setup_viewport(vp: Viewport) -> void:
	if vp == null:
		return
	vp.msaa_3d = Viewport.MSAA_4X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	# Debanding (quasi gratuit : dither en fin de pipeline) : supprime les BANDES dans les dégradés doux —
	# ciel au crépuscule, brume, halo du soleil — très visibles sur les dalles de casque.
	vp.use_debanding = true
