extends Node

## Test d'intégration des images par niveau des bâtiments (Caserne, Ferme,
## Maison, Mine) : comme la HDV, ils utilisent un Sprite3D billboard texturé
## selon le niveau au lieu d'un cube. La tour et la carrière (sans images)
## restent en cube.

func _make_building(bt: int, level: int) -> Building:
	var b := Building.new()
	b.type = bt
	b.level = level
	b.call("_build_visual")
	return b

## Types qui doivent utiliser une image (Sprite3D) : 4 + HDV.
const SPRITE_TYPES := [Building.Type.TOWN_HALL, Building.Type.BARRACKS, Building.Type.HOUSE, Building.Type.FERME, Building.Type.MINE_OR]
## Types sans image (cube).
const CUBE_TYPES := [Building.Type.TOWER, Building.Type.CARRIERE]

func test_sprite_types_use_sprite_not_cube() -> void:
	for bt in SPRITE_TYPES:
		var b: Building = _make_building(bt, 1)
		var sprite := b.get_node_or_null("Sprite") as Sprite3D
		if sprite == null:
			push_error("CHECK FAILED: type %d n'a pas de noeud Sprite" % bt)
		elif sprite.texture == null:
			push_error("CHECK FAILED: type %d Sprite sans texture" % bt)
		if b.get_node_or_null("Mesh") != null:
			push_error("CHECK FAILED: type %d devrait être un Sprite, pas un Mesh" % bt)
		b.free()

func test_cube_types_use_mesh() -> void:
	for bt in CUBE_TYPES:
		var b: Building = _make_building(bt, 1)
		if b.get_node_or_null("Sprite") != null:
			push_error("CHECK FAILED: type %d (sans image) ne devrait pas avoir de Sprite" % bt)
		if b.get_node_or_null("Mesh") == null:
			push_error("CHECK FAILED: type %d devrait avoir un Mesh cube" % bt)
		b.free()

func test_building_texture_follows_level() -> void:
	var b: Building = _make_building(Building.Type.BARRACKS, 2)
	var tex: Texture2D = b.call("_building_texture")
	if tex == null or not tex.resource_path.ends_with("Caserne-2.png"):
		push_error("CHECK FAILED: _building_texture niveau 2 Caserne attendu Caserne-2.png, obtenu ", tex.resource_path if tex else "<null>")
	b.level = 5
	tex = b.call("_building_texture")
	if tex == null or not tex.resource_path.ends_with("Caserne-5.png"):
		push_error("CHECK FAILED: _building_texture niveau 5 Caserne attendu Caserne-5.png, obtenu ", tex.resource_path if tex else "<null>")
	b.free()

func test_new_buildings_max_level_six() -> void:
	for bt in [Building.Type.BARRACKS, Building.Type.HOUSE, Building.Type.FERME, Building.Type.MINE_OR]:
		var cfg: Dictionary = Building.TYPES[bt]
		if cfg.get("max_level", 0) != 6:
			push_error("CHECK FAILED: max_level type %d attendu 6, obtenu %s" % [bt, cfg.get("max_level", 0)])

func test_new_buildings_multi_level_sprite() -> void:
	for bt in SPRITE_TYPES:
		var b: Building = _make_building(bt, 6)
		var sprite := b.get_node_or_null("Sprite") as Sprite3D
		if sprite != null:
			var w: float = float(sprite.texture.get_size().x) * sprite.pixel_size
			var foot: int = b.footprint()
			var vs: float = Building.HDV_VISUAL_SCALE if bt == Building.Type.TOWN_HALL else Building.BUILDING_VISUAL_SCALE
			if absf(w - float(foot) * vs) > 0.01:
				push_error("CHECK FAILED: largeur sprite type %d (%.2f) != empreinte*scale %.2f" % [bt, w, foot * vs])
			var hh: float = float(sprite.texture.get_size().y) * sprite.pixel_size
			if sprite.position.y < hh * 0.5 or sprite.position.y > hh * 0.5 + 0.05:
				push_error("CHECK FAILED: pied sprite type %d mal ancré (y=%.2f, hh=%.2f)" % [bt, sprite.position.y, hh])
		b.free()
