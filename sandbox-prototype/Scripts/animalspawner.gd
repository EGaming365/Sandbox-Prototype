extends Node

const CHICKEN_SCENE := preload("res://Scenes/chicken.tscn")
const NIGHT_ENEMY_SCENE := preload("res://Scenes/night_enemy.tscn")

@export var max_chickens_in_radius: int = 10.0
@export var max_night_enemies_in_radius: int = 4
@export var spawn_radius_min: float = 1000.0
@export var spawn_radius_max: float = 2000.0
@export var despawn_radius: float = 1600.0
@export var despawn_grace_period: float = 10.0

var _scene_node: Node = null
var _out_of_range_timers: Dictionary = {}
var _spawn_timer: Timer
var _despawn_timer: Timer
var _next_chicken_id: int = 0
var _next_night_enemy_id: int = 0

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
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return
	# Check spawn need per player
	var in_radius := _count_chickens_in_radius()
	var needed = max(max_chickens_in_radius - in_radius, 0)
	for i in needed:
		# Pick a random player to spawn near
		var target_player = players[randi() % players.size()]
		var pos := _random_spawn_pos_near((target_player as Node2D).global_position)
		if pos != Vector2.ZERO:
			_spawn_chicken(pos)
	if _is_night():
		var enemies_needed = max(max_night_enemies_in_radius - _count_night_enemies_in_radius(), 0)
		for i in enemies_needed:
			var target_player = players[randi() % players.size()]
			var pos := _random_spawn_pos_near((target_player as Node2D).global_position, "night_enemies")
			if pos != Vector2.ZERO:
				_spawn_night_enemy(pos)

func _check_despawn() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var players := get_tree().get_nodes_in_group("players")
	for chicken in get_tree().get_nodes_in_group("chickens"):
		var c := chicken as Node2D
		if not is_instance_valid(c):
			continue
		# Only despawn if ALL players are out of range
		var all_out_of_range := true
		for p in players:
			if is_instance_valid(p):
				if (p as Node2D).global_position.distance_to(c.global_position) <= despawn_radius:
					all_out_of_range = false
					break
		if all_out_of_range:
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
	for enemy in get_tree().get_nodes_in_group("night_enemies"):
		var e := enemy as Node2D
		if not is_instance_valid(e):
			continue
		if not _is_night():
			e.queue_free()
			continue
		var all_out := true
		for p in players:
			if is_instance_valid(p):
				if (p as Node2D).global_position.distance_to(e.global_position) <= despawn_radius:
					all_out = false
					break
		if all_out:
			e.queue_free()

func _spawn_chicken(pos: Vector2) -> void:
	var chicken = CHICKEN_SCENE.instantiate()
	chicken.chicken_id = _next_chicken_id
	chicken.name = "Chicken_" + str(_next_chicken_id)
	_next_chicken_id += 1
	chicken.global_position = pos
	chicken.set_meta("sync_ready", false)
	_scene_node.add_child(chicken)
	chicken.set_multiplayer_authority(1)
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		_scene_node.spawn_chicken_on_client_rpc.rpc(chicken.global_position.x, chicken.global_position.y, chicken.chicken_id)
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(chicken):
		chicken.set_meta("sync_ready", true)

func _spawn_night_enemy(pos: Vector2) -> void:
	var enemy = NIGHT_ENEMY_SCENE.instantiate()
	enemy.enemy_id = _next_night_enemy_id
	enemy.name = "Enemy_" + str(_next_night_enemy_id)
	_next_night_enemy_id += 1
	enemy.global_position = pos
	enemy.set_meta("sync_ready", false)
	_scene_node.add_child(enemy)
	enemy.set_multiplayer_authority(1)
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		_scene_node.spawn_enemy_on_client_rpc.rpc(enemy.global_position.x, enemy.global_position.y, enemy.enemy_id)
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(enemy):
		enemy.set_meta("sync_ready", true)

func _count_night_enemies_in_radius() -> int:
	var center := _get_player_center()
	var count := 0
	for enemy in get_tree().get_nodes_in_group("night_enemies"):
		if is_instance_valid(enemy):
			if center.distance_to((enemy as Node2D).global_position) <= despawn_radius:
				count += 1
	return count

func _random_spawn_pos(avoid_group: String = "chickens") -> Vector2:
	var center := _get_player_center()
	for i in 30:
		var angle := randf_range(0.0, TAU)
		var dist := randf_range(spawn_radius_min, spawn_radius_max)
		var pos := center + Vector2(cos(angle), sin(angle)) * dist
		var too_close := false

		for existing in get_tree().get_nodes_in_group(avoid_group):
			if pos.distance_to((existing as Node2D).global_position) < 100.0:
				too_close = true
				break

		if too_close:
			continue

		if not _is_spawn_pos_clear(pos):
			continue

		return pos

	return Vector2.ZERO

func _get_player_center() -> Vector2:
	if multiplayer.has_multiplayer_peer():
		# Use all players' positions for spawn/despawn so none get despawned unfairly
		var players := get_tree().get_nodes_in_group("players")
		if players.is_empty():
			return Vector2.ZERO
		var furthest_dist := 0.0
		var best_pos := Vector2.ZERO
		# Find the player furthest from origin as reference
		for p in players:
			if is_instance_valid(p):
				best_pos += (p as Node2D).global_position
		return best_pos / players.size()
	else:
		var players := get_tree().get_nodes_in_group("players")
		if players.is_empty():
			return Vector2.ZERO
		return (players[0] as Node2D).global_position

func _is_spawn_pos_clear(pos: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = _scene_node.get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 14.0
	query.shape = shape
	query.transform = Transform2D(0, pos)
	query.collision_mask = 1

	return space.intersect_shape(query).is_empty()

func _is_night() -> bool:
	var weather = get_tree().root.get_node_or_null("Scene/Weather")
	return weather != null and weather.has_method("is_night") and weather.is_night()

func _random_spawn_pos_near(center: Vector2, avoid_group: String = "chickens") -> Vector2:
	for i in 30:
		var angle := randf_range(0.0, TAU)
		var dist := randf_range(spawn_radius_min, spawn_radius_max)
		var pos := center + Vector2(cos(angle), sin(angle)) * dist
		var too_close := false
		for existing in get_tree().get_nodes_in_group(avoid_group):
			if pos.distance_to((existing as Node2D).global_position) < 100.0:
				too_close = true
				break
		if too_close:
			continue
		if not _is_spawn_pos_clear(pos):
			continue
		return pos
	return Vector2.ZERO
