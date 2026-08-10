extends Camera3D

## CameraController — caméra orthographique iso au-dessus du village.
##   - Glisser avec le bouton du milieu (molette pressée) : déplacer la vue
##     (la carte suit le curseur 1:1 — déplacement simple et stable)
##   - Molette : zoomer (zoom orthographique, sans déformation)
##   - Q / E : pivoter la caméra autour du point focal
## La projection est orthographique : pas de déformation en perspective.

@export var zoom_speed: float = 6.0        # variation de taille (cran de molette)
@export var min_size: float = 8.0
@export var max_size: float = 220.0        # dézoom jusqu'à voir la carte entière (400 m)
@export var pitch_deg: float = 50.0        # inclinaison iso (plus bas = vue plus horizontale)

## Bornes du monde (½ côte de la carte) pour ne pas paner hors de la map.
@export var world_half: float = 200.0

var _pivot := Vector3(2.0, 0.0, 0.0)       # point au sol que la caméra regarde
var _size: float = 22.0                    # hauteur de la vue orthographique
# Rotation Y initiale à 45° : vraie vue isométrique (axes symétriques en biais).
var _yaw: float = deg_to_rad(45.0)
var _dragging := false
var _last_mouse := Vector2.ZERO

func _ready() -> void:
	# Projection orthographique : pas de déformation en perspective.
	projection = Camera3D.PROJECTION_ORTHOGONAL
	_apply()

## Déplace le point focal de la caméra vers la base du joueur (multijoueur).
func set_pivot(point: Vector3) -> void:
	_pivot = _clamp_pivot(Vector3(point.x, 0.0, point.z))

## Clampe le point focal dans les bornes du monde (reste la carte en vue).
func _clamp_pivot(p: Vector3) -> Vector3:
	return Vector3(
		clampf(p.x, -world_half, world_half),
		0.0,
		clampf(p.z, -world_half, world_half)
	)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_size = clampf(_size - zoom_speed, min_size, max_size)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_size = clampf(_size + zoom_speed, min_size, max_size)
			MOUSE_BUTTON_MIDDLE:
				_dragging = event.pressed
				_last_mouse = _mouse_pos()
	elif event is InputEventMouseMotion and _dragging:
		_pan(event.position - _last_mouse)
		_last_mouse = event.position
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_Q:
			_yaw -= deg_to_rad(45.0)
		elif event.keycode == KEY_E:
			_yaw += deg_to_rad(45.0)
	# --- TACTILE : pour jouer sur écran tactile ---
	# 1 doigt qui glisse = déplacer la carte (même logique que la molette pressée).
	elif event is InputEventScreenTouch:
		_dragging = event.pressed
		_last_mouse = event.position
	elif event is InputEventScreenDrag and _dragging:
		_pan(event.position - _last_mouse)
		_last_mouse = event.position
	# Pincement / geste de zoom tactile (envoyé par l'OS sur mobile).
	elif event is InputEventMagnifyGesture:
		_size = clampf(_size / (event.factor if event.factor > 0.0 else 1.0), min_size, max_size)

func _process(_delta: float) -> void:
	_apply()

func _apply() -> void:
	var pitch := deg_to_rad(pitch_deg)
	# Distance caméra fixe (n'importe pas en ortho, juste assez grande pour éviter
	# le clipping) ; le zoom se fait via `size`.
	var offset := Vector3(
		cos(pitch) * sin(_yaw),
		sin(pitch),
		cos(pitch) * cos(_yaw)
	) * 45.0
	global_transform = Transform3D(Basis.IDENTITY, _pivot + offset)
	look_at(_pivot, Vector3.UP)
	size = _size

## Déplacement "grab the map" : la carte suit le curseur 1:1 (orthographique).
func _pan(screen_delta: Vector2) -> void:
	var vp_h := float(get_viewport().get_visible_rect().size.y)
	if vp_h <= 0.0:
		return
	
	# Ratio pixels -> mètres monde.
	var world_per_pixel := _size / vp_h
	
	# Les axes de mouvement à l'écran :
	# Right est toujours horizontal (parfait).
	# Up est incliné vers le haut (pitch), on veut sa projection sur le sol.
	var right: Vector3 = global_transform.basis.x
	var forward: Vector3 = global_transform.basis.z # Dans Godot, Z est le forward
	
	# On projette le forward sur le plan XZ et on le normalise.
	var forward_ground := Vector3(forward.x, 0.0, forward.z).normalized()
	
	# Le mouvement horizontal (souris X -> Right du monde)
	var move_x := right * (-screen_delta.x * world_per_pixel)
	
	# Le mouvement vertical (souris Y -> Forward/Backward du monde)
	# On inverse le signe (-screen_delta.y) pour que tirer la souris vers le bas
	# fasse descendre la carte (mouvement "Grab").
	var pitch_rad := deg_to_rad(pitch_deg)
	var compensate := 1.0 / sin(pitch_rad)
	var move_y := forward_ground * (-screen_delta.y * world_per_pixel * compensate)
	
	_pivot = _clamp_pivot(_pivot + move_x + move_y)

func _mouse_pos() -> Vector2:
	return get_viewport().get_mouse_position()