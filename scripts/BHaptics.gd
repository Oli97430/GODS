extends Node
## bHaptics TactSuit X40 — retour haptique GILET (40 moteurs : 20 avant + 20 arrière), en parallèle
## du haptique manettes. Pilote le serveur WebSocket LOCAL du « bHaptics Player » (l'appli PC) via le
## protocole legacy « direct submit » (dotPoints) : aucune dépendance, aucune authentification cloud,
## fonctionne avec le Player installé + le gilet appairé. Autoload, accessible globalement : BHaptics.xxx().
##
## DÉGRADATION GRACIEUSE : si le Player n'est pas lancé (ou pas de gilet), la connexion échoue en
## silence et TOUTES les méthodes deviennent des no-op — le jeu n'est jamais impacté. Reconnexion
## automatique périodique (on peut lancer le Player après le jeu).
##
## Réf. protocole (SDK bHaptics, WebSocketSender) :
##   URL    : ws://127.0.0.1:15881/v2/feedbacks?app_id=...&app_name=...
##   Message: {"Register":[],"Submit":[{"type":"frame","key":K,"Frame":{
##              "durationMillis":D,"position":"VestFront","dotPoints":[{"index":i,"intensity":0..100}],
##              "pathPoints":[]}}]}
##   Casse MIXTE imposée par le Player : Submit/Frame (PascalCase), type/key/durationMillis/position/
##   dotPoints (camelCase), index/intensity (minuscule). Positions X40 : "VestFront" / "VestBack".

const WS_URL := "ws://127.0.0.1:15881/v2/feedbacks?app_id=GODS_VR&app_name=GODS_VR"
const RETRY_MIN := 4.0        # s : 1er délai de (re)connexion au Player
const RETRY_MAX := 30.0       # s : plafond du back-off (Player jamais lancé => essais espacés, pas de spam)
const FRONT := "VestFront"
const BACK := "VestBack"
const DOTS_PER_SIDE := 20      # X40 : 4 colonnes × 5 rangées par face

var _ws := WebSocketPeer.new()
var _open := false             # true = connecté au Player (gilet potentiellement présent)
var _retry_t := 0.0
var _retry_period := RETRY_MIN   # délai courant (croît en back-off tant que la connexion échoue)
var _enabled := true           # coupe-circuit global (réglable depuis l'UI plus tard)
var _intensity_scale := 1.0    # multiplicateur global d'intensité de TOUS les motifs (menu Options)
var _rng := RandomNumberGenerator.new()   # ordre des gouttes de pluie — éphémère, HORS déterminisme monde

func _ready() -> void:
	_rng.randomize()
	# Tentative initiale (échoue en silence si le Player n'est pas là — repris par le retry).
	_ws.connect_to_url(WS_URL)
	set_process(true)

func _process(delta: float) -> void:
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _open:
			_open = true
			_retry_period = RETRY_MIN   # connecté : une déconnexion future retentera vite d'abord
			print("[bHaptics] connecté au Player (gilet X40 actif si appairé)")
		# On vide les messages de statut du Player (non utilisés mais à consommer).
		while _ws.get_available_packet_count() > 0:
			_ws.get_packet()
	elif st == WebSocketPeer.STATE_CLOSED:
		if _open:
			_open = false
			_retry_period = RETRY_MIN
			print("[bHaptics] Player déconnecté")
		_retry_t += delta
		if _retry_t >= _retry_period:
			_retry_t = 0.0
			_retry_period = minf(_retry_period * 1.6, RETRY_MAX)   # back-off : espace les essais tant que ça échoue
			_ws = WebSocketPeer.new()   # un peer « closed » ne se rouvre pas : on en recrée un
			_ws.connect_to_url(WS_URL)
	elif st == WebSocketPeer.STATE_CONNECTING:
		# Garde-fou : si le handshake reste bloqué (port filtré, upgrade WS jamais complété), on ne
		# retomberait jamais en CLOSED => on timeoute aussi ici pour repartir d'un peer neuf.
		_retry_t += delta
		if _retry_t >= _retry_period:
			_retry_t = 0.0
			_retry_period = minf(_retry_period * 1.6, RETRY_MAX)
			_ws = WebSocketPeer.new()
			_ws.connect_to_url(WS_URL)
	# STATE_CLOSING : on patiente jusqu'au prochain poll.

# Vrai si le Player est joignable (le gilet reçoit). Sert aussi à éviter tout travail si absent.
func is_suit_connected() -> bool:
	return _open and _enabled

func set_enabled(on: bool) -> void:
	_enabled = on
	if not on:
		turn_off_all()

func is_enabled() -> bool:
	return _enabled

# Le Player est-il joignable (indépendamment du coupe-circuit) — pour l'état affiché dans les options.
func is_player_connected() -> bool:
	return _open

# Multiplicateur global d'intensité de tous les motifs (0..1.5), appliqué dans submit_dots().
func set_intensity(s: float) -> void:
	_intensity_scale = clampf(s, 0.0, 1.5)

func get_intensity() -> float:
	return _intensity_scale

# --- Envoi bas niveau ------------------------------------------------------------------------------

# Envoi bas niveau. Vérifie SEULEMENT `_open` (pas `_enabled`) : turn_off/turn_off_all doivent pouvoir
# couper le gilet même après désactivation du coupe-circuit. Les motifs passent, eux, par
# is_suit_connected() (= _open ET _enabled) => rien ne part si désactivé.
func _send(obj: Dictionary) -> void:
	if not _open:
		return
	_ws.send_text(JSON.stringify(obj))

# Soumet une trame de dots sur UNE face. `dots` : Array de [index, intensity]. Ignore les intensités <=0.
func submit_dots(key: String, position: String, dots: Array, duration_ms: int) -> void:
	if not is_suit_connected() or dots.is_empty():
		return
	var pts := []
	for d in dots:
		var inten := int(clampf(d[1] * _intensity_scale, 0.0, 100.0))
		if inten <= 0:
			continue
		pts.append({"index": int(d[0]), "intensity": inten})
	if pts.is_empty():
		return
	_send({
		"Register": [],
		"Submit": [{
			"type": "frame",
			"key": key,
			"Frame": {
				"durationMillis": clampi(duration_ms, 20, 100000),
				"position": position,
				"dotPoints": pts,
				"pathPoints": [],
			},
		}],
	})

# Coupe un effet par clé / tout.
func turn_off(key: String) -> void:
	if not _open:
		return
	_send({"Register": [], "Submit": [{"type": "turnOff", "key": key}]})

func turn_off_all() -> void:
	if not _open:
		return
	_send({"Register": [], "Submit": [{"type": "turnOffAll"}]})

# --- Construction de motifs (20 intensités par face) -----------------------------------------------

# Soumet un tableau de 20 intensités sur une face (zéros ignorés).
func _submit_side(key: String, position: String, intens20: Array, duration_ms: int) -> void:
	var dots := []
	for i in DOTS_PER_SIDE:
		if intens20[i] > 0:
			dots.append([i, intens20[i]])
	submit_dots(key, position, dots, duration_ms)

# Même motif avant + arrière (clés distinctes pour ne pas s'écraser).
func _submit_both(key: String, intens20: Array, duration_ms: int) -> void:
	_submit_side(key + "F", FRONT, intens20, duration_ms)
	_submit_side(key + "B", BACK, intens20, duration_ms)

# Tableau de 20 intensités à partir d'un poids par RANGÉE (haut→bas, 5 valeurs) × base.
func _rows(weights: Array, base: float) -> Array:
	var out := []
	out.resize(DOTS_PER_SIDE)
	for r in 5:
		var v := int(clampf(base * float(weights[r]), 0.0, 100.0))
		for c in 4:
			out[r * 4 + c] = v
	return out

# Tableau uniforme (toutes rangées à la même intensité).
func _uniform(base: float) -> Array:
	return _rows([1.0, 1.0, 1.0, 1.0, 1.0], base)

# --- Motifs de jeu (mappés sur les mêmes événements que le haptique manettes) -----------------------

# Atterrissage : secousse pondérée vers le bas (jambes/bas du torse), intensité ∝ force d'impact 0..1.
func landing(strength: float, dur := 150) -> void:
	if not is_suit_connected():
		return
	var base := 42.0 + 55.0 * clampf(strength, 0.0, 1.0)
	_submit_both("land", _rows([0.2, 0.35, 0.55, 0.8, 1.0], base), dur)

# Rumble continu (repulseurs Iron Man) : nappe uniforme basse, rappelée à intervalle (~0,1 s) => continu.
func flight_rumble(intensity: float, dur := 130) -> void:
	if not is_suit_connected():
		return
	_submit_both("fly", _uniform(15.0 + 50.0 * clampf(intensity, 0.0, 1.0)), dur)

# Ouverture de voile : à-coup haut (épaules/poitrine — la sellette tire vers le haut).
func deploy(dur := 200) -> void:
	if not is_suit_connected():
		return
	_submit_both("deploy", _rows([1.0, 0.8, 0.4, 0.1, 0.0], 95.0), dur)

# Enclenchement de l'armure : « mise sous tension » ferme et pleine.
func armor_on(dur := 170) -> void:
	if not is_suit_connected():
		return
	_submit_both("armor", _uniform(72.0), dur)

# Tap doux générique (repli voile, extinction armure, posé en douceur).
func soft_tap(intensity := 30.0, dur := 100) -> void:
	if not is_suit_connected():
		return
	_submit_both("soft", _uniform(intensity), dur)

# Ascendance (parapente) : frisson léger sur les rangées médianes (on « monte »).
func thermal(intensity: float, dur := 70) -> void:
	if not is_suit_connected():
		return
	_submit_both("therm", _rows([0.4, 0.8, 1.0, 0.8, 0.4], 14.0 + 20.0 * clampf(intensity, 0.0, 1.0)), dur)

# Souffle de vol-plané : pression d'air sur la POITRINE (face avant uniquement), ∝ vitesse-air 0..1.
func glide_buffet(intensity: float, dur := 120) -> void:
	if not is_suit_connected():
		return
	_submit_side("buffet", FRONT, _rows([0.6, 1.0, 0.8, 0.4, 0.2], 10.0 + 32.0 * clampf(intensity, 0.0, 1.0)), dur)

# --- Motifs de COMBAT (phase 26) — ressenti opt-in, no-op si gilet absent ---------------------------

# Recul d'arme : « coup » sec dans la poitrine (face avant, haut du torse), ∝ poids de l'arme 0..1.
func weapon_recoil(strength: float) -> void:
	if not is_suit_connected():
		return
	var base := 28.0 + 58.0 * clampf(strength, 0.0, 1.0)
	_submit_side("recoil", FRONT, _rows([0.9, 1.0, 0.6, 0.2, 0.0], base), 90)

# Encaissement DIRECTIONNEL : la secousse part de la direction d'où vient le tir (avant/arrière + côté).
# local_dir = direction vers le tireur dans le repère caméra (x=droite, z=arrière) ; strength 0..1.
func damage_hit(local_dir: Vector3, strength: float) -> void:
	if not is_suit_connected():
		return
	var d := Vector2(local_dir.x, local_dir.z)
	if d.length() < 0.01:
		d = Vector2(0.0, -1.0)
	d = d.normalized()
	var pos := FRONT if d.y < 0.0 else BACK   # -Z (caméra) = devant => face avant du gilet
	var cols := _dir_columns(d.x)
	var base := 42.0 + 52.0 * clampf(strength, 0.0, 1.0)
	var arr := []
	arr.resize(DOTS_PER_SIDE)
	var rw := [0.5, 0.85, 1.0, 0.75, 0.45]   # centré poitrine/ventre
	for r in 5:
		for c in 4:
			arr[r * 4 + c] = base * rw[r] * cols[c]
	_submit_side("dmg", pos, arr, 130)

# Poids de colonnes (gauche→droite) selon le côté du tir : x=-1 gauche .. +1 droite.
func _dir_columns(x: float) -> Array:
	var l := clampf(0.55 - x, 0.2, 1.0)
	var r := clampf(0.55 + x, 0.2, 1.0)
	return [l, lerpf(l, r, 0.34), lerpf(l, r, 0.67), r]

# Confirmation de destruction d'un drone : petit tap sec mi-poitrine.
func kill_confirm() -> void:
	if not is_suit_connected():
		return
	submit_dots("kill", FRONT, [[5, 48], [6, 48], [9, 30], [10, 30]], 60)

# Soin (vague nettoyée) : nappe douce et chaude qui monte le long du torse. amount 0..1.
func heal_pulse(amount: float) -> void:
	if not is_suit_connected():
		return
	_submit_both("heal", _rows([0.3, 0.55, 0.8, 0.55, 0.3], 22.0 + 22.0 * clampf(amount, 0.0, 1.0)), 260)

# Bouclier qui intercepte un tir : buzz sur la POITRINE GAUCHE (le bouclier est en main gauche).
func shield_block() -> void:
	if not is_suit_connected():
		return
	submit_dots("block", FRONT, [[0, 30], [4, 58], [8, 52], [12, 46], [16, 28]], 90)

# Mort en combat : gros choc plein gilet (avant + arrière).
func combat_death() -> void:
	if not is_suit_connected():
		return
	_submit_both("cdeath", _uniform(92.0), 380)

# --- Extensions ambiance / UI (appelées en cadence par les systèmes concernés) ---------------------

# Pluie : quelques gouttes ÉPARSES (dots aléatoires faibles), avant + arrière. Intensité ∝ précip 0..1.
func rain(intensity: float) -> void:
	if not is_suit_connected():
		return
	var f := clampf(intensity, 0.0, 1.0)
	var n := 1 + int(round(5.0 * f))
	var amp := 12.0 + 26.0 * f
	for pos in [FRONT, BACK]:
		var used := {}
		var dots := []
		for k in n:
			var idx := _rng.randi_range(0, DOTS_PER_SIDE - 1)
			if used.has(idx):
				continue   # pas de goutte en double sur le même moteur
			used[idx] = true
			dots.append([idx, amp])
		submit_dots("rain_" + pos, pos, dots, 70)

# Vent : bouffée douce sur les COLONNES EXTÉRIEURES (ça « enveloppe » le torse), avant + arrière.
func wind(intensity: float) -> void:
	if not is_suit_connected():
		return
	var amp := 9.0 + 20.0 * clampf(intensity, 0.0, 1.0)
	var a := []
	a.resize(DOTS_PER_SIDE)
	for i in DOTS_PER_SIDE:
		a[i] = amp if (i % 4 == 0 or i % 4 == 3) else 0.0
	_submit_both("wind", a, 200)

# Battement de cœur (moments calmes) : pulsation douce sur la poitrine GAUCHE (index 8,9,12,13).
func heartbeat() -> void:
	if not is_suit_connected():
		return
	submit_dots("heart", FRONT, [[8, 38], [9, 30], [12, 30], [13, 22]], 130)

# Tic UI (toucher l'écran de la montre-poignet) : très léger, haut du gilet.
func ui_tick() -> void:
	if not is_suit_connected():
		return
	submit_dots("uitick", FRONT, [[1, 22], [2, 22]], 45)

# Transition d'échelle (galaxie/système/planète/surface) : houle douce traversant le gilet. Descente
# (on plonge dans l'échelle) = plus marquée ; remontée = plus légère.
func transition_swell(descending: bool) -> void:
	if not is_suit_connected():
		return
	_submit_both("trans", _uniform(48.0 if descending else 30.0), 340)
