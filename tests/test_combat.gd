extends Node
## Test du combat de base (santé + mort) ajouté aux unités pour le PvP.

func test_villager_health() -> void:
	var v: Node = load("res://scenes/Villager.tscn").instantiate()
	add_child(v)
	await get_tree().process_frame
	var hp: int = v.get("hp")
	if hp <= 0:
		push_error("CHECK FAILED: paysan sans points de vie")
	v.call("take_damage", hp)
	# Après les dégâts fatals, l'unité doit être marquée (queue_free) peu après.
	var dead: bool = v.is_queued_for_deletion()
	if not dead:
		push_error("CHECK FAILED: le paysan n'est pas mort après dégâts fatals")
	v.queue_free()

func test_soldier_health() -> void:
	var s: Node = load("res://scenes/Soldier.tscn").instantiate()
	add_child(s)
	await get_tree().process_frame
	var hp: int = s.get("hp")
	var max_hp: int = s.get("max_hp")
	if hp <= 0 or max_hp <= 0:
		push_error("CHECK FAILED: soldat sans points de vie")
	s.call("take_damage", 1)
	if s.get("hp") != hp - 1:
		push_error("CHECK FAILED: dégâts non appliqués au soldat")
	s.queue_free()
