class_name VillagerModel
extends Node3D

## Assemble le modèle du paysan : charge le mesh de base (Character_output) et
## réunit les animations (idle / walk / run) issues des .glb Meshy séparés dans
## l'AnimationPlayer du modèle. À attacher à la racine du modèle instancié.

const MODEL_BASE := "res://assets/models/characters/Paysan Chibi+Animations/Meshy_AI_chibi_character_gamer_biped_Character_output.glb"

## Teinte appliquée au corps du modèle (pour distinguer les unités partageant
## le même modèle, ex. soldat). Blanc = aucune teinte.
@export var tint: Color = Color.WHITE

# (fichier d'animation, nom à donner dans le jeu)
const ANIMS: Array[Array] = [
	["res://assets/models/characters/Paysan Chibi+Animations/Meshy_AI_chibi_character_gamer_biped_Animation_Idle_3_withSkin.glb", "Idle"],
	["res://assets/models/characters/Paysan Chibi+Animations/Meshy_AI_chibi_character_gamer_biped_Animation_Walking_withSkin.glb", "Walk"],
	["res://assets/models/characters/Paysan Chibi+Animations/Meshy_AI_chibi_character_gamer_biped_Animation_Running_withSkin.glb", "Run"],
]

var _model: Node3D = null
var _anim_player: AnimationPlayer = null

func _ready() -> void:
	_build()

## Crée le sous-arbre du modèle et assemble les animations.
func _build() -> void:
	var base: PackedScene = load(MODEL_BASE)
	if base == null:
		push_warning("VillagerModel : modèle de base introuvable.")
		return
	_model = base.instantiate()
	_model.name = "Model"
	# AJUSTEMENT FINAL : 0.75m.
	# On baisse de 5cm par rapport au calcul théorique pour s'assurer
	# que les pieds s'enfoncent un peu dans le sol (l'herbe).
	# Cela garantit que l'ombre est parfaitement rattachée aux pieds.
	_model.position.y = 0.75
	add_child(_model)
	_apply_tint()
	_anim_player = _model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if _anim_player == null:
		push_warning("VillagerModel : pas d'AnimationPlayer dans le modèle de base.")
		return
	# Réunit les animations des autres .glb.
	for entry in ANIMS:
		_add_animation(entry[0], entry[1] as String)

## Charge un .glb d'animation, en extrait l'animation et l'ajoute à l'AnimationPlayer
## du modèle de base sous le nom cible.
func _add_animation(src_path: String, target_name: String) -> void:
	var ps: PackedScene = load(src_path)
	if ps == null:
		return
	var tmp: Node = ps.instantiate()
	var ap := tmp.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		tmp.free()
		return
	var list := ap.get_animation_list()
	if list.is_empty():
		tmp.free()
		return
	# Prend la première animation du fichier et la duplique sous le nom cible.
	var src_anim: Animation = ap.get_animation(list[0])
	var copy: Animation = src_anim.duplicate()
	copy.resource_name = target_name
	# Ajoute dans la bibliothèque d'animation par défaut ("") de l'AnimationPlayer.
	var lib := _anim_player.get_animation_library("")
	if lib == null:
		lib = AnimationLibrary.new()
		_anim_player.add_animation_library("", lib)
	# Remplace si une animation du même nom existe déjà.
	if lib.has_animation(target_name):
		lib.remove_animation(target_name)
	lib.add_animation(target_name, copy)
	tmp.free()

## Applique la teinte (si différente de blanc) sur tous les matériaux du mesh.
func _apply_tint() -> void:
	if tint.is_equal_approx(Color.WHITE):
		return
	var char1 := _model.find_child("char1", true, false) as MeshInstance3D
	if char1 == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	char1.material_override = mat

## Expose l'AnimationPlayer pour le script de gameplay (Villager.gd).
func get_model_anim_player() -> AnimationPlayer:
	return _anim_player
