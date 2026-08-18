extends Node
## Tests de la logique de comparaison de versions de UpdateManager.
## version_newer est statique et pure : pas d'await, fiable sous le runner.

func test_version_newer_true() -> void:
	if not UpdateManager.version_newer("1.2.0", "1.1.9"):
		push_error("CHECK FAILED: 1.2.0 devrait être plus récent que 1.1.9")

func test_version_newer_false_when_equal() -> void:
	if UpdateManager.version_newer("1.2.0", "1.2.0"):
		push_error("CHECK FAILED: égal ne doit pas être 'plus récent'")

func test_version_newer_false_when_older() -> void:
	if UpdateManager.version_newer("1.1.0", "1.2.0"):
		push_error("CHECK FAILED: 1.1.0 ne doit pas être plus récent que 1.2.0")

func test_version_newer_handles_v_prefix() -> void:
	if not UpdateManager.version_newer("v1.3.0", "1.2.9"):
		push_error("CHECK FAILED: v1.3.0 (avec v) devrait être plus récent")

func test_version_newer_pad_zeros() -> void:
	if not UpdateManager.version_newer("1.10.0", "1.9.9"):
		push_error("CHECK FAILED: 1.10.0 > 1.9.9 (comparaison numérique)")

func test_version_newer_major() -> void:
	if not UpdateManager.version_newer("2.0.0", "1.9.9"):
		push_error("CHECK FAILED: 2.0.0 > 1.9.9")
	if UpdateManager.version_newer("1.9.9", "2.0.0"):
		push_error("CHECK FAILED: 1.9.9 ne doit pas être plus récent que 2.0.0")

## Vérifie que le script .bat d'installation est bien généré (avec les % littéraux
## corrects, pas doublés — le bug '%%' dans les lignes sans opérateur de format).
func test_bat_script_content() -> void:
	var bat: String = UpdateManager._build_bat_script("C:\\Games\\TheLastClan")
	if not bat.contains("set \"SRC=%~dp0\""):
		push_error("CHECK FAILED: le .bat doit contenir 'SRC=%~dp0' (sans %% doublé)")
	if not bat.contains("set \"DST=C:\\Games\\TheLastClan\""):
		push_error("CHECK FAILED: le .bat doit contenir le DST du dossier du jeu")
	if not bat.contains("copy /Y \"%SRC%TheLastClan.exe\""):
		push_error("CHECK FAILED: le .bat doit copier l'exe avec %SRC% simple")
	if not bat.contains("del /Q \"%SRC%update.zip\""):
		push_error("CHECK FAILED: le .bat doit nettoyer update.zip avec %SRC% simple")
	if bat.contains("%%"):
		push_error("CHECK FAILED: '%%' résiduel dans le .bat (échappement mal géré)")
