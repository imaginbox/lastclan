class_name Monster
extends CharacterBody3D

## Faune hostile (PvE) : loup / sanglier / ours.
## - Peut être attaquée par le joueur (clic droit, groupe "enemy") et riposte.
## - Chasse les unités du joueur (groupe "player") si elle est agressive ou s'est
##   fait attaquer.
## - Lâche du butin à sa mort (signal `died`).

enum Type { WOLF, BOAR, BEAR }
enum State { IDLE, CHASE, ATTACK }

## Stats + butin par type. `aggressive` = chasse seule les unités proches ;
## une bête passive ne riposte que si on l'attaque.
const STATS: Dictionary = {
	Type.WOLF: {
		"hp": 40.0, "speed": 5.5, "damage": 8, "range": 1.4, "cd": 0.8,
		"aggro": 8.0, "aggressive": true, "scale": 0.85, "color": Color(0.55, 0.58, 0.63),
		"loot": [["wood", 12], ["food", 4]],
	},
	Type.BOAR: {
		"hp": 75.0, "speed": 4.0, "damage": 12, "range": 1.4, "cd": 1.1,
		"aggro": 5.0, "aggressive": false, "scale": 1.0, "color": Color(0.34, 0.25, 0.20),
		"loot": [["food", 15], ["wood", 6]],
	},
	Type.BEAR: {
		"hp": 140.0, "speed": 3.0, "damage": 22, "range": 1.6, "cd": 1.4,
		"aggro": 8.5, "aggressive": true, "scale": 1.35, "color": Color(0.43, 0.33, 0.27),
		"loot": [["stone", 12], ["gold", 8], ["food", 8]],
	},
}

const GRAVITY: float = 20.0

@export var type: int = Type.WOLF

var hp: float = 40.0
var max_hp: float = 40.0
var last_damage_ms: int = -100000
## Émis à la mort ; main.gd s'occupe du butin.
signal died(monster: Node)

var _state: int = State.IDLE
var _target: Node3D = null
var _attack_cd: float = 0.0
var _scan_t: float = 0.0
var _wander_t: float = 0.0
var _wander_point: Vector3 = Vector3.ZERO
var _spawn_pos: Vector3 = Vector3.ZERO

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

func _ready() -> void:
	# Ennemi attaquable (clic droit) + contre-attaquable par les soldats.
	add_to_group("enemy")
	_spawn_pos = global_position
	var s := _stat()
	max_hp = s.hp
	hp = max_hp
	_build_model(s)
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.5
	# Sol uniquement (gravité / ancrage), comme les autres unités : la faune
	# ne doit pas être freinée par les arbres/bâtiments/unités.
	collision_mask = 8
	_wander_point = _spawn_pos

func _stat() -> Dictionary:
	return STATS[type]

## Butin relâché à la mort : liste de [ressource, quantité].
func loot() -> Array:
	return _stat().loot

## Nom lisible du type de créature.
func _type_name() -> String:
	match int(type):
		Type.WOLF: return "Loup"
		Type.BOAR: return "Sanglier"
		Type.BEAR: return "Ours"
	return "Créature"

## Liste des caractéristiques affichées dans l'inspecteur (clic sur la créature).
func characteristics() -> Array:
	var s := _stat()
	return [
		["Rôle", "Faune hostile (%s)" % _type_name()],
		["Vie (endurance)", "%d / %d" % [int(hp), int(max_hp)]],
		["Rapidité", "%.2f" % s.speed],
		["Force", "%d" % s.damage],
		["Portée", "%.1f" % s.range],
		["Cadence", "%.1f s" % s.cd],
		["Agressif", "Oui" if s.aggressive else "Non"],
	]

# ============================================================ MODÈLE 3D (primitif)

func _build_model(s: Dictionary) -> void:
	var m := Node3D.new()
	m.name = "Model"
	add_child(m)
	var sc: float = s.scale
	var col: Color = s.color
	var body := _box(Vector3(0.7 * sc, 0.45 * sc, 1.15 * sc), Vector3(0, 0.55 * sc, 0), col)
	m.add_child(body)
	var head := _box(Vector3(0.34 * sc, 0.30 * sc, 0.34 * sc), Vector3(0, 0.92 * sc, -0.72 * sc), col.lightened(0.08))
	m.add_child(head)
	# 4 pattes.
	for leg in range(4):
		var lx := 0.26 * sc if leg % 2 == 0 else -0.26 * sc
		var lz := 0.38 * sc if leg < 2 else -0.38 * sc
		m.add_child(_box(Vector3(0.13 * sc, 0.55 * sc, 0.13 * sc), Vector3(lx, 0.275 * sc, lz), col.darkened(0.15)))
	# Queue vers +Z (arrière).
	m.add_child(_box(Vector3(0.10 * sc, 0.10 * sc, 0.45 * sc), Vector3(0, 0.72 * sc, 0.72 * sc), col.darkened(0.1)))
	# Yeux (deux petites sphères claires côté -Z = devant).
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.95, 0.9, 0.8)
	for ex in [-0.14 * sc, 0.14 * sc]:
		var eye := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.05 * sc
		sph.height = 0.1 * sc
		eye.mesh = sph
		eye.material_override = eye_mat
		eye.position = Vector3(ex, 1.0 * sc, -0.88 * sc)
		m.add_child(eye)

func _box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	# Position du CENTRE de la boîte.
	mi.position = pos
	return mi

# ============================================================ PHYSIQUE / VIE

func _gravity() -> float:
	var gc := get_node_or_null("/root/GameConfig")
	if gc != null:
		return -float(gc.get_value("jeu.gravite"))
	return GRAVITY

func _physics_process(delta: float) -> void:
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	if not is_on_floor():
		velocity.y -= _gravity() * delta
	else:
		velocity.y = -2.0
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.3
		_find_target()
	match _state:
		State.IDLE:
			_idle(delta)
		State.CHASE:
			_chase(delta)
		State.ATTACK:
			_attack(delta)

func _alive(u: Node) -> bool:
	if not is_instance_valid(u):
		return false
	if u.get("hp") != null:
		return float(u.get("hp")) > 0.0
	return true

func _find_target() -> void:
	# Cible actuelle toujours valide ? On garde.
	if _target != null and _alive(_target):
		return
	_target = null
	var s := _stat()
	# Bête passive : ne chasse pas d'elle-même (ne riposte que si attaquée).
	if not s.aggressive and _state == State.IDLE:
		return
	var best: Node3D = null
	var best_d := INF
	for u in get_tree().get_nodes_in_group("player"):
		if u is Node3D and _alive(u):
			var d: float = global_position.distance_squared_to((u as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = u as Node3D
	if best != null and best_d <= s.aggro * s.aggro:
		_set_chase_target(best)

## Désigne une unité du joueur comme cible et se met en chasse.
func _set_chase_target(u: Node3D) -> void:
	_target = u
	_state = State.CHASE
	nav_agent.target_position = u.global_position

# ============================================================ ÉTATS

func _idle(delta: float) -> void:
	_wander_t -= delta
	if _wander_t <= 0.0:
		_wander_t = randf_range(2.0, 5.0)
		_wander_point = _spawn_pos + Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-6.0, 6.0))
	if global_position.distance_to(_wander_point) < 0.7:
		velocity = Vector3.ZERO
		move_and_slide()
		return
	# Petit déplacement direct vers le point d'errance (pas besoin de navmesh).
	var dir := global_position.direction_to(_wander_point)
	dir.y = 0.0
	velocity = dir * _stat().speed * 0.35
	_facing(dir)
	move_and_slide()

func _chase(_delta: float) -> void:
	if _target == null or not _alive(_target):
		_target = null
		_state = State.IDLE
		return
	nav_agent.target_position = _target.global_position
	if global_position.distance_to(_target.global_position) <= _stat().range:
		_state = State.ATTACK
		return
	_steer(_stat().speed)
	move_and_slide()

func _attack(_delta: float) -> void:
	if _target == null or not _alive(_target):
		_target = null
		_state = State.IDLE
		return
	_facing(global_position.direction_to(_target.global_position))
	if global_position.distance_to(_target.global_position) > _stat().range:
		_state = State.CHASE
		return
	if _attack_cd <= 0.0 and _target.has_method("take_damage"):
		_target.call("take_damage", _stat().damage, global_position)
		_attack_cd = _stat().cd
	move_and_slide()

func _steer(speed: float) -> void:
	if nav_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		return
	var next := nav_agent.get_next_path_position()
	var dir := global_position.direction_to(next)
	dir.y = 0.0
	velocity = dir * speed
	_facing(dir)

func _facing(dir: Vector3) -> void:
	if dir.length_squared() > 0.0001:
		look_at(global_position + dir, Vector3.UP)

# ============================================================ DÉGÂTS / MORT

## Reçoit des dégâts. Riposte en visant l'unité du joueur la plus proche de
## l'attaquant (comme la défense auto des soldats), puis meurt à 0 PV.
func take_damage(amount: int, attacker_pos: Vector3 = Vector3.ZERO) -> void:
	hp -= amount
	last_damage_ms = Time.get_ticks_msec()
	var victim := _nearest_player(attacker_pos)
	if victim != null:
		_set_chase_target(victim)
	if hp <= 0.0:
		die()

func _nearest_player(from_pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for u in get_tree().get_nodes_in_group("player"):
		if u is Node3D and _alive(u):
			var from := global_position if from_pos == Vector3.ZERO else from_pos
			var d: float = from.distance_squared_to((u as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = u as Node3D
	return best

func die() -> void:
	died.emit(self)
	queue_free()

## Un monstre mort (ou en train d'être libéré) n'est plus une cible valide.
func is_dead() -> bool:
	return hp <= 0.0 or not is_inside_tree()
