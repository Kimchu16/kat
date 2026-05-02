class_name KatAnimationDriver
extends RefCounted

# Small wrapper around AnimationPlayer. This keeps animation name lookups and
# enter/idle/exit handling out of the autonomy controller.

const ACTION_ANIMATIONS: Dictionary = {
	&"idle": &"Idle",
	&"eat": &"Eat",
	&"rest": &"Sleep",
	&"play": &"Pounce",
	&"explore": &"Run",
}

const LOCOMOTION_ANIMATION: StringName = &"Run"
const JUMP_ANIMATION: StringName = &"Pounce"
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

var animation_player: AnimationPlayer


func setup(player: AnimationPlayer) -> void:
	animation_player = player


func play_state_animation(current_state: StringName) -> void:
	if animation_player == null:
		return

	# Explore uses Run while travelling, but once Kat reaches the point it should
	# settle instead of running on the spot.
	if current_state == &"explore":
		play_idle_animation()
		return

	# Sleep is split into enter/idle/exit clips, so try that path before using a
	# single animation name.
	if play_action_phase_animation(current_state, PHASE_ENTER, 0.2):
		return

	var animation_name: StringName = ACTION_ANIMATIONS.get(current_state, &"Idle") as StringName
	if animation_player.has_animation(animation_name):
		animation_player.play(animation_name, 0.2)


func play_locomotion_animation(is_jumping: bool) -> void:
	if animation_player == null:
		return

	var animation_name: StringName = LOCOMOTION_ANIMATION
	var blend_time: float = 0.15
	if is_jumping and animation_player.has_animation(JUMP_ANIMATION):
		animation_name = JUMP_ANIMATION
		blend_time = 0.08

	if animation_player.has_animation(animation_name):
		if StringName(animation_player.current_animation) != animation_name or not animation_player.is_playing():
			animation_player.play(animation_name, blend_time)


func play_idle_animation() -> void:
	if animation_player == null:
		return

	if animation_player.has_animation(&"Idle"):
		if StringName(animation_player.current_animation) != &"Idle" or not animation_player.is_playing():
			animation_player.play(&"Idle", 0.15)


func play_attention_animation() -> void:
	if animation_player == null:
		return

	if animation_player.has_animation(ATTENTION_ANIMATION):
		animation_player.play(ATTENTION_ANIMATION, 0.12)


func play_action_phase_animation(action: StringName, phase: StringName, blend: float) -> bool:
	if animation_player == null:
		return false

	var animation_name: StringName = get_action_phase_animation(action, phase)
	if animation_name == &"":
		return false

	if not animation_player.has_animation(animation_name):
		return false

	animation_player.play(animation_name, blend)
	return true


func get_action_phase_animation(action: StringName, phase: StringName) -> StringName:
	if not PHASED_ACTION_ANIMATIONS.has(action):
		return &""

	var phase_animations: Dictionary = PHASED_ACTION_ANIMATIONS[action] as Dictionary
	return phase_animations.get(phase, &"") as StringName


func animation_matches_phase(action: StringName, phase: StringName, animation_name: StringName) -> bool:
	return get_action_phase_animation(action, phase) == animation_name
