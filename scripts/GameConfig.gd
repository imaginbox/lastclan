extends Node
## GameConfig — registre central des paramètres de gameplay (mode admin).
##
## Tous les paramètres ajustables du jeu sont déclarés ici (dans REGISTRY),
## avec leur catégorie, leur type, leur valeur par défaut et leurs bornes.
## Le panneau admin (AdminMenu.gd) génère automatiquement son interface à
## partir de ce registre : ajouter un paramètre ici le rend éditable dans
## l'UI, sans toucher au panneau.
##
## API :
##   GameConfig.get("economie.gold.mult")            -> valeur actuelle (double)
##   GameConfig.set_value("economie.gold.mult", 2.0) -> régler + persister
##   GameConfig.reset()                              -> revenir aux défauts
##   GameConfig.save()/load()                        -> persistance JSON
##   GameConfig.registry()                           -> description (pour l'UI)
##
## LB: autoloads accessibles via get_node("/root/GameConfig") dans le code.

# Fichier de sauvegarde (persiste les réglages admin sur ce client).
const SAVE_PATH := "user://game_config.json"

## Type paramétique d'un champ.
enum Kind { INT, FLOAT, BOOL, STRING, COLOR }

## ---------------------------------------------------------------------------
## Registre des paramètres. Chaque entrée :
##   key    : clé unique stockée (ex "economie.gold.mult").
##   kind   : Kind (INT/Durée etc.).
##   cat    : nom de la section d'UI.
##   label  : libellé affiché.
##   def    : valeur par défaut.
##   min/max/step : bornes et pas (interface).
## ---------------------------------------------------------------------------
const REGISTRY: Array = [
	# ----------------------------- ÉCONOMIE --------------------------------
	{"key": "economie.gold.taux", "kind": Kind.FLOAT, "cat": "Économie",
	 "label": "Taux d'or de l'hôtel de ville", "def": 0.8, "min": 0.0, "max": 20.0, "step": 0.1},
	{"key": "economie.nourriture.taux", "kind": Kind.FLOAT, "cat": "Économie",
	 "label": "Taux de nourriture (ferme)", "def": 4.0, "min": 0.0, "max": 30.0, "step": 0.5},
	{"key": "economie.pierre.taux", "kind": Kind.FLOAT, "cat": "Économie",
	 "label": "Taux de pierre (carrière)", "def": 2.0, "min": 0.0, "max": 20.0, "step": 0.5},
	{"key": "economie.or.taux", "kind": Kind.FLOAT, "cat": "Économie",
	 "label": "Taux d'or (mine)", "def": 3.0, "min": 0.0, "max": 30.0, "step": 0.5},

	# --------------------------- UNITÉS PAYSAN -----------------------------
	{"key": "unite.paysan.vitesse", "kind": Kind.FLOAT, "cat": "Paysan",
	 "label": "Vitesse du paysan", "def": 3.0, "min": 0.5, "max": 20.0, "step": 0.1},
	{"key": "unite.paysan.pv", "kind": Kind.INT, "cat": "Paysan",
	 "label": "Points de vie du paysan", "def": 60, "min": 1, "max": 1000},
	{"key": "unite.paysan.degats", "kind": Kind.INT, "cat": "Paysan",
	 "label": "Dégâts d'attaque du paysan", "def": 5, "min": 0, "max": 200},
	{"key": "unite.paysan.portee", "kind": Kind.FLOAT, "cat": "Paysan",
	 "label": "Portée d'attaque du paysan", "def": 1.5, "min": 0.1, "max": 20.0, "step": 0.1},
	{"key": "unite.paysan.recolte", "kind": Kind.FLOAT, "cat": "Paysan",
	 "label": "Temps de récolte (s)", "def": 2.0, "min": 0.1, "max": 20.0, "step": 0.1},
	{"key": "unite.paysan.charge", "kind": Kind.INT, "cat": "Paysan",
	 "label": "Charge transportée max", "def": 15, "min": 1, "max": 500},

	# --------------------------- UNITÉS SOLDAT -----------------------------
	{"key": "unite.soldat.vitesse", "kind": Kind.FLOAT, "cat": "Soldat",
	 "label": "Vitesse du soldat", "def": 4.0, "min": 0.5, "max": 20.0, "step": 0.1},
	{"key": "unite.soldat.pv", "kind": Kind.INT, "cat": "Soldat",
	 "label": "Points de vie du soldat", "def": 80, "min": 1, "max": 1000},
	{"key": "unite.soldat.degats", "kind": Kind.INT, "cat": "Soldat",
	 "label": "Dégâts d'attaque du soldat", "def": 6, "min": 0, "max": 300},
	{"key": "unite.soldat.portee", "kind": Kind.FLOAT, "cat": "Soldat",
	 "label": "Portée d'attaque du soldat", "def": 1.6, "min": 0.1, "max": 25.0, "step": 0.1},
	{"key": "unite.soldat.cadence", "kind": Kind.FLOAT, "cat": "Soldat",
	 "label": "Cadence d'attaque (s)", "def": 1.0, "min": 0.1, "max": 10.0, "step": 0.1},

	# --------------------------- COÛTS BÂTIMENTS ---------------------------
	{"key": "batiment.hdv.cout_or", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "HDV — coût or", "def": 0, "min": 0, "max": 100000},
	{"key": "batiment.hdv.ameli_or", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "HDV — coût amél. or", "def": 60, "min": 0, "max": 100000},
	{"key": "batiment.hdv.ameli_bois", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "HDV — coût amél. bois", "def": 100, "min": 0, "max": 100000},
	{"key": "batiment.caserne.cout_or", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Caserne — coût or", "def": 100, "min": 0, "max": 100000},
	{"key": "batiment.caserne.cout_bois", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Caserne — coût bois", "def": 80, "min": 0, "max": 100000},
	{"key": "batiment.caserne.cout_pierre", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Caserne — coût pierre", "def": 40, "min": 0, "max": 100000},
	{"key": "batiment.maison.cout_or", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Maison — coût or", "def": 40, "min": 0, "max": 100000},
	{"key": "batiment.maison.cout_bois", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Maison — coût bois", "def": 60, "min": 0, "max": 100000},
	{"key": "batiment.maison.pop", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Maison — logement par niveau", "def": 8, "min": 0, "max": 500},
	{"key": "batiment.tour.cout_or", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Tour — coût or", "def": 80, "min": 0, "max": 100000},
	{"key": "batiment.tour.cout_bois", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Tour — coût bois", "def": 70, "min": 0, "max": 100000},
	{"key": "batiment.tour.cout_pierre", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Tour — coût pierre", "def": 120, "min": 0, "max": 100000},
	{"key": "batiment.tour.degats", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Tour — dégâts", "def": 10, "min": 0, "max": 500},
	{"key": "batiment.ferme.cout_or", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Ferme — coût or", "def": 30, "min": 0, "max": 100000},
	{"key": "batiment.ferme.cout_bois", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Ferme — coût bois", "def": 60, "min": 0, "max": 100000},
	{"key": "batiment.carriere.cout_or", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Carrière — coût or", "def": 60, "min": 0, "max": 100000},
	{"key": "batiment.carriere.cout_bois", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Carrière — coût bois", "def": 80, "min": 0, "max": 100000},
	{"key": "batiment.carriere.cout_pierre", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Carrière — coût pierre", "def": 15, "min": 0, "max": 100000},
	{"key": "batiment.mine.cout_bois", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Mine d'or — coût bois", "def": 100, "min": 0, "max": 100000},
	{"key": "batiment.mine.cout_pierre", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Mine d'or — coût pierre", "def": 60, "min": 0, "max": 100000},

	# ----------------------------- RECRUTEMENT -----------------------------
	{"key": "recrutement.paysan.or", "kind": Kind.INT, "cat": "Recrutement",
	 "label": "Recruter paysan — or", "def": 40, "min": 0, "max": 100000},
	{"key": "recrutement.paysan.nourriture", "kind": Kind.INT, "cat": "Recrutement",
	 "label": "Recruter paysan — nourriture", "def": 5, "min": 0, "max": 100000},
	{"key": "recrutement.soldat.or", "kind": Kind.INT, "cat": "Recrutement",
	 "label": "Entraîner soldat — or", "def": 45, "min": 0, "max": 100000},
	{"key": "recrutement.soldat.bois", "kind": Kind.INT, "cat": "Recrutement",
	 "label": "Entraîner soldat — bois", "def": 15, "min": 0, "max": 100000},
	{"key": "recrutement.soldat.temps", "kind": Kind.FLOAT, "cat": "Recrutement",
	 "label": "Entraîner soldat — temps (s)", "def": 4.0, "min": 0.1, "max": 60.0, "step": 0.1},

	# ------------------------------- JEU ------------------------------------
	{"key": "jeu.ressources.initial_or", "kind": Kind.INT, "cat": "Jeu",
	 "label": "Or de départ", "def": 100, "min": 0, "max": 100000},
	{"key": "jeu.ressources.initial_bois", "kind": Kind.INT, "cat": "Jeu",
	 "label": "Bois de départ", "def": 100, "min": 0, "max": 100000},
	{"key": "jeu.ressources.initial_pierre", "kind": Kind.INT, "cat": "Jeu",
	 "label": "Pierre de départ", "def": 50, "min": 0, "max": 100000},
	{"key": "jeu.gravite", "kind": Kind.FLOAT, "cat": "Jeu",
	 "label": "Gravité (négatif=vers le bas)", "def": -20.0, "min": -100.0, "max": 0.0, "step": 1.0},

	# --------------------------- ROYAUME / SOCIAL ---------------------------
	{"key": "royaume.montant_combat", "kind": Kind.FLOAT, "cat": "Royaume",
	 "label": "Royaume — gain par combat", "def": 5.0, "min": 0.0, "max": 50.0, "step": 0.5},
	{"key": "royaume.drain_parseconde", "kind": Kind.FLOAT, "cat": "Royaume",
	 "label": "Royaume — drain /s (déclin)", "def": 0.1, "min": 0.0, "max": 5.0, "step": 0.05},

	# ------------------------------- ADMIN ----------------------------------
	{"key": "admin.mot_de_passe", "kind": Kind.STRING, "cat": "Admin",
	 "label": "Mot de passe admin", "def": "lastclan", "min": 0, "max": 0},
]

# Valeurs courantes (défauts copiés puis surchargées par le JSON sauvegardé).
var _values: Dictionary = {}
var _loaded: bool = false

func _ready() -> void:
	reset()
	load_saved()

## Recalcule _values à partir des défauts du registre.
func reset() -> void:
	_values.clear()
	for p in REGISTRY:
		_values[p["key"]] = p["def"]
	_loaded = false

## Récupère la valeur d'un paramètre (par sa clé). Type retourné : Variant.
func get_value(k: String) -> Variant:
	if _values.has(k):
		return _values[k]
	# Retombe sur le défaut du registre.
	for p in REGISTRY:
		if p["key"] == k:
			return p["def"]
	return null

## Type retourné d'une clé (utile pour brancher du code).
func get_type(k: String) -> Kind:
	for p in REGISTRY:
		if p["key"] == k:
			return p["kind"]
	return Kind.FLOAT

## Règle une valeur (bornée) et persiste.
func set_value(k: String, v: Variant) -> void:
	for p in REGISTRY:
		if p["key"] == k:
			v = _clamp(p, v)
			_values[k] = v
			break
	save()

func _clamp(p: Dictionary, v: Variant) -> Variant:
	match p["kind"]:
		Kind.INT:
			return int(clampi(int(v), int(p.get("min", 0)), int(p.get("max", 999999))))
		Kind.FLOAT:
			return float(clampf(float(v), float(p.get("min", 0.0)), float(p.get("max", 99999.0))))
		Kind.BOOL:
			return bool(v)
		Kind.STRING:
			return str(v)
	return v

## Copie du registre (pour construire l'UI).
func registry() -> Array:
	return REGISTRY

## Sections uniques, ordonnées par première apparition (pour l'UI).
func categories() -> Array:
	var out: Array = []
	for p in REGISTRY:
		if not out.has(p["cat"]):
			out.append(p["cat"])
	return out

## Paramètres d'une catégorie donnée.
func params_in_cat(cat: String) -> Array:
	var out: Array = []
	for p in REGISTRY:
		if p["cat"] == cat:
			out.append(p)
	return out

func to_dict() -> Dictionary:
	return _values.duplicate()

## Persiste les réglages courants dans user://game_config.json.
func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_values, "\t"))
	f.close()

## Charge un fichier sauvegardé s'il existe (fusionne sur les défauts).
func load_saved() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		return
	for k in data:
		if _values.has(k):
			_values[k] = data[k]
	_loaded = true
