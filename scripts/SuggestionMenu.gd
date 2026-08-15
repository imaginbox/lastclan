class_name SuggestionMenu
extends Control

## SuggestionMenu — écran de suggestions persistantes côté serveur.
##
## Le joueur écrit une suggestion / un rapport de bug. Le message est envoyé au
## SERVEUR (auto-hébergé WebSocket sur le VPS) via une RPC qui écrit dans un
## fichier persistant (hors dépôt Git), pour que l'équipe puisse le lire.
## Hors ligne, le message est mis en file d'attente locale puis vidée à la
## connexion suivante.

const LOBBY_SCENE := "res://scenes/LobbyMenu.tscn"

## File d'attente locale des suggestions non encore envoyées (hors ligne).
const QUEUE_FILE := "user://suggestions_queue.json"
## Fichier persistant écrit par le SERVEUR (sur le VPS) — survit aux git reset.
const SERVER_OUTBOX := "res://outbox/suggestions.jsonl"

var _name_input: LineEdit
var _msg_input: TextEdit
var _status_label: Label
var _send_button: Button

func _ready() -> void:
	_build_ui()

## Accesseurs des autoloads via get_node (fiabilité au parse — voir LobbyMenu).
func _langs() -> Node:
	return get_node("/root/Langs")

func _lobby() -> Node:
	return get_node("/root/Lobby")

func _gd(s: int) -> int:
	return int(round(s * 1.6))

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad := 8.0
	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", int(pad))
	outer.add_theme_constant_override("margin_right", int(pad))
	outer.add_theme_constant_override("margin_top", int(pad))
	outer.add_theme_constant_override("margin_bottom", int(pad))
	add_child(outer)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.13, 0.1, 0.075, 0.97)
	ps.border_color = Color(0.85, 0.66, 0.3, 0.9)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(14)
	ps.content_margin_left = _gd(16)
	ps.content_margin_right = _gd(16)
	ps.content_margin_top = _gd(18)
	ps.content_margin_bottom = _gd(16)
	panel.add_theme_stylebox_override("panel", ps)
	outer.add_child(panel)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", _gd(14))
	panel.add_child(vb)

	# ---- Titre.
	var title := Label.new()
	title.text = _langs().t("suggest.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", _gd(30))
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.03, 0.95))
	title.add_theme_constant_override("outline_size", 4)
	vb.add_child(title)

	var subtitle := Label.new()
	subtitle.text = _langs().t("suggest.subtitle")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", _gd(15))
	subtitle.add_theme_color_override("font_color", Color(0.85, 0.78, 0.6))
	vb.add_child(subtitle)

	# ---- Nom.
	vb.add_child(_field_label(_langs().t("suggest.name")))
	_name_input = LineEdit.new()
	_name_input.text = _lobby().player_info.get("name", "Joueur")
	_name_input.custom_minimum_size = Vector2(0, _gd(44))
	_stylize_field(_name_input)
	vb.add_child(_name_input)

	# ---- Message.
	vb.add_child(_field_label(_langs().t("suggest.message")))
	_msg_input = TextEdit.new()
	_msg_input.custom_minimum_size = Vector2(0, _gd(180))
	_msg_input.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_msg_input.placeholder_text = _langs().t("suggest.message")
	_msg_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_stylize_textedit(_msg_input)
	vb.add_child(_msg_input)

	# ---- Envoyer.
	_send_button = _big_button(_langs().t("suggest.send"), _on_send, true)
	_send_button.custom_minimum_size = Vector2(0, _gd(60))
	_send_button.add_theme_font_size_override("font_size", _gd(22))
	_send_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_send_button)

	# ---- Retour.
	var back := _big_button(_langs().t("suggest.back"), _on_back, false)
	back.custom_minimum_size = Vector2(0, _gd(46))
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(back)

	# ---- Statut.
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", _gd(15))
	_status_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.6))
	vb.add_child(_status_label)

func _field_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.88, 0.82, 0.68))
	l.add_theme_font_size_override("font_size", _gd(17))
	l.add_theme_constant_override("outline_size", 4)
	return l

func _big_button(text: String, handler: Callable, _primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, _gd(48))
	b.add_theme_font_size_override("font_size", _gd(18))
	b.pressed.connect(handler)
	_stylize_button(b)
	return b

func _stylize_button(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.16, 0.12, 0.09, 0.94)
		sb.border_color = Color(0.85, 0.66, 0.3, 0.95)
		sb.set_border_width_all(_gd(2))
		sb.set_corner_radius_all(_gd(8))
		sb.content_margin_left = _gd(12)
		sb.content_margin_right = _gd(12)
		sb.content_margin_top = _gd(6)
		sb.content_margin_bottom = _gd(6)
		if state == "hover" or state == "pressed":
			sb.bg_color = Color(0.28, 0.2, 0.13, 1.0)
			sb.border_color = Color(1.0, 0.8, 0.4, 1.0)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.05, 0.95))
	b.add_theme_constant_override("outline_size", _gd(8))

func _stylize_field(e: LineEdit) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.045, 0.9)
	sb.border_color = Color(0.85, 0.66, 0.3, 0.45)
	sb.set_border_width_all(_gd(1))
	sb.set_corner_radius_all(_gd(8))
	sb.content_margin_left = _gd(14)
	sb.content_margin_right = _gd(14)
	sb.content_margin_top = _gd(8)
	sb.content_margin_bottom = _gd(8)
	e.add_theme_stylebox_override("normal", sb)
	e.add_theme_stylebox_override("focus", sb)
	e.add_theme_color_override("font_color", Color(0.98, 0.95, 0.85))
	e.add_theme_color_override("caret_color", Color(1.0, 0.85, 0.5))
	e.add_theme_font_size_override("font_size", _gd(16))

func _stylize_textedit(t: TextEdit) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.045, 0.9)
	sb.border_color = Color(0.85, 0.66, 0.3, 0.6)
	sb.set_border_width_all(_gd(1))
	sb.set_corner_radius_all(_gd(8))
	sb.content_margin_left = _gd(12)
	sb.content_margin_right = _gd(12)
	sb.content_margin_top = _gd(10)
	sb.content_margin_bottom = _gd(10)
	t.add_theme_stylebox_override("normal", sb)
	t.add_theme_stylebox_override("focus", sb)
	t.add_theme_color_override("font_color", Color(0.98, 0.95, 0.85))
	t.add_theme_color_override("caret_color", Color(1.0, 0.85, 0.5))
	t.add_theme_font_size_override("font_size", _gd(16))

## Envoie la suggestion. Si le client est en ligne, la RPC part immédiatement vers
## le serveur qui l'écrit dans le fichier persistant. Sinon, on met en file
## d'attente locale, vidée à la prochaine connexion.
func _on_send() -> void:
	var pname := _name_input.text.strip_edges()
	var text := _msg_input.text.strip_edges()
	if text.is_empty():
		_status_label.text = _langs().t("suggest.message")
		return
	if pname.is_empty():
		pname = "Anonyme"

	var lobby := _lobby()
	if lobby.is_online and lobby.my_id > 0:
		lobby.submit_feedback(pname, text)
		_status_label.text = _langs().t("suggest.sent")
		_msg_input.text = ""
	else:
		_enqueue_local(pname, text)
		_status_label.text = _langs().t("suggest.sent") + " (hors ligne, envoi en attente)"

## File d'attente locale des suggestions hors ligne.
func _enqueue_local(pname: String, text: String) -> void:
	var arr: Array = []
	if FileAccess.file_exists(QUEUE_FILE):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(QUEUE_FILE))
		if data is Array:
			arr = data
	arr.append({"name": pname, "text": text, "ts": Time.get_unix_time_from_system()})
	var f := FileAccess.open(QUEUE_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(arr))

func _on_back() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)
