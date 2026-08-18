extends StaticBody3D
class_name EnemyOutpost
## Avant-poste ennemi : le cœur d'une base rivale à piller. Une fois détruit,
## il rapporte un gros butin. Il est dans le groupe "enemy" : toute unité peut
## l'attaquer (clic droit / A-Move) comme une créature.

signal died(outpost: Node)

var hp: float = 300.0
var max_hp: float = 300.0
var last_damage_ms: int = -100000
var _dead: bool = false

func is_dead() -> bool:
	return _dead or hp <= 0.0

## Butin versé à la destruction (or / pierre / nourriture). Montants variables
## pour rendre chaque raid un peu différent et plus gratifiant.
func loot() -> Array:
	return [
		["gold", randi_range(50, 70)],
		["stone", randi_range(35, 55)],
		["food", randi_range(20, 40)],
	]

## Reçoit les dégâts des unités du joueur (même signature que les créatures).
func take_damage(amount: int, _attacker_pos: Vector3 = Vector3.ZERO) -> void:
	if _dead:
		return
	hp -= float(amount)
	last_damage_ms = Time.get_ticks_msec()
	if hp <= 0.0:
		hp = 0.0
		_die()

## Liste des caractéristiques affichées dans l'inspecteur (clic sur l'avant-poste).
func characteristics() -> Array:
	return [
		["Rôle", "Avant-poste ennemi (à piller)"],
		["Vie (endurance)", "%d / %d" % [int(hp), int(max_hp)]],
		["Butin (à la destruction)", "or 50-70 · pierre 35-55 · nourriture 20-40"],
	]

func _die() -> void:
	_dead = true
	died.emit(self)
	queue_free()
