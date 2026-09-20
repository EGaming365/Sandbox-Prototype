extends Node

@export var ambient_tracks: Array[String] = [
	"res://Sounds/Ambience_1.mp3",
	"res://Sounds/Ambience_2.mp3",
	"res://Sounds/Ambience_3.mp3",
]
@export var rain_track: String = "res://Sounds/rain.mp3"
@export var thunder_track: String = "res://Sounds/thunder.mp3"
@export var ambient_volume_db: float = 0.0
@export var rain_volume_db: float = -10.0
@export var thunder_volume_db: float = 0.0
@export var rain_fade_speed_db: float = 6.0

var _ambient_player: AudioStreamPlayer
var _rain_player: AudioStreamPlayer
var _thunder_player: AudioStreamPlayer
var _ambient_queue: Array[String] = []
var _is_raining: bool = false


func _ready() -> void:
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.bus = "Master"
	_ambient_player.volume_db = ambient_volume_db
	add_child(_ambient_player)
	_ambient_player.finished.connect(_play_next_ambient_track)
	_rain_player = AudioStreamPlayer.new()
	_rain_player.bus = "Master"
	_rain_player.volume_db = -80.0
	add_child(_rain_player)
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


func _process(delta: float) -> void:
	if not _rain_player:
		return
	var target_db: float = rain_volume_db if _is_raining else -80.0
	_rain_player.volume_db = move_toward(_rain_player.volume_db, target_db, rain_fade_speed_db * delta)
	if _is_raining and not _rain_player.playing:
		_rain_player.play()
	elif not _is_raining and _rain_player.volume_db <= -79.5 and _rain_player.playing:
		_rain_player.stop()


func set_raining(active: bool) -> void:
	_is_raining = active


func play_thunder() -> void:
	if _thunder_player and _thunder_player.stream:
		_thunder_player.stop()
		_thunder_player.play()


func _shuffle_ambient_queue() -> void:
	_ambient_queue = ambient_tracks.duplicate()
	_ambient_queue.shuffle()


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
