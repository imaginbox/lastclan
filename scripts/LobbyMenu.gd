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
var _players_box: VBoxContainer
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _launch_button: Button
var _name_input: LineEdit
var _create_code_input: LineEdit
var _join_code_input: LineEdit
var _recent_box: VBoxContainer
var _invite_button: Button
var _offline_button: Button
var _servers_box: VBoxContainer

var _recent_rooms: Array[String] = []

## Lance le jeu automatiquement dès la connexion (création ou rejoindre).
var _auto_launch: bool = false

func _ready() -> void:
	_load_recent_rooms()
	_load_servers()
	_build_ui()
	# Signaux de l'autoload Lobby.
	Lobby.player_connected.connect(_on_player_connected)
	Lobby.player_disconnected.connect(_on_player_disconnected)
	Lobby.connection_status.connect(_on_status)
	Lobby.chat_received.connect(_on_chat)
	Lobby.server_disconnected.connect(_on_server_disconnected)
	Lobby.roster_changed.connect(_on_roster_changed)
	_on_status("Prêt. Créez ou rejoignez une partie.")
	_refresh_players()
	_refresh_recent()
	# Si on arrive via un lien (web) ou des args, on rejoint directement la room.
	_auto_join_from_entry()

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
	_join_code_input.text = code
	# En éditeur, le `--room` ne fait que pré-remplir le champ (l'utilisateur
	# valide lui-même), SAUF si `--autostart` est fourni : permet d'automatiser
	# un vrai test multijoueur en lançant plusieurs clients en ligne de commande
	# qui rejoignent ET lancent la partie sans aucune interaction. Le serveur
	# dédié, lui, lance toujours la partie automatiquement.
	if OS.has_feature("editor") and not OS.get_cmdline_user_args().has("--autostart") and not is_server:
		_on_status("Lien détecté : « %s ». Cliquez sur Rejoindre." % code)
		return
	_auto_launch = true
	_connect(code)

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

	# ---- Contenu centré, largeur responsive (mobile plein, PC ~640 max).
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var panel_w := clampf(vp_size.x * 0.94, 300.0, 640.0)
	panel.custom_minimum_size = Vector2(panel_w, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_END
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.13, 0.1, 0.075, 0.96)
	ps.border_color = Color(0.85, 0.66, 0.3, 0.9)
	ps.set_border_width_all(2)
	ps.corner_radius_top_left = 14
	ps.corner_radius_top_right = 14
	ps.corner_radius_bottom_left = 14
	ps.corner_radius_bottom_right = 14
	ps.content_margin_left = 20
	ps.content_margin_right = 20
	ps.content_margin_top = 22
	ps.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	# Défilable (évite la coupure sur petit écran mobile).
	var scroll_h := maxf(340.0, vp_size.y * 0.86)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, scroll_h)
	panel.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 14)
	scroll.add_child(vb)

	# ---- En-tête : titre stylé.
	var title := Label.new()
	title.text = "The Last Clan"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.03, 0.95))
	title.add_theme_constant_override("outline_size", 10)
	vb.add_child(title)
	var tagline := Label.new()
	tagline.text = "Rejoignez votre clan et bâtissez votre royaume"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_size_override("font_size", 14)
	tagline.add_theme_color_override("font_color", Color(0.85, 0.78, 0.6))
	tagline.add_theme_constant_override("outline_size", 4)
	vb.add_child(tagline)

	# ---- Nom du joueur.
	vb.add_child(_field_label("Votre nom"))
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Entrez votre nom…"
	_name_input.text = Lobby.player_info.get("name", "Joueur")
	_name_input.custom_minimum_size = Vector2(0, 42)
	_stylize_field(_name_input)
	vb.add_child(_name_input)

	# ---- Langue de l'interface + du chat (international). Persiste via I18n.
	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 8)
	vb.add_child(lang_row)
	lang_row.add_child(_field_label(Langs.t("ui.chat") + " / Langue :"))
	var _lang = OptionButton.new()
	_lang.custom_minimum_size = Vector2(0, 38)
	_lang.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stylize_button(_lang)
	for lang_code in Langs.available_languages():
		_lang.add_item("%s %s" % [Langs.code_to_flag(lang_code), Langs.lang_name(lang_code)])
		if lang_code == Langs.language:
			_lang.select(_lang.item_count - 1)
	_lang.item_selected.connect(_on_language_selected)
	lang_row.add_child(_lang)

	# ---- Actions principales (gros boutons « jouer »).
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	vb.add_child(action_row)
	_offline_button = _big_button("Jouer hors ligne", _on_offline_pressed, true)
	_offline_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(_offline_button)
	_launch_button = _big_button("Lancer le jeu", _on_launch_pressed, false)
	_launch_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(_launch_button)

	# ---- Sélecteur de serveurs (modèle « royaumes »).
	vb.add_child(_field_label("Choisir un royaume"))
	_servers_box = VBoxContainer.new()
	_servers_box.add_theme_constant_override("separation", 8)
	vb.add_child(_servers_box)
	_build_server_list(_servers_box)

	# ---- Créer / Rejoindre.
	var grid := GridContainer.new()
	grid.columns = (2 if (vp_size.x >= 560 and vp_size.x > vp_size.y) else 1)
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vb.add_child(grid)

	# --- Colonne Créer ---
	var create_card := VBoxContainer.new()
	create_card.add_theme_constant_override("separation", 8)
	grid.add_child(create_card)
	var create_title := Label.new()
	create_title.text = "Créer une partie"
	create_title.add_theme_font_size_override("font_size", 18)
	create_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	create_card.add_child(create_title)
	_create_code_input = LineEdit.new()
	_create_code_input.placeholder_text = "Nom (vide = auto)"
	_create_code_input.custom_minimum_size = Vector2(0, 40)
	_stylize_field(_create_code_input)
	create_card.add_child(_create_code_input)
	var create_btn := _big_button("Créer et lancer", _on_create_pressed, true)
	create_card.add_child(create_btn)
	_invite_button = _big_button("Copier l'invitation", _on_copy_invite, false)
	_invite_button.disabled = true
	_invite_button.custom_minimum_size = Vector2(0, 44)
	create_card.add_child(_invite_button)
	if OS.has_feature("editor"):
		var test_btn := _big_button("Lancer un 2e joueur (test)", _on_spawn_test_player, false)
		test_btn.custom_minimum_size = Vector2(0, 40)
		create_card.add_child(test_btn)

	# --- Colonne Rejoindre ---
	var join_card := VBoxContainer.new()
	join_card.add_theme_constant_override("separation", 8)
	grid.add_child(join_card)
	var join_title := Label.new()
	join_title.text = "Rejoindre une partie"
	join_title.add_theme_font_size_override("font_size", 18)
	join_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	join_card.add_child(join_title)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	join_card.add_child(join_row)
	_join_code_input = LineEdit.new()
	_join_code_input.placeholder_text = "Code de la partie"
	_join_code_input.custom_minimum_size = Vector2(0, 40)
	_join_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_code_input.text_submitted.connect(_on_join_submitted)
	_stylize_field(_join_code_input)
	join_row.add_child(_join_code_input)
	var join_btn := _big_button("Rejoindre", _on_join_pressed, true)
	join_btn.custom_minimum_size = Vector2(0, 40)
	join_row.add_child(join_btn)
	join_card.add_child(_field_label("Parties récentes"))
	_recent_box = VBoxContainer.new()
	_recent_box.add_theme_constant_override("separation", 6)
	join_card.add_child(_recent_box)

	# ---- Statut de connexion.
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.6))
	_status_label.add_theme_font_size_override("font_size", 15)
	_status_label.add_theme_constant_override("outline_size", 4)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_status_label)

	# ---- Joueurs (compact).
	vb.add_child(_field_label("Joueurs dans la partie"))
	var players_scroll := ScrollContainer.new()
	players_scroll.custom_minimum_size = Vector2(0, 70)
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 4)
	_players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_scroll.add_child(_players_box)
	vb.add_child(players_scroll)

	# ---- Chat (compact, replié en liste).
	vb.add_child(_field_label("Chat"))
	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = true
	_chat_log.custom_minimum_size = Vector2(0, 110)
	_chat_log.scroll_following = true
	_stylize_panel_container(_chat_log)
	vb.add_child(_chat_log)
	var chat_row := HBoxContainer.new()
	chat_row.add_theme_constant_override("separation", 8)
	vb.add_child(chat_row)
	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Écrivez un message…"
	_chat_input.custom_minimum_size = Vector2(0, 40)
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.text_submitted.connect(_on_chat_submitted)
	_stylize_field(_chat_input)
	chat_row.add_child(_chat_input)
	var send_btn := _big_button("Envoyer", _on_chat_send, true)
	send_btn.custom_minimum_size = Vector2(0, 40)
	chat_row.add_child(send_btn)

func _field_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.88, 0.82, 0.68))
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.03, 0.9))
	return l

## Crée un bouton « CTA » style CoC (bois sombre + liseré doré + police grasse).
func _big_button(text: String, handler: Callable, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(handler)
	_stylize_button(b)
	if primary:
		# Accent doré plus marqué pour l'action principale.
		var focus := StyleBoxFlat.new()
		focus.bg_color = Color(0.32, 0.24, 0.1, 1.0)
		focus.border_color = Color(1.0, 0.82, 0.4, 1.0)
		focus.set_border_width_all(2)
		focus.corner_radius_top_left = 8
		focus.corner_radius_top_right = 8
		focus.corner_radius_bottom_left = 8
		focus.corner_radius_bottom_right = 8
		focus.content_margin_left = 10
		focus.content_margin_right = 10
		focus.content_margin_top = 4
		focus.content_margin_bottom = 4
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
		sb.set_border_width_all(2)
		sb.corner_radius_top_left = 8
		sb.corner_radius_top_right = 8
		sb.corner_radius_bottom_left = 8
		sb.corner_radius_bottom_right = 8
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
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
	b.add_theme_constant_override("outline_size", 8)

## Style CoC pour les champs de saisie (LineEdit).
func _stylize_field(e: LineEdit) -> void:
	e.add_theme_stylebox_override("normal", _field_box(false))
	e.add_theme_stylebox_override("focus", _field_box(true))
	e.add_theme_color_override("font_color", Color(0.98, 0.95, 0.85))
	e.add_theme_color_override("font_placeholder_color", Color(0.6, 0.55, 0.45))
	e.add_theme_color_override("caret_color", Color(1.0, 0.85, 0.5))
	e.add_theme_constant_override("outline_size", 4)

func _field_box(focused: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.045, 0.9)
	sb.border_color = Color(0.85, 0.66, 0.3, 0.7 if focused else 0.45)
	sb.set_border_width_all(1 if not focused else 2)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
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
	sb.set_border_width_all(1)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
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
	Lobby.join_room(code)

## Lance une 2e instance du jeu (nouvelle fenêtre) rejoignant la même room,
## pour tester le multijoueur localement (2 vrais clients sur le même réseau).
func _on_spawn_test_player() -> void:
	_apply_name()
	var code := _create_code_input.text.strip_edges()
	if code.is_empty():
		code = _generate_code()
		_create_code_input.text = code
	# Assure que CE joueur est bien connecté à la room avant d'en lancer un second.
	if not Lobby.is_online:
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
	var code := Lobby.room_id
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
	var langs := Langs.available_languages()
	if index >= 0 and index < langs.size():
		Langs.language = langs[index]
		_on_status("Langue : %s" % Langs.lang_name(Langs.language))

func _apply_name() -> void:
	var player_name := _name_input.text.strip_edges()
	if not player_name.is_empty():
		Lobby.player_info["name"] = player_name
	# Embarque la langue du joueur pour l'affichage international (roster/chat).
	Lobby.player_info["lang"] = Langs.language

func _on_chat_send() -> void:
	_send_chat_text()

func _on_chat_submitted(_text: String) -> void:
	_send_chat_text()

func _send_chat_text() -> void:
	var text := _chat_input.text
	if text.strip_edges().is_empty():
		return
	Lobby.send_chat(text)
	_chat_input.clear()
	_chat_input.grab_focus()

func _on_launch_pressed() -> void:
	_auto_launch = false
	_launch_game()

## Passe le Lobby en mode hors ligne (base à l'origine, aucun réseau) puis lance
## immédiatement la partie en solo, sans attendre le relais.
func _on_offline_pressed() -> void:
	_apply_name()
	# Force un mode 100 % hors ligne : pas de WebSocket, base à l'origine.
	Lobby._go_offline()
	_on_status("Mode hors ligne — lancement de la partie en solo…")
	_auto_launch = false
	_launch_game()

## Bascule vers la scène de jeu Main.tscn.
func _launch_game() -> void:
	_apply_name()
	get_tree().change_scene_to_file(MAIN_SCENE)

## --- Réactions aux signaux ---

func _on_player_connected(peer_id: int, _info: Dictionary) -> void:
	_refresh_players()
	_update_launch()
	if _auto_launch and Lobby.is_online and peer_id == Lobby.my_id:
		_auto_launch = false
		_launch_game()

func _on_player_disconnected(_peer_id: int) -> void:
	_refresh_players()

func _on_status(text: String) -> void:
	_status_label.text = text
	# Dès qu'on est connecté, on active la copie d'invitation.
	if Lobby.is_online and not Lobby.room_id.is_empty():
		_invite_button.disabled = false

func _on_server_disconnected() -> void:
	_refresh_players()
	_update_launch()

func _on_roster_changed() -> void:
	_refresh_players()
	_update_launch()

func _on_chat(author: String, text: String, src_lang: String = "en") -> void:
	# Chat international : on affiche dans la langue du joueur via le moteur de
	# traduction (Translator). Tant que le moteur est inactif, texte original.
	var res := Translator.translate(text, src_lang)
	var shown: String = res["text"]
	var flag := Langs.code_to_flag(src_lang)
	if res["auto"]:
		_chat_log.append_text("[b]%s[/b] %s : %s  [i](%s)[/i]\n" % [flag, author, shown, Langs.lang_name(src_lang)])
	else:
		_chat_log.append_text("[b]%s[/b] %s : %s\n" % [flag, author, shown])

func _refresh_players() -> void:
	for child in _players_box.get_children():
		child.queue_free()
	var ids: Array = Lobby.players.keys()
	ids.sort()
	for id in ids:
		var info: Dictionary = Lobby.players[id]
		var pname := str(info.get("name", "Joueur %d" % id))
		var me := " (vous)" if (Lobby.is_online and id == Lobby.my_id) else ""
		var l := Label.new()
		l.text = "• %s%s" % [pname, me]
		_players_box.add_child(l)

func _update_launch() -> void:
	_launch_button.disabled = not Lobby.is_online

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
		b.custom_minimum_size = Vector2(0, 40)
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
		b.custom_minimum_size = Vector2(0, 48)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var badge := "★ " if is_official else "◆ "
		var label := badge + sname
		if not sub.is_empty():
			label += "\n      " + sub
		b.text = label
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
		Lobby.join_room(room)
		return
	if address.is_empty():
		_on_status("Ce serveur n'a pas d'adresse configurée.")
		return
	_on_status("Connexion au serveur « %s » (%s, royaume %s)…" % [address, transport, room])
	_auto_launch = true
	Lobby.join_server(transport, address, room)
