class_name KatBallPlay
extends RefCounted

# Ball-only pounce logic. This keeps furniture/wall steering out of the main
# autonomy flow.

var actor: Node3D
var pounce_impulse: float = 0.65
var play_bounds_min: Vector2 = Vector2(-3.15, -3.15)
var play_bounds_max: Vector2 = Vector2(3.15, 3.15)
var edge_turn_margin: float = 0.55
var inward_push_bias: float = 0.85
var obstacle_avoidance_distance: float = 0.9
var obstacle_avoidance_bias: float = 0.8
var obstacle_avoidance_mask: int = 1


func setup(owner: Node3D) -> void:
	actor = owner


func push_ball(ball: RigidBody3D, actor_position: Vector3, fallback_forward: Vector3) -> void:
	if ball == null:
		return

	var impulse_direction: Vector3 = ball.global_position - actor_position
	impulse_direction.y = 0.08
	if impulse_direction.length_squared() < 0.001:
		impulse_direction = fallback_forward + Vector3.UP * 0.08

	impulse_direction = _steer_impulse(ball, impulse_direction)
	ball.apply_central_impulse(impulse_direction.normalized() * pounce_impulse)


func _steer_impulse(ball: RigidBody3D, impulse_direction: Vector3) -> Vector3:
	var steered_impulse: Vector3 = _steer_from_bounds(ball.global_position, impulse_direction)
	return _steer_from_obstacles(ball, steered_impulse)


func _steer_from_bounds(ball_position: Vector3, impulse_direction: Vector3) -> Vector3:
	var horizontal_impulse: Vector3 = Vector3(impulse_direction.x, 0.0, impulse_direction.z)
	var inward_direction: Vector3 = Vector3.ZERO

	if ball_position.x <= play_bounds_min.x + edge_turn_margin and horizontal_impulse.x < 0.0:
		inward_direction.x += 1.0
	if ball_position.x >= play_bounds_max.x - edge_turn_margin and horizontal_impulse.x > 0.0:
		inward_direction.x -= 1.0
	if ball_position.z <= play_bounds_min.y + edge_turn_margin and horizontal_impulse.z < 0.0:
		inward_direction.z += 1.0
	if ball_position.z >= play_bounds_max.y - edge_turn_margin and horizontal_impulse.z > 0.0:
		inward_direction.z -= 1.0

	if inward_direction.length_squared() < 0.001:
		return impulse_direction

	var inward_normal: Vector3 = inward_direction.normalized()
	if horizontal_impulse.length_squared() < 0.001:
		horizontal_impulse = inward_normal
	else:
		horizontal_impulse = horizontal_impulse.normalized().lerp(inward_normal, inward_push_bias)
		if horizontal_impulse.length_squared() < 0.001:
			horizontal_impulse = inward_normal

	return Vector3(horizontal_impulse.x, impulse_direction.y, horizontal_impulse.z)


func _steer_from_obstacles(ball: RigidBody3D, impulse_direction: Vector3) -> Vector3:
	var horizontal_impulse: Vector3 = Vector3(impulse_direction.x, 0.0, impulse_direction.z)
	if ball == null or horizontal_impulse.length_squared() < 0.001:
		return impulse_direction

	var avoidance: Vector3 = _obstacle_avoidance_vector(ball, horizontal_impulse.normalized())
	if avoidance.length_squared() < 0.001:
		return impulse_direction

	var steer_amount: float = clampf(obstacle_avoidance_bias, 0.0, 1.0)
	horizontal_impulse = horizontal_impulse.normalized().lerp(avoidance.normalized(), steer_amount)
	if horizontal_impulse.length_squared() < 0.001:
		horizontal_impulse = avoidance.normalized()

	return Vector3(horizontal_impulse.x, impulse_direction.y, horizontal_impulse.z)


func _obstacle_avoidance_vector(ball: RigidBody3D, direction: Vector3) -> Vector3:
	if actor == null or direction.length_squared() < 0.001 or obstacle_avoidance_distance <= 0.0:
		return Vector3.ZERO

	var world: World3D = actor.get_world_3d()
	if world == null:
		return Vector3.ZERO

	var origin: Vector3 = ball.global_position + Vector3.UP * 0.08
	var feeler: Vector3 = direction.normalized() * obstacle_avoidance_distance
	var rays: Array[Vector3] = [
		feeler,
		Quaternion(Vector3.UP, deg_to_rad(22.0)) * feeler,
		Quaternion(Vector3.UP, deg_to_rad(-22.0)) * feeler,
	]

	var avoidance: Vector3 = Vector3.ZERO
	for ray in rays:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + ray)
		query.collision_mask = obstacle_avoidance_mask
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.exclude = [ball.get_rid()]

		var hit: Dictionary = world.direct_space_state.intersect_ray(query)
		if hit.is_empty():
			continue

		var hit_position: Vector3 = hit.get("position", origin) as Vector3
		var hit_normal: Vector3 = hit.get("normal", Vector3.ZERO) as Vector3
		hit_normal.y = 0.0
		if hit_normal.length_squared() < 0.001:
			continue

		var hit_distance: float = origin.distance_to(hit_position)
		var proximity: float = clampf(1.0 - (hit_distance / obstacle_avoidance_distance), 0.0, 1.0)
		avoidance += hit_normal.normalized() * maxf(proximity, 0.25)

	return avoidance
