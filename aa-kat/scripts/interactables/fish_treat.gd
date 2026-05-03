class_name FishTreat
extends "res://addons/godot-xr-tools/objects/pickable.gd"

signal consumed(treat: FishTreat)

# Pickable fish treat. Kat calls consume() once the treat reaches the small
# feeding area near her mouth, then the spawner makes the next one.

var _consumed: bool = false


func _ready() -> void:
	super._ready()
	add_to_group("fish_treat")


func is_consumed() -> bool:
	return _consumed


func get_holder_node() -> Node3D:
	var controller: Node3D = get_picked_up_by_controller()
	if controller != null:
		return controller

	return get_picked_up_by()


func consume() -> void:
	if _consumed:
		return

	_consumed = true
	enabled = false
	visible = false
	collision_layer = 0
	collision_mask = 0
	consumed.emit(self)
	queue_free()
