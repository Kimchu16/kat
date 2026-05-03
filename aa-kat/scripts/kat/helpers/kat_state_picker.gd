class_name KatStatePicker
extends RefCounted

# Weighted state selection. This script is only concerned with deciding what
# Kat should try next, not how that state moves or animates.

var rng: RandomNumberGenerator
var state_selection_noise: float = 0.35
var state_repeat_penalty: float = 0.42
var state_recent_penalty: float = 0.82
var state_fatigue_decay_per_second: float = 0.08
var state_fatigue_on_use: float = 0.7
var min_decision_time: float = 4.0
var max_decision_time: float = 8.5
var social_affection_threshold: float = 0.70
var angry_treat_ignore_threshold: float = 0.60
var anger_avoid_duration_min: float = 4.5
var anger_avoid_duration_max: float = 7.5

var _state_fatigue: Dictionary = {}
var _state_history: Array[StringName] = []


func setup(random: RandomNumberGenerator) -> void:
	rng = random


func decay_fatigue(delta: float) -> void:
	for action in _state_fatigue.keys():
		var fatigue: float = float(_state_fatigue[action])
		_state_fatigue[action] = maxf(0.0, fatigue - state_fatigue_decay_per_second * delta)


func choose_next_state(current_state: StringName, context: Dictionary) -> StringName:
	var scored_actions: Dictionary = _score_actions(context)
	var selected_state: StringName = _sample_next_state(current_state, scored_actions, context)
	_record_state_choice(selected_state)
	return selected_state


func decision_window_for_state(action: StringName) -> float:
	match action:
		&"eat":
			return _random_range(5.5, 11.5)
		&"rest":
			return _random_range(9.0, 18.0)
		&"play":
			return _random_range(5.0, 10.0)
		&"explore":
			return _random_range(2.5, 6.5)
		&"social":
			return _random_range(4.5, 8.0)
		&"avoid":
			return _random_range(anger_avoid_duration_min, anger_avoid_duration_max)
		&"idle":
			return _random_range(1.8, 4.5)
		_:
			return _random_range(min_decision_time, max_decision_time)


func should_social_follow(needs_snapshot: Dictionary) -> bool:
	var affection: float = float(needs_snapshot.get("affection", 0.0))
	var anger: float = float(needs_snapshot.get("anger", 0.0))
	return affection >= social_affection_threshold and anger < angry_treat_ignore_threshold


func _score_actions(context: Dictionary) -> Dictionary:
	var needs_snapshot: Dictionary = context.get("needs", {}) as Dictionary
	var hunger: float = float(needs_snapshot.get("hunger", 0.0))
	var energy: float = float(needs_snapshot.get("energy", 1.0))
	var play: float = float(needs_snapshot.get("play", 1.0))
	var stress: float = float(needs_snapshot.get("stress", 0.0))
	var curiosity: float = float(needs_snapshot.get("curiosity", 0.0))
	var eat_score: float = hunger * 1.45
	if bool(context.get("should_beg_for_food", false)):
		eat_score += 0.75

	return {
		&"eat": eat_score,
		&"rest": (1.0 - energy) * 1.25 + stress * 0.35,
		&"play": (1.0 - play) * 0.95 + curiosity * 0.25,
		&"explore": curiosity * 0.85 + (1.0 - stress) * 0.12,
		&"social": _social_follow_score(needs_snapshot, context),
		&"idle": 0.18,
	}


func _social_follow_score(needs_snapshot: Dictionary, context: Dictionary) -> float:
	if not should_social_follow(needs_snapshot) or not bool(context.get("has_user_target", false)):
		return 0.0

	var affection: float = float(needs_snapshot.get("affection", 0.0))
	var last_interaction_age: float = float(needs_snapshot.get("last_interaction_age", 0.0))
	var affection_bonus: float = maxf(affection - social_affection_threshold, 0.0) * 2.2
	var time_bonus: float = clampf(last_interaction_age / 80.0, 0.0, 0.35)
	return 0.22 + affection_bonus + time_bonus


func _sample_next_state(current_state: StringName, scored_actions: Dictionary, context: Dictionary) -> StringName:
	var weighted_actions: Dictionary = {}
	var total_weight: float = 0.0

	for action in scored_actions:
		var action_name: StringName = action as StringName
		if not _action_is_available(action_name, context):
			continue

		var weight: float = maxf(float(scored_actions[action]), 0.01)
		weight *= _state_noise_for_action(action_name)
		weight *= _state_fatigue_factor(action_name)
		weight *= _settled_state_bias(action_name, context)
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

	var roll: float = _random_value() * total_weight
	for action in weighted_actions:
		roll -= float(weighted_actions[action])
		if roll <= 0.0:
			return action as StringName

	return weighted_actions.keys()[0] as StringName


func _action_is_available(action: StringName, context: Dictionary) -> bool:
	match action:
		&"eat":
			return bool(context.get("can_eat", false))
		&"rest":
			return bool(context.get("can_rest", false))
		&"play":
			return bool(context.get("can_play", false))
		&"explore":
			return bool(context.get("can_explore", false))
		&"social":
			return bool(context.get("can_social", false))
		&"avoid":
			return bool(context.get("has_user_target", false))
		&"idle":
			return true
		_:
			return false


func _state_noise_for_action(action: StringName) -> float:
	var jitter: float = _random_range(1.0 - state_selection_noise, 1.0 + state_selection_noise)
	if action == &"idle" or action == &"explore":
		jitter += 0.12
	if action == &"social":
		jitter += 0.08
	if action == &"eat":
		jitter -= 0.05
	return maxf(jitter, 0.1)


func _state_fatigue_factor(action: StringName) -> float:
	var fatigue: float = float(_state_fatigue.get(action, 0.0))
	return 1.0 / (1.0 + fatigue)


func _settled_state_bias(action: StringName, context: Dictionary) -> float:
	var needs_snapshot: Dictionary = context.get("needs", {}) as Dictionary
	var dominant_need: StringName = needs_snapshot.get("dominant_need", &"settled") as StringName
	if dominant_need == &"settled" or dominant_need == &"curious":
		if action == &"idle" or action == &"explore":
			return 1.45
		if action == &"social" and bool(context.get("can_social", false)):
			return 1.25
		if action == &"eat" or action == &"rest" or action == &"play":
			return 0.82
	return 1.0


func _record_state_choice(action: StringName) -> void:
	_state_history.append(action)
	if _state_history.size() > 5:
		_state_history.remove_at(0)

	var fatigue: float = float(_state_fatigue.get(action, 0.0))
	_state_fatigue[action] = clampf(fatigue + state_fatigue_on_use, 0.0, 2.5)


func _random_range(from_value: float, to_value: float) -> float:
	if rng == null:
		return (from_value + to_value) * 0.5
	return rng.randf_range(from_value, to_value)


func _random_value() -> float:
	if rng == null:
		return randf()
	return rng.randf()
