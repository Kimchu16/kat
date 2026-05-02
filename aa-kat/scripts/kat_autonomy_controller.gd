class_name KatAutonomyController
extends Node3D

@export var autonomy_enabled: bool = true
@export var target_root_path: NodePath = NodePath("../KatTargets")
@export var move_speed: float = 0.85
@export var turn_speed: float = 6.0
@export var arrival_radius: float = 0.22
@export var pounce_impulse: float = 0.65
@export var ball_play_bounds_min: Vector2 = Vector2(-3.15, -3.15)
@export var ball_play_bounds_max: Vector2 = Vector2(3.15, 3.15)
@export var ball_edge_turn_margin: float = 0.55
@export_range(0.0, 1.0, 0.05) var ball_inward_push_bias: float = 0.85
@export var wall_avoidance_distance: float = 0.95
@export var wall_avoidance_strength: float = 0.75
@export var explore_wander_radius: float = 0.45
@export var explore_wander_jitter: float = 1.75
@export var room_roam_min: Vector2 = Vector2(-3.2, -2.95)
@export var room_roam_max: Vector2 = Vector2(3.25, 2.9)
@export var roam_pick_min_distance: float = 1.35
@export var roam_procedural_chance: float = 0.75
@export_range(0.0, 1.0, 0.01) var state_selection_noise: float = 0.35
@export_range(0.0, 1.0, 0.01) var state_repeat_penalty: float = 0.42
@export_range(0.0, 1.0, 0.01) var state_recent_penalty: float = 0.82
@export var state_fatigue_decay_per_second: float = 0.08
@export var state_fatigue_on_use: float = 0.7
@export var min_decision_time: float = 4.0
@export var max_decision_time: float = 8.5
@export var show_debug_label: bool = true
@export_range(-180.0, 180.0, 1.0) var model_forward_yaw_offset_degrees: float = 90.0

const ACTION_ANIMATIONS: Dictionary = {
	&"idle": &"Idle",
	&"eat": &"Eat",
	&"rest": &"Sleep",
	&"play": &"Pounce",
	&"explore": &"Run",
}

const LOCOMOTION_ANIMATION: StringName = &"Run"
const ATTENTION_ANIMATION: StringName = &"AttentionCaught"
const PHASE_ENTER: StringName = &"enter"
const PHASE_IDLE: StringName = &"idle"
const PHASE_EXIT: StringName = &"exit"
const PHASED_ACTION_ANIMATIONS: Dictionary = {
	&"rest": {
		PHASE_ENTER: &"Sleep_Enter",
		PHASE_IDLE: &"Sleep_Idle",
		PHASE_EXIT: &"Sleep_Exit",
	},
}

var needs: KatNeeds = KatNeeds.new()
var current_state: StringName = &"idle"

var _targets: Dictionary = {}
var _target_node: Node3D
var _animation_player: AnimationPlayer
var _pounce_hitbox: Area3D
var _debug_label: Label3D
var _space_state: PhysicsDirectSpaceState3D
var _explore_wander_offset: Vector3 = Vector3.ZERO
var _roam_target: Node3D
var _state_fatigue: Dictionary = {}
var _state_history: Array[StringName] = []
var _decision_timer: float = 0.0
var _pounce_impulse_sent: bool = false
var _has_reached_target: bool = true
var _is_exiting_state: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_animation_player = get_node_or_null("AnimationPlayer") as AnimationPlayer
	if _animation_player != null:
		_animation_player.animation_finished.connect(_on_animation_finished)
	_pounce_hitbox = get_node_or_null("PounceHitbox") as Area3D
	if _pounce_hitbox != null:
		_pounce_hitbox.body_entered.connect(_on_pounce_hitbox_body_entered)
	_space_state = get_world_3d().direct_space_state if get_world_3d() != null else null
	_setup_roam_target()
	_collect_targets()
	_setup_debug_label()
	needs.changed.connect(_on_needs_changed)
	_choose_next_state()


func _process(delta: float) -> void:
	if not autonomy_enabled:
		return

	_decay_state_fatigue(delta)
	needs.tick(delta)
	if _is_exiting_state:
		return

	if _target_node == null:
		_decision_timer -= delta
		if _decision_timer <= 0.0:
			_choose_next_state()
		return

	if not _has_reached_target:
		var arrived: bool = _move_towards_target(delta)
		if arrived:
			_has_reached_target = true
			_decision_timer = _rng.randf_range(min_decision_time, max_decision_time)
			_play_state_animation()
			_apply_arrival_effects(delta)
		return

	_apply_arrival_effects(delta)
	_decision_timer -= delta
	if _decision_timer <= 0.0:
		_finish_current_state()


func _collect_targets() -> void:
	_targets.clear()
	var target_root: Node = get_node_or_null(target_root_path)
	if target_root == null:
		return

	for child in target_root.get_children():
		if child is Node3D:
			_targets[child.name] = child

	var play_target: Node3D = get_node_or_null("../Ball/PlayTarget") as Node3D
	if play_target != null:
		_targets[&"PlayTarget"] = play_target


func _choose_next_state() -> void:
	var scored_actions: Dictionary = _score_actions()
	var selected_state: StringName = _sample_next_state(scored_actions)

	current_state = selected_state
	_target_node = _get_target_for_action(current_state, true)
	_pounce_impulse_sent = false
	_is_exiting_state = false
	_has_reached_target = _target_node == null
	if current_state != &"explore" and current_state != &"idle":
		_explore_wander_offset = Vector3.ZERO
	_record_state_choice(current_state)
	_decision_timer = _decision_window_for_state(current_state)
	if _has_reached_target:
		_play_state_animation()
	else:
		_play_locomotion_animation()
	_update_debug_label(needs.snapshot())


func _score_actions() -> Dictionary:
	return {
		&"eat": needs.hunger * 1.45,
		&"rest": (1.0 - needs.energy) * 1.25 + needs.stress * 0.35,
		&"play": (1.0 - needs.play) * 0.95 + needs.curiosity * 0.25,
		&"explore": needs.curiosity * 0.85 + (1.0 - needs.stress) * 0.12,
		&"idle": 0.18,
	}


func _action_is_available(action: StringName) -> bool:
	match action:
		&"eat":
			return _targets.get(&"FoodTarget") != null
		&"rest":
			return _targets.get(&"RestTarget") != null
		&"play":
			return _targets.get(&"PlayTarget") != null
		&"explore":
			return _roam_target != null or _targets.has(&"ExploreTargetA") or _targets.has(&"ExploreTargetB")
		&"idle":
			return true
		_:
			return false


func _get_target_for_action(action: StringName, refresh_roam: bool = false) -> Node3D:
	match action:
		&"eat":
			return _targets.get(&"FoodTarget") as Node3D
		&"rest":
			return _targets.get(&"RestTarget") as Node3D
		&"play":
			return _targets.get(&"PlayTarget") as Node3D
		&"explore":
			return _pick_explore_target()
		&"idle":
			if refresh_roam:
				_refresh_roam_target(true)
			return _roam_target
		_:
			return null


func _pick_explore_target() -> Node3D:
	if _roam_target == null:
		return null

	if _rng.randf() < roam_procedural_chance:
		_refresh_roam_target(true)
		return _roam_target

	var explore_targets: Array[Node3D] = []
	for key in [&"ExploreTargetA", &"ExploreTargetB"]:
		var target: Node3D = _targets.get(key) as Node3D
		if target != null:
			explore_targets.append(target)

	if explore_targets.is_empty():
		_refresh_roam_target(true)
		return _roam_target

	if _rng.randf() < 0.35:
		_refresh_roam_target(true)
		return _roam_target

	return explore_targets[_rng.randi_range(0, explore_targets.size() - 1)]


func _sample_next_state(scored_actions: Dictionary) -> StringName:
	var weighted_actions: Dictionary = {}
	var total_weight: float = 0.0

	for action in scored_actions:
		var action_name: StringName = action as StringName
		if not _action_is_available(action_name):
			continue

		var weight: float = maxf(float(scored_actions[action]), 0.01)
		weight *= _state_noise_for_action(action_name)
		weight *= _state_fatigue_factor(action_name)
		weight *= _settled_state_bias(action_name)
		if action_name == current_state:
			weight *= state_repeat_penalty
		if _state_history.size() > 0 and _state_history[_state_history.size() - 1] == action_name:
			weight *= state_recent_penalty
		if weight <= 0.001:
			continue

		weighted_actions[action_name] = weight
		total_weight += weight

	if weighted_actions.is_empty() or total_weight <= 0.0:
		return &"idle"

	var roll: float = _rng.randf() * total_weight
	for action in weighted_actions:
		roll -= float(weighted_actions[action])
		if roll <= 0.0:
			return action as StringName

	return weighted_actions.keys()[0] as StringName


func _state_noise_for_action(action: StringName) -> float:
	var jitter: float = _rng.randf_range(1.0 - state_selection_noise, 1.0 + state_selection_noise)
	if action == &"idle" or action == &"explore":
		jitter += 0.12
	if action == &"eat":
		jitter -= 0.05
	return maxf(jitter, 0.1)


func _state_fatigue_factor(action: StringName) -> float:
	var fatigue: float = float(_state_fatigue.get(action, 0.0))
	return 1.0 / (1.0 + fatigue)


func _settled_state_bias(action: StringName) -> float:
	var dominant_need: StringName = needs.dominant_need()
	if dominant_need == &"settled" or dominant_need == &"curious":
		if action == &"idle" or action == &"explore":
			return 1.45
		if action == &"eat" or action == &"rest" or action == &"play":
			return 0.82
	return 1.0


func _record_state_choice(action: StringName) -> void:
	_state_history.append(action)
	if _state_history.size() > 5:
		_state_history.remove_at(0)

	var fatigue: float = float(_state_fatigue.get(action, 0.0))
	_state_fatigue[action] = clampf(fatigue + state_fatigue_on_use, 0.0, 2.5)


func _decay_state_fatigue(delta: float) -> void:
	for action in _state_fatigue.keys():
		var fatigue: float = float(_state_fatigue[action])
		_state_fatigue[action] = maxf(0.0, fatigue - state_fatigue_decay_per_second * delta)


func _decision_window_for_state(action: StringName) -> float:
	match action:
		&"eat":
			return _rng.randf_range(5.5, 11.5)
		&"rest":
			return _rng.randf_range(9.0, 18.0)
		&"play":
			return _rng.randf_range(5.0, 10.0)
		&"explore":
			return _rng.randf_range(2.5, 6.5)
		&"idle":
			return _rng.randf_range(1.8, 4.5)
		_:
			return _rng.randf_range(min_decision_time, max_decision_time)


func _setup_roam_target() -> void:
	_roam_target = get_node_or_null("ProceduralRoamTarget") as Node3D
	var roam_parent: Node = get_node_or_null(target_root_path)
	if roam_parent == null:
		roam_parent = get_tree().current_scene

	if _roam_target == null:
		_roam_target = Node3D.new()
		_roam_target.name = "ProceduralRoamTarget"
		roam_parent.add_child(_roam_target)
	elif _roam_target.get_parent() != roam_parent:
		_roam_target.reparent(roam_parent, true)
	_refresh_roam_target(true)


func _refresh_roam_target(force: bool = false) -> void:
	if _roam_target == null:
		return

	if not force and _roam_target.global_position.distance_to(global_position) > roam_pick_min_distance:
		return

	var min_x: float = minf(room_roam_min.x, room_roam_max.x)
	var max_x: float = maxf(room_roam_min.x, room_roam_max.x)
	var min_z: float = minf(room_roam_min.y, room_roam_max.y)
	var max_z: float = maxf(room_roam_min.y, room_roam_max.y)
	var candidate: Vector3 = _roam_target.global_position

	for i in range(6):
		candidate = Vector3(
			_rng.randf_range(min_x, max_x),
			global_position.y,
			_rng.randf_range(min_z, max_z)
		)
		if candidate.distance_to(global_position) >= roam_pick_min_distance:
			break

	_roam_target.global_position = candidate


func _move_towards_target(delta: float) -> bool:
	var current_position: Vector3 = global_position
	var target_position: Vector3 = _target_node.global_position
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
	var state_speed: float = _speed_for_current_state()
	var step: float = min(state_speed * delta, offset.length())
	global_position = current_position + (direction * step)
	_face_direction(direction, delta)
	return false


func _speed_for_current_state() -> float:
	var state_speed: float = move_speed
	if current_state == &"play" or current_state == &"explore":
		state_speed *= 1.12
	if needs.energy < 0.25:
		state_speed *= 0.65
	return state_speed


func _face_direction(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.001:
		return

	var model_forward_offset: float = deg_to_rad(model_forward_yaw_offset_degrees)
	var target_yaw: float = atan2(-direction.x, -direction.z) + model_forward_offset
	rotation.y = lerp_angle(rotation.y, target_yaw, min(turn_speed * delta, 1.0))


func _update_explore_wander_offset(delta: float) -> Vector3:
	var jitter: Vector2 = Vector2(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)
	)
	var offset_2d: Vector2 = Vector2(_explore_wander_offset.x, _explore_wander_offset.z)
	offset_2d += jitter * explore_wander_jitter * delta
	if offset_2d.length_squared() > explore_wander_radius * explore_wander_radius:
		offset_2d = offset_2d.normalized() * explore_wander_radius

	_explore_wander_offset = Vector3(offset_2d.x, 0.0, offset_2d.y)
	return _explore_wander_offset


func _wall_avoidance_vector(origin: Vector3, direction: Vector3) -> Vector3:
	if _space_state == null or direction.length_squared() < 0.001:
		return Vector3.ZERO

	var feeler: Vector3 = direction.normalized() * wall_avoidance_distance
	var rays: Array[Vector3] = [
		feeler,
		Quaternion(Vector3.UP, deg_to_rad(30.0)) * feeler,
		Quaternion(Vector3.UP, deg_to_rad(-30.0)) * feeler,
	]

	var avoidance: Vector3 = Vector3.ZERO
	for ray in rays:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + ray)
		var hit: Dictionary = _space_state.intersect_ray(query)
		if hit.is_empty():
			continue

		var hit_position: Vector3 = hit.get("position", origin) as Vector3
		var hit_normal: Vector3 = hit.get("normal", Vector3.ZERO) as Vector3
		var hit_distance: float = origin.distance_to(hit_position)
		var proximity: float = clampf(1.0 - (hit_distance / wall_avoidance_distance), 0.0, 1.0)
		if hit_normal.length_squared() > 0.001:
			avoidance += hit_normal * proximity

	return avoidance


func _apply_arrival_effects(delta: float) -> void:
	match current_state:
		&"eat":
			needs.nibble(delta)
		&"rest":
			needs.rest(delta)
		&"play":
			if not _pounce_impulse_sent:
				_pounce_ball()
				_pounce_impulse_sent = true
			needs.chase(delta)
		&"explore":
			needs.curiosity = clampf(needs.curiosity - 0.045 * delta, 0.0, 1.0)
			needs.stress = clampf(needs.stress - 0.012 * delta, 0.0, 1.0)
			needs.changed.emit(needs.snapshot())


func catch_attention(source: Node3D = null) -> void:
	current_state = &"attention"
	_target_node = null
	_has_reached_target = true
	_is_exiting_state = false
	_decision_timer = min_decision_time
	needs.socialise(0.6)
	if source != null:
		var direction: Vector3 = source.global_position - global_position
		direction.y = 0.0
		_face_direction(direction, 1.0)
	_play_attention_animation()
	_update_debug_label(needs.snapshot())


func _pounce_ball() -> void:
	var ball: RigidBody3D = _find_target_rigid_body()
	if ball == null:
		return

	_push_ball(ball)


func _push_ball(ball: RigidBody3D) -> void:
	var impulse_direction: Vector3 = ball.global_position - global_position
	impulse_direction.y = 0.08
	if impulse_direction.length_squared() < 0.001:
		impulse_direction = _get_visual_forward_direction() + Vector3.UP * 0.08

	impulse_direction = _steer_ball_impulse_from_bounds(ball.global_position, impulse_direction)
	ball.apply_central_impulse(impulse_direction.normalized() * pounce_impulse)


func _steer_ball_impulse_from_bounds(ball_position: Vector3, impulse_direction: Vector3) -> Vector3:
	var horizontal_impulse: Vector3 = Vector3(impulse_direction.x, 0.0, impulse_direction.z)
	var inward_direction: Vector3 = Vector3.ZERO

	if ball_position.x <= ball_play_bounds_min.x + ball_edge_turn_margin and horizontal_impulse.x < 0.0:
		inward_direction.x += 1.0
	if ball_position.x >= ball_play_bounds_max.x - ball_edge_turn_margin and horizontal_impulse.x > 0.0:
		inward_direction.x -= 1.0
	if ball_position.z <= ball_play_bounds_min.y + ball_edge_turn_margin and horizontal_impulse.z < 0.0:
		inward_direction.z += 1.0
	if ball_position.z >= ball_play_bounds_max.y - ball_edge_turn_margin and horizontal_impulse.z > 0.0:
		inward_direction.z -= 1.0

	if inward_direction.length_squared() < 0.001:
		return impulse_direction

	var inward_normal: Vector3 = inward_direction.normalized()
	if horizontal_impulse.length_squared() < 0.001:
		horizontal_impulse = inward_normal
	else:
		horizontal_impulse = horizontal_impulse.normalized().lerp(inward_normal, ball_inward_push_bias)
		if horizontal_impulse.length_squared() < 0.001:
			horizontal_impulse = inward_normal

	return Vector3(horizontal_impulse.x, impulse_direction.y, horizontal_impulse.z)


func _on_pounce_hitbox_body_entered(body: Node3D) -> void:
	if current_state != &"play" or _pounce_impulse_sent:
		return

	if body is RigidBody3D:
		_push_ball(body as RigidBody3D)
		_pounce_impulse_sent = true


func _find_target_rigid_body() -> RigidBody3D:
	var node: Node = _target_node
	while node != null:
		if node is RigidBody3D:
			return node as RigidBody3D
		node = node.get_parent()
	return null


func _play_state_animation() -> void:
	if _animation_player == null:
		return

	if current_state == &"explore":
		_play_idle_animation()
		return

	if _play_action_phase_animation(current_state, PHASE_ENTER, 0.2):
		return

	var animation_name: StringName = ACTION_ANIMATIONS.get(current_state, &"Idle") as StringName
	if _animation_player.has_animation(animation_name):
		_animation_player.play(animation_name, 0.2)


func _play_locomotion_animation() -> void:
	if _animation_player == null:
		return

	if _animation_player.has_animation(LOCOMOTION_ANIMATION):
		if StringName(_animation_player.current_animation) != LOCOMOTION_ANIMATION or not _animation_player.is_playing():
			_animation_player.play(LOCOMOTION_ANIMATION, 0.15)


func _play_idle_animation() -> void:
	if _animation_player == null:
		return

	if _animation_player.has_animation(&"Idle"):
		if StringName(_animation_player.current_animation) != &"Idle" or not _animation_player.is_playing():
			_animation_player.play(&"Idle", 0.15)


func _get_visual_forward_direction() -> Vector3:
	var forward: Vector3 = global_transform.basis.x
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		return Vector3.FORWARD

	return forward.normalized()


func _finish_current_state() -> void:
	if _play_action_phase_animation(current_state, PHASE_EXIT, 0.12):
		_is_exiting_state = true
		_target_node = null
		_has_reached_target = true
		return

	_choose_next_state()


func _play_action_phase_animation(action: StringName, phase: StringName, blend: float) -> bool:
	if _animation_player == null:
		return false

	var animation_name: StringName = _get_action_phase_animation(action, phase)
	if animation_name == &"":
		return false

	if not _animation_player.has_animation(animation_name):
		return false

	_animation_player.play(animation_name, blend)
	return true


func _get_action_phase_animation(action: StringName, phase: StringName) -> StringName:
	if not PHASED_ACTION_ANIMATIONS.has(action):
		return &""

	var phase_animations: Dictionary = PHASED_ACTION_ANIMATIONS[action] as Dictionary
	return phase_animations.get(phase, &"") as StringName


func _animation_matches_phase(action: StringName, phase: StringName, animation_name: StringName) -> bool:
	return _get_action_phase_animation(action, phase) == animation_name


func _on_animation_finished(animation_name: StringName) -> void:
	if _is_exiting_state and _animation_matches_phase(current_state, PHASE_EXIT, animation_name):
		_is_exiting_state = false
		_choose_next_state()
		return

	if _animation_matches_phase(current_state, PHASE_ENTER, animation_name):
		_play_action_phase_animation(current_state, PHASE_IDLE, 0.12)
		return

	if _animation_matches_phase(current_state, PHASE_IDLE, animation_name):
		_play_action_phase_animation(current_state, PHASE_IDLE, 0.0)


func _play_attention_animation() -> void:
	if _animation_player == null:
		return

	if _animation_player.has_animation(ATTENTION_ANIMATION):
		_animation_player.play(ATTENTION_ANIMATION, 0.12)


func _setup_debug_label() -> void:
	if not show_debug_label:
		return

	_debug_label = get_node_or_null("AutonomyDebugLabel") as Label3D
	if _debug_label == null:
		_debug_label = Label3D.new()
		_debug_label.name = "AutonomyDebugLabel"
		add_child(_debug_label)

	_debug_label.position = Vector3(0.0, 0.68, 0.0)
	_debug_label.pixel_size = 0.006
	_debug_label.font_size = 12
	_debug_label.no_depth_test = true
	_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED


func _on_needs_changed(snapshot: Dictionary) -> void:
	_update_debug_label(snapshot)


func _update_debug_label(snapshot: Dictionary) -> void:
	if _debug_label == null:
		return

	_debug_label.text = "%s | %s\nH %.0f E %.0f P %.0f A %.0f" % [
		String(current_state).capitalize(),
		String(snapshot.get("mood", &"content")).capitalize(),
		needs.hunger * 100.0,
		needs.energy * 100.0,
		needs.play * 100.0,
		needs.affection * 100.0,
	]
