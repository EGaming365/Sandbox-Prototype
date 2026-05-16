extends Node

const CHICKEN_SCENE := preload("res://scenes/Chicken.tscn")

@export var max_chickens_in_radius: int = 0
@export var spawn_radius_min: float = 1000.0
@export var spawn_radius_max: float = 2000.0
@export var despawn_radius: float = 1600.0
@export var despawn_grace_period: float = 120.0

var _scene_node: Node = null
var _out_of_range_timers: Dictionary = {}
var _spawn_timer: Timer
var _despawn_timer: Timer
var _next_chicken_id: int = 0

func _ready() -> void:
	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = 5.0
	_spawn_timer.autostart = false
	_spawn_timer.one_shot = false
	_spawn_timer.timeout.connect(_on_spawn_tick)
	add_child(_spawn_timer)

	_despawn_timer = Timer.new()
	_despawn_timer.wait_time = 5.0
	_despawn_timer.autostart = false
	_despawn_timer.one_shot = false
	_despawn_timer.timeout.connect(_check_despawn)
	add_child(_despawn_timer)

	call_deferred("_wait_for_scene")

func _wait_for_scene() -> void:
	_scene_node = get_tree().root.get_node_or_null("Scene")
	if not _scene_node:
		await get_tree().process_frame
		_wait_for_scene()
		return
	await _wait_for_player()
	_on_spawn_tick()
	_despawn_timer.start()
	_spawn_timer.start()

func _wait_for_player() -> void:
	while get_tree().get_nodes_in_group("players").is_empty():
		await get_tree().process_frame

func _count_chickens_in_radius() -> int:
	var center := _get_player_center()
	var count := 0
	for chicken in get_tree().get_nodes_in_group("chickens"):
		if is_instance_valid(chicken):
			if center.distance_to((chicken as Node2D).global_position) <= despawn_radius:
				count += 1
	return count

func _on_spawn_tick() -> void:
	if not _scene_node:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var in_radius := _count_chickens_in_radius()
	var needed := max_chickens_in_radius - in_radius
	for i in needed:
		var pos := _random_spawn_pos()
		if pos != Vector2.ZERO:
			_spawn_chicken(pos)

func _check_despawn() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var center := _get_player_center()
	for chicken in get_tree().get_nodes_in_group("chickens"):
		var c := chicken as Node2D
		if not is_instance_valid(c):
			continue
		if center.distance_to(c.global_position) > despawn_radius:
			if not _out_of_range_timers.has(c):
				_out_of_range_timers[c] = 0.0
			_out_of_range_timers[c] += 5.0
			if _out_of_range_timers[c] >= despawn_grace_period:
				_out_of_range_timers.erase(c)
				c.queue_free()
		else:
			_out_of_range_timers.erase(c)
	for key in _out_of_range_timers.keys():
		if not is_instance_valid(key):
			_out_of_range_timers.erase(key)

func _spawn_chicken(pos: Vector2) -> void:
	print("Spawning chicken as child of: ", _scene_node.name)
	var chicken = CHICKEN_SCENE.instantiate()
	chicken.chicken_id = _next_chicken_id
	_next_chicken_id += 1
	chicken.global_position = pos
	_scene_node.add_child(chicken)

func _random_spawn_pos() -> Vector2:
	var center := _get_player_center()
	for i in 30:
		var angle := randf_range(0.0, TAU)
		var dist := randf_range(spawn_radius_min, spawn_radius_max)
		var pos := center + Vector2(cos(angle), sin(angle)) * dist
		var too_close := false
		for chicken in get_tree().get_nodes_in_group("chickens"):
			if pos.distance_to((chicken as Node2D).global_position) < 100.0:
				too_close = true
				break
		if not too_close:
			return pos
	return Vector2.ZERO

func _get_player_center() -> Vector2:
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for p in players:
		sum += (p as Node2D).global_position
	return sum / players.size()
