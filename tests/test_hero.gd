extends Node
## Tests du module Héros :
##  - capacité de troupe (base + évolution HDV)
##  - assignation / désassignation d'unités
##  - bonus de commandement (option A : permanent, dépend du niveau héros + HDV)
##  - conversion paysan -> soldat (coût + population conservée)

var hero: Node = null

func _make_hero() -> Node:
	if hero != null:
		return hero
	hero = load("res://scripts/Hero.gd").new()
	add_child(hero)
	hero.level = 1
	hero.xp = 0
	return hero

func test_capacity_base() -> void:
	var h := _make_hero()
	h.level = 1
	# Hors arbre, pas d'HDV -> capacité = base.
	if h.call("troop_capacity") < Hero.BASE_TROOP_CAPACITY:
		push_error("CHECK FAILED: capacité < base (Hors arbre) : %d" % h.call("troop_capacity"))

func test_assign_unit() -> void:
	var h := _make_hero()
	h.call("unassign_all")
	# Simule un paysan.
	var v: Node = load("res://scripts/Villager.gd").new()
	add_child(v)
	var ok: bool = h.call("assign_unit", v)
	if not ok:
		push_error("CHECK FAILED: assign_unit a échoué")
	if not h.call("troop_has", v):
		push_error("CHECK FAILED: unité non dans la troupe")
	if h.call("troop_size") != 1:
		push_error("CHECK FAILED: troop_size != 1")
	h.call("unassign_unit", v)
	if h.call("troop_size") != 0:
		push_error("CHECK FAILED: désassignation inefficace")
	v.queue_free()

func test_command_bonus_scales_with_level() -> void:
	var h := _make_hero()
	h.level = 1
	h.profile = Hero.ProfileKind.COMMANDER
	var m1: float = h.call("command_attack_mult")
	h.level = 5
	var m5: float = h.call("command_attack_mult")
	if m5 <= m1:
		push_error("CHECK FAILED: bonus ne croît pas avec le niveau (%f -> %f)" % [m1, m5])

func test_command_bonus_registry_params() -> void:
	var gc: Node = load("res://scripts/GameConfig.gd").new()
	var reg: Array = gc.registry()
	var keys := [
		"hero.pv", "hero.degats", "hero.vitesse", "hero.capacite_base",
		"hero.bonus_par_niveau", "hero.bonus_hdv", "hero.convert_or", "hero.convert_bois",
	]
	var found: Array = []
	for p in reg:
		if String(p["key"]) in keys:
			found.append(String(p["key"]))
	for k in keys:
		if not found.has(k):
			push_error("CHECK FAILED: paramètre héros absent : %s" % k)
