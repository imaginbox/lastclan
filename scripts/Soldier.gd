class_name Soldier
extends CharacterBody3D

## Soldier — unité de combat entraînée depuis la caserne.
## États : IDLE (immobile), MOVE (déplacement vers un point ou une cible),
## ATTACK (combat à portée). Contrôlable comme un paysan (sélection + ordres).

enum State { IDLE, MOVE, ATTACK }

const MOVE_SPEED: float = 4.0
const REACH_DISTANCE: float = 0.8
const ATTACK_RANGE: float = 1.6
const ATTACK_DAMAGE: int = 6
const ATTACK_COOLDOWN: float = 1.0
const VILLAGE_HALF: float = 190.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

@export var anim_idle: StringName = &"Idle"
@export var anim_run: StringName = &"Run"

@onready var anim_player: AnimationPlayer = null

## Santé de l'unité : permet d'être endommagé par d'autres joueurs (combat PvP).
var hp: int = 80
var max_hp: int = 80
signal died
## Horodatage (ms) de la dernière fois que l'unité a reçu des dégâts. La barre
## ne s'affiche que si une frappe a eu lieu récemment (disparaît sans attaques).
var last_damage_ms: int = -100000

var _state: State = State.IDLE
var _move_point: Vector3 = Vector3.ZERO
var _target: Node3D = null
var _attack_cd: float = 0.0

func _ready() -> void:
	# AnimationPlayer fourni par le modèle (VillagerModel).
	var model := get_node_or_null("Model") as VillagerModel
	if model != null:
		anim_player = model.get_model_anim_player()
	nav_agent.path_desired_distance = REACH_DISTANCE
	nav_agent.target_desired_distance = REACH_DISTANCE
	# Comme le paysan, le soldat ne détecte QUE le sol pour s'y ancrer par gravité
	# (il traverse arbres/bâtiments). Sans ça il peut dériver verticalement et
	# paraître "disparaître" lorsqu'on le déplace.
	collision_mask = 8

func _physics_process(delta: float) -> void:
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	# GRAVITÉ : plaquer le soldat au sol (comme le paysan). Sans elle le corps
	# peut dériver verticalement pendant le déplacement et sembler disparaître.
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = -2.0
	match _state:
		State.IDLE:
			velocity = Vector3.ZERO
			_anim(anim_idle)
		State.MOVE:
			_anim(anim_run)
			_move(delta)
		State.ATTACK:
			_anim(anim_idle)
			_attack(delta)

## --- API publique ---
## Se déplace vers un point du sol.
func move_to_point(point: Vector3) -> void:
	_target = null
	_move_point = Vector3(point.x, 0.0, point.z)
	nav_agent.target_position = _move_point
	_state = State.MOVE

## Attaque une cible (nœud avec take_damage).
func attack_target(target: Node3D) -> void:
	_target = target
	_state = State.MOVE
	nav_agent.target_position = target.global_position

func set_selected(on: bool) -> void:
	# Met en évidence le modèle via une émission (contour lumineux).
	var model := get_node_or_null("Model") as VillagerModel
	if model == null:
		return
	var mesh := model.find_child("char1", true, false) as MeshInstance3D
	if mesh == null:
		return
	if on:
		mesh.material_override = _sel_mat()
	elif mesh.material_override != null and mesh.material_override.has_method("get") \
			and _is_sel_material(mesh.material_override):
		mesh.material_override = null

## DÉFENSE AUTO : quand le soldat est attaqué, il CONTRE-ATTAQUE l'unité ennemie
## la plus proche (via la position de l'attaquant). S'il n'y a plus d'ennemi à
## portée notable, il retourne au repos. Déclenché depuis main.gd (côté défenseur).
func react_to_attack(attacker_pos: Vector3) -> void:
	var closest: Node3D = _nearest_enemy(attacker_pos)
	if closest != null:
		attack_target(closest)
	else:
		# Plus d'ennemi visible : retour au repos.
		_target = null
		_state = State.IDLE

## Cherche l'unité ennemie (groupe "enemy") la plus proche de ce soldat, en
## privilégiant celle la plus proche de l'ATTAQUANT (pour bien riposter celui
## qui nous a frappé).
func _nearest_enemy(attacker_pos: Vector3 = Vector3.ZERO) -> Node3D:
	var best: Node3D = null
	var best_d: float = INF
	for node in get_tree().get_nodes_in_group("enemy"):
		if node is Node3D:
			var to_att := INF
			if attacker_pos != Vector3.ZERO:
				to_att = (node as Node3D).global_position.distance_squared_to(attacker_pos)
			else:
				to_att = global_position.distance_squared_to((node as Node3D).global_position)
			if to_att < best_d:
				best_d = to_att
				best = node as Node3D
	return best

## --- Logique ---
func _move(delta: float) -> void:
	if _target != null and is_instance_valid(_target):
		nav_agent.target_position = _target.global_position
		if global_position.distance_to(_target.global_position) <= ATTACK_RANGE:
			_state = State.ATTACK
			return
	elif nav_agent.is_navigation_finished() and global_position.distance_to(_move_point) <= REACH_DISTANCE:
		_state = State.IDLE
		return
	_step(delta)

func _attack(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_target = null
		_state = State.IDLE
		return
	if global_position.distance_to(_target.global_position) > ATTACK_RANGE:
		_state = State.MOVE
		return
	if _attack_cd <= 0.0 and _target.has_method("take_damage"):
		_target.call("take_damage", ATTACK_DAMAGE, self.global_position)
		_attack_cd = ATTACK_COOLDOWN

func _step(_delta: float) -> void:
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
	# On reste dans la zone jouable autour de la base du joueur.
	var base: Vector3 = Lobby.base_origin if Lobby.has_base else Vector3.ZERO
	global_position.x = clampf(global_position.x, base.x - VILLAGE_HALF, base.x + VILLAGE_HALF)
	global_position.z = clampf(global_position.z, base.z - VILLAGE_HALF, base.z + VILLAGE_HALF)

func _facing(dir: Vector3) -> void:
	if dir.length_squared() > 0.0001:
		look_at(global_position + dir, Vector3.UP)

func _anim(anim_name: StringName) -> void:
	if anim_player != null and anim_player.has_animation(anim_name) and anim_player.current_animation != anim_name:
		anim_player.play(anim_name)

var _sel_material: StandardMaterial3D = null
func _sel_mat() -> StandardMaterial3D:
	if _sel_material == null:
		_sel_material = StandardMaterial3D.new()
		_sel_material.albedo_color = Color(0.85, 0.2, 0.2)
		_sel_material.emission_enabled = true
		_sel_material.emission = Color(0.9, 0.3, 0.3)
		_sel_material.emission_energy = 2.0
	return _sel_material

func _is_sel_material(mat: Material) -> bool:
	return mat == _sel_material

## --- Santé / Combat PvP ---
## Reçoit des dégâts d'une unité adverse. Meurt quand la santé tombe à 0.
func take_damage(amount: int, attacker_pos: Vector3 = Vector3.ZERO) -> void:
	hp -= amount
	last_damage_ms = Time.get_ticks_msec()
	# Défense auto : le soldat contre-attaque l'ennemi le plus proche.
	react_to_attack(attacker_pos)
	if hp <= 0:
		die()

func die() -> void:
	died.emit()
	queue_free()