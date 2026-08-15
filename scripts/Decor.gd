class_name Decor
extends Node3D
## Décoration 3D du monde : touffes d'herbe et arbres décoratifs (non récoltables)
## construits à partir des modèles fournis (.gltf). L'herbe est dispersée un peu
## partout pour le paysage, et de grands arbres servent de repères visuels.

## Touffes d'herbe disponibles (variantes profilées et doubles faces).
const GRASS_POOL: Array[PackedScene] = [
	preload("res://assets/models/Mes assets/Assets/grass1/Grass_1_A_Singlesided_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/grass1/Grass_1_B_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/grass1/Grass_1_B_Singlesided_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/grass1/Grass_1_C_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/grass1/Grass_1_C_Singlesided_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/grass1/Grass_1_D_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/grass1/Grass_1_D_Singlesided_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/grass2/Grass_2_A_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/grass2/Grass_2_A_Singlesided_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/grass2/Grass_2_B_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/grass2/Grass_2_B_Singlesided_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/grass2/Grass_2_C_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/grass2/Grass_2_C_Singlesided_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/grass2/Grass_2_D_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/grass2/Grass_2_D_Singlesided_Color1.gltf"),
]

## Arbres décoratifs (grandes variantes, non récoltables) pour le paysage.
const TREE_POOL: Array[PackedScene] = [
	preload("res://assets/models/Mes assets/Assets/tree1/Tree_1_A_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/tree1/Tree_1_B_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/tree1/Tree_1_C_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/tree2/Tree_2_A_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/tree2/Tree_2_B_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/tree2/Tree_2_C_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/tree2/Tree_2_D_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/tree2/Tree_2_E_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/tree3/Tree_5_A_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/tree3/Tree_5_B_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/tree3/Tree_5_C_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/tree3/Tree_5_D_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/tree3/Tree_5_E_Color1.gltf"),
	preload("res://assets/models/Mes assets/Assets/tree3/Tree_5_F_Color1.gltf"),
]

## Construit une touffe d'herbe (modèle aléatoire).
func build_grass() -> void:
	var ps := GRASS_POOL[randi() % GRASS_POOL.size()]
	_instantiate(ps)

## Construit un tapis d'herbe en IMAGE (Sprite3D billboard) avec des dimensions
## explicites largeur x hauteur (en mètres). Utilisé quand le panel admin fournit
## une image pour le décor herbe (personnages = 3D, décor = images).
func build_grass_image(image_path: String, width: float, height: float) -> void:
	var tex := load(image_path) as Texture2D
	if tex == null:
		# Repli silencieux sur la touffe 3D si l'image n'existe pas.
		build_grass()
		return
	var spr := Sprite3D.new()
	spr.name = "GrassImage"
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.centered = true
	spr.pixel_size = 1.0
	# pixel_size=1.0 → la texture occupe tex.width x tex.height unités monde.
	# On force exactement largeur x hauteur en mètres via l'échelle.
	spr.scale = Vector3(width / float(tex.get_width()), height / float(tex.get_height()), 1.0)
	spr.position.y = height * 0.5
	add_child(spr)

## Construit un arbre décoratif (modèle aléatoire), plus grand que l'herbe.
func build_tree() -> void:
	var ps := TREE_POOL[randi() % TREE_POOL.size()]
	_instantiate(ps)

## Texture forêt partagée (chargée une seule fois).
var _forest_tex: Texture2D = null

## Instancie un modèle fourni comme enfant de ce nœud décor,
## et applique la texture forêt (les .gltf référencent forest_texture.png par un
## chemin relatif qui ne se résout pas, on l'applique donc explicitement).
func _instantiate(ps: PackedScene) -> void:
	var inst: Node = ps.instantiate()
	add_child(inst)
	if _forest_tex == null:
		_forest_tex = load("res://assets/models/Mes assets/Textures/forest_texture.png") as Texture2D
	for mi in _collect_meshes(inst):
		var mesh := mi as MeshInstance3D
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _forest_tex
		mat.roughness = 0.8
		mat.metallic = 0.0
		mesh.material_override = mat

func _collect_meshes(node: Node, acc: Array = []) -> Array:
	if node is MeshInstance3D:
		acc.append(node)
	for c in node.get_children():
		acc = _collect_meshes(c, acc)
	return acc