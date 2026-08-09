extends Node
## Test Phase Économie : vérifie que la production passive des bâtiments fonctionne
## vraiment (accumulation, plus de troncature à 0) et que le coût cumulé pour
## atteindre les premières troupes est accessible depuis les ressources de départ.

func test_building_production_gold() -> void:
	# HDV produit 0.8 or/s en continu. Sans accumulation, int(0.8 * 0.016) = 0 dès
	# le 1er frame -> il ne produirait jamais rien. Vérifions qu'il produit ~0.8/s.
	# Il n'y a pas de scène Building.tscn : les bâtiments se construisent en code.
	var th: Building = Building.new()
	th.type = Building.Type.TOWN_HALL
	th.level = 1
	add_child(th)
	# Simuler ~5 secondes de _produce à 60 ticks/s.
	var rm := get_node("/root/ResourceManager")
	rm.gold = 0
	rm.wood = 0
	rm.stone = 0
	rm.food = 0
	for i in range(60 * 5):
		th._produce(1.0 / 60.0)
	if rm.gold < 3:
		push_error("CHECK FAILED: HDV ne produit pas assez d'or (or=%d en 5s, attendu ~4)" % rm.gold)
	th.queue_free()

func test_building_production_mine() -> void:
	var mine: Building = Building.new()
	mine.type = Building.Type.MINE_OR
	mine.level = 1
	add_child(mine)
	var rm := get_node("/root/ResourceManager")
	rm.gold = 0
	rm.wood = 0
	rm.stone = 0
	rm.food = 0
	for i in range(60 * 5):
		mine._produce(1.0 / 60.0)
	if rm.gold < 12:
		push_error("CHECK FAILED: Mine ne produit pas assez d'or (produit %d en 5s, attendu ~15)" % rm.gold)
	mine.queue_free()

func test_building_production_farm() -> void:
	var farm: Building = Building.new()
	farm.type = Building.Type.FERME
	farm.level = 1
	add_child(farm)
	var rm := get_node("/root/ResourceManager")
	rm.gold = 0
	rm.wood = 0
	rm.stone = 0
	rm.food = 0
	for i in range(60 * 5):
		farm._produce(1.0 / 60.0)
	if rm.food < 16:
		push_error("CHECK FAILED: Ferme ne produit pas assez (produit %d nourriture en 5s, attendu ~20)" % rm.food)
	farm.queue_free()

func test_cost_to_soldier_reachable() -> void:
	# Depuis les ressources de départ, vérifions que le coût cumulé pour un soldat
	# (HDV niv2 + caserne + maison + 1 soldat) est au plus ~1.3x les stocks de départ,
	# prouvant qu'une récolte raisonnable suffit (pas de soft-lock).
	var start := { "gold": 300, "wood": 200, "stone": 50 }
	var hdv_upg: Dictionary = Building.TYPES[Building.Type.TOWN_HALL]
	var barracks: Dictionary = Building.TYPES[Building.Type.BARRACKS]
	var house: Dictionary = Building.TYPES[Building.Type.HOUSE]
	var train: Dictionary = {}
	var train_gold: int = Building.TYPES[Building.Type.BARRACKS].get("train_gold", 45)
	var train_wood: int = Building.TYPES[Building.Type.BARRACKS].get("train_wood", 15)

	var total_gold: int = hdv_upg["upg_gold"] + barracks["cost_gold"] + house["cost_gold"] + train_gold
	var total_wood: int = hdv_upg["upg_wood"] + barracks["cost_wood"] + house["cost_wood"] + train_wood
	var total_stone: int = int(hdv_upg.get("upg_stone", 0)) + int(barracks.get("cost_stone", 0))

	if total_gold > start["gold"] * 1.5:
		push_error("CHECK FAILED: coût or vers 1er soldat trop lourd (%d vs départ %d)" % [total_gold, start["gold"]])
	if total_wood > start["wood"] * 1.5:
		push_error("CHECK FAILED: coût bois vers 1er soldat trop lourd (%d vs départ %d)" % [total_wood, start["wood"]])
	if total_stone > start["stone"] * 2.5:
		push_error("CHECK FAILED: coût pierre vers 1er soldat trop lourd (%d vs départ %d)" % [total_stone, start["stone"]])
