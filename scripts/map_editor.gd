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
# Distribution du décor : placement ponctuel (clic) ou dispersion aléatoire.
var _decor_random := false
var _scatter_count := 8
var _scatter_radius := 25.0
# Déplacement de la caméra (zoom molette, pan clic molette).
var _panning := false
# Outil « Route » : premier clic = départ, second clic = tracé d'un chemin droit.
var _route_mode := false
var _route_start := Vector2.INF

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
	top_box.add_child(_btn("Générer", _on_generate))
	top_box.add_child(_btn("Charger", _on_load))
	top_box.add_child(_btn("Sauvegarder", _on_save))
	var def_btn := _btn("Défaut", _on_set_default)
	def_btn.tooltip_text = "Définir comme monde par défaut du jeu (active.json)"
	top_box.add_child(def_btn)
	top_box.add_child(_btn("Retour", _on_back))

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
	# Outil route : trace un chemin droit entre deux clics.
	var route_btn := _btn("Route (2 pts)", Callable())
	route_btn.toggle_mode = true
	route_btn.toggled.connect(_on_toggle_route)
	left_box.add_child(route_btn)

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
	for t in ["tree", "cactus", "rock", "bush", "flower", "grass", "house"]:
		var btn := _btn(t.capitalize(), func(): _set_decor(t))
		btn.toggle_mode = true
		_decor_buttons.append(btn)
		right_box.add_child(btn)
	var village_btn := _btn("Village", func(): _set_decor("village"))
	right_box.add_child(village_btn)
	right_box.add_child(_sep("Distribution"))
	var dgroup := ButtonGroup.new()
	var place_btn := _btn("Placer", Callable())
	place_btn.toggle_mode = true
	place_btn.button_group = dgroup
	place_btn.button_pressed = true
	place_btn.toggled.connect(func(p: bool): if p: _set_decor_random(false))
	right_box.add_child(place_btn)
	var rand_btn := _btn("Aléatoire", Callable())
	rand_btn.toggle_mode = true
	rand_btn.button_group = dgroup
	rand_btn.toggled.connect(func(p: bool): if p: _set_decor_random(true))
	right_box.add_child(rand_btn)
	var cnt_row := HBoxContainer.new()
	cnt_row.add_child(_row_label("Nb"))
	var cnt_spin := SpinBox.new()
	cnt_spin.min_value = 1
	cnt_spin.max_value = 60
	cnt_spin.value = _scatter_count
	cnt_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cnt_spin.value_changed.connect(func(v: float): _scatter_count = int(v))
	cnt_row.add_child(cnt_spin)
	right_box.add_child(cnt_row)
	var rad_row := HBoxContainer.new()
	rad_row.add_child(_row_label("Rayon"))
	var rad_spin := SpinBox.new()
	rad_spin.min_value = 5
	rad_spin.max_value = 120
	rad_spin.step = 5
	rad_spin.value = _scatter_radius
	rad_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rad_spin.value_changed.connect(func(v: float): _scatter_radius = v)
	rad_row.add_child(rad_spin)
	right_box.add_child(rad_row)
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
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

func _sep(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	return l

## Petit label pour les lignes de réglage (Nb, Rayon…).
func _row_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(48, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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

func _set_decor_random(v: bool) -> void:
	_decor_random = v
	_status.text = ("Décor aléatoire (dispersion naturelle)" if v
			else "Décor placé au clic")

# ---------------------------------------------------------------------------
# Entrées souris
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_camera(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_camera(1)
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
				if event.pressed:
					Input.set_default_cursor_shape(Input.CURSOR_MOVE)
				else:
					Input.set_default_cursor_shape(Input.CURSOR_ARROW)
			MOUSE_BUTTON_LEFT:
				_painting = event.pressed
				if event.pressed:
					var w := _world_from_mouse(event.position)
					if w != Vector3.INF:
						_apply_at(w)
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					var w := _world_from_mouse(event.position)
					if w != Vector3.INF:
						_erase_decor_near(w)
	elif event is InputEventMouseMotion:
		if _panning:
			_pan_camera(event.relative)
		# En mode décor, on place UN élément par clic (pas à chaque mouvement) ;
		# seul le mode peinture suit le glisser de la souris.
		elif _painting and _mode == "paint":
			var w := _world_from_mouse(event.position)
			if w != Vector3.INF:
				_apply_at(w)

## Zoom orthographique : molette. size = hauteur visible du monde.
func _zoom_camera(dir: int) -> void:
	_cam.size = clampf(_cam.size * (1.0 + 0.12 * float(dir)), 25.0, 460.0)

## Déplacement de la caméra : glisser avec le clic molette (relatif à l'écran).
func _pan_camera(rel: Vector2) -> void:
	var vp_h: float = get_viewport().get_visible_rect().size.y
	var wpp := _cam.size / maxf(vp_h, 1.0)
	_cam.position.x = clampf(_cam.position.x - rel.x * wpp, -200.0, 200.0)
	_cam.position.z = clampf(_cam.position.z - rel.y * wpp, -200.0, 200.0)

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
	if _route_mode:
		_route_click(w)
	elif _mode == "paint":
		_paint_brush(w)
	else:
		_place_decor(w)

## Route en 2 points : premier clic = départ, second clic = chemin droit (PATH).
func _route_click(w: Vector3) -> void:
	var cell := Vector2(_map.world_to_cell(w.x, w.z))
	if _route_start == Vector2.INF:
		_route_start = cell
		_status.text = "Route : cliquez le point d'arrivée."
	else:
		_draw_route_line(_route_start, cell)
		_route_start = Vector2.INF
		_rebake()
		_status.text = "Route tracée."

func _on_toggle_route(pressed: bool) -> void:
	_route_mode = pressed
	_mode = "paint"
	_route_start = Vector2.INF
	_status.text = ("Route : cliquez le point de départ." if pressed else "Peindre au clic.")

## Tracé d'une ligne droite (Bresenham) de cellules CHEMIN de a vers b.
func _draw_route_line(a: Vector2, b: Vector2) -> void:
	var x0 := int(a.x)
	var y0 := int(a.y)
	var x1 := int(b.x)
	var y1 := int(b.y)
	var dx := absi(x1 - x0)
	var sx := 1 if x0 < x1 else -1
	var dy := -absi(y1 - y0)
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	while true:
		_set_cell_safe(x0, y0, TerrainMap.TB.PATH)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy

func _paint_brush(w: Vector3) -> void:
	var c := _map.world_to_cell(w.x, w.z)
	var r := _brush_size
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dz * dz <= r * r:
				_map.set_cell(c.x + dx, c.y + dz, _brush_biome)
	_rebake()

func _place_decor(w: Vector3) -> void:
	# Village : groupe de maisons + une petite croix de chemin au centre.
	if _decor_type == "village":
		_place_village(w)
	# Base / avant-poste = spawns (un seul de chaque), toujours au clic exact.
	elif _decor_type == "base" or _decor_type == "outpost":
		_map.spawns = _map.spawns.filter(func(s): return s["kind"] != _decor_type)
		_map.add_spawn(_decor_type, w.x, w.z)
	# Dispersion aléatoire : on répartit plusieurs éléments autour du clic avec
	# rotation et échelle aléatoires → rendu naturel, non aligné en ligne.
	elif _decor_random:
		for i in _scatter_count:
			var ang := randf_range(0.0, TAU)
			var rad := sqrt(randf()) * _scatter_radius
			var x := clampf(w.x + cos(ang) * rad, -200.0, 200.0)
			var z := clampf(w.z + sin(ang) * rad, -200.0, 200.0)
			_map.add_decor(_decor_type, x, z,
					randf_range(0.7, 1.5), randf_range(0.0, 360.0))
	# Placement ponctuel : léger aléa de rotation/échelle pour rester vivant.
	else:
		_map.add_decor(_decor_type, w.x, w.z, randf_range(0.9, 1.3), randf_range(0.0, 360.0))
	_refresh_decor_preview()
	_rebake()

## Pose un petit village : quelques maisons en cercle + une croix de chemin.
func _place_village(w: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 7:
		var ang := rng.randf_range(0.0, TAU)
		var rad := rng.randf_range(6.0, 26.0)
		_map.add_decor("house", w.x + cos(ang) * rad, w.z + sin(ang) * rad,
				rng.randf_range(0.9, 1.4), rng.randf_range(0.0, 360.0))
	# Croix de chemin au centre du village.
	var c := Vector2(_map.world_to_cell(w.x, w.z))
	_draw_route_line(c, c + Vector2(4, 0))
	_draw_route_line(c - Vector2(4, 0), c + Vector2(4, 0))
	_draw_route_line(c, c + Vector2(0, 4))
	_draw_route_line(c - Vector2(0, 4), c + Vector2(0, 4))
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
		"house": col = Color(0.72, 0.5, 0.3); shape = "box"
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

## Génère une carte aléatoire naturelle (rivières, forêts, déserts) à utiliser
## comme base de travail, puis à modifier à la main.
func _on_generate() -> void:
	_map = TerrainMap.new()
	var G := TerrainMap.GRID
	var HALF := G / 2.0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# Base : tout en herbe.
	for iz in G:
		for ix in G:
			_map.set_cell(ix, iz, TerrainMap.TB.GRASS)
	# 1 à 2 rivières courbes traversant la carte.
	var rivers := rng.randi_range(1, 2)
	for r in rivers:
		var x := rng.randf_range(HALF * 0.25, HALF * 0.75)
		var z := rng.randf_range(HALF * 0.25, HALF * 0.75)
		var dir := rng.randf_range(0.0, TAU)
		var seg: Array[Vector2] = []
		var px := x
		var pz := z
		var step := 0.5
		var steps := int(G * 1.4 / step)
		for i in steps:
			seg.append(Vector2(px, pz))
			var w := sin(i * 0.18) * 1.4 + sin(i * 0.07 + 3.0) * 0.8
			px += cos(dir + w) * step
			pz += sin(dir + w) * step
		_draw_thick_path(seg, 2 + rng.randi_range(0, 2), TerrainMap.TB.WATER)
	# Taches de forêt.
	var forests := rng.randi_range(2, 4)
	for i in forests:
		_draw_blob(rng.randf_range(HALF * 0.25, G - HALF * 0.25),
				rng.randf_range(HALF * 0.25, G - HALF * 0.25),
				rng.randf_range(6.0, 14.0), TerrainMap.TB.FOREST, rng)
	# Taches de désert.
	var deserts := rng.randi_range(2, 4)
	for i in deserts:
		_draw_blob(rng.randf_range(HALF * 0.25, G - HALF * 0.25),
				rng.randf_range(HALF * 0.25, G - HALF * 0.25),
				rng.randf_range(6.0, 13.0), TerrainMap.TB.DESERT, rng)
	# Base au centre, avant-poste sur le bord.
	_map.add_spawn("base", 0.0, 0.0)
	var ang := rng.randf_range(0.0, TAU)
	_map.add_spawn("outpost", cos(ang) * 120.0, sin(ang) * 120.0)
	_name_edit.text = "carte_" + str(Time.get_unix_time_from_system()).substr(7)
	_refresh_decor_preview()
	_rebake()
	_status.text = "Carte générée aléatoirement — modifie-la puis sauvegarde."

## Trace une bande épaisse de cellules le long d'une série de points.
func _draw_thick_path(seg: Array, width: int, biome: int) -> void:
	for s in seg:
		var sx := int(s.x)
		var sz := int(s.y)
		for dz in range(-width, width + 1):
			for dx in range(-width, width + 1):
				if dx * dx + dz * dz <= width * width:
					_set_cell_safe(sx + dx, sz + dz, biome)

## Remplit un « blob » circulaire à bord irrégulier (aspect naturel).
func _draw_blob(cx: float, cz: float, rad: float, biome: int, rng: RandomNumberGenerator) -> void:
	var wob := rng.randf_range(0.0, TAU)
	for iz in range(int(cz - rad) - 2, int(cz + rad) + 3):
		for ix in range(int(cx - rad) - 2, int(cx + rad) + 3):
			var d := Vector2(float(ix) - cx, float(iz) - cz).length()
			var jitter := sin(ix * 0.4 + wob) * 2.0 + sin(iz * 0.35 - wob) * 2.0
			if d < rad + jitter:
				_set_cell_safe(ix, iz, biome)

func _set_cell_safe(ix: int, iz: int, b: int) -> void:
	if ix >= 0 and ix < TerrainMap.GRID and iz >= 0 and iz < TerrainMap.GRID:
		_map.set_cell(ix, iz, b)

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

## Retour au menu principal.
func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/LobbyMenu.tscn")

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

## Liste les cartes enregistrées (res://maps/*.json), triées par nom.
func _list_saved_maps() -> Array:
	DirAccess.make_dir_recursive_absolute(MAPS_DIR)
	var dir := DirAccess.open(MAPS_DIR)
	var names: Array = []
	if dir == null:
		return names
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".json") and not f.begins_with("."):
			names.append(f.trim_suffix(".json"))
		f = dir.get_next()
	names.sort()
	return names

## Définit une carte enregistrée comme monde par défaut du jeu (active.json),
## sans modifier le dessin en cours. Ouvre une boîte de choix des cartes.
func _on_set_default() -> void:
	var names := _list_saved_maps()
	if names.is_empty():
		_status.text = "Aucune carte enregistrée."
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "Définir le monde par défaut"
	dlg.ok_button_text = "Définir par défaut"
	dlg.cancel_button_text = "Annuler"
	var box := VBoxContainer.new()
	dlg.add_child(box)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	var lbl := Label.new()
	lbl.text = "Choisis la carte chargée par défaut dans le jeu :"
	box.add_child(lbl)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for n in names:
		opt.add_item(n)
	opt.selected = 0
	box.add_child(opt)
	dlg.get_ok_button().pressed.connect(func():
		var chosen: String = names[opt.selected]
		var tm := TerrainMap.load_from(MAPS_DIR + "/" + chosen + ".json")
		if tm != null and tm.save_to(ACTIVE_MAP) == OK:
			_status.text = "« " + chosen + " » défini comme monde par défaut."
		else:
			_status.text = "Erreur : impossible de définir la carte par défaut."
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered(Vector2(380, 140))
