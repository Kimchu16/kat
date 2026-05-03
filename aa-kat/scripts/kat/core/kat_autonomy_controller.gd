class_name KatAutonomyController
extends Node3D

# Main "brain" for Kat. This script keeps the high-level state flow, while
# audio, ball steering, sensing, target picking, navigation and UI live in
# small helper scripts.

@export var autonomy_enabled: bool = true
@export var target_root_path: NodePath = NodePath("../KatTargets")
@export var food_bowl_path: NodePath = NodePath("../Furniture/Food Bowl")
@export var eating_audio_path: NodePath = NodePath("../Furniture/Food Bowl/KatEating")
@export var eating_audio_stream: AudioStream = preload("res://audio/sfx/cat-eating.mp3")
@export var eating_audio_volume_db: float = 5.0
@export var user_follow_target_path: NodePath = NodePath("../QuestVRPlayer/XROrigin3D")
@export var complaint_audio_stream: AudioStream = preload("res://audio/sfx/cat-complaint.mp3")
@export var complaint_audio_volume_db: float = 4.0
@export var hungry_beg_threshold: float = 0.62
@export var begging_sit_distance: float = 1.05
@export var begging_follow_resume_distance: float = 1.35
@export var treat_notice_area_path: NodePath = NodePath("TreatNoticeArea")
@export var treat_feed_area_path: NodePath = NodePath("TreatFeedArea")
@export var treat_eating_particles_path: NodePath = NodePath("TreatEatingParticles")
@export var treat_meow_stream: AudioStream = preload("res://audio/sfx/cat-meow-short.mp3")
@export var purr_audio_stream: AudioStream = preload("res://audio/sfx/cats-purring2.mp3")
@export var hiss_audio_stream: AudioStream = preload("res://audio/sfx/cat_hiss.mp3")
@export var hiss_audio_volume_db: float = 4.0
@export var treat_attention_time: float = 1.1
@export var treat_wait_distance: float = 0.95
@export var treat_follow_resume_distance: float = 1.25
@export var treat_meow_interval: float = 5.0
@export var treat_eat_duration: float = 1.7
@export var treat_affection_reward: float = 0.24
@export var treat_tease_penalty: float = 0.14
@export var purr_affection_threshold: float = 0.70
@export var social_affection_threshold: float = 0.70
@export var social_follow_stop_distance: float = 1.05
@export var social_follow_resume_distance: float = 1.45
@export var angry_treat_ignore_threshold: float = 0.60
@export var anger_avoid_threshold: float = 0.80
@export var anger_avoid_duration_min: float = 4.5
@export var anger_avoid_duration_max: float = 7.5
@export var angry_treat_reject_duration: float = 3.5
@export var avoid_target_distance: float = 1.85
@export var avoid_resume_distance: float = 1.45
@export var avoid_meow_interval: float = 4.0
@export var avoid_warning_distance: float = 1.05
@export var avoid_warning_cooldown: float = 2.4
@export var avoid_warning_pause: float = 0.7
@export var low_affection_threshold: float = 0.32
@export var low_affection_keep_distance: float = 1.45
@export var low_affection_avoid_duration: float = 3.0

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
@export var ball_obstacle_avoidance_distance: float = 0.9
@export_range(0.0, 1.0, 0.05) var ball_obstacle_avoidance_bias: float = 0.8
@export var ball_obstacle_avoidance_mask: int = 1
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
const KAT_TARGET_SELECTOR_SCRIPT: GDScript = preload("res://scripts/kat/helpers/kat_target_selector.gd")
const KAT_NAVIGATOR_SCRIPT: GDScript = preload("res://scripts/kat/helpers/kat_navigator.gd")
const KAT_ANIMATION_DRIVER_SCRIPT: GDScript = preload("res://scripts/kat/helpers/kat_animation_driver.gd")
const KAT_AUDIO_CONTROLLER_SCRIPT: GDScript = preload("res://scripts/kat/helpers/kat_audio_controller.gd")
const KAT_BALL_PLAY_SCRIPT: GDScript = preload("res://scripts/kat/helpers/kat_ball_play.gd")
const KAT_STATE_PICKER_SCRIPT: GDScript = preload("res://scripts/kat/helpers/kat_state_picker.gd")
const KAT_TREAT_SENSOR_SCRIPT: GDScript = preload("res://scripts/kat/helpers/kat_treat_sensor.gd")
const KAT_DEBUG_DISPLAY_SCRIPT: GDScript = preload("res://scripts/kat/helpers/kat_debug_display.gd")
const KAT_POSITION_HELPER_SCRIPT: GDScript = preload("res://scripts/kat/helpers/kat_position_helper.gd")
const KAT_FOOD_BEHAVIOUR_SCRIPT: GDScript = preload("res://scripts/kat/behaviours/kat_food_behaviour.gd")
const KAT_PLAY_BEHAVIOUR_SCRIPT: GDScript = preload("res://scripts/kat/behaviours/kat_play_behaviour.gd")
const KAT_RELATIONSHIP_BEHAVIOUR_SCRIPT: GDScript = preload("res://scripts/kat/behaviours/kat_relationship_behaviour.gd")
const KAT_TREAT_BEHAVIOUR_SCRIPT: GDScript = preload("res://scripts/kat/behaviours/kat_treat_behaviour.gd")
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
var _audio: Variant = KAT_AUDIO_CONTROLLER_SCRIPT.new()
var _ball_play: Variant = KAT_BALL_PLAY_SCRIPT.new()
var _state_picker: Variant = KAT_STATE_PICKER_SCRIPT.new()
var _treat_sensor: Variant = KAT_TREAT_SENSOR_SCRIPT.new()
var _debug_display: Variant = KAT_DEBUG_DISPLAY_SCRIPT.new()
var _position_helper: Variant = KAT_POSITION_HELPER_SCRIPT.new()
var _food_behavior: Variant = KAT_FOOD_BEHAVIOUR_SCRIPT.new()
var _play_behavior: Variant = KAT_PLAY_BEHAVIOUR_SCRIPT.new()
var _relationship_behavior: Variant = KAT_RELATIONSHIP_BEHAVIOUR_SCRIPT.new()
var _treat_behavior: Variant = KAT_TREAT_BEHAVIOUR_SCRIPT.new()
var _animation_player: AnimationPlayer
var _pounce_hitbox: Area3D
var _decision_timer: float = 0.0
var _pounce_impulse_sent: bool = false
var _eat_bowl_emptied: bool = false
var _is_begging_for_food: bool = false
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
	_setup_role_modules()
	_target_selector.setup_roam_target()
	_target_selector.collect_targets()
	_setup_debug_label()
	needs.changed.connect(_on_needs_changed)
	_choose_next_state()


func _process(delta: float) -> void:
	if not autonomy_enabled:
		_audio.stop_all()
		_set_treat_eating_particles(false)
		return

	_sync_helper_config()
	_state_picker.decay_fatigue(delta)
	needs.tick(delta, current_state == &"play")
	_update_purr_audio()
	if bool(_treat_behavior.update(delta)):
		return
	if _is_exiting_state:
		return
	if bool(_food_behavior.update(delta)):
		return
	if _update_relationship_behaviour(delta):
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
			if _is_begging_for_food:
				_food_behavior.play_wait_animation(delta)
			else:
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


func _setup_role_modules() -> void:
	_state_picker.setup(_rng)
	_ball_play.setup(self)
	_position_helper.setup(self)
	_food_behavior.setup(self)
	_play_behavior.setup(self)
	_relationship_behavior.setup(self)
	_audio.setup(
		self,
		_food_bowl,
		eating_audio_path,
		eating_audio_stream,
		eating_audio_volume_db,
		complaint_audio_stream,
		complaint_audio_volume_db,
		treat_meow_stream,
		purr_audio_stream,
		hiss_audio_stream,
		hiss_audio_volume_db
	)
	_treat_sensor.setup(self, treat_notice_area_path, treat_feed_area_path, treat_eating_particles_path)
	_treat_behavior.setup(self, _treat_sensor)
	_treat_behavior.avoidance_requested.connect(_on_treat_avoidance_requested)
	_sync_helper_config()


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

	_ball_play.pounce_impulse = pounce_impulse
	_ball_play.play_bounds_min = ball_play_bounds_min
	_ball_play.play_bounds_max = ball_play_bounds_max
	_ball_play.edge_turn_margin = ball_edge_turn_margin
	_ball_play.inward_push_bias = ball_inward_push_bias
	_ball_play.obstacle_avoidance_distance = ball_obstacle_avoidance_distance
	_ball_play.obstacle_avoidance_bias = ball_obstacle_avoidance_bias
	_ball_play.obstacle_avoidance_mask = ball_obstacle_avoidance_mask

	_state_picker.state_selection_noise = state_selection_noise
	_state_picker.state_repeat_penalty = state_repeat_penalty
	_state_picker.state_recent_penalty = state_recent_penalty
	_state_picker.state_fatigue_decay_per_second = state_fatigue_decay_per_second
	_state_picker.state_fatigue_on_use = state_fatigue_on_use
	_state_picker.min_decision_time = min_decision_time
	_state_picker.max_decision_time = max_decision_time
	_state_picker.social_affection_threshold = social_affection_threshold
	_state_picker.angry_treat_ignore_threshold = angry_treat_ignore_threshold
	_state_picker.anger_avoid_duration_min = anger_avoid_duration_min
	_state_picker.anger_avoid_duration_max = anger_avoid_duration_max

	_position_helper.user_follow_target_path = user_follow_target_path
	_position_helper.floor_height = floor_height
	_position_helper.elevated_target_min_height = elevated_target_min_height
	_position_helper.avoid_target_distance = avoid_target_distance
	_position_helper.room_roam_min = room_roam_min
	_position_helper.room_roam_max = room_roam_max


func _choose_next_state() -> void:
	_sync_helper_config()
	var selected_state: StringName = StringName(_state_picker.choose_next_state(current_state, _state_context()))

	current_state = selected_state
	_target_node = _target_for_state(current_state)
	_play_behavior.reset()
	_eat_bowl_emptied = false
	_is_begging_for_food = current_state == &"eat" and bool(_food_behavior.should_beg())
	_relationship_behavior.reset()
	if _is_begging_for_food:
		var user_target: Node3D = _resolve_user_follow_target()
		if user_target != null:
			_target_node = _floor_target_for_user(user_target)
		_start_complaint_audio()
		_stop_eating_audio()
	else:
		_stop_complaint_audio()
	_is_exiting_state = false
	_has_reached_target = _target_node == null
	if _target_node != null:
		_navigator.begin_target_movement(_target_node)
	else:
		_navigator.clear()
	if current_state != &"explore" and current_state != &"idle":
		_navigator.clear_explore_wander_offset()
	_decision_timer = _decision_window_for_state(current_state)
	if _has_reached_target:
		if _is_begging_for_food:
			_food_behavior.play_wait_animation(1.0)
		else:
			_play_state_animation()
	else:
		_play_locomotion_animation()
	_update_debug_label(needs.snapshot())


func _target_for_state(action: StringName) -> Node3D:
	if action == &"social":
		var user_target: Node3D = _resolve_user_follow_target()
		if user_target == null:
			return null
		return _floor_target_for_user(user_target)
	if action == &"avoid":
		return null
	return _target_selector.get_target_for_action(action, true)


func _should_social_follow_player() -> bool:
	return bool(_state_picker.should_social_follow(needs.snapshot()))


func _state_context() -> Dictionary:
	return {
		"needs": needs.snapshot(),
		"should_beg_for_food": _food_behavior.should_beg(),
		"has_user_target": _resolve_user_follow_target() != null,
		"can_eat": _target_selector.action_is_available(&"eat") and (bool(_food_behavior.has_food()) or bool(_food_behavior.should_beg())),
		"can_rest": _target_selector.action_is_available(&"rest"),
		"can_play": _target_selector.action_is_available(&"play"),
		"can_explore": _target_selector.action_is_available(&"explore"),
		"can_social": _should_social_follow_player() and _resolve_user_follow_target() != null,
	}


func _decision_window_for_state(action: StringName) -> float:
	return float(_state_picker.decision_window_for_state(action))


func _apply_arrival_effects(delta: float) -> void:
	match current_state:
		&"eat":
			if _is_begging_for_food or not bool(_food_behavior.has_food()):
				if bool(_food_behavior.should_beg()):
					_food_behavior.begin_begging()
				return
			_stop_complaint_audio()
			_start_eating_audio()
			needs.nibble(delta)
		&"rest":
			needs.rest(delta)
		&"play":
			_play_behavior.apply_arrival_effects(delta)
		&"explore":
			needs.curiosity = clampf(needs.curiosity - 0.045 * delta, 0.0, 1.0)
			needs.stress = clampf(needs.stress - 0.012 * delta, 0.0, 1.0)
			needs.changed.emit(needs.snapshot())
		&"social":
			needs.socialise(delta * 0.45)
		&"avoid":
			if _relationship_behavior.avoid_reason == &"anger" or _relationship_behavior.avoid_reason == &"treat":
				needs.calm_down(delta)


func _update_play_chase_loop(delta: float) -> bool:
	return bool(_play_behavior.update_chase_loop(delta))


func _update_relationship_behaviour(delta: float) -> bool:
	return bool(_relationship_behavior.update(delta, _relationship_can_take_over()))


func _relationship_can_take_over() -> bool:
	if bool(_treat_behavior.blocks_relationship()):
		return false
	if bool(_food_behavior.is_begging()):
		return false
	if current_state == &"eat":
		return false
	return true


func _avoid_target_from(source: Node3D) -> Node3D:
	return _position_helper.avoid_target_from(source, _navigator.get_visual_forward_direction()) as Node3D


func _resolve_user_follow_target() -> Node3D:
	return _position_helper.resolve_user_follow_target() as Node3D


func _floor_target_for_user(user_target: Node3D) -> Node3D:
	return _position_helper.floor_target_for_user(user_target) as Node3D


func _snap_to_floor_after_player_follow() -> void:
	_position_helper.snap_actor_to_floor_after_follow()


func _horizontal_distance_to_node(node: Node3D) -> float:
	return float(_position_helper.horizontal_distance_to_node(node))


func _finish_eating_state() -> void:
	_food_behavior.finish_eating_state()


func _clear_food_begging() -> void:
	_food_behavior.clear_begging()


func catch_attention(source: Node3D = null) -> void:
	_stop_eating_audio()
	_stop_complaint_audio()
	_stop_treat_meow_audio()
	_treat_behavior.stop_particles()
	_food_behavior.clear_begging()
	_treat_behavior.clear(false)
	current_state = &"attention"
	_target_node = null
	_has_reached_target = true
	_is_exiting_state = false
	_navigator.clear()
	_play_behavior.clear_reengage_timer()
	_decision_timer = min_decision_time
	needs.socialise(0.6)
	if source != null:
		var direction: Vector3 = source.global_position - global_position
		direction.y = 0.0
		_navigator.face_direction(direction, 1.0)
	_play_attention_animation()
	_update_debug_label(needs.snapshot())


func _floor_target_for_treat_holder(holder: Node3D) -> Node3D:
	return _position_helper.floor_target_for_treat_holder(holder) as Node3D


func _face_node(node: Node3D, delta: float) -> void:
	if node == null:
		return

	var direction: Vector3 = node.global_position - global_position
	direction.y = 0.0
	_navigator.face_direction(direction, maxf(delta, 0.016))


func _on_treat_avoidance_requested(source: Node3D, duration: float, reason: StringName, should_meow: bool) -> void:
	_relationship_behavior.start_avoidance_from(source, duration, reason, should_meow)


func _on_pounce_hitbox_body_entered(body: Node3D) -> void:
	_play_behavior.on_pounce_hitbox_body_entered(body)


func _play_state_animation() -> void:
	_animation_driver.play_state_animation(current_state)


func _play_locomotion_animation() -> void:
	_animation_driver.play_locomotion_animation(_navigator.is_jumping())


func _finish_current_state() -> void:
	_finish_eating_state()
	if _animation_driver.play_action_phase_animation(current_state, PHASE_EXIT, 0.12):
		_is_exiting_state = true
		_target_node = null
		_has_reached_target = true
		_navigator.clear()
		_play_behavior.clear_reengage_timer()
		return

	_choose_next_state()


func _start_eating_audio() -> void:
	_audio.start_eating()


func _stop_eating_audio() -> void:
	_audio.stop_eating()


func _start_complaint_audio() -> void:
	_audio.start_complaint()


func _stop_complaint_audio() -> void:
	_audio.stop_complaint()


func _play_treat_meow_audio() -> void:
	_audio.play_treat_meow()


func _stop_treat_meow_audio() -> void:
	_audio.stop_treat_meow()


func _update_purr_audio() -> void:
	var should_purr: bool = needs.affection >= purr_affection_threshold and needs.anger < 0.35 and needs.stress < 0.45
	_audio.update_purr(should_purr)


func _stop_purr_audio() -> void:
	_audio.stop_purr()


func _play_hiss_audio() -> void:
	_audio.play_hiss()


func _stop_hiss_audio() -> void:
	_audio.stop_hiss()


func _set_treat_eating_particles(enabled: bool) -> void:
	_treat_sensor.set_eating_particles(enabled)


func _on_animation_finished(animation_name: StringName) -> void:
	if (_is_begging_for_food or bool(_treat_behavior.is_waiting())) and _animation_driver.continue_sit_wait_animation(animation_name):
		return

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
	_debug_display.setup(self, show_debug_label)


func _on_needs_changed(snapshot: Dictionary) -> void:
	_update_debug_label(snapshot)


func _update_debug_label(snapshot: Dictionary) -> void:
	_debug_display.update(current_state, snapshot)
