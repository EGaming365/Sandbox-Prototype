extends Node

const CHICKEN_SCENE := preload("res://Scenes/chicken.tscn")
const NIGHT_ENEMY_SCENE := preload("res://Scenes/night_enemy.tscn")

@export var max_chickens_in_radius: int = 10
@export var max_night_enemies_in_radius: int = 4
@export var max_cave_night_enemies_in_radius: int = 3
@export var spawn_radius_min: float = 1000.0
@export var spawn_radius_max: float = 2000.0
@export var cave_spawn_radius_min: float = 450.0
@export var cave_spawn_radius_max: float = 1200.0
@export var despawn_radius: float = 1600.0
@export var despawn_grace_period: float = 2.0
@export var max_spawns_per_tick: int = 1
@export var max_enemy_spawn_light_level: float = 0.35

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
	var cave_world_gen = get_tree().root.get_node_or_null("Scene/CaveWorldGen")
	var in_cave: bool = cave_world_gen != null and cave_world_gen.get("in_cave")
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return
	var spawned_this_tick := 0
	if in_cave:
		return
	else:
		var chicken_count := _count_chickens_in_radius()
		while chicken_count < max_chickens_in_radius and spawned_this_tick < max_spawns_per_tick:
			var pos := _random_spawn_pos_near(_get_player_center(), "chickens")
			if pos == Vector2.ZERO:
				break
			_spawn_chicken(pos)
			chicken_count += 1
			spawned_this_tick += 1

func _check_despawn() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var cave_world_gen = get_tree().root.get_node_or_null("Scene/CaveWorldGen")
	var in_cave: bool = cave_world_gen != null and cave_world_gen.get("in_cave")
	var players := get_tree().get_nodes_in_group("players")
	for chicken in get_tree().get_nodes_in_group("chickens"):
		var c := chicken as Node2D
		if not is_instance_valid(c):
			continue
		if in_cave:
			c.queue_free()
			continue
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
		if not in_cave:
			e.queue_free()
			continue
		var all_out := true
		for p in players:
			if is_instance_valid(p):
				if (p as Node2D).global_position.distance_to(e.global_position) <= despawn_radius:
					all_out = false
					break
		if all_out:
			var aggressive := int(e.get("state")) != 0
			if not aggressive:
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
	if _is_too_bright_for_enemy_spawn(pos):
		return
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

func spawn_combat_night_enemy(pos: Vector2, combat_room_id: int) -> Node:
	if not _scene_node:
		_scene_node = get_tree().root.get_node_or_null("Scene")
	if not _scene_node:
		return null
	var enemy = NIGHT_ENEMY_SCENE.instantiate()
	enemy.enemy_id = _next_night_enemy_id
	enemy.name = "Enemy_" + str(_next_night_enemy_id)
	_next_night_enemy_id += 1
	enemy.global_position = pos
	enemy.set_meta("sync_ready", false)
	enemy.set_meta("combat_room_id", combat_room_id)
	_scene_node.add_child(enemy)
	enemy.set_multiplayer_authority(1)
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		_scene_node.spawn_enemy_on_client_rpc.rpc(enemy.global_position.x, enemy.global_position.y, enemy.enemy_id)
	if is_instance_valid(enemy):
		enemy.set_meta("sync_ready", true)
	return enemy

func spawn_combat_boss(pos: Vector2, combat_room_id: int) -> Node:
	if not _scene_node:
		_scene_node = get_tree().root.get_node_or_null("Scene")
	if not _scene_node:
		return null
	var boss_scene: PackedScene = load("res://Scenes/boss_spider.tscn")
	if not boss_scene:
		return null
	var boss: Node = boss_scene.instantiate()
	boss.set("enemy_id", _next_night_enemy_id)
	boss.name = "Boss_" + str(_next_night_enemy_id)
	_next_night_enemy_id += 1
	boss.global_position = pos
	boss.set_meta("combat_room_id", combat_room_id)
	_scene_node.add_child(boss)
	boss.set_multiplayer_authority(1)
	return boss

func _count_night_enemies_in_radius() -> int:
	var center := _get_player_center()
	var count := 0
	for enemy in get_tree().get_nodes_in_group("night_enemies"):
		if is_instance_valid(enemy):
			if center.distance_to((enemy as Node2D).global_position) <= despawn_radius:
				count += 1
	return count

func _get_player_center() -> Vector2:
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return Vector2.ZERO
	if multiplayer.has_multiplayer_peer():
		var sum := Vector2.ZERO
		var valid := 0
		for p in players:
			if is_instance_valid(p):
				sum += (p as Node2D).global_position
				valid += 1
		if valid == 0:
			return Vector2.ZERO
		return sum / valid
	else:
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

func _is_too_bright_for_enemy_spawn(pos: Vector2) -> bool:
	var lighting = get_tree().root.get_node_or_null("Scene/LightingSystem")
	if not lighting or not lighting.has_method("get_light_level_at"):
		return false
	return lighting.get_light_level_at(pos) > max_enemy_spawn_light_level

func _is_night() -> bool:
	var weather = get_tree().root.get_node_or_null("Scene/Weather")
	return weather != null and weather.has_method("is_night") and weather.is_night()

func _random_spawn_pos_near(center: Vector2, avoid_group: String = "chickens") -> Vector2:
	var world_gen = get_tree().root.get_node_or_null("Scene/WorldGen")
	var cave_world_gen = get_tree().root.get_node_or_null("Scene/CaveWorldGen")
	for i in 30:
		var angle := randf_range(0.0, TAU)
		var dist := randf_range(spawn_radius_min, spawn_radius_max)
		var pos := center + Vector2(cos(angle), sin(angle)) * dist
		if cave_world_gen and cave_world_gen.get("in_cave"):
			continue
		if _is_position_on_screen(pos):
			continue
		if world_gen and world_gen.has_method("is_water_at") and world_gen.is_water_at(pos):
			continue
		var too_close := false
		for existing in get_tree().get_nodes_in_group(avoid_group):
			if pos.distance_to((existing as Node2D).global_position) < 100.0:
				too_close = true
				break
		if too_close:
			continue
		if not _is_spawn_pos_clear(pos):
			continue
		if avoid_group == "night_enemies" and _is_too_bright_for_enemy_spawn(pos):
			continue
		return pos
	return Vector2.ZERO

func _random_cave_spawn_pos(cave_world_gen: Node, avoid_group: String = "night_enemies") -> Vector2:
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return Vector2.ZERO
	var player := players[0] as Node2D
	var tilemap = get_tree().root.get_node_or_null("Scene/TileMap")
	for i in 60:
		var angle := randf_range(0.0, TAU)
		var dist := randf_range(cave_spawn_radius_min, cave_spawn_radius_max)
		var pos := player.global_position + Vector2(cos(angle), sin(angle)) * dist
		var tc: Vector2i = cave_world_gen.world_to_tile(pos)
		if not cave_world_gen._carved_tiles.has(tc):
			continue
		if cave_world_gen._wall_tiles.has(tc):
			continue
		if cave_world_gen._water_tiles.has(tc):
			continue
		if tilemap:
			pos = tilemap.to_global(tilemap.map_to_local(tc))
		if _is_position_on_screen(pos):
			continue
		var too_close := false
		for existing in get_tree().get_nodes_in_group(avoid_group):
			if pos.distance_to((existing as Node2D).global_position) < 100.0:
				too_close = true
				break
		if too_close:
			continue
		if not _is_spawn_pos_clear(pos):
			continue
		if avoid_group == "night_enemies" and _is_too_bright_for_enemy_spawn(pos):
			continue
		return pos
	return Vector2.ZERO

func _is_position_on_screen(pos: Vector2, margin: float = 160.0) -> bool:
	var viewport := get_viewport()
	if not viewport:
		return false
	var camera := viewport.get_camera_2d()
	if not camera:
		return false
	var size := viewport.get_visible_rect().size
	var top_left := camera.global_position - size * 0.5 - Vector2(margin, margin)
	var rect := Rect2(top_left, size + Vector2(margin * 2.0, margin * 2.0))
	return rect.has_point(pos)

func clear_all_entities() -> void:
	_spawn_timer.stop()
	_despawn_timer.stop()
	for chicken in get_tree().get_nodes_in_group("chickens"):
		if is_instance_valid(chicken):
			chicken.queue_free()
	for enemy in get_tree().get_nodes_in_group("night_enemies"):
		if is_instance_valid(enemy):
			enemy.queue_free()
	if _scene_node and multiplayer.has_multiplayer_peer() and multiplayer.is_server() and _scene_node.has_method("clear_chickens_and_enemies_rpc"):
		_scene_node.clear_chickens_and_enemies_rpc.rpc()
	_out_of_range_timers.clear()
	await get_tree().create_timer(3.0).timeout
	_spawn_timer.start()
	_despawn_timer.start()
