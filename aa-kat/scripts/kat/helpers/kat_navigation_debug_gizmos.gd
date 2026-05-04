class_name KatNavigationDebugGizmos
extends RefCounted

# Runtime navigation gizmos. These are just in-game lines, so they work in VR
# builds instead of depending on Godot editor gizmos.

const TARGET_COLOR: Color = Color(0.2, 0.65, 1.0, 0.95)
const DETOUR_COLOR: Color = Color(0.1, 1.0, 0.45, 0.95)
const MOVE_COLOR: Color = Color(1.0, 0.9, 0.1, 0.95)
const AVOID_COLOR: Color = Color(1.0, 0.45, 0.05, 0.95)
const RAY_CLEAR_COLOR: Color = Color(0.25, 0.9, 1.0, 0.42)
const RAY_HIT_COLOR: Color = Color(1.0, 0.1, 0.08, 0.9)

var actor: Node3D
var root: Node3D
var mesh_instance: MeshInstance3D
var mesh: ImmediateMesh
var material: StandardMaterial3D
var enabled: bool = false


func setup(owner: Node3D) -> void:
	actor = owner
	if actor == null:
		return

	root = actor.get_node_or_null("NavigationDebugGizmos") as Node3D
	if root == null:
		root = Node3D.new()
		root.name = "NavigationDebugGizmos"
		actor.add_child(root)
	root.top_level = true
	root.global_transform = Transform3D.IDENTITY
	root.visible = enabled

	mesh = ImmediateMesh.new()
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true

	mesh_instance = root.get_node_or_null("Lines") as MeshInstance3D
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "Lines"
		root.add_child(mesh_instance)
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material


func set_enabled(value: bool) -> void:
	enabled = value
	if root != null:
		root.visible = enabled
	if not enabled:
		clear()


func clear() -> void:
	if mesh != null:
		mesh.clear_surfaces()


func update(snapshot: Dictionary) -> void:
	if not enabled or mesh == null:
		return

	if root != null:
		root.global_transform = Transform3D.IDENTITY
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)

	var target_line: Dictionary = snapshot.get("target_line", {}) as Dictionary
	_add_optional_line(target_line, TARGET_COLOR)

	var movement_line: Dictionary = snapshot.get("movement_line", {}) as Dictionary
	_add_optional_line(movement_line, MOVE_COLOR)

	var avoidance_line: Dictionary = snapshot.get("avoidance_line", {}) as Dictionary
	_add_optional_line(avoidance_line, AVOID_COLOR)

	var detour_line: Dictionary = snapshot.get("detour_line", {}) as Dictionary
	_add_optional_line(detour_line, DETOUR_COLOR)
	var detour_point: Variant = snapshot.get("detour_point", null)
	if detour_point is Vector3:
		_add_cross(detour_point as Vector3, 0.16, DETOUR_COLOR)

	var rays: Array = snapshot.get("rays", []) as Array
	for ray_data in rays:
		var ray: Dictionary = ray_data as Dictionary
		_add_ray(ray)

	mesh.surface_end()


func _add_optional_line(line: Dictionary, fallback_color: Color) -> void:
	if line.is_empty():
		return

	var from_position: Vector3 = line.get("from", Vector3.ZERO) as Vector3
	var to_position: Vector3 = line.get("to", Vector3.ZERO) as Vector3
	var color: Color = line.get("color", fallback_color) as Color
	_add_line(from_position, to_position, color)


func _add_ray(ray: Dictionary) -> void:
	if ray.is_empty():
		return

	var from_position: Vector3 = ray.get("from", Vector3.ZERO) as Vector3
	var to_position: Vector3 = ray.get("to", Vector3.ZERO) as Vector3
	var hit_position: Vector3 = ray.get("hit", Vector3.ZERO) as Vector3
	var did_hit: bool = bool(ray.get("did_hit", false))
	if did_hit:
		_add_line(from_position, hit_position, RAY_HIT_COLOR)
		_add_line(hit_position, to_position, Color(1.0, 0.1, 0.08, 0.22))
		_add_cross(hit_position, 0.07, RAY_HIT_COLOR)
		return

	_add_line(from_position, to_position, RAY_CLEAR_COLOR)


func _add_cross(position: Vector3, size: float, color: Color) -> void:
	_add_line(position + Vector3.LEFT * size, position + Vector3.RIGHT * size, color)
	_add_line(position + Vector3.FORWARD * size, position + Vector3.BACK * size, color)
	_add_line(position + Vector3.DOWN * size, position + Vector3.UP * size, color)


func _add_line(from_position: Vector3, to_position: Vector3, color: Color) -> void:
	if from_position.distance_squared_to(to_position) < 0.0001:
		return

	mesh.surface_set_color(color)
	mesh.surface_add_vertex(from_position)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(to_position)
