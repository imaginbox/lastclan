class_name RemoteUnit
extends Node3D
## Représentation distante d'une unité appartenant à un autre joueur.
## Simple visuel (capsule) : les dégâts reçus sont relayés au propriétaire réel
## via un RPC, qui applique les dégâts sur sa propre unité (modèle d'autorité
## "chaque pair possède ses unités", cohérent avec le relais sans serveur).

## peer_id du propriétaire réel de cette unité.
var owner_peer: int = 0
## index de l'unité dans la liste des unités locales du propriétaire
## (utilsé pour la cibler via RPC ; synchro par index).
var unit_index: int = 0
## référence vers le script main (définit l'autorité de l'attaque).
var relay: Node = null

const ATTACK_RANGE: float = 2.0

func _ready() -> void:
	add_to_group("enemy")

## Reçoit des dégâts d'un attaquant local. Relaie au propriétaire réel, qui
## applique les dégâts sur sa propre unité et diffuse l'état (via la synchro).
func take_damage(amount: int) -> void:
	if relay != null and is_instance_valid(relay):
		relay.request_unit_damage(owner_peer, unit_index, amount)

## Position courante (utile aux attaquants pour le suivi de cible).
func current_pos() -> Vector3:
	return global_position
