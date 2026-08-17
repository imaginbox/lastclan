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

## Butin versé à la destruction (or / pierre / nourriture).
func loot() -> Array:
	return [["gold", 60], ["stone", 45], ["food", 30]]

## Reçoit les dégâts des unités du joueur (même signature que les créatures).
func take_damage(amount: int, _attacker_pos: Vector3 = Vector3.ZERO) -> void:
	if _dead:
		return
	hp -= float(amount)
	last_damage_ms = Time.get_ticks_msec()
	if hp <= 0.0:
		hp = 0.0
		_die()

func _die() -> void:
	_dead = true
	died.emit(self)
	queue_free()
