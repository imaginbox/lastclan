class_name Minimap
extends Control
## Minimap RTS : carte en coin d'écran montrant la base, les unités du joueur,
## les ressources, la faune/ennemis et les bâtiments ennemis. Cliquer déplace la
## caméra. Les groupes sont lus en direct depuis l'arbre de scène.

## Demi-largeur du monde (doit matcher GRID_HALF de main.gd).
var world_half: float = 190.0
## Référence au nœud de jeu (root "Main") pour lire la base et piloter la caméra.
var game: Node = null

var col_bg: Color = Color(0.04, 0.06, 0.10, 0.82)
var col_border: Color = Color(0.6, 0.7, 0.9, 0.5)
var col_base: Color = Color(0.45, 0.75, 1.0)
var col_hero: Color = Color(1.0, 0.9, 0.3)
var col_player: Color = Color(0.4, 1.0, 0.4)
var col_enemy: Color = Color(1.0, 0.35, 0.3)

var _refresh := 0.0
var _panel_sb: StyleBoxFlat = null

## Configure la minimap : demi-largeur du monde + référence au jeu.
func setup(world_half_val: float, game_node: Node) -> void:
	world_half = world_half_val
	game = game_node
	# Purement visuelle : le clic est géré par main.gd (_unhandled_input) pour
	# éviter tout conflit de consommation d'événements GUI.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_sb = StyleBoxFlat.new()
	_panel_sb.bg_color = col_bg
	_panel_sb.set_corner_radius_all(8)
	_panel_sb.set_border_width_all(2)
	_panel_sb.border_color = col_border
	_panel_sb.content_margin_left = 4
	_panel_sb.content_margin_top = 4
	_panel_sb.content_margin_right = 4
	_panel_sb.content_margin_bottom = 4

## Clic sur la minimap : déplace la caméra vers le point monde correspondant.
func focus_at(screen_pos: Vector2) -> void:
	if game != null and game.has_method("_focus_camera"):
		game._focus_camera(_to_world(screen_pos - global_position))

func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.15
		queue_redraw()

## Convertit une position monde (x, z) en coordonnées locales du contrôle.
func _to_local(world: Vector3) -> Vector2:
	var pad := 4.0
	var inner := size - Vector2(pad * 2.0, pad * 2.0)
	var nx := clampf((world.x + world_half) / (world_half * 2.0), 0.0, 1.0)
	var nz := clampf((world.z + world_half) / (world_half * 2.0), 0.0, 1.0)
	return Vector2(pad + nx * inner.x, pad + nz * inner.y)

## Convertit une position locale du contrôle en position monde (au sol).
func _to_world(local: Vector2) -> Vector3:
	var pad := 4.0
	var inner := size - Vector2(pad * 2.0, pad * 2.0)
	var nx := (local.x - pad) / maxf(inner.x, 1.0)
	var nz := (local.y - pad) / maxf(inner.y, 1.0)
	return Vector3(
		clampf(nx * world_half * 2.0 - world_half, -world_half, world_half),
		0.0,
		clampf(nz * world_half * 2.0 - world_half, -world_half, world_half)
	)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if game != null and game.has_method("_focus_camera"):
			game._focus_camera(_to_world(event.position))

func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	if _panel_sb != null:
		draw_style_box(_panel_sb, Rect2(Vector2.ZERO, size))
	else:
		draw_rect(Rect2(Vector2.ZERO, size), col_bg)
	var tree := get_tree()
	if tree == null:
		return

	# Base du joueur.
	var base := Vector3.ZERO
	if game != null and "get_base_origin" in game:
		base = game.get_base_origin()
	draw_rect(Rect2(_to_local(base) - Vector2(2.5, 2.5), Vector2(5, 5)), col_base)

	# Unités du joueur (le héros en jaune brillant).
	for u in tree.get_nodes_in_group("player"):
		var p: Vector3 = u.global_position
		if u.is_in_group("hero"):
			draw_rect(Rect2(_to_local(p) - Vector2(2, 2), Vector2(4, 4)), col_hero)
		else:
			draw_rect(Rect2(_to_local(p) - Vector2(1.5, 1.5), Vector2(3, 3)), col_player)

	# Ennemis (faune, poste ennemi, gardes).
	for e in tree.get_nodes_in_group("enemy"):
		var p2: Vector3 = e.global_position
		draw_rect(Rect2(_to_local(p2) - Vector2(1.5, 1.5), Vector2(3, 3)), col_enemy)

	# Ressources.
	for r in tree.get_nodes_in_group("resource"):
		var p3: Vector3 = r.global_position
		draw_rect(Rect2(_to_local(p3) - Vector2(1, 1), Vector2(2, 2)), Color(1.0, 0.85, 0.3))
