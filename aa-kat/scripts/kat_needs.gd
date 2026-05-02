class_name KatNeeds
extends RefCounted

signal changed(snapshot: Dictionary)

# Tiny need model for Kat. Higher hunger means "more hungry"; higher play means
# "more satisfied with play", so play slowly drops over time.

const MIN_VALUE: float = 0.0
const MAX_VALUE: float = 1.0

var hunger: float = 0.32
var energy: float = 0.82
var play: float = 0.62
var affection: float = 0.46
var curiosity: float = 0.58
var trust: float = 0.50
var stress: float = 0.08
var last_interaction_age: float = 0.0


func tick(delta: float, is_playing: bool = false) -> void:
	# These rates are deliberately small so the cat changes mood over minutes,
	# not every few seconds.
	hunger = _bounded(hunger + 0.030 * delta)
	energy = _bounded(energy - (0.012 + stress * 0.010) * delta)
	# Do not drain play during the play state, otherwise the reward from chasing
	# the ball gets cancelled out and Kat keeps choosing play again.
	if not is_playing:
		play = _bounded(play - 0.020 * delta)
	affection = _bounded(affection - 0.008 * delta)
	curiosity = _bounded(curiosity + 0.010 * delta)
	stress = _bounded(stress - 0.020 * delta)
	last_interaction_age += delta
	changed.emit(snapshot())


func feed(amount: float = 0.42) -> void:
	hunger = _bounded(hunger - amount)
	energy = _bounded(energy + amount * 0.10)
	trust = _bounded(trust + amount * 0.14)
	affection = _bounded(affection + amount * 0.07)
	stress = _bounded(stress - amount * 0.08)
	last_interaction_age = 0.0
	changed.emit(snapshot())


func play_with(amount: float = 0.34) -> void:
	play = _bounded(play + amount)
	curiosity = _bounded(curiosity + amount * 0.20)
	affection = _bounded(affection + amount * 0.12)
	trust = _bounded(trust + amount * 0.08)
	energy = _bounded(energy - amount * 0.18)
	last_interaction_age = 0.0
	changed.emit(snapshot())


func pet(amount: float = 0.25) -> void:
	affection = _bounded(affection + amount)
	trust = _bounded(trust + amount * 0.18)
	stress = _bounded(stress - amount * 0.20)
	last_interaction_age = 0.0
	changed.emit(snapshot())


func startle(amount: float = 0.28) -> void:
	stress = _bounded(stress + amount)
	trust = _bounded(trust - amount * 0.12)
	affection = _bounded(affection - amount * 0.05)
	last_interaction_age = 0.0
	changed.emit(snapshot())


func rest(delta: float) -> void:
	energy = _bounded(energy + 0.130 * delta)
	play = _bounded(play - 0.006 * delta)
	stress = _bounded(stress - 0.050 * delta)
	changed.emit(snapshot())


func nibble(delta: float) -> void:
	hunger = _bounded(hunger - 0.180 * delta)
	energy = _bounded(energy + 0.025 * delta)
	changed.emit(snapshot())


func chase(delta: float) -> void:
	play = _bounded(play + 0.060 * delta)
	energy = _bounded(energy - 0.045 * delta)
	curiosity = _bounded(curiosity - 0.035 * delta)
	changed.emit(snapshot())


func socialise(delta: float) -> void:
	affection = _bounded(affection + 0.060 * delta)
	trust = _bounded(trust + 0.030 * delta)
	stress = _bounded(stress - 0.030 * delta)
	changed.emit(snapshot())


func dominant_need() -> StringName:
	# Order matters here. Hunger/tiredness should override less urgent moods.
	if hunger > 0.76:
		return &"hungry"
	if energy < 0.30:
		return &"tired"
	if stress > 0.56:
		return &"nervous"
	if affection < 0.28 or last_interaction_age > 38.0:
		return &"lonely"
	if play < 0.34:
		return &"playful"
	if curiosity > 0.78:
		return &"curious"
	return &"settled"


func mood() -> StringName:
	var need: StringName = dominant_need()
	match need:
		&"hungry":
			return &"hungry"
		&"tired":
			return &"sleepy"
		&"nervous":
			return &"guarded"
		&"lonely":
			return &"needy"
		&"playful":
			return &"playful"
		&"curious":
			return &"curious"
		_:
			return &"content"


func snapshot() -> Dictionary:
	return {
		"hunger": hunger,
		"energy": energy,
		"play": play,
		"affection": affection,
		"curiosity": curiosity,
		"trust": trust,
		"stress": stress,
		"dominant_need": dominant_need(),
		"mood": mood(),
	}


func _bounded(value: float) -> float:
	return clampf(value, MIN_VALUE, MAX_VALUE)
