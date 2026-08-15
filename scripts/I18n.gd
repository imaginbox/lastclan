extends Node
## I18n — autoload de gestion des langues.
##
## Rôles :
##   - Détecte la langue du joueur (OS en 1er choix, stockée ensuite dans
##     user://settings.cfg pour persistance).
##   - Fournit I18n.t("key") pour traduire les chaînes d'interface.
##   - Fournit I18n.code_to_flag(lang) / I18n.lang_name(lang) pour afficher
##     le drapeau / le nom natif d'une langue dans le chat.
##   - C'est la couche sur laquelle on branchera le MOTEUR DE TRADUCTION
##     automatique du chat (chaque message porte déjà sa langue source).
##
## Langues initiales supportées (extensibles) :
##   fr, en, es, de, it, pt, ar, zh, ja, ru
class_name I18n

## Langue actuelle de l'interface (BPC 2 lettres, ex "fr", "en").
var language: String = "en" :
	set(v):
		language = v
		_settings_save()
		language_changed.emit(language)

signal language_changed(lang: String)

## Langues supportées + drapeau (emoji) + nom natif + auto-traduction dispo.
const SUPPORTED: Dictionary = {
	"fr": {"flag": "🇫🇷", "name": "Français"},
	"en": {"flag": "🇬🇧", "name": "English"},
	"es": {"flag": "🇪🇸", "name": "Español"},
	"de": {"flag": "🇩🇪", "name": "Deutsch"},
	"it": {"flag": "🇮🇹", "name": "Italiano"},
	"pt": {"flag": "🇵🇹", "name": "Português"},
	"ar": {"flag": "🇸🇦", "name": "العربية"},
	"zh": {"flag": "🇨🇳", "name": "中文"},
	"ja": {"flag": "🇯🇵", "name": "日本語"},
	"ru": {"flag": "🇷🇺", "name": "Русский"},
}

## Dictionnaire clé -> { lang: texte }. Extensible.
const STRINGS := {
	"app.title": {"en": "The Last Clan", "fr": "The Last Clan"},
	"ui.name": {"en": "Your name", "fr": "Votre nom"},
	"ui.play_offline": {"en": "Play offline (solo)", "fr": "Jouer hors ligne (solo)"},
	"ui.choose_server": {"en": "Choose a server (kingdom)", "fr": "Choisir un serveur (royaume)"},
	"ui.create_game": {"en": "Create a game", "fr": "Créer une partie"},
	"ui.join_game": {"en": "Join a game", "fr": "Rejoindre une partie"},
	"ui.room_code": {"en": "Game code", "fr": "Code de la partie"},
	"ui.recent_games": {"en": "Recent games", "fr": "Parties récentes"},
	"ui.players": {"en": "Players in game", "fr": "Joueurs dans la partie"},
	"ui.chat": {"en": "Chat", "fr": "Chat"},
	"ui.launch": {"en": "Launch game", "fr": "Lancer le jeu"},
	"ui.clan": {"en": "Clan", "fr": "Clan"},
	"ui.create_clan": {"en": "Create a clan", "fr": "Créer un clan"},
	"ui.join_clan": {"en": "Join a clan", "fr": "Rejoindre un clan"},
	"ui.clan_name": {"en": "Clan name", "fr": "Nom du clan"},
	"ui.clan_tag": {"en": "Clan tag", "fr": "Tag du clan"},
	"ui.clan_desc": {"en": "Description", "fr": "Description"},
	"ui.members": {"en": "Members", "fr": "Membres"},
	"ui.realm_health": {"en": "Realm fate", "fr": "Sort du royaume"},
	"ui.translate": {"en": "Translate", "fr": "Traduire"},
	"ui.msg_typing": {"en": "Type a message…", "fr": "Écrire un message…"},
	"ui.close": {"en": "Close", "fr": "Fermer"},
	"ui.play": {"en": "Play", "fr": "Jouer"},
	"ui.suggest": {"en": "Suggest an idea", "fr": "Suggérer une amélioration"},
	"help.title": {"en": "Help / How to play", "fr": "Aide / Comment jouer"},
	"help.alpha": {"en": "This is an ALPHA test build: bugs are possible.",
				   "fr": "Jeu en version ALPHA de test : des bugs sont possibles."},
	"help.objective": {"en": "Goal: manage your base, collect gold / wood / stone, and train Villagers and Soldiers to grow your clan.",
					   "fr": "Objectif : gérer sa base, récolter or / bois / pierre, et entraîner Villageois et Soldats pour développer votre clan."},
	"help.howto": {"en": "How to play: select units and buildings. The Build button (bottom-left) moves the camera. Give orders to your units.",
				   "fr": "Comment jouer : sélectionnez vos unités et bâtiments. Le bouton Construire (en bas à gauche) déplace la caméra. Donnez des ordres à vos unités."},
	"help.suggest": {"en": "Send us your improvement ideas with the “Suggest” button.",
					 "fr": "Envoyez-nous vos idées d’amélioration via le bouton « Suggérer »."},
	"suggest.title": {"en": "Suggestions", "fr": "Suggestions"},
	"suggest.subtitle": {"en": "This is an ALPHA build. Tell us what to improve!",
						 "fr": "Jeu en version ALPHA. Dites-nous quoi améliorer !"},
	"suggest.name": {"en": "Your name", "fr": "Votre nom"},
	"suggest.message": {"en": "Your idea / bug report…", "fr": "Votre idée / rapport de bug…"},
	"suggest.send": {"en": "Send", "fr": "Envoyer"},
	"suggest.sent": {"en": "Thank you! Your message was sent to the team.",
					 "fr": "Merci ! Votre message a été envoyé à l’équipe."},
	"suggest.back": {"en": "Back", "fr": "Retour"},
}

const SETTINGS := "user://settings.cfg"

func _ready() -> void:
	_load_settings()

func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS):
		# 1er lancement : langue du système si supportée, sinon anglais.
		language = native_from_os(OS.get_locale())
		_settings_save()
		return
	var f := FileAccess.open(SETTINGS, FileAccess.READ)
	var text: String = f.get_as_text()
	f.close()
	for line in text.split("\n"):
		if line.begins_with("language="):
			var v := line.trim_prefix("language=").strip_edges()
			if SUPPORTED.has(v):
				language = v

func _settings_save() -> void:
	var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
	f.store_line("language=%s" % language)
	f.close()

## Renvoie la langue la plus proche du système (fr_CA -> fr, en_US -> en).
func native_from_os(locale: String) -> String:
	if locale.is_empty():
		return "en"
	var base := locale.split("_")[0].split("-")[0].to_lower()
	return base if SUPPORTED.has(base) else "en"

## Traduit une clé d'interface dans la langue actuelle (fallback EN puis clé).
func t(key: String) -> String:
	if not STRINGS.has(key):
		return key
	var map: Dictionary = STRINGS[key]
	if map.has(language):
		return str(map[language])
	if map.has("en"):
		return str(map["en"])
	return key

## Drapeau (emoji) d'une langue. "" si inconnue.
func code_to_flag(lang: String) -> String:
	if SUPPORTED.has(lang):
		return str(SUPPORTED[lang]["flag"])
	return "🌐"

## Nom natif d'une langue (ex "Français"). "Inconnue" sinon.
func lang_name(lang: String) -> String:
	if SUPPORTED.has(lang):
		return str(SUPPORTED[lang]["name"])
	return lang.to_upper()

## Vrai si la langue est supportée par le moteur de traduction.
func can_translate(lang: String) -> bool:
	return SUPPORTED.has(lang)

## Langues d'interface disponibles (triées alpha), pour un menu déroulant.
func available_languages() -> Array:
	var keys := SUPPORTED.keys()
	keys.sort()
	return keys
