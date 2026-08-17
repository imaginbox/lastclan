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
	_check(d_p1 > d_s0, "paysan au retrait (rayon > soldats) : %f vs %f" % [d_p1, d_s0])
	# Les soldats restent les plus proches du héros : chaque soldat est plus
	# proche OU à égalité que le paysan le plus éloigné d'eux.
	_check(d_s0 < d_p1 and d_s2 < d_p1, "soldats strictement plus proches que le paysan")
	# Paysan UNIQUE : placé exactement au DOS du héros (local +Z), pas sur le côté.
	var p: Vector3 = spots[1]
	_check(abs(p.x) < 0.01, "paysan centré au dos (x~0) : %f" % p.x)
	_check(p.z > 0.0, "paysan derrière le héros (z>0) : %f" % p.z)
	# Soldats de part et d'autre du héros (l'un à l'avant -Z, l'autre à l'arrière +Z).
	_check(spots[0].z < 0.0, "soldat avant (z<0) : %f" % spots[0].z)
