class_name ResourceNode
extends StaticBody3D

## ResourceNode — nœud de ressource (mine d'or, arbre à bois, carrière de pierre).
## Utilise les modèles 3D fournis (arbres pour le bois, rochers pour la pierre,
## rocher doré pour l'or). Chaque type propose plusieurs variantes triées du PLUS
## GRAND (ressource pleine) au PLUS PETIT (ressource presque épuisée) : au fil des
## récoltes, le modèle échange de variante pour montrer visuellement l'épuisement.
## Quand la ressource est vide, elle disparaît (émet `depleted`, le monde la fait
## réapparaître ailleurs).

signal depleted ## Émis quand la ressource est épuisée (quantité <= 0).

enum ResourceType { GOLD, WOOD, STONE, FOOD }

## Vitesse de régénération (unités par seconde).
const REGEN_RATE: float = 0.5

# --- Pools de modèles (variantes triées du plus grand au plus petit) ---
const TREE_FAMILIES: Array[Array] = [
	[
		preload("res://assets/models/Mes assets/Assets/tree1/Tree_1_C_Color1.gltf"),
		preload("res://assets/models/Mes assets/Assets/tree1/Tree_1_B_Color1.gltf"),
		preload("res://assets/models/Mes assets/Assets/tree1/Tree_1_A_Color1.gltf"),
	],
	[
		preload("res://assets/models/Mes assets/Assets/tree2/Tree_2_E_Color1.gltf"),
		preload("res://assets/models/Mes assets/Assets/tree2/Tree_2_D_Color1.gltf"),
		preload("res://assets/models/Mes assets/Assets/tree2/Tree_2_C_Color1.gltf"),
		preload("res://assets/models/Mes assets/Assets/tree2/Tree_2_B_Color1.gltf"),
		preload("res://assets/models/Mes assets/Assets/tree2/Tree_2_A_Color1.gltf"),
	],
	[
		preload("res://assets/models/Mes assets/Assets/tree3/Tree_5_F_Color1.gltf"),
		preload("res://assets/models/Mes assets/Assets/tree3/Tree_5_E_Color1.gltf"),
		preload("res://assets/models/Mes assets/Assets/tree3/Tree_5_C_Color1.gltf"),
		preload("res://assets/models/Mes assets/Assets/tree3/Tree_5_B_Color1.gltf"),
		preload("res://assets/models/Mes assets/Assets/tree3/Tree_5_D_Color1.gltf"),
		preload("res://assets/models/Mes assets/Assets/tree3/Tree_5_A_Color1.gltf"),
	],
]

## Variantes de rocher pour la pierre (et l'or), du plus grand au plus petit.
## Arbres fruitiers (nourriture à récolter), du plus grand au plus petit.
## On réutilise les modèles d'arbres tree2, bien visibles à la caméra.
const FOOD_STAGES: Array[PackedScene] = [
	preload("res://assets/models/Mes assets/Assets/tree2/Tree_2_E_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/tree2/Tree_2_D_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/tree2/Tree_2_C_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/tree2/Tree_2_B_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/tree2/Tree_2_A_Color1.gltf"),
]

const ROCK_STAGES: Array[PackedScene] = [
	preload("res://assets/models/Mes assets/Assets/rock1/Rock_1_K_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/rock1/Rock_1_L_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/rock1/Rock_1_J_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/rock1/Rock_1_I_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/rock1/Rock_1_G_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/rock1/Rock_1_H_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/rock1/Rock_1_D_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/rock1/Rock_1_E_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/rock1/Rock_1_F_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/rock1/Rock_1_A_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/rock1/Rock_1_B_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/rock1/Rock_1_C_Color1.gltf"),
]

@export var resource_type: ResourceType = ResourceType.GOLD
@export var max_amount: int = 100
@export var starting_amount: int = 100

## Quantité restante (lecture publique).
var amount: int
## Nombre de récoltes simultanées en cours (pour différer la destruction).
var busy_workers: int = 0
## Échelle appliquée au modèle (ajustée selon le type pour cadrer au monde).
var model_scale: float = 1.0

var _model_root: Node3D = null
var _current_stage: int = -1
var _selection_ring: MeshInstance3D = null
## Indice de la famille d'arbres choisie UNE fois à la création. Chaque famille
## (tree1, tree2, tree3) correspond à un répertoire / un type d'arbre différent.
## On le fige pour que l'arbre garde TOUJOURS le même type (et donc les modèles du
## même répertoire) pendant toute sa vie, au lieu de changer de famille au hasard
## à chaque mise à jour visuelle (ce qui le faisait se transformer en deux modèles).
var _tree_family_index: int = -1
var _regen_timer: float = 0.0

func _process(delta: float) -> void:
	# CYCLE NATUREL : Régénération lente des arbres si non épuisés.
	# Permet un écosystème durable si le joueur gère bien sa forêt.
	if resource_type == ResourceType.WOOD and amount > 0 and amount < max_amount:
		_regen_timer += delta
		if _regen_timer >= 15.0: # Repousse un peu toutes les 15s
			amount = min(amount + 1, max_amount)
			_regen_timer = 0.0
			_update_visual()

func _ready() -> void:
	# COLLISION RTS : les ressources sont des obstacles physiques (layer 1).
	collision_layer = 1
	collision_mask = 0
	
	amount = clampi(starting_amount, 0, max_amount)
	# Détermine une fois pour toutes la famille d'arbres de ce nœud.
	if resource_type == ResourceType.WOOD:
		_tree_family_index = randi() % TREE_FAMILIES.size()
	_build_model_root()
	_setup_collision()
	_build_selection_ring()
	_update_visual()

## Construit un anneau posé au sol : il apparaît quand le joueur clique sur la
## source, pour qu'on voie à l'instant que cette source a bien été sélectionnée.
func _build_selection_ring() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 1.0, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(0.95, 1.0, 0.35)
	mat.emission_energy = 2.5
	# Rayon du cercle adapté à l'empreinte réelle de l'objet : il doit épouser la
	# base de l'arbre / du rocher. Auparavant trop grand (1.4–1.6), le cercle
	# entourait un espace vide et l'objet paraissait décentré dedans.
	var inner_r: float = 1.0
	var outer_r: float = 1.15
	var torus := TorusMesh.new()
	torus.inner_radius = inner_r
	torus.outer_radius = outer_r
	torus.rings = 48
	torus.ring_segments = 24
	_selection_ring = MeshInstance3D.new()
	_selection_ring.name = "SelectionRing"
	_selection_ring.mesh = torus
	_selection_ring.material_override = mat
	# Le TorusMesh est DÉJÀ plat dans le plan horizontal (AABB 2.3 x 0.15 x 2.3,
	# l'épaisseur 0.15 est sur Y, l'axe du trou est Y). Le tourner de 90° sur X le
	# redressait à la verticale (cercle "mal orienté" debout au lieu d'une couronne
	# au sol). On ne le tourne donc PAS.
	_selection_ring.position.y = 0.12
	_selection_ring.visible = false
	add_child(_selection_ring)

## Affiche l'anneau de sélection au-dessus de la source.
func set_selected(on: bool) -> void:
	if _selection_ring != null:
		_selection_ring.visible = on

## Quand on clique sur la source : montre l'anneau puis le fait disparaître.
func flash_selected() -> void:
	if _selection_ring == null:
		return
	set_selected(true)
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_callback(set_selected.bind(false))

func _process(delta: float) -> void:
	# Régénération lente : tant que le nœud existe, sa quantité remonte.
	if amount < max_amount and amount > 0:
		amount = mini(max_amount, amount + int(REGEN_RATE * delta))
		_update_visual()

## Crée le conteneur du modèle (les variantes s'échangent à l'intérieur).
func _build_model_root() -> void:
	_model_root = Node3D.new()
	_model_root.name = "Model"
	add_child(_model_root)
	# Échelle du modèle selon le type (les arbres sont grands, les rochers fins).
	match resource_type:
		ResourceType.WOOD:
			model_scale = 0.55
		ResourceType.STONE:
			model_scale = 1.0
		ResourceType.GOLD:
			model_scale = 1.0
		ResourceType.FOOD:
			model_scale = 0.7
	_model_root.scale = Vector3.ONE * model_scale

## Configure l'obstacle de navigation (évitement temps réel).
## La collision physique est désormais générée dynamiquement à partir du mesh du modèle.
func _setup_collision() -> void:
	var full := 1.6
	match resource_type:
		ResourceType.WOOD: full = 1.8
		ResourceType.STONE, ResourceType.GOLD: full = 1.6
		ResourceType.FOOD: full = 1.8
	
	var obs := NavigationObstacle3D.new()
	obs.name = "NavObstacle"
	obs.radius = full * 0.5
	obs.affect_navigation_mesh = false
	add_child(obs)

## Récolte [count] unités. Renvoie la quantité réellement prélevée (0 si vide).
func harvest(count: int) -> int:
	if amount <= 0:
		return 0
	var taken := mini(count, amount)
	amount -= taken
	_update_visual()
	if amount <= 0:
		depleted.emit()
	return taken

## Nombre de nœuds encore présents (pour le directeur du monde).
func exists() -> bool:
	return amount > 0

## Renvoie true tant qu'il reste de la ressource.
func has_left() -> bool:
	return amount > 0

## Nom affichable du type de ressource.
func display_name() -> String:
	match resource_type:
		ResourceType.GOLD: return "Or"
		ResourceType.WOOD: return "Bois"
		ResourceType.STONE: return "Pierre"
		ResourceType.FOOD: return "Nourriture"
	return "?"

## Met à jour le visuel : choisit la variante de modèle selon la quantité restante.
## ratio 1.0 → variante la plus grande (pleine), ratio ~0 → la plus petite (épuisée).
func _update_visual() -> void:
	var ratio: float = minf(1.0, float(amount) / float(max_amount)) if max_amount > 0 else 0.0
	if ratio <= 0.0:
		visible = false
		return
	visible = true
	var stages := _stages()
	if stages.is_empty():
		return
	var stage := _stage_for_ratio(ratio, stages.size())
	if stage != _current_stage:
		_current_stage = stage
		_swap_model(stages[stage])

## Renvoie la liste des variantes de modèle pour ce type (grand → petit).
func _stages() -> Array:
	match resource_type:
		ResourceType.WOOD:
			# Famille figée à la création : l'arbre reste toujours dans le même
			# répertoire (tree1, tree2 ou tree3) — plus de changement aléatoire.
			if _tree_family_index < 0:
				_tree_family_index = randi() % TREE_FAMILIES.size()
			return TREE_FAMILIES[_tree_family_index]
		ResourceType.STONE, ResourceType.GOLD:
			return ROCK_STAGES
		ResourceType.FOOD:
			return FOOD_STAGES
	return []

## Assigne un indice de stage (0..n-1) depuis un ratio (1.0 → 0, 0.0 → n-1).
func _stage_for_ratio(ratio: float, n: int) -> int:
	if n <= 1:
		return 0
	var idx := int((1.0 - ratio) * float(n - 1))
	return clampi(idx, 0, n - 1)

## Remplace le modèle courant par la variante donnée.
func _swap_model(stage: PackedScene) -> void:
	if _model_root == null:
		return
	# Nettoie l'ancien modèle ET les anciennes formes de collision générées.
	for child in _model_root.get_children():
		child.queue_free()
	for child in get_children():
		if child is CollisionShape3D:
			child.queue_free()

	var inst: Node = stage.instantiate()
	_model_root.add_child(inst)
	
	# GÉNÉRATION DE COLLISION PAR MESH :
	# On parcourt les meshes du modèle et on génère une forme de collision convexe
	# pour chacun. C'est beaucoup plus précis qu'une simple boîte.
	for mi in _collect_meshes(inst):
		var mesh_instance := mi as MeshInstance3D
		if mesh_instance.mesh != null:
			var shape := mesh_instance.mesh.create_convex_shape()
			var cs := CollisionShape3D.new()
			cs.shape = shape
			# On applique l'échelle et la position relative du mesh.
			cs.scale = mesh_instance.scale * model_scale
			cs.position = mesh_instance.position * model_scale
			add_child(cs)

	# Applique la texture forêt aux modèles...
	match resource_type:
		ResourceType.GOLD:
			_make_gold(inst)
		ResourceType.WOOD, ResourceType.STONE:
			_apply_forest_texture(inst)
		ResourceType.FOOD:
			_make_food(inst)

## Texture forêt partagée (chargée une seule fois).
var _forest_tex: Texture2D = null

## Applique la texture forêt à tous les meshes du modèle.
func _apply_forest_texture(node: Node) -> void:
	if _forest_tex == null:
		_forest_tex = load("res://assets/models/Mes assets/Textures/forest_texture.png") as Texture2D
	for mi in _collect_meshes(node):
		var mesh := mi as MeshInstance3D
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _forest_tex
		mat.roughness = 0.8
		mat.metallic = 0.0
		mesh.material_override = mat

## Applique un matériau doré à tous les meshes du modèle (source d'or).
func _make_gold(node: Node) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.8, 0.25)
	mat.metallic = 0.7
	mat.roughness = 0.3
	for mi in _collect_meshes(node):
		(mi as MeshInstance3D).material_override = mat

## Teinte rouge/baie pour les arbres fruitiers (nourriture), pour les distinguer visuellement des arbres à bois.
func _make_food(node: Node) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.5, 0.35)
	mat.roughness = 0.7
	mat.metallic = 0.0
	for mi in _collect_meshes(node):
		(mi as MeshInstance3D).material_override = mat

func _collect_meshes(node: Node, acc: Array = []) -> Array:
	if node is MeshInstance3D:
		acc.append(node)
	for c in node.get_children():
		acc = _collect_meshes(c, acc)
	return acc