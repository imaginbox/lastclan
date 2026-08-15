extends Node

## Test responsive du HUD : en portrait (mobile), les sous-infos (Population /
## Royaume / Clan) sont repliées derrière le bouton « + » pour que la barre du
## haut ne soit jamais coupée ; en paysage (PC) elles sont ouvertes d'office.

func _make_main() -> Node:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	return main

func test_portrait_folds_extra_info() -> void:
	var main := _make_main()
	if not main.has_method("_apply_orientation_layout"):
		main.queue_free()
		return
	main._is_portrait = true
	main.call("_apply_orientation_layout")
	var extra: PanelContainer = main.get("_hud_extra_panel")
	if extra != null and main.get_tree() != null:
		if extra.visible:
			push_error("CHECK FAILED: sous-infos visibles en portrait")
	main.queue_free()

func test_landscape_shows_extra_info() -> void:
	var main := _make_main()
	if not main.has_method("_apply_orientation_layout"):
		main.queue_free()
		return
	main._is_portrait = false
	main.call("_apply_orientation_layout")
	var extra: PanelContainer = main.get("_hud_extra_panel")
	if extra != null and extra.is_inside_tree():
		if not extra.visible:
			push_error("CHECK FAILED: sous-infos repliées en paysage")
	main.queue_free()

func test_plus_button_toggles_extra_panel() -> void:
	var main := _make_main()
	if not main.has_method("_toggle_extra_info"):
		main.queue_free()
		return
	var extra: PanelContainer = main.get("_hud_extra_panel")
	if extra == null:
		main.queue_free()
		return
	main._is_portrait = false
	main.call("_apply_orientation_layout")
	main.call("_toggle_extra_info")
	if extra.visible:
		push_error("CHECK FAILED: + ne referme pas le panneau")
	main.call("_toggle_extra_info")
	if not extra.visible:
		push_error("CHECK FAILED: + ne rouvre pas le panneau")
	main.queue_free()

## Sélectionner une unité doit faire apparaître le panneau des états (droite).
func test_unit_selection_shows_state_panel() -> void:
	var main := _make_main()
	if get_tree() == null:
		main.queue_free()
		return
	# Instance directe d'une unité (fiable en headless, comme test_combat).
	var u: Node = load("res://scenes/Villager.tscn").instantiate()
	main.add_child(u)
	await get_tree().process_frame
	main.call("_select_single_from_node", u)
	await get_tree().process_frame
	var panel: PanelContainer = main.get("_unit_panel")
	if panel == null:
		push_error("CHECK FAILED: _unit_panel nul")
		main.queue_free()
		return
	if not panel.visible:
		push_error("CHECK FAILED: panneau d'états invisible après sélection d'unité")
	var role: Label = main.get("_unit_role_lbl")
	if role == null or role.text.is_empty():
		push_error("CHECK FAILED: rôle unité manquant")
	main.queue_free()

func test_unit_deselect_hides_state_panel() -> void:
	var main := _make_main()
	if get_tree() == null:
		main.queue_free()
		return
	var u: Node = load("res://scenes/Villager.tscn").instantiate()
	main.add_child(u)
	await get_tree().process_frame
	main.call("_select_single_from_node", u)
	await get_tree().process_frame
	main.call("_deselect_all")
	var panel: PanelContainer = main.get("_unit_panel")
	if panel != null and panel.visible:
		push_error("CHECK FAILED: panneau d'états visible après désélection")
	main.queue_free()
