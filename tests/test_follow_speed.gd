extends Node
## Test du rappel de formation : quand une unité suit le héros (_following_hero),
## elle doit courir plus vite (command_follow_speed_mult = 1.5x) que sa vitesse de
## commandement normale, pour pouvoir rester autour du héros pendant le déplacement.
## Les unités ne sont PAS ajoutées à l'arbre : on teste la logique pure (pas de _ready).

func test_follow_speed_mult_is_higher_than_command() -> void:
	var hero: Node = load("res://scenes/Hero.tscn").instantiate()
	var follow: float = hero.call("command_follow_speed_mult")
	var normal: float = hero.call("command_speed_mult")
	if follow <= normal:
		push_error("CHECK FAILED: command_follow_speed_mult (%.2f) doit être > command_speed_mult (%.2f)" % [follow, normal])
	if follow <= 1.0:
		push_error("CHECK FAILED: command_follow_speed_mult doit être > 1.0 (accélération), obtenu %.2f" % follow)
	hero.free()

func test_soldier_speed_uses_follow_when_recalled() -> void:
	var hero: Node = load("res://scenes/Hero.tscn").instantiate()
	var soldier: Node = load("res://scenes/Soldier.tscn").instantiate()
	soldier.set("command_hero", hero)
	# Pendant le rappel : l'unité court à la vitesse de suivi accélérée.
	soldier.set("_following_hero", true)
	var follow_speed: float = soldier.call("_speed_mult")
	if not is_equal_approx(follow_speed, hero.call("command_follow_speed_mult")):
		push_error("CHECK FAILED: vitesse pendant rappel (%.2f) != follow_mult (%.2f)" % [follow_speed, hero.call("command_follow_speed_mult")])
	# Après arrivée / attaque : _following_hero=false -> vitesse de commandement normale.
	soldier.set("_following_hero", false)
	var normal_speed: float = soldier.call("_speed_mult")
	if not is_equal_approx(normal_speed, hero.call("command_speed_mult")):
		push_error("CHECK FAILED: vitesse hors rappel (%.2f) != command_mult (%.2f)" % [normal_speed, hero.call("command_speed_mult")])
	if normal_speed >= follow_speed:
		push_error("CHECK FAILED: la vitesse normale ne doit pas dépasser la vitesse de suivi")
	soldier.free()
	hero.free()

func test_villager_speed_uses_follow_when_recalled() -> void:
	var hero: Node = load("res://scenes/Hero.tscn").instantiate()
	var villager: Node = load("res://scenes/Villager.tscn").instantiate()
	villager.set("command_hero", hero)
	villager.set("_following_hero", true)
	var follow_speed: float = villager.call("_speed_mult")
	if not is_equal_approx(follow_speed, hero.call("command_follow_speed_mult")):
		push_error("CHECK FAILED: paysan en rappel vitesse (%.2f) != follow_mult (%.2f)" % [follow_speed, hero.call("command_follow_speed_mult")])
	villager.set("_following_hero", false)
	var normal_speed: float = villager.call("_speed_mult")
	if not is_equal_approx(normal_speed, hero.call("command_speed_mult")):
		push_error("CHECK FAILED: paysan hors rappel vitesse (%.2f) != command_mult (%.2f)" % [normal_speed, hero.call("command_speed_mult")])
	villager.free()
	hero.free()

func test_follow_speed_guarantees_catch_up_to_hero() -> void:
	# La troupe doit courir plus vite que le héros pendant le rappel (x1.2), même
	# si la vitesse de base de l'unité est faible -> la troupe rattrape le héros.
	var hero: Node = load("res://scenes/Hero.tscn").instantiate()
	var hero_speed: float = hero.call("_move_speed")
	var soldier: Node = load("res://scenes/Soldier.tscn").instantiate()
	soldier.set("command_hero", hero)
	soldier.set("_following_hero", true)
	var soldier_follow: float = soldier.call("_move_speed")
	if soldier_follow <= hero_speed:
		push_error("CHECK FAILED: soldat en rappel (%.2f) doit dépasser le héros (%.2f) pour le rattraper" % [soldier_follow, hero_speed])
	var villager: Node = load("res://scenes/Villager.tscn").instantiate()
	villager.set("command_hero", hero)
	villager.set("_following_hero", true)
	var villager_follow: float = villager.call("_move_speed")
	if villager_follow <= hero_speed:
		push_error("CHECK FAILED: paysan en rappel (%.2f) doit dépasser le héros (%.2f) pour le rattraper" % [villager_follow, hero_speed])
	soldier.free()
	villager.free()
	hero.free()

func test_soldier_has_hdist_for_reaiming() -> void:
	# CAUSE RACINE : sans _hdist, le héros ne ré-aiguille jamais les soldats dans
	# son _physics_process (il filtre via has_method("_hdist")) -> les soldats
	# restaient à la traîne. Ce test protège contre la régression.
	var s: Node = load("res://scripts/Soldier.gd").new()
	if not s.has_method("_hdist"):
		push_error("CHECK FAILED: Soldier doit avoir _hdist pour être ré-aimé en continu par le héros")

func test_unassigned_unit_has_no_command_speed() -> void:
	var soldier: Node = load("res://scenes/Soldier.tscn").instantiate()
	# Unité libre (pas de command_hero) : multiplicateur = 1.0, même en rappel.
	soldier.set("_following_hero", true)
	var speed: float = soldier.call("_speed_mult")
	if not is_equal_approx(speed, 1.0):
		push_error("CHECK FAILED: unité libre doit avoir _speed_mult=1.0, obtenu %.2f" % speed)
	soldier.free()
