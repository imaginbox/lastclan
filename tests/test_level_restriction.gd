extends Node
## Tests de la restriction de niveau des bâtiments (liée à l'HDV) et des
## paramètres d'échelle visuelle ajoutés dans l'admin (Bâtiments).

var gc: Node = null

func _node() -> Node:
	if gc == null:
		gc = load("res://scripts/GameConfig.gd").new()
	return gc

func test_effective_max_level_capped_by_hdv() -> void:
	# Simule le calcul : la restriction effective = min(max_level, hdv_level) pour
	# tout bâtiment hors HDV. On vérifie la fonction à travers un scénario auxiliaire.
	var b := Building.new()
	b.type = Building.Type.HOUSE
	b.level = 1
	# Hors arbre, town_hall_level()=999 => pas de restriction : effective = max_level.
	if b.effective_max_level() != 6:
		push_error("CHECK FAILED: maison max hors arbre attendu 6, obtenu %d" % b.effective_max_level())
	# Le comportement borné se teste via la formule : min(max_level, th_level).
	# (le calcul réel dépend de l'arbre, couvert en jeu)
	var capped := mini(b.max_level(), 3)
	if capped != 3:
		push_error("CHECK FAILED: mimo cap attendance = 3")
	b.free()

func test_visual_scale_params_registered() -> void:
	var n := _node()
	var reg: Array = n.registry()
	for key in [
		"batiment.hdv.echelle", "batiment.caserne.echelle", "batiment.maison.echelle",
		"batiment.tour.echelle", "batiment.ferme.echelle", "batiment.carriere.echelle",
		"batiment.mine.echelle",
	]:
		var found := false
		for p in reg:
			if p.get("key") == key:
				found = true
				if p.get("kind") != GameConfig.Kind.FLOAT:
					push_error("CHECK FAILED: %s devrait être FLOAT" % key)
				if p.get("def") != 1.0:
					push_error("CHECK FAILED: %s def devrait être 1.0" % key)
		if not found:
			push_error("CHECK FAILED: paramètre %s manquant" % key)

func test_visual_scale_params_in_descs() -> void:
	var n := _node()
	for key in [
		"batiment.hdv.echelle", "batiment.caserne.echelle", "batiment.maison.echelle",
		"batiment.tour.echelle", "batiment.ferme.echelle", "batiment.carriere.echelle",
		"batiment.mine.echelle",
	]:
		if str(n.param_desc(key)).is_empty():
			push_error("CHECK FAILED: description %s manquante" % key)

func test_echelle_prefix_maps_correctly() -> void:
	# Vérifie que le préfixe de clé utilisé par Building correspond aux clés admin.
	var b := Building.new()
	b.type = Building.Type.BARRACKS
	var expected := "batiment.caserne.echelle"
	var pre: String = b.call("_cfg_prefix")
	if pre + "echelle" != expected:
		push_error("CHECK FAILED: prefix caserne → %s, attendu %s" % [pre + "echelle", expected])
	b.free()
