# Sound manager.
# Plays shuffled ambient music, a looping rain sound that fades in and out, and thunder on request.

extends Node

# Ambient music files, played in a random order.
@export var ambient_tracks: Array[String] = [
	"res://Sounds/Ambience_1.mp3",
	"res://Sounds/Ambience_2.mp3",
	"res://Sounds/Ambience_3.mp3",
]
# Looping rain sound file.
@export var rain_track: String = "res://Sounds/rain.mp3"
# Thunder sound file.
@export var thunder_track: String = "res://Sounds/thunder.mp3"
# Ambient music volume in decibels.
@export var ambient_volume_db: float = 0.0
# Rain volume in decibels when fully faded in.
@export var rain_volume_db: float = -10.0
# Thunder volume in decibels.
@export var thunder_volume_db: float = 0.0
# How many decibels per second the rain fades in or out.
@export var rain_fade_speed_db: float = 6.0

# Plays the ambient music.
var _ambient_player: AudioStreamPlayer
# Plays the rain loop.
var _rain_player: AudioStreamPlayer
# Plays thunder sounds.
var _thunder_player: AudioStreamPlayer
# Ambient tracks still to be played in this shuffle.
var _ambient_queue: Array[String] = []
# True while the rain sound should be audible.
var _is_raining: bool = false


# Creates the three audio players, loads the sounds and starts the ambient music.
func _ready() -> void:
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.bus = "Master"
	_ambient_player.volume_db = ambient_volume_db
	add_child(_ambient_player)
	# Start the next track as soon as one ends.
	_ambient_player.finished.connect(_play_next_ambient_track)
	_rain_player = AudioStreamPlayer.new()
	_rain_player.bus = "Master"
	# The rain starts silent and fades in when it begins to rain.
	_rain_player.volume_db = -80.0
	add_child(_rain_player)
	# Load the rain sound and make it loop.
	var rain_stream: AudioStream = load(rain_track)
	if rain_stream:
		rain_stream.loop = true
		_rain_player.stream = rain_stream
	_thunder_player = AudioStreamPlayer.new()
	_thunder_player.bus = "Master"
	_thunder_player.volume_db = thunder_volume_db
	add_child(_thunder_player)
	var thunder_stream: AudioStream = load(thunder_track)
	if thunder_stream:
		_thunder_player.stream = thunder_stream
	_shuffle_ambient_queue()
	_play_next_ambient_track()


# Fades the rain sound in and out and starts or stops the player as needed.
func _process(delta: float) -> void:
	if not _rain_player:
		return
	# Fade towards the rain volume, or towards silence when it is not raining.
	var target_db: float = rain_volume_db if _is_raining else -80.0
	_rain_player.volume_db = move_toward(_rain_player.volume_db, target_db, rain_fade_speed_db * delta)
	if _is_raining and not _rain_player.playing:
		_rain_player.play()
	elif not _is_raining and _rain_player.volume_db <= -79.5 and _rain_player.playing:
		_rain_player.stop()


# Called by the weather system to turn the rain sound on or off.
func set_raining(active: bool) -> void:
	_is_raining = active


# Plays the thunder sound from the beginning.
func play_thunder() -> void:
	if _thunder_player and _thunder_player.stream:
		_thunder_player.stop()
		_thunder_player.play()


# Refills the queue with all ambient tracks in a new random order.
func _shuffle_ambient_queue() -> void:
	_ambient_queue = ambient_tracks.duplicate()
	_ambient_queue.shuffle()


# Plays the next ambient track, reshuffling when the queue is empty and skipping any track that fails to load.
func _play_next_ambient_track() -> void:
	if _ambient_queue.is_empty():
		_shuffle_ambient_queue()
	var next_path: String = _ambient_queue.pop_front()
	var stream: AudioStream = load(next_path)
	if not stream:
		_play_next_ambient_track()
		return
	_ambient_player.stream = stream
	_ambient_player.play()
