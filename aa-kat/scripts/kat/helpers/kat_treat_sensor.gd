class_name KatTreatSensor
extends RefCounted

signal held_treat_entered(treat: Node3D)
signal held_treat_exited(treat: Node3D)
signal held_treat_fed(treat: Node3D)

# Owns the treat notice/feed areas and the little eating crumb particles.
# Movement and need changes stay in the autonomy controller.

var actor: Node3D

var _notice_area: Area3D
var _feed_area: Area3D
var _eating_particles: GPUParticles3D


func setup(owner: Node3D, notice_area_path: NodePath, feed_area_path: NodePath, particles_path: NodePath) -> void:
	actor = owner

	if actor == null:
		return

	_notice_area = actor.get_node_or_null(notice_area_path) as Area3D
	if _notice_area != null:
		_notice_area.body_entered.connect(_on_notice_body_entered)
		_notice_area.body_exited.connect(_on_notice_body_exited)

	_feed_area = actor.get_node_or_null(feed_area_path) as Area3D
	if _feed_area != null:
		_feed_area.body_entered.connect(_on_feed_body_entered)

	_eating_particles = actor.get_node_or_null(particles_path) as GPUParticles3D
	set_eating_particles(false)


func find_held_treat_in_notice_area(reject_timer: float) -> Node3D:
	if _notice_area == null or reject_timer > 0.0:
		return null

	for body in _notice_area.get_overlapping_bodies():
		if is_held_treat(body):
			return body as Node3D

	return null


func is_inside_notice(treat: Node3D) -> bool:
	return _area_has_body(_notice_area, treat)


func is_inside_feed(treat: Node3D) -> bool:
	return _area_has_body(_feed_area, treat)


func is_held_treat(node: Node) -> bool:
	if node == null or not node.is_in_group("fish_treat"):
		return false
	if node.has_method(&"is_consumed") and bool(node.call(&"is_consumed")):
		return false
	if not node.has_method(&"is_picked_up"):
		return false

	return bool(node.call(&"is_picked_up"))


func holder_for_treat(treat: Node) -> Node3D:
	if treat == null:
		return null
	if treat.has_method(&"get_holder_node"):
		var holder_value: Variant = treat.call(&"get_holder_node")
		if holder_value is Node3D:
			return holder_value as Node3D

	return null


func set_eating_particles(enabled: bool) -> void:
	if _eating_particles != null:
		_eating_particles.emitting = enabled


func _area_has_body(area: Area3D, body: Node3D) -> bool:
	if area == null or body == null:
		return false

	return area.get_overlapping_bodies().has(body)


func _on_notice_body_entered(body: Node3D) -> void:
	if is_held_treat(body):
		held_treat_entered.emit(body)


func _on_notice_body_exited(body: Node3D) -> void:
	if is_held_treat(body):
		held_treat_exited.emit(body)


func _on_feed_body_entered(body: Node3D) -> void:
	if is_held_treat(body):
		held_treat_fed.emit(body)
