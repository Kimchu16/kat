class_name KatFoodBehaviour
extends RefCounted

# Food bowl and hungry-begging behaviour. It keeps the "empty bowl means follow
# the player and complain" logic out of the main controller.

var brain: Variant


func setup(owner: Variant) -> void:
	brain = owner


func is_begging() -> bool:
	return bool(brain._is_begging_for_food)


func clear_begging() -> void:
	brain._is_begging_for_food = false


func has_food() -> bool:
	var food_bowl: Node = brain._food_bowl as Node
	if food_bowl == null:
		return true
	if food_bowl.has_method(&"has_food_available"):
		return bool(food_bowl.call(&"has_food_available"))
	return true


func should_beg() -> bool:
	return not has_food() and brain.needs.hunger >= float(brain.hungry_beg_threshold)


func begin_begging() -> void:
	brain._is_begging_for_food = true
	brain._stop_eating_audio()
	brain._start_complaint_audio()
	brain._decision_timer = maxf(float(brain._decision_timer), float(brain.min_decision_time))

	var user_target: Node3D = brain._resolve_user_follow_target() as Node3D
	if user_target == null:
		brain._target_node = null
		brain._has_reached_target = true
		brain._navigator.clear()
		play_wait_animation(1.0)
		return

	var follow_target: Node3D = brain._floor_target_for_user(user_target) as Node3D
	if brain._target_node != follow_target:
		brain._target_node = follow_target
		if float(brain._horizontal_distance_to_node(brain._target_node)) <= float(brain.begging_sit_distance):
			stop_follow()
		else:
			brain._has_reached_target = false
			brain._navigator.begin_target_movement(brain._target_node)
			brain._play_locomotion_animation()


func update(delta: float) -> bool:
	if brain.current_state != &"eat":
		return false

	if has_food():
		if is_begging():
			resume_eating_after_refill()
			return true
		return false

	if not should_beg():
		return false

	if not is_begging():
		begin_begging()

	brain._decision_timer = maxf(float(brain._decision_timer), float(brain.min_decision_time))
	brain._stop_eating_audio()
	brain._start_complaint_audio()

	var user_target: Node3D = brain._resolve_user_follow_target() as Node3D
	if user_target == null:
		brain._target_node = null
		brain._has_reached_target = true
		brain._navigator.clear()
		play_wait_animation(delta)
		return true

	var follow_target: Node3D = brain._floor_target_for_user(user_target) as Node3D
	if brain._target_node != follow_target:
		brain._target_node = follow_target
		brain._has_reached_target = false
		brain._navigator.begin_target_movement(brain._target_node)

	var player_distance: float = float(brain._horizontal_distance_to_node(brain._target_node))
	if player_distance <= float(brain.begging_sit_distance):
		stop_follow()
		play_wait_animation(delta)
		return true

	var resume_distance: float = maxf(float(brain.begging_follow_resume_distance), float(brain.begging_sit_distance) + 0.15)
	if bool(brain._has_reached_target) and player_distance > resume_distance:
		brain._has_reached_target = false
		brain._navigator.begin_target_movement(brain._target_node)
		brain._play_locomotion_animation()
		return true

	if bool(brain._has_reached_target):
		play_wait_animation(delta)
		return true

	return false


func stop_follow() -> void:
	brain._has_reached_target = true
	brain._navigator.clear()
	brain._snap_to_floor_after_player_follow()


func play_wait_animation(delta: float) -> void:
	var target_node: Node3D = brain._target_node as Node3D
	if target_node != null and is_instance_valid(target_node):
		var look_direction: Vector3 = target_node.global_position - brain.global_position
		look_direction.y = 0.0
		brain._navigator.face_direction(look_direction, maxf(delta, 0.016))

	brain._animation_driver.play_sit_wait_animation()


func resume_eating_after_refill() -> void:
	brain._is_begging_for_food = false
	brain._stop_complaint_audio()
	brain._target_node = brain._target_selector.get_target_for_action(&"eat", false)
	brain._decision_timer = brain._decision_window_for_state(&"eat")

	if brain._target_node == null:
		brain._has_reached_target = true
		brain._navigator.clear()
		brain._play_state_animation()
		return

	brain._has_reached_target = false
	brain._navigator.begin_target_movement(brain._target_node)
	brain._play_locomotion_animation()


func finish_eating_state() -> void:
	if brain.current_state != &"eat":
		return

	brain._stop_eating_audio()
	if is_begging():
		brain._stop_complaint_audio()
		brain._is_begging_for_food = false
		return

	if not bool(brain._eat_bowl_emptied):
		_empty_food_bowl()
		brain._eat_bowl_emptied = true


func _empty_food_bowl() -> void:
	var food_bowl: Node = brain._food_bowl as Node
	if food_bowl != null and food_bowl.has_method(&"empty_bowl"):
		food_bowl.call(&"empty_bowl")
