extends Node
## Test Phase 1 : vérifie que ResourceManager, ResourceNode et Villager
## fonctionnent ensemble (récolte -> dépôt -> ressource).

func test_resource_manager() -> void:
	var rm := get_node("/root/ResourceManager")
	rm.gold = 100
	rm.wood = 50
	rm.add_gold(25)
	rm.add_wood(10)
	if rm.gold != 125 or rm.wood != 60:
		push_error("CHECK FAILED: add_gold/add_wood")
	if not rm.spend(30, 20) or rm.gold != 95 or rm.wood != 40:
		push_error("CHECK FAILED: spend ok")
	if rm.spend(999, 1) or rm.gold != 95 or rm.wood != 40:
		push_error("CHECK FAILED: spend insuffisant ne débite pas")

func test_resource_node() -> void:
	var rn: ResourceNode = load("res://scenes/ResourceNode.tscn").instantiate()
	add_child(rn)
	rn.set("resource_type", ResourceNode.ResourceType.GOLD)
	rn.set("max_amount", 100)
	rn.set("starting_amount", 100)
	# Force _ready
	await get_tree().process_frame
	if not rn.has_left():
		push_error("CHECK FAILED: ressource vide au départ")
	var taken: int = rn.harvest(10)
	if taken != 10 or rn.amount != 90:
		push_error("CHECK FAILED: harvest")
	# Vider complètement.
	var collected: int = 0
	while rn.has_left():
		collected += rn.harvest(10)
	if collected != 90:
		push_error("CHECK FAILED: total collecté")
	if rn.has_left():
		push_error("CHECK FAILED: ressource pas épuisée")
	rn.queue_free()

func test_villager_gather() -> void:
	var rm := get_node("/root/ResourceManager")
	rm.gold = 0
	rm.wood = 0
	var villager: Node = load("res://scenes/Villager.tscn").instantiate()
	add_child(villager)
	var rn: ResourceNode = load("res://scenes/ResourceNode.tscn").instantiate()
	add_child(rn)
	rn.set("resource_type", ResourceNode.ResourceType.GOLD)
	rn.set("starting_amount", 50)
	rn.set("max_amount", 50)
	rn.global_position = villager.global_position + Vector3(3, 0, 0)
	await get_tree().process_frame
	villager.call("send_to_gather", rn)
	# Attendre genre ~3.5s (2s de récolte + trajet).
	await get_tree().create_timer(4.0).timeout
	if rm.gold <= 0:
		push_error("CHECK FAILED: pas d'or récolté, gold=", rm.gold)
	rn.queue_free()
	villager.queue_free()
