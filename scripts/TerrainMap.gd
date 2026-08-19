class_name TerrainMap
extends Resource
## Modèle de données d'une carte créée dans l'éditeur.
## Le monde est une grille de biomes (GRID x GRID cellules sur GRID_WORLD unités),
## plus des listes de décor (arbres, cactus, rochers...) et de points de spawn.
## Sauvegardable / chargeable en JSON (déterministe => partagé en multijoueur).

enum TB { GRASS, FOREST, DESERT, WATER, PATH }

## Taille en cellules de la grille et taille en unités du monde.
const GRID := 80
const GRID_WORLD := 400.0
const CELL := GRID_WORLD / GRID  # 5.0 u par cellule

## Palette de couleurs par biome (utilisée pour la texture + l'aperçu).
const PALETTE: Dictionary = {
	TB.GRASS: Color(0.42, 0.66, 0.30),
	TB.FOREST: Color(0.30, 0.52, 0.24),
	TB.DESERT: Color(0.80, 0.71, 0.46),
	TB.WATER: Color(0.20, 0.50, 0.85),
	TB.PATH: Color(0.58, 0.47, 0.34),
}
const BIOME_NAMES: Dictionary = {
	TB.GRASS: "Prairie", TB.FOREST: "Forêt", TB.DESERT: "Désert",
	TB.WATER: "Eau", TB.PATH: "Chemin",
}

var map_name: String = "nouvelle_carte"
var cells := PackedByteArray()
var decor: Array[Dictionary] = []   # {type:String, x:float, z:float, s:float, r:float}
var spawns: Array[Dictionary] = []  # {kind:String, x:float, z:float}

func _init() -> void:
	cells.resize(GRID * GRID)
	cells.fill(TB.GRASS)

# ---- accès grille ----
func index(ix: int, iz: int) -> int:
	return iz * GRID + ix

func in_bounds(ix: int, iz: int) -> bool:
	return ix >= 0 and ix < GRID and iz >= 0 and iz < GRID

func get_cell(ix: int, iz: int) -> int:
	if not in_bounds(ix, iz):
		return TB.GRASS
	return cells[index(ix, iz)]

func set_cell(ix: int, iz: int, b: int) -> void:
	if in_bounds(ix, iz):
		cells[index(ix, iz)] = b

## Coordonnées monde -> cellule de la grille.
func world_to_cell(wx: float, wz: float) -> Vector2i:
	return Vector2i(
		int(floor((wx + GRID_WORLD * 0.5) / CELL)),
		int(floor((wz + GRID_WORLD * 0.5) / CELL))
	)

## Centre monde d'une cellule.
func cell_to_world(ix: int, iz: int) -> Vector2:
	return Vector2(
		- GRID_WORLD * 0.5 + (ix + 0.5) * CELL,
		- GRID_WORLD * 0.5 + (iz + 0.5) * CELL
	)

# ---- texture de la grille (couleurs de palette, filtre linéaire => transitions douces) ----
func bake_color_texture() -> ImageTexture:
	var img := Image.create(GRID, GRID, false, Image.FORMAT_RGBA8)
	for iz in GRID:
		for ix in GRID:
			var b := get_cell(ix, iz)
			img.set_pixel(ix, iz, PALETTE.get(b, PALETTE[TB.GRASS]))
	# Filtre linéaire géré côté shader (hint_filter_linear) pour les transitions douces.
	return ImageTexture.create_from_image(img)

# ---- décor ----
func add_decor(type: String, wx: float, wz: float, s: float = 1.0, r: float = 0.0) -> void:
	decor.append({"type": type, "x": wx, "z": wz, "s": s, "r": r})

# ---- spawns ----
func add_spawn(kind: String, wx: float, wz: float) -> void:
	spawns.append({"kind": kind, "x": wx, "z": wz})

func base_spawn() -> Dictionary:
	for s in spawns:
		if s["kind"] == "base":
			return s
	return {"kind": "base", "x": 0.0, "z": 0.0}

# ---- sauvegarde / chargement JSON ----
func to_dict() -> Dictionary:
	var cell_list: Array = []
	for i in cells.size():
		cell_list.append(int(cells[i]))
	return {
		"name": map_name,
		"grid": GRID,
		"cells": cell_list,
		"decor": decor,
		"spawns": spawns,
	}

func save_to(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	return OK

static func load_from(path: String) -> TerrainMap:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		return null
	var tm := TerrainMap.new()
	if data.has("name"):
		tm.map_name = data["name"]
	if data.has("cells") and (data["cells"] is Array):
		var arr: Array = data["cells"]
		tm.cells.resize(GRID * GRID)
		tm.cells.fill(TB.GRASS)
		for i in mini(arr.size(), GRID * GRID):
			tm.cells[i] = int(arr[i]) & 0xff
	if data.has("decor") and (data["decor"] is Array):
		for d in data["decor"]:
			if d is Dictionary:
				tm.decor.append({
					"type": str(d.get("type", "tree")),
					"x": float(d.get("x", 0.0)),
					"z": float(d.get("z", 0.0)),
					"s": float(d.get("s", 1.0)),
					"r": float(d.get("r", 0.0)),
				})
	if data.has("spawns") and (data["spawns"] is Array):
		for s in data["spawns"]:
			if s is Dictionary:
				tm.spawns.append({
					"kind": str(s.get("kind", "base")),
					"x": float(s.get("x", 0.0)),
					"z": float(s.get("z", 0.0)),
				})
	return tm
