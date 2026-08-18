extends Node
## Tests de la logique de comparaison de versions de UpdateManager.
## version_newer est statique et pure : pas d'await, fiable sous le runner.

func test_version_newer_true() -> void:
	if not UpdateManagerCore.version_newer("1.2.0", "1.1.9"):
		push_error("CHECK FAILED: 1.2.0 devrait être plus récent que 1.1.9")

func test_version_newer_false_when_equal() -> void:
	if UpdateManagerCore.version_newer("1.2.0", "1.2.0"):
		push_error("CHECK FAILED: égal ne doit pas être 'plus récent'")

func test_version_newer_false_when_older() -> void:
	if UpdateManagerCore.version_newer("1.1.0", "1.2.0"):
		push_error("CHECK FAILED: 1.1.0 ne doit pas être plus récent que 1.2.0")

func test_version_newer_handles_v_prefix() -> void:
	if not UpdateManagerCore.version_newer("v1.3.0", "1.2.9"):
		push_error("CHECK FAILED: v1.3.0 (avec v) devrait être plus récent")

func test_version_newer_pad_zeros() -> void:
	if not UpdateManagerCore.version_newer("1.10.0", "1.9.9"):
		push_error("CHECK FAILED: 1.10.0 > 1.9.9 (comparaison numérique)")

func test_version_newer_major() -> void:
	if not UpdateManagerCore.version_newer("2.0.0", "1.9.9"):
		push_error("CHECK FAILED: 2.0.0 > 1.9.9")
	if UpdateManagerCore.version_newer("1.9.9", "2.0.0"):
		push_error("CHECK FAILED: 1.9.9 ne doit pas être plus récent que 2.0.0")

## Vérifie que le script .bat d'installation est bien généré (avec les % littéraux
## corrects, pas doublés — le bug '%%' dans les lignes sans opérateur de format).
func test_bat_script_content() -> void:
	var bat: String = UpdateManagerCore._build_bat_script("C:\\Games\\TheLastClan")
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

# ======================== _parse_release (décision de mise à jour) =============

const NEWER_BODY := '{"tag_name":"v1.1.0","body":"Corrections et nouveautés","assets":[{"name":"TheLastClan_Windows.zip","browser_download_url":"https://x/z.zip","size":123456}]}'

func test_parse_release_newer_returns_update() -> void:
	var r: Dictionary = UpdateManagerCore._parse_release(NEWER_BODY.to_utf8_buffer())
	if r.is_empty():
		push_error("CHECK FAILED: une release plus récente doit déclencher une mise à jour")
		return
	if r["version"] != "1.1.0":
		push_error("CHECK FAILED: version attendue 1.1.0, reçue " + str(r["version"]))
	if r["url"] != "https://x/z.zip":
		push_error("CHECK FAILED: url mal extraite")
	if r["size"] != 123456:
		push_error("CHECK FAILED: taille mal extraite")
	if r["notes"] != "Corrections et nouveautés":
		push_error("CHECK FAILED: notes mal extraites")

func test_parse_release_equal_no_update() -> void:
	var body := '{"tag_name":"v1.0.0","assets":[{"name":"TheLastClan_Windows.zip","browser_download_url":"https://x/z.zip","size":1}]}'
	if not UpdateManagerCore._parse_release(body.to_utf8_buffer()).is_empty():
		push_error("CHECK FAILED: version égale -> aucune mise à jour")

func test_parse_release_older_no_update() -> void:
	var body := '{"tag_name":"v0.9.0","assets":[{"name":"TheLastClan_Windows.zip","browser_download_url":"https://x/z.zip","size":1}]}'
	if not UpdateManagerCore._parse_release(body.to_utf8_buffer()).is_empty():
		push_error("CHECK FAILED: version plus vieille -> aucune mise à jour")

func test_parse_release_ignores_non_windows_asset() -> void:
	var body := '{"tag_name":"v1.2.0","assets":[{"name":"index.html","browser_download_url":"https://x/index.html","size":1},{"name":"TheLastClan_Windows.zip","browser_download_url":"https://x/w.zip","size":99}]}'
	var r: Dictionary = UpdateManagerCore._parse_release(body.to_utf8_buffer())
	if r.is_empty() or r["url"] != "https://x/w.zip":
		push_error("CHECK FAILED: doit choisir l'asset Windows .zip")

func test_parse_release_no_zip_empty() -> void:
	var body := '{"tag_name":"v1.2.0","assets":[{"name":"index.html","browser_download_url":"https://x/index.html","size":1}]}'
	if not UpdateManagerCore._parse_release(body.to_utf8_buffer()).is_empty():
		push_error("CHECK FAILED: aucun .zip -> aucune mise à jour")

func test_parse_release_invalid_empty() -> void:
	if not UpdateManagerCore._parse_release("pas du json".to_utf8_buffer()).is_empty():
		push_error("CHECK FAILED: JSON invalide -> aucune mise à jour")
