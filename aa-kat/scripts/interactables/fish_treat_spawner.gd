class_name FishTreatSpawner
extends Marker3D

# Table marker that keeps exactly one fish treat available. The first treat can
# be a child in the scene; after Kat eats it, this marker creates the next one.

@export var treat_scene: PackedScene = preload("res://scenes/fish_treat.tscn")
@export var respawn_delay: float = 0.4

var _current_treat: Node3D
var _respawn_timer: float = 0.0


func _ready() -> void:
	add_to_group("fish_treat_spawner")
	_current_treat = _find_existing_treat()
	if _current_treat != null:
		_watch_treat(_current_treat)
	else:
		_spawn_treat()


func _process(delta: float) -> void:
	if _current_treat != null and is_instance_valid(_current_treat):
		return

	if _respawn_timer > 0.0:
		_respawn_timer = maxf(_respawn_timer - delta, 0.0)
		return

	_spawn_treat()


func _find_existing_treat() -> Node3D:
	for child in get_children():
		if child is Node3D and child.is_in_group("fish_treat"):
			return child as Node3D

	return null


func _watch_treat(treat: Node3D) -> void:
	var consumed_callback: Callable = Callable(self, "_on_treat_consumed")
	if treat.has_signal("consumed"):
		if not treat.is_connected("consumed", consumed_callback):
			treat.connect("consumed", consumed_callback)
	treat.tree_exited.connect(_on_treat_tree_exited.bind(treat))


func _spawn_treat() -> void:
	if treat_scene == null:
		return

	var treat: Node3D = treat_scene.instantiate() as Node3D
	if treat == null:
		return

	add_child(treat)
	treat.transform = Transform3D.IDENTITY
	_current_treat = treat
	_watch_treat(treat)


func _on_treat_consumed(treat: Node) -> void:
	if treat == _current_treat:
		_current_treat = null
		_respawn_timer = respawn_delay


func _on_treat_tree_exited(treat: Node) -> void:
	if treat == _current_treat:
		_current_treat = null
		_respawn_timer = respawn_delay
