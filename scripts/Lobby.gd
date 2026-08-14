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
## Le roster a changé (mode auto-hébergé natif : le serveur diffuse la liste
## complète des joueurs à tous les clients — ils ne se voient pas directement).
signal roster_changed

const WORLD_HALF: float = 190.0     # limite de placement des bases (mètres)
const BASE_SPAWN_MIN: float = 8.0    # rayon minimal : proche du centre
const BASE_SPAWN_MAX: float = 40.0   # rayon maximal : petite arène resserrée (marche ~20s entre bases opposées)
## Taille (octets) des buffers WebSocket du peer multijoueur. Le défaut (64 Ko) se
## sature vite sur les réseaux instables/à forte latence quand les RPC de synchro
## s'empilent plus vite que la TCP ne les évacue → « Buffer payload full ! Dropping
## data ». Un buffer large absorbe ces pics sans perdre d'état de jeu.
const WS_BUFFER_BYTES: int = 8 * 1024 * 1024  # 8 Mo

var is_online: bool = false
var my_id: int = 0
var base_origin: Vector3 = Vector3.ZERO
var has_base: bool = false

## Vrai quand cette instance tourne en tant que SERVEUR DÉDIÉ (--server).
## Contrairement à un simple client, il se connecte au relais et y RESTE en
## continu : reconnexion infinie, jamais « hors ligne », et sert de présence
## hôte permanente pour que les joueurs retrouvent toujours la partie en ligne.
var is_dedicated_server: bool = false

## MODE AUTO-HÉBERGÉ (sans Ziva) : quand cette instance est un VRAI SERVEUR
## (net_mode == NET_HOST), elle écoute sur un port ENet et accueille directement
## les clients (net_mode == NET_CLIENT) qui s'y connectent en peer à peer via
## le réseau (LAN ou VPS avec IP publique). Aucune dépendance à un relais.
enum NetMode { NET_NONE = 0, NET_HOST = 1, NET_CLIENT = 2 }
var net_mode: int = NetMode.NET_NONE
var net_port: int = 7934        # port du serveur (à ouvrir dans le firewall du VPS)
var net_address: String = ""    # IP/domaine du serveur pour un client

## Transport utilisé en mode auto-hébergé :
##   false = ENet (UDP) — client de bureau installé (recommandé desktop).
##   true  = WebSocket — client navigateur/WebGL (itch.io) ou mobile web,
##           car les navigateurs ne supportent PAS l'UDP brut.
var net_use_websocket: bool = false

## Chemins TLS (certificat + clé) pour le serveur WebSocket sécurisé (wss://).
## Obligatoire pour que les navigateurs (page HTTPS d'itch.io) acceptent la
## connexion, sinon le contenu mixte ws:// est bloqué.
var net_tls_cert: String = ""
var net_tls_key: String = ""

## Max de clients simultanés sur le serveur auto-hébergé.
const MAX_CLIENTS: int = 16

## Graine partagée du monde : dérivée du room_id de façon déterministe pour que
## TOUS les clients d'une même room génèrent exactement le même monde (mêmes
## ressources, mêmes décor). En mode hors ligne on utilise une graine fixe.
var world_seed: int = 1337

## Calcule la graine de monde à partir du room_id (identique pour tous les pairs
## connectés à la même room grâce à la fonction de hachage déterministe).
func _compute_world_seed() -> int:
	return abs(hash(room_id))

## Info locale du joueur, transmise à chaque pair. Le nom est rempli par l'UI.
var player_info: Dictionary = {"name": "Joueur"}

## Roster : peer_id -> {"name": ...}
var players: Dictionary = {}

## Nom de la room (partie) choisie.
var room_id: String = "global"

## Délai max (s) avant de déclarer la connexion en échec si elle reste en attente.
## Voir au-dessus : le relais Ziva est en ligne mais notre réseau instable fait
## parfois dépasser 8s au handshake WebSocket → on laisse une marge confortable
## pour éviter de déclarer « hors ligne » à tort.
const CONNECT_TIMEOUT: float = 15.0

var _connect_timer: SceneTreeTimer = null
var _retry_count: int = 0
const MAX_RETRIES: int = 3

## Socket brut de diagnostic : ouvert sur la même URL que le peer multijoueur,
## pour capturer le code/raison de fermeture WebSocket sans crasher.
var _diag_ws: WebSocketPeer = null
var _diag_closed: bool = false
var _diag_detail: String = ""

## Journal multijoueur fiable écrit dans un fichier local (le stdout est mis en
## tampon quand on lance plusieurs instances graphiques, ce fichier ne l'est pas).
## Un fichier PAR peer pour éviter tout écrasement entre instances.
func _mp_log(msg: String) -> void:
	var f := FileAccess.open("user://ziva_mp_%d.log" % my_id, FileAccess.WRITE)
	if f != null:
		f.store_line("[peer=%d] %s" % [my_id, msg])
		f.close()

func _ready() -> void:
	_prepare_args()
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# Mode AUTO-HÉBERGÉ natif : on est soit le serveur (écoute), soit un client
	# qui s'y connecte directement. Aucun relais Ziva impliqué.
	if net_mode == NetMode.NET_HOST:
		_start_host()
		return
	if net_mode == NetMode.NET_CLIENT:
		_start_client()
		return
	# Sinon : mode Ziva (relais) si serveur dédié, et hors ligne pour le solo.
	if is_dedicated_server:
		connection_status.emit("Serveur dédié : connexion à la room « %s »…" % room_id)
		join_room(room_id)
	elif _should_go_offline():
		_go_offline()

## Lit les arguments de ligne de commande (--room=<id>, --offline, --name=<nom>,
## --server). Détecte aussi le mode serveur dédié.
func _prepare_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--server":
			is_dedicated_server = true
			player_info["name"] = "Serveur"
		elif arg == "--host":
			# Mode AUTO-HÉBERGÉ : ce process EST le serveur (écoute un port ENet).
			net_mode = NetMode.NET_HOST
			net_use_websocket = false
			is_dedicated_server = true
			player_info["name"] = "Serveur"
		elif arg == "--ws-host":
			# Mode AUTO-HÉBERGÉ : serveur WebSocket (pour clients navigateur/itch.io).
			net_mode = NetMode.NET_HOST
			net_use_websocket = true
			is_dedicated_server = true
			player_info["name"] = "Serveur"
		elif arg.begins_with("--connect="):
			# Mode AUTO-HÉBERGÉ : ce process EST un client vers IP:PORT du serveur.
			net_mode = NetMode.NET_CLIENT
			net_use_websocket = false
			net_address = arg.trim_prefix("--connect=").strip_edges()
		elif arg.begins_with("--ws-connect="):
			# Mode AUTO-HÉBERGÉ : client WebSocket vers une URL ws:// ou wss://.
			net_mode = NetMode.NET_CLIENT
			net_use_websocket = true
			net_address = arg.trim_prefix("--ws-connect=").strip_edges()
		elif arg.begins_with("--tls-cert="):
			net_tls_cert = arg.trim_prefix("--tls-cert=")
		elif arg.begins_with("--tls-key="):
			net_tls_key = arg.trim_prefix("--tls-key=")
		elif arg.begins_with("--port="):
			net_port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--room="):
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
	world_seed = _compute_world_seed()
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
	peer.inbound_buffer_size = WS_BUFFER_BYTES
	peer.outbound_buffer_size = WS_BUFFER_BYTES
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

## --- Mode AUTO-HÉBERGÉ NATIF (sans Ziva) ---

## Démarre un VRAI SERVEUR qui écoute sur net_port et accueille directement les
## clients. Aucun relais : le serveur est peer 1, les clients seront peers 2+.
func _start_host() -> void:
	var peer: MultiplayerPeer
	var err: Error
	if net_use_websocket:
		# Serveur WebSocket (clients navigateur/mobile via itch.io).
		var ws := WebSocketMultiplayerPeer.new()
		ws.inbound_buffer_size = WS_BUFFER_BYTES
		ws.outbound_buffer_size = WS_BUFFER_BYTES
		var tls: TLSOptions = null
		if not net_tls_cert.is_empty() and not net_tls_key.is_empty():
			var key := CryptoKey.new()
			var cert := X509Certificate.new()
			if key.load(net_tls_key) == OK and cert.load(net_tls_cert) == OK:
				tls = TLSOptions.server(key, cert)
			else:
				push_warning("Impossible de charger les clés TLS — serveur en ws:// non sécurisé")
		err = ws.create_server(net_port, "*", tls)
		peer = ws
	else:
		# Serveur ENet (clients de bureau installés).
		var enet := ENetMultiplayerPeer.new()
		err = enet.create_server(net_port, MAX_CLIENTS)
		peer = enet
	if err != OK:
		connection_status.emit("Impossible de démarrer le serveur (port %d, code %d)" % [net_port, err])
		_mp_log("HOST_FAIL port=%d err=%d" % [net_port, err])
		_go_offline()
		return
	multiplayer.multiplayer_peer = peer
	my_id = 1
	is_online = true
	players.clear()
	players[1] = player_info
	world_seed = _compute_world_seed()
	base_origin = Vector3.ZERO
	has_base = true
	base_ready.emit(base_origin)
	player_connected.emit(1, player_info)
	var scheme := "ws" if net_use_websocket else "enet"
	_mp_log("HOST peer=%d port=%d world_seed=%d transport=%s" % [my_id, net_port, world_seed, scheme])
	connection_status.emit("Serveur démarré sur le port %d (%s, auto-hébergé, sans Ziva)" % [net_port, scheme])

## Se connecte en CLIENT au serveur auto-hébergé (adresse IP/domaine:port).
func _start_client() -> void:
	var peer: MultiplayerPeer
	var err: Error
	if net_use_websocket:
		# Client WebSocket (navigateur/itch.io/mobile web). net_address est une URL
		# ws:// ou wss:// complète (ex: wss://mondomaine.fr:7934).
		var ws := WebSocketMultiplayerPeer.new()
		ws.inbound_buffer_size = WS_BUFFER_BYTES
		ws.outbound_buffer_size = WS_BUFFER_BYTES
		err = ws.create_client(net_address)
		peer = ws
	else:
		# Client ENet (bureau installé). net_address = "ip[:port]".
		var enet := ENetMultiplayerPeer.new()
		var host := net_address
		var port := net_port
		if host.contains(":"):
			var parts := host.rsplit(":", true, 1)
			host = parts[0]
			port = int(parts[1])
		err = enet.create_client(host, port)
		peer = enet
	if err != OK:
		connection_status.emit("Impossible de se connecter à %s (code %d)" % [net_address, err])
		_mp_log("CLIENT_FAIL addr=%s err=%d" % [net_address, err])
		_go_offline()
		return
	multiplayer.multiplayer_peer = peer
	_mp_log("CLIENT connect addr=%s transport=%s" % [net_address, "ws" if net_use_websocket else "enet"])
	connection_status.emit("Connexion au serveur %s…" % net_address)
	_start_connect_timeout()

## Se connecte à un serveur de la liste (modèle « royaumes » à la Call of Dragons).
## transport : "enet" (desktop) ou "ws" (navigateur/itch.io/mobile).
## address   : "ip:port" pour enet, "ws://…" / "wss://…" pour ws.
## room      : room_id du royaume (facultatif) — aligne le monde du client sur la
##             saison du royaume. Le serveur re-confirmera via _sync_room.
func join_server(transport: String, address: String, room: String = "") -> void:
	disconnect_from()
	net_mode = NetMode.NET_CLIENT
	net_use_websocket = (transport == "ws")
	if not room.is_empty():
		room_id = room
	var clean := address.strip_edges()
	if net_use_websocket:
		net_address = clean
		# L'URL ws:// ou wss:// porte déjà le port.
	else:
		# Pour enet, l'adresse "ip[:port]" — net_port est déduit de l'adresse.
		net_address = clean
	_start_client()

## --- Événements réseau ---

## Quand un pair arrive, on lui envoie notre info de joueur.
func _on_player_connected(id: int) -> void:
	if id <= 1:
		return
	_register_player.rpc_id(id, player_info)
	# Mode auto-hébergé natif : le SERVEUR (peer 1) voit chaque client arriver et
	# diffuse le roster complet à tous, pour que chaque client découvre les autres.
	if net_mode == NetMode.NET_HOST:
		players[id] = {"name": "Joueur %d" % id}
		_mp_log("JOIN peer=%d (serveur auto-hébergé) room=%s" % [id, room_id])
		# Chaque royaume (room) a sa propre saison/monde. On transmet notre room_id
		# au client pour qu'il génère exactement le même monde déterministe.
		_sync_room.rpc_id(id, room_id)
		_broadcast_roster.rpc(players)

## Reçoit le room_id du serveur (pour que le monde soit cohérent avec le royaume).
@rpc("any_peer", "reliable")
func _sync_room(room: String) -> void:
	room_id = room
	world_seed = _compute_world_seed()
	# Recalcule la base pour ce monde (le client garde sa position en anneau).
	base_origin = _compute_base(my_id)
	has_base = true
	base_ready.emit(base_origin)
	_mp_log("SYNC_ROOM room=%s world_seed=%d base=%.1f,%.1f,%.1f" % [room_id, world_seed, base_origin.x, base_origin.y, base_origin.z])

## Une fois connecté au relais : on s'ajoute au roster.
func _on_connected_ok() -> void:
	_stop_connect_timeout()
	_retry_count = 0
	my_id = multiplayer.get_unique_id()
	is_online = true
	players[my_id] = player_info
	world_seed = _compute_world_seed()
	base_origin = _compute_base(my_id)
	_mp_log("CONNECT peer=%d room=%s world_seed=%d base=%.1f,%.1f,%.1f" % [my_id, room_id, world_seed, base_origin.x, base_origin.y, base_origin.z])
	has_base = true
	base_ready.emit(base_origin)
	# Mode client natif : on demande la liste des autres joueurs au serveur.
	if net_mode == NetMode.NET_CLIENT:
		_request_roster()
	player_connected.emit(my_id, player_info)
	var mode_label := "client" if net_mode == NetMode.NET_CLIENT else "room « %s »" % room_id
	connection_status.emit("Connecté (peer %d), %s" % [my_id, mode_label])

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
	# Mode natif : le serveur retire le client et rediffuse le roster restant.
	if net_mode == NetMode.NET_HOST:
		_mp_log("LEAVE peer=%d (serveur auto-hébergé)" % id)
		_broadcast_roster.rpc(players)

## Diffuse le roster complet. Appelé avec .rpc() par le serveur (peer 1) ; les
## clients le reçoivent et remplacent leur liste locale. "any_peer" + garde pour
## n'accepter le roster que depuis le serveur.
@rpc("any_peer", "call_local", "reliable")
func _broadcast_roster(roster: Dictionary) -> void:
	# Seul le serveur (peer 1) peut diffuser le roster. En local (serveur), le
	# sender est 0 ; sur un client, il doit être 1.
	var sender: int = multiplayer.get_remote_sender_id()
	if net_mode == NetMode.NET_CLIENT and sender != 1:
		return
	players = roster.duplicate()
	if net_mode == NetMode.NET_CLIENT:
		# Le client se garde toujours lui-même (ne dépend pas du roster serveur).
		players[my_id] = player_info
	roster_changed.emit()

## Le client natif demande le roster au serveur juste après sa connexion
## (il a pu rater la diffusion du serveur pendant son arrivée).
func _request_roster() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	_request_roster_rpc.rpc_id(1)

@rpc("any_peer", "reliable")
func _request_roster_rpc() -> void:
	if net_mode != NetMode.NET_HOST:
		return
	_broadcast_roster.rpc(players)

func _on_connected_fail() -> void:
	_stop_connect_timeout()
	var detail := _diag_peer()
	_remove_peer()
	# Le relais Ziva est en ligne, mais notre réseau local instable peut faire
	# échouer UNE tentative (WebSocket fermée avant le handshake). On ne déclare
	# JAMAIS « hors ligne » : on retente indéfiniment avec un délai croissant
	# plafonné, jusqu'à ce que la connexion s'établisse.
	var delay := _retry_delay()
	connection_status.emit("Connexion instable%s — nouvel essai dans %.0fs…" % [detail, delay])
	await get_tree().create_timer(delay).timeout
	join_room(room_id)

## Délai d'attente avant le prochain essai de reconnexion : croissant (2s, 3s,
## 4s…) puis plafonné à 6s pour ne pas marteler le relais en continu.
func _retry_delay() -> float:
	_retry_count += 1
	return clampf(1.0 + float(_retry_count), 2.0, 6.0)

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
		# Le relais ne répond pas (réseau instable) : on retente indéfiniment avec
		# un délai croissant plafonné, jamais « hors ligne ».
		_remove_peer()
		var delay := _retry_delay()
		connection_status.emit("Le relais ne répond pas%s — nouvel essai dans %.0fs…" % [detail, delay])
		await get_tree().create_timer(delay).timeout
		join_room(room_id)

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
	# Serveur dédié : à la moindre déconnexion, on se reconnecte en continu.
	if is_dedicated_server:
		print("[SERVEUR] déconnecté du relais — reconnexion dans 3s…")
		connection_status.emit("Serveur : déconnecté — reconnexion dans 3s…")
		await get_tree().create_timer(3.0).timeout
		join_room(room_id)
	server_disconnected.emit()

func _remove_peer() -> void:
	multiplayer.multiplayer_peer = null
	is_online = false
	_close_diag_ws()

## Déconnecte proprement le peer actuel (si connecté) avant d'en établir un neuf.
## Sert à passer d'un serveur à un autre sans état résiduel.
func disconnect_from() -> void:
	_remove_peer()
	_stop_connect_timeout()
	players.clear()
	has_base = false

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

## Calcule la position de base d'un joueur.
## Placement ALÉATOIRE dans une PETITE ARÈNE centrale : la zone de spawn est
## volontairement resserrée (rayon 14 à 65 m) pour que les joueurs puissent se
## trouver, collaborer et se faire la guerre. Vastes étendues loin du centre
## servent de marge de manœuvre, sans éloigner les bases les unes des autres.
func _compute_base(_id: int) -> Vector3:
	if _id <= 1:
		return Vector3.ZERO
	var angle := randf() * TAU
	var radius := randf_range(BASE_SPAWN_MIN, BASE_SPAWN_MAX)
	var x := cos(angle) * radius
	var z := sin(angle) * radius
	return Vector3(x, 0.0, z)
