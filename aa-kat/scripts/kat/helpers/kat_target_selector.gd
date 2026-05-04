class_name KatTargetSelector
extends RefCounted

# Keeps all target lookup and random roaming code out of the main controller.
# The controller asks for "a play target" or "an explore target"; this decides
# which Marker3D should actually be used.

const FLOOR_EXPLORE_TARGETS: Array[StringName] = [&"ExploreTargetA", &"ExploreTargetB"]
const ELEVATED_EXPLORE_TARGETS: Array[StringName] = [
	&"CouchTarget",
	&"CatTreeSmallTarget",
	&"CatTreePerchTarget",
	&"PillowTarget",
]
const REST_TARGETS: Array[StringName] = [&"RestTarget", &"PillowTarget"]

var owner: Node3D
var rng: RandomNumberGenerator
var target_root_path: NodePath = NodePath("../KatTargets")
var floor_height: float = 0.0
var elevated_explore_chance: float = 0.65
var roam_procedural_chance: float = 0.55
var room_roam_min: Vector2 = Vector2(-3.2, -2.95)
var room_roam_max: Vector2 = Vector2(3.25, 2.9)
var roam_pick_min_distance: float = 1.35
var roam_obstacle_check_radius: float = 0.32
var roam_obstacle_collision_mask: int = 1
var targets: Dictionary = {}

var _roam_target: Node3D
var _ground_explore_picks_since_elevated: int = 0


func setup(actor: Node3D, random: RandomNumberGenerator) -> void:
	owner = actor
	rng = random


func setup_roam_target() -> void:
	if owner == null:
		return

	# The procedural target is just a hidden point that gets moved around the
	# room. This makes idle/explore feel less like fixed marker hopping.
	_roam_target = owner.get_node_or_null("ProceduralRoamTarget") as Node3D
	var roam_parent: Node = owner.get_node_or_null(target_root_path)
	if roam_parent == null:
		roam_parent = owner.get_tree().current_scene

	if _roam_target == null:
		_roam_target = Node3D.new()
		_roam_target.name = "ProceduralRoamTarget"
		roam_parent.add_child(_roam_target)
	elif _roam_target.get_parent() != roam_parent:
		_roam_target.reparent(roam_parent, true)

	refresh_roam_target(true)


func collect_targets() -> void:
	targets.clear()
	if owner == null:
		return

	# Most targets are direct children of KatTargets, but the play target lives
	# under the ball so it can move with the ball.
	var target_root: Node = owner.get_node_or_null(target_root_path)
	if target_root == null:
		return

	for child in target_root.get_children():
		if child is Node3D:
			targets[child.name] = child

	var play_target: Node3D = owner.get_node_or_null("../Ball/PlayTarget") as Node3D
	if play_target != null:
		targets[&"PlayTarget"] = play_target


func action_is_available(action: StringName) -> bool:
	match action:
		&"eat":
			return targets.get(&"FoodTarget") != null
		&"rest":
			return _has_any_target(REST_TARGETS)
		&"play":
			return targets.get(&"PlayTarget") != null
		&"explore":
			return _roam_target != null or _has_any_target(FLOOR_EXPLORE_TARGETS) or _has_any_target(ELEVATED_EXPLORE_TARGETS)
		&"idle":
			return true
		_:
			return false


func get_target_for_action(action: StringName, refresh_roam: bool = false) -> Node3D:
	match action:
		&"eat":
			return targets.get(&"FoodTarget") as Node3D
		&"rest":
			return _pick_target_from_names(REST_TARGETS)
		&"play":
			return targets.get(&"PlayTarget") as Node3D
		&"explore":
			return _pick_explore_target()
		&"idle":
			if refresh_roam:
				refresh_roam_target(true)
			return _roam_target
		_:
			return null


func refresh_roam_target(force: bool = false) -> void:
	if _roam_target == null or owner == null:
		return

	# Keep the current roam target until Kat gets close enough; otherwise the
	# destination changes too often and the cat looks confused.
	if not force and _roam_target.global_position.distance_to(owner.global_position) > roam_pick_min_distance:
		return

	var min_x: float = minf(room_roam_min.x, room_roam_max.x)
	var max_x: float = maxf(room_roam_min.x, room_roam_max.x)
	var min_z: float = minf(room_roam_min.y, room_roam_max.y)
	var max_z: float = maxf(room_roam_min.y, room_roam_max.y)
	var candidate: Vector3 = _roam_target.global_position
	for i in range(18):
		candidate = Vector3(
			rng.randf_range(min_x, max_x),
			floor_height,
			rng.randf_range(min_z, max_z)
		)
		if candidate.distance_to(owner.global_position) < roam_pick_min_distance:
			continue
		if not _roam_candidate_is_clear(candidate):
			continue

		_roam_target.global_position = candidate
		return

	if not _roam_candidate_is_clear(_roam_target.global_position):
		_roam_target.global_position = Vector3(0.0, floor_height, 0.2)


func _pick_explore_target() -> Node3D:
	# Explore is a mix of furniture climbing and floor roaming. The exact chance
	# is exported so it can be tuned in the editor during testing.
	var elevated_targets: Array[Node3D] = _collect_targets_from_names(ELEVATED_EXPLORE_TARGETS)
	var should_force_elevated: bool = _ground_explore_picks_since_elevated >= 2
	var should_pick_elevated: bool = not elevated_targets.is_empty() and (should_force_elevated or rng.randf() < elevated_explore_chance)
	if should_pick_elevated:
		_ground_explore_picks_since_elevated = 0
		return elevated_targets[rng.randi_range(0, elevated_targets.size() - 1)]

	if _roam_target != null and rng.randf() < roam_procedural_chance:
		refresh_roam_target(true)
		_note_ground_explore_pick()
		return _roam_target

	var explore_targets: Array[Node3D] = _collect_targets_from_names(FLOOR_EXPLORE_TARGETS)

	if explore_targets.is_empty():
		if _roam_target != null:
			refresh_roam_target(true)
			_note_ground_explore_pick()
		return _roam_target

	if _roam_target != null and rng.randf() < 0.35:
		refresh_roam_target(true)
		_note_ground_explore_pick()
		return _roam_target

	_note_ground_explore_pick()
	return explore_targets[rng.randi_range(0, explore_targets.size() - 1)]


func _note_ground_explore_pick() -> void:
	_ground_explore_picks_since_elevated += 1


func _roam_candidate_is_clear(candidate: Vector3) -> bool:
	if owner == null or owner.get_world_3d() == null:
		return true

	var space_state: PhysicsDirectSpaceState3D = owner.get_world_3d().direct_space_state
	if space_state == null:
		return true

	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = roam_obstacle_check_radius

	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(
		Basis.IDENTITY,
		Vector3(candidate.x, floor_height + roam_obstacle_check_radius + 0.08, candidate.z)
	)
	query.collision_mask = roam_obstacle_collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var owner_collision: CollisionObject3D = owner as CollisionObject3D
	if owner_collision != null:
		query.exclude = [owner_collision.get_rid()]

	var hits: Array[Dictionary] = space_state.intersect_shape(query, 1)
	return hits.is_empty()


func _has_any_target(target_names: Array[StringName]) -> bool:
	for target_name in target_names:
		if targets.get(target_name) != null:
			return true
	return false


func _pick_target_from_names(target_names: Array[StringName]) -> Node3D:
	var available_targets: Array[Node3D] = _collect_targets_from_names(target_names)
	if available_targets.is_empty():
		return null

	return available_targets[rng.randi_range(0, available_targets.size() - 1)]


func _collect_targets_from_names(target_names: Array[StringName]) -> Array[Node3D]:
	var available_targets: Array[Node3D] = []
	for target_name in target_names:
		var target: Node3D = targets.get(target_name) as Node3D
		if target != null:
			available_targets.append(target)
	return available_targets
