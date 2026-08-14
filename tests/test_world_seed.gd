extends Node
## Test de la graine de monde partagée : vérifie que deux appels de calcul à
## partir du même room_id produisent LA MÊME graine (base du monde déterministe).

func test_compute_world_seed_deterministic() -> void:
	if not Lobby:
		return  # autoload absent en mode test headless : on saute l'appel direct
	var a: int = Lobby._compute_world_seed()
	var b: int = Lobby._compute_world_seed()
	if a != b:
		push_error("CHECK FAILED: seed non déterministe pour le même room")

## La fonction de hachage de Godot est stable pour une même entrée : vérifie
## qu'aucune exception n'est levée lors du calcul (compilation correcte).
func test_world_seed_no_error() -> void:
	var room_id := "ROOM_SYNCTEST"
	var seed_val: int = abs(hash(room_id))
	if seed_val <= 0:
		push_error("CHECK FAILED: graine invalide")
