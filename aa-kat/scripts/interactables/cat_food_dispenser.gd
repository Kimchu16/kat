class_name CatFoodDispenser
extends "res://addons/godot-xr-tools/objects/pickable.gd"

# Pickable cat-food container. When the player holds and tips it, it shows
# falling kibble. If the stream is over an empty FoodBowl, the bowl refills.

@export var food_bowl_path: NodePath = NodePath("../Food Bowl")
@export var pour_origin_path: NodePath = NodePath("PourOrigin")
@export var particles_path: NodePath = NodePath("PourOrigin/KibbleParticles")
@export var pour_audio_path: NodePath = NodePath("PourOrigin/PourAudio")
@export var pour_down_dot: float = 0.35
@export var max_horizontal_offset: float = 0.7
@export var min_height_above_bowl: float = 0.08
@export var max_height_above_bowl: float = 1.4
@export var seconds_to_fill_bowl: float = 1.2
@export var require_pickup_for_pour: bool = false

var _food_bowl: Node
var _pour_origin: Node3D
var _particles: GPUParticles3D
var _pour_audio_player: AudioStreamPlayer3D
var _pour_time: float = 0.0


func _ready() -> void:
	super._ready()
	_food_bowl = get_node_or_null(food_bowl_path)
	_pour_origin = get_node_or_null(pour_origin_path) as Node3D
	_particles = get_node_or_null(particles_path) as GPUParticles3D
	_pour_audio_player = get_node_or_null(pour_audio_path) as AudioStreamPlayer3D
	_setup_pour_audio()
	_set_particles(false)


func _physics_process(delta: float) -> void:
	_resolve_food_bowl()

	var is_pouring: bool = _is_tilted_to_pour()
	if require_pickup_for_pour:
		is_pouring = is_pouring and is_picked_up()
	_set_particles(is_pouring)

	if not is_pouring or not _is_over_empty_bowl():
		_pour_time = 0.0
		return

	_pour_time += delta
	if _pour_time >= seconds_to_fill_bowl:
		_fill_food_bowl()
		_pour_time = 0.0


func _resolve_food_bowl() -> void:
	if _food_bowl != null and is_instance_valid(_food_bowl):
		return

	_food_bowl = get_node_or_null(food_bowl_path)
	if _food_bowl == null:
		_food_bowl = get_tree().get_first_node_in_group("food_bowl")


func _is_tilted_to_pour() -> bool:
	var source: Node3D = _pour_origin
	if source == null:
		source = self

	# Local +Y points out of the top/opening. When it points downward, food pours.
	var opening_direction: Vector3 = source.global_transform.basis.y.normalized()
	return opening_direction.dot(Vector3.DOWN) >= pour_down_dot


func _is_over_empty_bowl() -> bool:
	if _food_bowl == null or not (_food_bowl is Node3D):
		return false
	if not _food_bowl.has_method(&"has_food_available"):
		return false
	if bool(_food_bowl.call(&"has_food_available")):
		return false

	var source: Node3D = _pour_origin
	if source == null:
		source = self

	var bowl_position: Vector3 = _food_bowl_fill_position()
	var pour_position: Vector3 = source.global_position
	var horizontal_distance: float = Vector2(
		pour_position.x - bowl_position.x,
		pour_position.z - bowl_position.z
	).length()
	var height_above_bowl: float = pour_position.y - bowl_position.y

	return (
		horizontal_distance <= max_horizontal_offset
		and height_above_bowl >= min_height_above_bowl
		and height_above_bowl <= max_height_above_bowl
	)


func _fill_food_bowl() -> void:
	if _food_bowl != null and _food_bowl.has_method(&"fill_bowl"):
		_food_bowl.call(&"fill_bowl")


func _food_bowl_fill_position() -> Vector3:
	if _food_bowl != null and _food_bowl.has_method(&"get_fill_position"):
		var fill_position: Variant = _food_bowl.call(&"get_fill_position")
		if fill_position is Vector3:
			return fill_position as Vector3

	return (_food_bowl as Node3D).global_position


func _set_particles(enabled: bool) -> void:
	if _particles != null:
		_particles.emitting = enabled
	_set_pour_audio(enabled)


func _set_pour_audio(enabled: bool) -> void:
	if enabled:
		_play_pour_audio()
		return

	_stop_pour_audio()


func _setup_pour_audio() -> void:
	if _pour_audio_player != null:
		_pour_audio_player.volume_db = 2.0
		_pour_audio_player.unit_size = 8.0
		_pour_audio_player.max_distance = 25.0
		_pour_audio_player.bus = &"Master"
		_make_stream_loop_3d(_pour_audio_player)

func _play_pour_audio() -> void:
	if _pour_audio_player != null and not _pour_audio_player.playing:
		_pour_audio_player.stream_paused = false
		_pour_audio_player.play()


func _stop_pour_audio() -> void:
	if _pour_audio_player != null and _pour_audio_player.playing:
		_pour_audio_player.stop()


func _make_stream_loop_3d(player: AudioStreamPlayer3D) -> void:
	if player == null or player.stream == null:
		return

	var looped_stream: AudioStream = player.stream.duplicate() as AudioStream
	if looped_stream is AudioStreamWAV:
		(looped_stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	if looped_stream is AudioStreamMP3:
		(looped_stream as AudioStreamMP3).loop = true
	player.stream = looped_stream
