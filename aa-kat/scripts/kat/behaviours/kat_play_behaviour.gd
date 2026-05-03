class_name KatPlayBehaviour
extends RefCounted

# Ball play and repeated pounce behaviour.

var brain: Variant


func setup(owner: Variant) -> void:
	brain = owner


func reset() -> void:
	brain._pounce_impulse_sent = false
	brain._play_reengage_timer = 0.0


func clear_reengage_timer() -> void:
	brain._play_reengage_timer = 0.0


func apply_arrival_effects(delta: float) -> void:
	if not bool(brain._pounce_impulse_sent):
		pounce_ball()
		brain._pounce_impulse_sent = true
		brain._play_reengage_timer = brain.play_pounce_recover_time
	brain.needs.chase(delta)


func update_chase_loop(delta: float) -> bool:
	if brain.current_state != &"play" or brain._target_node == null:
		return false

	if float(brain._play_reengage_timer) > 0.0:
		brain._play_reengage_timer = maxf(float(brain._play_reengage_timer) - delta, 0.0)
		return false

	if _target_horizontal_distance() > float(brain.play_reengage_distance):
		_restart_chase()
		return true

	brain._pounce_impulse_sent = false
	brain._play_state_animation()
	return false


func on_pounce_hitbox_body_entered(body: Node3D) -> void:
	if brain.current_state != &"play" or bool(brain._pounce_impulse_sent):
		return

	if body is RigidBody3D:
		_push_ball(body as RigidBody3D)
		brain._pounce_impulse_sent = true
		brain._play_reengage_timer = brain.play_pounce_recover_time
		brain._has_reached_target = true
		brain._play_state_animation()


func pounce_ball() -> void:
	var ball: RigidBody3D = _find_target_rigid_body()
	if ball == null:
		return

	_push_ball(ball)


func _restart_chase() -> void:
	brain._pounce_impulse_sent = false
	brain._has_reached_target = false
	brain._navigator.begin_target_movement(brain._target_node)
	brain._play_locomotion_animation()


func _target_horizontal_distance() -> float:
	var target_node: Node3D = brain._target_node as Node3D
	if target_node == null:
		return 0.0

	var target_position: Vector3 = target_node.global_position
	return Vector2(
		target_position.x - brain.global_position.x,
		target_position.z - brain.global_position.z
	).length()


func _push_ball(ball: RigidBody3D) -> void:
	brain._ball_play.push_ball(ball, brain.global_position, brain._navigator.get_visual_forward_direction())


func _find_target_rigid_body() -> RigidBody3D:
	var node: Node = brain._target_node as Node
	while node != null:
		if node is RigidBody3D:
			return node as RigidBody3D
		node = node.get_parent()
	return null
