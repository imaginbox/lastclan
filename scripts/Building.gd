class_name Building
extends StaticBody3D

## Building — base de tous les bâtiments.
## Gère le type, le niveau, l'upgrade, l'empreinte au sol, les effets (population,
## entraînement, recrutement, dégâts) et la production passive de ressources.
## Le champ min_th_level débloque chaque bâtiment selon le niveau de l'hôtel de ville.

## Signaux émis vers le contrôleur (main.gd) pour qu'il fasse le spawn réel.
signal unit_requested(unit_type: int)   # 0 = paysan, 1 = soldat
signal building_changed
## Émis quand ce bâtiment est détruit/déplacé hors de la grille (local SEUL).
## Le contrôleur (main.gd) le relaie en réseau pour que les copies distantes
## disparaissent aussi (pas de bâtiment fantôme chez les autres joueurs).
signal removed(cell: Vector2i)

enum Type { TOWN_HALL, BARRACKS, HOUSE, TOWER, FERME, CARRIERE, MINE_OR }
enum Unit { VILLAGER, SOLDIER }

## --- Configuration Stratégique ---
const TYPES := {
	Type.TOWN_HALL: {
		"name": "Hôtel de ville",
		"cost_gold": 0, "cost_wood": 0,
		"footprint": 2, "max_level": 6,
		"upg_gold": 60, "upg_wood": 100, "upg_stone": 40,
		"min_th_level": 0,
		"color": Color(0.6, 0.4, 0.2),
		"recruit_gold": 40, "recruit_food": 5, "recruit_pop": 1,
		"production": { "gold": 0.8 },
	},
	Type.BARRACKS: {
		"name": "Caserne",
		"cost_gold": 100, "cost_wood": 80, "cost_stone": 40,
		"footprint": 2, "max_level": 3,
		"upg_gold": 80, "upg_wood": 60,
		"min_th_level": 2,
		"color": Color(0.7, 0.2, 0.2),
		"train_gold": 45, "train_wood": 15, "train_pop": 1,
		"train_time": 4.0,
	},
	Type.HOUSE: {
		"name": "Maison",
		"cost_gold": 40, "cost_wood": 60,
		"footprint": 1, "max_level": 3,
		"upg_gold": 40, "upg_wood": 40,
		"min_th_level": 1,
		"color": Color(0.8, 0.6, 0.35),
		"pop_provided": 8,
	},
	Type.TOWER: {
		"name": "Tour de garde",
		"cost_gold": 80, "cost_wood": 70, "cost_stone": 120,
		"footprint": 1, "max_level": 3,
		"upg_gold": 60, "upg_wood": 50, "upg_stone": 90,
		"min_th_level": 2,
		"color": Color(0.4, 0.4, 0.5),
		"attack_damage": 10,
	},
	Type.FERME: {
		"name": "Ferme",
		"cost_gold": 30, "cost_wood": 60,
		"footprint": 2, "max_level": 3,
		"upg_gold": 40, "upg_wood": 40,
		"min_th_level": 1,
		"color": Color(0.9, 0.8, 0.2),
		"production": { "food": 4 },
	},
	Type.CARRIERE: {
		"name": "Carrière",
		"cost_gold": 60, "cost_wood": 80, "cost_stone": 15,
		"footprint": 1, "max_level": 3,
		"upg_gold": 50, "upg_wood": 50,
		"min_th_level": 1,
		"color": Color(0.6, 0.6, 0.65),
		"production": { "stone": 2 },
	},
	Type.MINE_OR: {
		"name": "Mine d'Or",
		"cost_gold": 0, "cost_wood": 100, "cost_stone": 60,
		"footprint": 1, "max_level": 3,
		"upg_gold": 60, "upg_wood": 60,
		"min_th_level": 1,
		"color": Color(1.0, 0.84, 0.0),
		"production": { "gold": 3.0 },
	},
}
const HEIGHT := 2.0   # hauteur de base d'un bâtiment (mètres)

var type: Type = Type.HOUSE
var level: int = 1
var hp: int = 100
var max_hp: int = 100
var grid_cell := Vector2i.ZERO   # cellule d'ancrage (bas-gauche de l'empreinte)
## Copie DISTANTE (vue d'un autre joueur) : vrai quand ce bâtiment est la
## représentation d'une construction appartenant à un autre pair. N'est ni
## sélectionnable, ni productif, ni recruteur — c'est un simple visuel + obstacle.
var remote: bool = false
## peer_id du propriétaire réel de ce bâtiment (à définir sur les copies distantes).
var owner_peer: int = 0
## référence vers le script main (relais des dégâts des copies distantes).
var relay: Node = null

var _mesh: MeshInstance3D = null
var _base_material: StandardMaterial3D = null
## Sprite 2D debout (billboard) utilisé pour l'hôtel de ville (type TOWN_HALL) :
## vu que le jeu n'a qu'un seul angle de caméra, une image suffit.
var _sprite: Sprite3D = null
# Accumulateur fractionnaire de production. `int(prod * delta)` à 60fps donne
# toujours 0 (ex. 2.5/s × 0.016s = 0.04 → int = 0), donc sans accumulation les
# bâtiments ne produisent JAMAIS rien. On cumule les fractions et on ne convertit
# en entier que quand le total dépasse 1. Clé = type de ressource ("gold", "wood"...).
var _prod_acc: Dictionary = { "gold": 0.0, "wood": 0.0, "stone": 0.0, "food": 0.0 }

func _ready() -> void:
	# COLLISION RTS : les bâtiments sont des obstacles physiques (layer 1).
	collision_layer = 1
	collision_mask = 0
	
	add_to_group("building")
	if type == Type.TOWN_HALL:
		add_to_group("town_hall")
	# Construit le visuel + la collision selon l'empreinte.
	_build_visual()
	# Obstacle d'évitement : dit au NavigationAgent3D qu'il doit CONTOURNER ce
	# bâtiment (l'évitement temps réel ne voit pas les colliders physiques, il a
	# besoin d'un NavigationObstacle3D dynamique pour pousser les paysans autour).
	var obs := NavigationObstacle3D.new()
	obs.name = "NavObstacle"
	obs.radius = float(footprint()) * 0.5
	obs.affect_navigation_mesh = false  # le navmesh est déjà carvé à la cuisson
	add_child(obs)
	hp = max_hp

func _process(delta: float) -> void:
	if remote:
		return  # les copies distantes ne produisent pas (économie du propriétaire)
	_produce(delta)

## --- Accesseurs de config ---
func building_display_name() -> String: return _cfg().get("name", "Bâtiment")
func footprint() -> int: return _cfg().get("footprint", 1)
func max_level() -> int: return _cfg().get("max_level", 3)
func building_type() -> Type: return type
func is_full_level() -> bool: return level >= max_level()
## Niveau d'hôtel de ville requis pour débloquer ce bâtiment.
func min_th_level() -> int: return _cfg().get("min_th_level", 0)

func _cfg() -> Dictionary:
	return TYPES[type]

## Coût d'upgrade pour passer du niveau actuel au suivant (ou {} si max).
func get_upgrade_cost() -> Dictionary:
	if is_full_level():
		return {}
	var lvl := level
	return {
		"gold": int(_cfg().get("upg_gold", 0) * lvl),
		"wood": int(_cfg().get("upg_wood", 0) * lvl),
		"stone": int(_cfg().get("upg_stone", 0) * lvl),
	}

## Tente d'upgrader. Dépense les ressources via ResourceManager.
func upgrade() -> bool:
	if is_full_level():
		return false
	var cost := get_upgrade_cost()
	var rm := get_node("/root/ResourceManager")
	if not rm.spend_full(cost["gold"], cost["wood"], cost["stone"]):
		return false
	level += 1
	max_hp = int(max_hp * 1.5)
	hp = max_hp
	_update_visual()
	building_changed.emit()
	return true

## --- Production passive ---
## Renvoie true si ce bâtiment produit des ressources dans le temps.
func is_producer() -> bool:
	return _cfg().has("production")

## Production actuelle par second (dépend du niveau).
func production_per_sec() -> Dictionary:
	var base: Dictionary = _cfg().get("production", {})
	var out := {}
	for key in base:
		out[key] = int(base[key] * level)
	return out

## Production actuelle par seconde en FLOTTANT (base × niveau), sans troncature.
## Utilisée par _produce pour que l'accumulation reçoive les valeurs exactes.
func production_float_per_sec() -> Dictionary:
	var base: Dictionary = _cfg().get("production", {})
	var out := {}
	for key in base:
		out[key] = float(base[key]) * float(level)
	return out

## Ajoute la production passive à l'économie, en ACCUMULANT les fractions.
## À 60fps, prod × delta est toujours < 1 (ex. 3/s × 0.016 = 0.05). On additionne
## ces fractions dans _prod_acc et on ne verse à l'économie que les unités entières
## dès qu'elles franchissent 1. Ainsi une production de 3 nourriture/s produit bien
## ~3 par seconde (ou 0.8 or/s pour la HDV), et non 0 en permanence.
func _produce(delta: float) -> void:
	if not is_producer():
		return
	var rm := get_node("/root/ResourceManager")
	var prod := production_float_per_sec()
	for res in _prod_acc:
		if prod.has(res):
			_prod_acc[res] += prod[res] * delta
			var whole: int = int(_prod_acc[res])
			if whole > 0:
				_prod_acc[res] -= float(whole)
				match res:
					"gold": rm.add_gold(whole)
					"wood": rm.add_wood(whole)
					"stone": rm.add_stone(whole)
					"food": rm.add_food(whole)

## --- Effets par type ---
## Population fournie (maisons) : augmente avec le niveau.
func population_provided() -> int:
	if type == Type.HOUSE:
		return int(_cfg().get("pop_provided", 5) * level)
	return 0

## --- Actions (Type) ---
## L'hôtel de ville recrute un paysan (coût or + nourriture).
func is_recruiter() -> bool: return type == Type.TOWN_HALL
func get_recruit_cost() -> Dictionary:
	if not is_recruiter():
		return {}
	return {
		"gold": _cfg().get("recruit_gold", 40),
		"food": _cfg().get("recruit_food", 5),
		"pop": _cfg().get("recruit_pop", 1),
	}
func try_recruit_villager() -> bool:
	if not is_recruiter():
		return false
	var cost := get_recruit_cost()
	var rm := get_node("/root/ResourceManager")
	if not rm.spend_food(cost["gold"], cost["food"]):
		return false
	if not rm.change_population(cost["pop"]):
		# Annule la dépense (pas assez de logement).
		rm.add_gold(cost["gold"])
		rm.add_food(cost["food"])
		return false
	unit_requested.emit(int(Unit.VILLAGER))
	return true

## La caserne entraîne un soldat.
func is_trainer() -> bool: return type == Type.BARRACKS
func get_train_cost() -> Dictionary:
	if not is_trainer():
		return {}
	# Le niveau réduit le coût en or.
	var gold: int = _cfg().get("train_gold", 50) - (level - 1) * 5
	return { "gold": maxi(gold, 10), "wood": _cfg().get("train_wood", 10), "pop": _cfg().get("train_pop", 1) }
func get_train_time() -> float:
	var base: float = _cfg().get("train_time", 4.0)
	return maxf(base * pow(0.85, level - 1), 1.0)
func try_train_soldier() -> bool:
	if not is_trainer():
		return false
	var cost := get_train_cost()
	var rm := get_node("/root/ResourceManager")
	if not rm.spend(cost["gold"], cost["wood"]):
		return false
	if not rm.change_population(cost["pop"]):
		rm.add_gold(cost["gold"])
		rm.add_wood(cost["wood"])
		return false
	unit_requested.emit(int(Unit.SOLDIER))
	return true

## La tour inflige des dégâts (pour les futurs ennemis).
func attack_damage() -> int:
	if type == Type.TOWER:
		return int(_cfg().get("attack_damage", 6) * level)
	return 0

## --- Dégâts / destruction ---
func take_damage(amount: int) -> void:
	# Copie distante : on relaie les dégâts au propriétaire réel, qui fait
	# autorité sur son bâtiment. On ne détruit pas la copie localement.
	if remote:
		if relay != null and is_instance_valid(relay):
			relay.request_building_damage(owner_peer, grid_cell, amount)
		return
	hp -= amount
	_update_visual()
	if hp <= 0:
		_destroy()

func _destroy() -> void:
	# Diffuse la destruction au monde réseau SAUF pour les copies distantes
	# (on ne veut pas re-propager la suppression d'une copie qu'on vient de créer).
	if not remote:
		removed.emit(grid_cell)
	queue_free()

## --- Visuel ---
func _build_visual() -> void:
	var f := footprint()
	var h := HEIGHT
	# La ferme et la carrière sont plus plates (champs / fondations).
	if type == Type.FERME or type == Type.CARRIERE:
		h = 0.3

	var size := Vector3(f, h, f)

	if type == Type.TOWN_HALL:
		# Hôtel de ville : image 2D debout (Sprite3D billboard) au lieu d'un cube.
		# Le jeu n'a qu'un seul angle de caméra, une image suffit donc.
		_sprite = Sprite3D.new()
		_sprite.name = "Sprite"
		_sprite.texture = _town_hall_texture()
		_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_sprite.centered = true
		var tsize := _sprite.texture.get_size()
		# IMPORTANT : la taille d'un Sprite3D dépend de `pixel_size` (par défaut
		# 1 px = 0.01 m). On règle pixel_size pour que la LARGEUR de l'image égale
		# l'empreinte au sol (f), la hauteur s'adaptant selon l'aspect. Sans ça, le
		# sprite serait démesuré (plus de 10 m) et sa base s'enfoncerait sous le
		# sol, qui le sectionnait à mi-hauteur (« bâtiment coupé »).
		if tsize.x > 0:
			_sprite.pixel_size = f / float(tsize.x)
		else:
			_sprite.pixel_size = 1.0
		# La hauteur affichée en mètres = tsize.y * pixel_size. On la déduit pour
		# poser le pied de l'image sur le sol (centre + moitié de la hauteur).
		var display_h := float(tsize.y) * _sprite.pixel_size
		# Petit offset minimal (~0.04 m) pour éviter un z-fighting du plan du sol.
		_sprite.position.y = (display_h * 0.5) + 0.04
		add_child(_sprite)
	else:
		_mesh = MeshInstance3D.new()
		_mesh.name = "Mesh"
		var box := BoxMesh.new()
		box.size = size
		_mesh.mesh = box
		_base_material = StandardMaterial3D.new()

		# Couleur spécifique pour la ferme (jaune blé) si pas définie.
		var color: Color = _cfg().get("color", Color.WHITE)
		if type == Type.FERME:
			color = Color(0.9, 0.8, 0.2) # Jaune blé

		_base_material.albedo_color = color
		_mesh.material_override = _base_material
		add_child(_mesh)
		_mesh.position.y = h / 2.0

	# Collision physique (idente pour les deux rendus) : un parallélépipède taille
	# empreinte × hauteur, pour que le bâtiment reste un obstacle RTS solide.
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var cshape := BoxShape3D.new()
	cshape.size = size
	shape.shape = cshape
	shape.position.y = h / 2.0
	add_child(shape)

## Texture de l'hôtel de ville selon son niveau (1..6 -> HDV-1..6.png).
func _town_hall_texture() -> Texture2D:
	var lvl := clampi(level, 1, 6)
	var path := "res://assets/models/Batiments/HDV/HDV-%d.png" % lvl
	return load(path) as Texture2D

func _update_visual() -> void:
	# L'HDV change de texture à chaque niveau + s'assombrit quand il est endommagé.
	if _sprite != null:
		_sprite.texture = _town_hall_texture()
		var ratio_spr := clampf(float(hp) / float(max_hp), 0.0, 1.0)
		_sprite.modulate = Color.WHITE.lerp(Color(0.25, 0.2, 0.18), 0.35 * (1.0 - ratio_spr))
		return
	if _base_material == null:
		return
	var ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
	_base_material.albedo_color = _cfg().get("color", Color.WHITE).lerp(Color.BLACK, 0.3 * (1.0 - ratio))

## Applique la teinte du propriétaire à une copie distante (distingue les camps).
func set_owner_tint(color: Color) -> void:
	if _sprite != null:
		_sprite.modulate = color
	elif _base_material != null:
		_base_material.albedo_color = color

## Actualise le visuel d'une copie distante après un changement de type/niveau
## (utilisé lors de la synchro des bâtiments entre joueurs).
func update_visual_for_sync() -> void:
	if _sprite != null:
		if remote:
			_sprite.texture = _town_hall_texture()
			_sprite.modulate = _cfg().get("color", Color.WHITE)
		return
	if _base_material != null and not remote:
		return
	if remote and _base_material != null:
		_base_material.albedo_color = _cfg().get("color", Color.WHITE)

## Sélection visuelle (contour/teinte).
func set_selected(on: bool) -> void:
	if _sprite != null:
		if on:
			_sprite.modulate = _cfg().get("color", Color.WHITE).lerp(Color(0.3, 1.0, 0.35), 0.35)
		else:
			_update_visual()
		return
	if _base_material == null:
		return
	if on:
		_base_material.albedo_color = _cfg().get("color", Color.WHITE).lerp(Color(0.3, 1.0, 0.35), 0.35)
	else:
		_update_visual()