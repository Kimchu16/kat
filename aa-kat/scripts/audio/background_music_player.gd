class_name BackgroundMusicPlayer
extends AudioStreamPlayer

# Room music controller. It swaps between the two background tracks so the room
# does not loop the exact same song forever.

@export var first_track: AudioStream = preload("res://audio/songs/sigmamusicart-jazz-lounge-relaxing-background-music-514554.mp3")
@export var second_track: AudioStream = preload("res://audio/songs/waveloom-jazz-restaurant-516751.mp3")
@export var target_volume_db: float = -16.0
@export var shuffle_tracks: bool = true
@export var play_on_start: bool = true

var _tracks: Array[AudioStream] = []
var _track_index: int = -1
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	finished.connect(_on_finished)
	bus = &"Master"
	volume_db = target_volume_db
	_tracks.clear()
	_add_track(first_track)
	_add_track(second_track)

	if play_on_start:
		_play_next_track()


func _add_track(track: AudioStream) -> void:
	if track == null:
		return

	_tracks.append(track)


func _on_finished() -> void:
	_play_next_track()


func _play_next_track() -> void:
	if _tracks.is_empty():
		return

	if _track_index < 0:
		if shuffle_tracks and _tracks.size() > 1:
			_track_index = _rng.randi_range(0, _tracks.size() - 1)
		else:
			_track_index = 0
	elif shuffle_tracks and _tracks.size() > 1:
		var next_offset: int = _rng.randi_range(1, _tracks.size() - 1)
		_track_index = (_track_index + next_offset) % _tracks.size()
	else:
		_track_index = (_track_index + 1) % _tracks.size()

	var selected_stream: AudioStream = _tracks[_track_index]
	if selected_stream is AudioStreamMP3:
		var mp3_stream: AudioStreamMP3 = selected_stream.duplicate() as AudioStreamMP3
		mp3_stream.loop = false
		selected_stream = mp3_stream

	stream = selected_stream
	play()
