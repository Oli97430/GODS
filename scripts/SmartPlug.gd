extends Node
## Prise connectée TP-Link Kasa (HS-100 / HS-110) — pilotage LOCAL (sans cloud) d'un appareil branché
## dessus (typiquement un VENTILATEUR) : ALLUMÉ quand le joueur VOLE (armure « Iron Man » ou parapente),
## ÉTEINT quand il MARCHE. Autoload, accessible globalement : `SmartPlug.set_airborne(bool)`.
##
## DÉGRADATION GRACIEUSE (comme BHaptics) : si aucune prise n'est trouvée sur le réseau (ou réglage
## désactivé), TOUT devient no-op — le jeu n'est jamais impacté. Découverte ET envois se font HORS
## THREAD PRINCIPAL (WorkerThreadPool) : aucune saccade VR, même si le réseau est lent ou la prise absente.
##
## Protocole Kasa local (documenté, réutilisé par python-kasa / tplink-smarthome-api) :
##   • Port 9999. Charge utile = JSON « chiffré » par XOR autokey (clé initiale 171, chaînée octet à octet).
##   • TCP  : préfixe big-endian 4 octets = longueur de la charge.   UDP (découverte) : pas de préfixe.
##   • Allumer : {"system":{"set_relay_state":{"state":1}}}    Éteindre : state 0.
##   • Découverte : broadcast 255.255.255.255:9999 de {"system":{"get_sysinfo":{}}} ; les prises répondent.

const PORT := 9999
const CMD_ON := '{"system":{"set_relay_state":{"state":1}}}'
const CMD_OFF := '{"system":{"set_relay_state":{"state":0}}}'
const CMD_INFO := '{"system":{"get_sysinfo":{}}}'

const ON_DEBOUNCE := 0.0     # s : allumage IMMÉDIAT (vol/chute délibérés, aucun flicker) — « anticipation » du souffle
const OFF_DEBOUNCE := 0.4    # s : extinction TEMPORISÉE (anti-flicker si on touche le sol une fraction de seconde)
const HOLD_TIMEOUT := 1.5    # s : sans rafraîchissement (contrôleur joueur muet = embarqué/menu/quitté) => OFF de sécurité
const RESEND := 6.0          # s : ré-affirme périodiquement l'état courant (auto-réparation si un paquet s'est perdu)
const DISCOVER_CD := 8.0     # s : délai entre deux découvertes infructueuses (évite le spam de broadcast)

var _enabled := true         # coupe-circuit global (Settings.smartplug_enabled)
var _ip := ""                # IP de la prise (manuelle via Settings, sinon découverte). "" = inconnue
var _manual_ip := ""         # override explicite (Settings) ; si non vide, court-circuite/écrase la découverte
var _model := ""             # modèle remonté par la prise (diagnostic / UI)
var _alias := ""             # nom (alias Kasa) de la prise — affiché dans l'UI
var _want_name := ""         # nom cible (Settings) : si non vide, ne cible QUE la prise portant cet alias
var _had_manual := false     # l'IP était-elle manuelle au dernier configure (pour repasser en auto proprement)

var _desired := false        # état VOULU (vol = true)
var _sent := false           # dernier état EFFECTIVEMENT confirmé envoyé à la prise
var _stable := 0.0           # temps pendant lequel _desired diffère de _sent (debounce)
var _since_refresh := 0.0    # temps depuis le dernier set_airborne() (watchdog contrôleur)
var _resend_t := 0.0         # ré-affirmation périodique
var _sending := false        # un envoi est en cours sur un thread du pool (évite l'empilement)
var _discovering := false    # une découverte est en cours sur un thread du pool
var _discover_cd := 0.0      # cooldown courant avant la prochaine tentative de découverte
var _quit_off_done := false  # garde-fou : prise éteinte une seule fois à la fermeture
var _pending_off := false    # un OFF de sécurité est demandé alors qu'un envoi est déjà en vol => rejoué au retour

func _ready() -> void:
	set_process(true)
	# Settings.apply_smartplug() pousse enabled + IP au boot (et lance la découverte si besoin).
	# Filet pour un lancement isolé (sans Settings) : tente une découverte différée.
	_ensure_discovery.call_deferred()

func _process(delta: float) -> void:
	if not _enabled:
		return
	if _discover_cd > 0.0:
		_discover_cd -= delta
	_since_refresh += delta
	# Watchdog : si le contrôleur joueur ne rafraîchit plus l'état (embarqué dans le ship, menu, scène
	# changée, jeu quitté), on considère « plus en vol » => extinction de sécurité du ventilateur.
	if _since_refresh > HOLD_TIMEOUT:
		_desired = false
	if _desired != _sent:
		_stable += delta
		var thresh := ON_DEBOUNCE if _desired else OFF_DEBOUNCE   # allumage immédiat, extinction temporisée
		if _stable >= thresh:
			_try_commit()
	else:
		_stable = 0.0
		_resend_t += delta
		if _resend_t >= RESEND:
			_resend_t = 0.0
			_try_commit()   # ré-affirme l'état courant (robustesse paquets perdus)

# --- API publique ---------------------------------------------------------------------------------

## Appelé CHAQUE frame par le PlayerController : true = le joueur est en l'air (vol/parapente).
func set_airborne(on: bool) -> void:
	_since_refresh = 0.0   # le contrôleur est vivant : rearme le watchdog
	_desired = on

## Poussé par Settings : coupe-circuit + IP manuelle ("" => auto) + nom cible ("" => 1re prise Kasa).
func configure(enabled: bool, manual_ip: String, name: String) -> void:
	var was := _enabled
	_enabled = enabled
	var nm := name.strip_edges()
	var name_changed := nm != _want_name
	_want_name = nm
	var mip := manual_ip.strip_edges()
	var manual_now := mip != ""
	_manual_ip = mip
	if manual_now:
		_ip = mip
	elif name_changed or _had_manual:
		_ip = ""            # cible changée / retour en auto : oublie l'IP et relance la découverte
		_discover_cd = 0.0
	_had_manual = manual_now
	if not _enabled:
		if was and _ip != "":
			_force_off()    # on quitte la fonctionnalité : éteint la prise par sécurité
		return
	if _ip == "":
		_ensure_discovery()

func is_enabled() -> bool:
	return _enabled

func current_ip() -> String:
	return _ip

func device_model() -> String:
	return _model

## Nom affichable de la prise : alias Kasa si défini, sinon modèle, sinon "prise".
func device_label() -> String:
	if _alias != "":
		return _alias
	return _model if _model != "" else "prise"

## Vrai si une prise est connue et la fonctionnalité active (pour l'état affiché dans les options).
func is_ready() -> bool:
	return _enabled and _ip != ""

## Vrai si une découverte est en cours (pour l'état affiché dans les options).
func is_searching() -> bool:
	return _discovering

## Relance une découverte réseau (bouton « Rechercher » de l'UI Options).
func rediscover() -> void:
	if _manual_ip == "":
		_ip = ""
	_discover_cd = 0.0
	_ensure_discovery()

## Test manuel depuis l'UI : allume ~1,2 s puis éteint, quel que soit l'état de vol (confirmation physique).
func test_pulse() -> void:
	if _ip == "" or _sending:
		return
	_sending = true
	WorkerThreadPool.add_task(_task_test.bind(_ip))

func _task_test(ip: String) -> void:
	send_command(ip, CMD_ON)
	OS.delay_msec(1200)
	send_command(ip, CMD_OFF)
	call_deferred("_on_sent", true, false)   # libère _sending + état cohérent (prise éteinte)

# --- Commutation (orchestration thread principal) -------------------------------------------------

func _try_commit() -> void:
	if _sending:
		return                      # un envoi est déjà en vol : on réessaiera au prochain tick
	if _ip == "":
		_ensure_discovery()         # IP inconnue : (re)cherche la prise, puis réessaiera
		return
	_sending = true
	var cmd := CMD_ON if _desired else CMD_OFF
	WorkerThreadPool.add_task(_task_send.bind(_ip, cmd, _desired))

func _force_off() -> void:
	# Extinction immédiate « fire-and-forget » (désactivation de la fonctionnalité).
	_desired = false
	_sent = false
	if _ip == "":
		return
	if _sending:
		# Un envoi (souvent la ré-affirmation ON du vol) est déjà parti : on ne peut pas l'empiler. On note
		# l'OFF de sécurité ; il sera rejoué dès le retour de la tâche, sinon le ventilateur resterait allumé.
		_pending_off = true
		return
	_sending = true
	WorkerThreadPool.add_task(_task_send.bind(_ip, CMD_OFF, false))

func _task_send(ip: String, cmd: String, state: bool) -> void:
	# Corps de thread (pool) : envoi TCP bloquant + timeout, puis retour au thread principal.
	var ok := send_command(ip, cmd)
	call_deferred("_on_sent", ok, state)

func _on_sent(ok: bool, state: bool) -> void:
	_sending = false
	if ok:
		_sent = state   # confirmé : _desired==_sent => bascule en ré-affirmation périodique
	if _pending_off and _ip != "":
		# Un OFF de sécurité a été demandé pendant l'envoi (fonctionnalité coupée en vol) : rejoue-le maintenant.
		_pending_off = false
		_sent = false
		_sending = true
		WorkerThreadPool.add_task(_task_send.bind(_ip, CMD_OFF, false))

func _ensure_discovery() -> void:
	if _discovering or _manual_ip != "" or _discover_cd > 0.0:
		return
	_discovering = true
	WorkerThreadPool.add_task(_task_discover)

func _task_discover() -> void:
	var res := discover(1600, _want_name)
	call_deferred("_on_discovered", res[0], res[1], res[2])

func _on_discovered(ip: String, model: String, alias: String) -> void:
	_discovering = false
	if _manual_ip != "":
		return   # une IP manuelle reste prioritaire sur la découverte
	if ip != "":
		_ip = ip
		_model = model
		_alias = alias
		print("[SmartPlug] prise trouvée : %s (%s%s)" % [ip, model if model != "" else "modèle inconnu", "" if alias == "" else " / " + alias])
	else:
		_discover_cd = DISCOVER_CD
		var tgt := "" if _want_name == "" else " nommée « %s »" % _want_name
		print("[SmartPlug] aucune prise Kasa%s détectée (broadcast %d). Réessai dans %ds, ou IP/nom manuels." % [tgt, PORT, int(DISCOVER_CD)])

func _notification(what: int) -> void:
	# À la fermeture, on éteint la prise (le ventilateur ne reste pas allumé après avoir quitté en vol).
	# Best-effort SYNCHRONE (court timeout) : si le réseau est down, l'appel échoue vite sans bloquer.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		if not _quit_off_done and _enabled and _ip != "":
			_quit_off_done = true
			send_command(_ip, CMD_OFF, 800)

# --- Protocole Kasa (statique, PUR : réutilisable depuis un script headless sans autoloads) --------

## Chiffre une commande JSON (XOR autokey, clé initiale 171).
static func _encrypt(s: String) -> PackedByteArray:
	var data := s.to_utf8_buffer()
	var out := PackedByteArray()
	out.resize(data.size())
	var key := 171
	for i in data.size():
		key = key ^ data[i]
		out[i] = key
	return out

## Déchiffre une réponse Kasa.
static func _decrypt(data: PackedByteArray) -> String:
	var out := PackedByteArray()
	out.resize(data.size())
	var key := 171
	for i in data.size():
		out[i] = key ^ data[i]
		key = data[i]
	return out.get_string_from_utf8()

## Envoie une commande à une prise (TCP, charge préfixée). Bloquant (à appeler hors thread principal
## ou depuis un script). Retourne true si la commande a été écrite sur la socket.
static func send_command(ip: String, json: String, timeout_ms := 1500) -> bool:
	if ip == "":
		return false
	var tcp := StreamPeerTCP.new()
	if tcp.connect_to_host(ip, PORT) != OK:
		return false
	var waited := 0
	while tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING and waited < timeout_ms:
		tcp.poll()
		OS.delay_msec(10)
		waited += 10
	if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		tcp.disconnect_from_host()
		return false
	tcp.set_no_delay(true)
	var payload := _encrypt(json)
	var n := payload.size()
	var msg := PackedByteArray([(n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF])
	msg.append_array(payload)
	var err := tcp.put_data(msg)
	# Lecture best-effort de la réponse : confirme le traitement + garantit le flush avant la fermeture.
	var rwait := 0
	while tcp.get_available_bytes() <= 0 and rwait < 400:
		tcp.poll()
		OS.delay_msec(10)
		rwait += 10
	tcp.disconnect_from_host()
	return err == OK

## Découverte par broadcast UDP (méthode officielle Kasa, DOUCE : quelques paquets). Retourne
## [ip, model, alias] ("" si rien trouvé). Bloquant (hors thread principal). `want_name` non vide => ne
## retient QUE la prise dont l'alias Kasa correspond (insensible à la casse).
## Émet sur le broadcast GLOBAL + DIRIGÉ /24 de chaque interface, ré-émis toutes les ~0,5 s (robustesse).
## ⚠️ PAS de balayage TCP : la pile réseau minuscule du HS-110 se fait SATURER par des connexions massives
## (elle devient muette). Si le broadcast est bloqué (réseau multi-cartes capricieux), renseigner l'IP fixe
## dans les options — chemin 100 % fiable (une seule connexion, douce).
static func discover(timeout_ms := 1500, want_name := "") -> Array:
	var udp := PacketPeerUDP.new()
	udp.set_broadcast_enabled(true)
	if udp.bind(0) != OK:
		return ["", "", ""]
	var enc := _encrypt(CMD_INFO)
	var targets: Array[String] = ["255.255.255.255"]
	for a in _local_ipv4():
		var p := a.split(".")
		if p.size() == 4:
			var b := "%s.%s.%s.255" % [p[0], p[1], p[2]]
			if not targets.has(b):
				targets.append(b)
	var wn := want_name.strip_edges().to_lower()
	var waited := 0
	while waited < timeout_ms:
		if waited % 500 == 0:   # (ré)émission toutes les ~0,5 s — robustesse paquets perdus
			for t in targets:
				udp.set_dest_address(t, PORT)
				udp.put_packet(enc)
		if udp.get_available_packet_count() > 0:
			var pkt := udp.get_packet()
			var sender := udp.get_packet_ip()
			var info := _parse_sysinfo(_decrypt(pkt))
			if not info.is_empty():
				var alias := str(info.get("alias", ""))
				if wn == "" or alias.to_lower() == wn:
					udp.close()
					return [sender, str(info.get("model", "")), alias]
		OS.delay_msec(20)
		waited += 20
	udp.close()
	return ["", "", ""]

## IPv4 locales utiles (hors IPv6 / loopback / APIPA).
static func _local_ipv4() -> Array[String]:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		if not a.contains(".") or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		out.append(a)
	return out

## Extrait le dictionnaire `system.get_sysinfo` (model, alias, relay_state…) d'une réponse Kasa. Vide si KO.
static func _parse_sysinfo(txt: String) -> Dictionary:
	var j = JSON.parse_string(txt)   # Variant : pas de `:=` (inférence impossible)
	if typeof(j) == TYPE_DICTIONARY and j.has("system"):
		var sys = j["system"]
		if typeof(sys) == TYPE_DICTIONARY and sys.has("get_sysinfo"):
			var info = sys["get_sysinfo"]
			if typeof(info) == TYPE_DICTIONARY:
				return info
	return {}
