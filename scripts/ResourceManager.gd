extends Node

## ResourceManager (Autoload "ResourceManager")
## Gère l'économie globale : or, bois, pierre, nourriture et population.
## Le signal resources_changed est émis à chaque modification,
## population_changed pour la population (utilisée / capacité).

signal resources_changed(gold: int, wood: int, stone: int, food: int)
signal population_changed(used: int, cap: int)

const START_GOLD: int = 300
const START_WOOD: int = 200
const START_STONE: int = 50
const START_FOOD: int = 20

var gold: int = START_GOLD
var wood: int = START_WOOD
var stone: int = START_STONE
var food: int = START_FOOD

var population: int = 0
var population_cap: int = 0

func _ready() -> void:
	resources_changed.emit(gold, wood, stone, food)
	population_changed.emit(population, population_cap)

## Ajoute de l'or (delta peut être négatif).
func add_gold(delta: int) -> void:
	gold += delta
	resources_changed.emit(gold, wood, stone, food)

## Ajoute du bois (delta peut être négatif).
func add_wood(delta: int) -> void:
	wood += delta
	resources_changed.emit(gold, wood, stone, food)

## Ajoute de la pierre (delta peut être négatif).
func add_stone(delta: int) -> void:
	stone += delta
	resources_changed.emit(gold, wood, stone, food)

## Ajoute de la nourriture (delta peut être négatif).
func add_food(delta: int) -> void:
	food += delta
	resources_changed.emit(gold, wood, stone, food)

## Tente de dépenser or + bois. Renvoie true si tout est couvert.
func spend(gold_cost: int, wood_cost: int) -> bool:
	if gold < gold_cost or wood < wood_cost:
		return false
	gold -= gold_cost
	wood -= wood_cost
	resources_changed.emit(gold, wood, stone, food)
	return true

## Tente de dépenser or + bois + pierre. Renvoie true si tout est couvert.
func spend_full(gold_cost: int, wood_cost: int, stone_cost: int) -> bool:
	if gold < gold_cost or wood < wood_cost or stone < stone_cost:
		return false
	gold -= gold_cost
	wood -= wood_cost
	stone -= stone_cost
	resources_changed.emit(gold, wood, stone, food)
	return true

## Tente de dépenser or + nourriture (recrutement). Renvoie true si tout est couvert.
func spend_food(gold_cost: int, food_cost: int) -> bool:
	if gold < gold_cost or food < food_cost:
		return false
	gold -= gold_cost
	food -= food_cost
	resources_changed.emit(gold, wood, stone, food)
	return true

## Met à jour la capacité de population (somme des maisons).
func set_population_cap(cap: int) -> void:
	population_cap = clampi(cap, 0, 99999)
	population = clampi(population, 0, population_cap)
	population_changed.emit(population, population_cap)

## Tente d'occuper [delta] places de population (delta > 0 = dépense, < 0 = libère).
## Renvoie false si la capacité serait dépassée.
func change_population(delta: int) -> bool:
	var new_pop := population + delta
	if new_pop > population_cap:
		return false
	if new_pop < 0:
		new_pop = 0
	population = new_pop
	population_changed.emit(population, population_cap)
	return true