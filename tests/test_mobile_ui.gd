extends Node

## Test UI mobile : vérifie que la barre d'ordre apparaît quand une unité est
## sélectionnée, et que l'armement des ordres définit le bon mode.

func _find_main() -> Node:
	# L'hôtel de ville / base peut être prêt ou non selon le timing ; on instancie
	# notre propre Main et on attend que le monde soit construit.
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	return main

func _await_world_built(main: Node) -> void:
	# Attendre jusqu'à ce que des unités soient spawnées (jusqu'à 6s).
	for i in 20:
		await get_tree().create_timer(0.3).timeout
		var units: Node3D = main.get_node_or_null("Units")
		if units != null and units.get_child_count() > 0:
			return

func test_order_bar_appears_when_unit_selected() -> void:
	var main := _find_main()
	await _await_world_built(main)
	var units: Node3D = main.get_node("Units")
	if units.get_child_count() == 0:
		push_error("CHECK FAILED: pas d'unité spawnée")
		main.queue_free()
		return
	# Sélectionner une unité.
	main.call("_select_single_from_node", units.get_child(0))
	await get_tree().process_frame
	var order_bar: HBoxContainer = main.get("_order_bar")
	if order_bar == null:
		push_error("CHECK FAILED: _order_bar nul")
		main.queue_free()
		return
	var panel := order_bar.get_parent().get_parent() as PanelContainer
	if panel == null or not panel.visible:
		push_error("CHECK FAILED: barre d'ordre invisible après sélection")
	var btns: Dictionary = main.get("_order_btns")
	if btns.size() < 3:
		push_error("CHECK FAILED: boutons d'ordre manquants (size=", btns.size(), ")")
	main.queue_free()

func test_arm_order_sets_mode() -> void:
	var main := _find_main()
	await _await_world_built(main)
	var units: Node3D = main.get_node("Units")
	if units.get_child_count() == 0:
		main.queue_free()
		return
	main.call("_select_single_from_node", units.get_child(0))
	await get_tree().process_frame
	main.call("_arm_order", main.OrderMode.MOVE)
	if main.get("_order_mode") != main.OrderMode.MOVE or not main.get("_order_armed"):
		push_error("CHECK FAILED: arm_order MOVE")
	main.call("_arm_order", main.OrderMode.GATHER)
	if main.get("_order_mode") != main.OrderMode.GATHER:
		push_error("CHECK FAILED: arm_order GATHER")
	main.queue_free()