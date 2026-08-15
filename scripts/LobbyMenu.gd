extends Control
## LobbyMenu — écran de connexion multijoueur.
##
## Deux onglets :
##   - « Créer »   : nom de partie libre (généré si vide) + copier l'invitation.
##   - « Rejoindre » : saisie d'un code + liste des parties récentes cliquables.
## Puis : statut de connexion, liste des joueurs, chat, et « Lancer le jeu ».
##
## Les parties récentes sont mémorisées dans user://rooms.cfg (local).

const MAIN_SCENE := "res://scenes/Main.tscn"
const ROOMS_CFG := "user://rooms.cfg"
const SERVERS_JSON := "res://servers.json"

## Liste des serveurs officiels (modèle « royaumes » à la Call of Dragons) :
## chaque entrée = {"name", "subtitle", "transport", "address", "official"}.
var _servers: Array[Dictionary] = []

var _status_label: Label
var _name_input: LineEdit
var _create_code_input: LineEdit
var _join_code_input: LineEdit
var _recent_box: VBoxContainer
var _offline_button: Button

var _recent_rooms: Array[String] = []

## Gros bouton « Jouer » (serveur officiel).
var _btn: Button
## Boîte Aide / Comment jouer (repliable).
var _help_box: VBoxContainer
## État de repli de la section Aide.
var _help_visible: bool = false

## Lance le jeu automatiquement dès la connexion (création ou rejoindre).
var _auto_launch: bool = false

## Facteur d'échelle UI : >1 sur mobile pour des boutons/lecture nettement plus
## grands et lisibles. Défini dans _build_ui().
var _ui_scale: float = 1.0

## Taille de base des gros boutons (px de hauteur).
var _btn_h: int = 48
## Taille de base des champs de saisie (px de hauteur).
var _field_h: int = 40

func _gd(s: int) -> int:
	## Convertit une taille « desktop » en taille adaptée à l'échelle mobile.
	return int(round(s * _ui_scale))

func _ready() -> void:
	_load_recent_rooms()
	_load_servers()
	_build_ui()
	# Signaux de l'autoload Lobby (récupéré au runtime pour fiabilité).
	var lobby := _lobby()
	lobby.player_connected.connect(_on_player_connected)
	lobby.player_disconnected.connect(_on_player_disconnected)
	lobby.connection_status.connect(_on_status)
	lobby.server_disconnected.connect(_on_server_disconnected)
	lobby.roster_changed.connect(_on_roster_changed)
	_on_status("Prêt. Choisissez votre nom puis cliquez sur Jouer.")
	# Si on arrive via un lien (web) ou des args, on rejoint directement la room.
	_auto_join_from_entry()

## Accesseurs des autoloads via get_node : évite les erreurs « Identifier not
## found » au parse (l'analyseur ne connaît pas toujours les singletons selon
## l'ordre de chargement du cache de l'éditeur). Au runtime /root/Langs existe.
func _langs() -> Node:
	return get_node("/root/Langs")

func _lobby() -> Node:
	return get_node("/root/Lobby")

func _translator() -> Node:
	return get_node("/root/Translator")

## Rejoint automatiquement une room fournie par :
##  - un paramètre d'URL web « ?room=CODE » (via JavaScriptBridge),
##  - ou l'argument de ligne de commande « --room=CODE » (desktop).
## Cela permet qu'un lien navigateur fasse rejoindre n'importe quel joueur.
func _auto_join_from_entry() -> void:
	var is_server: bool = OS.get_cmdline_user_args().has("--server")
	# --host (ENet) ou --ws-host (WebSocket, serveur VPS) ⇒ ce process EST le serveur
	# et doit auto-lancer la partie dès que le réseau est prêt (pas rester au lobby).
	var is_host: bool = OS.get_cmdline_user_args().has("--host") \
		or OS.get_cmdline_user_args().has("--ws-host")
	var is_client_arg: bool = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--connect="):
			is_client_arg = true
			break
	# Mode auto-hébergé natif : --host / --connect lancent directement la partie
	# dès que le réseau est prêt (le lobby AUTOLOAD a déjà démarré le serveur).
	if is_host or is_client_arg:
		_auto_launch = true
		return
	var code := _url_param("room")
	if code.is_empty():
		# Fallback desktop : args du lancement (--room=XXXX).
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--room="):
				code = arg.trim_prefix("--room=").strip_edges()
				break
	# Un serveur dédié sans room précise rejoint une room publique par défaut,
	# pour que les joueurs le retrouvent toujours (partie partagée permanente).
	if code.is_empty() and is_server:
		code = "the-last-clan-officiel"
	if code.is_empty():
		return
	_on_status("Lien détecté : rejoint la partie « %s »…" % code)
	# On rejoint directement la room ; ensuite le joueur clique sur Jouer (ou la
	# partie se lance seule si --autostart / serveur dédié).
	_auto_launch = OS.has_feature("editor") and OS.get_cmdline_user_args().has("--autostart")
	_lobby().join_room(code)

## Lit un paramètre de l'URL web « ?cle=valeur ». Renvoie "" hors web.
func _url_param(key: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var query: String = JavaScriptBridge.get_interface("window").location.search
	if query.is_empty() or not query.begins_with("?"):
		return ""
	for pair in query.trim_prefix("?").split("&"):
		var kv := pair.split("=", true, 1)
		if kv.size() == 2 and kv[0] == key:
			return kv[1].uri_decode()
	return ""

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var vp_size := get_viewport_rect().size

	# Sur mobile (écran étroit), on agrandit fortement toute l'interface pour la
	# lisibilité : boutons plus hauts, police plus grande, champs plus épais.
	_ui_scale = 1.6 if vp_size.x < 720.0 else 1.0
	_btn_h = _gd(48)
	_field_h = _gd(46)

	# ---- Fond : dégradé sombre « royaume » + filet décoratif doré en haut.
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.07, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var glow := ColorRect.new()
	glow.color = Color(0.35, 0.24, 0.1)
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.modulate = Color(1, 1, 1, 0.28)
	add_child(glow)

	# ---- Contenu : panneau bois+or pleine largeur/hauteur.
	#     Une seule taille cohérente : marge selon la largeur d'écran.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad := 4.0 if vp_size.x < 720.0 else 18.0
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
	# Sur écran très large (>1200), on borne la largeur utile pour rester lisible.
	if vp_size.x >= 1200.0:
		panel.custom_minimum_size = Vector2(960.0, 0)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.13, 0.1, 0.075, 0.97)
	ps.border_color = Color(0.85, 0.66, 0.3, 0.9)
	ps.set_border_width_all(_gd(2))
	ps.corner_radius_top_left = _gd(14)
	ps.corner_radius_top_right = _gd(14)
	ps.corner_radius_bottom_left = _gd(14)
	ps.corner_radius_bottom_right = _gd(14)
	ps.content_margin_left = _gd(16)
	ps.content_margin_right = _gd(16)
	ps.content_margin_top = _gd(18)
	ps.content_margin_bottom = _gd(16)
	panel.add_theme_stylebox_override("panel", ps)
	outer.add_child(panel)

	# Défilable (remplit le panneau, évite la coupure sur petit écran mobile).
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", _gd(14))
	scroll.add_child(vb)

	# ---- En-tête : titre stylé.
	var title := Label.new()
	title.text = "The Last Clan"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", _gd(30))
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.03, 0.95))
	title.add_theme_constant_override("outline_size", _gd(4))
	vb.add_child(title)
	var tagline := Label.new()
	tagline.text = "Rejoignez votre clan et bâtissez votre royaume"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_size_override("font_size", _gd(14))
	tagline.add_theme_color_override("font_color", Color(0.85, 0.78, 0.6))
	tagline.add_theme_constant_override("outline_size", _gd(4))
	vb.add_child(tagline)

	# ---- Nom du joueur.
	vb.add_child(_field_label("Votre nom"))
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Entrez votre nom…"
	_name_input.text = _lobby().player_info.get("name", "Joueur")
	_name_input.custom_minimum_size = Vector2(0, _field_h)
	_stylize_field(_name_input)
	vb.add_child(_name_input)

	# ---- Langue de l'interface + du chat (international). Persiste via I18n.
	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", _gd(8))
	vb.add_child(lang_row)
	lang_row.add_child(_field_label(_langs().t("ui.chat") + " / Langue :"))
	var _lang = OptionButton.new()
	_lang.custom_minimum_size = Vector2(0, _gd(40))
	_lang.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stylize_button(_lang)
	for lang_code in _langs().available_languages():
		_lang.add_item("%s %s" % [_langs().code_to_flag(lang_code), _langs().lang_name(lang_code)])
		if lang_code == _langs().language:
			_lang.select(_lang.item_count - 1)
	_lang.item_selected.connect(_on_language_selected)
	lang_row.add_child(_lang)

	# ---- Actions principales (interface épurée : un seul gros « Jouer »).
	# Boutons empilés pleine largeur pour une utilisation simple au doigt.
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", _gd(12))
	vb.add_child(actions)

	# GROS bouton « Jouer » : rejoint le serveur officiel puis lance la partie.
	_btn = _big_button(_langs().t("ui.play"), _on_play_pressed, true)
	_btn.custom_minimum_size = Vector2(0, _gd(66))
	_btn.add_theme_font_size_override("font_size", _gd(26))
	_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_btn)

	# « Jouer hors ligne » : petit bouton secondaire en dessous.
	_offline_button = _big_button(_langs().t("ui.play_offline"), _on_offline_pressed, false)
	_offline_button.custom_minimum_size = Vector2(0, _gd(46))
	_offline_button.add_theme_font_size_override("font_size", _gd(15))
	_offline_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_offline_button)

	# ---- Aide / Comment jouer (repliable).
	var help_header := _big_button("❓ " + _langs().t("help.title"), _on_toggle_help, false)
	help_header.custom_minimum_size = Vector2(0, _gd(48))
	help_header.add_theme_font_size_override("font_size", _gd(16))
	help_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	vb.add_child(help_header)

	_help_box = VBoxContainer.new()
	_help_box.add_theme_constant_override("separation", _gd(8))
	vb.add_child(_help_box)
	var help_text := Label.new()
	help_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_text.add_theme_font_size_override("font_size", _gd(15))
	help_text.add_theme_color_override("font_color", Color(0.92, 0.88, 0.76))
	help_text.add_theme_stylebox_override("normal", _big_panel_box())
	var lines: Array[String] = [
		"• " + _langs().t("help.alpha"),
		"• " + _langs().t("help.objective"),
		"• " + _langs().t("help.howto"),
		"• " + _langs().t("help.suggest"),
	]
	help_text.text = "\n".join(lines)
	_help_box.add_child(help_text)
	_help_box.visible = _help_visible

	# ---- Suggestions (persistantes côté serveur).
	var suggest_btn := _big_button("💬 " + _langs().t("ui.suggest"), _open_suggestions, false)
	suggest_btn.custom_minimum_size = Vector2(0, _gd(50))
	suggest_btn.add_theme_font_size_override("font_size", _gd(18))
	suggest_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(suggest_btn)

	# ---- Statut de connexion.
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.6))
	_status_label.add_theme_font_size_override("font_size", _gd(15))
	_status_label.add_theme_constant_override("outline_size", _gd(4))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_status_label)

func _field_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.88, 0.82, 0.68))
	l.add_theme_constant_override("outline_size", _gd(4))
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.03, 0.9))
	l.add_theme_font_size_override("font_size", _gd(16))
	return l

## Crée un bouton « CTA » style CoC (bois sombre + liseré doré + police grasse).
func _big_button(text: String, handler: Callable, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, _btn_h)
	b.add_theme_font_size_override("font_size", _gd(17))
	b.pressed.connect(handler)
	_stylize_button(b)
	if primary:
		# Accent doré plus marqué pour l'action principale.
		var focus := StyleBoxFlat.new()
		focus.bg_color = Color(0.32, 0.24, 0.1, 1.0)
		focus.border_color = Color(1.0, 0.82, 0.4, 1.0)
		focus.set_border_width_all(_gd(2))
		focus.corner_radius_top_left = _gd(8)
		focus.corner_radius_top_right = _gd(8)
		focus.corner_radius_bottom_left = _gd(8)
		focus.corner_radius_bottom_right = _gd(8)
		focus.content_margin_left = _gd(12)
		focus.content_margin_right = _gd(12)
		focus.content_margin_top = _gd(6)
		focus.content_margin_bottom = _gd(6)
		b.add_theme_stylebox_override("normal", focus)
		b.add_theme_stylebox_override("hover", focus.duplicate())
		b.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	return b

## Applique le style CoC (bois + liseré doré) à un Button/OptionButton.
func _stylize_button(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.16, 0.12, 0.09, 0.94)
		sb.border_color = Color(0.85, 0.66, 0.3, 0.95)
		sb.set_border_width_all(_gd(2))
		sb.corner_radius_top_left = _gd(8)
		sb.corner_radius_top_right = _gd(8)
		sb.corner_radius_bottom_left = _gd(8)
		sb.corner_radius_bottom_right = _gd(8)
		sb.content_margin_left = _gd(12)
		sb.content_margin_right = _gd(12)
		sb.content_margin_top = _gd(6)
		sb.content_margin_bottom = _gd(6)
		if state == "hover" or state == "pressed":
			sb.bg_color = Color(0.28, 0.2, 0.13, 1.0)
			sb.border_color = Color(1.0, 0.8, 0.4, 1.0)
		if state == "pressed":
			sb.bg_color = Color(0.36, 0.26, 0.16, 1.0)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.9, 0.6))
	b.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.05, 0.95))
	b.add_theme_constant_override("outline_size", _gd(8))

## Style CoC pour les champs de saisie (LineEdit).
func _stylize_field(e: LineEdit) -> void:
	e.add_theme_stylebox_override("normal", _field_box(false))
	e.add_theme_stylebox_override("focus", _field_box(true))
	e.add_theme_color_override("font_color", Color(0.98, 0.95, 0.85))
	e.add_theme_color_override("font_placeholder_color", Color(0.6, 0.55, 0.45))
	e.add_theme_color_override("caret_color", Color(1.0, 0.85, 0.5))
	e.add_theme_constant_override("outline_size", _gd(4))
	e.add_theme_font_size_override("font_size", _gd(16))

func _field_box(focused: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.045, 0.9)
	sb.border_color = Color(0.85, 0.66, 0.3, 0.7 if focused else 0.45)
	sb.set_border_width_all(_gd(1 if not focused else 2))
	sb.corner_radius_top_left = _gd(8)
	sb.corner_radius_top_right = _gd(8)
	sb.corner_radius_bottom_left = _gd(8)
	sb.corner_radius_bottom_right = _gd(8)
	sb.content_margin_left = _gd(14)
	sb.content_margin_right = _gd(14)
	sb.content_margin_top = _gd(8)
	sb.content_margin_bottom = _gd(8)
	return sb

## Style CoC pour un panneau (chat, zone).
func _stylize_panel_container(c: Control) -> void:
	var box := _big_panel_box()
	c.add_theme_stylebox_override("panel", box)
	c.add_theme_stylebox_override("normal", box)

func _big_panel_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.045, 0.88)
	sb.border_color = Color(0.85, 0.66, 0.3, 0.5)
	sb.set_border_width_all(_gd(1))
	sb.corner_radius_top_left = _gd(8)
	sb.corner_radius_top_right = _gd(8)
	sb.corner_radius_bottom_left = _gd(8)
	sb.corner_radius_bottom_right = _gd(8)
	sb.content_margin_left = _gd(10)
	sb.content_margin_right = _gd(10)
	sb.content_margin_top = _gd(8)
	sb.content_margin_bottom = _gd(8)
	return sb

## --- Actions ---

func _on_create_pressed() -> void:
	_apply_name()
	var code := _create_code_input.text.strip_edges()
	if code.is_empty():
		code = _generate_code()
		_create_code_input.text = code
	_auto_launch = true
	_connect(code)

func _on_join_pressed() -> void:
	_apply_name()
	var code := _join_code_input.text.strip_edges()
	if code.is_empty():
		code = _create_code_input.text.strip_edges()
	if code.is_empty():
		_on_status("Entrez un code de partie pour rejoindre.")
		return
	_auto_launch = true
	_connect(code)

func _on_join_submitted(_text: String) -> void:
	_on_join_pressed()

func _on_recent_pressed(code: String) -> void:
	_join_code_input.text = code
	_auto_launch = true
	_connect(code)

func _connect(code: String) -> void:
	_remember_room(code)
	_lobby().join_room(code)

## Lance une 2e instance du jeu (nouvelle fenêtre) rejoignant la même room,
## pour tester le multijoueur localement (2 vrais clients sur le même réseau).
func _on_spawn_test_player() -> void:
	_apply_name()
	var code := _create_code_input.text.strip_edges()
	if code.is_empty():
		code = _generate_code()
		_create_code_input.text = code
	# Assure que CE joueur est bien connecté à la room avant d'en lancer un second.
	if not _lobby().is_online:
		_connect(code)
	_on_status("Lancement du 2e joueur (Joueur2) dans « %s »…" % code)
	var project_path := ProjectSettings.globalize_path("res://")
	# Le 2e joueur rejoint la room via les args --room / --name (gérés par Lobby).
	var args := PackedStringArray([
		"--path", project_path,
		"--", "--room=%s" % code, "--name=Joueur2",
	])
	var err := OS.create_process(OS.get_executable_path(), args)
	if err >= 0:
		_on_status("2e joueur lancé (pid %d). Cherchez la nouvelle fenêtre « Joueur2 »." % err)
	else:
		_on_status("Échec du lancement de la 2e instance (code %d)." % err)

func _on_copy_invite() -> void:
	var code: String = str(_lobby().room_id)
	if code.is_empty():
		code = _create_code_input.text.strip_edges()
	if code.is_empty():
		return
	DisplayServer.clipboard_set(code)
	_on_status("Invitation copiée : « %s »" % code)

func _generate_code() -> String:
	var chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var out := ""
	for i in 4:
		out += chars[randi() % chars.length()]
	return out

func _on_language_selected(index: int) -> void:
	var langs: Array = _langs().available_languages()
	if index >= 0 and index < langs.size():
		_langs().language = langs[index]
		_on_status("Langue : %s" % _langs().lang_name(_langs().language))

func _apply_name() -> void:
	var player_name := _name_input.text.strip_edges()
	if not player_name.is_empty():
		_lobby().player_info["name"] = player_name
	# Embarque la langue du joueur pour l'affichage international (roster/chat).
	_lobby().player_info["lang"] = _langs().language

func _on_launch_pressed() -> void:
	_auto_launch = false
	_launch_game()

## Passe le Lobby en mode hors ligne (base à l'origine, aucun réseau) puis lance
## immédiatement la partie en solo, sans attendre le relais.
func _on_offline_pressed() -> void:
	_apply_name()
	# Force un mode 100 % hors ligne : pas de WebSocket, base à l'origine.
	_lobby()._go_offline()
	_on_status("Mode hors ligne — lancement de la partie en solo…")
	_auto_launch = false
	_launch_game()

## Bascule vers la scène de jeu Main.tscn.
func _launch_game() -> void:
	_apply_name()
	get_tree().change_scene_to_file(MAIN_SCENE)

## « Jouer » : applique le nom, trouve le 1er (seul) serveur de servers.json puis
## se connecte à sa room officielle et lance la partie automatiquement.
func _on_play_pressed() -> void:
	_apply_name()
	_load_servers()
	if _servers.is_empty():
		_on_status("Aucun serveur officiel configuré (servers.json).")
		return
	var first: Dictionary = _servers[0]
	var transport := str(first.get("transport", "ws"))
	var address := str(first.get("address", ""))
	var room := str(first.get("room", ""))
	if address.is_empty():
		_on_status("Le serveur officiel n'a pas d'adresse configurée.")
		return
	_on_status("Connexion au royaume officiel « %s » (%s)…" % [room, address])
	_auto_launch = true
	_lobby().join_server(transport, address, room)

## Affiche / replie la section Aide / Comment jouer.
func _on_toggle_help() -> void:
	_help_visible = not _help_visible
	if _help_box != null:
		_help_box.visible = _help_visible

## Ouvre l'écran de suggestions persistantes (serveur).
func _open_suggestions() -> void:
	_apply_name()
	get_tree().change_scene_to_file("res://scenes/SuggestionMenu.tscn")

## --- Réactions aux signaux ---

func _on_player_connected(peer_id: int, _info: Dictionary) -> void:
	if _auto_launch and _lobby().is_online and peer_id == _lobby().my_id:
		_auto_launch = false
		_launch_game()

func _on_player_disconnected(_peer_id: int) -> void:
	pass

func _on_status(text: String) -> void:
	_status_label.text = text

func _on_server_disconnected() -> void:
	_on_status("Déconnecté du serveur.")

func _on_roster_changed() -> void:
	pass

## --- Parties récentes (mémoire locale) ---

func _load_recent_rooms() -> void:
	_recent_rooms.clear()
	var cfg := ConfigFile.new()
	if cfg.load(ROOMS_CFG) == OK:
		var arr: Array = cfg.get_value("saved", "rooms", [])
		for r in arr:
			_recent_rooms.append(str(r))

func _remember_room(code: String) -> void:
	if code.is_empty():
		return
	_recent_rooms.erase(code)
	_recent_rooms.push_front(code)
	# Garde les 10 dernières.
	while _recent_rooms.size() > 10:
		_recent_rooms.pop_back()
	var cfg := ConfigFile.new()
	cfg.set_value("saved", "rooms", _recent_rooms)
	cfg.save(ROOMS_CFG)
	_refresh_recent()

func _refresh_recent() -> void:
	if _recent_box == null:
		return
	for child in _recent_box.get_children():
		child.queue_free()
	for code in _recent_rooms:
		var b := Button.new()
		b.text = code
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, _gd(42))
		b.add_theme_font_size_override("font_size", _gd(16))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_stylize_button(b)
		b.pressed.connect(_on_recent_pressed.bind(code))
		_recent_box.add_child(b)

## --- Sélecteur de serveurs (modèle « royaumes ») ---

## Charge la liste des serveurs depuis servers.json (embarqué, modifiable).
func _load_servers() -> void:
	_servers.clear()
	if not FileAccess.file_exists(SERVERS_JSON):
		push_warning("Fichier de serveurs introuvable : %s" % SERVERS_JSON)
		return
	var f := FileAccess.open(SERVERS_JSON, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary and data.has("servers"):
		for s in data["servers"]:
			if s is Dictionary:
				_servers.append(s)

## Affiche le sélecteur de serveurs dans l'onglet « Serveurs ».
## Ajoute les boutons pour chaque serveur de la liste.
func _build_server_list(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()
	if _servers.is_empty():
		var none := Label.new()
		none.text = "Aucun serveur configuré."
		none.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		container.add_child(none)
		return
	for server in _servers:
		var sname := str(server.get("name", "Serveur"))
		var sub := str(server.get("subtitle", ""))
		var transport := str(server.get("transport", "enet"))
		var address := str(server.get("address", ""))
		var room := str(server.get("room", ""))
		var is_official: bool = bool(server.get("official", false))
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, _gd(56))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var badge := "★ " if is_official else "◆ "
		var label := badge + sname
		if not sub.is_empty():
			label += "\n      " + sub
		b.text = label
		b.add_theme_font_size_override("font_size", _gd(17))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = (transport.to_upper() + " — " + address)
		_stylize_button(b)
		b.pressed.connect(_on_server_pressed.bind(transport, address, room))
		container.add_child(b)

## Action : rejoint le serveur choisi et lance la partie.
## - transport "ziva" : royaume officiel sur le RELAIS Ziva — on rejoint la room
##   directement (tous les peers passent par le relais, aucun port à ouvrir).
## - transport "enet"/"ws" : serveur auto-hébergé (IP/domaine:port).
func _on_server_pressed(transport: String, address: String, room: String = "") -> void:
	_apply_name()
	if transport == "ziva":
		if room.is_empty():
			_on_status("Ce royaume n'a pas de room configurée.")
			return
		_on_status("Connexion au royaume « %s » (relais officiel)…" % room)
		_auto_launch = true
		_lobby().join_room(room)
		return
	if address.is_empty():
		_on_status("Ce serveur n'a pas d'adresse configurée.")
		return
	_on_status("Connexion au serveur « %s » (%s, royaume %s)…" % [address, transport, room])
	_auto_launch = true
	_lobby().join_server(transport, address, room)
