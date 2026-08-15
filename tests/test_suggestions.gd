extends Node

## Test du canal de suggestions (feedback) : vérifie que le serveur écrit bien un
## fichier JSONL persistant et que l'ajout se fait en fin de fichier sans écraser.

func _cleanup() -> void:
	# Supprime tout fichier de test éventuel.
	var p := ProjectSettings.globalize_path("res://outbox/suggestions.jsonl")
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)

func test_feedback_append_writes_jsonl() -> void:
	_cleanup()
	var lobby: Node = load("res://scripts/Lobby.gd").new()
	# Appelle directement l'écriture (pas de réseau/multiplayer nécessaire).
	var ok: bool = lobby.call("_append_feedback", "Testeur", "J'adore ce jeu !")
	if not ok:
		push_error("CHECK FAILED: _append_feedback a retourné false")
	var p := ProjectSettings.globalize_path("res://outbox/suggestions.jsonl")
	if not FileAccess.file_exists(p):
		push_error("CHECK FAILED: fichier suggestions.jsonl absent")
		lobby.free()
		return
	# Ligne JSON valide contenant le nom et le texte.
	var content := FileAccess.get_file_as_string(p)
	var parsed: Variant = JSON.parse_string(content.strip_edges())
	if parsed is not Dictionary:
		push_error("CHECK FAILED: contenu non parsable: ", content)
	elif parsed.get("name") != "Testeur" or parsed.get("text") != "J'adore ce jeu !":
		push_error("CHECK FAILED: contenu inattendu: ", content)
	lobby.free()

func test_feedback_append_appends_not_overwrites() -> void:
	_cleanup()
	var lobby: Node = load("res://scripts/Lobby.gd").new()
	lobby.call("_append_feedback", "A", "premier")
	lobby.call("_append_feedback", "B", "second")
	var content := FileAccess.get_file_as_string(
		ProjectSettings.globalize_path("res://outbox/suggestions.jsonl"))
	if content.count("premier") != 1:
		push_error("CHECK FAILED: 'premier' absent ou dupliqué")
	if content.count("second") != 1:
		push_error("CHECK FAILED: 'second' absent ou dupliqué")
	# Deux lignes distinctes (JSON Lines).
	var lines := content.strip_edges().split("\n")
	if lines.size() < 2:
		push_error("CHECK FAILED: attendu >= 2 lignes, obtenu ", lines.size())
	lobby.free()
	_cleanup()
