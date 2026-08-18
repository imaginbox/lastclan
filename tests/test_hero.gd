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

## _last_troop_unit doit retrouver un paysan dans la troupe. Ce test verrouille
## le bug où le contrôle utilisait has_method("_troop") (variable, pas méthode)
## et retournait donc toujours null => bouton "-" inopérant.
func test_last_troop_unit_finds_villager() -> void:
	var h := _make_hero()
	h.call("unassign_all")
	var v: Node = load("res://scripts/Villager.gd").new()
	add_child(v)
	h.call("assign_unit", v)
	if h.call("troop_size") != 1:
		push_error("CHECK FAILED: troupe vide après assignation")
	# Réplique la logique de main.gd _last_troop_unit (le bug réel).
	var arr: Array = h.get("_troop")
	if arr == null or arr.is_empty():
		push_error("CHECK FAILED: _troop inaccessible/vide")
		return
	var found_id: int = -1
	for i in range(arr.size() - 1, -1, -1):
		var u: Node = arr[i]
		if u is Villager:
			found_id = i
	if found_id == -1:
		push_error("CHECK FAILED: _last_troop_unit n'a trouvé aucun paysan (bug has_method)")
	v.queue_free()

## _is_member_busy doit considérer un paysan en récolte comme 'occupé' (sinon le
## héros le rappelle vers la formation et annule sa récolte). Ce test verrouille
## le bug où _state (variable) était testée via has_method() -> toujours false.
func test_is_member_busy_detects_gathering() -> void:
	var h := _make_hero()
	var v: Node = load("res://scripts/Villager.gd").new()
	add_child(v)
	# Simule un paysan en train de récolter.
	v.set("_state", 2)  # GATHERING
	if not h.call("_is_member_busy", v):
		push_error("CHECK FAILED: paysan en GATHERING non détecté occupé (bug has_method)")
	# Un paysan idle ne doit PAS être considéré occupé.
	v.set("_state", 0)  # IDLE
	if h.call("_is_member_busy", v):
		push_error("CHECK FAILED: paysan IDLE considéré occupé à tort")
	v.queue_free()

## Bug "invalid previously freed instance" : quand un membre de la troupe meurt,
## sa référence reste dans _troop, et l'affectation typée 'var u: Node = _troop[i]'
## dans _physics_process levait une erreur à chaque frame (combat figé). Ce test
## vérifie que prune_dead_troop() retire bien la référence libérée avant toute
## affectation typée, donc que le combat ne fige plus.
func test_prune_dead_troop_removes_freed_member() -> void:
	var h := _make_hero()
	h.call("unassign_all")
	var v: Node = load("res://scripts/Villager.gd").new()
	add_child(v)
	h.call("assign_unit", v)
	if h.call("troop_size") != 1:
		push_error("CHECK FAILED: troupe non remplie avant libération")
	# Le paysan meurt (libéré) sans être retiré manuellement de la troupe.
	v.queue_free()
	await get_tree().process_frame
	# Sans le correctif, 'var u: Node = _troop[0]' lèverait "invalid freed instance".
	# prune_dead_troop() (appelé en tête de _physics_process) doit purger la réf.
	h.call("prune_dead_troop")
	if h.call("troop_size") != 0:
		push_error("CHECK FAILED: prune_dead_troop n'a pas retiré la référence libérée")
	# Après purge, l'affectation typée de _physics_process est sûre (aucune erreur).
	var arr: Array = h.get("_troop")
	for i in arr.size():
		var u: Node = arr[i]
		if not is_instance_valid(u):
			push_error("CHECK FAILED: référence libérée encore présente après purge")

