extends Node
## Test du câblage mode admin : les valeurs du panneau (GameConfig) changent
## réellement le coût/la production des bâtiments et les stats des unités.

var gc: Node = null
var gc_in_tree: bool = false

func _ensure_gc() -> Node:
	# Si l'autoload existe déjà dans l'arbre, on l'utilise.
	var glb := get_tree().root.get_node_or_null("GameConfig")
	if glb != null:
		gc_in_tree = true
		return glb
	if gc == null:
		gc = load("res://scripts/GameConfig.gd").new()
	return gc

func _cfg_of_building(t) -> Dictionary:
	# Reconstruit le chemin _cfg() du Building avec un GC présent dans l'arbre.
	var b: Building = Building.new()
	b.type = t
	b.level = 1
	add_child(b)
	return b._cfg()

func test_override_cost_applies_to_tour() -> void:
	var g := _ensure_gc()
	g.reset()
	g.set_value("batiment.tour.cout_bois", 500)
	var cfg := _cfg_of_building(Building.Type.TOWER)
	if int(cfg.get("cost_wood", 0)) != 500:
		push_error("CHECK FAILED: coût bois tour non surchargé (a %s)" % str(cfg.get("cost_wood")))

func test_override_production_applies_to_ferme() -> void:
	var g := _ensure_gc()
	g.reset()
	g.set_value("economie.nourriture.taux", 12.0)
	var cfg := _cfg_of_building(Building.Type.FERME)
	var prod: Dictionary = cfg.get("production", {})
	if float(prod.get("food", 0.0)) != 12.0:
		push_error("CHECK FAILED: production ferme non surchargée (a %s)" % str(prod))

func test_default_cost_without_gc() -> void:
	# Sans surch docs: le Building doit retomber sur sa config de base.
	var cfg := _cfg_of_building(Building.Type.TOWER)
	if int(cfg.get("cost_wood", 0)) != 70:
		push_error("CHECK FAILED: coût bois tour défaut != 70 (a %s)" % str(cfg.get("cost_wood")))

func test_hdv_recruit_cost_override() -> void:
	var g := _ensure_gc()
	g.reset()
	g.set_value("recrutement.paysan.or", 200)
	var cfg := _cfg_of_building(Building.Type.TOWN_HALL)
	if int(cfg.get("recruit_gold", 0)) != 200:
		push_error("CHECK FAILED: recruit_gold HDV non surchargé (a %s)" % str(cfg.get("recruit_gold")))
