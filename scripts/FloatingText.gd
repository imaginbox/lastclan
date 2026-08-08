class_name FloatingText
extends Label

## FloatingText — chiffre de récolte cartoonesque.
## Créé à la volée lorsqu'un paysan récolte : le nombre apparaît sur la source
## (position monde projetée à l'écran), grossit en un petit "pop", puis monte
## doucement vers le haut et s'estompe avant de se détruire. Style arcade/RTS.

const LIFE: float = 1.15          # durée de vie totale (s)
const RISE_SPEED: float = 1.9     # montée verticale (u.m./s)
const POP_IN_TIME: float = 0.16   # durée du "pop" d'apparition
const SETTLE_TIME: float = 0.22   # durée de retour à l'échelle normale
const FADE_START: float = 0.62    # fraction de vie à partir de laquelle on fond

var _world_pos: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _camera: Camera3D = null

func _ready() -> void:
	# Contrôle UI : ne gêne pas les clics sur le monde.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Style cartoon : police épaisse, contour sombre, centré.
	var ls := LabelSettings.new()
	ls.font_size = 34
	ls.font_color = Color.WHITE
	ls.outline_size = 8
	ls.outline_color = Color(0.0, 0.0, 0.0, 1.0)
	label_settings = ls
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	z_index = 100

## Initialise et affiche le nombre. `world_pos` = position 3D sur la source,
## `value` = "+1", `color` = couleur selon le type de ressource.
func start(world_pos: Vector3, value: String, color: Color) -> void:
	_world_pos = world_pos
	set_text(value)
	label_settings.font_color = color
	_camera = get_viewport().get_camera_3d()
	_age = 0.0
	_refresh_position()

func _process(delta: float) -> void:
	_age += delta
	_camera = get_viewport().get_camera_3d()
	if _camera == null:
		return
	# Le nombre monte tout en suivant la position monde de la source.
	_world_pos.y += RISE_SPEED * delta
	_refresh_position()
	# Animation d'échelle : pop rapide puis retour à la normale.
	var t: float = _age / LIFE
	var s: float
	if t < POP_IN_TIME:
		s = lerpf(0.5, 1.35, t / POP_IN_TIME)
	elif t < POP_IN_TIME + SETTLE_TIME:
		s = lerpf(1.35, 1.0, (t - POP_IN_TIME) / SETTLE_TIME)
	else:
		s = 1.0
	scale = Vector2(s, s)
	pivot_offset = size / 2.0
	# Fondu en fin de vie.
	var alpha: float = 1.0
	if t > FADE_START:
		alpha = 1.0 - (t - FADE_START) / (1.0 - FADE_START)
	label_settings.font_color.a = alpha
	label_settings.outline_color.a = alpha
	if t >= 1.0:
		queue_free()

## Recentre le label sur la projection écran de la position monde.
func _refresh_position() -> void:
	if _camera == null:
		return
	var scr: Vector2 = _camera.unproject_position(_world_pos)
	position = scr - size / 2.0