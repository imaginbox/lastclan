extends Node

## Test du scaling mobile du Lobby : sur écran étroit (< 720 px) tous les
## boutons, champs et polices doivent être nettement plus grands et lisibles.

func test_mobile_scale_gt_desktop() -> void:
	var menu: Node = load("res://scripts/LobbyMenu.gd").new()
	# Simule un écran mobile étroit.
	menu.set("_ui_scale", 1.45)
	menu.set("_btn_h", menu.call("_gd", 50))
	menu.set("_field_h", menu.call("_gd", 44))

	# Gros boutons : nettement plus hauts que la version desktop (≥ 60 px).
	var btn: Button = menu.call("_big_button", "Jouer hors ligne", Callable(), true)
	if btn.custom_minimum_size.y < 60:
		push_error("CHECK FAILED: bouton mobile trop petit (h=%s)" % btn.custom_minimum_size.y)

	# Champs de saisie : plus épais et lisibles.
	var field: LineEdit = LineEdit.new()
	field.custom_minimum_size = Vector2(0, menu.get("_field_h"))
	if field.custom_minimum_size.y < 55:
		push_error("CHECK FAILED: champ mobile trop fin (h=%s)" % field.custom_minimum_size.y)

	# Police des gros boutons agrandie (>= 20).
	var fs: int = menu.call("_gd", 17)
	if fs < 20:
		push_error("CHECK FAILED: police bouton mobile trop petite (%s)" % fs)

	# Conversion cohérente : _gd multiplie par le facteur d'échelle.
	if menu.call("_gd", 48) < 65:
		push_error("CHECK FAILED: _gd(48) ne grossit pas assez")

	btn.queue_free()
	field.queue_free()
	menu.free()
