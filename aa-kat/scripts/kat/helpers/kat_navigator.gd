class_name KatNavigator
extends RefCounted

# Handles "how do I get there?" for Kat. The controller decides the state, and
# this helper only moves/rotates Kat toward the active target.

var actor: Node3D
var body: CharacterBody3D
var rng: RandomNumberGenerator
var space_state: PhysicsDirectSpaceState3D
var move_speed: float = 0.85
var turn_speed: float = 6.0
var arrival_radius: float = 0.22
var elevated_arrival_radius: float = 0.18
var jump_start_distance: float = 0.95
var jump_speed: float = 1.05
var jump_arc_height: float = 0.65
var elevated_target_min_height: float = 0.18
var floor_height: float = 0.0
var moving_target_prediction_limit: float = 0.35
var wall_avoidance_distance: float = 1.15
var wall_avoidance_strength: float = 1.05
var explore_wander_radius: float = 0.45
var explore_wander_jitter: float = 1.75
var room_roam_min: Vector2 = Vector2(-3.2, -2.95)
var room_roam_max: Vector2 = Vector2(3.25, 2.9)
var detour_clearance: float = 0.65
var play_ball_approach_distance: float = 0.52
var play_ball_near_obstacle_distance: float = 0.68
var model_forward_yaw_offset_degrees: float = 90.0

var _target_node: Node3D
var _explore_wander_offset: Vector3 = Vector3.ZERO
var _slide_avoidance: Vector3 = Vector3.ZERO
var _has_detour: bool = false
var _detour_position: Vector3 = Vector3.ZERO
var _debug_rays: Array[Dictionary] = []
var _debug_snapshot: Dictionary = {}
var _movement_start_position: Vector3 = Vector3.ZERO
var _movement_progress: float = 0.0
var _jump_destination: Vector3 = Vector3.ZERO
var _target_requires_jump: bool = false
var _using_jump_arc: bool = false
var _jump_lands_before_target: bool = false


func setup(navigation_actor: Node3D, random: RandomNumberGenerator) -> void:
	actor = navigation_actor
	body = navigation_actor as CharacterBody3D
	rng = random


func begin_target_movement(target: Node3D) -> void:
	_target_node = target
	_target_requires_jump = _should_jump_to_target(_target_node)
	_using_jump_arc = false
	_jump_lands_before_target = false
	_clear_detour()

	# If Kat is already on furniture and needs a far-away/floor target, jump down
	# to an edge point first instead of sliding through the object.
	if _should_jump_down_before_target(_target_node):
		var landing_position: Vector3 = _jump_down_landing_position(_target_node.global_position)
		_start_jump_arc(landing_position, true)


func clear() -> void:
	_target_node = null
	_target_requires_jump = false
	_using_jump_arc = false
	_jump_lands_before_target = false
	_clear_detour()
	_stop_body_velocity()


func is_jumping() -> bool:
	return _using_jump_arc


func debug_snapshot() -> Dictionary:
	return _debug_snapshot.duplicate(true)


func clear_explore_wander_offset() -> void:
	_explore_wander_offset = Vector3.ZERO


func move_towards_target(delta: float, current_state: StringName, energy: float) -> bool:
	if actor == null or _target_node == null:
		return true

	# Jump movement is still hand-controlled because couch/tree jumps need a
	# readable arc instead of just sliding into the side of the furniture.
	if _using_jump_arc:
		return _move_along_jump_arc(delta)

	if _target_requires_jump:
		return _move_to_jump_start(delta, current_state, energy)

	var current_position: Vector3 = actor.global_position
	_begin_debug_frame()
	var target_position: Vector3 = _target_position_for_state(current_state, current_position, energy)
	target_position.y = current_position.y
	if current_state == &"explore" or current_state == &"idle":
		target_position += _update_explore_wander_offset(delta)
	target_position = _target_position_with_detour(current_position, target_position, current_state)
	_record_debug_line(&"target_line", current_position + Vector3.UP * 0.08, target_position + Vector3.UP * 0.08)
	_record_debug_detour(current_position)

	var offset: Vector3 = target_position - current_position
	if offset.length() <= arrival_radius:
		_finish_debug_frame()
		return true

	var direction: Vector3 = offset.normalized()
	var avoidance: Vector3 = _wall_avoidance_vector(current_position, direction)
	if avoidance.length_squared() > 0.001:
		direction = (direction + (avoidance * wall_avoidance_strength)).normalized()
		_record_debug_line(&"avoidance_line", current_position + Vector3.UP * 0.12, current_position + avoidance.normalized() * 0.55 + Vector3.UP * 0.12)
	if _slide_avoidance.length_squared() > 0.001:
		direction = (direction + (_slide_avoidance * wall_avoidance_strength)).normalized()
		_record_debug_line(&"avoidance_line", current_position + Vector3.UP * 0.16, current_position + _slide_avoidance.normalized() * 0.55 + Vector3.UP * 0.16)

	var state_speed: float = _speed_for_current_state(current_state, energy)
	_move_actor(direction, state_speed, delta, offset.length())
	_record_debug_line(&"movement_line", current_position + Vector3.UP * 0.2, current_position + direction * 0.7 + Vector3.UP * 0.2)
	_finish_debug_frame()
	face_direction(direction, delta)
	return false


func _target_position_for_state(current_state: StringName, current_position: Vector3, energy: float) -> Vector3:
	var target_position: Vector3 = _target_node.global_position
	if current_state == &"play":
		# During play, lead the ball slightly based on its velocity so Kat does
		# not keep chasing where the ball used to be. If the ball is beside
		# furniture, aim for a reachable side of it instead of the ball centre.
		var predicted_position: Vector3 = _predict_moving_target_position(target_position, current_state, current_position, energy)
		return _play_ball_approach_position(predicted_position, current_position)

	return target_position


func _target_position_with_detour(current_position: Vector3, target_position: Vector3, current_state: StringName) -> Vector3:
	if current_state != &"play":
		_clear_detour()
		return target_position

	if _has_detour:
		if current_position.distance_to(_detour_position) <= arrival_radius * 1.4:
			_clear_detour()
		elif not _path_is_blocked(current_position, _detour_position):
			return _detour_position
		else:
			_clear_detour()

	var hit: Dictionary = _path_obstacle_hit(current_position, target_position)
	if hit.is_empty():
		_clear_detour()
		return target_position

	_detour_position = _best_detour_position(current_position, target_position, hit)
	_has_detour = true
	return _detour_position


func _clear_detour() -> void:
	_has_detour = false
	_detour_position = Vector3.ZERO


func _play_ball_approach_position(ball_position: Vector3, current_position: Vector3) -> Vector3:
	var flat_ball_position: Vector3 = Vector3(ball_position.x, current_position.y, ball_position.z)
	var away_from_obstacle: Vector3 = _nearby_obstacle_away_vector(flat_ball_position)
	if away_from_obstacle.length_squared() < 0.001 and not _path_is_blocked(current_position, flat_ball_position):
		return flat_ball_position

	var from_ball_to_kat: Vector3 = current_position - flat_ball_position
	from_ball_to_kat.y = 0.0
	if from_ball_to_kat.length_squared() < 0.001:
		from_ball_to_kat = get_visual_forward_direction()
	from_ball_to_kat = from_ball_to_kat.normalized()

	var candidate_directions: Array[Vector3] = _play_approach_directions(from_ball_to_kat, away_from_obstacle)
	var approach_radii: Array[float] = [
		play_ball_approach_distance,
		play_ball_approach_distance + 0.35,
		play_ball_approach_distance + 0.65,
	]
	var best_position: Vector3 = flat_ball_position
	var best_score: float = INF
	var found_clear_floor: bool = false

	for radius in approach_radii:
		for direction in candidate_directions:
			var candidate: Vector3 = flat_ball_position + direction.normalized() * radius
			candidate.y = current_position.y
			candidate = _clamp_to_room_bounds(candidate)

			var score: float = current_position.distance_to(candidate)
			if _path_is_blocked(current_position, candidate):
				score += 4.0
			if _floor_position_is_clear(candidate, 0.26):
				found_clear_floor = true
			else:
				score += 20.0
			if away_from_obstacle.length_squared() > 0.001:
				score -= direction.normalized().dot(away_from_obstacle.normalized()) * 0.8

			if score < best_score:
				best_score = score
				best_position = candidate

	if not found_clear_floor:
		return flat_ball_position

	return best_position


func _play_approach_directions(from_ball_to_kat: Vector3, away_from_obstacle: Vector3) -> Array[Vector3]:
	var directions: Array[Vector3] = []
	_add_unique_direction(directions, from_ball_to_kat)
	_add_unique_direction(directions, Quaternion(Vector3.UP, deg_to_rad(45.0)) * from_ball_to_kat)
	_add_unique_direction(directions, Quaternion(Vector3.UP, deg_to_rad(-45.0)) * from_ball_to_kat)
	_add_unique_direction(directions, Quaternion(Vector3.UP, deg_to_rad(90.0)) * from_ball_to_kat)
	_add_unique_direction(directions, Quaternion(Vector3.UP, deg_to_rad(-90.0)) * from_ball_to_kat)

	if away_from_obstacle.length_squared() > 0.001:
		var away: Vector3 = away_from_obstacle.normalized()
		_add_unique_direction(directions, away)
		_add_unique_direction(directions, Quaternion(Vector3.UP, deg_to_rad(45.0)) * away)
		_add_unique_direction(directions, Quaternion(Vector3.UP, deg_to_rad(-45.0)) * away)

	return directions


func _add_unique_direction(directions: Array[Vector3], direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		return

	var normalized_direction: Vector3 = direction.normalized()
	for existing_direction in directions:
		var existing: Vector3 = existing_direction as Vector3
		if existing.dot(normalized_direction) > 0.96:
			return

	directions.append(normalized_direction)


func _predict_moving_target_position(target_position: Vector3, current_state: StringName, current_position: Vector3, energy: float) -> Vector3:
	var moving_body: RigidBody3D = _find_target_rigid_body()
	if moving_body == null:
		return target_position

	var target_velocity: Vector3 = moving_body.linear_velocity
	target_velocity.y = 0.0
	if target_velocity.length_squared() < 0.001 or moving_target_prediction_limit <= 0.0:
		return target_position

	var flat_distance: float = Vector2(
		target_position.x - current_position.x,
		target_position.z - current_position.z
	).length()
	var state_speed: float = maxf(_speed_for_current_state(current_state, energy), 0.01)
	var prediction_time: float = clampf(flat_distance / state_speed, 0.0, moving_target_prediction_limit)
	return _clamp_to_room_bounds(target_position + target_velocity * prediction_time)


func _find_target_rigid_body() -> RigidBody3D:
	var node: Node = _target_node
	while node != null:
		if node is RigidBody3D:
			return node as RigidBody3D
		node = node.get_parent()
	return null


func face_direction(direction: Vector3, delta: float) -> void:
	if actor == null or direction.length_squared() < 0.001:
		return

	var model_forward_offset: float = deg_to_rad(model_forward_yaw_offset_degrees)
	var target_yaw: float = atan2(-direction.x, -direction.z) + model_forward_offset
	actor.rotation.y = lerp_angle(actor.rotation.y, target_yaw, minf(turn_speed * delta, 1.0))


func get_visual_forward_direction() -> Vector3:
	if actor == null:
		return Vector3.FORWARD

	var forward: Vector3 = actor.global_transform.basis.x
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		return Vector3.FORWARD

	return forward.normalized()


func _should_jump_to_target(target: Node3D) -> bool:
	if actor == null or target == null:
		return false

	var height_delta: float = absf(target.global_position.y - actor.global_position.y)
	return height_delta >= elevated_target_min_height


func _should_jump_down_before_target(target: Node3D) -> bool:
	if actor == null or target == null:
		return false
	if actor.global_position.y <= floor_height + elevated_target_min_height:
		return false

	var target_position: Vector3 = target.global_position
	if target_position.y <= floor_height + elevated_target_min_height:
		return true

	var horizontal_distance: float = Vector2(
		target_position.x - actor.global_position.x,
		target_position.z - actor.global_position.z
	).length()
	return horizontal_distance > jump_start_distance


func _jump_down_landing_position(next_target_position: Vector3) -> Vector3:
	var direction: Vector3 = Vector3(
		next_target_position.x - actor.global_position.x,
		0.0,
		next_target_position.z - actor.global_position.z
	)
	if direction.length_squared() < 0.001:
		direction = get_visual_forward_direction()

	var landing_position: Vector3 = actor.global_position + direction.normalized() * jump_start_distance
	landing_position.y = floor_height
	return _clamp_to_room_bounds(landing_position)


func _clamp_to_room_bounds(position: Vector3) -> Vector3:
	var min_x: float = minf(room_roam_min.x, room_roam_max.x)
	var max_x: float = maxf(room_roam_min.x, room_roam_max.x)
	var min_z: float = minf(room_roam_min.y, room_roam_max.y)
	var max_z: float = maxf(room_roam_min.y, room_roam_max.y)
	return Vector3(
		clampf(position.x, min_x, max_x),
		position.y,
		clampf(position.z, min_z, max_z)
	)


func _move_to_jump_start(delta: float, current_state: StringName, energy: float) -> bool:
	var current_position: Vector3 = actor.global_position
	_begin_debug_frame()
	var target_position: Vector3 = _target_node.global_position
	if current_position.y > floor_height + elevated_target_min_height:
		_record_debug_line(&"target_line", current_position + Vector3.UP * 0.08, target_position + Vector3.UP * 0.08)
		_finish_debug_frame()
		_start_jump_arc(target_position, false)
		return _move_along_jump_arc(delta)

	# Walk to a safe edge point first, then do the jump arc onto the surface.
	var approach_position: Vector3 = _jump_approach_position(target_position, current_position)
	_record_debug_line(&"target_line", current_position + Vector3.UP * 0.08, approach_position + Vector3.UP * 0.08)
	var offset: Vector3 = approach_position - current_position
	var horizontal_distance: float = offset.length()

	if horizontal_distance <= arrival_radius:
		_finish_debug_frame()
		_start_jump_arc(target_position, false)
		return _move_along_jump_arc(delta)

	var direction: Vector3 = offset.normalized()
	if horizontal_distance > jump_start_distance + wall_avoidance_distance:
		var avoidance: Vector3 = _wall_avoidance_vector(current_position, direction)
		if avoidance.length_squared() > 0.001:
			direction = (direction + (avoidance * wall_avoidance_strength)).normalized()
		if _slide_avoidance.length_squared() > 0.001:
			direction = (direction + (_slide_avoidance * wall_avoidance_strength)).normalized()

	var state_speed: float = _speed_for_current_state(current_state, energy)
	_move_actor(direction, state_speed, delta, horizontal_distance)
	_record_debug_line(&"movement_line", current_position + Vector3.UP * 0.2, current_position + direction * 0.7 + Vector3.UP * 0.2)
	_finish_debug_frame()
	face_direction(direction, delta)
	return false


func _jump_approach_position(target_position: Vector3, current_position: Vector3) -> Vector3:
	var approach_position: Vector3 = Vector3(target_position.x, current_position.y, target_position.z)
	var target_name: StringName = StringName(_target_node.name)

	# These offsets are hand-tuned for the room layout. They keep Kat from
	# approaching the middle of a couch/tree collision before jumping.
	if target_name == &"CouchTarget":
		approach_position.x += jump_start_distance
	elif target_name == &"CatTreeSmallTarget":
		approach_position.x -= jump_start_distance
		approach_position.z += jump_start_distance * 0.45
	elif target_name == &"CatTreePerchTarget":
		approach_position.x -= jump_start_distance
		approach_position.z += jump_start_distance * 0.45
	elif target_name == &"RestTarget" or target_name == &"PillowTarget":
		approach_position.z += jump_start_distance
	else:
		var away_from_target: Vector3 = Vector3(
			current_position.x - target_position.x,
			0.0,
			current_position.z - target_position.z
		)
		if away_from_target.length_squared() < 0.001:
			away_from_target = get_visual_forward_direction()
		approach_position += away_from_target.normalized() * jump_start_distance

	approach_position.y = current_position.y
	return _clamp_to_room_bounds(approach_position)


func _start_jump_arc(destination: Vector3, lands_before_target: bool) -> void:
	_stop_body_velocity()
	_movement_start_position = actor.global_position
	_movement_progress = 0.0
	_jump_destination = destination
	_jump_lands_before_target = lands_before_target
	_using_jump_arc = true


func _move_along_jump_arc(delta: float) -> bool:
	_stop_body_velocity()
	var target_position: Vector3 = _jump_destination
	var start_flat: Vector3 = Vector3(_movement_start_position.x, 0.0, _movement_start_position.z)
	var target_flat: Vector3 = Vector3(target_position.x, 0.0, target_position.z)
	var horizontal_distance: float = start_flat.distance_to(target_flat)
	var vertical_distance: float = absf(target_position.y - _movement_start_position.y)
	var travel_distance: float = maxf(horizontal_distance, vertical_distance)

	if travel_distance <= elevated_arrival_radius:
		return _complete_jump_arc(target_position)

	var progress_step: float = (jump_speed * delta) / travel_distance
	_movement_progress = minf(_movement_progress + progress_step, 1.0)

	# Simple parabolic lift. It is not real physics, but it reads as a jump and
	# avoids Kat phasing straight through furniture vertically.
	var base_position: Vector3 = _movement_start_position.lerp(target_position, _movement_progress)
	var arc_offset: float = sin(_movement_progress * PI) * jump_arc_height
	actor.global_position = Vector3(base_position.x, base_position.y + arc_offset, base_position.z)

	var face_target: Vector3 = target_position - actor.global_position
	face_target.y = 0.0
	face_direction(face_target, delta)

	if _movement_progress >= 1.0 or actor.global_position.distance_to(target_position) <= elevated_arrival_radius:
		return _complete_jump_arc(target_position)

	return false


func _complete_jump_arc(destination: Vector3) -> bool:
	actor.global_position = destination
	_using_jump_arc = false
	_stop_body_velocity()

	if _jump_lands_before_target:
		_jump_lands_before_target = false
		_target_requires_jump = _should_jump_to_target(_target_node)
		return false

	_target_requires_jump = false
	return true


func _move_actor(direction: Vector3, speed: float, delta: float, distance_to_target: float) -> void:
	if actor == null or direction.length_squared() < 0.001:
		return

	if body == null:
		var step: float = minf(speed * delta, distance_to_target)
		actor.global_position += direction * step
		return

	var safe_delta: float = maxf(delta, 0.001)
	var frame_speed: float = minf(speed, distance_to_target / safe_delta)
	body.velocity = Vector3(direction.x * frame_speed, 0.0, direction.z * frame_speed)
	body.move_and_slide()
	_update_slide_avoidance(direction, delta)
	body.velocity = Vector3.ZERO


func _stop_body_velocity() -> void:
	if body != null:
		body.velocity = Vector3.ZERO
	_slide_avoidance = Vector3.ZERO


func _update_slide_avoidance(move_direction: Vector3, delta: float) -> void:
	if body == null:
		_slide_avoidance = Vector3.ZERO
		return

	var steer: Vector3 = Vector3.ZERO
	for i in range(body.get_slide_collision_count()):
		var collision: KinematicCollision3D = body.get_slide_collision(i)
		if collision == null:
			continue

		var normal: Vector3 = collision.get_normal()
		normal.y = 0.0
		if normal.length_squared() < 0.001:
			continue

		normal = normal.normalized()
		steer += _avoidance_from_normal(normal, move_direction, 1.0)

	if steer.length_squared() > 0.001:
		_slide_avoidance = steer.normalized()
		return

	var decay: float = minf(delta * 5.0, 1.0)
	_slide_avoidance = _slide_avoidance.lerp(Vector3.ZERO, decay)


func _speed_for_current_state(current_state: StringName, energy: float) -> float:
	var state_speed: float = move_speed
	if current_state == &"play" or current_state == &"explore":
		state_speed *= 1.12
	if energy < 0.25:
		state_speed *= 0.65
	return state_speed


func _update_explore_wander_offset(delta: float) -> Vector3:
	var jitter: Vector2 = Vector2(
		rng.randf_range(-1.0, 1.0),
		rng.randf_range(-1.0, 1.0)
	)
	var offset_2d: Vector2 = Vector2(_explore_wander_offset.x, _explore_wander_offset.z)
	offset_2d += jitter * explore_wander_jitter * delta
	if offset_2d.length_squared() > explore_wander_radius * explore_wander_radius:
		offset_2d = offset_2d.normalized() * explore_wander_radius

	_explore_wander_offset = Vector3(offset_2d.x, 0.0, offset_2d.y)
	return _explore_wander_offset


func _wall_avoidance_vector(origin: Vector3, direction: Vector3) -> Vector3:
	if space_state == null or direction.length_squared() < 0.001:
		return Vector3.ZERO

	# Local steering inspired by the old obstacle-avoidance test project: cast a
	# few feelers ahead, then blend away from the hit normal and around its edge.
	var feeler: Vector3 = direction.normalized() * wall_avoidance_distance
	var rays: Array[Vector3] = [
		feeler,
		Quaternion(Vector3.UP, deg_to_rad(28.0)) * feeler,
		Quaternion(Vector3.UP, deg_to_rad(-28.0)) * feeler,
		Quaternion(Vector3.UP, deg_to_rad(55.0)) * feeler * 0.72,
		Quaternion(Vector3.UP, deg_to_rad(-55.0)) * feeler * 0.72,
	]

	var avoidance: Vector3 = Vector3.ZERO
	var ray_origin: Vector3 = origin + Vector3.UP * 0.22
	for ray in rays:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray)
		query.collision_mask = _navigation_collision_mask()
		query.collide_with_areas = false
		query.collide_with_bodies = true
		if body != null:
			query.exclude = [body.get_rid()]
		var hit: Dictionary = space_state.intersect_ray(query)
		_record_debug_ray(ray_origin, ray_origin + ray, hit)
		if hit.is_empty():
			continue

		var hit_position: Vector3 = hit.get("position", ray_origin) as Vector3
		var hit_normal: Vector3 = hit.get("normal", Vector3.ZERO) as Vector3
		hit_normal.y = 0.0
		if hit_normal.length_squared() < 0.001:
			continue

		var hit_distance: float = ray_origin.distance_to(hit_position)
		var proximity: float = clampf(1.0 - (hit_distance / ray.length()), 0.0, 1.0)
		avoidance += _avoidance_from_normal(hit_normal.normalized(), direction, maxf(proximity, 0.15))

	return avoidance


func _path_is_blocked(from_position: Vector3, to_position: Vector3) -> bool:
	return not _path_obstacle_hit(from_position, to_position).is_empty()


func _floor_position_is_clear(position: Vector3, radius: float) -> bool:
	if space_state == null:
		return true

	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = radius

	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(
		Basis.IDENTITY,
		Vector3(position.x, floor_height + radius + 0.08, position.z)
	)
	query.collision_mask = _navigation_collision_mask()
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if body != null:
		query.exclude = [body.get_rid()]

	var hits: Array[Dictionary] = space_state.intersect_shape(query, 1)
	return hits.is_empty()


func _nearby_obstacle_away_vector(position: Vector3) -> Vector3:
	if space_state == null:
		return Vector3.ZERO

	var directions: Array[Vector3] = [
		Vector3.FORWARD,
		Vector3.BACK,
		Vector3.LEFT,
		Vector3.RIGHT,
		Vector3(1.0, 0.0, 1.0).normalized(),
		Vector3(-1.0, 0.0, 1.0).normalized(),
		Vector3(1.0, 0.0, -1.0).normalized(),
		Vector3(-1.0, 0.0, -1.0).normalized(),
	]
	var origin: Vector3 = Vector3(position.x, floor_height + 0.24, position.z)
	var away: Vector3 = Vector3.ZERO

	for direction in directions:
		var ray_end: Vector3 = origin + direction * play_ball_near_obstacle_distance
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, ray_end)
		query.collision_mask = _navigation_collision_mask()
		query.collide_with_areas = false
		query.collide_with_bodies = true
		if body != null:
			query.exclude = [body.get_rid()]

		var hit: Dictionary = space_state.intersect_ray(query)
		_record_debug_ray(origin, ray_end, hit)
		if hit.is_empty():
			continue

		var hit_position: Vector3 = hit.get("position", ray_end) as Vector3
		var hit_distance: float = origin.distance_to(hit_position)
		var proximity: float = clampf(1.0 - (hit_distance / play_ball_near_obstacle_distance), 0.0, 1.0)
		away -= direction.normalized() * maxf(proximity, 0.25)

	if away.length_squared() < 0.001:
		return Vector3.ZERO
	return away.normalized()


func _path_obstacle_hit(from_position: Vector3, to_position: Vector3) -> Dictionary:
	if space_state == null:
		return {}

	var flat_offset: Vector3 = Vector3(
		to_position.x - from_position.x,
		0.0,
		to_position.z - from_position.z
	)
	var distance: float = flat_offset.length()
	if distance <= arrival_radius:
		return {}

	var direction: Vector3 = flat_offset / distance
	var side: Vector3 = Vector3(direction.z, 0.0, -direction.x)
	var side_offsets: Array[float] = [0.0, 0.26, -0.26]
	var heights: Array[float] = [0.24, 0.36]
	var best_hit: Dictionary = {}
	var best_distance: float = INF

	for height in heights:
		for side_offset in side_offsets:
			var ray_start: Vector3 = Vector3(from_position.x, floor_height + height, from_position.z) + side * side_offset
			var ray_end: Vector3 = ray_start + direction * distance
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
			query.collision_mask = _navigation_collision_mask()
			query.collide_with_areas = false
			query.collide_with_bodies = true
			if body != null:
				query.exclude = [body.get_rid()]

			var hit: Dictionary = space_state.intersect_ray(query)
			_record_debug_ray(ray_start, ray_end, hit)
			if hit.is_empty():
				continue

			var hit_position: Vector3 = hit.get("position", ray_start) as Vector3
			var hit_distance: float = ray_start.distance_to(hit_position)
			if hit_distance < best_distance:
				best_hit = hit
				best_distance = hit_distance

	return best_hit


func _best_detour_position(from_position: Vector3, target_position: Vector3, hit: Dictionary) -> Vector3:
	var candidates: Array[Vector3] = _detour_candidates(from_position, target_position, hit)
	var best_position: Vector3 = _detour_around_hit(from_position, target_position, hit)
	var best_score: float = INF

	for candidate in candidates:
		var checked_candidate: Vector3 = candidate as Vector3
		checked_candidate.y = from_position.y
		checked_candidate = _clamp_to_room_bounds(checked_candidate)
		if not _floor_position_is_clear(checked_candidate, 0.28):
			continue
		if _path_is_blocked(from_position, checked_candidate):
			continue

		var score: float = from_position.distance_to(checked_candidate)
		score += checked_candidate.distance_to(target_position) * 0.65
		if _path_is_blocked(checked_candidate, target_position):
			score += 1.75
		else:
			score -= 2.25

		if score < best_score:
			best_score = score
			best_position = checked_candidate

	return best_position


func _detour_candidates(from_position: Vector3, target_position: Vector3, hit: Dictionary) -> Array[Vector3]:
	var candidates: Array[Vector3] = []
	var hit_position: Vector3 = hit.get("position", from_position) as Vector3
	var normal: Vector3 = hit.get("normal", Vector3.ZERO) as Vector3
	normal.y = 0.0
	if normal.length_squared() < 0.001:
		normal = from_position - hit_position
		normal.y = 0.0
	if normal.length_squared() < 0.001:
		normal = get_visual_forward_direction()
	normal = normal.normalized()

	var desired_direction: Vector3 = target_position - from_position
	desired_direction.y = 0.0
	if desired_direction.length_squared() < 0.001:
		desired_direction = get_visual_forward_direction()
	desired_direction = desired_direction.normalized()

	var tangent: Vector3 = _best_tangent_for_direction(normal, desired_direction)
	_add_detour_ring(candidates, hit_position, normal, tangent, from_position.y, detour_clearance)
	_add_detour_ring(candidates, hit_position, normal, tangent, from_position.y, detour_clearance * 1.55)

	var target_away: Vector3 = _nearby_obstacle_away_vector(target_position)
	if target_away.length_squared() > 0.001:
		_add_detour_ring(candidates, target_position, target_away, tangent, from_position.y, play_ball_approach_distance + 0.25)

	return candidates


func _add_detour_ring(candidates: Array[Vector3], base_position: Vector3, normal: Vector3, tangent: Vector3, y: float, radius: float) -> void:
	var directions: Array[Vector3] = []
	_add_unique_direction(directions, normal)
	_add_unique_direction(directions, -normal)
	_add_unique_direction(directions, tangent)
	_add_unique_direction(directions, -tangent)
	_add_unique_direction(directions, normal + tangent)
	_add_unique_direction(directions, normal - tangent)

	for direction in directions:
		var detour_direction: Vector3 = direction as Vector3
		var candidate: Vector3 = base_position + detour_direction.normalized() * radius
		candidate.y = y
		candidates.append(candidate)


func _detour_around_hit(from_position: Vector3, target_position: Vector3, hit: Dictionary) -> Vector3:
	var hit_position: Vector3 = hit.get("position", from_position) as Vector3
	var normal: Vector3 = hit.get("normal", Vector3.ZERO) as Vector3
	normal.y = 0.0
	if normal.length_squared() < 0.001:
		normal = (from_position - hit_position)
		normal.y = 0.0
	if normal.length_squared() < 0.001:
		normal = get_visual_forward_direction()
	normal = normal.normalized()

	var desired_direction: Vector3 = target_position - from_position
	desired_direction.y = 0.0
	if desired_direction.length_squared() < 0.001:
		desired_direction = get_visual_forward_direction()
	desired_direction = desired_direction.normalized()

	var tangent: Vector3 = _best_tangent_for_direction(normal, desired_direction)
	var candidate_a: Vector3 = hit_position + normal * 0.35 + tangent * detour_clearance
	var candidate_b: Vector3 = hit_position + normal * 0.35 - tangent * detour_clearance
	candidate_a.y = from_position.y
	candidate_b.y = from_position.y

	if candidate_a.distance_to(target_position) <= candidate_b.distance_to(target_position):
		return _clamp_to_room_bounds(candidate_a)
	return _clamp_to_room_bounds(candidate_b)


func _begin_debug_frame() -> void:
	_debug_rays.clear()
	_debug_snapshot = {
		"rays": _debug_rays,
	}


func _finish_debug_frame() -> void:
	_debug_snapshot["rays"] = _debug_rays.duplicate(true)
	if _has_detour:
		_debug_snapshot["detour_point"] = _detour_position


func _record_debug_line(key: StringName, from_position: Vector3, to_position: Vector3) -> void:
	_debug_snapshot[key] = {
		"from": from_position,
		"to": to_position,
	}


func _record_debug_detour(from_position: Vector3) -> void:
	if not _has_detour:
		return

	_debug_snapshot["detour_line"] = {
		"from": from_position + Vector3.UP * 0.12,
		"to": _detour_position + Vector3.UP * 0.12,
	}
	_debug_snapshot["detour_point"] = _detour_position


func _record_debug_ray(from_position: Vector3, to_position: Vector3, hit: Dictionary) -> void:
	if _debug_rays.size() >= 36:
		return

	var ray_data: Dictionary = {
		"from": from_position,
		"to": to_position,
		"did_hit": not hit.is_empty(),
	}
	if not hit.is_empty():
		ray_data["hit"] = hit.get("position", to_position)

	_debug_rays.append(ray_data)


func _navigation_collision_mask() -> int:
	if body != null:
		return body.collision_mask
	return 1


func _avoidance_from_normal(normal: Vector3, desired_direction: Vector3, strength: float) -> Vector3:
	var tangent: Vector3 = _best_tangent_for_direction(normal, desired_direction)
	return (normal * strength) + (tangent * strength * 0.75)


func _best_tangent_for_direction(normal: Vector3, desired_direction: Vector3) -> Vector3:
	var tangent_a: Vector3 = Vector3(normal.z, 0.0, -normal.x).normalized()
	var tangent_b: Vector3 = -tangent_a
	if tangent_a.dot(desired_direction) >= tangent_b.dot(desired_direction):
		return tangent_a
	return tangent_b
