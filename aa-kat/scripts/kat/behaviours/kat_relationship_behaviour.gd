class_name KatRelationshipBehaviour
extends RefCounted

# Social following, anger avoidance, and warning the player when they crowd Kat.

var brain: Variant
var avoid_reason: StringName = &""

var _avoid_timer: float = 0.0
var _avoid_meow_timer: float = 0.0
var _avoid_warning_timer: float = 0.0
var _avoid_warning_pause_timer: float = 0.0


func setup(owner: Variant) -> void:
	brain = owner


func reset() -> void:
	avoid_reason = &""
	_avoid_timer = 0.0
	_avoid_meow_timer = 0.0
	_avoid_warning_timer = 0.0
	_avoid_warning_pause_timer = 0.0


func update(delta: float, can_take_over: bool) -> bool:
	if brain.current_state == &"avoid":
		_update_avoidance(delta)
		return true

	if brain.current_state == &"social":
		_update_social_follow(delta)
		return true

	if not can_take_over:
		return false

	if brain.needs.anger >= float(brain.anger_avoid_threshold):
		var angry_source: Node3D = brain._resolve_user_follow_target() as Node3D
		if angry_source != null:
			var angry_duration: float = brain._rng.randf_range(float(brain.anger_avoid_duration_min), float(brain.anger_avoid_duration_max))
			start_avoidance_from(angry_source, angry_duration, &"anger", true)
			_update_avoidance(delta)
			return true

	if brain.needs.affection < float(brain.low_affection_threshold):
		var cautious_source: Node3D = brain._resolve_user_follow_target() as Node3D
		if cautious_source != null and float(brain._horizontal_distance_to_node(cautious_source)) < float(brain.low_affection_keep_distance):
			start_avoidance_from(cautious_source, float(brain.low_affection_avoid_duration), &"cautious", false)
			_update_avoidance(delta)
			return true

	return false


func start_avoidance_from(source: Node3D, duration: float, reason: StringName, should_meow: bool) -> void:
	if source == null:
		return

	brain.current_state = &"avoid"
	avoid_reason = reason
	_avoid_timer = maxf(duration, 0.4)
	_avoid_meow_timer = 0.0
	_avoid_warning_timer = 0.0
	_avoid_warning_pause_timer = 0.0
	brain._target_node = brain._avoid_target_from(source)
	brain._has_reached_target = false
	brain._is_exiting_state = false
	brain._clear_food_begging()
	brain._stop_eating_audio()
	brain._stop_complaint_audio()
	brain._navigator.begin_target_movement(brain._target_node)
	brain._decision_timer = _avoid_timer
	_play_avoid_entry_warning(source)
	if should_meow:
		_avoid_meow_timer = maxf(float(brain.avoid_meow_interval), 0.4)


func _update_social_follow(delta: float) -> void:
	var user_target: Node3D = brain._resolve_user_follow_target() as Node3D
	if user_target == null or not bool(brain._should_social_follow_player()):
		brain._choose_next_state()
		return

	brain._decision_timer = float(brain._decision_timer) - delta
	if float(brain._decision_timer) <= 0.0:
		brain._choose_next_state()
		return

	var follow_target: Node3D = brain._floor_target_for_user(user_target) as Node3D
	brain._target_node = follow_target
	var player_distance: float = float(brain._horizontal_distance_to_node(follow_target))
	if player_distance <= float(brain.social_follow_stop_distance):
		_stop_social_follow()
		_play_social_wait_animation(user_target, delta)
		brain.needs.socialise(delta * 0.45)
		return

	var resume_distance: float = maxf(float(brain.social_follow_resume_distance), float(brain.social_follow_stop_distance) + 0.15)
	if bool(brain._has_reached_target) and player_distance <= resume_distance:
		_play_social_wait_animation(user_target, delta)
		brain.needs.socialise(delta * 0.35)
		return

	brain._has_reached_target = false
	brain._navigator.begin_target_movement(brain._target_node)
	var arrived: bool = bool(brain._navigator.move_towards_target(delta, brain.current_state, brain.needs.energy))
	if arrived:
		_stop_social_follow()
		_play_social_wait_animation(user_target, delta)
	else:
		brain._play_locomotion_animation()


func _stop_social_follow() -> void:
	brain._has_reached_target = true
	brain._navigator.clear()
	brain._snap_to_floor_after_player_follow()


func _play_social_wait_animation(user_target: Node3D, delta: float) -> void:
	brain._face_node(user_target, delta)
	brain._animation_driver.play_sit_wait_animation()


func _update_avoidance(delta: float) -> void:
	var source: Node3D = brain._resolve_user_follow_target() as Node3D
	if source == null:
		_finish_avoidance()
		return

	_avoid_timer = maxf(_avoid_timer - delta, 0.0)
	_avoid_warning_timer = maxf(_avoid_warning_timer - delta, 0.0)
	_avoid_warning_pause_timer = maxf(_avoid_warning_pause_timer - delta, 0.0)
	brain._decision_timer = maxf(float(brain._decision_timer), float(brain.min_decision_time))

	if avoid_reason == &"anger" or avoid_reason == &"treat":
		brain.needs.calm_down(delta)
		_update_avoid_meow(delta)

	var desired_distance: float = float(brain.avoid_resume_distance)
	if avoid_reason == &"cautious":
		desired_distance = float(brain.low_affection_keep_distance)

	var source_distance: float = float(brain._horizontal_distance_to_node(source))
	if _avoid_warning_pause_timer > 0.0:
		brain._face_node(source, delta)
		return
	if source_distance <= float(brain.avoid_warning_distance) and _warn_player_to_back_off(source, delta):
		return

	if source_distance < desired_distance and bool(brain._has_reached_target):
		brain._target_node = brain._avoid_target_from(source)
		brain._has_reached_target = false
		brain._navigator.begin_target_movement(brain._target_node)

	if not bool(brain._has_reached_target):
		var arrived: bool = bool(brain._navigator.move_towards_target(delta, brain.current_state, brain.needs.energy))
		if arrived:
			brain._has_reached_target = true
			brain._navigator.clear()
			_play_avoid_wait_animation(source, delta)
		else:
			brain._play_locomotion_animation()
		return

	_play_avoid_wait_animation(source, delta)
	if _avoid_timer <= 0.0 and source_distance >= desired_distance:
		_finish_avoidance()


func _update_avoid_meow(delta: float) -> void:
	_avoid_meow_timer -= delta
	if _avoid_meow_timer > 0.0:
		return

	brain._play_treat_meow_audio()
	_avoid_meow_timer = maxf(float(brain.avoid_meow_interval), 0.4)


func _warn_player_to_back_off(source: Node3D, delta: float) -> bool:
	_avoid_timer = maxf(_avoid_timer, 1.2)
	brain._face_node(source, delta)
	if _avoid_warning_timer > 0.0:
		return false

	_play_avoid_warning()
	return true


func _play_avoid_entry_warning(source: Node3D) -> void:
	_avoid_warning_timer = 0.0
	brain._face_node(source, 1.0)
	_play_avoid_warning()


func _play_avoid_warning() -> void:
	brain._stop_purr_audio()
	brain._animation_driver.play_mad_animation()
	brain._play_hiss_audio()
	_avoid_warning_timer = maxf(float(brain.avoid_warning_cooldown), 0.3)
	_avoid_warning_pause_timer = maxf(float(brain.avoid_warning_pause), 0.0)


func _play_avoid_wait_animation(source: Node3D, delta: float) -> void:
	brain._face_node(source, delta)
	brain._animation_driver.play_idle_animation()


func _finish_avoidance() -> void:
	reset()
	brain._stop_treat_meow_audio()
	brain._stop_hiss_audio()
	if brain.current_state == &"avoid":
		brain._choose_next_state()
