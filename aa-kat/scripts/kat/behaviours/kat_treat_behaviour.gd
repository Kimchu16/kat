class_name KatTreatBehaviour
extends RefCounted

signal avoidance_requested(source: Node3D, duration: float, reason: StringName, should_meow: bool)

# Held fish treat interaction. The sensor tells this script about nearby treats;
# this script handles attention, waiting, feeding, and tease penalties.

var brain: Variant
var sensor: Variant

var _active_treat: Node3D
var _is_waiting_for_treat: bool = false
var _is_treat_feeding: bool = false
var _treat_attention_timer: float = 0.0
var _treat_meow_timer: float = 0.0
var _treat_eat_timer: float = 0.0
var _treat_left_notice_penalized: bool = false
var _treat_reject_timer: float = 0.0


func setup(owner: Variant, treat_sensor: Variant) -> void:
	brain = owner
	sensor = treat_sensor
	sensor.held_treat_entered.connect(_on_treat_notice_body_entered)
	sensor.held_treat_exited.connect(_on_treat_notice_body_exited)
	sensor.held_treat_fed.connect(_on_treat_feed_body_entered)


func is_waiting() -> bool:
	return _is_waiting_for_treat


func blocks_relationship() -> bool:
	return _is_treat_feeding or _active_treat != null


func stop_particles() -> void:
	sensor.set_eating_particles(false)


func update(delta: float) -> bool:
	_treat_reject_timer = maxf(_treat_reject_timer - delta, 0.0)

	if _is_treat_feeding:
		_update_treat_feeding(delta)
		return true

	if _active_treat == null or not is_instance_valid(_active_treat):
		return _find_held_treat_in_notice_area()

	if not bool(sensor.is_held_treat(_active_treat)):
		clear(false)
		return true

	if not bool(sensor.is_inside_notice(_active_treat)):
		_apply_treat_tease_penalty()
		clear(false)
		return true

	if bool(sensor.is_inside_feed(_active_treat)):
		_start_treat_feeding(_active_treat)
		return true

	var holder: Node3D = sensor.holder_for_treat(_active_treat) as Node3D
	if holder == null:
		clear(false)
		return true

	brain.current_state = &"treat"
	brain._decision_timer = maxf(float(brain._decision_timer), float(brain.min_decision_time))
	if _treat_attention_timer > 0.0:
		_treat_attention_timer = maxf(_treat_attention_timer - delta, 0.0)
		brain._face_node(holder, delta)
		return true

	_follow_treat_holder(holder, delta)
	return true


func clear(choose_next: bool) -> void:
	_active_treat = null
	_is_waiting_for_treat = false
	_treat_attention_timer = 0.0
	_treat_meow_timer = 0.0
	_treat_left_notice_penalized = false
	brain._stop_treat_meow_audio()
	if not _is_treat_feeding:
		sensor.set_eating_particles(false)

	if choose_next and brain.current_state == &"treat":
		brain._choose_next_state()


func _find_held_treat_in_notice_area() -> bool:
	var treat: Node3D = sensor.find_held_treat_in_notice_area(_treat_reject_timer) as Node3D
	if treat != null:
		_begin_treat_interest(treat)
		return _active_treat != null

	return false


func _begin_treat_interest(treat: Node3D) -> void:
	if treat == null or _is_treat_feeding:
		return
	if brain.needs.anger >= float(brain.angry_treat_ignore_threshold):
		_reject_held_treat(treat)
		return

	_active_treat = treat
	_is_waiting_for_treat = false
	_treat_left_notice_penalized = false
	_treat_attention_timer = float(brain.treat_attention_time)
	_treat_meow_timer = 0.6
	brain.current_state = &"treat"
	brain._target_node = null
	brain._has_reached_target = true
	brain._is_exiting_state = false
	brain._clear_food_begging()
	brain._navigator.clear()
	brain._stop_eating_audio()
	brain._stop_complaint_audio()
	brain._play_attention_animation()
	brain._update_debug_label(brain.needs.snapshot())


func _reject_held_treat(treat: Node3D) -> void:
	_treat_reject_timer = float(brain.angry_treat_reject_duration)
	_active_treat = null
	_is_waiting_for_treat = false
	_treat_attention_timer = 0.0
	_treat_meow_timer = 0.0
	_treat_left_notice_penalized = true
	brain._stop_eating_audio()
	brain._stop_complaint_audio()
	brain._stop_purr_audio()

	var holder: Node3D = sensor.holder_for_treat(treat) as Node3D
	if holder != null:
		avoidance_requested.emit(holder, float(brain.angry_treat_reject_duration), &"treat", true)
	else:
		brain._play_treat_meow_audio()


func _follow_treat_holder(holder: Node3D, delta: float) -> void:
	var follow_target: Node3D = brain._floor_target_for_treat_holder(holder) as Node3D
	var holder_distance: float = float(brain._horizontal_distance_to_node(follow_target))
	var resume_distance: float = maxf(float(brain.treat_follow_resume_distance), float(brain.treat_wait_distance) + 0.15)

	if holder_distance <= float(brain.treat_wait_distance):
		brain._target_node = follow_target
		_stop_treat_follow()
		_play_treat_wait_animation(holder, delta)
		_update_treat_wait_meow(delta)
		return

	if bool(brain._has_reached_target) and holder_distance <= resume_distance:
		_play_treat_wait_animation(holder, delta)
		_update_treat_wait_meow(delta)
		return

	brain._target_node = follow_target
	brain._has_reached_target = false
	_is_waiting_for_treat = false
	brain._navigator.begin_target_movement(brain._target_node)
	var arrived: bool = bool(brain._navigator.move_towards_target(delta, brain.current_state, brain.needs.energy))
	if arrived:
		_stop_treat_follow()
		_play_treat_wait_animation(holder, delta)
		_update_treat_wait_meow(delta)
	else:
		brain._play_locomotion_animation()


func _stop_treat_follow() -> void:
	brain._has_reached_target = true
	_is_waiting_for_treat = true
	brain._navigator.clear()
	if brain.global_position.y > float(brain.floor_height) + float(brain.elevated_target_min_height):
		var floor_position: Vector3 = brain.global_position
		floor_position.y = float(brain.floor_height)
		brain.global_position = floor_position


func _play_treat_wait_animation(holder: Node3D, delta: float) -> void:
	brain._face_node(holder, delta)
	brain._animation_driver.play_sit_wait_animation()


func _update_treat_wait_meow(delta: float) -> void:
	_treat_meow_timer -= delta
	if _treat_meow_timer > 0.0:
		return

	brain._play_treat_meow_audio()
	_treat_meow_timer = maxf(float(brain.treat_meow_interval), 0.2)


func _start_treat_feeding(treat: Node3D) -> void:
	if treat == null or _is_treat_feeding:
		return

	_is_treat_feeding = true
	_is_waiting_for_treat = false
	_treat_eat_timer = float(brain.treat_eat_duration)
	brain.current_state = &"treat"
	brain._target_node = null
	brain._has_reached_target = true
	brain._navigator.clear()
	brain._stop_treat_meow_audio()
	brain._start_eating_audio()
	sensor.set_eating_particles(true)
	brain._animation_driver.play_state_animation(&"eat")
	brain.needs.eat_treat(float(brain.treat_affection_reward))

	if treat.has_method(&"consume"):
		treat.call(&"consume")

	_active_treat = null
	brain._update_debug_label(brain.needs.snapshot())


func _update_treat_feeding(delta: float) -> void:
	_treat_eat_timer = maxf(_treat_eat_timer - delta, 0.0)
	if _treat_eat_timer > 0.0:
		return

	brain._stop_eating_audio()
	sensor.set_eating_particles(false)
	_is_treat_feeding = false
	clear(true)


func _apply_treat_tease_penalty() -> void:
	if _treat_left_notice_penalized:
		return

	_treat_left_notice_penalized = true
	brain.needs.tease_with_treat(float(brain.treat_tease_penalty))


func _on_treat_notice_body_entered(body: Node3D) -> void:
	if bool(sensor.is_held_treat(body)):
		_begin_treat_interest(body)


func _on_treat_notice_body_exited(body: Node3D) -> void:
	if body == _active_treat and bool(sensor.is_held_treat(body)):
		_apply_treat_tease_penalty()
		clear(true)


func _on_treat_feed_body_entered(body: Node3D) -> void:
	if body == _active_treat and bool(sensor.is_held_treat(body)):
		_start_treat_feeding(body)
