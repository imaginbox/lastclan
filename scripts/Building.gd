class_name Building
extends StaticBody3D

## Building — base de tous les bâtiments.
## Gère le type, le niveau, l'upgrade, l'empreinte au sol, les effets (population,
## entraînement, recrutement, dégâts) et la production passive de ressources.
## Le champ min_th_level débloque chaque bâtiment selon le niveau de l'hôtel de ville.

## Signaux émis vers le contrôleur (main.gd) pour qu'il fasse le spawn réel.
signal unit_requested(unit_type: int)   # 0 = paysan, 1 = soldat
signal building_changed

enum Type { TOWN_HALL, BARRACKS, HOUSE, TOWER, FERME, CARRIERE }
enum Unit { VILLAGER, SOLDIER }

## --- Configuration par type ---
const TYPES := {
	Type.TOWN_HALL: {
		"name": "Hôtel de ville",
		"cost_gold": 0, "cost_wood": 0,
		"footprint": 2, "max_level": 3,
		"upg_gold": 150, "upg_wood": 100,
		"min_th_level": 0,
		"color": Color(0.6, 0.4, 0.2),
		"recruit_gold": 40, "recruit_wood": 0, "recruit_food": 5, "recruit_pop": 1,
	},
	Type.BARRACKS: {
		"name": "Caserne",
		"cost_gold": 120, "cost_wood": 80,
		"footprint": 2, "max_level": 3,
		"upg_gold": 80, "upg_wood": 60,
		"min_th_level": 3,
		"color": Color(0.55, 0.35, 0.6),
		"train_gold": 50, "train_wood": 10, "train_pop": 1,
		"train_time": 4.0,
	},
	Type.HOUSE: {
		"name": "Maison",
		"cost_gold": 40, "cost_wood": 60,
		"footprint": 1, "max_level": 3,
		"upg_gold": 40, "upg_wood": 50,
		"min_th_level": 1,
		"color": Color(0.8, 0.6, 0.35),
		"pop_provided": 5,
	},
	Type.TOWER: {
		"name": "Tour de défense",
		"cost_gold": 60, "cost_wood": 40, "cost_stone": 80,
		"footprint": 1, "max_level": 3,
		"upg_gold": 50, "upg_wood": 40, "upg_stone": 60,
		"min_th_level": 2,
		"color": Color(0.5, 0.55, 0.65),
		"attack_damage": 6,
	},
	Type.FERME: {
		"name": "Ferme",
		"cost_gold": 30, "cost_wood": 40,
		"footprint": 2, "max_level": 3,
		"upg_gold": 30, "upg_wood": 30,
		"min_th_level": 1,
		"color": Color(0.55, 0.75, 0.35),
		"production": { "food": 1 },
	},
	Type.CARRIERE: {
		"name": "Carrière",
		"cost_gold": 20, "cost_wood": 30, "cost_stone": 10,
		"footprint": 1, "max_level": 3,
		"upg_gold": 25, "upg_wood": 25,
		"min_th_level": 2,
		"color": Color(0.6, 0.6, 0.65),
		"production": { "stone": 1 },
	},
}
const HEIGHT := 2.0   # hauteur de base d'un bâtiment (mètres)

var type: Type = Type.HOUSE
var level: int = 1
var hp: int = 100
var max_hp: int = 100
var grid_cell := Vector2i.ZERO   # cellule d'ancrage (bas-gauche de l'empreinte)

var _mesh: MeshInstance3D = null
var _base_material: StandardMaterial3D = null

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

## Ajoute la production passive à l'économie.
func _produce(delta: float) -> void:
	if not is_producer():
		return
	var rm := get_node("/root/ResourceManager")
	var prod := production_per_sec()
	if prod.has("food"):
		rm.add_food(int(prod["food"] * delta))
	if prod.has("stone"):
		rm.add_stone(int(prod["stone"] * delta))

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
	hp -= amount
	_update_visual()
	if hp <= 0:
		_destroy()

func _destroy() -> void:
	queue_free()

## --- Visuel ---
func _build_visual() -> void:
	var f := footprint()
	var size := Vector3(f, HEIGHT, f)
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = size
	_mesh.mesh = box
	_base_material = StandardMaterial3D.new()
	_base_material.albedo_color = _cfg().get("color", Color.WHITE)
	_mesh.material_override = _base_material
	add_child(_mesh)
	_mesh.position.y = HEIGHT / 2.0
	
	# COLLISION PAR MESH : On utilise directement la géométrie du mesh pour la collision.
	# Même pour une boîte, cela garantit une synchronisation parfaite entre visuel et physique.
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	shape.shape = _mesh.mesh.create_convex_shape()
	shape.position.y = HEIGHT / 2.0
	add_child(shape)

func _update_visual() -> void:
	if _base_material == null:
		return
	var ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
	_base_material.albedo_color = _cfg().get("color", Color.WHITE).lerp(Color.BLACK, 0.3 * (1.0 - ratio))

## Sélection visuelle (contour/teinte).
func set_selected(on: bool) -> void:
	if _base_material == null:
		return
	if on:
		_base_material.albedo_color = _cfg().get("color", Color.WHITE).lerp(Color(0.3, 1.0, 0.35), 0.35)
	else:
		_update_visual()