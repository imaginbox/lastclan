class_name MapEditor
extends Node3D
## Éditeur de carte : peindre les zones de terrain (herbe, forêt, désert, eau,
## chemin) au pinceau, placer du décor et des points de spawn, puis sauvegarder
## la carte en JSON (res://maps/). Les cartes remplacent le monde procédural.

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const MAPS_DIR := "res://maps"
const ACTIVE_MAP := "res://maps/active.json"

var _map := TerrainMap.new()
var _cam: Camera3D
var _ground_mesh: MeshInstance3D
var _ground_mat: ShaderMaterial

# État de l'outil
var _brush_biome: int = TerrainMap.TB.GRASS
var _brush_size: int = 3
var _mode: String = "paint"     # "paint" | "decor"
var _decor_type: String = "tree"
var _painting := false

# UI
var _name_edit: LineEdit
var _status: Label
var _decor_buttons: Array[Button] = []

func _ready() -> void:
	_cam = $Camera3D
	_ground_mesh = $GroundMesh
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = TERRAIN_SHADER
	_ground_mat.set_shader_parameter("u_use_grid", true)
	_ground_mesh.material_override = _ground_mat
	_build_ui()
	# Charge la carte active si elle existe (pratique pour retravailler).
	var existing := TerrainMap.load_from(ACTIVE_MAP)
	if existing != null:
		_map = existing
		_name_edit.text = _map.map_name
	_refresh_decor_preview()
	_rebake()
	_status.text = "Prêt. Peins une zone (bouton gauche), clic droit = efface (prairie)."

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	var lay := $CanvasLayer
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Ne pas avaler les clics : les zones vides laissent passer la souris vers
	# _unhandled_input (peinture) ; seuls les boutons/panneaux enfants les capturent.
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lay.add_child(root)

	# --- Barre du haut : nom + actions ---
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 8
	top.offset_top = 8
	top.offset_right = -8
	root.add_child(top)
	var top_box := HBoxContainer.new()
	top_box.add_theme_constant_override("separation", 8)
	top.add_child(top_box)

	var title := Label.new()
	title.text = "Éditeur de carte"
	top_box.add_child(title)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "nom_de_la_carte"
	_name_edit.custom_minimum_size = Vector2(180, 0)
	top_box.add_child(_name_edit)

	top_box.add_child(_btn("Nouveau", _on_new))
	top_box.add_child(_btn("Charger", _on_load))
	top_box.add_child(_btn("Sauvegarder", _on_save))

	_status = Label.new()
	_status.text = ""
	top_box.add_child(_status)

	# --- Panneau gauche : pinceaux de biomes ---
	var left := PanelContainer.new()
	left.offset_left = 8
	left.offset_top = 60
	left.custom_minimum_size = Vector2(150, 0)
	root.add_child(left)
	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 6)
	left.add_child(left_box)

	var mode_paint := _btn("Mode: Peindre", func(): _set_mode("paint"))
	left_box.add_child(mode_paint)
	var mode_decor := _btn("Mode: Décor", func(): _set_mode("decor"))
	left_box.add_child(mode_decor)

	left_box.add_child(_sep("Zones"))
	for b in TerrainMap.TB.keys():
		var bid: int = TerrainMap.TB[b]
		var btn := _btn(TerrainMap.BIOME_NAMES[bid], func(): _set_brush(bid))
		btn.modulate = TerrainMap.PALETTE[bid]
		left_box.add_child(btn)

	left_box.add_child(_sep("Pinceau"))
	var size_box := HBoxContainer.new()
	var size_label := Label.new()
	size_label.text = "Taille"
	size_box.add_child(size_label)
	var size_spin := SpinBox.new()
	size_spin.min_value = 1
	size_spin.max_value = 12
	size_spin.value = _brush_size
	size_spin.value_changed.connect(func(v: float): _brush_size = int(v))
	size_box.add_child(size_spin)
	left_box.add_child(size_box)

	# --- Panneau droite : décor ---
	var right := PanelContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -170
	right.offset_top = 60
	right.custom_minimum_size = Vector2(162, 0)
	root.add_child(right)
	var right_box := VBoxContainer.new()
	right_box.add_theme_constant_override("separation", 6)
	right.add_child(right_box)
	right_box.add_child(_sep("Décor"))
	for t in ["tree", "cactus", "rock", "bush", "flower", "grass"]:
		var btn := _btn(t.capitalize(), func(): _set_decor(t))
		btn.toggle_mode = true
		_decor_buttons.append(btn)
		right_box.add_child(btn)
	right_box.add_child(_sep("Spawn"))
	var base_btn := _btn("Base (spawn)", func(): _set_decor("base"))
	right_box.add_child(base_btn)
	var outpost_btn := _btn("Avant-poste ennemi", func(): _set_decor("outpost"))
	right_box.add_child(outpost_btn)

# ---------------------------------------------------------------------------
# Aide UI
# ---------------------------------------------------------------------------
func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b

func _sep(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	return l

func _set_mode(m: String) -> void:
	_mode = m
	_status.text = "Mode " + ("Décor (clique pour placer)" if m == "decor" else "Peindre (clic glisser)")

func _set_brush(b: int) -> void:
	_brush_biome = b
	_mode = "paint"
	_status.text = "Peindre: " + TerrainMap.BIOME_NAMES[b]

func _set_decor(t: String) -> void:
	_decor_type = t
	_mode = "decor"
	_status.text = "Placer: " + t.capitalize()

# ---------------------------------------------------------------------------
# Entrées souris
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_painting = event.pressed
			if event.pressed:
				var w := _world_from_mouse(event.position)
				if w != Vector3.INF:
					_apply_at(w)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var w := _world_from_mouse(event.position)
			if w != Vector3.INF:
				_erase_decor_near(w)
	elif event is InputEventMouseMotion and _painting:
		var w := _world_from_mouse(event.position)
		if w != Vector3.INF:
			_apply_at(w)

func _world_from_mouse(ev_pos: Vector2) -> Vector3:
	var origin := _cam.project_ray_origin(ev_pos)
	var normal := _cam.project_ray_normal(ev_pos)
	if absf(normal.y) < 1e-4:
		return Vector3.INF
	var t := -origin.y / normal.y
	if t < 0.0:
		return Vector3.INF
	return origin + normal * t

func _apply_at(w: Vector3) -> void:
	if _mode == "paint":
		_paint_brush(w)
	else:
		_place_decor(w)

func _paint_brush(w: Vector3) -> void:
	var c := _map.world_to_cell(w.x, w.z)
	var r := _brush_size
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dz * dz <= r * r:
				_map.set_cell(c.x + dx, c.y + dz, _brush_biome)
	_rebake()

func _place_decor(w: Vector3) -> void:
	if _decor_type == "base":
		# une seule base : on retire les anciennes puis on place
		_map.spawns = _map.spawns.filter(func(s): return s["kind"] != "base")
		_map.add_spawn("base", w.x, w.z)
	else:
		_map.add_decor(_decor_type, w.x, w.z, 1.0, 0.0)
	_refresh_decor_preview()
	_rebake()

func _erase_decor_near(w: Vector3) -> void:
	var i := _map.decor.size() - 1
	while i >= 0:
		var d: Dictionary = _map.decor[i]
		if Vector2(d["x"], d["z"]).distance_to(Vector2(w.x, w.z)) < 3.0:
			_map.decor.remove_at(i)
		i -= 1
	_refresh_decor_preview()
	_rebake()

# ---------------------------------------------------------------------------
# Rendu
# ---------------------------------------------------------------------------
func _rebake() -> void:
	_ground_mat.set_shader_parameter("u_grid", _map.bake_color_texture())

func _refresh_decor_preview() -> void:
	var root := $DecorRoot
	for c in root.get_children():
		c.queue_free()
	for d in _map.decor:
		root.add_child(_make_decor_mesh(d))
	for s in _map.spawns:
		root.add_child(_make_spawn_mesh(s))

func _make_decor_mesh(d: Dictionary) -> MeshInstance3D:
	var col: Color
	var shape := "sphere"
	match str(d["type"]):
		"tree": col = Color(0.25, 0.55, 0.2); shape = "cone"
		"cactus": col = Color(0.3, 0.62, 0.25); shape = "cyl"
		"rock": col = Color(0.55, 0.55, 0.58); shape = "box"
		"bush": col = Color(0.28, 0.45, 0.2)
		"flower": col = Color(0.9, 0.4, 0.4)
		_ : col = Color(0.5, 0.8, 0.3); shape = "quad"
	var mi := MeshInstance3D.new()
	mi.mesh = _shape_mesh(shape)
	mi.position = Vector3(d["x"], 0.5, d["z"])
	mi.scale = Vector3(d["s"], d["s"], d["s"])
	mi.material_override = _solid(col)
	return mi

func _make_spawn_mesh(s: Dictionary) -> MeshInstance3D:
	var col := Color(1.0, 0.8, 0.1) if s["kind"] == "base" else Color(1.0, 0.2, 0.2)
	var mi := MeshInstance3D.new()
	mi.mesh = CylinderMesh.new()
	mi.mesh.height = 1.0
	mi.position = Vector3(s["x"], 0.5, s["z"])
	mi.material_override = _solid(col)
	return mi

func _shape_mesh(kind: String) -> Mesh:
	match kind:
		"cone": return CylinderMesh.new()
		"cyl": return CylinderMesh.new()
		"box": return BoxMesh.new()
		"quad": return QuadMesh.new()
	return SphereMesh.new()

func _solid(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	return m

# ---------------------------------------------------------------------------
# Sauvegarde / chargement / nouveau
# ---------------------------------------------------------------------------
func _on_new() -> void:
	_map = TerrainMap.new()
	_name_edit.text = "nouvelle_carte"
	_refresh_decor_preview()
	_rebake()
	_status.text = "Nouvelle carte (tout prairie)."

func _on_load() -> void:
	DirAccess.make_dir_recursive_absolute(MAPS_DIR)
	var dir := DirAccess.open(MAPS_DIR)
	if dir == null:
		_status.text = "Dossier maps introuvable."
		return
	var names: Array = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".json") and not f.begins_with("."):
			names.append(f.trim_suffix(".json"))
		f = dir.get_next()
	if names.is_empty():
		_status.text = "Aucune carte enregistrée."
		return
	var chosen: String = names[0]
	var tm := TerrainMap.load_from(MAPS_DIR + "/" + chosen + ".json")
	if tm != null:
		_map = tm
		_name_edit.text = _map.map_name
		_refresh_decor_preview()
		_rebake()
		_status.text = "Chargé: " + chosen
	else:
		_status.text = "Échec chargement " + chosen

func _on_save() -> void:
	DirAccess.make_dir_recursive_absolute(MAPS_DIR)
	var map_id := _name_edit.text.strip_edges()
	if map_id.is_empty():
		map_id = "nouvelle_carte"
	_map.map_name = map_id
	var path := MAPS_DIR + "/" + map_id + ".json"
	if _map.save_to(path) == OK:
		# On définit aussi la carte active (chargée par le jeu).
		_map.save_to(ACTIVE_MAP)
		_status.text = "Sauvegardé: " + map_id + " (active)"
	else:
		_status.text = "Erreur de sauvegarde."
