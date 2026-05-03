class_name FoodBowl
extends Node3D

# The bowl only controls the visual state for now. Later the VR hand/object
# interaction can call fill_bowl() when the player adds food.

@export var starts_full: bool = true
@export var full_visual_path: NodePath = NodePath("FoodFull")

var has_food: bool = true

var _full_visual: Node3D


func _ready() -> void:
	_full_visual = get_node_or_null(full_visual_path) as Node3D
	set_has_food(starts_full)


func fill_bowl() -> void:
	set_has_food(true)


func empty_bowl() -> void:
	set_has_food(false)


func set_has_food(value: bool) -> void:
	has_food = value
	if _full_visual != null:
		_full_visual.visible = has_food


func has_food_available() -> bool:
	return has_food
