class_name Villager
extends CharacterBody3D

## Villager — paysan contrôlé par IA via NavigationAgent3D.
## Machine à états :
##   GOING_TO_RESOURCE    -> se rend vers une ressource
##   GATHERING            -> récolte (2s, anim Work)
##   RETURNING            -> transporte la ressource jusqu'à l'hôtel de ville
##   GOING_TO_ATTACK      -> se rend vers une cible ennemie
##   ATTACKING            -> combat une cible à portée
## Comportement par défaut : chaque paysan est assigné à une ressource et enchaîne
## des allers-retours automatiques (récolte -> dépôt à l'hôtel de ville -> récolte).

signal resource_delivered(resource_type: ResourceNode.ResourceType, amount: int)

enum State { IDLE, GOING_TO_RESOURCE, GATHERING, RETURNING, GOING_TO_ATTACK, ATTACKING, MOVING }

## --- Noms d'animations configurables (remplacés par tes modèles Meshy) ---
@export var anim_idle: StringName = &"Idle"
@export var anim_run: StringName = &"Run"
@export var anim_work: StringName = &"Idle"

const MOVE_SPEED: float = 3.0
const GATHER_TIME: float = 2.0
const REACH_DISTANCE: float = 1.2
# Rayon de livraison à l'hôtel de ville : doit être assez grand pour être atteint
# malgré la collision de la bâtisse (les paysans s'arrêtent à son bord, pas au centre).
const DELIVER_DISTANCE: float = 2.5
const VILLAGE_HALF: float = 60.0      # le paysan peut explorer une large zone autour de sa base
const ATTACK_RANGE: float = 1.5
const ATTACK_DAMAGE: int = 5
const ATTACK_COOLDOWN: float = 1.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
## Référence à un AnimationPlayer si présent (optionnel, pour tes modèles).
@onready var anim_player: AnimationPlayer = null

var _state: State = State.IDLE
var _assigned_resource: ResourceNode = null   # ressource qu'il doit exploiter (boucle)
var _carried_type: ResourceNode.ResourceType = ResourceNode.ResourceType.GOLD
var _gather_timer: float = 0.0
var _assigned_attack: Node3D = null
var _attack_cd: float = 0.0
var _town_hall: Node3D = null

func _ready() -> void:
	# AnimationPlayer : le modèle (VillagerModel) construit son AnimationPlayer
	# interne dans son propre _ready (exécuté avant celui-ci). On le récupère
	# via l'API du modèle pour rester robuste à la structure interne.
	var model := get_node_or_null("Model") as VillagerModel
	if model != null:
		anim_player = model.get_model_anim_player()
	nav_agent.path_desired_distance = REACH_DISTANCE
	nav_agent.target_desired_distance = REACH_DISTANCE
	_town_hall = get_tree().get_first_node_in_group("town_hall") as Node3D
	# Le paysan ne percute que les obstacles/unités (couche 1), pas le sol (couche 2).
	collision_mask = 1
	# Sans ordre, il attend en place. La tâche par défaut (récolte) lui est
	# assignée depuis main.gd (ressource la plus proche) -> allers-retours infinis.
	set_state(State.IDLE)

func _physics_process(delta: float) -> void:
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	match _state:
		State.IDLE:
			_anim(anim_idle)
		State.GOING_TO_RESOURCE:
			_anim(anim_run)
			_move_to_target(delta)
		State.GATHERING:
			_anim(anim_work)
			_gather(delta)
		State.RETURNING:
			_anim(anim_run)
			_return_to_townhall(delta)
		State.GOING_TO_ATTACK:
			_anim(anim_run)
			_move_to_attack(delta)
		State.ATTACKING:
			_anim(anim_work)
			_attack(delta)
		State.MOVING:
			_anim(anim_run)
			_move_to_point_state(delta)

## --- API publique ---

## Ordre de récolte (clic droit sur une ressource pour tous les sélectionnés).
## Interrompt l'activité en cours et assigne immédiatement la ressource.
func send_to_gather(resource_node: ResourceNode) -> void:
	if resource_node == null or not resource_node.has_left():
		return
	_begin_gather(resource_node)

## Ordre d'attaque (framework : aucun ennemi pour l'instant, mais branché).
func attack_node(target: Node3D) -> void:
	if target == null:
		return
	_assigned_attack = target
	nav_agent.target_position = target.global_position
	set_state(State.GOING_TO_ATTACK)

func set_selected(on: bool) -> void:
	# Met en évidence le modèle (mesh "char1") via une émission lumineuse.
	var model := get_node_or_null("Model") as VillagerModel
	if model == null:
		return
	var mesh := model.find_child("char1", true, false) as MeshInstance3D
	if mesh == null:
		return
	if on:
		mesh.material_override = _sel_mat()
	elif mesh.material_override != null and _is_sel_material(mesh.material_override):
		mesh.material_override = null

## Ordre de déplacement (clic droit sur le sol vide) : le paysan s'y rend
## puis s'arrête au repos (il interrompt sa tâche de récolte en cours).
func move_to_point(point: Vector3) -> void:
	_assigned_resource = null
	_assigned_attack = null
	nav_agent.target_position = point
	set_state(State.MOVING)

## --- Logique interne ---

func _begin_gather(resource_node: ResourceNode) -> void:
	_assigned_resource = resource_node
	_carried_type = resource_node.resource_type
	_gather_timer = 0.0
	nav_agent.target_position = resource_node.global_position
	set_state(State.GOING_TO_RESOURCE)

func _move_to_target(delta: float) -> void:
	# Arrivée basée sur la distance réelle (robuste) plutôt que sur le drapeau
	# "is_navigation_finished" (peu fiable juste après un changement de cible).
	if global_position.distance_to(nav_agent.target_position) <= REACH_DISTANCE:
		if _assigned_resource != null and _assigned_resource.has_left():
			_gather_timer = 0.0
			set_state(State.GATHERING)
		else:
			_select_next_task()
		return
	_step(delta)

func _gather(delta: float) -> void:
	_gather_timer += delta
	if _gather_timer >= GATHER_TIME:
		if _assigned_resource != null and _assigned_resource.has_left():
			var taken: int = _assigned_resource.harvest(1)
			if taken > 0:
				_add_harvest_to_city(taken)
				_carried_type = _assigned_resource.resource_type
		if _town_hall != null:
			nav_agent.target_position = _town_hall.global_position
			set_state(State.RETURNING)
		else:
			_select_next_task()

func _return_to_townhall(delta: float) -> void:
	if _town_hall == null:
		_select_next_task()
		return
	# Dépôt effectué dès que le paysan est assez près de l'hôtel de ville
	# (au bord de la bâtisse, pas à son centre). -> enchaînement automatique.
	if global_position.distance_to(_town_hall.global_position) <= DELIVER_DISTANCE:
		resource_delivered.emit(_carried_type, 1)
		_select_next_task()
		return
	_step(delta)

## Après le dépôt, repart sur la même ressource si elle a encore des ressources,
## sinon sur la ressource disponible la plus proche -> allers-retours automatiques.
func _select_next_task() -> void:
	var next: ResourceNode = null
	if _assigned_resource != null and _assigned_resource.has_left():
		next = _assigned_resource
	else:
		next = _nearest_resource()
	if next != null:
		_begin_gather(next)
	else:
		# Plus de ressources exploitables : le paysan s'arrête en place,
		# il ne repartira que sur un ordre (récolte/attaque).
		_assigned_resource = null
		set_state(State.IDLE)

## Ajoute la récolte à l'économie de la ville selon son type.
func _add_harvest_to_city(taken: int) -> void:
	if _assigned_resource == null:
		return
	match _assigned_resource.resource_type:
		ResourceNode.ResourceType.GOLD:
			ResourceManager.add_gold(taken)
		ResourceNode.ResourceType.WOOD:
			ResourceManager.add_wood(taken)
		ResourceNode.ResourceType.STONE:
			ResourceManager.add_stone(taken)

## Choix intelligent de la ressource suivante.
## Loi simple d'émergence : le paysan vise le type de ressource le plus rare dans
## la ville (le plus utile), puis la source de ce type la plus proche. Comme tous
## les paysans suivent cette loi, la rareté se déplace et ils se rééquilibrent
## naturellement entre or / bois / pierre.
func _nearest_resource() -> ResourceNode:
	var target_type := _scarcest_type()
	var best: ResourceNode = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("resource"):
		var r := node as ResourceNode
		if r != null and r.has_left():
			# Privilégie le type le plus rare, mais accepte les autres s'il est absent.
			var d := global_position.distance_squared_to(r.global_position)
			if r.resource_type == target_type:
				d -= 1000.0  # forte préférence pour le type le plus utile
			if d < best_d:
				best_d = d
				best = r
	return best

## Renvoie le type de ressource dont la ville a le plus besoin (le plus bas stock).
func _scarcest_type() -> ResourceNode.ResourceType:
	var gold := ResourceManager.gold
	var wood := ResourceManager.wood
	var stone := ResourceManager.stone
	var worst := gold
	var worst_type := ResourceNode.ResourceType.GOLD
	if wood < worst:
		worst = wood
		worst_type = ResourceNode.ResourceType.WOOD
	if stone < worst:
		worst = stone
		worst_type = ResourceNode.ResourceType.STONE
	return worst_type

func _move_to_attack(delta: float) -> void:
	if _assigned_attack == null or not is_instance_valid(_assigned_attack):
		_assigned_attack = null
		_select_next_task()
		return
	nav_agent.target_position = _assigned_attack.global_position
	if global_position.distance_to(_assigned_attack.global_position) <= ATTACK_RANGE:
		set_state(State.ATTACKING)
		return
	_step(delta)

func _attack(_delta: float) -> void:
	if _assigned_attack != null and is_instance_valid(_assigned_attack):
		if global_position.distance_to(_assigned_attack.global_position) > ATTACK_RANGE:
			nav_agent.target_position = _assigned_attack.global_position
			set_state(State.GOING_TO_ATTACK)
			return
		if _attack_cd <= 0.0 and _assigned_attack.has_method("take_damage"):
			_assigned_attack.call("take_damage", ATTACK_DAMAGE)
			_attack_cd = ATTACK_COOLDOWN
	else:
		_assigned_attack = null
		_select_next_task()

func _move_to_point_state(delta: float) -> void:
	# Se rend au point demandé puis passe au repos (IDLE).
	if global_position.distance_to(nav_agent.target_position) <= REACH_DISTANCE:
		set_state(State.IDLE)
		return
	_step(delta)

func _step(_delta: float) -> void:
	# Déplacement direct vers la destination finale (target_position).
	var target := nav_agent.target_position
	var dir := target - global_position
	dir.y = 0.0
	var dist := dir.length()
	if dist > 0.001:
		dir = dir.normalized()
		velocity = dir * MOVE_SPEED * minf(1.0, dist / 1.5)
		_facing(dir)
	else:
		velocity = Vector3.ZERO
	move_and_slide()
	# Filet de sécurité : on reste dans la zone jouable autour de la base du joueur.
	var base: Vector3 = Lobby.base_origin if Lobby.has_base else Vector3.ZERO
	global_position.x = clampf(global_position.x, base.x - VILLAGE_HALF - 2.0, base.x + VILLAGE_HALF + 2.0)
	global_position.z = clampf(global_position.z, base.z - VILLAGE_HALF - 2.0, base.z + VILLAGE_HALF + 2.0)

func _facing(dir: Vector3) -> void:
	if dir.length_squared() > 0.0001:
		look_at(global_position + dir, Vector3.UP)

func _anim(anim_name: StringName) -> void:
	if anim_player != null and anim_player.has_animation(anim_name) and anim_player.current_animation != anim_name:
		anim_player.play(anim_name)

func set_state(s: State) -> void:
	_state = s

var _sel_material: StandardMaterial3D = null

func _sel_mat() -> StandardMaterial3D:
	if _sel_material == null:
		_sel_material = StandardMaterial3D.new()
		_sel_material.albedo_color = Color(0.3, 1.0, 0.35)
		_sel_material.emission_enabled = true
		_sel_material.emission = Color(0.3, 1.0, 0.35)
		_sel_material.emission_energy = 2.0
	return _sel_material

func _is_sel_material(mat: Material) -> bool:
	return mat == _sel_material
