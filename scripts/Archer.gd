class_name Archer
extends CharacterBody3D

## Archer — unité de combat À DISTANCE entraînée depuis la caserne.
## Comme le soldat (sélection + ordres + troupe du héros) mais attaque de loin :
## il s'arrête à distance et tire une flèche (projectile) qui vole jusqu'à la
## cible et lui inflige des dégâts. Placé à l'arrière de la formation, il reste
## protégé derrière les soldats tout en engageant la faune/les ennemis.

enum State { IDLE, MOVE, ATTACK }

const MOVE_SPEED: float = 3.6
const REACH_DISTANCE: float = 0.8
const ATTACK_RANGE: float = 6.0
const ATTACK_DAMAGE: int = 7
const ATTACK_COOLDOWN: float = 1.4
const VILLAGE_HALF: float = 190.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

@export var anim_idle: StringName = &"Idle"
@export var anim_run: StringName = &"Run"

@onready var anim_player: AnimationPlayer = null

## Santé de l'unité : endommageable par les ennemis (faune / PvP).
var hp: int = 70
var max_hp: int = 70
signal died
var last_damage_ms: int = -100000

var _state: State = State.IDLE
var _move_point: Vector3 = Vector3.ZERO
var _target: Node3D = null
var _attack_cd: float = 0.0

func _ready() -> void:
	var gc := get_node_or_null("/root/GameConfig")
	if gc != null:
		var pv = gc.get_value("unite.archer.pv")
		if pv != null:
			max_hp = int(pv)
			hp = max_hp
	_apply_command_bonus()
	var model := get_node_or_null("Model") as Node
	if model != null:
		# Le modèle sait lire son AnimationPlayer (VillagerModel).
		if model.has_method("get_model_anim_player"):
			anim_player = model.call("get_model_anim_player")
		# Arc visible dans la main.
		_build_bow(model)
	nav_agent.path_desired_distance = REACH_DISTANCE
	nav_agent.target_desired_distance = REACH_DISTANCE
	collision_mask = 8

## Petit arc en bois tenu à la main (distingue l'archer du soldat).
func _build_bow(model: Node) -> void:
	var bow := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.05
	cyl.height = 0.7
	bow.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.32, 0.16)
	bow.material_override = mat
	bow.position = Vector3(0.22, 0.95, 0.05)
	bow.rotation_degrees.z = 15.0
	model.add_child(bow)

## Vitesse configurable.
func _move_speed() -> float:
	var gc := get_node_or_null("/root/GameConfig")
	var base: float = MOVE_SPEED
	if gc != null:
		var v = gc.get_value("unite.archer.vitesse")
		if v != null:
			base = float(v)
	var mult: float = _speed_mult()
	if _following_hero and command_hero != null and is_instance_valid(command_hero):
		return maxf(base * mult, command_hero.call("command_follow_speed"))
	return base * mult

func _atk_damage() -> int:
	var gc := get_node_or_null("/root/GameConfig")
	var base: int = ATTACK_DAMAGE
	if gc != null:
		var v = gc.get_value("unite.archer.degats")
		if v != null:
			base = int(v)
	if command_hero != null and is_instance_valid(command_hero):
		return int(float(base) * command_hero.call("command_attack_mult"))
	return base

## Héros commandant cette unité — null = unité libre.
var command_hero: Node = null
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
		var pv = gc.get_value("unite.archer.pv")
		if pv != null:
			base_hp = int(pv)
	var mult: float = 1.0
	if command_hero != null and is_instance_valid(command_hero):
		mult = command_hero.call("command_hp_mult")
	var new_max: int = maxi(int(float(base_hp) * mult), 1)
	max_hp = new_max
	hp = mini(hp, new_max)

func notify_command(hero: Node) -> void:
	command_hero = hero
	_apply_command_bonus()

func _atk_range() -> float:
	var gc := get_node_or_null("/root/GameConfig")
	if gc != null:
		var v = gc.get_value("unite.archer.portee")
		if v != null:
			return float(v)
	return ATTACK_RANGE

func _atk_cd() -> float:
	var gc := get_node_or_null("/root/GameConfig")
	if gc != null:
		var v = gc.get_value("unite.archer.cadence")
		if v != null:
			return float(v)
	return ATTACK_COOLDOWN

func _gravity() -> float:
	var gc := get_node_or_null("/root/GameConfig")
	if gc != null:
		return -float(gc.get_value("jeu.gravite"))
	return 20.0

func _physics_process(delta: float) -> void:
	_attack_cd = maxf(_attack_cd - delta, 0.0)
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

# ============================================================ API PUBLIQUE

func move_to_point(point: Vector3) -> void:
	_target = null
	_move_point = Vector3(point.x, 0.0, point.z)
	nav_agent.target_position = _move_point
	_state = State.MOVE

func attack_target(target: Node3D) -> void:
	_following_hero = false
	_target = target
	_state = State.MOVE
	nav_agent.target_position = target.global_position

func set_selected(on: bool) -> void:
	var model := get_node_or_null("Model") as Node
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

func react_to_attack(attacker_pos: Vector3) -> void:
	var closest: Node3D = _nearest_enemy(attacker_pos)
	if closest != null:
		attack_target(closest)
	else:
		_target = null
		_state = State.IDLE

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

# ============================================================ LOGIQUE

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
	_facing(global_position.direction_to(_target.global_position))
	if _attack_cd <= 0.0:
		_fire_arrow()
		_attack_cd = _atk_cd()

## Tire une flèche vers la cible (dégâts appliqués à l'arrivée).
func _fire_arrow() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var arrow := Arrow.new()
	scene.add_child(arrow)
	arrow.setup(global_position + Vector3(0, 1.1, 0), _target, _atk_damage())

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
		_sel_material.albedo_color = Color(0.3, 0.8, 0.3)
		_sel_material.emission_enabled = true
		_sel_material.emission = Color(0.3, 0.9, 0.3)
		_sel_material.emission_energy = 2.0
	return _sel_material

func _is_sel_material(mat: Material) -> bool:
	return mat == _sel_material

# ============================================================ SANTÉ / COMBAT

func take_damage(amount: int, attacker_pos: Vector3 = Vector3.ZERO) -> void:
	hp -= amount
	last_damage_ms = Time.get_ticks_msec()
	react_to_attack(attacker_pos)
	if hp <= 0:
		die()

func die() -> void:
	died.emit()
	queue_free()
