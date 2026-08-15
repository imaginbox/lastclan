class_name AdminMenu
extends Control

## AdminMenu — panneau d'administration protégé par mot de passe.
##
## Le panneau est RÉGÉNÉRÉ à partir du registre de GameConfig : chaque paramètre
## déclaré dans GameConfig.REGISTRY apparaît automatiquement ici (catégorie ->
## section -> SpinBox/LineEdit). Ajouter un paramètre dans GameConfig suffit pour
## le rendre éditable — pas de code d'UI à écrire.
##
## Accès : depuis le lobby, via une petite icône cadenas (voir LobbyMenu). Un mot
## de passe (paramètre admin.mot_de_passe, défaut "lastclan") est demandé.

const LOBBY_SCENE := "res://scenes/LobbyMenu.tscn"

const _ui_scale := 1.6
## Borne du nombre de contrôles par section (alias pour lisibilité).
const _gd := 1.6

var _unlocked: bool = false
var _pw_input: LineEdit
var _pw_status: Label
var _status: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if _check_autoload():
		_show_password_gate()

func _gc() -> Node:
	return get_node("/root/GameConfig")

func _check_autoload() -> bool:
	if get_node_or_null("/root/GameConfig") == null:
		return false
	return true

## ---------------------------------------------------------------------------
## Écran 1 : demande du mot de passe.
## ---------------------------------------------------------------------------
func _show_password_gate() -> void:
	for c in get_children():
		c.queue_free()

	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := int(24 * _ui_scale)
	outer.add_theme_constant_override("margin_left", m)
	outer.add_theme_constant_override("margin_right", m)
	outer.add_theme_constant_override("margin_top", m)
	outer.add_theme_constant_override("margin_bottom", m)
	add_child(outer)

	var center := CenterContainer.new()
	outer.add_child(center)

	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.13, 0.1, 0.075, 0.98)
	ps.border_color = Color(0.85, 0.66, 0.3, 0.95)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(14)
	ps.content_margin_left = _px(24)
	ps.content_margin_right = _px(24)
	ps.content_margin_top = _px(26)
	ps.content_margin_bottom = _px(24)
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", _px(14))
	panel.add_child(vb)

	var lock := Label.new()
	lock.text = "ADMINISTRATION"
	lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock.add_theme_font_size_override("font_size", _px(26))
	lock.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	lock.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.03, 0.95))
	lock.add_theme_constant_override("outline_size", 4)
	vb.add_child(lock)

	var sub := Label.new()
	sub.text = "Mode réservé — configuration du gameplay"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", _px(15))
	sub.add_theme_color_override("font_color", Color(0.85, 0.78, 0.6))
	vb.add_child(sub)

	_pw_input = LineEdit.new()
	_pw_input.name = "PasswordField"
	_pw_input.placeholder_text = "Mot de passe"
	_pw_input.secret = true
	_pw_input.custom_minimum_size = Vector2(_px(220), _px(46))
	_pw_input.text_submitted.connect(_on_pw_submit)
	_stylize_field(_pw_input)
	vb.add_child(_pw_input)

	_pw_status = Label.new()
	_pw_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pw_status.add_theme_font_size_override("font_size", _px(15))
	_pw_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	_pw_status.text = ""
	vb.add_child(_pw_status)

	var ok := _make_button("Ouvrir", _on_pw_ok)
	ok.name = "OuvrirButton"
	ok.custom_minimum_size = Vector2(0, _px(46))
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(ok)

	var back := _make_button("Retour", _on_back)
	back.custom_minimum_size = Vector2(0, _px(40))
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(back)

	_pw_input.grab_focus()

func _on_pw_submit(_t: String) -> void:
	_on_pw_ok()

func _on_pw_ok() -> void:
	var want: String = str(_gc().get_value("admin.mot_de_passe"))
	var got := _pw_input.text.strip_edges()
	if got == want:
		_unlocked = true
		_show_panel()
	else:
		_pw_status.text = "Mot de passe incorrect"
		_pw_input.text = ""
		_pw_input.grab_focus()

func _on_back() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)

## ---------------------------------------------------------------------------
## Écran 2 : panneau de configuration généré depuis le registre.
## ---------------------------------------------------------------------------
func _show_panel() -> void:
	for c in get_children():
		c.queue_free()

	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := int(8 * _ui_scale)
	outer.add_theme_constant_override("margin_left", m)
	outer.add_theme_constant_override("margin_right", m)
	outer.add_theme_constant_override("margin_top", m)
	outer.add_theme_constant_override("margin_bottom", m)
	add_child(outer)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.11, 0.085, 0.06, 0.99)
	ps.border_color = Color(0.85, 0.66, 0.3, 0.95)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(12)
	ps.content_margin_left = _px(14)
	ps.content_margin_right = _px(14)
	ps.content_margin_top = _px(14)
	ps.content_margin_bottom = _px(14)
	panel.add_theme_stylebox_override("panel", ps)
	outer.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", _px(10))
	panel.add_child(vb)

	# Titre + barre d'actions (haut) : colonne fixe.
	var title := Label.new()
	title.text = "ADMINISTRATION — CONFIGURATION DU JEU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", _px(20))
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.03, 0.95))
	title.add_theme_constant_override("outline_size", 3)
	vb.add_child(title)

	var hint := Label.new()
	hint.text = "Règle les valeurs puis « Appliquer et enregistrer ». Elles sont persistées."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", _px(13))
	hint.add_theme_color_override("font_color", Color(0.82, 0.76, 0.6))
	vb.add_child(hint)

	# Zone des onglets (un onglet par catégorie). Le contenu de chaque onglet
	# est une colonne scrollable avec l'explication de la catégorie en tête.
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size = Vector2(0, _px(120))
	# Style des onglets (bois + doré).
	var tab_bar: TabBar = tabs.get_tab_bar()
	if tab_bar != null:
		tab_bar.add_theme_font_size_override("font_size", _px(15))
		tab_bar.add_theme_stylebox_override("tab_unselected", _tab_style(Color(0.14, 0.1, 0.07, 0.9)))
		tab_bar.add_theme_stylebox_override("tab_selected", _tab_style(Color(0.24, 0.17, 0.1, 1.0)))
		tab_bar.add_theme_color_override("font_unselected_color", Color(0.85, 0.78, 0.6))
		tab_bar.add_theme_color_override("font_selected_color", Color(1.0, 0.9, 0.65))
	vb.add_child(tabs)

	_build_tabs(tabs)

	# Label de statut (retours "appliqué / réinitialisé").
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", _px(13))
	_status.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_status.text = ""
	vb.add_child(_status)

	# Barre d'actions (bas).
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", _px(8))
	vb.add_child(actions)

	var apply := _make_button("APPLIQUER ET SAUVEGARDER", _on_apply)
	apply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply.custom_minimum_size = Vector2(0, _px(46))
	actions.add_child(apply)

	var reset := _make_button("Réinitialiser", _on_reset)
	reset.custom_minimum_size = Vector2(0, _px(46))
	actions.add_child(reset)

	var back := _make_button("Fermer", _on_back)
	back.custom_minimum_size = Vector2(0, _px(46))
	actions.add_child(back)

## Construit un onglet par catégorie du registre, avec son explication.
func _build_tabs(tabs: TabContainer) -> void:
	var gc := _gc()
	var first := true
	for cat in gc.categories():
		var cat_name := String(cat)
		var tab_root := PanelContainer.new()
		var ts := StyleBoxFlat.new()
		ts.bg_color = Color(0.07, 0.05, 0.035, 0.8)
		ts.set_corner_radius_all(6)
		ts.content_margin_left = _px(10)
		ts.content_margin_right = _px(10)
		ts.content_margin_top = _px(10)
		ts.content_margin_bottom = _px(10)
		tab_root.add_theme_stylebox_override("panel", ts)
		tabs.add_child(tab_root)
		tabs.set_tab_title(tabs.get_tab_count() - 1, cat_name)

		var tvb := VBoxContainer.new()
		tvb.add_theme_constant_override("separation", _px(8))
		tab_root.add_child(tvb)

		# Explication de la catégorie.
		var desc := Label.new()
		desc.text = gc.category_desc(cat_name)
		if desc.text.is_empty():
			desc.text = "Réglages de la catégorie « %s »." % cat_name
		desc.add_theme_font_size_override("font_size", _px(13))
		desc.add_theme_color_override("font_color", Color(0.66, 0.78, 0.74))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tvb.add_child(desc)

		# Colonne scrollable des paramètres.
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tvb.add_child(scroll)

		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", _px(8))
		scroll.add_child(col)

		for p in gc.params_in_cat(cat):
			col.add_child(_make_param_row(cat_name, p))

		if first:
			tabs.current_tab = 0
			first = false

func _make_param_row(_cat: String, p: Dictionary) -> Control:
	var gc := _gc()
	var key := String(p["key"])

	# Enveloppe verticale : ligne (label + contrôle) + aide explicative.
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 2)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _px(8))
	cell.add_child(row)

	var keylabel := Label.new()
	keylabel.text = String(p["label"])
	keylabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keylabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keylabel.add_theme_font_size_override("font_size", _px(14))
	keylabel.add_theme_color_override("font_color", Color(0.9, 0.86, 0.74))
	keylabel.custom_minimum_size = Vector2(_px(200), 0)
	row.add_child(keylabel)

	var kind: int = int(p["kind"])
	if kind == GameConfig.Kind.STRING:
		var le := LineEdit.new()
		le.text = str(gc.get_value(key))
		le.custom_minimum_size = Vector2(_px(180), _px(38))
		_stylize_field(le)
		le.text_submitted.connect(func(_t: String, k: String = key) -> void:
			gc.set_value(k, _t)
		)
		row.add_child(le)
		_add_param_help(cell, gc, key)
		return cell

	# SpinBox pour INT/FLOAT/BOOL (BOOL traité comme INT 0/1 via checkbox):
	if kind == GameConfig.Kind.BOOL:
		var cb := CheckBox.new()
		cb.text = "Activé"
		cb.button_pressed = bool(gc.get_value(key))
		cb.add_theme_font_size_override("font_size", _px(14))
		cb.pressed.connect(func(k: String = key, c: CheckBox = cb) -> void:
			gc.set_value(k, c.button_pressed)
		)
		row.add_child(cb)
		_add_param_help(cell, gc, key)
		return cell

	var sb := SpinBox.new()
	sb.min_value = p.get("min", 0)
	sb.max_value = p.get("max", 99999)
	sb.step = p.get("step", 1.0)
	sb.value = float(gc.get_value(key))
	sb.custom_minimum_size = Vector2(_px(170), _px(38))
	var fmt: int = 2 if kind == GameConfig.Kind.FLOAT else 0
	sb.value_changed.connect(func(v: float, k: String = key, _f: int = fmt) -> void:
		gc.set_value(k, v)
	)
	row.add_child(sb)
	_add_param_help(cell, gc, key)
	return cell

## Ajoute une petite ligne d'aide sous le paramètre (si GameConfig en déclare une).
func _add_param_help(cell: VBoxContainer, gc: Node, key: String) -> void:
	var text: String = gc.param_desc(key)
	if text.is_empty():
		return
	var help := Label.new()
	help.text = text
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", _px(11))
	help.add_theme_color_override("font_color", Color(0.62, 0.65, 0.55))
	cell.add_child(help)

func _on_apply() -> void:
	# Dès qu'une valeur change, set_value() persiste déjà ; ce bouton force une
	# sauvegarde propre et renvoie un retour.
	_gc().save()
	_notify("Configuration appliquée et enregistrée !")

func _on_reset() -> void:
	_gc().reset()
	_gc().save()
	_show_panel()
	_notify("Réglages réinitialisés aux valeurs par défaut.")

func _notify(t: String) -> void:
	if _status != null:
		_status.text = t

## Aide visuelle : scalent px selon l'échelle d'UI du lobby (1.6 mobile).
func _px(v: int) -> int:
	return int(round(v * _ui_scale))

func _make_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	_stylize_button(b)
	return b

func _stylize_button(b: Button) -> void:
	b.add_theme_font_size_override("font_size", _px(15))
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.16, 0.12, 0.09, 0.94)
		sb.border_color = Color(0.85, 0.66, 0.3, 0.95)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = _px(12)
		sb.content_margin_right = _px(12)
		sb.content_margin_top = _px(8)
		sb.content_margin_bottom = _px(8)
		if state == "hover" or state == "pressed":
			sb.bg_color = Color(0.28, 0.2, 0.13, 1.0)
			sb.border_color = Color(1.0, 0.8, 0.4, 1.0)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.05, 0.95))
	b.add_theme_constant_override("outline_size", 6)

func _stylize_field(e: LineEdit) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.045, 0.9)
	sb.border_color = Color(0.85, 0.66, 0.3, 0.45)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = _px(12)
	sb.content_margin_right = _px(12)
	sb.content_margin_top = _px(8)
	sb.content_margin_bottom = _px(8)
	e.add_theme_stylebox_override("normal", sb)
	e.add_theme_stylebox_override("focus", sb)
	e.add_theme_color_override("font_color", Color(0.98, 0.95, 0.85))
	e.add_theme_color_override("caret_color", Color(1.0, 0.85, 0.5))
	e.add_theme_color_override("font_placeholder_color", Color(0.6, 0.55, 0.45))
	e.add_theme_font_size_override("font_size", _px(15))

## Style des onglets (TabBar) : bois foncé avec liseré doré.
func _tab_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(0.85, 0.66, 0.3, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = _px(14)
	sb.content_margin_right = _px(14)
	sb.content_margin_top = _px(7)
	sb.content_margin_bottom = _px(7)
	return sb
