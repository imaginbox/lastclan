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
# Distance de portée : assez grande pour que le paysan atteigne une ressource
# malgré sa collision (arbre : boîte 1.8 → bord à 0.9 + rayon 0.35 = ~1.25).
# Anciennement 1.2, trop juste pour les arbres : le paysan restait bloqué au
# bord sans jamais déclencher la récolte.
# Distance de portée : ajustée à 2.2 pour être proche de la source sans coller.
const REACH_DISTANCE: float = 2.2
# Rayon de livraison à l'hôtel de ville : ajusté à 2.6 pour un visuel propre.
const DELIVER_DISTANCE: float = 2.6
const VILLAGE_HALF: float = 60.0      # le paysan peut explorer une large zone autour de sa base
const ATTACK_RANGE: float = 1.5
const ATTACK_DAMAGE: int = 5
const ATTACK_COOLDOWN: float = 1.0
# PATHFINDING RÉACTIF : On réduit le timeout de blocage à 2.0s pour que le paysan
# cherche une autre route beaucoup plus vite s'il est gêné par un arbre.
const STUCK_TIMEOUT: float = 2.0

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
# --- Filet anti-blocage : détecte l'absence de progression vers la cible ---
var _stuck_t: float = 0.0
var _last_dist: float = INF
var _watch_armed: bool = false

func _ready() -> void:
	# AnimationPlayer : le modèle (VillagerModel) construit son AnimationPlayer
	# interne dans son propre _ready (exécuté avant celui-ci). On le récupère
	# via l'API du modèle pour rester robuste à la structure interne.
	var model := get_node_or_null("Model") as VillagerModel
	if model != null:
		anim_player = model.get_model_anim_player()
	nav_agent.path_desired_distance = 1.0
	nav_agent.target_desired_distance = REACH_DISTANCE
	
	# NAVIGATION AMÉLIORÉE : On ajuste les paramètres pour plus de fluidité.
	# path_max_distance : si on s'éloigne trop du chemin (ex: poussé par une collision),
	# on recalcule immédiatement la route.
	nav_agent.path_max_distance = 2.0
	
	# On active le post-processing pour lisser les virages et éviter les coins abrupts.
	# Note: Cela dépend du support dans la version Godot, on reste sur du standard robuste.
	
	# ÉVITEMENT DÉSACTIVÉ : Pour éviter tout blocage ou trajectoire hésitante entre paysans...
	# nav_agent.velocity_computed.connect(_on_velocity_computed) # Retiré pour le ghosting
	_town_hall = get_tree().get_first_node_in_group("town_hall") as Node3D
	# COUCHES DE COLLISION :
	# COLLISION GHOST : Le paysan est guidé à 100% par le NavMesh.
	# Il n'a plus besoin de masque de collision car le NavMesh contient déjà
	# les trous pour les arbres et les bâtiments. Cela supprime tout risque
	# de rester "collé" physiquement à un objet.
	collision_layer = 2
	collision_mask = 0
	# Sans ordre, il attend en place. La tâche par défaut (récolte) lui est
	# assignée depuis main.gd (ressource la plus proche) -> allers-retours infinis.
	set_state(State.IDLE)

func _physics_process(delta: float) -> void:
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	
	# GESTION DES ANIMATIONS SELON LE MOUVEMENT RÉEL
	# Si on est censé courir mais qu'on ne bouge pas (bloqué contre un mur/arbre),
	# on joue l'animation Idle pour éviter de "courir dans le vide".
	var moving := velocity.length() > 0.2
	
	match _state:
		State.IDLE:
			_anim(anim_idle)
		State.GOING_TO_RESOURCE, State.RETURNING, State.GOING_TO_ATTACK, State.MOVING:
			if moving:
				_anim(anim_run)
			else:
				_anim(anim_idle)
			
			# Dispatch des mouvements
			if _state == State.GOING_TO_RESOURCE: _move_to_target(delta)
			elif _state == State.RETURNING: _return_to_townhall(delta)
			elif _state == State.GOING_TO_ATTACK: _move_to_attack(delta)
			elif _state == State.MOVING: _move_to_point_state(delta)
			
		State.GATHERING, State.ATTACKING:
			_anim(anim_work)
			if _state == State.GATHERING: _gather(delta)
			else: _attack(delta)

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
	_arm_watch()
	set_state(State.MOVING)

## --- Logique interne ---

func _begin_gather(resource_node: ResourceNode) -> void:
	_assigned_resource = resource_node
	_carried_type = resource_node.resource_type
	_gather_timer = 0.0
	# Légère décalage aléatoire autour de la source : plusieurs paysans affectés à
	# la même ressource se répartissent autour d'elle au lieu de s'empiler au centre.
	var approach := resource_node.global_position
	approach.x += randf_range(-0.9, 0.9)
	approach.z += randf_range(-0.9, 0.9)
	# La ressource est découpée comme obstacle dans le navmesh : si le point
	# aléatoire tombe dans cet obstacle, aucun chemin n'existe et le paysan reste
	# bloqué au bord. On projette donc le point sur le navmesh -> il atterrit juste
	# sur le bord atteignable de la source, toujours accessible (REACH_DISTANCE couvre).
	var nav_map := get_world_3d().navigation_map
	# Ne projette sur le navmesh que si la carte est synchronisée (sinon la requête
	# échoue avec "before first map synchronization"). Sinon on garde le point brut,
	# la navigation se rajustera naturellement dès que le navmesh sera prêt.
	if NavigationServer3D.map_is_active(nav_map) and NavigationServer3D.map_get_iteration_id(nav_map) > 0:
		approach = NavigationServer3D.map_get_closest_point(nav_map, approach)
	nav_agent.target_position = approach
	_arm_watch()
	set_state(State.GOING_TO_RESOURCE)

func _move_to_target(delta: float) -> void:
	# Filet anti-blocage : si le paysan n'avance plus vers sa cible (STUCK_TIMEOUT
	# sans progrès), on passe à la tâche suivante pour ne jamais rester à "courir
	# sans rien faire". _stuck_check a déjà re-routé une fois la navigation.
	if _stuck_check(delta):
		_select_next_task()
		return
	# Arrivée basée sur la distance HORIZONTALE (plan XZ) : le terrain en gradins
	# donne une différence de hauteur Y qui gonflerait la distance 3D et empêcherait
	# d'atteindre REACH_DISTANCE même juste à côté de la ressource.
	# On juge l'arrivée par rapport à la POSITION DE LA RESSOURCE (pas le point
	# d'approche décalé). On est très permissif (REACH_DISTANCE=4.0) et on ajoute
	# une détection par collision : si le paysan touche l'arbre, il récolte.
	var reached: bool = false
	if _assigned_resource != null:
		reached = _hdist(_assigned_resource.global_position) <= REACH_DISTANCE
		# Détection par contact : si on bute contre la ressource, c'est qu'on est arrivé.
		if not reached and get_slide_collision_count() > 0:
			for i in get_slide_collision_count():
				if get_slide_collision(i).get_collider() == _assigned_resource:
					reached = true
					break
	else:
		reached = _hdist(nav_agent.target_position) <= REACH_DISTANCE
	
	if reached:
		if _assigned_resource != null and _assigned_resource.has_left():
			_gather_timer = 0.0
			set_state(State.GATHERING)
		else:
			_select_next_task()
		return
	_step(delta)

func _gather(delta: float) -> void:
	# RÉCOLTE = À L'ARRÊT : on coupe l'évitement et toute vitesse résiduelle pour
	# que le paysan ne bouge pas d'un pixel pendant qu'il récolte (contrairement au
	# déplacement où on dévie des obstacles). Re-activé au passage dans un état de
	# déplacement (voir _begin_gather / _move_to_attack).
	nav_agent.avoidance_enabled = false
	velocity = Vector3.ZERO
	_gather_timer += delta
	if _gather_timer >= GATHER_TIME:
		_gather_timer = 0.0
		if _assigned_resource != null and _assigned_resource.has_left():
			# RENDEMENT ALÉATOIRE : récolte entre 1 et 5 unités à chaque coup.
			var amount := randi_range(1, 5)
			var taken: int = _assigned_resource.harvest(amount)
			if taken > 0:
				_add_harvest_to_city(taken)
				_carried_type = _assigned_resource.resource_type
				_show_harvest_float(taken)
		
		# Si la ressource est épuisée suite à ce coup, on cherche immédiatement une
		# remplaçante DU MÊME TYPE avant de décider de rentrer ou non.
		if _assigned_resource == null or not _assigned_resource.has_left():
			var replacement := _find_nearest_of_type(_carried_type)
			if replacement != null:
				_begin_gather(replacement)
				return

		if _town_hall != null:
			nav_agent.target_position = _town_hall.global_position
			set_state(State.RETURNING)
		else:
			_select_next_task()

func _return_to_townhall(delta: float) -> void:
	if _town_hall == null:
		_select_next_task()
		return
	# Filet anti-blocage : si le paysan n'arrive plus à l'hôtel de ville, on livre
	# quand même (le dépôt touche l'économie) pour ne pas rester bloqué à courir.
	if _stuck_check(delta):
		resource_delivered.emit(_carried_type, 1)
		_select_next_task()
		return
	# Dépôt effectué dès que le paysan est assez près de l'hôtel de ville.
	# Distance très souple (4.5) pour éviter que les paysans ne courent contre les murs.
	if _town_hall != null and _hdist(_town_hall.global_position) <= DELIVER_DISTANCE:
		resource_delivered.emit(_carried_type, 1)
		_select_next_task()
		return
	# Détection par contact avec l'hôtel de ville.
	if get_slide_collision_count() > 0:
		for i in get_slide_collision_count():
			if get_slide_collision(i).get_collider() == _town_hall:
				resource_delivered.emit(_carried_type, 1)
				_select_next_task()
				return
	_step(delta)

## Choisit l'activité suivante (souvent après une livraison ou un épuisement).
func _select_next_task() -> void:
	# REPLI INTELLIGENT : si la ressource en cours est épuisée, on cherche d'abord
	# la source la plus proche du MÊME type.
	var next: ResourceNode = null
	if _assigned_resource != null and _assigned_resource.has_left():
		next = _assigned_resource
	else:
		next = _find_nearest_of_type(_carried_type)
	
	# Si ce type est totalement épuisé sur la carte, on se rabat sur le type
	# le plus nécessaire (loi d'émergence globale).
	if next == null:
		next = _nearest_resource()
		
	if next != null:
		_begin_gather(next)
	else:
		_assigned_resource = null
		set_state(State.IDLE)

## Cherche la ressource la plus proche d'un type spécifique.
func _find_nearest_of_type(t: ResourceNode.ResourceType) -> ResourceNode:
	var best: ResourceNode = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("resource"):
		var r := node as ResourceNode
		if r != null and r.resource_type == t and r.has_left():
			var d := global_position.distance_squared_to(r.global_position)
			if d < best_d:
				best_d = d
				best = r
	return best

## Affiche le nombre de récolte cartoonesque au-dessus de la source.
func _show_harvest_float(taken: int) -> void:
	if _assigned_resource == null:
		return
	var world := get_tree().get_first_node_in_group("world")
	if world == null or not world.has_method("show_float_text"):
		return
	var pos := _assigned_resource.global_position + Vector3(0.0, 2.4, 0.0)
	world.call("show_float_text", pos, "+%d" % taken, _resource_color(_assigned_resource.resource_type))

## Couleur du nombre flottant selon le type de ressource.
func _resource_color(t: ResourceNode.ResourceType) -> Color:
	match t:
		ResourceNode.ResourceType.GOLD: return Color(1.0, 0.85, 0.3)   # or
		ResourceNode.ResourceType.WOOD: return Color(0.55, 0.9, 0.4)   # bois/vert
		ResourceNode.ResourceType.STONE: return Color(0.8, 0.82, 0.88) # pierre
		ResourceNode.ResourceType.FOOD: return Color(0.9, 0.25, 0.25)  # nourri./rouge
	return Color.WHITE

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
		ResourceNode.ResourceType.FOOD:
			ResourceManager.add_food(taken)

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
	if ResourceManager.food < worst:
		worst = ResourceManager.food
		worst_type = ResourceNode.ResourceType.FOOD
	return worst_type

func _move_to_attack(delta: float) -> void:
	if _assigned_attack == null or not is_instance_valid(_assigned_attack):
		_assigned_attack = null
		_select_next_task()
		return
	nav_agent.target_position = _assigned_attack.global_position
	if _hdist(_assigned_attack.global_position) <= ATTACK_RANGE:
		set_state(State.ATTACKING)
		return
	_step(delta)

func _attack(_delta: float) -> void:
	if _assigned_attack != null and is_instance_valid(_assigned_attack):
		if _hdist(_assigned_attack.global_position) > ATTACK_RANGE:
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
	# Filet anti-blocage : si le paysan ne peut pas atteindre le point demandé
	# (ex. point dans un obstacle/un trou), on s'arrête au repos au lieu de
	# courir indéfiniment dans le vide.
	if _stuck_check(delta):
		set_state(State.IDLE)
		return
	# Se rend au point demandé puis passe au repos (IDLE). Distance horizontale :
	# la hauteur Y ne doit pas empêcher de considérer le point comme atteint.
	if _hdist(nav_agent.target_position) <= REACH_DISTANCE:
		set_state(State.IDLE)
		return
	_step(delta)

## Distance HORIZONTALE (plan XZ) jusqu'à un point. Les vérifications d'arrivée
## utilisent cette distance plutôt que la distance 3D : sur le terrain en gradins,
## une ressource sur une butte et un paysan en contrebas ont une différence de
## hauteur Y qui interdisait à la distance 3D de descendre sous REACH_DISTANCE,
## le paysan "courait sans rien faire" à jamais juste à côté de sa cible.
func _hdist(pt: Vector3) -> float:
	var dx: float = pt.x - global_position.x
	var dz: float = pt.z - global_position.z
	return sqrt(dx * dx + dz * dz)

## Réarme la surveillance de progression (appelé quand la cible change).
func _arm_watch() -> void:
	_stuck_t = 0.0
	_last_dist = INF
	_watch_armed = true

## Renvoie true si le paysan n'a pas progressé vers sa cible depuis STUCK_TIMEOUT.
## L'appelant ré-aiguille/re-route alors la navigation pour le débloquer.
func _stuck_check(delta: float) -> bool:
	if not _watch_armed:
		return false
	var d: float = _hdist(nav_agent.target_position)
	if d < _last_dist - 0.02:
		_last_dist = d
		_stuck_t = 0.0
	else:
		_stuck_t += delta
	# Bloqué trop longtemps : on essaie de se dégager radicalement.
	if _stuck_t >= STUCK_TIMEOUT:
		_arm_watch()
		# On se déplace vers le prochain point de passage immédiatement pour "sauter" le blocage.
		var next := nav_agent.get_next_path_position()
		var dir := global_position.direction_to(next)
		global_position += dir * 0.4
		nav_agent.target_position = nav_agent.get_final_position()
		return true
	return false

func _step(_delta: float) -> void:
	var target := nav_agent.target_position
	var desired := Vector3.ZERO
	var map_ready: bool = NavigationServer3D.map_get_iteration_id(nav_agent.get_navigation_map()) > 0
	
	# RE-ROUTAGE AGRESSIF : Si le paysan hésite ou semble ralentir contre un obstacle,
	# on force une réévaluation de la position suivante.
	if map_ready and not nav_agent.is_navigation_finished():
		var next := nav_agent.get_next_path_position()
		desired = next - global_position
		desired.y = 0.0
	else:
		desired = target - global_position
		desired.y = 0.0
	
	var dist := desired.length()
	if dist > 0.001:
		# On augmente la précision du virage
		desired = desired.normalized() * MOVE_SPEED
		_facing(desired)
	else:
		desired = Vector3.ZERO
	
	_apply_movement(desired)

func _apply_movement(vel: Vector3) -> void:
	velocity = vel
	move_and_slide()
	
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
	# Arrêt immédiat de la physique ET de l'animation de course lors d'un arrêt.
	if _state in [State.GATHERING, State.ATTACKING, State.IDLE]:
		velocity = Vector3.ZERO
		nav_agent.set_velocity(Vector3.ZERO)
		if anim_player != null:
			anim_player.stop() # Stoppe l'animation en cours (Course) immédiatement

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
