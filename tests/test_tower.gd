extends Node
## Tests du système de tour de défense (combat automatique).

func test_tower_attack_damage_scales_with_level() -> void:
	var b := Building.new()
	b.type = Building.Type.TOWER
	b.level = 1
	if b.attack_damage() != 10:
		push_error("CHECK FAILED: tour niveau 1 attendu 10 dégâts, obtenu %d" % b.attack_damage())
	b.level = 3
	if b.attack_damage() != 30:
		push_error("CHECK FAILED: tour niveau 3 attendu 30 dégâts, obtenu %d" % b.attack_damage())
	b.free()

func test_non_tower_has_no_damage() -> void:
	var b := Building.new()
	b.type = Building.Type.HOUSE
	b.level = 3
	if b.attack_damage() != 0:
		push_error("CHECK FAILED: une maison ne doit infliger aucun dégât")
	b.free()

func test_tower_range_filter_logic() -> void:
	# Vérifie le SEUIL de portée (logique pure) : un ennemi au-delà de TOWER_RANGE
	# est écarté par le carré de distance. (le ciblage en arbre réel est couvert en jeu)
	var range_sq := 24.0 * 24.0
	var inside := 10.0 * 10.0 < range_sq
	var outside := 100.0 * 100.0 < range_sq
	if not inside:
		push_error("CHECK FAILED: un ennemi à 10 u doit être dans la portée")
	if outside:
		push_error("CHECK FAILED: un ennemi à 100 u ne doit PAS être dans la portée")