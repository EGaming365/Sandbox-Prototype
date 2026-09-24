# Animal spawner autoload.
# Spawns chickens around the players and removes them when players move away or enter the cave.
# It also creates combat room enemies and the boss, and clears them again when a room ends.
# Only the host spawns creatures. The other players are told about each spawn.

extends Node

# Scene created for each chicken.
const CHICKEN_SCENE := preload("res://Scenes/chicken.tscn")
# Scene created for each night enemy.
const NIGHT_ENEMY_SCENE := preload("res://Scenes/night_enemy.tscn")

# Most chickens allowed near the players.
@export var max_chickens_in_radius: int = 10
# Most spiders allowed near the players at night.
@export var max_night_enemies_in_radius: int = 4
# Cave night enemy limit. It is not currently used.
@export var max_cave_night_enemies_in_radius: int = 3
# Closest distance from the players at which a chicken can spawn.
@export var spawn_radius_min: float = 1000.0
# Furthest distance from the players at which a chicken can spawn.
@export var spawn_radius_max: float = 2000.0
# Closest cave spawn distance. It is only used by a function that is not currently called.
@export var cave_spawn_radius_min: float = 450.0
# Furthest cave spawn distance. It is only used by a function that is not currently called.
@export var cave_spawn_radius_max: float = 1200.0
# Creatures further than this from every player can be removed.
@export var despawn_radius: float = 1600.0
# Seconds a creature can stay out of range before it is removed.
@export var despawn_grace_period: float = 2.0
# Most creatures spawned each time the spawn timer fires.
@export var max_spawns_per_tick: int = 1
# Enemies do not spawn where the light level is above this.
@export var max_enemy_spawn_light_level: float = 0.35

# The main scene, which new creatures are added to.
var _scene_node: Node = null
# How long each creature has been out of range.
var _out_of_range_timers: Dictionary = {}
# Fires regularly to spawn creatures.
var _spawn_timer: Timer
# Fires regularly to remove distant creatures.
var _despawn_timer: Timer
# ID given to the next chicken so all players agree on it.
var _next_chicken_id: int = 0
# ID given to the next enemy or boss.
var _next_night_enemy_id: int = 0


# Creates the spawn and despawn timers, which start once the scene and a player exist.
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


# Waits until the main scene exists, then until a player exists, and then starts the timers.
func _wait_for_scene() -> void:
	_scene_node = get_tree().root.get_node_or_null("Scene")
	if not _scene_node:
		await get_tree().process_frame
		_wait_for_scene()
		return
	await _wait_for_player()
	_despawn_timer.start()
	_spawn_timer.start()


# Waits frame by frame until at least one player is in the game.
func _wait_for_player() -> void:
	while get_tree().get_nodes_in_group("players").is_empty():
		await get_tree().process_frame


# Returns how many chickens are close to the players.
func _count_chickens_in_radius() -> int:
	var center := _get_player_center()
	var count := 0
	# Check every chicken.
	for chicken in get_tree().get_nodes_in_group("chickens"):
		if is_instance_valid(chicken):
			if center.distance_to((chicken as Node2D).global_position) <= despawn_radius:
				count += 1
	return count


# Runs on the host every few seconds. Spawns chickens on the surface until there are enough, and nothing in the cave.
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
	# Stop after the maximum number of spawns for this tick.
	var spawned_this_tick := 0
	if in_cave:
		return
	else:
		var chicken_count := _count_chickens_in_radius()
		while chicken_count < max_chickens_in_radius and spawned_this_tick < max_spawns_per_tick:
			var spawn_position := _random_spawn_pos_near(_get_player_center(), "chickens")
			if spawn_position == Vector2.ZERO:
				break
			_spawn_chicken(spawn_position)
			chicken_count += 1
			spawned_this_tick += 1
		# Spiders only come out at night, same idea as the chicken loop above but capped by max_night_enemies_in_radius.
		if _is_night():
			var night_enemy_count := _count_night_enemies_in_radius()
			var spawned_night_enemies_this_tick := 0
			while night_enemy_count < max_night_enemies_in_radius and spawned_night_enemies_this_tick < max_spawns_per_tick:
				var enemy_spawn_position := _random_spawn_pos_near(_get_player_center(), "night_enemies")
				if enemy_spawn_position == Vector2.ZERO:
					break
				_spawn_night_enemy(enemy_spawn_position)
				night_enemy_count += 1
				spawned_night_enemies_this_tick += 1


# Runs on the host. Removes chickens that are far from every player and in the cave, removes cave room enemies that end up on the surface, and removes enemies that are left far behind.
func _check_despawn() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var cave_world_gen = get_tree().root.get_node_or_null("Scene/CaveWorldGen")
	var in_cave: bool = cave_world_gen != null and cave_world_gen.get("in_cave")
	var players := get_tree().get_nodes_in_group("players")
	for chicken in get_tree().get_nodes_in_group("chickens"):
		var chicken_node := chicken as Node2D
		if not is_instance_valid(chicken_node):
			continue
		if in_cave:
			chicken_node.queue_free()
			continue
		var all_out_of_range := true
		for player_node in players:
			if is_instance_valid(player_node):
				if (player_node as Node2D).global_position.distance_to(chicken_node.global_position) <= despawn_radius:
					all_out_of_range = false
					break
		if all_out_of_range:
			if not _out_of_range_timers.has(chicken_node):
				_out_of_range_timers[chicken_node] = 0.0
			_out_of_range_timers[chicken_node] += 5.0
			if _out_of_range_timers[chicken_node] >= despawn_grace_period:
				_out_of_range_timers.erase(chicken_node)
				chicken_node.queue_free()
		else:
			_out_of_range_timers.erase(chicken_node)
	# Forget timers for creatures that no longer exist.
	for key in _out_of_range_timers.keys():
		if not is_instance_valid(key):
			_out_of_range_timers.erase(key)
	# Cave room enemies that end up on the surface are removed. Any enemy that is far from every player and not chasing anyone is removed. Surface night enemies otherwise stay until day breaks.
	var enemy_despawn_radius := despawn_radius if in_cave else _surface_enemy_radius()
	for enemy in get_tree().get_nodes_in_group("night_enemies"):
		var enemy_node := enemy as Node2D
		if not is_instance_valid(enemy_node):
			continue
		if not in_cave and enemy_node.has_meta("combat_room_id"):
			enemy_node.queue_free()
			continue
		var all_players_out_of_range := true
		for player_node in players:
			if is_instance_valid(player_node):
				if (player_node as Node2D).global_position.distance_to(enemy_node.global_position) <= enemy_despawn_radius:
					all_players_out_of_range = false
					break
		if all_players_out_of_range:
			var aggressive := int(enemy_node.get("state")) != 0
			if not aggressive:
				enemy_node.queue_free()


# Creates a chicken on the host and tells the other players to create it too.
func _spawn_chicken(spawn_position: Vector2) -> void:
	var chicken = CHICKEN_SCENE.instantiate()
	chicken.chicken_id = _next_chicken_id
	chicken.name = "Chicken_" + str(_next_chicken_id)
	_next_chicken_id += 1
	chicken.global_position = spawn_position
	chicken.set_meta("sync_ready", false)
	_scene_node.add_child(chicken)
	chicken.set_multiplayer_authority(1)
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		_scene_node.spawn_chicken_on_client_rpc.rpc(
			chicken.global_position.x, chicken.global_position.y, chicken.chicken_id,
		)
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(chicken):
		chicken.set_meta("sync_ready", true)


# Creates a night enemy (a spider) in the same way as a chicken.
func _spawn_night_enemy(spawn_position: Vector2) -> void:
	if _is_too_bright_for_enemy_spawn(spawn_position):
		return
	var enemy = NIGHT_ENEMY_SCENE.instantiate()
	enemy.enemy_id = _next_night_enemy_id
	enemy.name = "Enemy_" + str(_next_night_enemy_id)
	_next_night_enemy_id += 1
	enemy.global_position = spawn_position
	enemy.set_meta("sync_ready", false)
	_scene_node.add_child(enemy)
	enemy.set_multiplayer_authority(1)
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		_scene_node.spawn_enemy_on_client_rpc.rpc(
			enemy.global_position.x, enemy.global_position.y, enemy.enemy_id,
		)
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(enemy):
		enemy.set_meta("sync_ready", true)


# Creates an enemy for a cave combat room and returns it.
func spawn_combat_night_enemy(spawn_position: Vector2, combat_room_id: int) -> Node:
	if not _scene_node:
		_scene_node = get_tree().root.get_node_or_null("Scene")
	if not _scene_node:
		return null
	var enemy = NIGHT_ENEMY_SCENE.instantiate()
	enemy.enemy_id = _next_night_enemy_id
	enemy.name = "Enemy_" + str(_next_night_enemy_id)
	_next_night_enemy_id += 1
	enemy.global_position = spawn_position
	enemy.set_meta("sync_ready", false)
	enemy.set_meta("combat_room_id", combat_room_id)
	_scene_node.add_child(enemy)
	enemy.set_multiplayer_authority(1)
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		_scene_node.spawn_enemy_on_client_rpc.rpc(
			enemy.global_position.x, enemy.global_position.y, enemy.enemy_id,
		)
	if is_instance_valid(enemy):
		enemy.set_meta("sync_ready", true)
	return enemy


# Creates the Spider Queen for a cave combat room and returns it.
func spawn_combat_boss(spawn_position: Vector2, combat_room_id: int) -> Node:
	if not _scene_node:
		_scene_node = get_tree().root.get_node_or_null("Scene")
	if not _scene_node:
		return null
	var boss_scene: PackedScene = load("res://Scenes/spider_queen.tscn")
	if not boss_scene:
		return null
	var boss: Node = boss_scene.instantiate()
	boss.set("enemy_id", _next_night_enemy_id)
	boss.name = "Boss_" + str(_next_night_enemy_id)
	boss.global_position = spawn_position
	boss.set_meta("sync_ready", false)
	boss.set_meta("combat_room_id", combat_room_id)
	_scene_node.add_child(boss)
	boss.set_multiplayer_authority(1)
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		_scene_node.spawn_boss_on_client_rpc.rpc(
			boss.global_position.x, boss.global_position.y, _next_night_enemy_id,
		)
	if is_instance_valid(boss):
		boss.set_meta("sync_ready", true)
	_next_night_enemy_id += 1
	return boss


# Returns how far from every player a surface enemy can be before it is removed. It is further out than the furthest spawn distance so new spawns are not removed straight away.
func _surface_enemy_radius() -> float:
	return maxf(despawn_radius, spawn_radius_max) + 600.0


# Returns how many enemies are close to the players.
func _count_night_enemies_in_radius() -> int:
	var center := _get_player_center()
	var count := 0
	var count_radius := _surface_enemy_radius()
	for enemy in get_tree().get_nodes_in_group("night_enemies"):
		if is_instance_valid(enemy):
			if center.distance_to((enemy as Node2D).global_position) <= count_radius:
				count += 1
	return count


# Returns the average position of all players, or the single player's position when playing alone.
func _get_player_center() -> Vector2:
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return Vector2.ZERO
	if multiplayer.has_multiplayer_peer():
		var position_sum := Vector2.ZERO
		var valid_player_count := 0
		for player_node in players:
			if is_instance_valid(player_node):
				position_sum += (player_node as Node2D).global_position
				valid_player_count += 1
		if valid_player_count == 0:
			return Vector2.ZERO
		return position_sum / valid_player_count
	else:
		return (players[0] as Node2D).global_position


# Returns true if nothing solid is at the position, using a small circle test against the physics world.
func _is_spawn_pos_clear(spawn_position: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = _scene_node.get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var circle_shape := CircleShape2D.new()
	circle_shape.radius = 14.0
	query.shape = circle_shape
	query.transform = Transform2D(0, spawn_position)
	query.collision_mask = 1
	return space.intersect_shape(query).is_empty()


# Returns true if the position is too well lit for an enemy to spawn.
func _is_too_bright_for_enemy_spawn(spawn_position: Vector2) -> bool:
	var lighting = get_tree().root.get_node_or_null("Scene/LightingSystem")
	if not lighting or not lighting.has_method("get_light_level_at"):
		return false
	return lighting.get_light_level_at(spawn_position) > max_enemy_spawn_light_level


# Returns true if the weather system says it is night.
func _is_night() -> bool:
	var weather = get_tree().root.get_node_or_null("Scene/Weather")
	return weather != null and weather.has_method("is_night") and weather.is_night()


# Tries up to 30 random positions in a ring around the centre and returns the first valid one, or zero if none is found.
func _random_spawn_pos_near(center: Vector2, avoid_group: String = "chickens") -> Vector2:
	var world_gen = get_tree().root.get_node_or_null("Scene/WorldGen")
	var cave_world_gen = get_tree().root.get_node_or_null("Scene/CaveWorldGen")
	for i in 30:
		var angle := randf_range(0.0, TAU)
		var spawn_distance := randf_range(spawn_radius_min, spawn_radius_max)
		var spawn_position := center + Vector2(cos(angle), sin(angle)) * spawn_distance
		if cave_world_gen and cave_world_gen.get("in_cave"):
			continue
		# Skip anywhere the player could see, so creatures do not appear in front of them.
		if _is_position_on_screen(spawn_position):
			continue
		if world_gen and world_gen.has_method("is_water_at") and world_gen.is_water_at(spawn_position):
			continue
		# Keep a gap between creatures of the same kind.
		var too_close := false
		for existing in get_tree().get_nodes_in_group(avoid_group):
			if spawn_position.distance_to((existing as Node2D).global_position) < 100.0:
				too_close = true
				break
		if too_close:
			continue
		if not _is_spawn_pos_clear(spawn_position):
			continue
		if avoid_group == "night_enemies" and _is_too_bright_for_enemy_spawn(spawn_position):
			continue
		return spawn_position
	return Vector2.ZERO


# Finds a random open cave floor tile away from the screen. It is not currently called.
func _random_cave_spawn_pos(
	cave_world_gen: Node,
	avoid_group: String = "night_enemies",
) -> Vector2:
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return Vector2.ZERO
	var player := players[0] as Node2D
	var tilemap = get_tree().root.get_node_or_null("Scene/TileMap")
	for i in 60:
		var angle := randf_range(0.0, TAU)
		var spawn_distance := randf_range(cave_spawn_radius_min, cave_spawn_radius_max)
		var spawn_position := player.global_position + Vector2(cos(angle), sin(angle)) * spawn_distance
		var tile_coord: Vector2i = cave_world_gen.world_to_tile(spawn_position)
		if not cave_world_gen._carved_tiles.has(tile_coord):
			continue
		if cave_world_gen._wall_tiles.has(tile_coord):
			continue
		if cave_world_gen._water_tiles.has(tile_coord):
			continue
		if tilemap:
			spawn_position = tilemap.to_global(tilemap.map_to_local(tile_coord))
		if _is_position_on_screen(spawn_position):
			continue
		var too_close := false
		for existing in get_tree().get_nodes_in_group(avoid_group):
			if spawn_position.distance_to((existing as Node2D).global_position) < 100.0:
				too_close = true
				break
		if too_close:
			continue
		if not _is_spawn_pos_clear(spawn_position):
			continue
		if avoid_group == "night_enemies" and _is_too_bright_for_enemy_spawn(spawn_position):
			continue
		return spawn_position
	return Vector2.ZERO


# Returns true if the position is on screen, plus a margin around the edges.
func _is_position_on_screen(spawn_position: Vector2, margin: float = 160.0) -> bool:
	var viewport := get_viewport()
	if not viewport:
		return false
	var camera := viewport.get_camera_2d()
	if not camera:
		return false
	var screen_size := viewport.get_visible_rect().size
	var top_left := camera.global_position - screen_size * 0.5 - Vector2(margin, margin)
	var screen_rect := Rect2(top_left, screen_size + Vector2(margin * 2.0, margin * 2.0))
	return screen_rect.has_point(spawn_position)


# Removes every enemy and boss that belongs to a combat room, and tells the other players to do the same.
func clear_room_entities(combat_room_id: int) -> void:
	for enemy in get_tree().get_nodes_in_group("night_enemies"):
		if is_instance_valid(enemy) and int(enemy.get_meta("combat_room_id", -999)) == combat_room_id:
			enemy.queue_free()
	for boss in get_tree().get_nodes_in_group("bosses"):
		if is_instance_valid(boss) and int(boss.get_meta("combat_room_id", -999)) == combat_room_id:
			boss.queue_free()
	if _scene_node and multiplayer.has_multiplayer_peer() and multiplayer.is_server() \
			and _scene_node.has_method("despawn_room_entities_rpc"):
		_scene_node.despawn_room_entities_rpc.rpc(combat_room_id)


# Removes all chickens and enemies, for example when changing world, then pauses spawning for three seconds.
func clear_all_entities() -> void:
	_spawn_timer.stop()
	_despawn_timer.stop()
	for chicken in get_tree().get_nodes_in_group("chickens"):
		if is_instance_valid(chicken):
			chicken.queue_free()
	for enemy in get_tree().get_nodes_in_group("night_enemies"):
		if is_instance_valid(enemy):
			enemy.queue_free()
	if _scene_node and multiplayer.has_multiplayer_peer() and multiplayer.is_server() \
			and _scene_node.has_method("clear_chickens_and_enemies_rpc"):
		_scene_node.clear_chickens_and_enemies_rpc.rpc()
	_out_of_range_timers.clear()
	await get_tree().create_timer(3.0).timeout
	_spawn_timer.start()
	_despawn_timer.start()
