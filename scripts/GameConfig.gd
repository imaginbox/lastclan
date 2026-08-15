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

	# ---- Dimensions / niveaux / PV par bâtiment ----
	{"key": "batiment.hdv.taille", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "HDV — empreinte (cases)", "def": 2, "min": 1, "max": 8},
	{"key": "batiment.hdv.niveaux", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "HDV — niveaux max", "def": 6, "min": 1, "max": 20},
	{"key": "batiment.hdv.pv", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "HDV — points de vie", "def": 300, "min": 10, "max": 10000},
	{"key": "batiment.caserne.taille", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Caserne — empreinte (cases)", "def": 2, "min": 1, "max": 8},
	{"key": "batiment.caserne.niveaux", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Caserne — niveaux max", "def": 3, "min": 1, "max": 20},
	{"key": "batiment.caserne.pv", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Caserne — points de vie", "def": 150, "min": 10, "max": 10000},
	{"key": "batiment.maison.taille", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Maison — empreinte (cases)", "def": 1, "min": 1, "max": 8},
	{"key": "batiment.maison.niveaux", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Maison — niveaux max", "def": 3, "min": 1, "max": 20},
	{"key": "batiment.maison.pv", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Maison — points de vie", "def": 80, "min": 10, "max": 10000},
	{"key": "batiment.tour.taille", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Tour — empreinte (cases)", "def": 1, "min": 1, "max": 8},
	{"key": "batiment.tour.niveaux", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Tour — niveaux max", "def": 3, "min": 1, "max": 20},
	{"key": "batiment.tour.pv", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Tour — points de vie", "def": 120, "min": 10, "max": 10000},
	{"key": "batiment.ferme.taille", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Ferme — empreinte (cases)", "def": 2, "min": 1, "max": 8},
	{"key": "batiment.ferme.niveaux", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Ferme — niveaux max", "def": 3, "min": 1, "max": 20},
	{"key": "batiment.ferme.pv", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Ferme — points de vie", "def": 80, "min": 10, "max": 10000},
	{"key": "batiment.carriere.taille", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Carrière — empreinte (cases)", "def": 1, "min": 1, "max": 8},
	{"key": "batiment.carriere.niveaux", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Carrière — niveaux max", "def": 3, "min": 1, "max": 20},
	{"key": "batiment.carriere.pv", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Carrière — points de vie", "def": 80, "min": 10, "max": 10000},
	{"key": "batiment.mine.taille", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Mine d'or — empreinte (cases)", "def": 1, "min": 1, "max": 8},
	{"key": "batiment.mine.niveaux", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Mine d'or — niveaux max", "def": 3, "min": 1, "max": 20},
	{"key": "batiment.mine.pv", "kind": Kind.INT, "cat": "Bâtiments",
	 "label": "Mine d'or — points de vie", "def": 80, "min": 10, "max": 10000},

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
	{"key": "jeu.ressources.initial_nourriture", "kind": Kind.INT, "cat": "Jeu",
	 "label": "Nourriture de départ", "def": 20, "min": 0, "max": 100000},
	{"key": "jeu.gravite", "kind": Kind.FLOAT, "cat": "Jeu",
	 "label": "Gravité (négatif=vers le bas)", "def": -20.0, "min": -100.0, "max": 0.0, "step": 1.0},

	# --------------------------- ROYAUME / SOCIAL ---------------------------
	{"key": "royaume.montant_combat", "kind": Kind.FLOAT, "cat": "Royaume",
	 "label": "Royaume — gain par combat", "def": 5.0, "min": 0.0, "max": 50.0, "step": 0.5},
	{"key": "royaume.drain_parseconde", "kind": Kind.FLOAT, "cat": "Royaume",
	 "label": "Royaume — drain /s (déclin)", "def": 0.1, "min": 0.0, "max": 5.0, "step": 0.05},
	{"key": "royaume.prosperite_bonus", "kind": Kind.FLOAT, "cat": "Royaume",
	 "label": "Royaume — bonus récolte en prospérité (x)", "def": 1.25, "min": 1.0, "max": 3.0, "step": 0.05},
	{"key": "royaume.declin_penalite", "kind": Kind.FLOAT, "cat": "Royaume",
	 "label": "Royaume — malus récolte en déclin (x)", "def": 0.85, "min": 0.1, "max": 1.0, "step": 0.05},
	{"key": "royaume.fonte_parseconde", "kind": Kind.FLOAT, "cat": "Royaume",
	 "label": "Royaume — fonte de la jauge /s", "def": 0.5, "min": 0.0, "max": 10.0, "step": 0.1},

	# ------------------------------ CAMÉRA --------------------------------
	{"key": "camera.zoom_min", "kind": Kind.FLOAT, "cat": "Caméra",
	 "label": "Zoom — valeur minimale", "def": 8.0, "min": 1.0, "max": 100.0, "step": 1.0},
	{"key": "camera.zoom_max", "kind": Kind.FLOAT, "cat": "Caméra",
	 "label": "Zoom — valeur maximale", "def": 220.0, "min": 10.0, "max": 600.0, "step": 5.0},
	{"key": "camera.vitesse_zoom", "kind": Kind.FLOAT, "cat": "Caméra",
	 "label": "Vitesse du zoom (molette)", "def": 6.0, "min": 1.0, "max": 30.0, "step": 1.0},
	{"key": "camera.inclinaison", "kind": Kind.FLOAT, "cat": "Caméra",
	 "label": "Inclinaison caméra (degrés)", "def": 50.0, "min": 10.0, "max": 85.0, "step": 1.0},

	# ------------------------------- MONDE ----------------------------------
	{"key": "monde.herbe_densite", "kind": Kind.INT, "cat": "Monde",
	 "label": "Densité d'herbe (nb. touffes)", "def": 320, "min": 0, "max": 2000},
	{"key": "monde.bois_max", "kind": Kind.INT, "cat": "Monde",
	 "label": "Bois max par arbre", "def": 80, "min": 10, "max": 500},
	{"key": "monde.pierre_max", "kind": Kind.INT, "cat": "Monde",
	 "label": "Pierre max par rocher", "def": 60, "min": 10, "max": 500},
	{"key": "monde.or_max", "kind": Kind.INT, "cat": "Monde",
	 "label": "Or max par filon", "def": 100, "min": 10, "max": 500},
	{"key": "monde.nourriture_max", "kind": Kind.INT, "cat": "Monde",
	 "label": "Nourriture max par buisson", "def": 40, "min": 10, "max": 500},

	# ------------------------------- ADMIN ----------------------------------
	{"key": "admin.mot_de_passe", "kind": Kind.STRING, "cat": "Admin",
	 "label": "Mot de passe admin", "def": "lastclan", "min": 0, "max": 0},
]

# ---------------------------------------------------------------------------
# Descriptions d'aide (affichées dans le panneau admin).
# CATEGORY_DESC : explication affichée en tête de chaque onglet.
# PARAM_DESC    : aide courte affichée sous chaque paramètre (par clé).
# ---------------------------------------------------------------------------
const CATEGORY_DESC: Dictionary = {
	"Économie": "Rythme auquel chaque bâtiment produit sa ressource. "
		+ "Augmenter accélère la production ; mettre à 0 coupe la production.",
	"Paysan": "Caractéristiques des paysans : déplacement, survie, dégâts, "
		+ "vitesse de collecte et quantité transportée.",
	"Soldat": "Caractéristiques des soldats entraînés à la caserne.",
	"Bâtiments": "Coûts de construction, d'amélioration, de dimension, de niveaux "
		+ "et de vie de chaque bâtiment, plus le logement des maisons et les dégâts des tours.",
	"Recrutement": "Coûts et durée pour recruter des paysans / entraîner des soldats.",
	"Jeu": "Réglages généraux de la partie : ressources de départ et gravité.",
	"Royaume": "Ressource sociale du royaume : gains par combat, déclin passif et bonus de récolte.",
	"Caméra": "Réglages de la caméra isométrique : bornes de zoom, vitesse de molette et inclinaison.",
	"Monde": "Génération du monde : densité d'herbe et quantités de ressources par type.",
	"Admin": "Paramètres d'administration. Changez ici le mot de passe d'accès.",
}

const PARAM_DESC: Dictionary = {
	"economie.gold.taux": "Or produit chaque seconde par l'hôtel de ville.",
	"economie.nourriture.taux": "Nourriture/s produite par chaque ferme.",
	"economie.pierre.taux": "Pierre/s produite par chaque carrière.",
	"economie.or.taux": "Or/s produit par chaque mine d'or.",
	"unite.paysan.vitesse": "Vitesse de déplacement du paysan (cases/s).",
	"unite.paysan.pv": "Points de vie maximum du paysan.",
	"unite.paysan.degats": "Dégâts infligés par attaque du paysan.",
	"unite.paysan.portee": "Distance d'attaque du paysan (cases).",
	"unite.paysan.recolte": "Durée pour collecter une ressource (s).",
	"unite.paysan.charge": "Quantité max transportée avant de revenir déposer.",
	"unite.soldat.vitesse": "Vitesse de déplacement du soldat (cases/s).",
	"unite.soldat.pv": "Points de vie maximum du soldat.",
	"unite.soldat.degats": "Dégâts infligés par attaque du soldat.",
	"unite.soldat.portee": "Distance d'attaque du soldat (cases).",
	"unite.soldat.cadence": "Délai entre deux attaques du soldat (s).",
	"batiment.hdv.cout_or": "Coût en or pour construire l'hôtel de ville.",
	"batiment.hdv.ameli_or": "Coût en or pour améliorer l'hôtel de ville.",
	"batiment.hdv.ameli_bois": "Coût en bois pour améliorer l'hôtel de ville.",
	"batiment.caserne.cout_or": "Coût en or de la caserne.",
	"batiment.caserne.cout_bois": "Coût en bois de la caserne.",
	"batiment.caserne.cout_pierre": "Coût en pierre de la caserne.",
	"batiment.maison.cout_or": "Coût en or d'une maison.",
	"batiment.maison.cout_bois": "Coût en bois d'une maison.",
	"batiment.maison.pop": "Logement offert par niveau de maison.",
	"batiment.tour.cout_or": "Coût en or d'une tour.",
	"batiment.tour.cout_bois": "Coût en bois d'une tour.",
	"batiment.tour.cout_pierre": "Coût en pierre d'une tour.",
	"batiment.tour.degats": "Dégâts infligés par la tour.",
	"batiment.ferme.cout_or": "Coût en or d'une ferme.",
	"batiment.ferme.cout_bois": "Coût en bois d'une ferme.",
	"batiment.carriere.cout_or": "Coût en or d'une carrière.",
	"batiment.carriere.cout_bois": "Coût en bois d'une carrière.",
	"batiment.carriere.cout_pierre": "Coût en pierre d'une carrière.",
	"batiment.mine.cout_bois": "Coût en bois d'une mine d'or.",
	"batiment.mine.cout_pierre": "Coût en pierre d'une mine d'or.",
	"recrutement.paysan.or": "Coût en or pour recruter un paysan.",
	"recrutement.paysan.nourriture": "Coût en nourriture pour recruter un paysan.",
	"recrutement.soldat.or": "Coût en or pour entraîner un soldat.",
	"recrutement.soldat.bois": "Coût en bois pour entraîner un soldat.",
	"recrutement.soldat.temps": "Durée d'entraînement d'un soldat (s).",
	"jeu.ressources.initial_or": "Or au début de chaque partie.",
	"jeu.ressources.initial_bois": "Bois au début de chaque partie.",
	"jeu.ressources.initial_pierre": "Pierre au début de chaque partie.",
	"jeu.gravite": "Gravité du monde (négatif = vers le bas).",
	"royaume.montant_combat": "Jauge de royaume gagnée par combat gagné.",
	"royaume.drain_parseconde": "Perte automatique de jauge du royaume par seconde.",
	"admin.mot_de_passe": "Mot de passe demandé pour ouvrir ce panneau.",
	"batiment.hdv.taille": "Empreinte au sol de l'hôtel de ville, en cases.",
	"batiment.hdv.niveaux": "Nombre maximal de niveaux pour l'hôtel de ville.",
	"batiment.hdv.pv": "Points de vie de base de l'hôtel de ville.",
	"batiment.caserne.taille": "Empreinte au sol de la caserne, en cases.",
	"batiment.caserne.niveaux": "Nombre maximal de niveaux pour la caserne.",
	"batiment.caserne.pv": "Points de vie de base de la caserne.",
	"batiment.maison.taille": "Empreinte au sol de la maison, en cases.",
	"batiment.maison.niveaux": "Nombre maximal de niveaux pour la maison.",
	"batiment.maison.pv": "Points de vie de base de la maison.",
	"batiment.tour.taille": "Empreinte au sol de la tour, en cases.",
	"batiment.tour.niveaux": "Nombre maximal de niveaux pour la tour.",
	"batiment.tour.pv": "Points de vie de base de la tour.",
	"batiment.ferme.taille": "Empreinte au sol de la ferme, en cases.",
	"batiment.ferme.niveaux": "Nombre maximal de niveaux pour la ferme.",
	"batiment.ferme.pv": "Points de vie de base de la ferme.",
	"batiment.carriere.taille": "Empreinte au sol de la carrière, en cases.",
	"batiment.carriere.niveaux": "Nombre maximal de niveaux pour la carrière.",
	"batiment.carriere.pv": "Points de vie de base de la carrière.",
	"batiment.mine.taille": "Empreinte au sol de la mine d'or, en cases.",
	"batiment.mine.niveaux": "Nombre maximal de niveaux pour la mine d'or.",
	"batiment.mine.pv": "Points de vie de base de la mine d'or.",
	"jeu.ressources.initial_nourriture": "Nourriture au début de chaque partie.",
	"royaume.prosperite_bonus": "Multiplicateur de récolte quand le royaume est prospère.",
	"royaume.declin_penalite": "Multiplicateur de récolte quand le royaume est en déclin.",
	"royaume.fonte_parseconde": "Vitesse à laquelle la jauge du royaume redescend.",
	"camera.zoom_min": "Plus petit zoom (le plus proche) en unités de vue.",
	"camera.zoom_max": "Plus grand zoom (le plus éloigné) en unités de vue.",
	"camera.vitesse_zoom": "Variation du zoom par cran de molette.",
	"camera.inclinaison": "Inclinaison de la caméra isométrique, en degrés.",
	"monde.herbe_densite": "Nombre de touffes d'herbe dispersées sur la carte.",
	"monde.bois_max": "Quantité de bois initiale sur chaque arbre récoltable.",
	"monde.pierre_max": "Quantité de pierre initiale sur chaque rocher récoltable.",
	"monde.or_max": "Quantité d'or initiale sur chaque filon récoltable.",
	"monde.nourriture_max": "Quantité de nourriture initiale sur chaque buisson récoltable.",
}

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

## Description d'aide d'une catégorie (ou "" si absente).
func category_desc(cat: String) -> String:
	return str(CATEGORY_DESC.get(cat, ""))

## Description d'aide d'un paramètre (par clé), ou "" si absente.
func param_desc(k: String) -> String:
	return str(PARAM_DESC.get(k, ""))

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
