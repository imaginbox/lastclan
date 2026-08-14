extends Node
## Tests du MVP Saison 1 : internationalisation (I18n), chat multilingue
## (Translator), Clans (solo/autorité) et jauge « Sort du Royaume » (Realm).

# -----------------------------------------------------------------------------
# I18n — langue + traduction d'interface
# -----------------------------------------------------------------------------
func test_i18n_default_and_translate() -> void:
	var langs := preload("res://scripts/I18n.gd").new()
	# Sans fichier de réglage, on bascule sur la langue système (ou anglais).
	langs.language = "en"
	if langs.t("ui.play_offline") != "Play offline (solo)":
		push_error("CHECK FAILED: t() EN")
	langs.language = "fr"
	if langs.t("ui.play_offline") != "Jouer hors ligne (solo)":
		push_error("CHECK FAILED: t() FR : " + langs.t("ui.play_offline"))
	if langs.t("cle.inconnue") != "cle.inconnue":
		push_error("CHECK FAILED: fallback clé inconnue")
	# Drapeaux
	if langs.code_to_flag("fr") != "🇫🇷":
		push_error("CHECK FAILED: drapeau fr")

# -----------------------------------------------------------------------------
# Translator — chat multilingue (le message transporte sa langue source)
# -----------------------------------------------------------------------------
func test_translator_returns_original_when_inactive() -> void:
	var tr := preload("res://scripts/Translator.gd").new()
	tr.engine_active = false
	tr.language = "fr"
	var res := tr.translate("bonjour", "en")
	if res["auto"] != false or res["text"] != "bonjour":
		push_error("CHECK FAILED: moteur inactif doit renvoyer le texte original")

# -----------------------------------------------------------------------------
# Clans — création / membres / quitter (solo = autorité locale)
# -----------------------------------------------------------------------------
func test_clans_solo_create_join_leave() -> void:
	var cl := preload("res://scripts/Clans.gd").new()
	cl.name = "Clans"
	add_child(cl)
	# En solo (pas de Lobby réseau actif), l'autorité est locale.
	cl.create_clan("Les Loups", "LOUP", 0)
	if not cl.clans.has("LOUP"):
		push_error("CHECK FAILED: clan LOUP non créé")
	if cl.my_clan != "LOUP":
		push_error("CHECK FAILED: my_clan pas LOUP")
	if cl.my_clan_name() != "Les Loups":
		push_error("CHECK FAILED: nom du clan")
	# Les membres d'un clan : le créateur est leader.
	var c: Dictionary = cl.clans["LOUP"]
	if int(c.get("leader", -1)) <= 0:
		push_error("CHECK FAILED: leader invalide")
	# Quitter libère l'appartenance.
	cl.leave_clan()
	if cl.my_clan != "":
		push_error("CHECK FAILED: quitter clan n'a pas libéré my_clan")
	cl.queue_free()

func test_clans_duplicate_tag_rejected() -> void:
	var cl := preload("res://scripts/Clans.gd").new()
	cl.name = "Clans"
	add_child(cl)
	cl.create_clan("A", "AAA", 0)
	# Deuxième clan avec le même tag (minuscules) doit être refusé (normalisé maj).
	cl.create_clan("B", "aaa", 1)
	if cl.clans.size() != 1:
		push_error("CHECK FAILED: tag dupliqué accepté (%d)" % cl.clans.size())
	cl.queue_free()

# -----------------------------------------------------------------------------
# Realm — jauge « Sort du Royaume »
# -----------------------------------------------------------------------------
func test_realm_bounds_and_zone() -> void:
	var r := preload("res://scripts/Realm.gd").new()
	r.value = 50.0
	if r.zone() != "stable":
		push_error("CHECK FAILED: zone 50 -> stable")
	r.value = 80.0
	if r.zone() != "prosperity":
		push_error("CHECK FAILED: zone 80 -> prosperity")
	r.value = 10.0
	if r.zone() != "decline":
		push_error("CHECK FAILED: zone 10 -> decline")
	# L'activité borne la valeur à [0,100].
	r.activity(1000.0)
	if r.value > 100.0:
		push_error("CHECK FAILED: valeur > 100")
	r.activity(-5000.0)
	if r.value < 0.0:
		push_error("CHECK FAILED: valeur < 0")
