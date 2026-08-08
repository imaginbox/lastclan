extends Node
## Lobby (Autoload "Lobby")
##
## Gère la connexion au relais multijoueur Ziva et le roster des joueurs.
## Modèle « cohabitation libre » : chaque joueur a sa propre base, dispersée sur
## une très grande carte (position calculée de façon déterministe depuis le
## peer_id, donc unique et stable). Pas encore de combat : pas besoin de spawner
## des objets partagés — on échange juste le roster et le chat.
##
## Le relais n'a PAS de serveur dédié : le peer 1 est un slot fantôme. Le "hôte"
## (peer réel le plus bas) serait l'autorité pour tout objet partagé futur.
##
## API :
##   - join_room(nom)      : connecte ce client à la room du relais.
##   - send_chat(text)     : diffuse un message à tous les joueurs de la room.
##   - signals : player_connected, player_disconnected, server_disconnected,
##               connection_status, chat_received, base_ready.
##   - propriétés : is_online, my_id, players, base_origin, has_base.

signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal server_disconnected
signal connection_status(text: String)
signal chat_received(author: String, text: String)
signal base_ready(origin: Vector3)

const WORLD_HALF: float = 190.0   # limite de placement des bases (mètres)
const BASE_SPACING: float = 18.0  # espacement entre deux bases (proches pour se voir)

var is_online: bool = false
var my_id: int = 0
var base_origin: Vector3 = Vector3.ZERO
var has_base: bool = false

## Info locale du joueur, transmise à chaque pair. Le nom est rempli par l'UI.
var player_info: Dictionary = {"name": "Joueur"}

## Roster : peer_id -> {"name": ...}
var players: Dictionary = {}

## Nom de la room (partie) choisie.
var room_id: String = "global"

## Délai max (s) avant de déclarer la connexion en échec si elle reste en attente.
const CONNECT_TIMEOUT: float = 8.0

var _connect_timer: SceneTreeTimer = null
var _retry_count: int = 0
const MAX_RETRIES: int = 3

## Socket brut de diagnostic : ouvert sur la même URL que le peer multijoueur,
## pour capturer le code/raison de fermeture WebSocket sans crasher.
var _diag_ws: WebSocketPeer = null
var _diag_closed: bool = false
var _diag_detail: String = ""

func _ready() -> void:
	_prepare_args()
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# En mode hors ligne (démo/solo/autotest), la base est à l'origine dès le départ.
	if _should_go_offline():
		_go_offline()

## Lit les arguments de ligne de commande (--room=<id>, --offline, --name=<nom>).
func _prepare_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--room="):
			room_id = arg.trim_prefix("--room=")
		elif arg.begins_with("--name="):
			player_info["name"] = arg.trim_prefix("--name=")

func _should_go_offline() -> bool:
	return OS.get_cmdline_user_args().has("--offline") \
		or OS.get_cmdline_user_args().has("--autotest")

## Mode hors ligne : base à l'origine, pas de réseau.
func _go_offline() -> void:
	is_online = false
	my_id = 0
	players.clear()
	players[0] = player_info
	base_origin = Vector3.ZERO
	has_base = true
	base_ready.emit(base_origin)
	connection_status.emit("Hors ligne")

## Connecte ce client au relais Ziva dans la room choisie.
func join_room(room: String) -> void:
	if not room.is_empty():
		room_id = room
	var user_id: String = ProjectSettings.get_setting("ziva/multiplayer/user_id", "")
	var game_id: String = ProjectSettings.get_setting("ziva/multiplayer/game_id", "")
	var relay_url: String = ProjectSettings.get_setting("ziva/multiplayer/relay_url", "")
	if user_id.is_empty() or game_id.is_empty() or relay_url.is_empty():
		push_error("Ziva multiplayer settings missing — ask Ziva to add multiplayer to this project.")
		connection_status.emit("Multijoueur non configuré")
		return
	var url: String = "%s/r/%s?u=%s&g=%s&v=1" % [relay_url, room_id, user_id, game_id]
	var peer: WebSocketMultiplayerPeer = WebSocketMultiplayerPeer.new()
	var err: Error = peer.create_client(url)
	if err != OK:
		connection_status.emit("Erreur de connexion (%d)" % err)
		return
	multiplayer.multiplayer_peer = peer
	_start_diag_ws(url)
	if _retry_count > 0:
		connection_status.emit("Connexion à la room « %s »… (essai %d)" % [room_id, _retry_count + 1])
	else:
		connection_status.emit("Connexion à la room « %s »…" % room_id)
	_start_connect_timeout()

## --- Événements réseau ---

## Quand un pair arrive, on lui envoie notre info de joueur.
func _on_player_connected(id: int) -> void:
	if id <= 1:
		return
	_register_player.rpc_id(id, player_info)

## Une fois connecté au relais : on s'ajoute au roster.
func _on_connected_ok() -> void:
	_stop_connect_timeout()
	_retry_count = 0
	my_id = multiplayer.get_unique_id()
	is_online = true
	players[my_id] = player_info
	base_origin = _compute_base(my_id)
	has_base = true
	base_ready.emit(base_origin)
	player_connected.emit(my_id, player_info)
	connection_status.emit("Connecté (peer %d), room « %s »" % [my_id, room_id])

@rpc("any_peer", "reliable")
func _register_player(info: Dictionary) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if info.has("name"):
		players[sender] = {"name": str(info["name"])}
	else:
		players[sender] = {"name": "Joueur %d" % sender}
	player_connected.emit(sender, players[sender])

func _on_player_disconnected(id: int) -> void:
	players.erase(id)
	player_disconnected.emit(id)

func _on_connected_fail() -> void:
	_stop_connect_timeout()
	var detail := _diag_peer()
	_remove_peer()
	if _retry_count < MAX_RETRIES:
		_retry_count += 1
		connection_status.emit("Échec de connexion%s — nouvel essai…" % detail)
		await get_tree().create_timer(2.0).timeout
		join_room(room_id)
	else:
		_retry_count = 0
		connection_status.emit("Échec de connexion au relais%s — hors ligne" % detail)
		_go_offline()

## Démarre un compte à rebours : si au bout de CONNECT_TIMEOUT la connexion
## n'est toujours pas établie, on la déclare en échec (le relais ne répond pas).
func _start_connect_timeout() -> void:
	_stop_connect_timeout()
	_connect_timer = get_tree().create_timer(CONNECT_TIMEOUT)
	_connect_timer.timeout.connect(_on_connect_timeout)

func _stop_connect_timeout() -> void:
	if _connect_timer != null:
		_connect_timer.timeout.disconnect(_on_connect_timeout)
		_connect_timer = null

func _on_connect_timeout() -> void:
	_connect_timer = null
	if not is_online:
		var peer := multiplayer.multiplayer_peer as WebSocketMultiplayerPeer
		var detail := ""
		if peer != null:
			detail = " (état relais %d)" % peer.get_connection_status()
		connection_status.emit("Le relais ne répond pas%s — hors ligne" % detail)
		_remove_peer()

## Extrait le détail du relais (état / code de fermeture) pour le diagnostic.
## Ouvre un WebSocket brut sur la même URL que le peer multijoueur pour
## diagnostiquer l'upgrade (le handshake est identique) sans entrer en conflit
## avec le protocole Godot. Le signal `closed` fournit code + raison propres.
func _start_diag_ws(url: String) -> void:
	_close_diag_ws()
	_diag_closed = false
	_diag_detail = ""
	_diag_ws = WebSocketPeer.new()
	_diag_ws.inbound_buffer_size = 65536
	_diag_ws.outbound_buffer_size = 65536
	var err: Error = _diag_ws.connect_to_url(url)
	if err != OK:
		_diag_detail = " (diag err %d)" % err
		push_warning("Diag relais : échec connect_to_url (%d)" % err)

func _close_diag_ws() -> void:
	if _diag_ws != null:
		_diag_ws.close()
		_diag_ws = null

func _process(_delta: float) -> void:
	if _diag_ws == null or _diag_closed:
		return
	_diag_ws.poll()
	if _diag_ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		_diag_closed = true
		var code := _diag_ws.get_close_code()
		var reason := _diag_ws.get_close_reason()
		_diag_detail = " (code fermeture %d)" % code
		if not reason.is_empty():
			_diag_detail += " : %s" % reason
		push_warning("Diag relais : WebSocket fermé%s" % _diag_detail)

## Retourne la chaîne de diagnostic (code/raison de fermeture) à afficher.
func _diag_peer() -> String:
	return _diag_detail

func _on_server_disconnected() -> void:
	connection_status.emit("Déconnecté du relais")
	_remove_peer()
	players.clear()
	server_disconnected.emit()

func _remove_peer() -> void:
	multiplayer.multiplayer_peer = null
	is_online = false
	_close_diag_ws()

## --- Chat ---

## Diffuse un message à tous les joueurs de la room (et l'affiche localement).
func send_chat(text: String) -> void:
	if not is_online or multiplayer.multiplayer_peer == null:
		return
	var clean := text.strip_edges()
	if clean.is_empty():
		return
	_send_chat.rpc(clean)

## RPC de chat : chaque pair l'affiche ("call_local" => l'expéditeur aussi).
@rpc("any_peer", "call_local", "reliable")
func _send_chat(text: String) -> void:
	var author := "Joueur"
	var sender: int = multiplayer.get_remote_sender_id()
	if sender <= 1 or sender == my_id:
		author = str(player_info.get("name", "Moi"))
	elif players.has(sender):
		author = str(players[sender].get("name", "Joueur %d" % sender))
	else:
		author = "Joueur %d" % sender
	chat_received.emit(author, text)

## --- Position de base ---

## Calcule la position de base d'un joueur à partir de son peer_id.
## Spirale de Fibonacci : chaque joueur est éloigné des autres sans chevauchement.
func _compute_base(id: int) -> Vector3:
	if id <= 1:
		return Vector3.ZERO
	var n := id - 1  # index 0-based de ce joueur
	var angle := float(n) * 2.399963229728653  # angle d'or (radians)
	var radius := minf(12.0 + float(n) * BASE_SPACING, WORLD_HALF - 10.0)
	var x := cos(angle) * radius
	var z := sin(angle) * radius
	return Vector3(x, 0.0, z)
