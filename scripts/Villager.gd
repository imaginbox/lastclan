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
# de bord sans jamais déclencher la récolte.
# Distance de portée pour un déplacement libre (clic droit sur le sol) :
# précise, on s'arrête exactement sur le point.
const REACH_DISTANCE: float = 0.15
# Portée de RÉCOLTE : le paysan vise le CENTRE de la ressource mais l'arbre est
# un obstacle volumineux (~1m de rayon) découpé du navmesh. Il s'arrête donc au
# bord de l'arbre, pas au centre. Il faut une portée généreuse (> rayon de
# l'obstacle) pour déclencher la récolte, sinon il "bloque" au bord en boucle.
const GATHER_REACH: float = 1.4
# Rayon de livraison à l'hôtel de ville : ajusté à 2.0 pour un visuel propre.
const DELIVER_DISTANCE: float = 2.0
const VILLAGE_HALF: float = 60.0      # le paysan peut explorer une large zone autour de sa base
const ATTACK_RANGE: float = 1.5
const ATTACK_DAMAGE: int = 5
const ATTACK_COOLDOWN: float = 1.0
# PATHFINDING RÉACTIF : On réduit le timeout de blocage à 2.0s pour que le paysan
# cherche une autre route beaucoup plus vite s'il est gêné par un arbre.
const STUCK_TIMEOUT: float = 2.0
# Inventaire de transport : le paysan accumule jusqu'à MAX_CARRIED unités
# avant de rentrer livrer. Évite les allers-retours trop fréquents (boucle)
# ET l'immobilisation trop longue (figé pendant toute la récolte).
const MAX_CARRIED: int = 15

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
## Référence à un AnimationPlayer si présent (optionnel, pour tes modèles).
@onready var anim_player: AnimationPlayer = null

## Santé de l'unité : permet d'être endommagé par d'autres joueurs (combat PvP).
var hp: int = 60
var max_hp: int = 60
signal died
## Horodatage (ms) de la dernière fois que l'unité a reçu des dégâts. La barre
## de vie ne s'affiche que si une frappe a eu lieu récemment (elle disparaît dès
## qu'il n'y a plus d'attaques). Mis à jour dans take_damage.
var last_damage_ms: int = -100000

## Héros commandant cette unité (bonus de commandement) — null = unité libre.
var command_hero: Node = null

## True pendant le rappel de formation par le héros : court plus vite pour suivre.
var _following_hero: bool = false

var _state: State = State.IDLE
var _assigned_resource: ResourceNode = null   # ressource qu'il doit exploiter (boucle)
var _carried_type: ResourceNode.ResourceType = ResourceNode.ResourceType.GOLD
var _carried_amount: int = 0   # unités transportées avant livraison à l'hôtel de ville
var _gather_timer: float = 0.0
var _assigned_attack: Node3D = null
var _attack_cd: float = 0.0
var _town_hall: Node3D = null
# --- Filet anti-blocage : détecte l'absence de progression vers la cible ---
var _stuck_t: float = 0.0
var _last_dist: float = INF
var _watch_armed: bool = false
# --- Fuite (défense auto) : vrai tant que le paysan court vers son point de fuite ---
var _flee_active: bool = false
# --- Suivi d'animation (lissage Course/Idle basé sur le déplacement réel) ---
var _anim_prev_pos: Vector3 = Vector3.ZERO
var _anim_moving_buf: float = 0.0

func _ready() -> void:
	# PV et stats configurables via le panneau admin (mode admin).
	var gc := get_node_or_null("/root/GameConfig")
	if gc != null:
		max_hp = int(gc.get_value("unite.paysan.pv"))
		hp = max_hp
	# Bonus de commandement (héros) sur les PV max — appliqué au ready. Comme le
	# héros peut assigner l'unité plus tard, on re-applique via _apply_command_bonus().
	_apply_command_bonus()
	# AnimationPlayer : le modèle (VillagerModel) construit son AnimationPlayer
	# interne dans son propre _ready (exécuté avant celui-ci). On le récupère
	# via l'API du modèle pour rester robuste à la structure interne.
	var model := get_node_or_null("Model") as VillagerModel
	if model != null:
		anim_player = model.get_model_anim_player()
	nav_agent.path_desired_distance = 0.1
	nav_agent.target_desired_distance = 0.1
	
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
	# Le paysan ne détecte QUE le sol (couche 4, valeur 8) pour rester ancré par
	# gravité, mais GLISSE à travers les arbres/bâtiments/autres paysans (couches
	# 1 et 2). Le contournement des obstacles est entièrement géré par le NavMesh,
	# ce qui élimine tout blocage physique en chemin.
	collision_layer = 2
	collision_mask = 8
	# Sans ordre, il attend en place. La tâche par défaut (récolte) lui est
	# assignée depuis main.gd (ressource la plus proche) -> allers-retours infinis.
	_anim_prev_pos = global_position
	set_state(State.IDLE)

## Vitesse configurable (panneau admin) — retombe sur MOVE_SPEED.
func _move_speed() -> float:
	var gc := get_node_or_null("/root/GameConfig")
	var base: float = MOVE_SPEED
	if gc != null:
		base = float(gc.get_value("unite.paysan.vitesse"))
	var mult: float = _speed_mult()
	# Pendant le rappel de formation, on court AU MOINS aussi vite que le héros
	# (x1.2) pour le rattraper et finir en position autour de lui.
	if _following_hero and command_hero != null and is_instance_valid(command_hero):
		return maxf(base * mult, command_hero.call("command_follow_speed"))
	return base * mult

## Temps de récolte configurable (panneau admin).
func _gather_time() -> float:
	var gc := get_node_or_null("/root/GameConfig")
	if gc != null:
		return float(gc.get_value("unite.paysan.recolte"))
	return GATHER_TIME

## Charge max configurable (panneau admin).
func _max_carried() -> int:
	var gc := get_node_or_null("/root/GameConfig")
	if gc != null:
		return int(gc.get_value("unite.paysan.charge"))
	return MAX_CARRIED

## Dégâts/multiplicateur d'attaque configurables.
func _atk_damage() -> int:
	var gc := get_node_or_null("/root/GameConfig")
	var base: int = ATTACK_DAMAGE
	if gc != null:
		base = int(gc.get_value("unite.paysan.degats"))
	# Bonus de commandement (héros) : + damage%.
	if command_hero != null and is_instance_valid(command_hero):
		var m: float = command_hero.call("command_attack_mult")
		return int(float(base) * m)
	return base

## Multiplicateur de vitesse du paysan (bonus de commandement inclus).
func _speed_mult() -> float:
	if _following_hero and command_hero != null and is_instance_valid(command_hero):
		return command_hero.call("command_follow_speed_mult")
	if command_hero != null and is_instance_valid(command_hero):
		return command_hero.call("command_speed_mult")
	return 1.0

## Applique (ou retire) le bonus de commandement sur les PV max quand l'unité est
## assignée à un héros. Appelé au ready et quand le héros assigne/libère l'unité.
func _apply_command_bonus() -> void:
	var base_hp: int = max_hp
	var gc := get_node_or_null("/root/GameConfig")
	if gc != null:
		base_hp = int(gc.get_value("unite.paysan.pv"))
	var mult: float = 1.0
	if command_hero != null and is_instance_valid(command_hero):
		mult = command_hero.call("command_hp_mult")
	var new_max: int = maxi(int(float(base_hp) * mult), 1)
	max_hp = new_max
	hp = mini(hp, new_max)

## Signale au paysan son héros commandant (appelé par le héros). Recalcule le bonus.
func notify_command(hero: Node) -> void:
	command_hero = hero
	_apply_command_bonus()

## Gravité configurable (panneau admin, jeu.gravite, défaut -20) — positive au sol.
func _gravity() -> float:
	var gc := get_node_or_null("/root/GameConfig")
	if gc != null:
		return -float(gc.get_value("jeu.gravite"))
	return 20.0

func _physics_process(delta: float) -> void:
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	
	# GRAVITÉ : On applique la gravité par défaut pour que le paysan tombe sur le sol.
	if not is_on_floor():
		velocity.y -= _gravity() * delta # Gravité plus forte pour plaquer au sol
	else:
		velocity.y = -2.0 # Pression constante vers le bas
	
	# GESTION DES ANIMATIONS SELON LE MOUVEMENT RÉEL.
	# On mesure le déplacement RÉEL entre frames (position précédente) plutôt que la
	# vitesse instantanée, qui clignote à l'arrêt. Un court lissage évite les
	# transitions brusques Course -> Idle -> Course (sautillements visuels).
	var actual_move := global_position - _anim_prev_pos
	_anim_prev_pos = global_position
	_anim_moving_buf = lerpf(_anim_moving_buf, 1.0 if actual_move.length() > 0.02 else 0.0, 0.25)
	var moving := _anim_moving_buf > 0.3
	
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

## DÉFENSE AUTO : quand le paysan est attaqué, il FUITE (il n'est pas une unité
## de combat). Il s'éloigne de l'attaquant d'une certaine distance puis retourne
## à sa tâche automatique de récolte. Déclenché depuis main.gd (côté défenseur).
func react_to_attack(attacker_pos: Vector3) -> void:
	var away: Vector3 = global_position - attacker_pos
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1))
	away = away.normalized()
	var flee_dist: float = 10.0
	var base: Vector3 = Lobby.base_origin if Lobby.has_base else Vector3.ZERO
	var dest: Vector3 = global_position + away * flee_dist
	dest.x = clampf(dest.x, base.x - VILLAGE_HALF, base.x + VILLAGE_HALF)
	dest.z = clampf(dest.z, base.z - VILLAGE_HALF, base.z + VILLAGE_HALF)
	# On interrompt récolte/déplacement en cours et on fuit vers ce point.
	_assigned_attack = null
	nav_agent.target_position = dest
	_arm_watch()
	_flee_active = true
	set_state(State.MOVING)

## --- Logique interne ---

func _begin_gather(resource_node: ResourceNode) -> void:
	_assigned_resource = resource_node
	_carried_type = resource_node.resource_type
	_carried_amount = 0
	_gather_timer = 0.0
	# Le paysan vise le CENTRE de la ressource. Comme il traverse physiquement les
	# obstacles (collision_mask = sol uniquement), il peut s'approcher directement
	# jusqu'à GATHER_REACH sans être renvoyé au bord de l'arbre par le navmesh.
	# Légère décalage pour que plusieurs paysans se répartissent autour de la source.
	var approach := resource_node.global_position
	approach.x += randf_range(-0.6, 0.6)
	approach.z += randf_range(-0.6, 0.6)
	nav_agent.target_position = approach
	_arm_watch()
	set_state(State.GOING_TO_RESOURCE)

func _move_to_target(delta: float) -> void:
	# Filet anti-blocage : si le paysan n'avance plus vers sa cible (STUCK_TIMEOUT
	# sans progrès), on passe à la tâche suivante pour ne jamais rester à "courir
	# sans rien faire". _stuck_check a déjà re-routé une fois la navigation.
	if _stuck_check(delta):
		# On vide la ressource courante pour ne pas la re-sélectionner
		# et boucler indéfiniment sur une cible inaccessible.
		_assigned_resource = null
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
		# Portée de RÉCOLTE généreuse : le paysan s'arrête au bord de l'arbre
		# (obstacle ~1m de rayon) et déclenche la récolte, sans tourner en boucle.
		reached = _hdist(_assigned_resource.global_position) <= GATHER_REACH
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
	if _gather_timer >= _gather_time():
		_gather_timer = 0.0
		if _assigned_resource != null and _assigned_resource.has_left():
			# RENDEMENT ALÉATOIRE : récolte entre 1 et 5 unités à chaque coup.
			var amount := randi_range(1, 5)
			var taken: int = _assigned_resource.harvest(amount)
			if taken > 0:
				_carried_amount += taken
				_carried_type = _assigned_resource.resource_type
				_show_harvest_float(taken)
		
		# ALLER-RETOUR : dès que le paysan transporte MAINTENANT une charge complète
		# (MAX_CARRIED), il rentre livrer à l'hôtel de ville, même si la ressource
		# a encore du stock. L'économie n'est créditée qu'au DÉPÔT, pas à la récolte.
		if _carried_amount >= _max_carried():
			if _town_hall != null:
				nav_agent.target_position = _town_hall.global_position
				set_state(State.RETURNING)
			else:
				# Pas d'hôtel de ville : on livre la charge sur place pour ne rien perdre.
				_deliver_city()
			return
		
		# Charge pas encore pleine : on continue sur la même ressource si elle reste.
		if _assigned_resource != null and _assigned_resource.has_left():
			return
		
		# Ressource épuisée avant le chargement complet : on cherche une remplaçante
		# DU MÊME TYPE pour finir la charge avant de rentrer.
		var replacement := _find_nearest_of_type(_carried_type)
		if replacement != null:
			_begin_gather(replacement)
			return

		# Aucune ressource de ce type restante : on rentre livrer ce qu'on a (même
		# partiel, pour ne jamais bloquer l'économie sur une charge inachevée).
		if _carried_amount > 0 and _town_hall != null:
			nav_agent.target_position = _town_hall.global_position
			set_state(State.RETURNING)
		elif _carried_amount > 0:
			_deliver_city()
		else:
			_select_next_task()

func _return_to_townhall(delta: float) -> void:
	if _town_hall == null:
		_select_next_task()
		return
	# Dépôt effectué dès que le paysan est RÉELLEMENT près de l'hôtel de ville.
	# Distance souple pour éviter que les paysans ne courent contre les murs.
	if _town_hall != null and _hdist(_town_hall.global_position) <= DELIVER_DISTANCE:
		_deliver_city()
		return
	# Détection par contact avec l'hôtel de ville.
	if get_slide_collision_count() > 0:
		for i in get_slide_collision_count():
			if get_slide_collision(i).get_collider() == _town_hall:
				_deliver_city()
				return
	# Filet anti-blocage : si le paysan n'avance plus vers l'hôtel de ville, on
	# RE-ROUTE la navigation (le paysan doit faire TOUT le chemin). On NE livre
	# PAS à distance : dépôt à mi-chemin = on ne crédite pas l'économie correctement.
	if _stuck_check(delta):
		if _hdist(_town_hall.global_position) <= DELIVER_DISTANCE * 1.5:
			_deliver_city()
			return
		_step(delta)
		return
	_step(delta)

## Dépôt effectif de la charge à l'hôtel de ville : crédite l'économie de la ville
## avec la quantité transportée, puis choisit la prochaine tâche (retour à la
## récolte). C'est ici, et non à la récolte, que la ressource entre dans le stock.
func _deliver_city() -> void:
	if _carried_amount > 0:
		var amount: int = _carried_amount
		# Bonus de récolte du royaume (prospérité / déclin) + activité collective.
		var realm := get_node_or_null("/root/Realm")
		if realm != null:
			var bonus: float = 1.0
			if realm.has_method("harvest_bonus"):
				bonus = float(realm.call("harvest_bonus"))
			amount = int(round(float(amount) * bonus))
			if realm.has_method("activity"):
				realm.call("activity", 0.3)
		match _carried_type:
			ResourceNode.ResourceType.GOLD:
				ResourceManager.add_gold(amount)
			ResourceNode.ResourceType.WOOD:
				ResourceManager.add_wood(amount)
			ResourceNode.ResourceType.STONE:
				ResourceManager.add_stone(amount)
			ResourceNode.ResourceType.FOOD:
				ResourceManager.add_food(amount)
		resource_delivered.emit(_carried_type, amount)
	_carried_amount = 0
	_select_next_task()

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
			_assigned_attack.call("take_damage", _atk_damage(), self.global_position)
			_attack_cd = ATTACK_COOLDOWN
	else:
		_assigned_attack = null
		_select_next_task()

func _move_to_point_state(delta: float) -> void:
	# Filet anti-blocage : si le paysan ne peut pas atteindre le point demandé
	# (ex. point dans un obstacle/un trou), on s'arrête au repos au lieu de
	# courir indéfiniment dans le vide.
	if _stuck_check(delta):
		_finish_move()
		return
	# Se rend au point demandé puis passe au repos (IDLE). Distance horizontale :
	# la hauteur Y ne doit pas empêcher de considérer le point comme atteint.
	if _hdist(nav_agent.target_position) <= REACH_DISTANCE:
		_finish_move()
		return
	_step(delta)

## Fin d'un déplacement vers un point (fuite OU ordre libre). Si c'était une
## fuite (défense auto), le paysan reprend sa tâche automatique de récolte ;
## sinon il reste au repos (déplacement libre classique).
func _finish_move() -> void:
	if _flee_active:
		_flee_active = false
		_select_next_task()
	else:
		set_state(State.IDLE)

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
	# Bloqué trop longtemps : on essaie de se dégager.
	if _stuck_t >= STUCK_TIMEOUT:
		_arm_watch()
		# On force un nouveau calcul de chemin pour contourner le blocage.
		nav_agent.target_position = nav_agent.get_final_position()
		# On donne une petite poussée vers le prochain point pour franchir le blocage,
		# et on réinitialise la vitesse pour repartir proprement.
		var next := nav_agent.get_next_path_position()
		var dir := global_position.direction_to(next)
		if dir.length_squared() > 0.0001:
			velocity = dir * _move_speed()
		else:
			velocity = Vector3.ZERO
		return true
	return false

func _step(_delta: float) -> void:
	# DÉPLACEMENT DIRECT : le paysan vise la DESTINATION DEMANDÉE (target_position),
	# pas les waypoints intermédiaires du navmesh. Comme il traverse physiquement
	# tous les obstacles (collision_mask = sol uniquement), suivre les waypoints ne
	# sert à rien et provoquait des oscillations (le paysan "tournait dans tous les
	# sens"). get_final_position() peut être déformé par un obstacle navmesh ; on
	# vise donc directement le point demandé -> stable et sans blocage.
	var target := nav_agent.target_position
	
	var to_target := target - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	
	var desired := Vector3.ZERO
	if dist > 0.001:
		desired = to_target.normalized() * _move_speed()
		_facing(to_target)
	
	_apply_movement(desired)

func _apply_movement(vel: Vector3) -> void:
	# Lissage : la vitesse converge doucement vers la vitesse horizontale désirée,
	# ce qui adoucit les démarrages/arrêts. La gravité (Y) reste inchangée.
	var target_xz := Vector2(vel.x, vel.z)
	var cur_xz := Vector2(velocity.x, velocity.z)
	cur_xz = cur_xz.lerp(target_xz, 0.15)
	velocity.x = cur_xz.x
	velocity.z = cur_xz.y
	# On conserve la vitesse verticale (gravité) calculée dans _physics_process
	
	move_and_slide()
	
	# Le clamp "rester au village" ne s'applique que si le paysan N'est PAS en
	# train de suivre son héros : sinon il serait bloqué à la limite de la base
	# dès que le héros part en expédition hors de la zone (± VILLAGE_HALF).
	if not _following_hero:
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
	if s != State.MOVING:
		_following_hero = false
	_state = s
	# Arrêt immédiat de la physique ET de l'animation de course lors d'un arrêt.
	if _state in [State.GATHERING, State.ATTACKING, State.IDLE]:
		velocity = Vector3.ZERO
		# On s'assure qu'on est bien posé au sol
		move_and_slide()
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

## --- Santé / Combat PvP ---
## Reçoit des dégâts d'une unité adverse. Meurt quand la santé tombe à 0.
func take_damage(amount: int, attacker_pos: Vector3 = Vector3.ZERO) -> void:
	hp -= amount
	last_damage_ms = Time.get_ticks_msec()
	# Défense auto : l'unité touchée réagit immédiatement (fuit l'attaquant).
	react_to_attack(attacker_pos)
	if hp <= 0:
		die()

func die() -> void:
	died.emit()
	queue_free()
