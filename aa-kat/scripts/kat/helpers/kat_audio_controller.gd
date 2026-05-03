class_name KatAudioController
extends RefCounted

# Handles all Kat-owned sounds. The autonomy script only asks for named sounds
# to start or stop instead of building AudioStreamPlayer3D nodes itself.

var actor: Node3D
var food_bowl: Node

var _eating_audio_player: AudioStreamPlayer3D
var _complaint_audio_player: AudioStreamPlayer3D
var _treat_meow_player: AudioStreamPlayer3D
var _purr_audio_player: AudioStreamPlayer3D
var _hiss_audio_player: AudioStreamPlayer3D


func setup(
	owner: Node3D,
	bowl: Node,
	eating_audio_path: NodePath,
	eating_audio_stream: AudioStream,
	eating_audio_volume_db: float,
	complaint_audio_stream: AudioStream,
	complaint_audio_volume_db: float,
	treat_meow_stream: AudioStream,
	purr_audio_stream: AudioStream,
	hiss_audio_stream: AudioStream,
	hiss_audio_volume_db: float
) -> void:
	actor = owner
	food_bowl = bowl
	_setup_eating_audio(eating_audio_path, eating_audio_stream, eating_audio_volume_db)
	_setup_complaint_audio(complaint_audio_stream, complaint_audio_volume_db)
	_setup_treat_audio(treat_meow_stream, purr_audio_stream)
	_setup_hiss_audio(hiss_audio_stream, hiss_audio_volume_db)


func stop_all() -> void:
	stop_eating()
	stop_complaint()
	stop_treat_meow()
	stop_purr()
	stop_hiss()


func start_eating() -> void:
	_start_looping_player(_eating_audio_player)


func stop_eating() -> void:
	_stop_player(_eating_audio_player)


func start_complaint() -> void:
	_start_looping_player(_complaint_audio_player)


func stop_complaint() -> void:
	_stop_player(_complaint_audio_player)


func play_treat_meow() -> void:
	_restart_one_shot_player(_treat_meow_player)


func stop_treat_meow() -> void:
	_stop_player(_treat_meow_player)


func update_purr(should_purr: bool) -> void:
	if should_purr:
		start_purr()
	else:
		stop_purr()


func start_purr() -> void:
	_start_looping_player(_purr_audio_player)


func stop_purr() -> void:
	_stop_player(_purr_audio_player)


func play_hiss() -> void:
	_restart_one_shot_player(_hiss_audio_player)


func stop_hiss() -> void:
	_stop_player(_hiss_audio_player)


func _setup_eating_audio(audio_path: NodePath, audio_stream: AudioStream, volume_db: float) -> void:
	if actor == null:
		return

	_eating_audio_player = actor.get_node_or_null(audio_path) as AudioStreamPlayer3D
	if _eating_audio_player == null and food_bowl != null:
		_eating_audio_player = food_bowl.get_node_or_null("KatEating") as AudioStreamPlayer3D

	if _eating_audio_player == null:
		if audio_stream == null:
			return
		_eating_audio_player = AudioStreamPlayer3D.new()
		_eating_audio_player.name = "EatingAudio"
		actor.add_child(_eating_audio_player)

	if _eating_audio_player.stream == null:
		if audio_stream == null:
			return
		_eating_audio_player.stream = audio_stream.duplicate() as AudioStream
	else:
		_eating_audio_player.stream = _eating_audio_player.stream.duplicate() as AudioStream

	_configure_player(_eating_audio_player, volume_db, 25.0, 8.0, true)


func _setup_complaint_audio(audio_stream: AudioStream, volume_db: float) -> void:
	if actor == null or audio_stream == null:
		return

	_complaint_audio_player = actor.get_node_or_null("ComplaintAudio") as AudioStreamPlayer3D
	if _complaint_audio_player == null:
		_complaint_audio_player = AudioStreamPlayer3D.new()
		_complaint_audio_player.name = "ComplaintAudio"
		actor.add_child(_complaint_audio_player)

	_complaint_audio_player.stream = audio_stream.duplicate() as AudioStream
	_configure_player(_complaint_audio_player, volume_db, 20.0, 6.0, true)


func _setup_treat_audio(treat_meow_stream: AudioStream, purr_audio_stream: AudioStream) -> void:
	if actor == null:
		return

	if treat_meow_stream != null:
		_treat_meow_player = actor.get_node_or_null("TreatMeowAudio") as AudioStreamPlayer3D
		if _treat_meow_player == null:
			_treat_meow_player = AudioStreamPlayer3D.new()
			_treat_meow_player.name = "TreatMeowAudio"
			actor.add_child(_treat_meow_player)
		_treat_meow_player.stream = treat_meow_stream
		_configure_player(_treat_meow_player, 3.0, 18.0, 6.0, false)

	if purr_audio_stream != null:
		_purr_audio_player = actor.get_node_or_null("PurrAudio") as AudioStreamPlayer3D
		if _purr_audio_player == null:
			_purr_audio_player = AudioStreamPlayer3D.new()
			_purr_audio_player.name = "PurrAudio"
			actor.add_child(_purr_audio_player)
		_purr_audio_player.stream = purr_audio_stream.duplicate() as AudioStream
		_configure_player(_purr_audio_player, 1.5, 12.0, 5.0, true)


func _setup_hiss_audio(audio_stream: AudioStream, volume_db: float) -> void:
	if actor == null or audio_stream == null:
		return

	_hiss_audio_player = actor.get_node_or_null("HissAudio") as AudioStreamPlayer3D
	if _hiss_audio_player == null:
		_hiss_audio_player = AudioStreamPlayer3D.new()
		_hiss_audio_player.name = "HissAudio"
		actor.add_child(_hiss_audio_player)

	_hiss_audio_player.stream = audio_stream
	_configure_player(_hiss_audio_player, volume_db, 16.0, 5.0, false)


func _configure_player(
	player: AudioStreamPlayer3D,
	volume_db: float,
	max_distance: float,
	unit_size: float,
	should_loop: bool
) -> void:
	if player == null:
		return

	player.volume_db = volume_db
	player.max_distance = max_distance
	player.unit_size = unit_size
	player.bus = &"Master"
	if should_loop:
		_make_audio_stream_loop(player)


func _start_looping_player(player: AudioStreamPlayer3D) -> void:
	if player != null and not player.playing:
		player.stream_paused = false
		player.play()


func _restart_one_shot_player(player: AudioStreamPlayer3D) -> void:
	if player == null:
		return

	if player.playing:
		player.stop()
	player.stream_paused = false
	player.play()


func _stop_player(player: AudioStreamPlayer3D) -> void:
	if player != null and player.playing:
		player.stop()


func _make_audio_stream_loop(player: AudioStreamPlayer3D) -> void:
	if player == null or player.stream == null:
		return

	if player.stream is AudioStreamWAV:
		(player.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	if player.stream is AudioStreamMP3:
		(player.stream as AudioStreamMP3).loop = true
