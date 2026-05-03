class_name KatDebugDisplay
extends RefCounted

# Small debug label helper so UI setup does not sit in the behaviour code.

var actor: Node3D
var label: Label3D


func setup(owner: Node3D, show_debug_label: bool) -> void:
	actor = owner
	if actor == null or not show_debug_label:
		return

	label = actor.get_node_or_null("AutonomyDebugLabel") as Label3D
	if label == null:
		label = Label3D.new()
		label.name = "AutonomyDebugLabel"
		actor.add_child(label)

	label.position = Vector3(0.0, 0.68, 0.0)
	label.pixel_size = 0.006
	label.font_size = 12
	label.no_depth_test = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED


func update(current_state: StringName, snapshot: Dictionary) -> void:
	if label == null:
		return

	label.text = "%s | %s\nH %.0f E %.0f P %.0f A %.0f Ang %.0f" % [
		String(current_state).capitalize(),
		String(snapshot.get("mood", &"content")).capitalize(),
		float(snapshot.get("hunger", 0.0)) * 100.0,
		float(snapshot.get("energy", 0.0)) * 100.0,
		float(snapshot.get("play", 0.0)) * 100.0,
		float(snapshot.get("affection", 0.0)) * 100.0,
		float(snapshot.get("anger", 0.0)) * 100.0,
	]
