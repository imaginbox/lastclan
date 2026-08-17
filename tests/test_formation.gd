extends Node
## Tests de réorganisation de formation : soldats proches du héros (anneau),
## paysans derrière (arc arrière plus large), repli « comme des soldats »
## quand il n'y a que des paysans.

func _check(cond: bool, msg: String) -> void:
	if not cond:
		push_error("CHECK FAILED: " + msg)

func _new_hero() -> Node:
	return load("res://scripts/Hero.gd").new()

func _new_soldier() -> Node:
	return load("res://scripts/Soldier.gd").new()

func _new_villager() -> Node:
	return load("res://scripts/Villager.gd").new()

## Distance horizontale (plan XZ) d'un spot local par rapport au centre.
func _d(spot: Vector3) -> float:
	return Vector2(spot.x, spot.z).length()

func test_peasants_only_form_like_soldiers() -> void:
	var hero: Node = _new_hero()
	var v1: Node = _new_villager()
	var v2: Node = _new_villager()
	hero.set("_troop", [v1, v2])
	hero.call("_build_formation_spots")
	var spots: Array = hero.get("_formation_spots")
	_check(spots.size() == 2, "2 spots paysans, got %d" % spots.size())
	# Même anneau (rayon unique) que la formation « soldats » à 2 unités.
	var expect: float = 1.1 + sqrt(2.0) * 0.35
	for sp in spots:
		_check(is_equal_approx(_d(sp), expect), "paysans seuls: rayon %f attendu %f" % [_d(sp), expect])
	# Tous au même rayon (anneau circulaire).
	_check(is_equal_approx(_d(spots[0]), _d(spots[1])), "rayons paysans égaux")

func test_soldiers_only_ring() -> void:
	var hero: Node = _new_hero()
	var s: Array = [_new_soldier(), _new_soldier(), _new_soldier()]
	hero.set("_troop", s)
	hero.call("_build_formation_spots")
	var spots: Array = hero.get("_formation_spots")
	_check(spots.size() == 3, "3 spots soldats")
	var r: float = _d(spots[0])
	for sp in spots:
		_check(is_equal_approx(_d(sp), r), "soldats au même rayon : %f vs %f" % [_d(sp), r])

func test_mixed_soldiers_front_peasants_back() -> void:
	var hero: Node = _new_hero()
	var s1: Node = _new_soldier()
	var s2: Node = _new_soldier()
	var v1: Node = _new_villager()
	hero.set("_troop", [s1, v1, s2])   # ordre mélangé volontairement
	hero.call("_build_formation_spots")
	var spots: Array = hero.get("_formation_spots")
	_check(spots.size() == 3, "3 spots mixtes, got %d" % spots.size())
	var d_s0: float = _d(spots[0])
	var d_p1: float = _d(spots[1])
	var d_s2: float = _d(spots[2])
	_check(is_equal_approx(d_s0, d_s2), "soldats même rayon proche : %f vs %f" % [d_s0, d_s2])
	_check(d_p1 > d_s0, "paysan derrière (rayon > soldats) : %f vs %f" % [d_p1, d_s0])
	# Le paysan est à l'opposé de l'avant (arc arrière) : son angle en XZ est
	# proche de -PI/2 +/- spread/2 lorsque le héros regarde vers -Z (défaut).
	# On vérifie qu'il est DERRIÈRE les soldats : cos de l'angle < un soldat.
	var center_angle_p1: float = atan2(spots[1].z, spots[1].x)
	var angle_s0: float = atan2(spots[0].z, spots[0].x)
	# Soldats démarrent vers l'avant (-Z -> angle -PI/2).
	_check(abs(TauHelper.diff(center_angle_p1, angle_s0)) > 1.0,
		"paysan écarté de l'avant des soldats (réf %f vs %f)" % [center_angle_p1, angle_s0])

## Petit helper de différence angulaire normalisée (pas de dépendance extérieure).
class TauHelper:
	static func diff(a: float, b: float) -> float:
		var d: float = fmod(a - b, TAU)
		if d > PI:
			d -= TAU
		elif d < -PI:
			d += TAU
		return d
