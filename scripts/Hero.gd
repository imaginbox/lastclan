class_name Hero
extends CharacterBody3D

## Hero — le commandant du village (style Rise of Kingdoms / Call of Dragons).
## On NE sélectionne que ce héros pour commander sa troupe : les unités qui lui
## sont assignées (paysans/soldats) le suivent en formation collée et reçoivent
## un BONUS DE COMMANDEMENT permanent (dégâts / PV / vitesse) qui croît avec
## son niveau et celui de l'HDV.
##
## Machine à états :
##   IDLE            -> immobile (troupe en formation autour de lui)
##   MOVING          -> se déplace vers un point (la troupe suit en formation)
##   MOVING_TO_ATTACK/ATTACKING -> combat à la tête de sa troupe

enum State { IDLE, MOVING, MOVING_TO_ATTACK, ATTACKING }

const MOVE_SPEED: float = 4.2
const REACH_DISTANCE: float = 0.6
const ATTACK_RANGE: float = 1.9
const ATTACK_DAMAGE: int = 8
const ATTACK_COOLDOWN: float = 1.1
const VILLAGE_HALF: float = 190.0
# Capacité de troupe de base (au niveau 1 du héros).
const BASE_TROOP_CAPACITY: int = 10
# Bonus de commandement de base par niveau de héros (multiplicateur).
const COMMAND_BONUS_PER_LEVEL: float = 0.10   # +10% / niveau de héros
# Contribution du bonus par niveau d'HDV (progression A).
const HDV_BONUS_PER_LEVEL: float = 0.04       # +4% / niveau d'HDV

enum UnitKind { VILLAGER, SOLDIER }
enum ProfileKind { COMMANDER, GATHERER, STRATEGIST }

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var anim_player: AnimationPlayer = null

## Santé / stats du héros (configurables admin).
var hp: int = 150
var max_hp: int = 150
signal died
var last_damage_ms: int = -100000

## Progression.
var level: int = 1
var xp: int = 0          # XP accumulée (gain en combattant / en récoltant)
var xp_to_next: int = 100

## Profil (spécialisation). Pour l'instant un seul profil : Commandant.
var profile: int = ProfileKind.COMMANDER

# --- Troupe assignée ---
var _troop: Array = []          # unités (Villager/Soldier) assignées à ce héros
var _formation_spots: Array = []  # offsets locaux de la formation (Vector3)

var _state: State = State.IDLE
var _move_target: Vector3 = Vector3.ZERO
var _attack_target: Node3D = null
var _attack_cd: float = 0.0
var _anim_prev_pos: Vector3 = Vector3.ZERO
signal troop_changed

func _ready() -> void:
	var gc := get_node_or_null("/root/GameConfig")
	if gc != null:
		max_hp = int(gc.get_value("hero.pv"))
		hp = max_hp
	var model := get_node_or_null("Model") as Node3D
	if model != null and model.has_method("get_model_anim_player"):
		anim_player = model.get_model_anim_player()
	nav_agent.path_desired_distance = REACH_DISTANCE
	nav_agent.target_desired_distance = REACH_DISTANCE
	nav_agent.path_max_distance = 2.5
	collision_layer = 2
	collision_mask = 8
	_anim_prev_pos = global_position
	_build_formation_spots()
	set_state(State.IDLE)

# ======================================================================
# STATS (avec bonus de commandement HDV)
# ======================================================================

func _move_speed() -> float:
	var gc := get_node_or_null("/root/GameConfig")
	var base: float = MOVE_SPEED
	if gc != null:
		var v = gc.get_value("hero.vitesse")
		if v != null:
			base = float(v)
	return base

func _atk_damage() -> int:
	var gc := get_node_or_null("/root/GameConfig")
	var base: int = ATTACK_DAMAGE
	if gc != null:
		var v = gc.get_value("hero.degats")
		if v != null:
			base = int(v)
	return int(base * _scale_level())

func _attack_range() -> float:
	return ATTACK_RANGE

func _attack_cooldown() -> float:
	return ATTACK_COOLDOWN

## Progression A — multiplicateur global des stats du héros selon sa propre
## progression (niveau). L'HDV agit sur la TROUPE via _command_bonus_mult().
func _scale_level() -> float:
	return 1.0 + (level - 1) * 0.08

# ======================================================================
# CAPACITÉ / PROFIL
# ======================================================================

## Capacité de troupe du héros = base + bonus par niveau de héros + bonus HDV.
func troop_capacity() -> int:
	var cap := BASE_TROOP_CAPACITY + (level - 1) * 2
	var gc := get_node_or_null("/root/GameConfig")
	if gc != null:
		var v = gc.get_value("hero.capacite_base")
		if v != null:
			cap = int(v) + (level - 1) * 2
	# La progression de l'HDV augmente aussi la capacité (débloque plus de troupes).
	var th := _town_hall()
	if th != null:
		cap += int(th.level) * 2
	return maxi(cap, 1)

## Bonus de commandement (option A — permanent tant que l'unité est assignée).
## = f(profil) * f(niveau héros) * f(niveau HDV).
func _command_bonus_mult() -> float:
	var mult := 1.0
	# Bonus individuel du profil.
	match profile:
		ProfileKind.GATHERER:
			mult = 1.0 + COMMAND_BONUS_PER_LEVEL   # bonus défini par héritage
		_:
			mult = 1.0
	# Bonus de niveau du héros (tous les rôles).
	var lvl_bonus := 1.0 + (level - 1) * COMMAND_BONUS_PER_LEVEL
	# Bonus de l'HDV (progression A : +4% / niveau HDV).
	var hdv_bonus := 1.0
	var th := _town_hall()
	if th != null:
		hdv_bonus = 1.0 + (th.level - 1) * HDV_BONUS_PER_LEVEL
	return mult * lvl_bonus * hdv_bonus

## Bonus de commandement EXPOSÉ pour les unités assignées : le multiplicateur à
## appliquer à leurs stats.
func command_attack_mult() -> float:
	return _command_bonus_mult()
func command_hp_mult() -> float:
	return _command_bonus_mult()
func command_speed_mult() -> float:
	return 1.0 + (_command_bonus_mult() - 1.0) * 0.5

func _town_hall() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("town_hall") as Node

# ======================================================================
# TROUPE
# ======================================================================

func troop_size() -> int:
	return _troop.size()

func has_space() -> bool:
	return troop_size() < troop_capacity()

## Assigne une unité existante au héros. Retourne true si ok.
func assign_unit(unit: Node) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	if unit == self:
		return false
	if not has_space():
		return false
	if _troop.has(unit):
		return true
	_troop.append(unit)
	if unit.has_method("notify_command"):
		unit.call("notify_command", self)
	_build_formation_spots()
	# Tire toute la troupe vers sa formation autour du héros : l'unité affectée
	# (même si elle récoltait) vient maintenant rejoindre le héros.
	_move_troop_to_formation()
	troop_changed.emit()
	return true

func unassign_unit(unit: Node) -> void:
	_troop.erase(unit)
	# Libère l'unité : elle perd le bonus de commandement et cesse de suivre le héros.
	if unit != null and is_instance_valid(unit) and unit.has_method("notify_command"):
		unit.call("notify_command", null)
	_build_formation_spots()
	troop_changed.emit()

func unassign_all() -> void:
	_troop.clear()
	_build_formation_spots()
	troop_changed.emit()

func troop_has(unit: Node) -> bool:
	return _troop.has(unit)

## Nombre d'unités du type donné dans la troupe.
func troop_count(kind: int) -> int:
	var n := 0
	for u in _troop:
		if kind == UnitKind.VILLAGER and u is Villager:
			n += 1
		elif kind == UnitKind.SOLDIER and u is Soldier:
			n += 1
	return n

## Construit les offsets de formation autour du héros.
## Logique « risque » :
##  - Soldats présents -> ils forment un anneau RAPPROCHÉ autour du héros (au plus
##    près, en plein cercle), et les paysans restent DERRIÈRE eux (arc arrière plus
##    large, protégés des combats).
##  - UNIQUEMENT des paysans -> ils se forment comme des soldats (anneau complet
##    autour du héros) car aucun front n'est à protéger.
## Les spots sont indexés par _troop[i] (même ordre), requis par le rappel.
## Construit les offsets de formation en RÉFÉRENTIEL LOCAL du héros (avant = -Z).
## La rotation du héros est appliquée à l'usage (_formation_spot_world), donc la
## formation pivote toujours avec l'orientation du héros.
##  - Soldats : ANNEAU complet autour du héros (le héros reste au centre).
##  - Paysans : ARC au DOS du héros (local +Z), à un rayon supérieur à l'anneau
##    des soldats => complètement derrière le cercle des soldats.
##  - Uniquement des paysans : anneau rond comme des soldats.
## Les spots restent indexés par _troop[i] (même ordre) pour le rappel.
func _build_formation_spots() -> void:
	_formation_spots.clear()
	var troop: Array = _troop
	var soldier_count := 0
	for u in troop:
		if u is Soldier:
			soldier_count += 1
	var peasant_count: int = troop.size() - soldier_count

	const A_FWD := -PI / 2.0   # angle local de l'avant (-Z) du héros

	# UNIQUEMENT des paysans (ou aucune troupe) : anneau rond comme des soldats.
	if soldier_count == 0:
		var n := troop.size()
		var radius: float = 0.0
		if n > 0:
			radius = 1.1 + sqrt(float(n)) * 0.35
		var step := TAU / maxi(n, 1)
		for i in n:
			_formation_spots.append(_ring_spot(A_FWD + step * float(i), radius))
		return

	# FORMATION MIXTE : soldats en anneau (cercle), paysans en arc derrière.
	var rs: float = 1.1 + sqrt(float(maxi(soldier_count, 1))) * 0.35
	var s_step := TAU / maxi(soldier_count, 1)

	# Paysans : arc au DOS du héros (local +Z = opposé de l'avant -Z), à un rayon
	# supérieur à celui de l'anneau des soldats pour être complètement derrière.
	var rp: float = rs + 1.4 + sqrt(float(maxi(peasant_count, 1))) * 0.35
	var back_center := A_FWD + PI   # local +Z : exactement au dos du héros
	var spread: float = 2.2
	var half := spread * 0.5

	var s_idx := 0
	var p_idx := 0
	for i in troop.size():
		if troop[i] is Soldier:
			_formation_spots.append(_ring_spot(A_FWD + s_step * float(s_idx), rs))
			s_idx += 1
		else:
			var angle: float = back_center
			if peasant_count > 1:
				angle = back_center - half + spread * float(p_idx) / float(peasant_count - 1)
			_formation_spots.append(_ring_spot(angle, rp))
			p_idx += 1

## Point LOCAL (référentiel héros, avant = -Z) sur un anneau : angle `a`, rayon `radius`.
func _ring_spot(a: float, radius: float) -> Vector3:
	return Vector3(cos(a) * radius, 0.0, sin(a) * radius)

## Point MONDE de la position de formation du membre `i`, en tenant compte de la
## rotation actuelle du héros : offset local pivoté par la base du héros.
func _formation_spot_world(i: int) -> Vector3:
	var off: Vector3 = _formation_spots[i] if i < _formation_spots.size() else Vector3.ZERO
	var world_off: Vector3 = global_transform.basis * off
	world_off.y = 0.0   # garder la formation au sol (plan XZ)
	return global_position + world_off

# ======================================================================
# FORMATION / MOUVEMENT
# ======================================================================

## Déplace le héros (et donc sa troupe) vers un point. La troupe la suit en
## formation collée : chaque membre garde son offset local par rapport au héros.
func move_to_point(_point: Vector3) -> void:
	_move_target = _point
	_move_target.y = 0.0
	nav_agent.target_position = _move_target
	set_state(State.MOVING)
	_move_troop_to_formation()

func attack_target(target: Node3D) -> void:
	if target == null:
		return
	_attack_target = target
	nav_agent.target_position = target.global_position
	set_state(State.MOVING_TO_ATTACK)
	# La troupe combat aussi.
	for u in _troop:
		if u is Soldier and u.has_method("attack_target"):
			u.attack_target(target)

## La troupe suit le héros : on place le point de navigation de chaque membre sur
## sa position de formation (centre du héros + offset). Ils restent groupés.
# Tire TOUTE la troupe vers la formation (ordre explicite : déplacement, ou
# assignation). Ici on ne filtre PAS les récolteurs : quand l'utilisateur donne un
# ordre de déplacement au héros ou affecte une unité, la troupe doit le rejoindre
# immédiatement, même si un membre était en train de récolter. (Le suivi continu
# du _physics_process, lui, évite de casser une récolte en cours.)
func _move_troop_to_formation() -> void:
	for i in _troop.size():
		var u: Node = _troop[i]
		if not is_instance_valid(u):
			continue
		var spot: Vector3 = _formation_spot_world(i)
		if u.has_method("move_to_point"):
			u.call("move_to_point", spot)

## Ordonne à la troupe de récolter une ressource : chaque paysan de la troupe va
## la puiser, et le héros s'approche aussi de la ressource. On ne tire pas la
## troupe ici (gather_troop) pour ne pas annuler la récolte ; seul le suivi
## continu de _physics_process ré-aiguille les membres après (sans casser une
## récolte en cours grâce à _is_member_busy).
func gather_troop(resource: ResourceNode) -> void:
	if resource == null or not resource.has_left():
		return
	for u in _troop:
		if u is Villager and u.has_method("send_to_gather"):
			u.call("send_to_gather", resource)
	# Le héros (commandant) s'approche aussi de la ressource. On NE tire PAS la
	# troupe ici : les paysans viennent de recevoir l'ordre de récolte et ne
	# doivent pas être rappelés. Seul le suivi continu du _physics_process les
	# ré-aiguillera après la récolte (sans casser celle en cours).
	var target: Vector3 = resource.global_position
	target.y = global_position.y
	nav_agent.target_position = target
	set_state(State.MOVING)

## Vrai si ce membre de la troupe est actuellement occupé à récolter (à ne pas
## rappeler vers la formation pendant qu'il travaille).
func _is_member_busy(u: Node) -> bool:
	# _state est une VARIABLE (pas une méthode) : on y accède via get().
	if u is Villager and u.get("_state") != null:
		var st: int = int(u.get("_state"))
		if st == 1 or st == 2 or st == 3:  # GOING_TO_RESOURCE, GATHERING, RETURNING
			return true
	return false

func has_gather_command_flag() -> void:
	pass

## Raccompagne les membres qui se sont éloignés de la formation (troupe collée).
func _physics_process(delta: float) -> void:
	# Mort éventuelle.
	if hp <= 0:
		die()
		return
	# Mise à jour continue de la formation : chaque membre reste sur sa position
	# de formation (offset local pivoté par l'orientation du héros).
	for i in _troop.size():
		var u: Node = _troop[i]
		if not is_instance_valid(u):
			_troop.erase(u)
			continue
		# Ne pas rappeler un membre occupé à récolter : il reviendra tout seul.
		if _is_member_busy(u):
			continue
		var spot: Vector3 = _formation_spot_world(i)
		# Tolérance : à l'arrêt (IDLE) on recentre précisément sur le cercle/arc
		# (petit seuil) pour une formation nette ; en mouvement on laisse suivre.
		var tol: float = 1.8
		if _state == State.IDLE:
			tol = 1.0 if u is Soldier else 0.4
		if u.has_method("_hdist"):
			var d: float = u.call("_hdist", spot)
			if d > tol:
				if u.has_method("move_to_point"):
					u.call("move_to_point", spot)

	# Héros : déplacement + attaque.
	if _state == State.MOVING:
		_move(delta)
	elif _state == State.MOVING_TO_ATTACK:
		if _attack_target == null or not is_instance_valid(_attack_target):
			set_state(State.IDLE)
			return
		nav_agent.target_position = _attack_target.global_position
		_move(delta)
		if _dist_to(_attack_target.global_position) <= ATTACK_RANGE:
			set_state(State.ATTACKING)
	elif _state == State.ATTACKING:
		if _attack_target == null or not is_instance_valid(_attack_target):
			set_state(State.IDLE)
			return
		if _dist_to(_attack_target.global_position) > ATTACK_RANGE * 1.3:
			set_state(State.MOVING_TO_ATTACK)
			return
		_attack(delta)

	_anim_prev_pos = global_position

func _move(_delta: float) -> void:
	if nav_agent.is_navigation_finished():
		set_state(State.IDLE)
		return
	var next := nav_agent.get_next_path_position()
	var dir := (next - global_position)
	dir.y = 0.0
	var spd := _move_speed()
	velocity = dir.normalized() * spd
	var collide := move_and_slide()
	if collide:
		pass
	_facing(dir)
	_anim("Run")

func _attack(_delta: float) -> void:
	if _attack_target == null:
		set_state(State.IDLE)
		return
	_facing(_attack_target.global_position - global_position)
	_attack_cd -= _delta
	if _attack_cd <= 0.0:
		_attack_cd = _attack_cooldown()
		if _attack_target.has_method("take_damage"):
			_attack_target.call("take_damage", _atk_damage(), global_position)
		# Gagne de l'XP en combattant.
		gain_xp(4)

func _dist_to(pt: Vector3) -> float:
	var p := global_position
	return Vector3(p.x - pt.x, 0.0, p.z - pt.z).length()

func _hdist(pt: Vector3) -> float:
	return _dist_to(pt)

# ======================================================================
# XP / NIVEAU
# ======================================================================

func gain_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = int(xp_to_next * 1.5)
		_build_formation_spots()
		troop_changed.emit()
	# Le bonus de commandement (PV notamment) augmente : on recalcule les troupes.
	for u in _troop:
		if is_instance_valid(u) and u.has_method("notify_command"):
			u.call("notify_command", self)

# ======================================================================
# SÉLECTION / VISUEL
# ======================================================================

func set_selected(on: bool) -> void:
	_apply_selection_fx(on)

## Applique la mise en évidence (émission lumineuse) sur le modèle du héros.
func _apply_selection_fx(on: bool) -> void:
	var model := get_node_or_null("Model") as VillagerModel
	if model == null:
		return
	var mesh := model.find_child("char1", true, false) as MeshInstance3D
	if mesh == null:
		return
	if on:
		var mat := mesh.material_override
		if mat == null:
			mat = StandardMaterial3D.new()
			mesh.material_override = mat
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.9, 0.3)
		mat.emission_energy_multiplier = 1.2
	else:
		if mesh.material_override != null:
			mesh.material_override.emission_enabled = false

## Affiche/masque un repère (cercle) sous chaque membre de la troupe — indique
## visuellement qu'ils sont « dirigés » par ce héros (sélection du héros).
func _show_troop_selected(on: bool) -> void:
	for u in _troop:
		if is_instance_valid(u) and u.has_method("set_selected"):
			u.call("set_selected", on)

func set_state(s: State) -> void:
	_state = s

# ======================================================================
# COMBAT
# ======================================================================

func react_to_attack(_attacker_pos: Vector3) -> void:
	# Le héros ne fuie pas : il est un commandant. (Troupes assignées gèrent leur
	# propre réaction individuelle.)
	pass

func take_damage(amount: int, _attacker_pos: Vector3 = Vector3.ZERO) -> void:
	hp -= amount
	last_damage_ms = Time.get_ticks_msec()
	if hp <= 0:
		die()

func die() -> void:
	if hp > 0:
		return
	died.emit()
	set_state(State.IDLE)

func _facing(dir: Vector3) -> void:
	if dir.length_squared() > 0.01:
		# Applique réellement la rotation (le modèle doit se tourner vers la cible).
		look_at(global_position + dir, Vector3.UP)

func _anim(_anim_name: StringName) -> void:
	if anim_player != null and anim_player.has_animation(_anim_name):
		anim_player.play(_anim_name)
