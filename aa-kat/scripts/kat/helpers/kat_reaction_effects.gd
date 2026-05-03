class_name KatReactionEffects
extends RefCounted

# Keeps the small visual reactions in one place so the main controller only
# decides when an effect should start or stop.

var actor: Node3D

var _sleep_z_root: Node3D
var _bowl_eating_particles: GPUParticles3D
var _sleep_z_base_positions: Dictionary = {}
var _sleep_z_time: float = 0.0


func setup(owner: Node3D, sleep_zs_path: NodePath, bowl_particles_path: NodePath) -> void:
	actor = owner
	if actor == null:
		return

	_sleep_z_root = actor.get_node_or_null(sleep_zs_path) as Node3D
	_bowl_eating_particles = actor.get_node_or_null(bowl_particles_path) as GPUParticles3D
	_cache_sleep_z_positions()
	stop_all()


func update(delta: float) -> void:
	if _sleep_z_root == null or not _sleep_z_root.visible:
		return

	_sleep_z_time += delta
	_animate_sleep_zs()


func set_sleep_zs(enabled: bool) -> void:
	if _sleep_z_root == null:
		return

	if enabled and not _sleep_z_root.visible:
		_sleep_z_time = 0.0
	_sleep_z_root.visible = enabled


func set_bowl_eating_particles(enabled: bool) -> void:
	if _bowl_eating_particles != null:
		_bowl_eating_particles.emitting = enabled


func stop_state_loops() -> void:
	set_sleep_zs(false)
	set_bowl_eating_particles(false)


func stop_all() -> void:
	stop_state_loops()


func _cache_sleep_z_positions() -> void:
	_sleep_z_base_positions.clear()
	if _sleep_z_root == null:
		return

	for child_node in _sleep_z_root.get_children():
		var child: Node3D = child_node as Node3D
		if child != null:
			_sleep_z_base_positions[child] = child.position


func _animate_sleep_zs() -> void:
	var index: int = 0
	for child_node in _sleep_z_root.get_children():
		var child: Node3D = child_node as Node3D
		if child == null:
			continue

		var base_position: Vector3 = child.position
		var base_value: Variant = _sleep_z_base_positions.get(child)
		if base_value is Vector3:
			base_position = base_value as Vector3

		var bob_amount: float = sin(_sleep_z_time * 2.1 + float(index) * 0.85) * 0.025
		child.position = base_position + Vector3(0.0, bob_amount, 0.0)
		index += 1
