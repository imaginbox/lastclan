extends Node3D
## Contrôleur principal : construit le monde 3D testable (sol, NavMesh, hôtel de
## ville, paysans, ressources) et gère les interactions RTS :
##   - Clic gauche         : sélection d'une unité ou d'un bâtiment
##   - Clic gauche + glisser : sélection multiple (cadre) d'unités
##   - Clic droit ressource : les unités sélectionnées vont récolter
##   - Clic droit ennemi    : les unités sélectionnées attaquent
##   - Clic droit sol       : les unités sélectionnées se déplacent
##   - Menu construction + fantôme : placer des bâtiments librement, puis les déplacer
##   - Panneau bâtiment : upgrader / entraîner / recruter
## Économie : or, bois et population (gérés par l'autoload ResourceManager).

const VILLAGER_SCENE := preload("res://scenes/Villager.tscn")
const RESOURCE_SCENE := preload("res://scenes/ResourceNode.tscn")
const SOLDIER_SCENE := preload("res://scenes/Soldier.tscn")
const DecorScript := preload("res://scripts/Decor.gd")
const FLOAT_TEXT_SCENE := preload("res://scripts/FloatingText.gd")

const CELL := 1.0
const GRID_HALF := 190.0
const DRAG_SELECT_THRESHOLD := 8.0

@onready var nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var villager_root: Node3D = $Units

## Timer anti-rebond pour re-cuire le navmesh après un placement/déplacement de
## bâtiment ou une réapparition de ressource (évite de cuire à chaque frame).
var _rebake_timer: Timer = null
@onready var building_root: Node3D = $Buildings
@onready var resource_root: Node3D = $Resources
@onready var decor_root: Node3D = $Decor

var _camera: Camera3D = null
var _selected_units: Array[Node] = []
var _selected_building: Building = null
## Position de la base de CE joueur (origine en solo, dispersée en multijoueur).
var _base_origin: Vector3 = Vector3.ZERO
## RNG déterministe du monde : seedé depuis Lobby.world_seed pour que TOUS les
## clients d'une même room génèrent le MÊME monde (ressources, décor). C'est ce
## qui rend le terrain visible et identique pour tout le monde.
var _world_rng: RandomNumberGenerator = null

## --- Grille / occupation ---
var _occupancy := {}   # Vector2i -> Building

## --- Mode placement / déplacement ---
var _pending_type: int = -1   # -1 = aucun type en cours de placement
var _ghost: Building = null
var _moving_building: Building = null
var _ghost_valid := false

## --- Surbrillance de sélection ---
class SelectionRect extends Control:
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	func _draw() -> void:
		var r := Rect2(from, to - from).abs()
		draw_rect(r, Color(0.2, 1.0, 0.3, 0.15), true)
		draw_rect(r, Color(0.2, 1.0, 0.3, 0.7), false, 2.0)

var _overlay_rect: SelectionRect = null
var _press_pos := Vector2.ZERO
var _dragging := false
var _drag_selecting := false
# --- Tactile : nombre de doigts posés et autorisation du tap (1 seul doigt) ---
var _touch_count := 0
var _tap_allowed := true
# --- Barre d'action mobile (remplace le clic droit) ---
# Modes d'ordre : quel ordre le prochain tap sur le monde doit-il exécuter.
enum OrderMode { NONE, MOVE, GATHER, ATTACK }
var _order_mode: int = OrderMode.NONE
var _order_bar: HBoxContainer = null
var _order_btns := {}   # OrderMode -> Button
var _order_hint: Label = null
var _order_armed := false
# --- Échelle UI (plus grande sur mobile) ---
var _ui_scale: float = 1.0

## --- HUD ---
var _hud_gold_label: Label = null
var _hud_wood_label: Label = null
var _hud_stone_label: Label = null
var _hud_food_label: Label = null
var _hud_pop_label: Label = null
var _hud_workers_label: Label = null
var _hud_soldiers_label: Label = null
var _hud_room_label: Label = null

## --- Nombres de récolte flottants (HUD cartoon) ---
var _float_root: CanvasLayer = null

## --- Sync live des unités (multijoueur) ---
var _remote_units: Node3D = null
var _remote_rep: Dictionary = {}      # peer_id -> Array[Node3D] (représentations distantes)
var _sync_timer: Timer = null
## --- Sync des bâtiments (multijoueur) ---
## Registre des bâtiments distants : "owner_peer:vector_string_of_cell" -> Building.
var _remote_buildings: Dictionary = {}
var _remote_building_root: Node3D = null
const UNIT_SYNC_INTERVAL: float = 0.15  # ~6,6 envois/s

## Graine avec laquelle le monde a été construit. Sert à détecter un changement
## de seed en cours de route (ex. _sync_room du serveur qui arrive après le build)
## pour REconstruire le monde et garder tous les joueurs d'un royaume identiques.
var _built_seed: int = -1
var _world_spawned: bool = false

## --- Sync mondiale des ressources (décor interactif partagé) ---
## Chaque ResourceNode reçoit un res_id DETERMINISTE (ordre de spawn de la graine),
## identique chez tous les clients d'une même room → on peut diffuser les
## quantités par cet id pour que TOUS voient le même épuisement.
var _next_res_id: int = 0
## res_id -> ResourceNode (registre local, pour retrouver un nœud depuis une sync).
var _res_by_id: Dictionary = {}
const REMOTE_UNIT_COLORS: Array[Color] = [
	Color(0.3, 0.6, 1.0),   # bleu
	Color(1.0, 0.4, 0.4),   # rouge
	Color(0.4, 1.0, 0.5),   # vert
	Color(1.0, 0.8, 0.3),   # orange
	Color(0.9, 0.4, 1.0),   # violet
	Color(0.4, 0.9, 1.0),   # cyan
	Color(1.0, 0.6, 0.8),   # rose
	Color(0.8, 0.8, 0.8),   # gris
]

## --- UI : menu construction & panneau bâtiment ---
var _build_buttons := {}   # Building.Type -> Button
var _build_hb: HBoxContainer = null
var _build_panel: PanelContainer = null
var _building_panel: PanelContainer = null
var _building_title: Label = null
var _building_info: Label = null
var _upgrade_button: Button = null
var _train_button: Button = null
var _recruit_button: Button = null
var _move_button: Button = null

func _ready() -> void:
	randomize()
	_camera = $Camera3D
	add_to_group("world")
	# Détection tactile dès le début : toutes les UI (HUD, barre d'ordre, panels)
	# doivent se construire avec la bonne échelle.
	_ui_scale = 1.8 if DisplayServer.is_touchscreen_available() else 1.0
	_setup_float_layer()
	_setup_selection_overlay()
	_setup_hud()
	_setup_build_ui()
	_setup_building_panel()
	_setup_order_button()
	# Le monde se construit une fois la position de base connue :
	#   - hors ligne : Lobby la fournit immédiatement (origine).
	#   - en ligne  : Lobby la fournit dès la connexion au relais.
	if Lobby.has_base:
		_spawn_world()
	else:
		Lobby.base_ready.connect(_on_base_ready)
		# Filet de sécurité : si aucun départ n'est signalé (ex. scène lancée
		# directement pendant le dev), on démarre quand même à l'origine.
		_offline_fallback_timer()

## Filet de sécurité : démarre le monde à l'origine si la scène a été lancée
## directement sans passer par le lobby/relais.
func _offline_fallback_timer() -> void:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = 3.0
	t.timeout.connect(_on_base_fallback_timeout)
	add_child(t)
	t.start()

func _on_base_fallback_timeout() -> void:
	if Lobby.has_base:
		return  # déjà prêt
	Lobby._go_offline()

func _on_base_ready(_origin: Vector3) -> void:
	# Sans la connexion, on garde la réceptivité à un éventuel bonus
	# (le monde peut être reconstruit si le seed du royaume change ensuite).
	if _world_spawned and _built_seed != Lobby.world_seed:
		_clear_world()
		_spawn_world()
		return
	if _world_spawned:
		return
	_spawn_world()

## Construit le monde (ressources, bâtiments, paysans, brouillard, caméra)
## autour de la base de CE joueur.
func _spawn_world() -> void:
	_base_origin = Lobby.base_origin
	# RNG du monde, seedé de façon déterministe depuis la room : tous les clients
	# d'une même room génèrent identiquement le décor et les ressources.
	_world_rng = RandomNumberGenerator.new()
	_world_rng.seed = Lobby.world_seed
	_built_seed = Lobby.world_seed
	_world_spawned = true
	# Répartit les ressources (positions absolues, identiques pour tous).
	_spawn_resources()
	# Serveur dédié : il génère le MONDE partagé (ressources, décor) pour que tous
	# les joueurs le retrouvent identique, mais il n'a pas de village joueur à lui
	# (personne ne le contrôle) ni de caméra interactive inutile. Il sert de
	# présence hôte permanente et légère qui reste connectée au relais.
	if not Lobby.is_dedicated_server:
		_spawn_initial_buildings()
		_spawn_villagers()
	_spawn_decor()
	# Les boutons dépendent du niveau de l'hôtel de ville, créé ci-dessus.
	_refresh_build_buttons()
	# Pose la caméra sur la base du joueur (pas de caméra interactive en serveur).
	if _camera != null and _camera.has_method("set_pivot") and not Lobby.is_dedicated_server:
		_camera.call("set_pivot", _base_origin)
	# En ligne : prépare la réception des unités des autres joueurs + diffusion.
	if Lobby.is_online:
		_setup_remote_units()
	_await_frame_then_bake()

## Vide les nœuds du monde générés (ressources, décor, bâtiments, unités) pour
## pouvoir reconstruire le monde avec un nouveau seed. Ne touche pas à l'occupancy
## des bâtiments du joueur construits après coup (ils sont suivis par ailleurs).
func _clear_world() -> void:
	_clear_root(resource_root)
	_clear_root(decor_root)
	_clear_root(building_root)
	_clear_root(villager_root)
	if _remote_units != null:
		_clear_root(_remote_units)
	if _remote_building_root != null:
		_clear_root(_remote_building_root)
	_occupancy.clear()
	_res_by_id.clear()
	_next_res_id = 0

func _clear_root(root: Node) -> void:
	for child in root.get_children():
		child.queue_free()

func _await_frame_then_bake() -> void:
	await get_tree().physics_frame
	_bake_navmesh()
	_refresh_population_cap()
	# Directeur du monde : le monde évolue tout seul (respawn des ressources).
	var director := Timer.new()
	director.wait_time = 8.0
	director.autostart = true
	director.timeout.connect(_world_director_tick)
	add_child(director)
	if OS.get_cmdline_user_args().has("--autotest"):
		_autotest()

func _bake_navmesh() -> void:
	var region := nav_region
	var mesh := NavigationMesh.new()
	
	# RÉGLAGE NAVMESH : On remonte à 0.2 pour plus de stabilité. 
	# 0.1 était trop "nerveux" et créait des micro-coupures dans les chemins.
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, 0.2)
	NavigationServer3D.map_set_cell_height(map, 0.2)
	
	mesh.cell_size = 0.2
	mesh.cell_height = 0.2
	mesh.agent_radius = 0.4
	mesh.agent_height = 1.5
	mesh.agent_max_climb = 0.5
	
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 0b11   # couches 1 et 2
	mesh.filter_baking_aabb = AABB(
		Vector3(-GRID_HALF, -1.0, -GRID_HALF),
		Vector3(GRID_HALF * 2.0, 4.0, GRID_HALF * 2.0)
	)
	region.navigation_mesh = mesh
	region.bake_navigation_mesh()
	# Filet de sécurité : si la cuisson échoue (0 polygones), on pose une grille
	# plate pour que les paysans puissent tout de même se déplacer (sans contourner).
	if region.get_navigation_mesh().get_polygon_count() == 0:
		_fallback_flat_navmesh(region)

## Navmesh de secours : grande grille plate (les paysans marchent en ligne droite).
func _fallback_flat_navmesh(region: NavigationRegion3D) -> void:
	var mesh := NavigationMesh.new()
	mesh.agent_radius = 0.4
	mesh.agent_height = 1.6
	var half := 200.0
	var step := 2.0
	var count := int(half * 2.0 / step)
	var verts := PackedVector3Array()
	for z in count + 1:
		for x in count + 1:
			verts.append(Vector3(-half + x * step, 0.0, -half + z * step))
	mesh.set_vertices(verts)
	for z in count:
		for x in count:
			var a := z * (count + 1) + x
			var b := a + 1
			var c := a + (count + 1)
			var d := c + 1
			mesh.add_polygon(PackedInt32Array([a, b, c]))
			mesh.add_polygon(PackedInt32Array([b, d, c]))
	region.navigation_mesh = mesh

## Planifie (avec rebond) une re-cuisson du navmesh. À appeler quand le monde
## change d'obstacles (bâtiment posé/déplacé, ressource réapparue).
func _schedule_rebake() -> void:
	if _rebake_timer == null:
		_rebake_timer = Timer.new()
		_rebake_timer.one_shot = true
		_rebake_timer.wait_time = 0.6
		_rebake_timer.timeout.connect(_bake_navmesh)
		add_child(_rebake_timer)
	_rebake_timer.start()

# ============================================================ SPAWN MONDE

## Génère les ressources initiales du monde : plusieurs grappes aléatoires
## (or, bois, pierre) dispersées sur la carte. Comme les arbres (bois) s'épuisent
## vite, on en place beaucoup plus que les autres types.
func _spawn_resources() -> void:
	# Les ressources sont placées à des positions ABSOLUES dérivées de la graine
	# du monde : chaque client de la room génère exactement les mêmes grappes aux
	# mêmes endroits. Le monde est ainsi partagé et visible par tous.
	var cluster_positions := [
		Vector3(8, 0, 4),
		Vector3(10, 0, -3),
		Vector3(-12, 0, 8),
		Vector3(14, 0, -12),
		Vector3(-14, 0, -10),
		Vector3(6, 0, -14),
		Vector3(-18, 0, -4),
		Vector3(-8, 0, 16),
	]
	for pos in cluster_positions:
		_spawn_cluster(pos, 4)
	# Plusieurs arbres isolés (bois) disséminés sur le monde, car ils s'épuisent
	# très vite : la forêt reste dense. Positions absolues, identiques pour tous.
	for i in 14:
		var pos := Vector3(
			_world_rng.randf_range(-24.0, 24.0),
			0.0,
			_world_rng.randf_range(-24.0, 24.0)
		)
		pos.x = clampf(pos.x, -GRID_HALF, GRID_HALF)
		pos.z = clampf(pos.z, -GRID_HALF, GRID_HALF)
		_spawn_resource_node(pos, ResourceNode.ResourceType.WOOD)

## Loi du monde : une grappe de ressources répartie autour d'un centre.
func _spawn_cluster(center: Vector3, count: int) -> void:
	for i in count:
		var offset := Vector3(
			_world_rng.randf_range(-3.0, 3.0),
			0.0,
			_world_rng.randf_range(-3.0, 3.0)
		)
		var pos := center + offset
		pos.x = clampf(pos.x, -GRID_HALF, GRID_HALF)
		pos.z = clampf(pos.z, -GRID_HALF, GRID_HALF)
		_spawn_resource_node(pos)

## Loi du monde : crée un nœud de ressource. `forced_type` force le type (utilisé
## pour densifier les arbres à bois), sinon il est tiré au sort.
## Connecte le signal `depleted` pour faire réapparaître la ressource ailleurs.
func _spawn_resource_node(pos: Vector3, forced_type: int = -1) -> Node3D:
	# Garde de la ressource à distance des bâtiments : on réessaie jusqu'à trouver
	# un emplacement libre, pour ne pas faire pousser d'arbres à côté des maisons.
	for attempt in 8:
		if not _near_building(pos, 6.0):
			break
		pos.x = clampf(pos.x + _world_rng.randf_range(-4.0, 4.0), -GRID_HALF, GRID_HALF)
		pos.z = clampf(pos.z + _world_rng.randf_range(-4.0, 4.0), -GRID_HALF, GRID_HALF)
	var t: ResourceNode.ResourceType
	if forced_type >= 0:
		t = forced_type as ResourceNode.ResourceType
	else:
		# RÉPARTITION STRATÉGIQUE : Le bois est abondant (60%), 
		# la pierre modérée (25%), la nourriture rare (10%), 
		# et l'or est très rare (5%).
		var r := _world_rng.randf()
		if r < 0.6: t = ResourceNode.ResourceType.WOOD
		elif r < 0.85: t = ResourceNode.ResourceType.STONE
		elif r < 0.95: t = ResourceNode.ResourceType.FOOD
		else: t = ResourceNode.ResourceType.GOLD
	var node: Node3D = RESOURCE_SCENE.instantiate()
	node.set("resource_type", t)
	match t:
		ResourceNode.ResourceType.GOLD:
			node.set("max_amount", 100)
		ResourceNode.ResourceType.WOOD:
			node.set("max_amount", 80)
		ResourceNode.ResourceType.STONE:
			node.set("max_amount", 60)
		ResourceNode.ResourceType.FOOD:
			node.set("max_amount", 40)
	node.set("starting_amount", node.get("max_amount"))
	# Identifiant STABLE et DÉTERMINISTE : comme le monde est généré à partir de la
	# même graine (même ordre de spawn), chaque client d'une room attribue le MÊME
	# res_id au même arbre/rocher → on peut diffuser sa quantité par cet id.
	node.set("res_id", _next_res_id)
	_next_res_id += 1
	_res_by_id[_next_res_id - 1] = node
	node.add_to_group("resource")
	resource_root.add_child(node)
	node.global_position = pos
	# Récolte/repousse : on diffuse la nouvelle quantité aux autres joueurs, pour
	# que TOUS voient le même épuisement (le monde reste interactif et cohérent).
	node.amount_changed.connect(_on_resource_amount_changed)
	# Quand la ressource est épuisée, elle disparaît et réapparaît ailleurs.
	node.depleted.connect(_on_resource_depleted.bind(node))
	return node

## Quand une ressource est épuisée : elle réapparaît même type ailleurs, et
## l'ancien nœud est libéré. Le monde reste ainsi peuplé en permanence.
##
## MULTIJOUEUR : le respawn est décidé ici (le client dont le paysan a pris la
## dernière unité), puis DIFFUSÉ à tous. Comme la quantité est déjà synchronisée
## via amount_changed → _sync_resource_amount, chaque client voit le même nœud
## tomber à 0, mais SEUL le récolteur émet depleted localement (le setter de sync
## ne ré-émet pas depleted). On choisit donc un nouvel emplacement DÉTERMINISTE et
## on le diffuse pour que TOUS recréent la même ressource au même endroit.
func _on_resource_depleted(node: Node3D) -> void:
	var rid: int = node.get("res_id")
	var t: int = node.get("resource_type")
	if Lobby.is_online and multiplayer.multiplayer_peer != null:
		# Choisit le nouvel emplacement, MAIS pour rester déterministe entre
		# joueurs on le dérive de l'id de l'ancien nœud (pas du RNG local qui
		# diverge entre clients) : position stable → monde identique partout.
		var pos := _respawn_pos_for(rid)
		var max_amt: int = node.get("max_amount")
		node.queue_free()
		_sync_resource_respawn.rpc(rid, t, pos.x, pos.z, max_amt)
		_schedule_rebake()
		return
	# Hors ligne : comportement local d'origine.
	var pos_off := _random_free_world_pos()
	_spawn_resource_node(pos_off, t)
	node.queue_free()
	_schedule_rebake()

## Choisit un emplacement de respawn DÉTERMINISTE depuis le res_id : tous les
## clients d'une room placent la nouvelle ressource au même endroit, et le décor
## reste identique chez tout le monde (aucune divergence de RNG).
func _respawn_pos_for(rid: int) -> Vector3:
	var angle := float((rid * 53) % 360) * PI / 180.0
	var radius := 6.0 + float((rid * 37) % 60) / 3.0
	var pos := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	pos.x = clampf(pos.x, -GRID_HALF, GRID_HALF)
	pos.z = clampf(pos.z, -GRID_HALF, GRID_HALF)
	# Évite de renaître pile à côté d'un bâtiment : décale légèrement sinon.
	for attempt in 8:
		if not _near_building(pos, 6.0):
			break
		var j := float(attempt + 1) * 2.0
		pos.x = clampf(pos.x + cos(angle + j) * 2.0, -GRID_HALF, GRID_HALF)
		pos.z = clampf(pos.z + sin(angle + j) * 2.0, -GRID_HALF, GRID_HALF)
	return pos

## Reçoit la réapparition (respawn) d'une ressource diffusée par le récolteur :
## retire l'ancien nœud (même res_id) et en crée un neuf au même emplacement,
## pour que le décor reste identique chez tous les joueurs.
@rpc("any_peer", "reliable", "call_local")
func _sync_resource_respawn(rid: int, t: int, px: float, pz: float, max_amt: int) -> void:
	var old: Object = _res_by_id.get(rid)
	if old != null and is_instance_valid(old):
		var old_node: Node3D = old as Node3D
		old_node.queue_free()
		_res_by_id.erase(rid)
	# Recrée la ressource au même endroit, avec le même res_id → cohérent partout.
	var nb: Node3D = RESOURCE_SCENE.instantiate()
	nb.set("resource_type", t)
	nb.set("max_amount", max_amt)
	nb.set("starting_amount", max_amt)
	nb.set("res_id", rid)
	nb.add_to_group("resource")
	resource_root.add_child(nb)
	nb.global_position = Vector3(px, 0.0, pz)
	nb.amount_changed.connect(_on_resource_amount_changed)
	nb.depleted.connect(_on_resource_depleted.bind(nb))
	_res_by_id[rid] = nb
	_schedule_rebake()

## Un joueur a récolté / un arbre a repoussé : on diffuse la nouvelle quantité pour
## que TOUS voient le même niveau d'épuisement (monde partagé et interactif).
func _on_resource_amount_changed(node: Node3D) -> void:
	if not Lobby.is_online or multiplayer.multiplayer_peer == null:
		return
	var rid: int = node.get("res_id")
	if rid < 0:
		return
	_sync_resource_amount.rpc(rid, int(node.get("amount")))

## Reçoit une quantité mise à jour d'une ressource (récolte/repousse) et l'applique
## localement sans re-diffusion (évite la boucle de broadcast).
@rpc("any_peer", "reliable", "call_local")
func _sync_resource_amount(rid: int, new_amount: int) -> void:
	var n: Object = _res_by_id.get(rid)
	if n != null and is_instance_valid(n):
		var node := n as Node3D
		node.call("set_amount_from_sync", new_amount)

## Disperser la décoration : des touffes d'herbe (modèles fournis) un peu partout
## + de grands arbres décoratifs (non récoltables) pour le paysage. Concentration
## plus forte autour de la base.
func _spawn_decor() -> void:
	# Herbe : dense, petits modèles, dispersés sur toute la carte.
	for i in 320:
		var pos := _random_decor_pos()
		if pos == Vector3.INF:
			continue
		var d := Decor.new()
		d.build_grass()
		d.add_to_group("decor")
		decor_root.add_child(d)
		d.global_position = pos
		d.rotation_degrees.y = _world_rng.randf_range(0, 360)
		var s := _world_rng.randf_range(0.7, 1.4)
		d.scale = Vector3(s, s, s)
	# Arbres décoratifs : SUPPRIMÉS. 
	# Tous les arbres du monde sont désormais des ResourceNode récoltables.
	# Le joueur a demandé à diminuer le nombre d'arbres et à les rendre tous récoltables.
	pass

## Position libre pour une décoration, avec une densité qui décroît avec la
## distance à la base (le monde est plus vivant près du joueur).
func _random_decor_pos() -> Vector3:
	for attempt in 40:
		var angle := _world_rng.randf() * TAU
		var dist := pow(_world_rng.randf(), 1.6) * 120.0
		var pos := Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		pos.x = clampf(pos.x, -GRID_HALF, GRID_HALF)
		pos.z = clampf(pos.z, -GRID_HALF, GRID_HALF)
		# Garde une petite marge autour du centre du monde.
		if pos.distance_to(Vector3.ZERO) < 4.0:
			continue
		var cell := _cell_from_pos(pos)
		if not _occupancy.has(cell):
			return pos
	return Vector3.INF

## Position libre pour un arbre décoratif : un peu plus éloigné de la base
## (les grands arbres ne bloquent pas la vue du village).
func _random_decor_pos_tree() -> Vector3:
	for attempt in 40:
		var angle := _world_rng.randf() * TAU
		var dist := pow(_world_rng.randf(), 1.6) * 150.0
		var pos := Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		pos.x = clampf(pos.x, -GRID_HALF, GRID_HALF)
		pos.z = clampf(pos.z, -GRID_HALF, GRID_HALF)
		if pos.distance_to(Vector3.ZERO) < 8.0:
			continue
		var cell := _cell_from_pos(pos)
		if not _occupancy.has(cell):
			return pos
	return Vector3.INF

## Directeur du monde : vérifie périodiquement la densité des ressources et fait
## apparaître de nouvelles sources aux emplacements libres quand elles se raréfient.
func _world_director_tick() -> void:
	# En ligne, seul le HOST (peer 1) fait apparaître de nouvelles ressources et les
	# diffuse : sinon chaque client respawn de son côté à des RNG différents et le
	# décor diverge. Hors ligne, comportement local d'origine.
	if Lobby.is_online and multiplayer.multiplayer_peer != null and Lobby.my_id != 1:
		return
	var threshold := 10
	var count := 0
	for child in resource_root.get_children():
		var r := child as ResourceNode
		if r != null and r.exists():
			count += 1
	if count < threshold:
		_spawn_world_cluster(_random_free_world_pos(), 3)

## L'hôte fait apparaître une grappe de ressources et la diffuse à tous (chaque
## nœud porte un res_id déterministe) → le monde reste identique chez chacun.
func _spawn_world_cluster(center: Vector3, count: int) -> void:
	var online: bool = Lobby.is_online and multiplayer.multiplayer_peer != null
	for i in count:
		var offset := Vector3(
			_world_rng.randf_range(-3.0, 3.0),
			0.0,
			_world_rng.randf_range(-3.0, 3.0)
		)
		var pos := center + offset
		pos.x = clampf(pos.x, -GRID_HALF, GRID_HALF)
		pos.z = clampf(pos.z, -GRID_HALF, GRID_HALF)
		if online:
			# Diffuse chaque nœud explicitement (type + position + quantit�). Le
			# call_local de _sync_resource_respawn recrée le nœud chez l'hôte aussi.
			var t := _random_resource_type()
			_sync_resource_respawn.rpc(_next_res_id, t, pos.x, pos.z, _max_for_type(t))
			_next_res_id += 1
		else:
			_spawn_resource_node(pos)

## Type de ressource tiré au sort avec la répartition stratégique utilisée à la
## création du monde (bois abondant, pierre modérée, nourriture rare, or très rare).
func _random_resource_type() -> int:
	var r := _world_rng.randf()
	if r < 0.6:
		return ResourceNode.ResourceType.WOOD
	elif r < 0.85:
		return ResourceNode.ResourceType.STONE
	elif r < 0.95:
		return ResourceNode.ResourceType.FOOD
	else:
		return ResourceNode.ResourceType.GOLD

## Quantité maximale associée à un type de ressource (cohérent avec la création).
func _max_for_type(t: int) -> int:
	match t as ResourceNode.ResourceType:
		ResourceNode.ResourceType.GOLD:
			return 100
		ResourceNode.ResourceType.WOOD:
			return 80
		ResourceNode.ResourceType.STONE:
			return 60
		ResourceNode.ResourceType.FOOD:
			return 40
	return 80

## Position libre aléatoire dans le monde (loin des bâtiments).
func _random_free_world_pos() -> Vector3:
	for attempt in 20:
		var pos := Vector3(_world_rng.randf_range(-GRID_HALF, GRID_HALF), 0.0, _world_rng.randf_range(-GRID_HALF, GRID_HALF))
		var cell := _cell_from_pos(pos)
		if not _occupancy.has(cell) and not _near_building(pos, 6.0):
			return pos
	return Vector3(_world_rng.randf_range(-GRID_HALF, GRID_HALF), 0.0, _world_rng.randf_range(-GRID_HALF, GRID_HALF))

## Vrai si la position est trop proche d'un bâtiment : sert à ne pas faire
## pousser d'arbres/ressources juste à côté des constructions (jamais bloquantes
## et visuellement propres).
func _near_building(pos: Vector3, min_dist: float) -> bool:
	for child in building_root.get_children():
		var b := child as Building
		if b == null:
			continue
		if pos.distance_to(b.global_position) < min_dist:
			return true
	return false

func _spawn_initial_buildings() -> void:
	# Hôtel de ville au centre de la base (décalé de la position de base).
	var base_cell := _cell_from_pos(_base_origin)
	var th := _instantiate_building(Building.Type.TOWN_HALL)
	var th_cell := base_cell - Vector2i(1, 1)
	_place_building(th, th_cell)
	# Maison de départ : le nouveau joueur démarre avec un logement.
	var house := _instantiate_building(Building.Type.HOUSE)
	_place_building(house, base_cell + Vector2i(2, -1))

func _spawn_villagers() -> void:
	var v: Node3D = VILLAGER_SCENE.instantiate()
	villager_root.add_child(v)
	v.global_position = _base_origin + Vector3(-2.0, 0.0, 0.0)
	var v2: Node3D = VILLAGER_SCENE.instantiate()
	villager_root.add_child(v2)
	v2.global_position = _base_origin + Vector3(-6.0, 0.0, -6.0)
	_add_default_task(v)
	_add_default_task(v2)
	_refresh_unit_counts()

func _add_default_task(villager: Node3D) -> void:
	var rn := _nearest_resource_node(villager.global_position)
	if rn != null:
		villager.call("send_to_gather", rn as ResourceNode)

func _nearest_resource_node(from_pos: Vector3) -> ResourceNode:
	var best: ResourceNode = null
	var best_d := INF
	for n in resource_root.get_children():
		var r := n as ResourceNode
		if r != null:
			var d: float = from_pos.distance_squared_to(r.global_position)
			if d < best_d:
				best_d = d
				best = r
	return best

# ============================================================ BÂTIMENTS / GRILLE

func _instantiate_building(t: Building.Type) -> Building:
	var b := Building.new()
	b.type = t
	building_root.add_child(b)
	return b

func _cell_from_pos(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / CELL), floori(pos.z / CELL))

func _cell_center(cell: Vector2i) -> Vector3:
	return Vector3((float(cell.x) + 0.5) * CELL, 0.0, (float(cell.y) + 0.5) * CELL)

## Empreinte (liste des cellules) pour un bâtiment ancré en [anchor].
func _footprint_cells(anchor: Vector2i, f: int) -> Array:
	var cells: Array = []
	for z in f:
		for x in f:
			cells.append(anchor + Vector2i(x, z))
	return cells

func _rect_free(anchor: Vector2i, f: int, ignore: Building = null) -> bool:
	for c in _footprint_cells(anchor, f):
		if absf(c.x) > GRID_HALF or absf(c.y) > GRID_HALF:
			return false
		var b: Building = _occupancy.get(c)
		if b != null and b != ignore:
			return false
	return true

func _place_building(b: Building, anchor: Vector2i) -> void:
	b.grid_cell = anchor
	var f := b.footprint()
	for c in _footprint_cells(anchor, f):
		_occupancy[c] = b
	# Centre le bâtiment sur le centre de son empreinte.
	var center := anchor + Vector2i(int(f / 2.0), int(f / 2.0))
	b.global_position = _cell_center(center)
	b.unit_requested.connect(_on_unit_requested, CONNECT_REFERENCE_COUNTED)
	b.building_changed.connect(_refresh_building_panel)
	b.building_changed.connect(_broadcast_building_upgrade.bind(b), CONNECT_REFERENCE_COUNTED)
	b.removed.connect(_on_building_removed, CONNECT_REFERENCE_COUNTED)
	_refresh_population_cap()
	_refresh_building_panel()
	_schedule_rebake()  # le nouveau bâtiment découpe le navmesh (contournement)

func _remove_building_from_grid(b: Building) -> void:
	var f := b.footprint()
	for c in _footprint_cells(b.grid_cell, f):
		if _occupancy.get(c) == b:
			_occupancy.erase(c)
	b.unit_requested.disconnect(_on_unit_requested)
	b.building_changed.disconnect(_refresh_building_panel)

func _on_unit_requested(unit_type: int) -> void:
	var producer: Building = _selected_building
	var spawn_pos := Vector3.ZERO
	if producer != null:
		spawn_pos = producer.global_position + Vector3(1.5, 0, 0)
	else:
		spawn_pos = get_tree().get_first_node_in_group("town_hall").global_position + Vector3(1.5, 0, 0)
	if unit_type == Building.Unit.SOLDIER:
		var s: Node3D = SOLDIER_SCENE.instantiate()
		villager_root.add_child(s)
		s.global_position = spawn_pos
	else:
		var v: Node3D = VILLAGER_SCENE.instantiate()
		villager_root.add_child(v)
		v.global_position = spawn_pos
		_add_default_task(v)
	_refresh_unit_counts()

# ============================================================ SYNC LIVE (MULTIJOUEUR)

## Prépare la réception des unités des autres joueurs et démarre la diffusion
## de nos propres positions vers tous les pairs de la room.
func _setup_remote_units() -> void:
	_remote_units = Node3D.new()
	_remote_units.name = "RemoteUnits"
	add_child(_remote_units)
	# Conteneur des bâtiments distants (les constructions des autres joueurs).
	_remote_building_root = Node3D.new()
	_remote_building_root.name = "RemoteBuildings"
	add_child(_remote_building_root)
	Lobby.player_disconnected.connect(_on_remote_player_disconnected)
	# Diffusion périodique de nos positions.
	_sync_timer = Timer.new()
	_sync_timer.wait_time = UNIT_SYNC_INTERVAL
	_sync_timer.autostart = true
	_sync_timer.timeout.connect(_broadcast_units)
	add_child(_sync_timer)

## Rassemble positions + santé de toutes nos unités (paysans + soldats).
func _collect_unit_states() -> Array:
	var states: Array = []
	for child in villager_root.get_children():
		if child is CharacterBody3D:
			var h: float = child.get("hp") if child.has_method("take_damage") else 100.0
			var mh: float = child.get("max_hp") if child.has_method("take_damage") else 100.0
			var kind: int = 1 if child is Soldier else 0
			states.append([child.global_position, h, mh, kind])
	return states

## Envoie nos unités (positions + santé + type) à tous les pairs.
## Profite du même tick pour diffuser l'ÉTAT COMPLET de nos bâtiments (snapshot
## périodique) : ça couvre à la fois nos constructions initiales (base) ET celles
## de joueurs arrivés après coup, sans événement manquant.
func _broadcast_units() -> void:
	if not Lobby.is_online or multiplayer.multiplayer_peer == null:
		return
	var bstates: Array = _collect_building_states()
	if bstates.size() > 0:
		_sync_buildings.rpc(Lobby.my_id, bstates)
	if villager_root.get_child_count() == 0:
		return
	var payload: Array = _collect_unit_states()
	_sync_units.rpc(Lobby.my_id, payload)

## Rassemble l'état de TOUS nos bâtiments : [type, cell_x, cell_y, level].
## Diffusé périodiquement (voir _broadcast_units) pour que chaque joueur voie le
## monde des autres se mettre à jour (création, déplacement, niveau).
func _collect_building_states() -> Array:
	var states: Array = []
	for child in building_root.get_children():
		var b := child as Building
		if b == null:
			continue
		states.append([b.type, b.grid_cell.x, b.grid_cell.y, b.level])
	return states

## Reçoit l'état complet des bâtiments d'un joueur distant et insère/met à jour
## chacun. Comme c'est un snapshot complet, il remplace proprement l'état local
## des bâtiments de ce joueur (pas de fantôme, pas d'oubli pour les arrivants).
@rpc("any_peer", "reliable", "call_local")
func _sync_buildings(owner_id: int, states: Array) -> void:
	if owner_id == Lobby.my_id:
		return  # on ignore nos propres données (déjà en local)
	for st in states:
		if st.size() >= 4:
			var key := "%d:%d,%d" % [owner_id, st[1], st[2]]
			_upsert_remote_building(owner_id, int(st[0]), Vector2i(int(st[1]), int(st[2])), int(st[3]), key)
	_schedule_rebake()
	_mp_log("SEE_BUILDINGS peer=%d count=%d" % [owner_id, states.size()])

## Reçoit les unités d'un joueur distant et met à jour ses représentations.
@rpc("any_peer", "unreliable_ordered", "call_local")
func _sync_units(owner_id: int, states: Array) -> void:
	if owner_id == Lobby.my_id:
		return  # on ignore nos propres données (déjà en local)
	_update_remote_units(owner_id, states)

## Crée / déplace / masque les représentations des unités d'un joueur distant.
## Chaque état = [position, hp, max_hp, kind] : on reflète position, type ET vie.
func _update_remote_units(owner_id: int, states: Array) -> void:
	if _remote_units == null:
		return
	if not _remote_rep.has(owner_id):
		_remote_rep[owner_id] = []
	var reps: Array = _remote_rep[owner_id]
	# S'assure qu'on a assez de représentations.
	while reps.size() < states.size():
		var cap := _make_remote_unit(owner_id, reps.size())
		_remote_units.add_child(cap)
		reps.append(cap)
	if not _remote_rep.has("_logged_%d" % owner_id) and states.size() > 0:
		_remote_rep["_logged_%d" % owner_id] = true
		_mp_log("SEE_UNITS peer=%d count=%d hp0=%.0f/%.0f" % [owner_id, states.size(), states[0][1], states[0][2]])
	# Positionne les représentations actives + met à jour leur vie.
	for i in states.size():
		var st: Array = states[i]
		var rep: RemoteUnit = reps[i]
		rep.visible = true
		rep.unit_index = i
		rep.global_position = st[0]
		var hpv: float = st[1]
		var maxh: float = st[2]
		_apply_remote_health(rep, hpv, maxh)
	# Masque les représentations surnuméraires.
	for i in range(states.size(), reps.size()):
		reps[i].visible = false

## Met à jour l'échelle (et éventuellement la couleur) d'une représentation
## distante en fonction des points de vie restants.
func _apply_remote_health(rep: Node3D, hpv: float, maxh: float) -> void:
	var ratio := 1.0
	if maxh > 0.0:
		ratio = clampf(hpv / maxh, 0.0, 1.0)
	# Le personnage reste debout mais son échelle verticale se tasse avec la vie,
	# et sa couleur fonce : on voit immédiatement une unité affaiblie.
	var mat := _remote_rep_mat(rep)
	if mat != null:
		mat.albedo_color = _player_color(int(rep.get_meta("owner", 0)))
		mat.albedo_color = mat.albedo_color.lerp(Color.BLACK, 0.5 * (1.0 - ratio))

## Récupère le matériau partagé d'une représentation distante.
func _remote_rep_mat(rep: Node3D) -> StandardMaterial3D:
	if rep == null or not rep.has_meta("_mat"):
		return null
	return rep.get_meta("_mat") as StandardMaterial3D

## Crée une capsule colorée représentant une unité distante. C'est une
## RemoteUnit (attaquable), qui relaie les dégâts au propriétaire réel.
func _make_remote_unit(owner_id: int, index: int) -> RemoteUnit:
	var root := RemoteUnit.new()
	root.owner_peer = owner_id
	root.unit_index = index
	root.relay = self
	root.set_meta("owner", owner_id)
	var mesh := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _player_color(owner_id)
	mat.roughness = 0.8
	mesh.material_override = mat
	mesh.mesh = CapsuleMesh.new()
	mesh.mesh.height = 1.6
	mesh.mesh.radius = 0.35
	root.add_child(mesh)
	root.set_meta("_mat", mat)
	return root

## Couleur stable associée à un peer (pour distinguer les joueurs).
func _player_color(peer_id: int) -> Color:
	return REMOTE_UNIT_COLORS[abs(peer_id) % REMOTE_UNIT_COLORS.size()]

## Journal multijoueur fiable (fichier local ; le stdout est mis en tampon
## quand plusieurs instances graphiques tournent). Un fichier PAR peer.
func _mp_log(msg: String) -> void:
	var f := FileAccess.open("user://ziva_mp_%d.log" % Lobby.my_id, FileAccess.WRITE)
	if f != null:
		f.store_line("[peer=%d] %s" % [Lobby.my_id, msg])
		f.close()

## Demande d'appliquer des dégâts sur une unité appartenant à un autre joueur.
## Envoyé par un attaquant au propriétaire (modèle : le propriétaire fait
## autorité sur sa propre unité). Le propriétaire applique puis la synchro
## périodique diffuse l'état actualisé à tous.
func request_unit_damage(owner_peer: int, unit_index: int, amount: int) -> void:
	if not Lobby.is_online or multiplayer.multiplayer_peer == null:
		return
	# Le propriétaire est l'unique autorité : on cible spécifiquement son pair.
	_apply_unit_damage.rpc_id(owner_peer, unit_index, amount)

## (Chez le propriétaire) applique des dégâts sur l'unité indexée, en vérifiant
## que l'émetteur est bien un des autres joueurs (anti-triche minimal).
@rpc("any_peer", "reliable")
func _apply_unit_damage(unit_index: int, amount: int) -> void:
	if not Lobby.is_online:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender <= 1 or sender == Lobby.my_id:
		return  # on n'accepte ni le relais fantôme ni nous-mêmes
	var units := villager_root.get_children()
	if unit_index < 0 or unit_index >= units.size():
		return
	var unit := units[unit_index]
	if unit.has_method("take_damage"):
		unit.call("take_damage", amount)

## Demande d'appliquer des dégâts sur un bâtiment appartenant à un autre joueur.
func request_building_damage(owner_peer: int, cell: Vector2i, amount: int) -> void:
	if not Lobby.is_online or multiplayer.multiplayer_peer == null:
		return
	_apply_building_damage.rpc_id(owner_peer, cell.x, cell.y, amount)

## (Chez le propriétaire) applique des dégâts sur le bâtiment à la cellule.
@rpc("any_peer", "reliable")
func _apply_building_damage(cx: int, cy: int, amount: int) -> void:
	if not Lobby.is_online:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender <= 1 or sender == Lobby.my_id:
		return
	var key := "%d:%d,%d" % [Lobby.my_id, cx, cy]
	var b: Building = _building_from_key(key)
	if b == null:
		return
	if b.has_method("take_damage"):
		b.call("take_damage", amount)

## Quand un joueur distant quitte, on supprime ses représentations (unités ET
## bâtiments), pour ne pas laisser de fantômes dans notre monde.
func _on_remote_player_disconnected(peer_id: int) -> void:
	if _remote_rep.has(peer_id):
		for rep in _remote_rep[peer_id]:
			if is_instance_valid(rep):
				rep.queue_free()
		_remote_rep.erase(peer_id)
	if _remote_building_root != null:
		for key in _remote_buildings.keys():
			if String(key).begins_with("%d:" % peer_id):
				var b: Building = _remote_buildings[key]
				if is_instance_valid(b):
					b.queue_free()
				_remote_buildings.erase(key)

## Diffuse la construction/déplacement d'un bâtiment à tous les pairs, pour que
## chacun voie le monde partagé se mettre à jour de façon cohérente.
func _sync_building_change(owner_peer: int, btype: int, cell: Vector2i, lvl: int) -> void:
	if not Lobby.is_online or multiplayer.multiplayer_peer == null:
		return
	_sync_building_data.rpc(owner_peer, btype, cell.x, cell.y, lvl)

## Un bâtiment local a changé (upgrade) : on diffuse le nouveau niveau partout,
## pour que la copie distante (et donc le monde des autres) monte aussi de niveau.
func _broadcast_building_upgrade(b: Building) -> void:
	if b == null or not is_instance_valid(b):
		return
	_sync_building_change(Lobby.my_id, b.type, b.grid_cell, b.level)

## Un bâtiment local est détruit (hp ≤ 0) : on diffuse sa suppression à tous les
## pairs pour qu'ils retirent aussi leur copie (pas de fantôme chez les autres).
func _on_building_removed(cell: Vector2i) -> void:
	if not Lobby.is_online or multiplayer.multiplayer_peer == null:
		return
	_sync_building_remove.rpc(Lobby.my_id, cell.x, cell.y)

## Reçoit la destruction d'un bâtiment distant et retire la copie locale.
@rpc("any_peer", "reliable", "call_local")
func _sync_building_remove(owner_peer: int, cx: int, cy: int) -> void:
	if owner_peer == Lobby.my_id:
		return
	var key := "%d:%d,%d" % [owner_peer, cx, cy]
	if _remote_buildings.has(key):
		var b: Building = _remote_buildings[key]
		if is_instance_valid(b):
			b.queue_free()
		_remote_buildings.erase(key)
		_schedule_rebake()

## Reçoit une construction d'un pair distant et crée/actualise sa copie visuelle.
@rpc("any_peer", "reliable", "call_local")
func _sync_building_data(owner_peer: int, btype: int, cx: int, cy: int, lvl: int) -> void:
	if owner_peer == Lobby.my_id:
		return  # on ignore nos propres constructions (déjà en local)
	var key := "%d:%d,%d" % [owner_peer, cx, cy]
	_upsert_remote_building(owner_peer, btype, Vector2i(cx, cy), lvl, key)
	_schedule_rebake()

## Crée ou met à jour un bâtiment distant (copie non sélectionnable, non productive).
func _upsert_remote_building(owner_peer: int, btype: int, cell: Vector2i, lvl: int, key: String) -> void:
	var b: Building = _remote_buildings.get(key) as Building
	if b != null:
		b.type = btype as Building.Type
		b.level = lvl
		b.update_visual_for_sync()
		b.grid_cell = cell
		_center_remote_building(b, cell)
		return
	var nb := Building.new()
	nb.type = btype as Building.Type
	nb.level = lvl
	nb.remote = true
	nb.owner_peer = owner_peer
	nb.relay = self
	nb.add_to_group("enemy")  # attaquable par les autres joueurs
	# Teinte la copie avec la couleur du propriétaire pour distinguer les camps.
	nb.set_owner_tint(_player_color(owner_peer))
	_remote_building_root.add_child(nb)
	nb.grid_cell = cell
	_center_remote_building(nb, cell)
	_remote_buildings[key] = nb

## Centre un bâtiment (distant ou non) sur sa cellule d'ancrage d'après son
## empreinte, au même endroit que le bâtiment source chez le propriétaire.
func _center_remote_building(b: Building, cell: Vector2i) -> void:
	var f := b.footprint()
	var center := cell + Vector2i(int(f / 2.0), int(f / 2.0))
	b.global_position = _cell_center(center)

## Retrouve un bâtiment local (chez nous) par sa cellule d'ancrage (clé distante).
func _building_from_key(key: String) -> Building:
	var parts := key.split(",")
	if parts.size() != 2:
		return null
	var cell := Vector2i(int(parts[0]), int(parts[1]))
	var b: Building = _occupancy.get(cell) as Building
	return b

func _refresh_population_cap() -> void:
	var cap := 0
	for b in building_root.get_children():
		var bb := b as Building
		if bb != null:
			cap += bb.population_provided()
	var rm := get_node("/root/ResourceManager")
	rm.set_population_cap(cap)

# ============================================================ FANTÔME / PLACEMENT

## Crée/met à jour le fantôme de placement pour le type en cours.
func _update_ghost(mouse_pos: Vector2) -> void:
	if _pending_type < 0 and _moving_building == null:
		return
	if _ghost == null:
		var t: Building.Type = (_pending_type as Building.Type) if _pending_type >= 0 else _moving_building.type
		_ghost = Building.new()
		_ghost.type = t
		building_root.add_child(_ghost)
		_ghost.get_node("CollisionShape3D").set_deferred("disabled", true)
		# Transparence pour le fantôme.
		var mat := _ghost.get_node("Mesh").material_override as StandardMaterial3D
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.5
	# Position selon la souris sur le sol.
	var ground := _ground_point(mouse_pos)
	if ground.has("pos"):
		var cell := _cell_from_pos(ground["pos"])
		var f := _ghost.footprint()
		var half := int(f / 2.0)
		var anchor := cell - Vector2i(half, half)
		var center := anchor + Vector2i(half, half)
		_ghost.global_position = _cell_center(center)
		_ghost_valid = _rect_free(anchor, f, _moving_building)
		var mat := _ghost.get_node("Mesh").material_override as StandardMaterial3D
		mat.albedo_color = Color(0.3, 1.0, 0.35, 0.5) if _ghost_valid else Color(1.0, 0.3, 0.3, 0.5)
	else:
		_ghost_valid = false

func _confirm_ghost() -> void:
	if _ghost == null or not _ghost_valid:
		return
	var half := int(_ghost.footprint() / 2.0)
	var anchor := _cell_from_pos(_ghost.global_position) - Vector2i(half, half)
	if _moving_building != null:
		# Déplacement : on réutilise le bâtiment existant.
		_remove_building_from_grid(_moving_building)
		_place_building(_moving_building, anchor)
		_sync_building_change(Lobby.my_id, _moving_building.type, anchor, _moving_building.level)
		_moving_building = null
	else:
		# Construction : achat + placement.
		var cost: Dictionary = Building.TYPES[_pending_type]
		var rm := get_node("/root/ResourceManager")
		var stone_cost: int = int(cost.get("cost_stone", 0))
		if rm.spend_full(cost["cost_gold"], cost["cost_wood"], stone_cost):
			var t: Building.Type = _pending_type as Building.Type
			_pending_type = -1
			_ghost.queue_free()
			_ghost = null
			var b := _instantiate_building(t)
			_place_building(b, anchor)
			_select_building(b)
			_sync_building_change(Lobby.my_id, t, anchor, 1)
		else:
			_notify("Ressources insuffisantes !")
			return
	_cancel_ghost()

func _cancel_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	_pending_type = -1
	_moving_building = null
	_ghost_valid = false
	_highlight_build_buttons()

func _ghost_active() -> bool:
	return _ghost != null or _pending_type >= 0 or _moving_building != null

# ============================================================ ENTRÉES

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F2:
			_spawn_test_player()
			return
		if event.keycode == KEY_F9:
			# DEBUG : sélectionne la première unité (test UI mobile).
			var units: Node3D = get_node_or_null("Units")
			if units != null and units.get_child_count() > 0:
				_select_single_from_node(units.get_child(0))
			return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _ghost_active():
					return  # le clic sert à poser le bâtiment
				_press_pos = event.position
				_dragging = true
				_drag_selecting = false
			else:
				if _ghost_active():
					_confirm_ghost()
					return
				# Ordre armé : le clic sert à exécuter l'ordre sur la cible visée
				# (sol, ressource ou ennemi), comme sur tactile.
				if _order_armed:
					var m: int = _order_mode
					_order_armed = false
					_order_mode = OrderMode.NONE
					if _order_hint != null:
						_order_hint.visible = false
					_refresh_order_button()
					_dragging = false
					_drag_selecting = false
					_order_action(event.position, m)
					return
				_on_left_release(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if _ghost_active():
					_cancel_ghost()
				else:
					_order_action(event.position)
	elif event is InputEventMouseMotion:
		if _ghost_active():
			_update_ghost(event.position)
		elif _dragging:
			if not _drag_selecting and event.position.distance_to(_press_pos) > DRAG_SELECT_THRESHOLD:
				_drag_selecting = true
				_overlay_rect.visible = true
			if _drag_selecting:
				_overlay_rect.from = _press_pos
				_overlay_rect.to = event.position
				_overlay_rect.queue_redraw()
	# --- TACTILE : un tap à 1 doigt = un clic gauche (sélection / pose bâtiment).
	# Un geste à 2 doigts déplace la carte (géré par la caméra): on l'ignore ici.
	elif event is InputEventScreenTouch:
		_touch_count += 1 if event.pressed else -1
		if _touch_count > 1:
			_tap_allowed = false
		if not event.pressed and _touch_count <= 0:
			_touch_count = 0
			if _tap_allowed:
				if _order_armed:
					var m: int = _order_mode
					_order_armed = false
					_order_mode = OrderMode.NONE
					if _order_hint != null:
						_order_hint.visible = false
					_refresh_order_button()
					_order_action(event.position, m)
				elif _ghost_active():
					_confirm_ghost()
				else:
					_on_left_release(event.position)
			_tap_allowed = true

func _on_left_release(release_pos: Vector2) -> void:
	if not _dragging:
		return
	if _drag_selecting:
		_select_box(_press_pos, release_pos)
	elif release_pos.distance_to(_press_pos) <= DRAG_SELECT_THRESHOLD:
		_select_single(release_pos)
	_dragging = false
	_drag_selecting = false
	_overlay_rect.visible = false

## Lance une 2e instance du jeu (nouvelle fenêtre) rejoignant la room actuelle,
## pour tester le multijoueur localement (2 vrais clients). Raccourci : F2.
func _spawn_test_player() -> void:
	var code := Lobby.room_id
	if code.is_empty():
		code = "global"
	var project_path := ProjectSettings.globalize_path("res://")
	var args := PackedStringArray([
		"--path", project_path,
		"--", "--room=%s" % code, "--name=Joueur2",
	])
	var err := OS.create_process(OS.get_executable_path(), args)
	if err >= 0:
		print("2e joueur lancé dans la room « %s » (pid %d)." % [code, err])
		if _hud_room_label != null:
			_hud_room_label.text = "2e joueur lancé (room « %s »)" % code
	else:
		print("Échec du lancement du 2e joueur (err %d)." % err)
		if _hud_room_label != null:
			_hud_room_label.text = "Échec 2e joueur (err %d) — code : %s" % [err, code]

# ============================================================ SÉLECTION

## Sélectionne directement un nœud d'unité (utilisé par les tests et le debug).
func _select_single_from_node(unit: Node) -> void:
	if unit == null:
		return
	_deselect_all()
	_selected_units.append(unit)
	_update_selection_feedback()

func _select_single(screen_pos: Vector2) -> void:
	var hit := _raycast(screen_pos)
	_deselect_all()
	if not hit.is_empty():
		var node: Node = hit["collider"] as Node
		# Clic sur une source : montre qu'elle a été cliquée (anneau lumineux).
		var rn := _resource_at(node)
		if rn != null:
			rn.flash_selected()
		var unit := _unit_at(node)
		if unit != null:
			_selected_units.append(unit)
		else:
			var b := _building_at(node)
			if b != null:
				_select_building(b)
	_update_selection_feedback()

func _select_box(from: Vector2, to: Vector2) -> void:
	var rect := Rect2(from, to - from).abs()
	_deselect_all()
	for child in villager_root.get_children():
		var u := child as Node
		if u == null or not ("set_selected" in u):
			continue
		var sp: Vector2 = _camera.unproject_position(u.global_position)
		if rect.has_point(sp):
			_selected_units.append(u)
	_update_selection_feedback()

func _deselect_all() -> void:
	for u in _selected_units:
		if is_instance_valid(u):
			u.call("set_selected", false)
	_selected_units.clear()
	if _selected_building != null:
		_selected_building.set_selected(false)
		_selected_building = null
	_building_panel.visible = false
	_refresh_order_button()

func _update_selection_feedback() -> void:
	for u in _selected_units:
		if is_instance_valid(u):
			u.call("set_selected", true)
	_refresh_order_button()

func _select_building(b: Building) -> void:
	_selected_building = b
	b.set_selected(true)
	_building_panel.visible = true
	_refresh_building_panel()

# ============================================================ ORDRES (clic droit)

func _order_action(screen_pos: Vector2, mode: int = OrderMode.NONE) -> void:
	if _selected_units.is_empty():
		return
	var hit := _raycast(screen_pos)
	if hit.is_empty():
		return
	var node: Node = hit["collider"] as Node

	# Ressource à puiser.
	var rn := _resource_at(node)
	if rn != null:
		# En mode GATHER explicite, on ignore les non-ressources ; en mode
		# GATHER/auto on récolte la ressource ciblée.
		if mode == OrderMode.ATTACK:
			return
		rn.flash_selected()
		for u in _selected_units:
			if u is Villager:
				u.send_to_gather(rn)
		return

	# Ennemi à attaquer.
	var enemy := _ancestor_in_group(node, "enemy")
	if enemy != null:
		if mode == OrderMode.GATHER:
			return
		for u in _selected_units:
			if u.has_method("attack_target"):
				u.attack_target(enemy as Node3D)
		return

	# Sol : déplacement (paysan -> aller sur place puis au repos ; soldat -> déplacement).
	if mode == OrderMode.GATHER:
		_notify("Touchez une ressource à récolter.")
		return
	var ground := _ground_point(screen_pos)
	if ground.has("pos"):
		for u in _selected_units:
			if u.has_method("move_to_point"):
				u.move_to_point(ground["pos"])

func _ground_point(screen_pos: Vector2) -> Dictionary:
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 1000.0
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {}
	var point: Vector3 = hit["position"]
	# On reporte sur le plan du sol (y=0) pour un placement net.
	point.y = 0.0
	return { "pos": point }

func _raycast(screen_pos: Vector2) -> Dictionary:
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 1000.0
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	return space.intersect_ray(query)

# ============================================================ HELPERS RAYCAST

func _unit_at(node: Node) -> Node:
	var cur: Node = node
	while cur != null:
		if cur is Villager or cur is Soldier:
			return cur
		cur = cur.get_parent()
	return null

func _building_at(node: Node) -> Building:
	var cur: Node = node
	while cur != null:
		if cur is Building:
			return cur
		cur = cur.get_parent()
	return null

func _resource_at(node: Node) -> ResourceNode:
	var cur: Node = node
	while cur != null:
		if cur is ResourceNode:
			return cur
		cur = cur.get_parent()
	return null

func _ancestor_in_group(node: Node, group: String) -> Node:
	var cur: Node = node
	while cur != null:
		if cur.is_in_group(group):
			return cur
		cur = cur.get_parent()
	return null

# ============================================================ UI : SURVOL & HUD

func _setup_selection_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_overlay_rect = SelectionRect.new()
	_overlay_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_overlay_rect)
	_overlay_rect.visible = false

## Couche dédiée aux nombres de récolte flottants (au-dessus du HUD).
func _setup_float_layer() -> void:
	_float_root = CanvasLayer.new()
	_float_root.name = "FloatingText"
	_float_root.layer = 60
	add_child(_float_root)

## Affiche un nombre de récolte cartoonesque sur une position monde (appelé par
## les paysans quand ils prélèvent une ressource).
func show_float_text(world_pos: Vector3, text: String, color: Color) -> void:
	if _float_root == null:
		_setup_float_layer()
	var ft: FloatingText = FLOAT_TEXT_SCENE.new()
	_float_root.add_child(ft)
	ft.start(world_pos, text, color)

func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 12.0
	panel.offset_top = 12.0
	# Fond sombre semi-transparent pour une lisibilité sur mobile
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.corner_radius_top_left = 8
	bg.corner_radius_top_right = 8
	bg.corner_radius_bottom_left = 8
	bg.corner_radius_bottom_right = 8
	bg.content_margin_left = 10
	bg.content_margin_top = 6
	bg.content_margin_right = 10
	bg.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", bg)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	margin.add_child(vb)
	var fs: int = int(16 * _ui_scale)
	_hud_gold_label = Label.new()
	_hud_wood_label = Label.new()
	_hud_stone_label = Label.new()
	_hud_food_label = Label.new()
	_hud_pop_label = Label.new()
	_hud_workers_label = Label.new()
	_hud_soldiers_label = Label.new()
	_hud_room_label = Label.new()
	_hud_room_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	for l in [_hud_gold_label, _hud_wood_label, _hud_stone_label, _hud_food_label,
			_hud_pop_label, _hud_workers_label, _hud_soldiers_label, _hud_room_label]:
		l.add_theme_font_size_override("font_size", fs)
		# Couleur claire pour la lisibilité sur fond sombre
		l.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
		vb.add_child(l)
	var room_code := Lobby.room_id if Lobby.has_base and Lobby.is_online else "hors ligne"
	_hud_room_label.text = "Partie : %s" % room_code
	var rm := get_node("/root/ResourceManager")
	rm.resources_changed.connect(_on_resources_changed)
	rm.population_changed.connect(_on_population_changed)
	_on_resources_changed(rm.gold, rm.wood, rm.stone, rm.food)
	_on_population_changed(rm.population, rm.population_cap)
	_refresh_unit_counts()

func _on_resources_changed(gold: int, wood: int, stone: int, food: int) -> void:
	if _hud_gold_label != null:
		_hud_gold_label.text = "Or : %d" % gold
	if _hud_wood_label != null:
		_hud_wood_label.text = "Bois : %d" % wood
	if _hud_stone_label != null:
		_hud_stone_label.text = "Pierre : %d" % stone
	if _hud_food_label != null:
		_hud_food_label.text = "Nourriture : %d" % food

func _on_population_changed(used: int, cap: int) -> void:
	if _hud_pop_label != null:
		_hud_pop_label.text = "Population : %d / %d" % [used, cap]

## Compte les unités vivantes pour l'affichage Travailleurs / Soldats.
func _refresh_unit_counts() -> void:
	var workers := 0
	var soldiers := 0
	for child in villager_root.get_children():
		if child is Villager:
			workers += 1
		elif child is Soldier:
			soldiers += 1
	if _hud_workers_label != null:
		_hud_workers_label.text = "Travailleurs : %d" % workers
	if _hud_soldiers_label != null:
		_hud_soldiers_label.text = "Soldats : %d" % soldiers

func _notify(text: String) -> void:
	print(text)

# ============================================================ BOUTON ORDRE (mobile)

## Bouton flottant qui remplace le clic droit sur mobile. Apparaît dès qu'une
## unité est sélectionnée ; on le touche pour "armer" l'ordre, puis un tap sur
## le sol / une ressource / un ennemi déclenche _order_action(screen_pos).
func _setup_order_button() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 42
	add_child(layer)
	
	# Barre horizontale en bas de l'écran, remontée au-dessus de la barre de
	# construction (qui occupe le bas-gauche) pour éviter tout chevauchement.
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Remonte au-dessus de la barre de construction (hauteur ~70px) + marge.
	panel.offset_top = -150.0 * _ui_scale
	panel.offset_bottom = -92.0 * _ui_scale
	panel.custom_minimum_size = Vector2(0, 56 * _ui_scale)
	panel.visible = false
	panel.name = "OrderPanel"
	# Fond sombre quasi opaque pour bien la mettre en évidence
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.8)
	bg.corner_radius_top_left = 10
	bg.corner_radius_top_right = 10
	bg.corner_radius_bottom_left = 10
	bg.corner_radius_bottom_right = 10
	bg.border_color = Color(1, 1, 1, 0.25)
	bg.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", bg)
	layer.add_child(panel)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)
	
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(hb)
	_order_bar = hb
	
	# Label d'aide : affiche l'instruction en cours (ex. "Touchez un sol").
	_order_hint = Label.new()
	_order_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_order_hint.add_theme_font_size_override("font_size", int(15 * _ui_scale))
	_order_hint.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	_order_hint.visible = false
	# L'affiche juste au-dessus de la barre d'ordre.
	_order_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_order_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_order_hint.offset_top = -172.0 * _ui_scale
	_order_hint.offset_bottom = -150.0 * _ui_scale
	layer.add_child(_order_hint)
	
	# Boutons d'ordre
	var actions := [
		[OrderMode.MOVE, "🏃 Déplacer"],
		[OrderMode.GATHER, "⛏️ Récolter"],
		[OrderMode.ATTACK, "⚔️ Attaquer"],
	]
	for a in actions:
		var btn := Button.new()
		btn.text = a[1]
		btn.custom_minimum_size = Vector2(110 * _ui_scale, 46 * _ui_scale)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", int(16 * _ui_scale))
		btn.pressed.connect(_arm_order.bind(a[0]))
		hb.add_child(btn)
		_order_btns[a[0]] = btn
	
	# Bouton Stop / Désélectionner (toujours utile)
	var stop_btn := Button.new()
	stop_btn.text = "🛑 Stop"
	stop_btn.custom_minimum_size = Vector2(90 * _ui_scale, 46 * _ui_scale)
	stop_btn.add_theme_font_size_override("font_size", int(16 * _ui_scale))
	stop_btn.pressed.connect(_cancel_selection)
	hb.add_child(stop_btn)

## Annule la sélection en cours (les unités retournent à leur tâche auto).
func _cancel_selection() -> void:
	_deselect_all()
	_notify("Sélection annulée.")

## Arme l'ordre : le prochain tap sur le monde exécutera cet ordre.
func _arm_order(mode: int) -> void:
	if _selected_units.is_empty():
		return
	_order_mode = mode
	_order_armed = true
	var hint := ""
	match mode:
		OrderMode.MOVE: hint = "Touchez un endroit du sol"
		OrderMode.GATHER: hint = "Touchez une ressource (or/bois/pierre)"
		OrderMode.ATTACK: hint = "Touchez un ennemi"
	_notify(hint)
	if _order_hint != null:
		_order_hint.text = "👉 " + hint
		_order_hint.visible = true
	_highlight_order_buttons()

func _highlight_order_buttons() -> void:
	for m in _order_btns:
		var btn := _order_btns[m] as Button
		if btn == null:
			continue
		var is_active: bool = _order_armed and _order_mode == m
		# Fond orange bien visible sur le bouton armé
		var bg := StyleBoxFlat.new()
		if is_active:
			bg.bg_color = Color(0.95, 0.55, 0.1, 0.95)
			bg.corner_radius_top_left = 6
			bg.corner_radius_top_right = 6
			bg.corner_radius_bottom_left = 6
			bg.corner_radius_bottom_right = 6
		else:
			bg.bg_color = Color(0.15, 0.15, 0.18, 0.95)
			bg.corner_radius_top_left = 6
			bg.corner_radius_top_right = 6
			bg.corner_radius_bottom_left = 6
			bg.corner_radius_bottom_right = 6
		btn.add_theme_stylebox_override("normal", bg)
		btn.add_theme_stylebox_override("hover", bg)
		btn.add_theme_stylebox_override("pressed", bg)

## Affiche/masque la barre d'ordre selon la sélection.
func _refresh_order_button() -> void:
	var has_units := not _selected_units.is_empty()
	if _order_bar != null:
		var panel := _order_bar.get_parent().get_parent() as PanelContainer
		if panel != null:
			panel.visible = has_units
	if not has_units:
		_order_armed = false
		_order_mode = OrderMode.NONE
		if _order_hint != null:
			_order_hint.visible = false
		_highlight_order_buttons()

# ============================================================ UI : CONSTRUCTION

func _setup_build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 41
	add_child(layer)
	_build_panel = PanelContainer.new()
	_build_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_build_panel.grow_horizontal = Control.GROW_DIRECTION_END
	_build_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_build_panel.offset_left = 12.0
	_build_panel.offset_top = -12.0
	_build_panel.offset_bottom = -12.0
	layer.add_child(_build_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	_build_panel.add_child(margin)
	var hb := HBoxContainer.new()
	margin.add_child(hb)
	_build_hb = hb
	# Tous les types de bâtiments ; le filtrage par niveau d'hôtel de ville
	# est fait dans _refresh_build_buttons.
	var all_types: Array[Building.Type] = [
		Building.Type.HOUSE, Building.Type.FERME,
		Building.Type.CARRIERE, Building.Type.MINE_OR,
		Building.Type.TOWER, Building.Type.BARRACKS,
	]
	for t in all_types:
		var btn := Button.new()
		var cfg: Dictionary = Building.TYPES[t]
		btn.text = cfg["name"]
		var tooltip := "%d or, %d bois" % [cfg["cost_gold"], cfg["cost_wood"]]
		if cfg.has("cost_stone"):
			tooltip += ", %d pierre" % cfg["cost_stone"]
		btn.tooltip_text = tooltip
		btn.custom_minimum_size = Vector2(120 * _ui_scale, 56 * _ui_scale)
		btn.add_theme_font_size_override("font_size", int(15 * _ui_scale))
		btn.pressed.connect(_on_build_button_pressed.bind(t))
		hb.add_child(btn)
		_build_buttons[t] = btn
	_refresh_build_buttons()

## Affiche/masque les boutons de construction selon le niveau de l'hôtel de ville.
func _refresh_build_buttons() -> void:
	var th_level := _town_hall_level()
	for t in _build_buttons:
		var btn: Button = _build_buttons[t]
		var cfg: Dictionary = Building.TYPES[t]
		btn.visible = th_level >= int(cfg.get("min_th_level", 0))

## Niveau actuel de l'hôtel de ville (0 si absent).
func _town_hall_level() -> int:
	for child in building_root.get_children():
		var b := child as Building
		if b != null and b.building_type() == Building.Type.TOWN_HALL:
			return b.level
	return 0

func _on_build_button_pressed(t: Building.Type) -> void:
	# Toggle : si on reclique sur le même type, on annule.
	if _pending_type == t:
		_cancel_ghost()
		return
	_pending_type = t
	_moving_building = null
	_deselect_all()
	_highlight_build_buttons()

func _highlight_build_buttons() -> void:
	for t in _build_buttons:
		var btn: Button = _build_buttons[t]
		btn.modulate = Color(1, 0.7, 0.3) if _pending_type == t else Color.WHITE

# ============================================================ UI : PANNEAU BÂTIMENT

func _setup_building_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 42
	add_child(layer)
	_building_panel = PanelContainer.new()
	_building_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_building_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_building_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_building_panel.offset_left = -12.0
	_building_panel.offset_right = -12.0
	_building_panel.offset_top = -12.0
	_building_panel.offset_bottom = -12.0
	layer.add_child(_building_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	_building_panel.add_child(margin)
	var vb := VBoxContainer.new()
	margin.add_child(vb)
	_building_title = Label.new()
	vb.add_child(_building_title)
	_building_info = Label.new()
	vb.add_child(_building_info)
	for l in [_building_title, _building_info]:
		l.add_theme_font_size_override("font_size", int(15 * _ui_scale))
		l.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	
	_upgrade_button = Button.new()
	_upgrade_button.text = "Améliorer"
	_upgrade_button.custom_minimum_size = Vector2(0, 40 * _ui_scale)
	_upgrade_button.add_theme_font_size_override("font_size", int(14 * _ui_scale))
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	vb.add_child(_upgrade_button)
	_recruit_button = Button.new()
	_recruit_button.text = "Recruter un paysan"
	_recruit_button.custom_minimum_size = Vector2(0, 40 * _ui_scale)
	_recruit_button.add_theme_font_size_override("font_size", int(14 * _ui_scale))
	_recruit_button.pressed.connect(_on_recruit_pressed)
	vb.add_child(_recruit_button)
	_train_button = Button.new()
	_train_button.text = "Entraîner un soldat"
	_train_button.custom_minimum_size = Vector2(0, 40 * _ui_scale)
	_train_button.add_theme_font_size_override("font_size", int(14 * _ui_scale))
	_train_button.pressed.connect(_on_train_pressed)
	vb.add_child(_train_button)
	_move_button = Button.new()
	_move_button.text = "Déplacer"
	_move_button.custom_minimum_size = Vector2(0, 40 * _ui_scale)
	_move_button.add_theme_font_size_override("font_size", int(14 * _ui_scale))
	_move_button.pressed.connect(_on_move_pressed)
	vb.add_child(_move_button)
	_building_panel.visible = false

func _refresh_building_panel() -> void:
	if _selected_building == null:
		return
	var b := _selected_building
	_building_title.text = "%s (niv. %d)" % [b.building_display_name(), b.level]
	var info := "PV : %d/%d\n" % [b.hp, b.max_hp]
	if b.is_recruiter():
		var rc := b.get_recruit_cost()
		info += "Recruter : %d or, %d nour., %d pop\n" % [rc["gold"], rc["food"], rc["pop"]]
	if b.is_trainer():
		var tc := b.get_train_cost()
		info += "Entraîner : %d or, %d bois, %d pop\n" % [tc["gold"], tc["wood"], tc["pop"]]
	if b.type == Building.Type.HOUSE:
		info += "Logement : +%d pop\n" % b.population_provided()
	if b.is_producer():
		var prod := b.production_per_sec()
		if prod.has("food"):
			info += "Produit : +%d nourriture/s\n" % prod["food"]
		if prod.has("stone"):
			info += "Produit : +%d pierre/s\n" % prod["stone"]
		if prod.has("gold"):
			info += "Produit : +%d or/s\n" % prod["gold"]
	if not b.is_full_level():
		var uc := b.get_upgrade_cost()
		info += "Améliorer : %d or, %d bois" % [uc["gold"], uc["wood"]]
		if int(uc["stone"]) > 0:
			info += ", %d pierre" % uc["stone"]
		info += "\n"
	_building_info.text = info
	# Boutons.
	var cost := b.get_upgrade_cost()
	if cost.is_empty():
		_upgrade_button.text = "Niveau max"
		_upgrade_button.disabled = true
	else:
		_upgrade_button.text = "Améliorer (%d or, %d bois)" % [cost["gold"], cost["wood"]]
		_upgrade_button.disabled = false
	_recruit_button.visible = b.is_recruiter()
	_train_button.visible = b.is_trainer()
	_move_button.visible = true

func _on_upgrade_pressed() -> void:
	if _selected_building != null:
		if _selected_building.upgrade():
			# L'hôtel de ville passe de niveau → débloque de nouveaux bâtiments.
			if _selected_building.building_type() == Building.Type.TOWN_HALL:
				_refresh_build_buttons()
			_refresh_building_panel()

func _on_recruit_pressed() -> void:
	if _selected_building != null:
		_selected_building.try_recruit_villager()

func _on_train_pressed() -> void:
	if _selected_building != null:
		_selected_building.try_train_soldier()

func _on_move_pressed() -> void:
	if _selected_building == null:
		return
	_moving_building = _selected_building
	_deselect_all()
	_moving_building.set_selected(false)
	_update_ghost(get_viewport().get_mouse_position())

# ============================================================ AUTOTEST

func _autotest() -> void:
	var first: Node3D = villager_root.get_child(0)
	var mine: Node = resource_root.get_child(0)
	var rm := get_node("/root/ResourceManager")
	rm.gold = 0
	rm.wood = 0
	first.call("send_to_gather", mine as ResourceNode)
	await get_tree().create_timer(12.0).timeout
	print("AUTOTEST RESULT gold=", rm.gold, " wood=", rm.wood,
		" state=", first.get("_state"), " mine_amount=", mine.get("amount"))
	get_tree().quit()
