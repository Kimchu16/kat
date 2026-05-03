class_name KatAutonomyController
extends Node3D

# Main "brain" for Kat. Movement, target picking, and animation playback are
# split into helper scripts so this file mostly controls the current behaviour.

@export var autonomy_enabled: bool = true
@export var target_root_path: NodePath = NodePath("../KatTargets")
@export var food_bowl_path: NodePath = NodePath("../Furniture/Food Bowl")

# Movement values are kept here so they can still be tweaked from the Kat scene.
@export var move_speed: float = 0.85
@export var turn_speed: float = 6.0
@export var arrival_radius: float = 0.22
@export var elevated_arrival_radius: float = 0.18
@export var jump_start_distance: float = 0.95
@export var jump_speed: float = 1.05
@export var jump_arc_height: float = 0.65
@export var elevated_target_min_height: float = 0.18
@export var floor_height: float = 0.0
@export_range(0.0, 1.0, 0.05) var elevated_explore_chance: float = 0.35

# Ball-play settings. The re-engage timer stops Kat from instantly spamming
# impulses before the ball has had a chance to move.
@export var pounce_impulse: float = 0.65
@export var play_reengage_distance: float = 0.45
@export var play_pounce_recover_time: float = 0.65
@export var play_target_prediction_limit: float = 0.35
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

# These make the state choice less robotic without completely ignoring needs.
@export_range(0.0, 1.0, 0.01) var state_selection_noise: float = 0.35
@export_range(0.0, 1.0, 0.01) var state_repeat_penalty: float = 0.42
@export_range(0.0, 1.0, 0.01) var state_recent_penalty: float = 0.82
@export var state_fatigue_decay_per_second: float = 0.08
@export var state_fatigue_on_use: float = 0.7
@export var min_decision_time: float = 4.0
@export var max_decision_time: float = 8.5
@export var show_debug_label: bool = true
@export_range(-180.0, 180.0, 1.0) var model_forward_yaw_offset_degrees: float = 90.0

# I preload these instead of using the class names directly because Godot can
# sometimes complain about new global script classes until the project reloads.
const KAT_TARGET_SELECTOR_SCRIPT: GDScript = preload("res://scripts/kat_target_selector.gd")
const KAT_NAVIGATOR_SCRIPT: GDScript = preload("res://scripts/kat_navigator.gd")
const KAT_ANIMATION_DRIVER_SCRIPT: GDScript = preload("res://scripts/kat_animation_driver.gd")
const PHASE_ENTER: StringName = &"enter"
const PHASE_IDLE: StringName = &"idle"
const PHASE_EXIT: StringName = &"exit"

var needs: KatNeeds = KatNeeds.new()
var current_state: StringName = &"idle"

var _target_node: Node3D
var _food_bowl: Node
var _target_selector: Variant = KAT_TARGET_SELECTOR_SCRIPT.new()
var _navigator: Variant = KAT_NAVIGATOR_SCRIPT.new()
var _animation_driver: Variant = KAT_ANIMATION_DRIVER_SCRIPT.new()
var _animation_player: AnimationPlayer
var _pounce_hitbox: Area3D
var _debug_label: Label3D
var _state_fatigue: Dictionary = {}
var _state_history: Array[StringName] = []
var _decision_timer: float = 0.0
var _pounce_impulse_sent: bool = false
var _eat_bowl_emptied: bool = false
var _play_reengage_timer: float = 0.0
var _has_reached_target: bool = true
var _is_exiting_state: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_food_bowl = get_node_or_null(food_bowl_path)
	_animation_player = get_node_or_null("AnimationPlayer") as AnimationPlayer
	if _animation_player != null:
		_animation_player.animation_finished.connect(_on_animation_finished)
	_animation_driver.setup(_animation_player)
	_pounce_hitbox = get_node_or_null("PounceHitbox") as Area3D
	if _pounce_hitbox != null:
		_pounce_hitbox.body_entered.connect(_on_pounce_hitbox_body_entered)
	_setup_helpers()
	_target_selector.setup_roam_target()
	_target_selector.collect_targets()
	_setup_debug_label()
	needs.changed.connect(_on_needs_changed)
	_choose_next_state()


func _process(delta: float) -> void:
	if not autonomy_enabled:
		return

	_sync_helper_config()
	_decay_state_fatigue(delta)
	needs.tick(delta, current_state == &"play")
	if _is_exiting_state:
		return

	# First Kat travels to the chosen target. Once it arrives, the state effect
	# keeps running until its timer expires or the play loop starts chasing again.
	if _target_node == null:
		_decision_timer -= delta
		if _decision_timer <= 0.0:
			_choose_next_state()
		return

	if not _has_reached_target:
		var arrived: bool = _navigator.move_towards_target(delta, current_state, needs.energy)
		if arrived:
			_has_reached_target = true
			_decision_timer = _decision_window_for_state(current_state)
			_play_state_animation()
			_apply_arrival_effects(delta)
		else:
			_play_locomotion_animation()
		return

	_apply_arrival_effects(delta)
	if _update_play_chase_loop(delta):
		return

	_decision_timer -= delta
	if _decision_timer <= 0.0:
		_finish_current_state()


func _setup_helpers() -> void:
	_target_selector.setup(self, _rng)
	_navigator.setup(self, _rng)
	_sync_helper_config()

	var current_world: World3D = get_world_3d()
	if current_world != null:
		_navigator.space_state = current_world.direct_space_state
	else:
		_navigator.space_state = null


func _sync_helper_config() -> void:
	# Exported values live on this script for easy inspector access, then get
	# copied into the helpers each frame in case I tune them while testing.
	_target_selector.target_root_path = target_root_path
	_target_selector.floor_height = floor_height
	_target_selector.elevated_explore_chance = elevated_explore_chance
	_target_selector.roam_procedural_chance = roam_procedural_chance
	_target_selector.room_roam_min = room_roam_min
	_target_selector.room_roam_max = room_roam_max
	_target_selector.roam_pick_min_distance = roam_pick_min_distance

	_navigator.move_speed = move_speed
	_navigator.turn_speed = turn_speed
	_navigator.arrival_radius = arrival_radius
	_navigator.elevated_arrival_radius = elevated_arrival_radius
	_navigator.jump_start_distance = jump_start_distance
	_navigator.jump_speed = jump_speed
	_navigator.jump_arc_height = jump_arc_height
	_navigator.elevated_target_min_height = elevated_target_min_height
	_navigator.floor_height = floor_height
	_navigator.moving_target_prediction_limit = play_target_prediction_limit
	_navigator.wall_avoidance_distance = wall_avoidance_distance
	_navigator.wall_avoidance_strength = wall_avoidance_strength
	_navigator.explore_wander_radius = explore_wander_radius
	_navigator.explore_wander_jitter = explore_wander_jitter
	_navigator.room_roam_min = room_roam_min
	_navigator.room_roam_max = room_roam_max
	_navigator.model_forward_yaw_offset_degrees = model_forward_yaw_offset_degrees


func _choose_next_state() -> void:
	_sync_helper_config()
	var scored_actions: Dictionary = _score_actions()
	var selected_state: StringName = _sample_next_state(scored_actions)

	current_state = selected_state
	_target_node = _target_selector.get_target_for_action(current_state, true)
	_pounce_impulse_sent = false
	_eat_bowl_emptied = false
	_play_reengage_timer = 0.0
	_is_exiting_state = false
	_has_reached_target = _target_node == null
	if _target_node != null:
		_navigator.begin_target_movement(_target_node)
	else:
		_navigator.clear()
	if current_state != &"explore" and current_state != &"idle":
		_navigator.clear_explore_wander_offset()
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
	if not _target_selector.action_is_available(action):
		return false
	if action == &"eat":
		return _food_bowl_has_food()
	return true


func _sample_next_state(scored_actions: Dictionary) -> StringName:
	var weighted_actions: Dictionary = {}
	var total_weight: float = 0.0

	# This is a weighted roll rather than a strict priority list. It still
	# favours important needs, but Kat should not choose the exact same loop.
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

	# Fatigue is separate from the short history so a state can become likely
	# again over time instead of being blocked completely.
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


func _apply_arrival_effects(delta: float) -> void:
	match current_state:
		&"eat":
			if not _eat_bowl_emptied:
				_empty_food_bowl()
				_eat_bowl_emptied = true
			needs.nibble(delta)
		&"rest":
			needs.rest(delta)
		&"play":
			if not _pounce_impulse_sent:
				_pounce_ball()
				_pounce_impulse_sent = true
				_play_reengage_timer = play_pounce_recover_time
			needs.chase(delta)
		&"explore":
			needs.curiosity = clampf(needs.curiosity - 0.045 * delta, 0.0, 1.0)
			needs.stress = clampf(needs.stress - 0.012 * delta, 0.0, 1.0)
			needs.changed.emit(needs.snapshot())


func _update_play_chase_loop(delta: float) -> bool:
	if current_state != &"play" or _target_node == null:
		return false

	# After the impulse, let the pounce animation and ball physics breathe for a
	# moment before deciding whether Kat should chase again.
	if _play_reengage_timer > 0.0:
		_play_reengage_timer = maxf(_play_reengage_timer - delta, 0.0)
		return false

	if _play_target_horizontal_distance() > play_reengage_distance:
		_restart_play_chase()
		return true

	_pounce_impulse_sent = false
	_play_state_animation()
	return false


func _restart_play_chase() -> void:
	_pounce_impulse_sent = false
	_has_reached_target = false
	_navigator.begin_target_movement(_target_node)
	_play_locomotion_animation()


func _play_target_horizontal_distance() -> float:
	if _target_node == null:
		return 0.0

	var target_position: Vector3 = _target_node.global_position
	return Vector2(
		target_position.x - global_position.x,
		target_position.z - global_position.z
	).length()


func _food_bowl_has_food() -> bool:
	if _food_bowl == null:
		return true
	if _food_bowl.has_method(&"has_food_available"):
		return bool(_food_bowl.call(&"has_food_available"))
	return true


func _empty_food_bowl() -> void:
	if _food_bowl != null and _food_bowl.has_method(&"empty_bowl"):
		_food_bowl.call(&"empty_bowl")


func catch_attention(source: Node3D = null) -> void:
	current_state = &"attention"
	_target_node = null
	_has_reached_target = true
	_is_exiting_state = false
	_navigator.clear()
	_play_reengage_timer = 0.0
	_decision_timer = min_decision_time
	needs.socialise(0.6)
	if source != null:
		var direction: Vector3 = source.global_position - global_position
		direction.y = 0.0
		_navigator.face_direction(direction, 1.0)
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
		impulse_direction = _navigator.get_visual_forward_direction() + Vector3.UP * 0.08

	# Keep pounces from sending the ball straight into the walls every time.
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
		_play_reengage_timer = play_pounce_recover_time
		_has_reached_target = true
		_play_state_animation()


func _find_target_rigid_body() -> RigidBody3D:
	var node: Node = _target_node
	while node != null:
		if node is RigidBody3D:
			return node as RigidBody3D
		node = node.get_parent()
	return null


func _play_state_animation() -> void:
	_animation_driver.play_state_animation(current_state)


func _play_locomotion_animation() -> void:
	_animation_driver.play_locomotion_animation(_navigator.is_jumping())


func _finish_current_state() -> void:
	if _animation_driver.play_action_phase_animation(current_state, PHASE_EXIT, 0.12):
		_is_exiting_state = true
		_target_node = null
		_has_reached_target = true
		_navigator.clear()
		_play_reengage_timer = 0.0
		return

	_choose_next_state()


func _on_animation_finished(animation_name: StringName) -> void:
	if _is_exiting_state and _animation_driver.animation_matches_phase(current_state, PHASE_EXIT, animation_name):
		_is_exiting_state = false
		_choose_next_state()
		return

	if _animation_driver.animation_matches_phase(current_state, PHASE_ENTER, animation_name):
		_animation_driver.play_action_phase_animation(current_state, PHASE_IDLE, 0.12)
		return

	if _animation_driver.animation_matches_phase(current_state, PHASE_IDLE, animation_name):
		_animation_driver.play_action_phase_animation(current_state, PHASE_IDLE, 0.0)


func _play_attention_animation() -> void:
	_animation_driver.play_attention_animation()


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
