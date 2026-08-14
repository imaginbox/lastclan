extends Node
## Translator — moteur de traduction du chat (architecture prête à brancher).
##
## Le but : chacun écrit dans sa langue, chaque joueur lit dans la sienne.
##
##   1. send_chat transporte {text, src_lang} (fait côté Lobby / MESSAGE).
##   2. À la réception, chaque client appelle Translator.translate(text, src_lang)
##      pour obtenir le texte dans SA langue (Translator.language).
##   3. Le moteur actuel est un STUB : il renvoie le texte original + un drapeau.
##      Pour activer la vraie traduction, implémenter _fetch_translation() avec
##      votre backend (DeepL / Google Translate / MyMemory gratuit) et fournir la
##      clé. L'interface reste identique — aucun refonte nécessaire.
##
## Le trade-off assumé : pas de traduction automatique tant qu'on n'a pas de clé
## API/serveur de traduction. La brique réseau (texte + langue source) est en place.

## Langue cible du joueur (synchronisée depuis I18n.language).
var language: String = "en"

## Drapeau : vrai quand un vrai moteur de traduction est actif.
var engine_active: bool = false

# --- Clé / adresse du backend de traduction (à renseigner pour activer) ---
const BACKEND_URL := ""          # ex "https://api.my-api.com/translate"
const BACKEND_KEY := ""          # ex clé d'API

func _ready() -> void:
	if Langs:
		language = Langs.language
		Langs.language_changed.connect(_on_language_changed)

func _on_language_changed(lang: String) -> void:
	language = lang

## Traduit `text` (écrit en `src_lang`) dans la langue du joueur.
## Retourne un Dictionary : {"text": …, "auto": bool, "src_lang": …}.
## Tant que le moteur est inactif, renvoie le texte original (auto=false).
func translate(text: String, src_lang: String) -> Dictionary:
	if engine_active and _can_translate(src_lang) and src_lang != language:
		var t := _fetch_translation(text, src_lang, language)
		if not t.is_empty():
			return {"text": t, "auto": true, "src_lang": src_lang}
	# Fallback : langue non supportée, moteur inactif, ou même langue.
	return {"text": text, "auto": false, "src_lang": src_lang}

## Vrai si la langue source peut être traduite.
func _can_translate(lang: String) -> bool:
	return Langs != null and Langs.can_translate(lang)

## Appelle le backend de traduction. À implémenter avec votre service.
## Renvoie "" si indisponible (le fallback renvoie alors le texte original).
func _fetch_translation(_text: String, _src: String, _dst: String) -> String:
	# Exemple (HTTPRequest async) :
	#   var url := BACKEND_URL + "?q=" + _text.uri_encode() + "&src=" + _src + "&dst=" + _dst
	#   … (manager HTTPRequest, parse JSON, renvoyer la chaîne)
	return ""
