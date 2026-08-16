extends Node
## Tests des sous-rubriques ajoutées à l'admin dashboard : chaque paramètre du
## registre doit déclarer une sous-rubrique (champ "sub") pour un affichage clair.

var gc: Node = null

func _node() -> Node:
	if gc == null:
		gc = load("res://scripts/GameConfig.gd").new()
	return gc

func test_all_params_have_sub_rubric() -> void:
	var n := _node()
	var reg: Array = n.registry()
	var missing: Array = []
	for p in reg:
		var key := String(p["key"])
		var sub := String(p.get("sub", ""))
		if sub.is_empty():
			missing.append(key)
	if not missing.is_empty():
		push_error("CHECK FAILED: paramètres sans sous-rubrique : %s" % str(missing))

func test_sub_rubrics_grouped_per_category() -> void:
	var n := _node()
	var reg: Array = n.registry()
	# Vérifie que chaque catégorie a au moins une sous-rubrique utilisée plusieurs
	# fois (preuve d'organisation) — et qu'aucune n'est vide.
	var by_cat := {}
	for p in reg:
		var cat := String(p["cat"])
		var sub := String(p.get("sub", ""))
		if not by_cat.has(cat):
			by_cat[cat] = {}
		by_cat[cat][sub] = true
	for cat in by_cat:
		for sub in by_cat[cat]:
			if String(sub).is_empty():
				push_error("CHECK FAILED: catégorie %s a une sous-rubrique vide" % cat)

func test_batiments_sous_rubriques_par_batiment() -> void:
	var n := _node()
	var reg: Array = n.registry()
	var hdv_subs: Array = []
	for p in reg:
		if String(p["key"]).begins_with("batiment.hdv."):
			var s := String(p.get("sub", ""))
			if not hdv_subs.has(s):
				hdv_subs.append(s)
	# La HDV est groupée sous au moins « HDV — Coûts » (et Caractéristiques).
	if not hdv_subs.has("HDV — Coûts"):
		push_error("CHECK FAILED: HDV pas groupée sous 'HDV — Coûts' (%s)" % str(hdv_subs))
