extends Node
## Auto-mise à jour (Desktop uniquement).
##
## Au lancement, le jeu interroge les Releases GitHub du dépôt. Si une version
## plus récente que la version locale existe, un panneau propose de la
## télécharger et de l'installer automatiquement : le jeu télécharge le .zip
## Windows, extrait l'exe + pck, puis un petit script .bat remplace les fichiers
## après la fermeture du jeu et le relance. Le Web se met à jour tout seul
## (rechargement de la page) : aucune logique ici.

signal update_available(version: String, notes: String, size: int)
signal update_finished(success: bool, message: String)

## Version actuelle embarquée. Doit correspondre au tag de la Release GitHub
## (sans le "v" initial). À incrémenter à chaque nouvelle version publiée.
const APP_VERSION := "1.0.0"
const REPO := "imaginbox/lastclan"
const EXE_NAME := "TheLastClan.exe"
const PCK_NAME := "TheLastClan.pck"

var _http: HTTPRequest = null
var _update_url := ""
var _update_size := 0
var _checking := false
var _downloading := false
var _check_done := false

# UI du panneau de mise à jour.
var _layer: CanvasLayer = null
var _progress_bar: ProgressBar = null
var _progress_label: Label = null
var _download_btn: Button = null

func _ready() -> void:
	# Le Web se met à jour via le rechargement de la page : rien à faire.
	if OS.get_name() == "Web":
		set_process(false)
		return
	_http = HTTPRequest.new()
	add_child(_http)
	_http.max_redirects = 8
	_http.timeout = 20.0
	_http.request_completed.connect(_on_check_completed)
	# Petite attente pour laisser le menu s'afficher avant le réseau.
	get_tree().create_timer(0.9).timeout.connect(check_for_updates)

func _process(_delta: float) -> void:
	if not _downloading or _http == null or _progress_bar == null:
		return
	var total: int = _http.get_body_size()
	var done: int = _http.get_downloaded_bytes()
	if total > 0:
		_progress_bar.max_value = total
		_progress_bar.value = done
		if _progress_label != null:
			_progress_label.text = "Téléchargement… %d / %d Mo" % [
				done / 1048576, total / 1048576
			]

## Vérifie si une version plus récente existe sur GitHub Releases.
func check_for_updates() -> void:
	if _check_done or _checking or OS.get_name() == "Web":
		return
	_checking = true
	var url := "https://api.github.com/repos/%s/releases/latest" % REPO
	var err := _http.request(url)
	if err != OK:
		_checking = false
		_check_done = true

func _on_check_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_checking = false
	_check_done = true
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return  # Hors-ligne ou aucune release : on reste silencieux.
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return
	var data: Dictionary = json.data
	var remote: String = String(data.get("tag_name", "v0.0.0")).trim_prefix("v")
	var url := ""
	var size := 0
	for a: Variant in data.get("assets", []):
		var aname := String(a.get("name", ""))
		if aname.ends_with(".zip") and (aname.contains("Windows") or url.is_empty()):
			url = String(a.get("browser_download_url", ""))
			size = int(a.get("size", 0))
	if url.is_empty():
		return
	if not version_newer(remote, APP_VERSION):
		return
	_update_url = url
	_update_size = size
	var notes := String(data.get("body", ""))
	update_available.emit(remote, notes, size)
	_show_panel(remote, notes, size)

## Lance le téléchargement puis l'installation de la mise à jour.
func download_and_install() -> void:
	if _downloading or _update_url.is_empty():
		return
	_downloading = true
	var exe_dir := OS.get_executable_path().get_base_dir()
	var upd_dir := exe_dir.path_join("update")
	var mk := DirAccess.make_dir_recursive_absolute(upd_dir)
	if mk != OK:
		_finish(false, "Impossible de créer le dossier de mise à jour.")
		return
	var zip_path := upd_dir.path_join("update.zip")
	_http.request_completed.disconnect(_on_check_completed)
	_http.request_completed.connect(_on_download_completed)
	_http.download_file = zip_path
	if _progress_bar != null:
		_progress_bar.visible = true
	if _download_btn != null:
		_download_btn.disabled = true
		_download_btn.text = "Téléchargement…"
	var err := _http.request(_update_url)
	if err != OK:
		_finish(false, "Échec du lancement du téléchargement.")

func _on_download_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_downloading = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_finish(false, "Échec du téléchargement (code %d)." % code)
		return
	_extract_and_install()

func _extract_and_install() -> void:
	var exe_dir := OS.get_executable_path().get_base_dir()
	var upd_dir := exe_dir.path_join("update")
	var zip_path := upd_dir.path_join("update.zip")
	var zr := ZIPReader.new()
	var err := zr.open(zip_path)
	if err != OK:
		_finish(false, "Archive de mise à jour corrompue.")
		return
	for name in [EXE_NAME, PCK_NAME]:
		if zr.get_files().has(name):
			var data := zr.read_file(name)
			var out := FileAccess.open(upd_dir.path_join(name), FileAccess.WRITE)
			if out != null:
				out.store_buffer(data)
				out.close()
	zr.close()

	# Petit .bat qui attend la fermeture du jeu, remplace les fichiers, relance.
	var bat := upd_dir.path_join("_update.bat")
	var f := FileAccess.open(bat, FileAccess.WRITE)
	if f == null:
		_finish(false, "Impossible d'écrire le script d'installation.")
		return
	f.store_string(_build_bat_script(exe_dir))
	f.close()

	# Lance le .bat puis quitte : le .bat finalise le remplacement + relance.
	OS.create_process("cmd", ["/c", bat])
	get_tree().quit()

## Script .bat : attends la fin du jeu, copie exe+pck depuis update/ vers le jeu,
## puis relance le nouveau binaire. Les '%' littéraux sont échappés en '%%' pour
## GDScript (le '%' est l'opérateur de format).
static func _build_bat_script(exe_dir: String) -> String:
	var lines := PackedStringArray()
	lines.append("@echo off")
	lines.append("set \"SRC=%~dp0\"")
	lines.append("set \"DST=%s\"" % exe_dir)
	lines.append(":wait")
	lines.append("tasklist /FI \"IMAGENAME eq %s\" 2>nul | find /I \"%s\" >nul" % [EXE_NAME, EXE_NAME])
	lines.append("if not errorlevel 1 ( timeout /t 1 /nobreak >nul & goto wait )")
	lines.append("copy /Y \"%%SRC%%%s\" \"%%DST%%\\%s\" >nul" % [EXE_NAME, EXE_NAME])
	lines.append("copy /Y \"%%SRC%%%s\" \"%%DST%%\\%s\" >nul" % [PCK_NAME, PCK_NAME])
	lines.append("del /Q \"%SRC%update.zip\" 2>nul")
	lines.append("start \"\" \"%%DST%%\\%s\"" % EXE_NAME)
	return "\n".join(lines) + "\n"

## Compare deux versions "1.2.3" (sans préfixe). Retourne vrai si remote > local.
static func version_newer(remote: String, local: String) -> bool:
	var r := _parse_version(remote)
	var l := _parse_version(local)
	var n := maxi(r.size(), l.size())
	for i in n:
		var rv: int = r[i] if i < r.size() else 0
		var lv: int = l[i] if i < l.size() else 0
		if rv != lv:
			return rv > lv
	return false

static func _parse_version(v: String) -> Array[int]:
	var out: Array[int] = []
	for part: String in v.trim_prefix("v").split("."):
		out.append(int(part))
	return out

func _finish(success: bool, message: String) -> void:
	_downloading = false
	update_finished.emit(success, message)
	if _download_btn != null:
		_download_btn.disabled = false
		_download_btn.text = "Réessayer"
	if _progress_label != null:
		_progress_label.text = message

## Construit un panneau modal centré annonçant la mise à jour.
func _show_panel(version: String, notes: String, size: int) -> void:
	if _layer != null:
		return
	_layer = CanvasLayer.new()
	_layer.layer = 100
	get_tree().root.add_child(_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.13, 1.0)
	sb.border_color = Color(0.85, 0.7, 0.2, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Mise à jour disponible (v%s)" % version
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.85, 0.7, 0.2))
	box.add_child(title)

	var desc := Label.new()
	desc.text = "Une nouvelle version du jeu est disponible. Souhaitez-vous la télécharger et l'installer ?"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(360, 0)
	box.add_child(desc)

	if not notes.strip_edges().is_empty():
		var note_lbl := Label.new()
		note_lbl.text = "Nouveautés :\n%s" % notes.strip_edges()
		note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
		box.add_child(note_lbl)

	_progress_label = Label.new()
	_progress_label.text = "Taille : %d Mo" % (size / 1048576)
	box.add_child(_progress_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(360, 16)
	_progress_bar.visible = false
	box.add_child(_progress_bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	_download_btn = Button.new()
	_download_btn.text = "Télécharger et installer"
	_download_btn.pressed.connect(download_and_install)
	row.add_child(_download_btn)

	var later := Button.new()
	later.text = "Plus tard"
	later.pressed.connect(_hide_panel)
	row.add_child(later)

func _hide_panel() -> void:
	if _layer != null:
		_layer.queue_free()
		_layer = null
