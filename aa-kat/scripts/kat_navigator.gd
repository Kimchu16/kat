class_name KatNavigator
extends RefCounted

# Handles "how do I get there?" for Kat. The controller decides the state, and
# this helper only moves/rotates the Node3D toward the active target.

var actor: Node3D
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
var wall_avoidance_distance: float = 0.95
var wall_avoidance_strength: float = 0.75
var explore_wander_radius: float = 0.45
var explore_wander_jitter: float = 1.75
var room_roam_min: Vector2 = Vector2(-3.2, -2.95)
var room_roam_max: Vector2 = Vector2(3.25, 2.9)
var model_forward_yaw_offset_degrees: float = 90.0

var _target_node: Node3D
var _explore_wander_offset: Vector3 = Vector3.ZERO
var _movement_start_position: Vector3 = Vector3.ZERO
var _movement_progress: float = 0.0
var _jump_destination: Vector3 = Vector3.ZERO
var _target_requires_jump: bool = false
var _using_jump_arc: bool = false
var _jump_lands_before_target: bool = false


func setup(navigation_actor: Node3D, random: RandomNumberGenerator) -> void:
	actor = navigation_actor
	rng = random


func begin_target_movement(target: Node3D) -> void:
	_target_node = target
	_target_requires_jump = _should_jump_to_target(_target_node)
	_using_jump_arc = false
	_jump_lands_before_target = false

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


func is_jumping() -> bool:
	return _using_jump_arc


func clear_explore_wander_offset() -> void:
	_explore_wander_offset = Vector3.ZERO


func move_towards_target(delta: float, current_state: StringName, energy: float) -> bool:
	if actor == null or _target_node == null:
		return true

	# Jump movement is separate from normal movement because the actor is a
	# Node3D, not a physics body that can naturally step up and down.
	if _using_jump_arc:
		return _move_along_jump_arc(delta)

	if _target_requires_jump:
		return _move_to_jump_start(delta, current_state, energy)

	var current_position: Vector3 = actor.global_position
	var target_position: Vector3 = _target_position_for_state(current_state, current_position, energy)
	target_position.y = current_position.y
	if current_state == &"explore" or current_state == &"idle":
		target_position += _update_explore_wander_offset(delta)

	var offset: Vector3 = target_position - current_position
	if offset.length() <= arrival_radius:
		return true

	var direction: Vector3 = offset.normalized()
	var avoidance: Vector3 = _wall_avoidance_vector(current_position, direction)
	if avoidance.length_squared() > 0.001:
		direction = (direction + (avoidance * wall_avoidance_strength)).normalized()

	var state_speed: float = _speed_for_current_state(current_state, energy)
	var step: float = minf(state_speed * delta, offset.length())
	actor.global_position = current_position + (direction * step)
	face_direction(direction, delta)
	return false


func _target_position_for_state(current_state: StringName, current_position: Vector3, energy: float) -> Vector3:
	var target_position: Vector3 = _target_node.global_position
	if current_state == &"play":
		# During play, lead the ball slightly based on its velocity so Kat does
		# not keep chasing where the ball used to be.
		return _predict_moving_target_position(target_position, current_state, current_position, energy)

	return target_position


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
	var target_position: Vector3 = _target_node.global_position
	if current_position.y > floor_height + elevated_target_min_height:
		_start_jump_arc(target_position, false)
		return _move_along_jump_arc(delta)

	# Walk to a safe edge point first, then do the jump arc onto the surface.
	var approach_position: Vector3 = _jump_approach_position(target_position, current_position)
	var offset: Vector3 = approach_position - current_position
	var horizontal_distance: float = offset.length()

	if horizontal_distance <= arrival_radius:
		_start_jump_arc(target_position, false)
		return _move_along_jump_arc(delta)

	var direction: Vector3 = offset.normalized()
	if horizontal_distance > jump_start_distance + wall_avoidance_distance:
		var avoidance: Vector3 = _wall_avoidance_vector(current_position, direction)
		if avoidance.length_squared() > 0.001:
			direction = (direction + (avoidance * wall_avoidance_strength)).normalized()

	var state_speed: float = _speed_for_current_state(current_state, energy)
	var approach_step: float = minf(state_speed * delta, horizontal_distance)
	actor.global_position = current_position + (direction * approach_step)
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
	_movement_start_position = actor.global_position
	_movement_progress = 0.0
	_jump_destination = destination
	_jump_lands_before_target = lands_before_target
	_using_jump_arc = true


func _move_along_jump_arc(delta: float) -> bool:
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

	if _jump_lands_before_target:
		_jump_lands_before_target = false
		_target_requires_jump = _should_jump_to_target(_target_node)
		return false

	_target_requires_jump = false
	return true


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

	# Three short feelers give enough warning for walls/furniture without making
	# Kat look like it is bouncing off invisible barriers.
	var feeler: Vector3 = direction.normalized() * wall_avoidance_distance
	var rays: Array[Vector3] = [
		feeler,
		Quaternion(Vector3.UP, deg_to_rad(30.0)) * feeler,
		Quaternion(Vector3.UP, deg_to_rad(-30.0)) * feeler,
	]

	var avoidance: Vector3 = Vector3.ZERO
	for ray in rays:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + ray)
		var hit: Dictionary = space_state.intersect_ray(query)
		if hit.is_empty():
			continue

		var hit_position: Vector3 = hit.get("position", origin) as Vector3
		var hit_normal: Vector3 = hit.get("normal", Vector3.ZERO) as Vector3
		var hit_distance: float = origin.distance_to(hit_position)
		var proximity: float = clampf(1.0 - (hit_distance / wall_avoidance_distance), 0.0, 1.0)
		if hit_normal.length_squared() > 0.001:
			avoidance += hit_normal * proximity

	return avoidance
