class_name FogOfWar
extends Node3D

## FogOfWar — brouillard de guerre.
## Un plan de brouillard posé au-dessus du monde cache tout ce qui n'est pas
## encore exploré. Les unités portant le groupe "fog_vision" (avec une propriété
## vision_radius) peignent un cercle de révélation autour d'elles à chaque tick,
## dispersant progressivement le nuage au fil de l'exploration.

const WORLD_HALF := 200.0     # taille du monde (mètres) depuis le centre
const MAP_SIZE := 512        # résolution de la carte de révélation
const FOG_HEIGHT := 4.0      # hauteur du plan de brouillard (au-dessus des bâtiments)
const UPDATE_INTERVAL := 0.1 # secondes entre deux mises à jour de la carte

var _image: Image
var _texture: ImageTexture
var _timer := 0.0

func _ready() -> void:
	global_position = Vector3(0.0, FOG_HEIGHT, 0.0)
	_image = Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_R8)
	_texture = ImageTexture.create_from_image(_image)
	_build_mesh()
	_texture.update(_image)

## API publique : révèle une zone circulaire autour d'un point du monde.
func reveal_area(center: Vector3, radius: float) -> void:
	_paint_circle(Vector3(center.x, 0.0, center.z), radius)
	_texture.update(_image)

func _process(delta: float) -> void:
	_timer += delta
	if _timer < UPDATE_INTERVAL:
		return
	_timer = 0.0
	_update_reveal()
	_texture.update(_image)

## Construit le plan de brouillard avec le shader.
func _build_mesh() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "FogMesh"
	var plane := PlaneMesh.new()
	plane.size = Vector2(WORLD_HALF * 2.0, WORLD_HALF * 2.0)
	mi.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/fog_of_war.gdshader")
	mat.set_shader_parameter("reveal_map", _texture)
	mat.set_shader_parameter("world_half", WORLD_HALF)
	mi.material_override = mat
	add_child(mi)
	# Pose le plan à plat (face vers le haut).
	mi.rotate_x(-PI / 2.0)

## Met à jour la carte de révélation depuis les unités exploratrices.
func _update_reveal() -> void:
	for unit in get_tree().get_nodes_in_group("fog_vision"):
		if unit == null or not is_instance_valid(unit):
			continue
		var radius: float = float(unit.get("vision_radius")) if unit.get("vision_radius") != null else 5.0
		_paint_circle(unit.global_position, radius)

## Convertit une coordonnée mondiale X ou Z en index de pixel.
func _w_to_px(v: float) -> int:
	var t := clampf((v + WORLD_HALF) / (WORLD_HALF * 2.0), 0.0, 1.0)
	return int(t * float(MAP_SIZE - 1))

## Peint un cercle de révélation (bord doux) autour d'une position mondiale.
func _paint_circle(center: Vector3, radius: float) -> void:
	if not is_instance_valid(_image):
		return
	var cx := _w_to_px(center.x)
	var cy := _w_to_px(center.z)
	var r_px := maxi(1, int(radius / (WORLD_HALF * 2.0) * float(MAP_SIZE)))
	for dy in range(-r_px, r_px + 1):
		var y := cy + dy
		if y < 0 or y >= MAP_SIZE:
			continue
		for dx in range(-r_px, r_px + 1):
			var x := cx + dx
			if x < 0 or x >= MAP_SIZE:
				continue
			var dist := sqrt(float(dx * dx + dy * dy))
			if dist > float(r_px):
				continue
			# Intérieur entièrement révélé + anneau extérieur en dégradé doux :
			# la zone visible est nette et le bord s'estompe progressivement.
			var soft_inner := float(r_px) * 0.35
			var falloff := 1.0 if dist <= soft_inner else 1.0 - smoothstep(soft_inner, float(r_px), dist)
			var cur := _image.get_pixel(x, y).r
			if falloff > cur:
				_image.set_pixel(x, y, Color(falloff, 0.0, 0.0, 0.0))