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

## Horodatage (ms) de la dernière fois que cette unité distante a été frappée
## par NOS unités. Sert à maintenir la barre de vie visible pendant le combat et
## à la faire disparaître dès qu'il n'y a plus d'attaques.
var last_damage_ms: int = -100000

func _ready() -> void:
	add_to_group("enemy")

## Reçoit des dégâts d'un attaquant local. Relaie au propriétaire réel, qui
## applique les dégâts sur sa propre unité et diffuse l'état (via la synchro).
## Affiche aussi un nombre « -X » chez l'ATTAQUANT pour confirmer les dégâts.
## `attacker_pos` = position de la cible frappée (pour la défense auto du côté
## du propriétaire : le défenseur réagit et se défend ou fuit dans la bonne
## direction).
func take_damage(amount: int, attacker_pos: Vector3 = Vector3.ZERO) -> void:
	last_damage_ms = Time.get_ticks_msec()
	if relay != null and is_instance_valid(relay):
		relay.request_unit_damage(owner_peer, unit_index, amount, attacker_pos)
		relay.call("show_damage_float", global_position, amount)

## Position courante (utile aux attaquants pour le suivi de cible).
func current_pos() -> Vector3:
	return global_position
