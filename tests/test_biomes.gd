extends Node
## Tests de la logique pure du monde à biomes (rivières, désert, forêt).

var _main: Node = null

func _m() -> Node:
	if _main == null:
		_main = load("res://scripts/main.gd").new()
	return _main

func test_bezier2_endpoints() -> void:
	var a := Vector3(0, 0, 0)
	var b := Vector3(10, 0, 5)
	var c := Vector3(20, 0, 0)
	if not _m()._bezier2(a, b, c, 0.0).is_equal_approx(a):
		push_error("CHECK FAILED: bezier à t=0 doit donner le point de départ")
	if not _m()._bezier2(a, b, c, 1.0).is_equal_approx(c):
		push_error("CHECK FAILED: bezier à t=1 doit donner le point d'arrivée")

func test_bezier2_midpoint_lerps() -> void:
	var a := Vector3(0, 0, 0)
	var b := Vector3(10, 0, 0)
	var c := Vector3(20, 0, 0)
	# Avec b au centre de la ligne, le point à t=0.5 est exactement au centre.
	var mid: Vector3 = _m()._bezier2(a, b, c, 0.5)
	if not mid.is_equal_approx(Vector3(10, 0, 0)):
		push_error("CHECK FAILED: bezier t=0.5 avec b central attendu (10,0,0), obtenu %s" % mid)

func test_dist_point_segment() -> void:
	var a := Vector3(0, 0, 0)
	var b := Vector3(10, 0, 0)
	# Point sur le segment → distance 0.
	if _m()._dist_point_segment(Vector3(5, 0, 0), a, b) > 0.001:
		push_error("CHECK FAILED: point sur le segment doit être à distance 0")
	# Point à 3 unités de côté → distance 3.
	if absf(_m()._dist_point_segment(Vector3(5, 0, 3), a, b) - 3.0) > 0.001:
		push_error("CHECK FAILED: distance latérale attendue 3")
	# Point au-delà de l'extrémité → distance au point d'arrivée.
	if absf(_m()._dist_point_segment(Vector3(13, 0, 0), a, b) - 3.0) > 0.001:
		push_error("CHECK FAILED: distance à l'extrémité attendue 3")

func test_biome_colors_distinct() -> void:
	var g: Color = _m()._biome_color(_m().Biome.GRASS)
	var d: Color = _m()._biome_color(_m().Biome.DESERT)
	var f: Color = _m()._biome_color(_m().Biome.FOREST)
	# Le désert doit être nettement plus clair/beige que la prairie.
	if not (d.r > g.r + 0.2):
		push_error("CHECK FAILED: le désert doit être plus clair (rouge) que la prairie")
	# La forêt doit être plus sombre (verte) que la prairie.
	if not (f.g < g.g - 0.05):
		push_error("CHECK FAILED: la forêt doit être plus sombre que la prairie")