extends Node
## Realm — autoload « Sort du Royaume ».
##
## Matérialise la vision : **les joueurs décident du sort de leur serveur**.
## Une jauge globale [0..100] traduit la santé du royaume, pilotée par l'activité
## collective. Chaque action positive (produire, récolter, construire, être
## actif) fait monter ; l'inaction/le déclin la fait redescendre.
##
## Modèle :
##   - Le score est un accumulateur : activity() ajoute, tick régulier draine.
##   - Le serveur reste l'autorité et diffuse la valeur (cohérent avec l'existant).
##   - Chaque client affiche la jauge (HUD) et reçoit les seuils (événements).
##
## Seuils → événements positifs quand la jauge est haute :
##   >= 66 : "prospérité"  → bonus de récolte du royaume (game feel).
##   >= 33 : "stable"      → normal.
##    < 33 : "déclin"      → les joueurs doivent réagir (coopérer / construire).

signal realm_changed(value: float, zone: String)

const SETTLE_RATE := 0.5        # fonte par seconde (re-statique si rien ne bouge)
const MAX := 100.0

## Valeur actuelle (0..100).
var value: float = 40.0

## Zone associée ("prosperity" / "stable" / "decline").
func zone() -> String:
	if value >= 66.0:
		return "prosperity"
	if value >= 33.0:
		return "stable"
	return "decline"

## Bonus de récolte (%) appliqué à tout le royaume selon la prospérité.
## En prospérité : +25% de rendement (récompense la coopération).
## En déclin : -15% (pénalise l'écosystème dégradé).
func harvest_bonus() -> float:
	match zone():
		"prosperity":
			return 1.25
		"decline":
			return 0.85
	return 1.0

## Activité collective positive : chaque événement significatif fait monter.
## `amount` : poids de l'événement (récolte=petit, construction=grand, etc.)
func activity(amount: float) -> void:
	value = clampf(value + amount, 0.0, MAX)
	realm_changed.emit(value, zone())

## Drain progressif pour que la jauge redescende si le royaume stagne.
func tick(delta: float) -> void:
	if value > 0.0:
		value = maxf(value - SETTLE_RATE * delta, 0.0)
		realm_changed.emit(value, zone())

## Applique la valeur reçue du serveur (sync réseau).
func apply_server_value(v: float) -> void:
	value = clampf(v, 0.0, MAX)
	realm_changed.emit(value, zone())

func _process(delta: float) -> void:
	# En ligne, SEUL le serveur draine et diffuse ; les clients reçoivent la
	# valeur par le réseau (pas de divergence locale). Hors ligne (solo), on
	# draine localement pour la démo.
	var is_client_online: bool = Lobby != null and Lobby.is_online and Lobby.net_mode == Lobby.NetMode.NET_CLIENT
	if is_client_online:
		return
	tick(delta)
