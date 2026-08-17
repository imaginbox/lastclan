class_name Arrow
extends Node3D

## Projectile d'archer : une flèche stylisée qui vole vers sa cible et lui
## inflige des dégâts à l'arrivée (attaque à distance visible).

var _target: Node3D = null
var _damage: int = 0
var _speed: float = 22.0
var _dir: Vector3 = Vector3.FORWARD

func _ready() -> void:
	_build_mesh()

func setup(from: Vector3, target: Node3D, damage: int) -> void:
	global_position = from
	_target = target
	_damage = damage
	if _target != null and is_instance_valid(_target):
		var to := _target.global_position - from
		to.y = 0.0
		if to.length() > 0.001:
			_dir = to.normalized()
		look_at(_target.global_position, Vector3.UP)

func _build_mesh() -> void:
	# Hampe.
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.03
	cyl.height = 0.5
	shaft.mesh = cyl
	shaft.rotation_degrees.x = 90.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.45, 0.25)
	shaft.material_override = mat
	add_child(shaft)
	# Pointe.
	var tip := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.06
	cone.height = 0.22
	tip.mesh = cone
	tip.position.z = 0.36
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.82, 0.82, 0.88)
	tip.material_override = tmat
	add_child(tip)

func _physics_process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		queue_free()
		return
	var to := _target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var step := _speed * delta
	if dist <= step + 0.2:
		if _target.has_method("take_damage"):
			_target.call("take_damage", _damage, global_position)
		queue_free()
		return
	var dir := to / dist
	global_position += dir * step
	global_position.y = 1.0
	look_at(global_position + dir, Vector3.UP)
