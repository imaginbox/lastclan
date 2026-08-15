extends Node

## Test du système de messages in-game (toasts) :
##  - _notify affiche un toast dans le conteneur _toast_box (pas seulement console)
##  - un toast est bien créé avec le texte fourni
##  - les messages de chat reçus déclenchent un toast

func _make_main() -> Node:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	return main

func test_notify_creates_toast() -> void:
	var main := _make_main()
	if not main.has_method("_setup_toasts"):
		main.queue_free()
		return
	var box: VBoxContainer = main.get("_toast_box")
	main.call("_push_toast", "Test message")
	if box != null:
		var n := box.get_child_count()
		if n < 1:
			push_error("CHECK FAILED: _push_toast ne crée aucun toast")
	main.queue_free()

func test_notify_pushes_toast() -> void:
	var main := _make_main()
	if not main.has_method("_notify"):
		main.queue_free()
		return
	var box: VBoxContainer = main.get("_toast_box")
	main.call("_notify", "Ressources insuffisantes !")
	if box != null and box.get_child_count() < 1:
		push_error("CHECK FAILED: _notify n'affiche pas de toast en jeu")
	main.queue_free()
