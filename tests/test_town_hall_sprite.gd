extends Node

## Test de l'intégration visuelle de l'hôtel de ville (HDV) :
## remplacement du cube par un Sprite3D billboard texturé selon le niveau.

func _make_th(level: int) -> Building:
	var b := Building.new()
	b.type = Building.Type.TOWN_HALL
	b.level = level
	# Construit le visuel manuellement (équivalent de _ready sans scène active).
	b.call("_build_visual")
	return b

func test_town_hall_uses_sprite_not_cube() -> void:
	var th: Building = _make_th(1)
	var sprite := th.get_node_or_null("Sprite") as Sprite3D
	if sprite == null:
		push_error("CHECK FAILED: HDV n'a pas de noeud Sprite")
		return
	if sprite.billboard != BaseMaterial3D.BILLBOARD_ENABLED:
		push_error("CHECK FAILED: Sprite HDV n'est pas en billboard")
	# La texture du niveau 1 est chargée.
	if sprite.texture == null:
		push_error("CHECK FAILED: Sprite HDV sans texture")
	if th.get_node_or_null("Mesh") != null:
		push_error("CHECK FAILED: HDV devrait être un Sprite, pas un Mesh")
	# LARGEUR = empreinte × HDV_VISUAL_SCALE : l'HDV est agrandie visuellement
	# (1.5x) au-delà de la collision pour dominer le village. La hauteur suit
	# l'aspect et le pied reste posé sur le sol.
	var foot: int = th.footprint()
	var w: float = float(sprite.texture.get_size().x) * sprite.pixel_size
	if absf(w - float(foot) * Building.HDV_VISUAL_SCALE) > 0.01:
		push_error("CHECK FAILED: largeur sprite HDV (%.2f) != empreinte*scale %.2f" % [w, foot * Building.HDV_VISUAL_SCALE])
	# Le bas du sprite doit reposer sur le sol : position.y = hauteur affichée/2.
	var h: float = float(sprite.texture.get_size().y) * sprite.pixel_size
	if sprite.position.y < h * 0.5 or sprite.position.y > h * 0.5 + 0.05:
		push_error("CHECK FAILED: pied du sprite mal ancré au sol (y=%.2f, h=%.2f)" % [sprite.position.y, h])
	th.free()

func test_town_hall_sprite_texture_follows_level() -> void:
	var th: Building = _make_th(3)
	var tex: Texture2D = th.call("_town_hall_texture")
	var p: String = tex.resource_path
	if not p.ends_with("HDV-3.png"):
		push_error("CHECK FAILED: _town_hall_texture niveau 3 ne renvoie pas HDV-3.png, obtenu ", p)
	th.level = 4
	tex = th.call("_town_hall_texture")
	p = tex.resource_path
	if not p.ends_with("HDV-4.png"):
		push_error("CHECK FAILED: _town_hall_texture niveau 4 ne renvoie pas HDV-4.png, obtenu ", p)
	th.free()

func test_town_hall_max_level_is_six() -> void:
	var cfg: Dictionary = Building.TYPES[Building.Type.TOWN_HALL]
	if cfg.get("max_level", 0) != 6:
		push_error("CHECK FAILED: max_level HDV attendu 6, obtenu ", cfg.get("max_level", 0))
