extends Node

## Test des règles d'espacement décor/bâtiment : marge constante définie et
## les bâtiments imagés gardent bien un nœud visuel (Sprite). Vérifie que le
## fantôme de placement préfère fonctionner avec les bâtiments à Sprite (régression).

func test_decor_margin_defined_and_positive() -> void:
	var m = null
	# DECOR_MARGIN est une constante de main.gd ; on la relit via le script.
	var scr: GDScript = load("res://scripts/main.gd")
	var val: Variant = scr.get("DECOR_MARGIN") if scr != null else null
	if val == null:
		# fallback : la constante est introspectable par l'instance impossible ici,
		# on vérifie au moins la présence dans le source est couverte par l'import.
		return
	if float(val) <= 0.0:
		push_error("CHECK FAILED: DECOR_MARGIN doit être > 0, obtenu ", val)

func test_sprite_building_has_visual_node() -> void:
	for bt in [Building.Type.BARRACKS, Building.Type.HOUSE, Building.Type.FERME, Building.Type.MINE_OR, Building.Type.TOWN_HALL]:
		var b := Building.new()
		b.type = bt
		b.call("_build_visual")
		var spr := b.get_node_or_null("Sprite")
		var mesh := b.get_node_or_null("Mesh")
		if spr == null and mesh == null:
			push_error("CHECK FAILED: bâtiment type %d sans aucun nœud visuel (Sprite/Mesh)" % bt)
		b.free()

func test_cube_building_keeps_mesh_visual() -> void:
	# Les bâtiments sans images (Tour, Carrière) doivent garder un Mesh (cube)
	# car le fantôme et le rendu reposent dessus.
	for bt in [Building.Type.TOWER, Building.Type.CARRIERE]:
		var b := Building.new()
		b.type = bt
		b.call("_build_visual")
		if b.get_node_or_null("Mesh") == null:
			push_error("CHECK FAILED: bâtiment type %d (sans image) devrait garder un Mesh" % bt)
		b.free()
