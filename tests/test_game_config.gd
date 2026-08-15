extends Node
## Tests du registre de paramètres GameConfig (mode admin).
## Instancie le script directement (pas besoin de l'arbre/pipeline).

var gc: Node = null

func _node() -> Node:
	if gc == null:
		gc = load("res://scripts/GameConfig.gd").new()
	return gc

func test_registry_declares_params() -> void:
	var n := _node()
	var reg: Array = n.registry()
	if reg.size() < 20:
		push_error("CHECK FAILED: le registre doit déclarer au moins 20 paramètres (a %d)" % reg.size())

func test_has_categories() -> void:
	var n := _node()
	var cats: Array = n.categories()
	if not cats.has("Économie"):
		push_error("CHECK FAILED: catégorie Économie absente (%s)" % str(cats))
	if not cats.has("Paysan"):
		push_error("CHECK FAILED: catégorie Paysan absente")
	if not cats.has("Admin"):
		push_error("CHECK FAILED: catégorie Admin absente")

func test_get_default_and_set() -> void:
	var n := _node()
	n.reset()
	if n.get_value("unite.soldat.vitesse") != 4.0:
		push_error("CHECK FAILED: vitesse soldat défaut != 4.0")
	n.set_value("unite.soldat.vitesse", 8.0)
	if n.get_value("unite.soldat.vitesse") != 8.0:
		push_error("CHECK FAILED: set_value n'a pas pris en compte la nouvelle vitesse")
	n.reset()

func test_tour_costs_defaults() -> void:
	var n := _node()
	n.reset()
	if n.get_value("batiment.tour.cout_or") != 80:
		push_error("CHECK FAILED: tour coût or défaut != 80")
	if n.get_value("batiment.maison.pop") != 8:
		push_error("CHECK FAILED: maison pop défaut != 8")

func test_password_default() -> void:
	var n := _node()
	n.reset()
	if n.get_value("admin.mot_de_passe") != "lastclan":
		push_error("CHECK FAILED: mot de passe admin défaut != 'lastclan'")

func test_persistence_roundtrip() -> void:
	var n := _node()
	n.reset()
	n.set_value("unite.paysan.vitesse", 9.5)
	n.save()
	var n2 := _node()
	n2.reset()
	n2.load_saved()
	if n2.get_value("unite.paysan.vitesse") != 9.5:
		push_error("CHECK FAILED: la persistance n'a pas retenu la vitesse paysan (a %s)" % str(n2.get_value("unite.paysan.vitesse")))
	n2.reset()
	n2.save()


func test_category_descriptions_present() -> void:
	var n := _node()
	if n.category_desc("Économie") == "":
		push_error("CHECK FAILED: la description de catégorie Économie est vide")
	if n.category_desc("CatégorieInexistante") != "":
		push_error("CHECK FAILED: devrait retourner vide pour une catégorie inconnue")

func test_param_descriptions_present() -> void:
	var n := _node()
	if n.param_desc("unite.paysan.vitesse") == "":
		push_error("CHECK FAILED: description du param vitesse paysan absente")
	if n.param_desc("clé.inconnue") != "":
		push_error("CHECK FAILED: devrait retourner vide pour une clé inconnue")
