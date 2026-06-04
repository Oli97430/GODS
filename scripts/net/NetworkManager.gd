extends Node
## Phase MULTIJOUEUR (coop) — CP0 : SOCLE réseau P2P direct (ENet). Héberger / rejoindre par IP, suivre les
## pairs, exposer des signaux. AUCUN gameplay réseau ici : juste la connexion. Le MONDE n'est JAMAIS
## synchronisé (déterministe par seed) ; on synchronisera plus tard les joueurs + entités dynamiques.
## Autoload : NetworkManager. P2P direct : un HÔTE (id==1) + des INVITÉS par IP (LAN simple ; IP publique =
## port-forward). Entrée DEV (test sans UI) : lancer avec « -- --host » ou « -- --join <ip> ».

signal peer_joined(id: int)          # un pair s'est connecté
signal peer_left(id: int)            # un pair s'est déconnecté
signal session_started(is_host: bool) # héberger réussi OU connexion à l'hôte établie
signal session_ended()               # déconnexion / fermeture
signal connection_failed_()          # l'invité n'a pas pu joindre l'hôte

const DEFAULT_PORT := 7711
const MAX_PEERS := 7                  # MVP 2 joueurs ; marge pour plus tard

var _peer: ENetMultiplayerPeer = null
var _active := false
var _dev_cmd := ""
var _dev_ip := "127.0.0.1"

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# Entrée DEV : --host / --join <ip> passés APRÈS « -- » sur la ligne de commande (test sans UI).
	var ua := OS.get_cmdline_user_args()
	if ua.has("--host"):
		_dev_cmd = "host"
	elif ua.has("--join"):
		_dev_cmd = "join"
		var i := ua.find("--join")
		if i >= 0 and i + 1 < ua.size():
			_dev_ip = ua[i + 1]
	if _dev_cmd != "":
		call_deferred("_dev_start")

func _dev_start() -> void:
	if _dev_cmd == "host":
		host()
	elif _dev_cmd == "join":
		join(_dev_ip)

# --- API publique ---

# Démarre un serveur ENet. Retourne true si l'écoute est ouverte.
func host(port := DEFAULT_PORT) -> bool:
	leave()
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(port, MAX_PEERS)
	if err != OK:
		push_warning("[Net] create_server échec (port %d) : %s" % [port, error_string(err)])
		return false
	_peer = p
	multiplayer.multiplayer_peer = p
	_active = true
	print("[Net] HÔTE démarré, port %d (id %d)" % [port, multiplayer.get_unique_id()])
	session_started.emit(true)
	return true

# Rejoint un hôte. session_started est émis plus tard, à connected_to_server.
func join(ip := "127.0.0.1", port := DEFAULT_PORT) -> bool:
	leave()
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(ip, port)
	if err != OK:
		push_warning("[Net] create_client échec (%s:%d) : %s" % [ip, port, error_string(err)])
		return false
	_peer = p
	multiplayer.multiplayer_peer = p
	_active = true
	print("[Net] connexion à %s:%d…" % [ip, port])
	return true

# Ferme la session (hôte ou invité).
func leave() -> void:
	if _peer == null and not _active:
		return
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	if _active:
		_active = false
		session_ended.emit()

func is_active() -> bool:
	return _active and multiplayer.multiplayer_peer != null

func is_host() -> bool:
	return is_active() and multiplayer.is_server()

func local_id() -> int:
	return multiplayer.get_unique_id() if is_active() else 0

func peers() -> Array:
	return multiplayer.get_peers() if is_active() else []

# --- Callbacks bas niveau ---

func _on_peer_connected(id: int) -> void:
	print("[Net] pair connecté : %d" % id)
	peer_joined.emit(id)

func _on_peer_disconnected(id: int) -> void:
	print("[Net] pair déconnecté : %d" % id)
	peer_left.emit(id)

func _on_connected_to_server() -> void:
	print("[Net] connecté à l'hôte (id %d)" % multiplayer.get_unique_id())
	session_started.emit(false)

func _on_connection_failed() -> void:
	push_warning("[Net] connexion à l'hôte ÉCHOUÉE")
	_peer = null
	multiplayer.multiplayer_peer = null
	_active = false
	connection_failed_.emit()

func _on_server_disconnected() -> void:
	print("[Net] hôte déconnecté")
	leave()
