class_name KatAutonomyController
extends Node3D

@export var autonomy_enabled: bool = true
@export var target_root_path: NodePath = NodePath("../KatTargets")
@export var move_speed: float = 0.85
@export var turn_speed: float = 6.0
@export var arrival_radius: float = 0.22
@export var pounce_impulse: float = 0.65
@export var min_decision_time: float = 4.0
@export var max_decision_time: float = 8.5
@export var show_debug_label: bool = true

const ACTION_ANIMATIONS: Dictionary = {
	&"idle": &"Idle",
	&"eat": &"Sit",
	&"rest": &"Sleep",
	&"play": &"Pounce",
	&"explore": &"Run",
}

const ATTENTION_ANIMATION: StringName = &"AttentionCaught"

var needs: KatNeeds = KatNeeds.new()
var current_state: StringName = &"idle"

var _targets: Dictionary = {}
var _target_node: Node3D
var _animation_player: AnimationPlayer
var _pounce_hitbox: Area3D
var _debug_label: Label3D
var _decision_timer: float = 0.0
var _pounce_impulse_sent: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_animation_player = get_node_or_null("AnimationPlayer") as AnimationPlayer
	_pounce_hitbox = get_node_or_null("PounceHitbox") as Area3D
	if _pounce_hitbox != null:
		_pounce_hitbox.body_entered.connect(_on_pounce_hitbox_body_entered)
	_collect_targets()
	_setup_debug_label()
	needs.changed.connect(_on_needs_changed)
	_choose_next_state()


func _process(delta: float) -> void:
	if not autonomy_enabled:
		return

	needs.tick(delta)
	_decision_timer -= delta

	if _target_node == null:
		if _decision_timer <= 0.0:
			_choose_next_state()
		return

	var arrived: bool = _move_towards_target(delta)
	if arrived:
		_apply_arrival_effects(delta)

	if _decision_timer <= 0.0 and (arrived or current_state == &"idle"):
		_choose_next_state()


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
	var selected_state: StringName = &"idle"
	var best_score: float = 0.18

	for action in scored_actions:
		var action_name: StringName = action as StringName
		if action_name != &"idle" and _get_target_for_action(action_name) == null:
			continue

		var score: float = float(scored_actions[action])
		if score > best_score:
			best_score = score
			selected_state = action_name

	current_state = selected_state
	_target_node = _get_target_for_action(current_state)
	_pounce_impulse_sent = false
	_decision_timer = _rng.randf_range(min_decision_time, max_decision_time)
	_play_state_animation()
	_update_debug_label(needs.snapshot())


func _score_actions() -> Dictionary:
	return {
		&"eat": needs.hunger * 1.45,
		&"rest": (1.0 - needs.energy) * 1.25 + needs.stress * 0.35,
		&"play": (1.0 - needs.play) * 0.95 + needs.curiosity * 0.25,
		&"explore": needs.curiosity * 0.85 + (1.0 - needs.stress) * 0.12,
		&"idle": 0.18,
	}


func _get_target_for_action(action: StringName) -> Node3D:
	match action:
		&"eat":
			return _targets.get(&"FoodTarget") as Node3D
		&"rest":
			return _targets.get(&"RestTarget") as Node3D
		&"play":
			return _targets.get(&"PlayTarget") as Node3D
		&"explore":
			return _pick_explore_target()
		_:
			return null


func _pick_explore_target() -> Node3D:
	var explore_targets: Array[Node3D] = []
	for key in [&"ExploreTargetA", &"ExploreTargetB"]:
		var target: Node3D = _targets.get(key) as Node3D
		if target != null:
			explore_targets.append(target)

	if explore_targets.is_empty():
		return null

	return explore_targets[_rng.randi_range(0, explore_targets.size() - 1)]


func _move_towards_target(delta: float) -> bool:
	var current_position: Vector3 = global_position
	var target_position: Vector3 = _target_node.global_position
	target_position.y = current_position.y

	var offset: Vector3 = target_position - current_position
	if offset.length() <= arrival_radius:
		return true

	var direction: Vector3 = offset.normalized()
	var state_speed: float = _speed_for_current_state()
	global_position = current_position.move_toward(target_position, state_speed * delta)
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

	var target_yaw: float = atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, min(turn_speed * delta, 1.0))


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
		impulse_direction = -global_transform.basis.z + Vector3.UP * 0.08

	ball.apply_central_impulse(impulse_direction.normalized() * pounce_impulse)


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

	var animation_name: StringName = ACTION_ANIMATIONS.get(current_state, &"Idle") as StringName
	if _animation_player.has_animation(animation_name):
		_animation_player.play(animation_name, 0.2)


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

	_debug_label.position = Vector3(0.0, 0.95, 0.0)
	_debug_label.pixel_size = 0.015
	_debug_label.font_size = 26
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
