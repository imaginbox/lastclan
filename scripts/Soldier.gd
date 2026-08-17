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
	# PV et stats configurables via le panneau admin (mode admin).
	var gc := get_node_or_null("/root/GameConfig")
	if gc != null:
		max_hp = int(gc.get_value("unite.soldat.pv"))
		hp = max_hp
	_apply_command_bonus()
	# Marque le modèle comme soldat (choix du modèle 3D dans le panel admin).
	var mod := get_node_or_null("Model") as VillagerModel
	if mod != null:
		mod.is_soldier = true
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

## Vitesse configurable (panneau admin) — retombe sur MOVE_SPEED.
func _move_speed() -> float:
	var gc := get_node_or_null("/root/GameConfig")
	var base: float = MOVE_SPEED
	if gc != null:
		base = float(gc.get_value("unite.soldat.vitesse"))
	var mult: float = _speed_mult()
	base = base * UnitStats.speed_scale(self)
	# Pendant le rappel de formation, on court AU MOINS aussi vite que le héros
	# (x1.2) pour le rattraper et finir en position autour de lui. Sans ça, si le
	# héros est plus rapide que base*mult, la troupe reste à la traîne à jamais.
	if _following_hero and command_hero != null and is_instance_valid(command_hero):
		return maxf(base * mult, command_hero.call("command_follow_speed"))
	return base * mult

## Dégâts configurable.
func _atk_damage() -> int:
	var gc := get_node_or_null("/root/GameConfig")
	var base: int = ATTACK_DAMAGE
	if gc != null:
		base = int(gc.get_value("unite.soldat.degats"))
	base = int(float(base) * UnitStats.damage_scale(self))
	if command_hero != null and is_instance_valid(command_hero):
		return int(float(base) * command_hero.call("command_attack_mult"))
	return base

## Héros commandant cette unité — null = unité libre.
var command_hero: Node = null

## True quand le héros rappelle cette unité en formation : elle court plus vite
## pour pouvoir se replacer AUTOUR du héros (devant lui) pendant son déplacement.
var _following_hero: bool = false

func _speed_mult() -> float:
	if _following_hero and command_hero != null and is_instance_valid(command_hero):
		return command_hero.call("command_follow_speed_mult")
	if command_hero != null and is_instance_valid(command_hero):
		return command_hero.call("command_speed_mult")
	return 1.0

func _apply_command_bonus() -> void:
	var base_hp: int = max_hp
	var gc := get_node_or_null("/root/GameConfig")
	if gc != null:
		base_hp = int(gc.get_value("unite.soldat.pv"))
	var mult: float = 1.0
	if command_hero != null and is_instance_valid(command_hero):
		mult = command_hero.call("command_hp_mult")
	var new_max: int = maxi(int(float(base_hp) * UnitStats.hp_scale(self) * mult), 1)
	max_hp = new_max
	hp = mini(hp, new_max)

func notify_command(hero: Node) -> void:
	command_hero = hero
	_apply_command_bonus()

## Liste des caractéristiques affichées dans l'inspecteur (clic sur l'unité).
func characteristics() -> Array:
	return [
		["Rôle", "Soldat"],
		["Niveau ville", str(UnitStats.town_hall_level(self))],
		["Vie (endurance)", "%d / %d" % [hp, max_hp]],
		["Rapidité", "%.2f" % _move_speed()],
		["Force", "%d" % _atk_damage()],
		["Portée", "%.1f" % _atk_range()],
		["Cadence", "%.1f s" % _atk_cd()],
		["État", _state_label()],
	]

func _state_label() -> String:
	match int(_state):
		Soldier.State.ATTACK: return "Combat"
		Soldier.State.MOVE: return "Se déplace"
	return "En attente"

## Portée configurable.
func _atk_range() -> float:
	var gc := get_node_or_null("/root/GameConfig")
	if gc != null:
		return float(gc.get_value("unite.soldat.portee"))
	return ATTACK_RANGE

## Cadence d'attaque configurable.
func _atk_cd() -> float:
	var gc := get_node_or_null("/root/GameConfig")
	if gc != null:
		return float(gc.get_value("unite.soldat.cadence"))
	return ATTACK_COOLDOWN

## Gravité configurable (panneau admin, jeu.gravite, défaut -20) — positive au sol.
func _gravity() -> float:
	var gc := get_node_or_null("/root/GameConfig")
	if gc != null:
		return -float(gc.get_value("jeu.gravite"))
	return 20.0

func _physics_process(delta: float) -> void:
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	# GRAVITÉ : plaquer le soldat au sol (comme le paysan). Sans elle le corps
	# peut dériver verticalement pendant le déplacement et sembler disparaître.
	if not is_on_floor():
		velocity.y -= _gravity() * delta
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
	_following_hero = false
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
		if global_position.distance_to(_target.global_position) <= _atk_range():
			_state = State.ATTACK
			return
	elif nav_agent.is_navigation_finished() and global_position.distance_to(_move_point) <= REACH_DISTANCE:
		_state = State.IDLE
		_following_hero = false
		return
	_step(delta)

## Distance horizontale (plan XZ) à un point — utilisée par le héros pour
## ré-aiguiller en continu la troupe (chaque membre vers sa position de formation).
## Sans cette méthode, les soldats ne sont JAMAIS ré-aimés par _physics_process du
## héros et restent à la traîne une fois leur 1er ordre terminé.
func _hdist(pt: Vector3) -> float:
	var dx: float = pt.x - global_position.x
	var dz: float = pt.z - global_position.z
	return sqrt(dx * dx + dz * dz)

func _attack(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_target = null
		_state = State.IDLE
		return
	if global_position.distance_to(_target.global_position) > _atk_range():
		_state = State.MOVE
		return
	if _attack_cd <= 0.0 and _target.has_method("take_damage"):
		_target.call("take_damage", _atk_damage(), self.global_position)
		_attack_cd = _atk_cd()

func _step(_delta: float) -> void:
	var target := nav_agent.target_position
	var dir := target - global_position
	dir.y = 0.0
	var dist := dir.length()
	if dist > 0.001:
		dir = dir.normalized()
		velocity = dir * _move_speed() * minf(1.0, dist / 1.5)
		_facing(dir)
	else:
		velocity = Vector3.ZERO
	move_and_slide()
	# On reste dans la zone jouable autour de la base — sauf si on suit le héros
	# (sinon le soldat serait bloqué à la limite pendant une expédition).
	if not _following_hero:
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