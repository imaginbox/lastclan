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
var _inspect_label: Label = null
var _order_btns := {}   # OrderMode -> Button
var _order_hint: Label = null
var _order_armed := false
## Panneau des états du personnage sélectionné (côté droit).
var _unit_panel: PanelContainer = null
var _unit_role_lbl: Label = null
var _unit_hp_lbl: Label = null
var _unit_state_lbl: Label = null
# --- Échelle UI (plus grande sur mobile) ---
var _ui_scale: float = 1.0
## True si l'écran est en portrait (plus haut que large) — guide la répartition
## de l'UI CoC responsive (barre ressources en haut, dock en bas).
var _is_portrait: bool = false

## --- HUD ---
var _hud_gold_label: Label = null
var _hud_wood_label: Label = null
var _hud_stone_label: Label = null
var _hud_food_label: Label = null
var _hud_pop_label: Label = null
var _hud_workers_label: Label = null
var _hud_soldiers_label: Label = null
var _hud_room_label: Label = null
var _hud_hover_label: Label = null
var _hud_realm_label: Label = null
var _hud_clan_label: Label = null
## Sous-infos repliées (CoC) : Population / Royaume / Clan vivent dans un panneau
## flottant accessibles via un bouton « + ». Repliées sur mobile, ouvertes sur PC.
var _hud_extra_box: HBoxContainer = null
var _hud_extra_panel: PanelContainer = null
var _hud_plus_btn: Button = null
var _clan_panel: PanelContainer = null
var _clan_name_input: LineEdit = null
var _clan_tag_input: LineEdit = null
var _clan_join_input: LineEdit = null
var _clan_list_label: Label = null

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
const UNIT_SYNC_INTERVAL: float = 0.2  # ~5 envois/s (léger carrousel réseau instable)
## Fenêtre (ms) pendant laquelle la barre de vie reste affichée après la dernière
## attaque subie. Dès qu'il n'y a plus d'attaques, la barre disparaît au bout de
## HEALTH_BAR_VISIBLE_MS sans nouveau dégât.
const HEALTH_BAR_VISIBLE_MS: int = 3500

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
## Dock central « Construire » (CoC) : un bouton qui se déplie en grille.
var _build_main_btn: Button = null
var _build_menu: PanelContainer = null
var _build_menu_grid: GridContainer = null
## Menu sommet « ☰ » : un bouton qui se déplie en actions du royaume.
var _top_menu_btn: Button = null
var _top_menu_panel: PanelContainer = null
var clan_entry_btn: Button = null
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
	_recompute_orientation()
	# Redimensionnement de la fenêtre -> ré-applique le layout responsive (portrait/paysage).
	get_viewport().size_changed.connect(_refresh_responsive)
	_setup_float_layer()
	_setup_selection_overlay()
	_setup_hud()
	_setup_build_ui()
	_setup_building_panel()
	_setup_order_button()
	# Applique une première fois le layout selon l'orientation détectée.
	_apply_orientation_layout()
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
	# Timer local de mise à jour des barres de vie (online + offline).
	var hb_timer := Timer.new()
	hb_timer.wait_time = 0.15
	hb_timer.autostart = true
	hb_timer.timeout.connect(_update_all_local_health_bars)
	add_child(hb_timer)
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

## Ajoute cercle vert (au sol) + barre de vie (cachée) à une unité LOCALE.
func _add_local_unit_visuals(unit: Node3D) -> void:
	unit.add_child(_make_ground_circle(Color.GREEN))
	unit.add_child(_make_health_bar_node())

func _spawn_villagers() -> void:
	var v: Node3D = VILLAGER_SCENE.instantiate()
	villager_root.add_child(v)
	v.global_position = _base_origin + Vector3(-2.0, 0.0, 0.0)
	_add_local_unit_visuals(v)
	var v2: Node3D = VILLAGER_SCENE.instantiate()
	villager_root.add_child(v2)
	v2.global_position = _base_origin + Vector3(-6.0, 0.0, -6.0)
	_add_local_unit_visuals(v2)
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
	b.building_changed.connect(_refresh_building_panel, CONNECT_REFERENCE_COUNTED)
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
	# Sécurité : si le bâtiment a déjà été libéré (queue_free), Godot a auto-déconnecté
	# ses signaux (CONNECT_REFERENCE_COUNTED). Un disconnect() explicite échouerait
	# avec "Attempt to disconnect a nonexistent connection" → on garde avec is_connected().
	if b.unit_requested.is_connected(_on_unit_requested):
		b.unit_requested.disconnect(_on_unit_requested)
	if b.building_changed.is_connected(_refresh_building_panel):
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
		_add_local_unit_visuals(s)
	else:
		var v: Node3D = VILLAGER_SCENE.instantiate()
		villager_root.add_child(v)
		v.global_position = spawn_pos
		_add_local_unit_visuals(v)
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
	# Synchro des bâtiments : timer SÉPARÉ et lent (rare, éviter la saturation buffer).
	var b_timer := Timer.new()
	b_timer.wait_time = 1.5
	b_timer.autostart = true
	b_timer.timeout.connect(_broadcast_buildings)
	add_child(b_timer)

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
	# Barres de vie locales : mises à jour même hors ligne (test/éditeur).
	_update_all_local_health_bars()
	if not Lobby.is_online or multiplayer.multiplayer_peer == null:
		return
	if villager_root.get_child_count() == 0:
		return
	var payload: Array = _collect_unit_states()
	_sync_units.rpc(Lobby.my_id, payload)

## Diffuse l'état des bâtiments sur un timer LENT (1.5s). Les bâtiments changent
## rarement (construction/upgrade) : les envoyer à chaque tick d'unités (6.6×/s)
## en RPC reliable saturait le buffer WebSocket sur les réseaux instables →
## « Buffer payload full ! Dropping data ». Ici on garde le snapshot complet mais
## espacé, ce qui couvre aussi les joueurs arrivés après coup.
func _broadcast_buildings() -> void:
	if not Lobby.is_online or multiplayer.multiplayer_peer == null:
		return
	var bstates: Array = _collect_building_states()
	if bstates.size() > 0:
		_sync_buildings.rpc(Lobby.my_id, bstates)

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
		var st_new: Array = states[reps.size()]
		var kind: int = int(st_new[3]) if st_new.size() > 3 else 0
		var cap := _make_remote_unit(owner_id, reps.size(), kind)
		_remote_units.add_child(cap)
		reps.append(cap)
	if not _remote_rep.has("_logged_%d" % owner_id) and states.size() > 0:
		_remote_rep["_logged_%d" % owner_id] = true
		_mp_log("SEE_UNITS peer=%d count=%d hp0=%.0f/%.0f" % [owner_id, states.size(), states[0][1], states[0][2]])
	# Positionne les représentations actives + met à jour leur vie (barre de vie au lieu de couleur).
	for i in states.size():
		var st: Array = states[i]
		var rep: RemoteUnit = reps[i]
		rep.visible = true
		rep.unit_index = i
		rep.global_position = st[0]
		var hpv: float = st[1]
		var maxh: float = st[2]
		# Unité morte (hp ≤ 0) : on la masque entièrement (corps + barre) pour
		# qu'elle disparaisse dès la mise à jour, sans attendre la prochaine synchro.
		if hpv <= 0.0:
			rep.visible = false
			continue
		rep.visible = true
		var hb := rep.get_node_or_null("HealthBar") as Node3D
		if hb != null:
			_update_health_bar(hb, hpv, maxh, rep.last_damage_ms)
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

## --- Composants visuels pour les unités (locales ET distantes) ---

## Cercle au sol sous une unité : VERT pour les siennes, ROUGE pour les ennemies.
func _make_ground_circle(col: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission = col
	mat.emission_energy_multiplier = 0.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35
	cm.bottom_radius = 0.35
	cm.height = 0.01
	mesh.mesh = cm
	mesh.position = Vector3(0, 0.05, 0)
	return mesh

## Barre de vie 3D au-dessus d'une unité (billboard, cachée par défaut).
## Fond + remplissage + NOMBRE de PV au-dessus (Label3D), pour savoir clairement
## quand une unité perd de la vie.
func _make_health_bar_node() -> Node3D:
	var container := Node3D.new()
	container.position = Vector3(0, 1.9, 0)
	container.visible = false
	# Fond sombre (pleine largeur)
	var bg := MeshInstance3D.new()
	var bg_quad := QuadMesh.new()
	bg_quad.size = Vector2(1.5, 0.18)
	bg.mesh = bg_quad
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.05, 0.05, 0.05, 0.9)
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg.material_override = bg_mat
	bg.name = "Bg"
	container.add_child(bg)
	# Barre remplie (verte/jaune/rouge selon ratio)
	var fill := MeshInstance3D.new()
	var fill_quad := QuadMesh.new()
	fill_quad.size = Vector2(1.3, 0.14)
	fill.mesh = fill_quad
	var fill_mat := StandardMaterial3D.new()
	fill_mat.albedo_color = Color.GREEN
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill.material_override = fill_mat
	fill.position.x = -0.65
	fill.name = "Fill"
	container.add_child(fill)
	# Nombre de PV au-dessus de la barre (Label3D billboard).
	var lbl := Label3D.new()
	lbl.name = "HpLabel"
	lbl.position = Vector3(0, 0.24, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.pixel_size = 0.008
	lbl.font_size = 64
	lbl.modulate = Color.WHITE
	lbl.outline_size = 16
	lbl.outline_modulate = Color(0, 0, 0, 1)
	lbl.no_depth_test = true
	container.add_child(lbl)
	container.set_meta("bar_fill", fill)
	container.set_meta("bar_label", lbl)
	container.name = "HealthBar"
	return container

## Met à jour la barre de vie : affichée uniquement si PV < max ET si l'unité a
## été frappée récemment (elle disparaît dès qu'il n'y a plus d'attaques).
## Met aussi à jour le NOMBRE de PV (« 34/100 ») qui descend quand l'unité perd
## de la vie, visible au-dessus de la barre.
func _update_health_bar(container: Node3D, hp: float, max_hp: float, last_damage_ms: int = -100000) -> void:
	# État mort : on masque TOUJOURS la barre/nombre de PV, même si l'unité a été
	# touchée il y a un instant — une unité à 0 PV ne doit plus afficher de vie.
	if hp <= 0.0:
		container.visible = false
		# Met quand même le libellé à 0 pour ne rien laisser de "fantôme" cohérent.
		var dlbl := container.get_node_or_null("HpLabel") as Label3D
		if dlbl != null:
			dlbl.text = "0/%d" % int(round(max_hp))
		return
	var ratio := clampf(hp / max_hp if max_hp > 0 else 0.0, 0.0, 1.0)
	var recently_hit := Time.get_ticks_msec() - last_damage_ms < HEALTH_BAR_VISIBLE_MS
	container.visible = ratio < 0.99 and recently_hit
	var fill: MeshInstance3D = container.get_meta("bar_fill", null) as MeshInstance3D
	if fill == null:
		return
	var fq: QuadMesh = fill.mesh as QuadMesh
	if fq == null:
		return
	fq.size = Vector2(ratio * 1.3, 0.14)
	fill.position.x = -0.65 + ratio * 0.65
	var fm: StandardMaterial3D = fill.material_override as StandardMaterial3D
	if fm != null:
		if ratio > 0.6:
			fm.albedo_color = Color.GREEN
		elif ratio > 0.3:
			fm.albedo_color = Color.YELLOW
		else:
			fm.albedo_color = Color.RED
	var lbl := container.get_node_or_null("HpLabel") as Label3D
	if lbl != null:
		lbl.text = "%d/%d" % [int(round(hp)), int(round(max_hp))]

## Met à jour les barres de vie de TOUTES les unités locales (online + offline).
func _update_all_local_health_bars() -> void:
	if villager_root == null:
		return
	for child in villager_root.get_children():
		if child is CharacterBody3D and child.has_method("take_damage"):
			var hb := child.get_node_or_null("HealthBar") as Node3D
			if hb != null:
				var hp: float = float(child.get("hp")) if child.get("hp") != null else 100.0
				var mh: float = float(child.get("max_hp")) if child.get("max_hp") != null else 100.0
				var ld: int = int(child.get("last_damage_ms")) if child.get("last_damage_ms") != null else -100000
				_update_health_bar(hb, hp, mh, ld)

## Crée une unité distante avec le VRAI modèle (paysan/soldat) + cercle rouge + barre de vie.
func _make_remote_unit(owner_id: int, index: int, kind: int) -> RemoteUnit:
	var root := RemoteUnit.new()
	root.owner_peer = owner_id
	root.unit_index = index
	root.relay = self
	root.set_meta("owner", owner_id)
	# Vrai modèle (comme les unités locales)
	var model := VillagerModel.new()
	model.name = "Model"
	model.transform = Transform3D(Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0)), Vector3.ZERO)
	if kind == 1:  # soldat → teinte rouge
		model.tint = _player_color(owner_id).lerp(Color.RED, 0.5)
	else:  # paysan → couleur du joueur
		model.tint = _player_color(owner_id)
	root.add_child(model)
	# Corps de collision : rend l'unité distante cliquable/ciblable au raycast
	# (sinon l'ennemi est invisible pour la sélection d'attaque -> on ne peut
	# jamais l'attaquer). StaticBody = corps d'ancrage simple, sans physique.
	var body := StaticBody3D.new()
	body.name = "Body"
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	cs.shape = cap
	cs.position = Vector3(0, 0.8, 0)
	body.add_child(cs)
	body.collision_layer = 2   # couche "unités"
	body.collision_mask = 0
	root.add_child(body)
	# Cercle rouge au sol (ennemi)
	root.add_child(_make_ground_circle(Color.RED))
	# Barre de vie (cachée, apparaît en combat)
	root.add_child(_make_health_bar_node())
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
func request_unit_damage(owner_peer: int, unit_index: int, amount: int, attacker_pos: Vector3 = Vector3.ZERO) -> void:
	if not Lobby.is_online or multiplayer.multiplayer_peer == null:
		return
	# Le propriétaire est l'unique autorité : on cible spécifiquement son pair.
	_apply_unit_damage.rpc_id(owner_peer, unit_index, amount, attacker_pos)

## (Chez le propriétaire) applique des dégâts sur l'unité indexée, en vérifiant
## que l'émetteur est bien un des autres joueurs (anti-triche minimal).
@rpc("any_peer", "reliable")
func _apply_unit_damage(unit_index: int, amount: int, attacker_pos: Vector3 = Vector3.ZERO) -> void:
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
		unit.call("take_damage", amount, attacker_pos)
		# Côté défenseur : nombre de dégâts rouge visible au-dessus de l'unité touchée.
		show_damage_float(unit.global_position, amount)
		# NB : la défense auto (contre-attaque/fuite) est déclenchée dans take_damage.

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
		else:
			_update_hover(event.position)
		if _dragging:
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
	_refresh_inspector()

func _update_selection_feedback() -> void:
	for u in _selected_units:
		if is_instance_valid(u):
			u.call("set_selected", true)
	_refresh_order_button()
	_refresh_inspector()

func _select_building(b: Building) -> void:
	# On ne PEUT PAS sélectionner/manipuler les bâtiments des autres joueurs :
	# les copies distantes sont de simples visuels + obstacles (non sélectionnables).
	if b.remote:
		return
	_selected_building = b
	b.set_selected(true)
	_building_panel.visible = true
	_refresh_building_panel()

# ============================================================ ORDRES (clic droit)

func _order_action(screen_pos: Vector2, mode: int = OrderMode.NONE) -> void:
	if _selected_units.is_empty():
		return

	# MODES EXPLICITES : quand on a choisi un mode puis qu'on tape sur le monde,
	# le groupe exécute DIRECTEMENT ce mode à cet endroit (pas de détection
	# "intelligente" ambigüe). Le clic droit (mode NONE) garde l'auto-détection.
	match mode:
		OrderMode.MOVE:
			_execute_move_order(screen_pos)
			return
		OrderMode.GATHER:
			_execute_gather_order(screen_pos)
			return
		OrderMode.ATTACK:
			_execute_attack_order(screen_pos)
			return

	# --- MODE AUTO (mode == NONE) : clic droit ---
	var hit := _raycast(screen_pos)
	if hit.is_empty():
		return
	var node: Node = hit["collider"] as Node
	# Ressource à puiser.
	var rn := _resource_at(node)
	if rn != null:
		rn.flash_selected()
		for u in _selected_units:
			if u is Villager:
				u.send_to_gather(rn)
		return
	# Ennemi à attaquer.
	var enemy := _ancestor_in_group(node, "enemy")
	if enemy != null:
		for u in _selected_units:
			if u.has_method("attack_target"):
				u.attack_target(enemy as Node3D)
			elif u.has_method("attack_node"):
				u.attack_node(enemy as Node3D)
		return
	# Sol : déplacement.
	var ground := _ground_point(screen_pos)
	if ground.has("pos"):
		for u in _selected_units:
			if u.has_method("move_to_point"):
				u.move_to_point(ground["pos"])

## MODE DÉPLACEMENT : le groupe se rend au point cliqué, quoi qu'il y ait dessus
## (ressource, ennemi, décor). On ne récolte/attaque pas.
func _execute_move_order(screen_pos: Vector2) -> void:
	var ground := _ground_point(screen_pos)
	if not ground.has("pos"):
		return
	for u in _selected_units:
		if u.has_method("move_to_point"):
			u.move_to_point(ground["pos"])

## MODE RÉCOLTE : le groupe récolte la ressource au point cliqué ; sinon la
## ressource la plus proche de ce point. Soldats sélectionnés : ignorés.
func _execute_gather_order(screen_pos: Vector2) -> void:
	var hit := _raycast(screen_pos)
	var rn: ResourceNode = null
	if not hit.is_empty():
		rn = _resource_at(hit["collider"] as Node)
	if rn == null:
		# Aucune ressource exacte sous le curseur : on prend la plus proche du point.
		rn = _nearest_resource_to(screen_pos)
	if rn == null or not rn.has_left():
		_notify("Touchez une ressource à récolter.")
		return
	rn.flash_selected()
	var got_villager := false
	for u in _selected_units:
		if u is Villager:
			u.send_to_gather(rn)
			got_villager = true
	if not got_villager:
		_notify("Sélectionnez un paysan pour récolter.")

## MODE ATTAQUE : le groupe attaque l'ennemi au point cliqué ; sinon l'ennemi
## le plus proche de ce point.
func _execute_attack_order(screen_pos: Vector2) -> void:
	var hit := _raycast(screen_pos)
	var enemy: Node3D = null
	if not hit.is_empty():
		enemy = _ancestor_in_group(hit["collider"] as Node, "enemy") as Node3D
	if enemy == null:
		enemy = _nearest_enemy_to(screen_pos)
	if enemy == null:
		_notify("Touchez un ennemi à attaquer.")
		return
	for u in _selected_units:
		if u.has_method("attack_target"):
			u.attack_target(enemy)
		elif u.has_method("attack_node"):
			u.attack_node(enemy)

## Ressource la plus proche du point de l'écran (projection rayon -> plan sol).
func _nearest_resource_to(screen_pos: Vector2) -> ResourceNode:
	var ground := _ground_point(screen_pos)
	if not ground.has("pos"):
		return null
	var p: Vector3 = ground["pos"]
	var best: ResourceNode = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("resource"):
		var r := node as ResourceNode
		if r != null and r.has_left():
			var d := p.distance_squared_to(r.global_position)
			if d < best_d:
				best_d = d
				best = r
	return best

## Ennemi (groupe "enemy") le plus proche du point de l'écran.
func _nearest_enemy_to(screen_pos: Vector2) -> Node3D:
	var ground := _ground_point(screen_pos)
	if not ground.has("pos"):
		return null
	var p: Vector3 = ground["pos"]
	var best: Node3D = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("enemy"):
		if node is Node3D:
			var d := p.distance_squared_to((node as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = node as Node3D
	return best

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

## Met à jour le label de survol : si le curseur est sur un personnage ou un
## bâtiment, on affiche le nom du joueur qui le possède. Sinon, on le masque.
func _update_hover(screen_pos: Vector2) -> void:
	if _hud_hover_label == null:
		return
	var hit := _raycast(screen_pos)
	var name_text := ""
	if not hit.is_empty():
		var node: Node = hit["collider"] as Node
		var unit := _unit_at(node)
		if unit != null:
			name_text = _owner_name(unit)
		else:
			# Unité distante ou bâtiment : l'owner est stocké en meta / propriété.
			var owner := _owner_of(node)
			if owner != -1:
				name_text = _owner_name_id(owner)
	if name_text.is_empty():
		_hud_hover_label.visible = false
	else:
		_hud_hover_label.text = "👑 %s" % name_text
		_hud_hover_label.visible = true

## Nom du joueur propriétaire d'UNE UNITÉ LOCALE (Villager/Soldier) : nous.
func _owner_name(obj: Node) -> String:
	return _owner_name_id(Lobby.my_id)

## Remonte la hiérarchie pour trouver le peer propriétaire (RemoteUnit.owner_peer
## ou Building.owner_peer, ou meta "owner"). -1 si aucun joueur propriétaire clair.
func _owner_of(node: Node) -> int:
	var cur: Node = node
	while cur != null:
		if cur is RemoteUnit and cur.get("owner_peer") != null:
			return int(cur.get("owner_peer"))
		if cur is Building and cur.get("owner_peer") != null:
			return int(cur.get("owner_peer"))
		if cur.has_meta("owner"):
			return int(cur.get_meta("owner"))
		cur = cur.get_parent()
	return -1

## Résout le peer_id en nom de joueur via le roster de Lobby.
func _owner_name_id(peer_id: int) -> String:
	if peer_id <= 0:
		return ""
	if peer_id == Lobby.my_id:
		return str(Lobby.player_info.get("name", "Moi"))
	if Lobby.players.has(peer_id):
		var info: Dictionary = Lobby.players[peer_id]
		return str(info.get("name", "Joueur %d" % peer_id))
	return "Joueur %d" % peer_id

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

## Affiche un nombre de DÉGÂTS « -X » en rouge au-dessus d'une unité, pour qu'on
## voie clairement qu'elle perd de la vie. Appelé des deux côtés (attaquant ET
## défenseur) pour que l'info soit visible partout.
func show_damage_float(world_pos: Vector3, amount: int) -> void:
	show_float_text(world_pos + Vector3(0, 0.4, 0), "-%d" % amount, Color(1.0, 0.25, 0.25))

func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	# Barre de ressources style Clash of Clans en haut : chaque ressource dans
	# son cartouche arrondi (fond bois + liseré doré), icône à gauche, valeur à
	# droite. La rangée est centrée, comme l'interface CoC.
	var top := PanelContainer.new()
	top.name = "ResourceBar"
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 10.0 * _ui_scale
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Conteneur transparent : seuls les cartouches individuels ont un fond.
	top.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	layer.add_child(top)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", int(8 * _ui_scale))
	top.add_child(hb)
	# Cartouches des 4 ressources principales (CoC).
	_hud_gold_label = _make_resource_pill(hb, "gold", Color(1.0, 0.85, 0.3))
	_hud_wood_label = _make_resource_pill(hb, "wood", Color(0.75, 0.55, 0.35))
	_hud_stone_label = _make_resource_pill(hb, "stone", Color(0.7, 0.72, 0.75))
	_hud_food_label = _make_resource_pill(hb, "food", Color(0.9, 0.6, 0.4))
	# Bouton « + » : déplie les sous-infos (population, royaume, clan) — CoC.
	_hud_plus_btn = Button.new()
	_hud_plus_btn.name = "HudPlusButton"
	_hud_plus_btn.text = "＋"
	_hud_plus_btn.custom_minimum_size = Vector2(36 * _ui_scale, 36 * _ui_scale)
	_hud_plus_btn.add_theme_font_size_override("font_size", int(20 * _ui_scale))
	_hud_plus_btn.focus_mode = Control.FOCUS_NONE
	_stylize_coc_button(_hud_plus_btn)
	_hud_plus_btn.pressed.connect(_toggle_extra_info)
	hb.add_child(_hud_plus_btn)
	# ===== Panneau flottant des sous-infos (Population / Royaume / Clan).
	_hud_extra_panel = PanelContainer.new()
	_hud_extra_panel.name = "ExtraInfo"
	_hud_extra_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hud_extra_panel.grow_horizontal = Control.GROW_DIRECTION_END
	_hud_extra_panel.offset_left = 10.0 * _ui_scale
	_hud_extra_panel.offset_top = 56.0 * _ui_scale
	_hud_extra_panel.visible = false
	var eb := StyleBoxFlat.new()
	eb.bg_color = Color(0.1, 0.12, 0.16, 0.92)
	eb.corner_radius_top_left = 10
	eb.corner_radius_top_right = 10
	eb.corner_radius_bottom_left = 10
	eb.corner_radius_bottom_right = 10
	eb.border_color = Color(0.6, 0.7, 0.9, 0.4)
	eb.set_border_width_all(2)
	eb.content_margin_left = 12
	eb.content_margin_right = 12
	eb.content_margin_top = 10
	eb.content_margin_bottom = 10
	_hud_extra_panel.add_theme_stylebox_override("panel", eb)
	layer.add_child(_hud_extra_panel)
	_hud_extra_box = HBoxContainer.new()
	_hud_extra_box.add_theme_constant_override("separation", int(10 * _ui_scale))
	_hud_extra_panel.add_child(_hud_extra_box)
	# Population.
	_hud_pop_label = _make_resource_pill(_hud_extra_box, "pop", Color(0.6, 0.9, 1.0))
	# Jauge du royaume (icône image).
	_hud_realm_label = _make_resource_pill(_hud_extra_box, "realm", Color(0.95, 0.95, 0.75))
	# Indicateur clan : icône bouclier + texte compact (pas d'émoji).
	var clan_row := HBoxContainer.new()
	clan_row.add_theme_constant_override("separation", int(4 * _ui_scale))
	clan_row.alignment = BoxContainer.ALIGNMENT_CENTER
	clan_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var clan_tex := TextureRect.new()
	clan_tex.texture = _icon("shield")
	var csize: float = 20.0 * _ui_scale
	clan_tex.custom_minimum_size = Vector2(csize, csize)
	clan_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	clan_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	clan_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clan_row.add_child(clan_tex)
	_hud_clan_label = Label.new()
	_hud_clan_label.add_theme_font_size_override("font_size", int(14 * _ui_scale))
	_hud_clan_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	_hud_clan_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hud_clan_label.add_theme_constant_override("outline_size", 6)
	_hud_clan_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clan_row.add_child(_hud_clan_label)
	_hud_extra_box.add_child(clan_row)
	# Liaisons données -> UI.
	if get_node_or_null("/root/Realm") != null:
		Realm.realm_changed.connect(_on_realm_changed)
		_on_realm_changed(Realm.value, Realm.zone())
	if get_node_or_null("/root/Clans") != null:
		Clans.my_clan_changed.connect(_on_my_clan_changed)
		_on_my_clan_changed()
	var rm := get_node("/root/ResourceManager")
	rm.resources_changed.connect(_on_resources_changed)
	rm.population_changed.connect(_on_population_changed)
	_on_resources_changed(rm.gold, rm.wood, rm.stone, rm.food)
	_on_population_changed(rm.population, rm.population_cap)
	_refresh_unit_counts()
	# Bouton pour ouvrir le panneau Clan (mobile + PC).
	_setup_clan_button()

## Crée un « cartouche » de ressource style Clash of Clans : un petit panneau
## arrondi (fond bois sombre + liseré doré) contenant une icône à gauche et la
## valeur à droite. L'icône est un sprite (visible sur navigateur, pas d'émoji)
## et reste remplaçable par tes propres PNG. Retourne le Label de la valeur.
func _make_resource_pill(parent: HBoxContainer, icon_key: String, _color: Color) -> Label:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.16, 0.12, 0.09, 0.92)          # bois sombre CoC
	cs.corner_radius_top_left = 7
	cs.corner_radius_top_right = 7
	cs.corner_radius_bottom_left = 7
	cs.corner_radius_bottom_right = 7
	cs.border_color = Color(0.85, 0.66, 0.3, 0.95)       # liseré doré
	cs.set_border_width_all(2)
	cs.content_margin_left = 8 * _ui_scale
	cs.content_margin_right = 10 * _ui_scale
	cs.content_margin_top = 3 * _ui_scale
	cs.content_margin_bottom = 3 * _ui_scale
	card.add_theme_stylebox_override("panel", cs)
	parent.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(5 * _ui_scale))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(row)
	var tex := TextureRect.new()
	tex.texture = _icon(icon_key)
	var size: float = 22.0 * _ui_scale
	tex.custom_minimum_size = Vector2(size, size)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tex)
	var lab := Label.new()
	lab.add_theme_font_size_override("font_size", int(16 * _ui_scale))
	lab.add_theme_color_override("font_color", Color(1.0, 0.96, 0.8))
	lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lab.add_theme_constant_override("outline_size", 6)
	lab.text = "0"
	row.add_child(lab)
	return lab

## Chargement en cache des icônes de ressources (sprites, pas d'émojis).
var _icon_cache := {}
func _icon(key: String) -> Texture2D:
	if _icon_cache.has(key):
		return _icon_cache[key]
	var tex := load("res://assets/generated/icon_%s.png" % key)
	_icon_cache[key] = tex
	return tex

## Détecte l'orientation courante (portrait si plus haut que large). Utilisée
## par les helpers de layout pour répartir l'UI (barre ressources, dock, panels).
func _recompute_orientation() -> void:
	var size := get_viewport().get_visible_rect().size
	_is_portrait = size.y > size.x

## Ré-applique le layout responsive après un redimensionnement de fenêtre.
func _refresh_responsive() -> void:
	var pre := _is_portrait
	_recompute_orientation()
	if pre != _is_portrait:
		# L'orientation a changé : on repositionne quelques ancres clés.
		_apply_orientation_layout()

func _apply_orientation_layout() -> void:
	# Le dock de construction central et le bouton ☰ s'adaptent à l'orientation.
	if _is_portrait:
		# Portrait : grille de construction sur 2 colonnes pour rester dans l'écran.
		if _build_menu_grid != null:
			_build_menu_grid.columns = 2
		if _top_menu_panel != null:
			_top_menu_panel.offset_left = -300.0 * _ui_scale
		# Sous-infos repliées sur mobile (accès via le bouton « + »).
		if _hud_extra_panel != null:
			_hud_extra_panel.visible = false
			_hud_plus_btn.modulate = Color.WHITE
	else:
		# Paysage : grille sur 3 colonnes.
		if _build_menu_grid != null:
			_build_menu_grid.columns = 3
		if _top_menu_panel != null:
			_top_menu_panel.offset_left = -320.0 * _ui_scale
		# Sur PC, sous-infos ouvertes d'office (assez de place).
		if _hud_extra_panel != null and not _hud_extra_panel.visible:
			_hud_extra_panel.visible = true
			_hud_plus_btn.modulate = Color(1, 0.8, 0.4)
	# Position du panneau des sous-infos : CENTRÉ sous la barre de ressources
	# (la barre est centrée, les sous-infos suivent le même alignement).
	if _hud_extra_panel != null:
		var ew: float = 460.0 * _ui_scale
		_hud_extra_panel.anchor_left = 0.5
		_hud_extra_panel.anchor_right = 0.5
		_hud_extra_panel.offset_left = -ew * 0.5
		_hud_extra_panel.offset_right = ew * 0.5
		_hud_extra_panel.offset_top = 58.0 * _ui_scale


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

## Met à jour la jauge « Sort du Royaume » dans le HUD.
func _on_realm_changed(value: float, zone: String) -> void:
	if _hud_realm_label == null:
		return
	var color := Color(0.7, 0.9, 0.5)
	match zone:
		"prosperity":
			color = Color(0.5, 1.0, 0.5)
			_hud_realm_label.add_theme_color_override("font_color", color)
		"decline":
			color = Color(1.0, 0.5, 0.4)
			_hud_realm_label.add_theme_color_override("font_color", color)
		_:
			color = Color(0.95, 0.95, 0.75)
			_hud_realm_label.add_theme_color_override("font_color", color)
	_hud_realm_label.text = "Royaume : %d" % int(value)

## Met à jour mon affiliation de clan dans le HUD.
func _on_my_clan_changed() -> void:
	if _hud_clan_label == null:
		return
	if Clans.my_clan == "":
		_hud_clan_label.text = "Aucun clan — touchez « Clan »"
	else:
		_hud_clan_label.text = "%s (%s)" % [Clans.my_clan_name(), Clans.my_clan]

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

## Inspecteur : affiche les états du personnage sélectionné dans le panneau
## de droite (mobile + PC). Donne au joueur un retour clair sur ce qu'il fait.
func _refresh_inspector() -> void:
	if _unit_panel == null:
		return
	if _selected_units.size() != 1 or not is_instance_valid(_selected_units[0]):
		_unit_panel.visible = false
		return
	var u: Node = _selected_units[0]
	var role := ""
	var hp_str := ""
	var state_str := ""
	if u is Villager:
		role = "Paysan"
		hp_str = "Vie : %d / %d" % [u.hp, u.max_hp]
		match int(u._state):
			Villager.State.GOING_TO_RESOURCE: state_str = "En route vers la ressource"
			Villager.State.GATHERING: state_str = "Récolte en cours…"
			Villager.State.RETURNING: state_str = "Livre la ressource (%d)" % u._carried_amount
			Villager.State.ATTACKING: state_str = "Combat"
			Villager.State.MOVING: state_str = "Se déplace"
			_: state_str = "En attente (idle)"
	elif u is Soldier:
		role = "Soldat"
		hp_str = "Vie : %d / %d" % [u.hp, u.max_hp]
		match int(u._state):
			Soldier.State.ATTACK: state_str = "Combat"
			Soldier.State.MOVE: state_str = "Se déplace"
			_: state_str = "En attente (idle)"
	else:
		_unit_panel.visible = false
		return
	_unit_role_lbl.text = role
	_unit_hp_lbl.text = hp_str
	_unit_state_lbl.text = state_str
	_unit_panel.visible = true

# ============================================================ PANEL CLAN

## Bouton flottant « Clan » (coin supérieur droit) : ouvre/ferme le panneau.
func _setup_clan_button() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 41
	add_child(layer)
	# ===== Bouton hub « ☰ » (sommet droite) : se déplie en actions du royaume.
	_top_menu_btn = Button.new()
	_top_menu_btn.name = "MenuButton"
	_top_menu_btn.text = "☰"
	_top_menu_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_top_menu_btn.offset_left = -60.0 * _ui_scale
	_top_menu_btn.offset_top = 12.0 * _ui_scale
	_top_menu_btn.offset_right = -12.0 * _ui_scale
	_top_menu_btn.offset_bottom = (12.0 + 46.0 * _ui_scale) * _ui_scale
	_top_menu_btn.add_theme_font_size_override("font_size", int(22 * _ui_scale))
	_stylize_coc_button(_top_menu_btn)
	_top_menu_btn.pressed.connect(_toggle_top_menu)
	layer.add_child(_top_menu_btn)
	# ===== Panneau qui se déplie : liste verticale d'actions du royaume.
	_top_menu_panel = PanelContainer.new()
	_top_menu_panel.name = "TopMenu"
	_top_menu_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_top_menu_panel.offset_left = -320.0 * _ui_scale
	_top_menu_panel.offset_top = 64.0 * _ui_scale
	_top_menu_panel.offset_right = -12.0 * _ui_scale
	_top_menu_panel.grow_vertical = Control.GROW_DIRECTION_END
	_top_menu_panel.visible = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.12, 0.16, 0.96)
	bg.corner_radius_top_left = 12
	bg.corner_radius_top_right = 12
	bg.corner_radius_bottom_left = 12
	bg.corner_radius_bottom_right = 12
	bg.border_color = Color(0.6, 0.7, 0.9, 0.45)
	bg.set_border_width_all(2)
	bg.content_margin_left = 10
	bg.content_margin_right = 10
	bg.content_margin_top = 8
	bg.content_margin_bottom = 8
	_top_menu_panel.add_theme_stylebox_override("panel", bg)
	layer.add_child(_top_menu_panel)
	var mv := MarginContainer.new()
	for m in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		mv.add_theme_constant_override(m, 6)
	_top_menu_panel.add_child(mv)
	var mvb := VBoxContainer.new()
	mvb.add_theme_constant_override("separation", 8)
	mv.add_child(mvb)
	# Entrées du menu (chaque un bouton dépliable ou action).
	var _realm_btn := _make_top_menu_item(mvb, "Royaume", _notify.bind("Jauge du royaume (bientôt détaillée)"))
	clan_entry_btn = _make_top_menu_item(mvb, "Clan", _toggle_clan_panel)
	var _settings_btn := _make_top_menu_item(mvb, "Paramètres", _notify.bind("Paramètres (bientôt)"))
	_make_top_menu_item(mvb, "Langue", _toggle_language_popup)
	var close_btn := Button.new()
	close_btn.text = "Fermer"
	close_btn.custom_minimum_size = Vector2(0, 40 * _ui_scale)
	close_btn.add_theme_font_size_override("font_size", int(15 * _ui_scale))
	_stylize_coc_button(close_btn)
	close_btn.pressed.connect(_toggle_top_menu)
	mvb.add_child(close_btn)
	# Le panneau Clan réutilise l'ancien emplacement.
	_clan_panel = PanelContainer.new()
	_clan_panel.name = "ClanPanel"
	_clan_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_clan_panel.offset_left = -340.0 * _ui_scale
	_clan_panel.offset_top = 64.0 * _ui_scale
	_clan_panel.offset_right = -12.0 * _ui_scale
	_clan_panel.offset_bottom = 64.0 * _ui_scale + 320.0 * _ui_scale
	var cbg := StyleBoxFlat.new()
	cbg.bg_color = Color(0, 0, 0, 0.88)
	cbg.corner_radius_top_left = 10
	cbg.corner_radius_top_right = 10
	cbg.corner_radius_bottom_left = 10
	cbg.corner_radius_bottom_right = 10
	cbg.border_color = Color(0.5, 0.7, 1.0, 0.6)
	cbg.set_border_width_all(2)
	_clan_panel.add_theme_stylebox_override("panel", cbg)
	_clan_panel.visible = false
	layer.add_child(_clan_panel)
	_build_clan_panel_content()

## Crée une entrée de menu supérieur (bouton pleine largeur, style CoC).
func _make_top_menu_item(parent: Container, text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46 * _ui_scale)
	b.add_theme_font_size_override("font_size", int(16 * _ui_scale))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_stylize_coc_button(b)
	b.pressed.connect(handler)
	parent.add_child(b)
	return b

## Ouvre/ferme le menu hub « ☰ ».
func _toggle_top_menu() -> void:
	if _top_menu_panel == null:
		return
	_top_menu_panel.visible = not _top_menu_panel.visible
	# Ouvrir un sous-panel ferme l'autre.
	if _top_menu_panel.visible:
		_clan_panel.visible = false

## Ouvre/ferme le panneau des sous-infos (Population / Royaume / Clan).
func _toggle_extra_info() -> void:
	if _hud_extra_panel == null:
		return
	_hud_extra_panel.visible = not _hud_extra_panel.visible
	_hud_plus_btn.modulate = Color(1, 0.8, 0.4) if _hud_extra_panel.visible else Color.WHITE

## Affiche une popup simple de sélection de langue (CoC).
func _toggle_language_popup() -> void:
	_toggle_top_menu()
	_notify("Sélecteur de langue (via LobbyMenu) — bientôt en jeu")

func _toggle_clan_panel() -> void:
	if _clan_panel == null:
		return
	_clan_panel.visible = not _clan_panel.visible
	if _clan_panel.visible:
		_refresh_clan_panel()

## Contenu du panneau Clan : selon mon statut (aucun clan / membre), montre les
## bons champs et boutons. Conçu mobile-first (champs larges + gros boutons).
func _build_clan_panel_content() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(m, 12)
	_clan_panel.add_child(margin)
	margin.add_child(vb)

	var title := Label.new()
	title.text = "Clans du royaume"
	title.add_theme_font_size_override("font_size", int(18 * _ui_scale))
	vb.add_child(title)

	# Champs création (toujours montrés ; on désactive si déjà dans un clan).
	_clan_name_input = LineEdit.new()
	_clan_name_input.placeholder_text = "Nom du clan"
	_clan_name_input.custom_minimum_size = Vector2(0, 34 * _ui_scale)
	vb.add_child(_clan_name_input)
	_clan_tag_input = LineEdit.new()
	_clan_tag_input.placeholder_text = "Tag (max 6)"
	_clan_tag_input.max_length = 6
	_clan_tag_input.custom_minimum_size = Vector2(0, 34 * _ui_scale)
	vb.add_child(_clan_tag_input)

	var create_btn := Button.new()
	create_btn.text = "Créer un clan"
	create_btn.custom_minimum_size = Vector2(0, 40 * _ui_scale)
	create_btn.pressed.connect(_on_create_clan_pressed)
	vb.add_child(create_btn)

	# Rejoindre un clan par tag.
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 6)
	var join_input := LineEdit.new()
	join_input.placeholder_text = "Tag à rejoindre"
	join_input.max_length = 6
	join_input.custom_minimum_size = Vector2(0, 34 * _ui_scale)
	join_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(join_input)
	_clan_join_input = join_input
	var join_btn := Button.new()
	join_btn.text = "Rejoindre"
	join_btn.pressed.connect(_on_join_clan_pressed)
	join_row.add_child(join_btn)
	vb.add_child(join_row)

	var leave_btn := Button.new()
	leave_btn.text = "Quitter mon clan"
	leave_btn.custom_minimum_size = Vector2(0, 38 * _ui_scale)
	leave_btn.pressed.connect(_on_leave_clan_pressed)
	vb.add_child(leave_btn)

	# Liste des clans existants.
	_clan_list_label = Label.new()
	_clan_list_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_clan_list_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	_clan_list_label.add_theme_font_size_override("font_size", int(14 * _ui_scale))
	vb.add_child(_clan_list_label)
	# NB : my_clan_changed est déjà connecté dans _setup_hud (pas de double lien).
	if get_node_or_null("/root/Clans") != null:
		Clans.clans_received.connect(_on_clans_received)

func _on_create_clan_pressed() -> void:
	var clan_label := _clan_name_input.text.strip_edges()
	var tag := _clan_tag_input.text.strip_edges()
	if clan_label.is_empty() or tag.is_empty():
		_notify("Choisissez un nom et un tag.")
		return
	Clans.create_clan(clan_label, tag, 0)

func _on_join_clan_pressed() -> void:
	var tag := _clan_join_input.text.strip_edges()
	if tag.is_empty():
		_notify("Entrez un tag de clan à rejoindre.")
		return
	Clans.join_clan(tag)

func _on_leave_clan_pressed() -> void:
	Clans.leave_clan()

func _on_clans_received() -> void:
	_refresh_clan_panel()

func _refresh_clan_panel() -> void:
	if _clan_panel == null or _clan_list_label == null:
		return
	# Met à jour la liste des clans visibles.
	var lines: Array = []
	for t in Clans.local_clans.keys():
		var c: Dictionary = Clans.local_clans[t]
		lines.append("• %s [%s] — %d membre(s) — Grandeur %d" % [
			str(c.get("name", t)), t, int(c.get("members", {}).size()), int(c.get("grandeur", 0))
		])
	if lines.is_empty():
		_clan_list_label.text = "Aucun clan pour l'instant.\nSoyez le premier à créer un clan !"
	else:
		_clan_list_label.text = "\n".join(lines)

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
		[OrderMode.MOVE, "Déplacer"],
		[OrderMode.GATHER, "Récolter"],
		[OrderMode.ATTACK, "Attaquer"],
	]
	for a in actions:
		var btn := Button.new()
		btn.text = a[1]
		btn.custom_minimum_size = Vector2(110 * _ui_scale, 46 * _ui_scale)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", int(16 * _ui_scale))
		_stylize_coc_button(btn)
		btn.pressed.connect(_arm_order.bind(a[0]))
		hb.add_child(btn)
		_order_btns[a[0]] = btn
	
	# Bouton Stop / Désélectionner (toujours utile)
	var stop_btn := Button.new()
	stop_btn.text = "Stop"
	stop_btn.custom_minimum_size = Vector2(90 * _ui_scale, 46 * _ui_scale)
	stop_btn.add_theme_font_size_override("font_size", int(16 * _ui_scale))
	_stylize_coc_button(stop_btn)
	stop_btn.pressed.connect(_cancel_selection)
	hb.add_child(stop_btn)

	# Inspecteur d'unité : infos sur l'unité sélectionnée (mobile + PC), affiché
	# juste au-dessus de la barre d'ordre quand il y a exactement une sélection.
	_inspect_label = Label.new()
	_inspect_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_inspect_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_inspect_label.offset_top = -196.0 * _ui_scale
	_inspect_label.offset_bottom = -172.0 * _ui_scale
	_inspect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inspect_label.add_theme_font_size_override("font_size", int(15 * _ui_scale))
	_inspect_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	_inspect_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_inspect_label.add_theme_constant_override("outline_size", 6)
	_inspect_label.visible = false
	layer.add_child(_inspect_label)

	# ===== Panneau des états du personnage sélectionné (côté droit, CoC).
	_unit_panel = PanelContainer.new()
	_unit_panel.name = "UnitStatePanel"
	_unit_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_unit_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_unit_panel.offset_left = -250.0 * _ui_scale
	_unit_panel.offset_top = 190.0 * _ui_scale
	_unit_panel.offset_right = -12.0 * _ui_scale
	_unit_panel.offset_bottom = 340.0 * _ui_scale
	_unit_panel.visible = false
	var ub := StyleBoxFlat.new()
	ub.bg_color = Color(0.1, 0.12, 0.16, 0.85)
	ub.corner_radius_top_left = 12
	ub.corner_radius_top_right = 12
	ub.corner_radius_bottom_left = 12
	ub.corner_radius_bottom_right = 12
	ub.border_color = Color(0.6, 0.7, 0.9, 0.4)
	ub.set_border_width_all(2)
	ub.content_margin_left = 14
	ub.content_margin_right = 14
	ub.content_margin_top = 12
	ub.content_margin_bottom = 12
	_unit_panel.add_theme_stylebox_override("panel", ub)
	var uv := VBoxContainer.new()
	uv.add_theme_constant_override("separation", int(8 * _ui_scale))
	_unit_panel.add_child(uv)
	_unit_role_lbl = Label.new()
	_unit_role_lbl.add_theme_font_size_override("font_size", int(18 * _ui_scale))
	_unit_role_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	_unit_role_lbl.add_theme_constant_override("outline_size", 6)
	_unit_role_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	uv.add_child(_unit_role_lbl)
	_unit_hp_lbl = Label.new()
	_unit_hp_lbl.add_theme_font_size_override("font_size", int(16 * _ui_scale))
	_unit_hp_lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	uv.add_child(_unit_hp_lbl)
	_unit_state_lbl = Label.new()
	_unit_state_lbl.add_theme_font_size_override("font_size", int(16 * _ui_scale))
	_unit_state_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	uv.add_child(_unit_state_lbl)
	layer.add_child(_unit_panel)

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
	if _unit_panel != null and not has_units:
		_unit_panel.visible = false

# ============================================================ UI : CONSTRUCTION

func _setup_build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 41
	add_child(layer)
	# ===== Bouton « Construire » en bas à gauche : se déplie en grille (CoC).
	_build_main_btn = Button.new()
	_build_main_btn.name = "BuildButton"
	_build_main_btn.text = "Construire"
	_build_main_btn.icon = _icon("hammer")
	_build_main_btn.expand_icon = true
	_build_main_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_build_main_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_build_main_btn.grow_horizontal = Control.GROW_DIRECTION_END
	_build_main_btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_build_main_btn.offset_left = 12.0 * _ui_scale
	_build_main_btn.offset_top = -90.0 * _ui_scale
	_build_main_btn.offset_right = (12.0 + 150.0) * _ui_scale
	_build_main_btn.offset_bottom = -30.0 * _ui_scale
	_build_main_btn.add_theme_font_size_override("font_size", int(18 * _ui_scale))
	_stylize_coc_button(_build_main_btn)
	_build_main_btn.pressed.connect(_toggle_build_menu)
	layer.add_child(_build_main_btn)
	# ===== Menu dépliable : grille de tous les bâtiments (au-dessus du bouton).
	_build_menu = PanelContainer.new()
	_build_menu.name = "BuildMenu"
	_build_menu.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_build_menu.grow_horizontal = Control.GROW_DIRECTION_END
	_build_menu.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_build_menu.offset_left = 12.0 * _ui_scale
	_build_menu.offset_top = -330.0 * _ui_scale
	_build_menu.offset_bottom = -100.0 * _ui_scale
	_build_menu.offset_right = (12.0 + 400.0) * _ui_scale
	_build_menu.visible = false
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color(0.1, 0.12, 0.16, 0.95)
	fb.corner_radius_top_left = 14
	fb.corner_radius_top_right = 14
	fb.corner_radius_bottom_left = 14
	fb.corner_radius_bottom_right = 14
	fb.border_color = Color(0.6, 0.7, 0.9, 0.45)
	fb.set_border_width_all(2)
	fb.content_margin_left = 12
	fb.content_margin_right = 12
	fb.content_margin_top = 10
	fb.content_margin_bottom = 10
	_build_menu.add_theme_stylebox_override("panel", fb)
	layer.add_child(_build_menu)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	_build_menu.add_child(margin)
	_build_menu_grid = GridContainer.new()
	_build_menu_grid.columns = 3
	_build_menu_grid.add_theme_constant_override("h_separation", 6)
	_build_menu_grid.add_theme_constant_override("v_separation", 6)
	margin.add_child(_build_menu_grid)
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
		btn.custom_minimum_size = Vector2(118 * _ui_scale, 56 * _ui_scale)
		btn.add_theme_font_size_override("font_size", int(14 * _ui_scale))
		_stylize_coc_button(btn)
		btn.pressed.connect(_on_build_button_pressed.bind(t))
		_build_menu_grid.add_child(btn)
		_build_buttons[t] = btn
	_refresh_build_buttons()

## Ouvre/ferme le menu dépliable de construction (CoC).
func _toggle_build_menu() -> void:
	if _build_menu == null:
		return
	_build_menu.visible = not _build_menu.visible
	if not _build_menu.visible:
		# On referme : on garde le mode placement actif s'il y en a un.
		pass

## Applique le style « bouton CoC » (arrondi, bordure claire, fond foncé).
func _stylize_coc_button(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.16, 0.12, 0.09, 0.94)      # bois sombre (comme les cartouches)
		sb.border_color = Color(0.85, 0.66, 0.3, 0.95)   # liseré doré CoC
		sb.set_border_width_all(2)
		sb.corner_radius_top_left = 7
		sb.corner_radius_top_right = 7
		sb.corner_radius_bottom_left = 7
		sb.corner_radius_bottom_right = 7
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		if state == "hover" or state == "pressed":
			sb.bg_color = Color(0.28, 0.2, 0.13, 1.0)
			sb.border_color = Color(1.0, 0.8, 0.4, 1.0)
		if state == "pressed":
			sb.bg_color = Color(0.36, 0.26, 0.16, 1.0)
			sb.border_color = Color(1.0, 0.9, 0.5, 1.0)
			sb.border_width_bottom = 1
			sb.content_margin_top = 5
		b.add_theme_stylebox_override(state, sb)
	# Police CoC grasse, texte doré clair pour la lisibilité sur bois sombre.
	b.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.9, 0.6))
	b.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.05, 0.95))
	b.add_theme_constant_override("outline_size", 8)

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
	# Un type choisi : on referme le menu dépliable (CoC).
	if _build_menu != null:
		_build_menu.visible = false

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
	# Style CoC : panneau sombre arrondi à droite.
	var bbg := StyleBoxFlat.new()
	bbg.bg_color = Color(0.1, 0.12, 0.16, 0.9)
	bbg.corner_radius_top_left = 10
	bbg.corner_radius_top_right = 10
	bbg.corner_radius_bottom_left = 10
	bbg.corner_radius_bottom_right = 10
	bbg.border_color = Color(0.6, 0.7, 0.9, 0.35)
	bbg.set_border_width_all(2)
	bbg.content_margin_left = 10
	bbg.content_margin_right = 10
	bbg.content_margin_top = 8
	bbg.content_margin_bottom = 8
	_building_panel.add_theme_stylebox_override("panel", bbg)
	layer.add_child(_building_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	_building_panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
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
	_stylize_coc_button(_upgrade_button)
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	vb.add_child(_upgrade_button)
	_recruit_button = Button.new()
	_recruit_button.text = "Recruter un paysan"
	_recruit_button.custom_minimum_size = Vector2(0, 40 * _ui_scale)
	_recruit_button.add_theme_font_size_override("font_size", int(14 * _ui_scale))
	_stylize_coc_button(_recruit_button)
	_recruit_button.pressed.connect(_on_recruit_pressed)
	vb.add_child(_recruit_button)
	_train_button = Button.new()
	_train_button.text = "Entraîner un soldat"
	_train_button.custom_minimum_size = Vector2(0, 40 * _ui_scale)
	_train_button.add_theme_font_size_override("font_size", int(14 * _ui_scale))
	_stylize_coc_button(_train_button)
	_train_button.pressed.connect(_on_train_pressed)
	vb.add_child(_train_button)
	_move_button = Button.new()
	_move_button.text = "Déplacer"
	_move_button.custom_minimum_size = Vector2(0, 40 * _ui_scale)
	_move_button.add_theme_font_size_override("font_size", int(14 * _ui_scale))
	_stylize_coc_button(_move_button)
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
