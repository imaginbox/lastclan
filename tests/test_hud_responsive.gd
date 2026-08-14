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
