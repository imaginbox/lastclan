class_name UnitStats
## Aides de statistiques d'unités : niveau de l'hôtel de ville (HDV) du joueur et
## multiplicateurs de montée en puissance. Plus la ville est avancée, plus les
## attributs des unités (endurance, force, rapidité, capacité de récolte) progressent.
## Toutes les fonctions sont statiques : utilisables depuis n'importe quelle unité.

## Niveau actuel de l'hôtel de ville du joueur (1 si absent / hors arbre).
static func town_hall_level(unit: Node) -> int:
	if unit == null or unit.get_tree() == null:
		return 1
	var th: Node = unit.get_tree().get_first_node_in_group("town_hall")
	return th.level if th != null else 1

## Multiplicateur de VIE / endurance selon le niveau de ville.
static func hp_scale(unit: Node) -> float:
	return 1.0 + float(town_hall_level(unit) - 1) * 0.08

## Multiplicateur de DÉGÂTS / force selon le niveau de ville.
static func damage_scale(unit: Node) -> float:
	return 1.0 + float(town_hall_level(unit) - 1) * 0.06

## Multiplicateur de VITESSE / rapidité selon le niveau de ville.
static func speed_scale(unit: Node) -> float:
	return 1.0 + float(town_hall_level(unit) - 1) * 0.02

## Multiplicateur de CAPACITÉ de récolte / transport selon le niveau de ville.
static func carry_scale(unit: Node) -> float:
	return 1.0 + float(town_hall_level(unit) - 1) * 0.05
