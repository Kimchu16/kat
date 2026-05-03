class_name KatPositionHelper
extends RefCounted

# Hidden target points and simple distance helpers used when Kat follows or
# avoids the player. This does not move Kat; it only gives the controller points
# to move toward.

var actor: Node3D
var user_follow_target_path: NodePath = NodePath("../QuestVRPlayer/XROrigin3D")
var floor_height: float = 0.0
var elevated_target_min_height: float = 0.18
var avoid_target_distance: float = 1.85
var room_roam_min: Vector2 = Vector2(-3.2, -2.95)
var room_roam_max: Vector2 = Vector2(3.25, 2.9)

var _user_floor_target: Node3D
var _treat_floor_target: Node3D
var _relationship_target: Node3D


func setup(owner: Node3D) -> void:
	actor = owner


func resolve_user_follow_target() -> Node3D:
	if actor == null:
		return null

	var user_target: Node3D = actor.get_node_or_null(user_follow_target_path) as Node3D
	if user_target != null:
		return user_target

	user_target = actor.get_node_or_null("../QuestVRPlayer/XROrigin3D") as Node3D
	if user_target != null:
		return user_target

	return actor.get_node_or_null("../QuestVRPlayer") as Node3D


func floor_target_for_user(user_target: Node3D) -> Node3D:
	if user_target == null:
		return null

	if _user_floor_target == null:
		_user_floor_target = _make_top_level_target("UserFollowTarget")

	var user_position: Vector3 = user_target.global_position
	_user_floor_target.global_position = Vector3(user_position.x, floor_height, user_position.z)
	return _user_floor_target


func floor_target_for_treat_holder(holder: Node3D) -> Node3D:
	if holder == null:
		return null

	if _treat_floor_target == null:
		_treat_floor_target = _make_top_level_target("TreatFollowTarget")

	var holder_position: Vector3 = holder.global_position
	_treat_floor_target.global_position = Vector3(holder_position.x, floor_height, holder_position.z)
	return _treat_floor_target


func avoid_target_from(source: Node3D, fallback_forward: Vector3) -> Node3D:
	if actor == null or source == null:
		return null

	if _relationship_target == null:
		_relationship_target = _make_top_level_target("RelationshipTarget")

	var away: Vector3 = actor.global_position - source.global_position
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = fallback_forward

	var avoid_position: Vector3 = actor.global_position + away.normalized() * avoid_target_distance
	avoid_position.x = clampf(avoid_position.x, minf(room_roam_min.x, room_roam_max.x), maxf(room_roam_min.x, room_roam_max.x))
	avoid_position.y = floor_height
	avoid_position.z = clampf(avoid_position.z, minf(room_roam_min.y, room_roam_max.y), maxf(room_roam_min.y, room_roam_max.y))
	_relationship_target.global_position = avoid_position
	return _relationship_target


func snap_actor_to_floor_after_follow() -> void:
	if actor != null and actor.global_position.y > floor_height + elevated_target_min_height:
		var floor_position: Vector3 = actor.global_position
		floor_position.y = floor_height
		actor.global_position = floor_position


func horizontal_distance_to_node(node: Node3D) -> float:
	if actor == null or node == null:
		return 0.0

	return Vector2(
		node.global_position.x - actor.global_position.x,
		node.global_position.z - actor.global_position.z
	).length()


func _make_top_level_target(target_name: String) -> Node3D:
	var target: Node3D = Node3D.new()
	target.name = target_name
	target.top_level = true
	if actor != null:
		actor.add_child(target)
	return target
