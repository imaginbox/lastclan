extends Node
## Clans — autoload de gestion des clans (alliances) en multijoueur.
##
## Modèle d'autorité (cohérent avec l'existant) :
##   - Le SERVEUR (peer 1, ou serveur dédié VPS) est l'autorité : il possède le
##     registre canonique `clans` et exécute les demandes (créer / rejoindre /
##     quitter / promouvoir).
##   - Un CLIENT envoie une RPC de demande ; le serveur applique puis diffuse le
##     registre complet à tous via `_broadcast_clans` (remplacement simple,
##     robuste, pas d'événement manquant).
##   - Chaque client garde une copie locale (lecture seule) et émet des signaux.
##
## Le clan est LE pivot de la saison : à la fin de la Saison 1, c'est le clan qui
## représentera le royaume en KvK. On stocke donc une « Grandeur » (prestige)
## commune, alimentée par l'activité des membres (voir jauge du royaume).

signal clans_updated          # le registre des clans a changé (côté serveur)
signal clans_received         # un registre complet est arrivé (côté client)
signal my_clan_changed        # mon appartenance a changé

## Rôles des membres.
enum Role { LEADER, OFFICER, MEMBER }

## Registre canonique (serveur) : tag -> {name, tag, color, leader, members:{peer:role}, grandeur}
var clans: Dictionary = {}

## Côté client : le tag de mon clan ("" si aucun).
var my_clan: String = ""

## Côté client : copie locale du registre (lecture seule).
var local_clans: Dictionary = {}

## Couleurs possibles pour le blason (choix à la création).
const COLORS: Array[Color] = [
	Color(0.85, 0.30, 0.30), Color(0.30, 0.55, 0.90), Color(0.30, 0.80, 0.40),
	Color(0.95, 0.75, 0.20), Color(0.80, 0.40, 0.85), Color(0.30, 0.85, 0.85),
]

# ============================================================ INTERFACE PUBLIQUE

## Créer un clan (appelé par le client). Le serveur crée, puis diffuse.
func create_clan(clan_name: String, tag: String, color_index: int) -> void:
	if my_clan != "":
		return
	if _is_server():
		_server_create_clan(clan_name, tag, color_index, _local_peer_id())
	else:
		_create_clan_rpc.rpc_id(1, clan_name, tag, color_index)

## Id du joueur local, fiable même hors réseau (tests / solo) : Lobby.my_id si
## connecté, sinon 1 (joueur local de référence).
func _local_peer_id() -> int:
	if Lobby != null and Lobby.is_online:
		return Lobby.my_id
	return 1

## Rejoindre un clan par tag (appelé par le client).
func join_clan(tag: String) -> void:
	if my_clan != "":
		return
	if _is_server():
		_server_join_clan(tag, _local_peer_id())
	else:
		_join_clan_rpc.rpc_id(1, tag)

## Quitter mon clan (appelé par le client).
func leave_clan() -> void:
	if my_clan == "":
		return
	if _is_server():
		_server_leave_clan(_local_peer_id())
	else:
		_leave_clan_rpc.rpc_id(1)

## Le joueur `target_peer` (de mon clan) demande à être promu. Réservé Leader.
func promote(leader_peer: int, target_peer: int) -> void:
	if _is_server():
		_server_promote(leader_peer, target_peer)

## Nom lisible de mon clan, sinon "".
func my_clan_name() -> String:
	if my_clan == "":
		return ""
	var c := _find(my_clan)
	if c.is_empty():
		return ""
	return str(c.get("name", my_clan))

## Ma couleur de clan (ou blanc si aucun).
func my_color() -> Color:
	if my_clan == "":
		return Color.WHITE
	var c := _find(my_clan)
	if c.is_empty():
		return Color.WHITE
	return c.get("color", Color.WHITE)

# ============================================================ ALLIANCES

## Le leader de mon clan propose une alliance au clan `tag`.
func propose_alliance(tag: String) -> void:
	if my_clan == "":
		return
	if _is_server():
		_server_propose_alliance(my_clan, tag.to_upper(), _local_peer_id())
	else:
		_propose_alliance_rpc.rpc_id(1, tag.to_upper())

## Le leader accepte une demande d'alliance en attente venant du clan `tag`.
func accept_alliance(tag: String) -> void:
	if my_clan == "":
		return
	if _is_server():
		_server_accept_alliance(my_clan, tag.to_upper(), _local_peer_id())
	else:
		_accept_alliance_rpc.rpc_id(1, tag.to_upper())

## Le leader refuse une demande d'alliance en attente venant du clan `tag`.
func decline_alliance(tag: String) -> void:
	if my_clan == "":
		return
	if _is_server():
		_server_decline_alliance(my_clan, tag.to_upper(), _local_peer_id())
	else:
		_decline_alliance_rpc.rpc_id(1, tag.to_upper())

## Le leader rompt l'alliance avec le clan `tag`.
func break_alliance(tag: String) -> void:
	if my_clan == "":
		return
	if _is_server():
		_server_break_alliance(my_clan, tag.to_upper(), _local_peer_id())
	else:
		_break_alliance_rpc.rpc_id(1, tag.to_upper())

## Les clans `a` et `b` sont-ils alliés (mutuel) ?
func are_allied(a: String, b: String) -> bool:
	var x := a.to_upper()
	var y := b.to_upper()
	var cl: Dictionary = clans if _is_server() else local_clans
	var c: Dictionary = cl.get(x, {})
	return (c.get("alliances", []) as Array).has(y)

## Mon clan est-il allié avec `tag` ?
func is_allied(tag: String) -> bool:
	return my_clan != "" and are_allied(my_clan, tag)

## Tags des clans alliés à mon clan.
func my_allies() -> Array:
	if my_clan == "":
		return []
	var cl: Dictionary = clans if _is_server() else local_clans
	var c: Dictionary = cl.get(my_clan, {})
	return (c.get("alliances", []) as Array).duplicate()

## Tags des demandes d'alliance en attente vers mon clan.
func my_pending() -> Array:
	if my_clan == "":
		return []
	var cl: Dictionary = clans if _is_server() else local_clans
	var c: Dictionary = cl.get(my_clan, {})
	return (c.get("pending", []) as Array).duplicate()

# ============================================================ SERVEUR (AUTORITÉ)

func _is_server() -> bool:
	# En ligne, le serveur (peer 1) est l'autorité. En SOLO (pas connecté, mode
	# NET_NONE), le joueur local est sa propre autorité pour tester la mécanique.
	if Lobby == null or not Lobby.is_online:
		return true
	return Lobby.net_mode == Lobby.NetMode.NET_HOST

## Le serveur reçoit + altère le registre puis le diffuse à tous.
func _server_create_clan(clan_name: String, tag: String, color_index: int, leader: int) -> void:
	var t := tag.to_upper().strip_edges()
	if t.is_empty() or t.length() > 6:
		return
	if clans.has(t):
		return
	var color: Color = COLORS[clampi(color_index, 0, COLORS.size() - 1)]
	clans[t] = {
		"name": clan_name.strip_edges(),
		"tag": t,
		"color": color,
		"leader": leader,
		"members": {str(leader): Role.LEADER},
		"grandeur": 0,
		"alliances": [],   # tags des clans alliés (mutuels, confirmés)
		"pending": [],     # tags des clans qui m'ont demandé une alliance
	}
	# Le leader quitte son éventuel ancien clan automatiquement.
	_remove_member_from_all(leader)
	clans[t]["members"][str(leader)] = Role.LEADER
	_broadcast()

func _server_join_clan(tag: String, peer: int) -> void:
	var t := tag.to_upper().strip_edges()
	if not clans.has(t):
		return
	_remove_member_from_all(peer)
	clans[t]["members"][str(peer)] = Role.MEMBER
	_broadcast()

func _server_leave_clan(peer: int) -> void:
	var removed := _remove_member_from_all(peer)
	# Si le leader part avec des membres, on transfère le leadership au 1er.
	for t in removed:
		if clans.has(t):
			var members: Dictionary = clans[t]["members"]
			if members.is_empty():
				clans.erase(t)
			elif clans[t]["leader"] == peer:
				var keys := members.keys()
				keys.sort()
				clans[t]["leader"] = int(keys[0])
				clans[t]["members"][keys[0]] = Role.LEADER
	_broadcast()

func _server_promote(leader_peer: int, target_peer: int) -> void:
	var t := _tag_of(leader_peer)
	if t == "":
		return
	if int(clans[t].get("leader", -1)) != leader_peer:
		return  # seul le Leader promeut
	if not clans[t]["members"].has(str(target_peer)):
		return
	clans[t]["members"][str(target_peer)] = Role.OFFICER
	_broadcast()

# ============================================================ ALLIANCES (SERVEUR)

## Seul le leader du clan `tag` peut faire de la diplomatie.
func _can_diplomacy(tag: String, peer: int) -> bool:
	if not clans.has(tag):
		return false
	return int(clans[tag].get("leader", -1)) == peer

func _server_propose_alliance(from_tag: String, to_tag: String, leader: int) -> void:
	if from_tag == to_tag:
		return
	if not clans.has(from_tag) or not clans.has(to_tag):
		return
	if not _can_diplomacy(from_tag, leader):
		return
	# Déjà alliés ou demande déjà en cours -> rien.
	if (clans[from_tag].get("alliances", []) as Array).has(to_tag):
		return
	var pending: Array = clans[to_tag].get("pending", [])
	if pending.has(from_tag):
		return
	pending.append(from_tag)
	clans[to_tag]["pending"] = pending
	_broadcast()

func _server_accept_alliance(me_tag: String, other_tag: String, leader: int) -> void:
	if not clans.has(me_tag) or not clans.has(other_tag):
		return
	if not _can_diplomacy(me_tag, leader):
		return
	var pending: Array = clans[me_tag].get("pending", [])
	if not pending.has(other_tag):
		return
	# Confirmation mutuelle.
	var a: Array = clans[me_tag].get("alliances", [])
	var b: Array = clans[other_tag].get("alliances", [])
	if not a.has(other_tag):
		a.append(other_tag)
	if not b.has(me_tag):
		b.append(me_tag)
	clans[me_tag]["alliances"] = a
	clans[other_tag]["alliances"] = b
	pending.erase(other_tag)
	clans[me_tag]["pending"] = pending
	var op: Array = clans[other_tag].get("pending", [])
	op.erase(me_tag)
	clans[other_tag]["pending"] = op
	_broadcast()

func _server_decline_alliance(me_tag: String, other_tag: String, leader: int) -> void:
	if not clans.has(me_tag):
		return
	if not _can_diplomacy(me_tag, leader):
		return
	var pending: Array = clans[me_tag].get("pending", [])
	pending.erase(other_tag)
	clans[me_tag]["pending"] = pending
	_broadcast()

func _server_break_alliance(me_tag: String, other_tag: String, leader: int) -> void:
	if not clans.has(me_tag) or not clans.has(other_tag):
		return
	if not _can_diplomacy(me_tag, leader):
		return
	var a: Array = clans[me_tag].get("alliances", [])
	var b: Array = clans[other_tag].get("alliances", [])
	a.erase(other_tag)
	b.erase(me_tag)
	clans[me_tag]["alliances"] = a
	clans[other_tag]["alliances"] = b
	_broadcast()

## Retire `peer` de tout clan. Renvoie la liste des tags modifiés.
func _remove_member_from_all(peer: int) -> Array:
	var touched: Array = []
	for t in clans.keys():
		if clans[t]["members"].has(str(peer)):
			clans[t]["members"].erase(str(peer))
			touched.append(t)
	return touched

func _tag_of(peer: int) -> String:
	for t in clans.keys():
		if clans[t]["members"].has(str(peer)):
			return t
	return ""

func _find(tag: String) -> Dictionary:
	return clans.get(tag.to_upper(), {}) if _is_server() else local_clans.get(tag.to_upper(), {})

func _broadcast() -> void:
	# En solo, pas de peer réseau : on applique localement (évite un RPC sans peer).
	if Lobby == null or not Lobby.is_online:
		local_clans = clans.duplicate(true)
		_apply_my_clan()
		clans_received.emit()
		return
	_broadcast_clans.rpc(clans)
	clans_updated.emit()

# ============================================================ RPC

@rpc("any_peer", "reliable")
func _create_clan_rpc(clan_name: String, tag: String, color_index: int) -> void:
	if not _is_server():
		return
	_server_create_clan(clan_name, tag, color_index, multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func _join_clan_rpc(tag: String) -> void:
	if not _is_server():
		return
	_server_join_clan(tag, multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func _leave_clan_rpc() -> void:
	if not _is_server():
		return
	_server_leave_clan(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func _propose_alliance_rpc(tag: String) -> void:
	if not _is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	_server_propose_alliance(_tag_of(sender), tag.to_upper(), sender)

@rpc("any_peer", "reliable")
func _accept_alliance_rpc(tag: String) -> void:
	if not _is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	_server_accept_alliance(_tag_of(sender), tag.to_upper(), sender)

@rpc("any_peer", "reliable")
func _decline_alliance_rpc(tag: String) -> void:
	if not _is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	_server_decline_alliance(_tag_of(sender), tag.to_upper(), sender)

@rpc("any_peer", "reliable")
func _break_alliance_rpc(tag: String) -> void:
	if not _is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	_server_break_alliance(_tag_of(sender), tag.to_upper(), sender)

## Le serveur diffuse le registre complet à tous (et à lui-même).
@rpc("any_peer", "call_local", "reliable")
func _broadcast_clans(registry: Dictionary) -> void:
	local_clans = registry.duplicate(true)
	_apply_my_clan()
	clans_received.emit()

## Recalcule `my_clan` à partir du registre reçu (recherche de mon peer id).
func _apply_my_clan() -> void:
	var id := str(_local_peer_id())
	my_clan = ""
	for t in local_clans.keys():
		if local_clans[t]["members"].has(id):
			my_clan = t
			break
	my_clan_changed.emit()

## Invoqué au démarrage réseau (server + clients) pour resync l'état.
func sync_from_server() -> void:
	if _is_server():
		_broadcast()
