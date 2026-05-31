extends Node2D

@export var chunk_size_tiles: int = 24
@export var chunk_view_distance: int = 3
@export var chunk_unload_distance: int = 5
@export var chunk_update_interval: float = 0.1
@export var tiles_per_frame: int = 80

@export var cave_source_name: String = "Cave Tiles"
@export var cave_source_fallback_id: int = 2
@export var cave_atlas: Vector2i = Vector2i(0, 0)
@export var cave_wall_atlas: Vector2i = Vector2i(1, 1)

@export var water_source_name: String = "Water Tiles"
@export var water_source_fallback_id: int = 1
@export var water_atlas: Vector2i = Vector2i(0, 0)

@export var lake_region_size_tiles: int = 72
@export var lake_chance_per_region: float = 0.30
@export var lake_second_chance: float = 0.10
@export var lake_min_radius_tiles: float = 3.5
@export var lake_max_radius_tiles: float = 7.0
@export var lake_margin_tiles: int = 4

@export var cave_rock_scene_path: String = "res://Scenes/rock.tscn"
@export var cave_exit_scene_path: String = "res://Scenes/cave.tscn"
@export var cave_rocks_per_chunk: float = 3.0
@export var cave_rock_min_distance: float = 200.0
@export var cave_rock_water_clearance: float = 3.0
@export var cave_rock_spawn_attempts: int = 20

@export var tunnel_radius: int = 4
@export var room_radius_min: int = 8
@export var room_radius_max: int = 30
@export var cave_half_extent: int = 180
@export var room_count_min: int = 8
@export var room_count_max: int = 16

enum BiomeType { CAVE_FLOOR, CAVE_WALL, WATER_LAKE }

var in_cave: bool = false
var world_seed: int = 0
var _enter_cooldown: float = 0.0
const ENTER_COOLDOWN_TIME: float = 2.0

var _active: bool = false
var _tilemap: TileMap
var _world_gen: Node
var _env_spawner: Node
var cave_source_id: int = -1
var water_source_id: int = -1

var lake_region_cache: Dictionary = {}
var loaded_chunks: Dictionary = {}
var pending_chunks: Array = []

var _paint_chunk: Vector2i = Vector2i(999999, 999999)
var _paint_index: int = 0
var _paint_tiles: Array = []
var _chunk_update_timer: float = 0.0

var _cave_rock_positions: Dictionary = {}
var _cave_active_rocks: Dictionary = {}
var _packed_cave_rock_scene: PackedScene = null
var _packed_cave_exit_scene: PackedScene = null
var _all_cave_rock_world_positions: Array = []

var _wall_tiles: Dictionary = {}
var _carved_tiles: Dictionary = {}
var _reachable_tiles: Dictionary = {}
var _cave_entrance_tile: Vector2i = Vector2i(0, 0)
var _cave_exit_tile: Vector2i = Vector2i(0, 0)
var _cave_exit: Node2D = null
var _cave_bounds_min: Vector2i = Vector2i(0, 0)
var _cave_bounds_max: Vector2i = Vector2i(0, 0)

func _ready():
	await get_tree().process_frame
	_resolve_refs()
	_packed_cave_rock_scene = load(cave_rock_scene_path)
	_packed_cave_exit_scene = load(cave_exit_scene_path)

func _resolve_refs():
	_tilemap = get_tree().root.get_node_or_null("Scene/TileMap")
	_world_gen = get_tree().root.get_node_or_null("Scene/WorldGen")
	_env_spawner = get_tree().root.get_node_or_null("Scene/EnvironmentGen")
	if not _env_spawner:
		var scene = get_tree().root.get_node_or_null("Scene")
		if scene:
			for child in scene.get_children():
				if child.get_script() and child.has_method("_unload_all_chunks"):
					_env_spawner = child
					break

func enter_cave(player: CharacterBody2D):
	if in_cave:
		return
	if _enter_cooldown > 0.0:
		return
	_resolve_refs()
	in_cave = true
	_enter_cooldown = ENTER_COOLDOWN_TIME
	_cave_entrance_tile = _find_linked_overworld_entrance_tile(player.global_position)
	var animal_spawner = get_tree().root.get_node_or_null("Scene/AnimalSpawner")
	if animal_spawner and animal_spawner.has_method("clear_all_entities"):
		await animal_spawner.clear_all_entities()
	if _world_gen:
		_world_gen.set_process(false)
		if _tilemap:
			for cc in _world_gen.loaded_chunks.keys():
				var start: Vector2i = _world_gen.chunk_to_start_tile(cc)
				for x in _world_gen.chunk_size_tiles:
					for y in _world_gen.chunk_size_tiles:
						_tilemap.erase_cell(0, Vector2i(start.x + x, start.y + y))
	if _env_spawner:
		_env_spawner.set_process(false)
		if _env_spawner.has_method("_unload_all_chunks"):
			_env_spawner._unload_all_chunks()
		if _env_spawner.has_method("_unload_all_cave_regions"):
			_env_spawner._unload_all_cave_regions()
	else:
		var fallback := get_tree().root.get_node_or_null("Scene/EnvObjectSpawner")
		if fallback:
			fallback.set_process(false)
			if fallback.has_method("_unload_all_chunks"):
				fallback._unload_all_chunks()
	var seed: int = _world_gen.world_seed if _world_gen else 0
	_activate(seed)
	var scene = get_tree().root.get_node_or_null("Scene")
	if scene and scene.has_method("_refresh_floor_item_visibility"):
		scene._refresh_floor_item_visibility()
	_chunk_update_timer = 0.0
	_update_chunks_around_player()
	for i in 6:
		_paint_next_tiles()

func exit_cave(player: CharacterBody2D):
	if not in_cave:
		return
	if _enter_cooldown > 0.0:
		return
	var return_tile := _cave_entrance_tile
	in_cave = false
	_enter_cooldown = ENTER_COOLDOWN_TIME
	var animal_spawner = get_tree().root.get_node_or_null("Scene/AnimalSpawner")
	if animal_spawner and animal_spawner.has_method("clear_all_entities"):
		await animal_spawner.clear_all_entities()
	_deactivate()
	if _world_gen:
		_world_gen.set_process(true)
		if _world_gen.has_method("_force_reload_all_chunks"):
			_world_gen._force_reload_all_chunks()
		elif _world_gen.has_method("_update_chunks_around_player"):
			_world_gen._update_chunks_around_player()
		_world_gen.chunk_update_timer = 0.0
		for i in 6:
			_world_gen._paint_next_tiles()
	if _env_spawner:
		_env_spawner.set_process(true)
		_env_spawner.update_timer = 0.0
		if _env_spawner.has_method("_refresh_references"):
			_env_spawner._refresh_references()
		if _env_spawner.has_method("queue_chunks_around_world_pos") and _world_gen:
			var return_world_pos = _world_gen.tile_to_world_center(return_tile)
			_env_spawner.queue_chunks_around_world_pos(return_world_pos, 4)
		if _env_spawner.has_method("_update_cave_regions"):
			_env_spawner._update_cave_regions()
		if _env_spawner.has_method("_process_load_queue_step"):
			for i in 8:
				_env_spawner._process_load_queue_step()
		if _env_spawner.has_method("_process_object_spawn_queue"):
			for i in 8:
				_env_spawner._process_object_spawn_queue()
	var scene = get_tree().root.get_node_or_null("Scene")
	if scene and scene.has_method("_refresh_floor_item_visibility"):
		scene._refresh_floor_item_visibility()

func _activate(seed: int):
	world_seed = seed
	_find_tile_sources()
	lake_region_cache.clear()
	loaded_chunks.clear()
	pending_chunks.clear()
	_paint_chunk = Vector2i(999999, 999999)
	_paint_index = 0
	_paint_tiles.clear()
	_chunk_update_timer = 0.0
	_cave_rock_positions.clear()
	_cave_active_rocks.clear()
	_all_cave_rock_world_positions.clear()
	_despawn_cave_exit()
	_wall_tiles.clear()
	_carved_tiles.clear()
	_reachable_tiles.clear()
	_generate_cave_layout()
	_flood_fill_reachable()
	_spawn_cave_exit()
	_active = true
	_update_chunks_around_player()

func _generate_cave_layout():
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(world_seed ^ 0xCAFEBABE)
	_cave_bounds_min = _cave_entrance_tile - Vector2i(cave_half_extent, cave_half_extent)
	_cave_bounds_max = _cave_entrance_tile + Vector2i(cave_half_extent, cave_half_extent)
	for x in range(_cave_bounds_min.x, _cave_bounds_max.x + 1):
		for y in range(_cave_bounds_min.y, _cave_bounds_max.y + 1):
			_wall_tiles[Vector2i(x, y)] = true
	var room_count := rng.randi_range(room_count_min, room_count_max)
	var room_centers: Array = []
	var margin := room_radius_max + 2
	var first_room := _cave_entrance_tile
	_cave_exit_tile = first_room
	var first_radius := rng.randi_range(room_radius_min, room_radius_max)
	_carve_room(first_room, first_radius, rng)
	room_centers.append(first_room)
	for _i in range(1, room_count):
		for _attempt in 40:
			var cx := rng.randi_range(_cave_bounds_min.x + margin, _cave_bounds_max.x - margin)
			var cy := rng.randi_range(_cave_bounds_min.y + margin, _cave_bounds_max.y - margin)
			var candidate := Vector2i(cx, cy)
			var too_close := false
			for existing in room_centers:
				if candidate.distance_to(existing) < room_radius_max * 2:
					too_close = true
					break
			if too_close:
				continue
			var radius := rng.randi_range(room_radius_min, room_radius_max)
			_carve_room(candidate, radius, rng)
			room_centers.append(candidate)
			break
	for i in range(room_centers.size() - 1):
		_carve_tunnel_between(room_centers[i], room_centers[i + 1])
	var extra_connections := rng.randi_range(2, 5)
	for _e in extra_connections:
		var a: Vector2i = room_centers[rng.randi() % room_centers.size()]
		var b: Vector2i = room_centers[rng.randi() % room_centers.size()]
		if a != b:
			_carve_tunnel_between(a, b)

func _carve_room(center: Vector2i, radius: int, rng: RandomNumberGenerator):
	var wobble := radius / 3
	for dx in range(-radius - wobble, radius + wobble + 1):
		for dy in range(-radius - wobble, radius + wobble + 1):
			var dist := Vector2(dx, dy).length()
			var wobbled_radius := radius + rng.randf_range(-wobble * 0.4, wobble * 0.4)
			if dist <= wobbled_radius:
				var tc := center + Vector2i(dx, dy)
				if tc.x >= _cave_bounds_min.x and tc.x <= _cave_bounds_max.x and \
				   tc.y >= _cave_bounds_min.y and tc.y <= _cave_bounds_max.y:
					_carved_tiles[tc] = true
					_wall_tiles.erase(tc)

func _carve_tunnel_between(from: Vector2i, to: Vector2i):
	var pos := from
	var max_steps := 600
	var steps := 0
	while pos != to and steps < max_steps:
		steps += 1
		var diff := to - pos
		if abs(diff.x) > abs(diff.y):
			pos += Vector2i(sign(diff.x), 0)
		else:
			pos += Vector2i(0, sign(diff.y))
		for dr in range(-tunnel_radius, tunnel_radius + 1):
			for dc in range(-tunnel_radius, tunnel_radius + 1):
				if Vector2(dr, dc).length() <= tunnel_radius:
					var tc := pos + Vector2i(dr, dc)
					if tc.x >= _cave_bounds_min.x and tc.x <= _cave_bounds_max.x and \
					   tc.y >= _cave_bounds_min.y and tc.y <= _cave_bounds_max.y:
						_carved_tiles[tc] = true
						_wall_tiles.erase(tc)

func _flood_fill_reachable():
	var seed_tile := Vector2i(0, 0)
	var found := false
	for radius in range(0, 200):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dy) != radius:
					continue
				var tc := _cave_entrance_tile + Vector2i(dx, dy)
				if _carved_tiles.has(tc):
					seed_tile = tc
					found = true
					break
			if found:
				break
		if found:
			break
	if not found:
		return
	var queue: Array = [seed_tile]
	var directions := [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
	]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_back()
		if _reachable_tiles.has(current):
			continue
		if not _carved_tiles.has(current):
			continue
		_reachable_tiles[current] = true
		for dir in directions:
			var neighbor: Vector2i = current + dir
			if _carved_tiles.has(neighbor) and not _reachable_tiles.has(neighbor):
				queue.append(neighbor)

func _deactivate():
	_active = false
	_despawn_cave_exit()
	_wall_tiles.clear()
	_carved_tiles.clear()
	_reachable_tiles.clear()
	_all_cave_rock_world_positions.clear()
	for cc in loaded_chunks.keys():
		_erase_chunk_tiles(cc)
		_despawn_cave_rocks_for_chunk(cc)
	loaded_chunks.clear()
	pending_chunks.clear()
	_paint_chunk = Vector2i(999999, 999999)
	_paint_index = 0
	_paint_tiles.clear()
	lake_region_cache.clear()

func _process(delta):
	if _enter_cooldown > 0.0:
		_enter_cooldown -= delta
	if not _active:
		return
	_paint_next_tiles()
	_chunk_update_timer -= delta
	if _chunk_update_timer > 0.0:
		return
	_chunk_update_timer = chunk_update_interval
	_update_chunks_around_player()

func _get_local_player():
	var scene = get_tree().root.get_node_or_null("Scene")
	if not scene:
		return null
	var lp = scene.get("local_player")
	if lp and is_instance_valid(lp):
		return lp
	for child in scene.get_children():
		if child is CharacterBody2D:
			if not multiplayer.has_multiplayer_peer() or child.is_multiplayer_authority():
				return child
	return null

func _update_chunks_around_player():
	if not _tilemap:
		return
	var player = _get_local_player()
	if not player:
		return
	var player_chunk := tile_to_chunk(world_to_tile(player.global_position))
	var to_queue: Array = []
	for cx in range(player_chunk.x - chunk_view_distance, player_chunk.x + chunk_view_distance + 1):
		for cy in range(player_chunk.y - chunk_view_distance, player_chunk.y + chunk_view_distance + 1):
			var cc := Vector2i(cx, cy)
			if loaded_chunks.has(cc) or pending_chunks.has(cc) or _paint_chunk == cc:
				continue
			to_queue.append(cc)
	to_queue.sort_custom(func(a, b):
		return a.distance_squared_to(player_chunk) < b.distance_squared_to(player_chunk))
	for cc in to_queue:
		pending_chunks.append(cc)
	for cc in loaded_chunks.keys().duplicate():
		if abs(cc.x - player_chunk.x) > chunk_unload_distance or \
		   abs(cc.y - player_chunk.y) > chunk_unload_distance:
			_unload_chunk(cc)
	pending_chunks = pending_chunks.filter(func(cc):
		return abs(cc.x - player_chunk.x) <= chunk_unload_distance and \
			   abs(cc.y - player_chunk.y) <= chunk_unload_distance)

func _paint_next_tiles():
	var painted := 0
	while painted < tiles_per_frame:
		if _paint_chunk == Vector2i(999999, 999999):
			if pending_chunks.is_empty():
				return
			_paint_chunk = pending_chunks.pop_front()
			_paint_index = 0
			_precompute_chunk(_paint_chunk)
		if _paint_index >= _paint_tiles.size():
			loaded_chunks[_paint_chunk] = true
			_paint_chunk = Vector2i(999999, 999999)
			_paint_tiles.clear()
			_paint_index = 0
			continue
		var entry = _paint_tiles[_paint_index]
		if entry[1] != null:
			_apply_tile(entry[0], entry[1])
		_paint_index += 1
		painted += 1

func _precompute_chunk(chunk_coord: Vector2i):
	_paint_tiles.clear()
	var start := chunk_to_start_tile(chunk_coord)
	var total := chunk_size_tiles * chunk_size_tiles
	_paint_tiles.resize(total)
	var chunk_has_content := false
	for i in total:
		var tc := Vector2i(start.x + i % chunk_size_tiles, start.y + i / chunk_size_tiles)
		if _carved_tiles.has(tc) or _wall_tiles.has(tc):
			chunk_has_content = true
			break
	if not chunk_has_content:
		for i in total:
			_paint_tiles[i] = [Vector2i(start.x + i % chunk_size_tiles, start.y + i / chunk_size_tiles), null]
		return
	for i in total:
		var tc := Vector2i(start.x + i % chunk_size_tiles, start.y + i / chunk_size_tiles)
		if _wall_tiles.has(tc):
			_paint_tiles[i] = [tc, BiomeType.CAVE_WALL]
		elif _reachable_tiles.has(tc):
			_paint_tiles[i] = [tc, _biome_for_tile(tc)]
		else:
			_paint_tiles[i] = [tc, null]
	_spawn_cave_rocks_for_chunk(chunk_coord)

func _apply_tile(tc: Vector2i, biome: BiomeType):
	match biome:
		BiomeType.WATER_LAKE:
			if water_source_id != -1:
				_tilemap.set_cell(0, tc, water_source_id, water_atlas)
			else:
				_tilemap.set_cell(0, tc, cave_source_id, cave_atlas)
		BiomeType.CAVE_WALL:
			_tilemap.set_cell(0, tc, cave_source_id, cave_wall_atlas)
		_:
			_tilemap.set_cell(0, tc, cave_source_id, cave_atlas)

func _biome_for_tile(tc: Vector2i) -> BiomeType:
	if not _reachable_tiles.has(tc):
		return BiomeType.CAVE_WALL
	var region := Vector2i(
		floori(float(tc.x) / float(lake_region_size_tiles)),
		floori(float(tc.y) / float(lake_region_size_tiles)))
	for lake in _get_lakes_for_region(region):
		var off: Vector2 = Vector2(tc) - lake["center"]
		if (off.x * off.x) / (lake["rx"] * lake["rx"]) + \
		   (off.y * off.y) / (lake["ry"] * lake["ry"]) <= 1.0:
			return BiomeType.WATER_LAKE
	return BiomeType.CAVE_FLOOR

func _tile_is_dry_floor(tc: Vector2i) -> bool:
	if not _reachable_tiles.has(tc):
		return false
	return _biome_for_tile(tc) == BiomeType.CAVE_FLOOR

func _unload_chunk(cc: Vector2i):
	pending_chunks.erase(cc)
	if _paint_chunk == cc:
		_paint_chunk = Vector2i(999999, 999999)
		_paint_index = 0
		_paint_tiles.clear()
	_erase_chunk_tiles(cc)
	_despawn_cave_rocks_for_chunk(cc)
	loaded_chunks.erase(cc)

func _erase_chunk_tiles(cc: Vector2i):
	var start := chunk_to_start_tile(cc)
	for x in chunk_size_tiles:
		for y in chunk_size_tiles:
			_tilemap.erase_cell(0, Vector2i(start.x + x, start.y + y))

func _get_lakes_for_region(region: Vector2i) -> Array:
	if lake_region_cache.has(region):
		return lake_region_cache[region]
	var lakes := []
	var rng := RandomNumberGenerator.new()
	rng.seed = _lake_seed(region)
	if rng.randf() <= lake_chance_per_region:
		var count := 2 if rng.randf() < lake_second_chance else 1
		for _i in count:
			var rx := rng.randf_range(lake_min_radius_tiles, lake_max_radius_tiles)
			var ry := rng.randf_range(lake_min_radius_tiles, lake_max_radius_tiles)
			var center := _pick_cave_lake_center(region, rx, ry, rng)
			if center == Vector2(-99999, -99999):
				continue
			lakes.append({"center": center, "rx": rx, "ry": ry})
	lake_region_cache[region] = lakes
	return lakes

func _pick_cave_lake_center(region: Vector2i, rx: float, ry: float, rng: RandomNumberGenerator) -> Vector2:
	var origin := Vector2i(region.x * lake_region_size_tiles, region.y * lake_region_size_tiles)
	for _attempt in 20:
		var center := Vector2i(
			origin.x + rng.randi_range(lake_margin_tiles, lake_region_size_tiles - lake_margin_tiles),
			origin.y + rng.randi_range(lake_margin_tiles, lake_region_size_tiles - lake_margin_tiles))
		var check_radius := int(max(rx, ry)) + 2
		var all_carved := true
		for dx in range(-check_radius, check_radius + 1):
			for dy in range(-check_radius, check_radius + 1):
				var off := Vector2(dx, dy)
				if (off.x * off.x) / (rx * rx) + (off.y * off.y) / (ry * ry) <= 1.0:
					if not _reachable_tiles.has(center + Vector2i(dx, dy)):
						all_carved = false
						break
			if not all_carved:
				break
		if all_carved:
			return Vector2(center)
	return Vector2(-99999, -99999)

func _spawn_cave_rocks_for_chunk(cc: Vector2i):
	if not _packed_cave_rock_scene:
		return
	if _cave_rock_positions.has(cc):
		for env_id in _cave_rock_positions[cc]:
			if not _cave_active_rocks.has(env_id):
				_spawn_cave_rock(env_id, _cave_rock_positions[cc][env_id])
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _cave_chunk_seed(cc, "rock")
	var count: int = int(cave_rocks_per_chunk)
	if cave_rocks_per_chunk - float(count) > 0.0:
		if rng.randf() < cave_rocks_per_chunk - float(count):
			count += 1
	var start_tile := chunk_to_start_tile(cc)
	_cave_rock_positions[cc] = {}
	var cave_positions := _get_cave_entrance_positions()
	var placed_this_chunk: Array = []
	var min_dist_sq := cave_rock_min_distance * cave_rock_min_distance
	for _i in count:
		for _attempt in cave_rock_spawn_attempts:
			var tx := rng.randi_range(start_tile.x, start_tile.x + chunk_size_tiles - 1)
			var ty := rng.randi_range(start_tile.y, start_tile.y + chunk_size_tiles - 1)
			var tc := Vector2i(tx, ty)
			if not _tile_is_dry_floor(tc):
				continue
			if tc.distance_to(_cave_exit_tile) < 8.0:
				continue
			var neighbors_clear := true
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					if not _tile_is_dry_floor(Vector2i(tx + dx, ty + dy)):
						neighbors_clear = false
						break
				if not neighbors_clear:
					break
			if not neighbors_clear:
				continue
			var world_pos: Vector2
			if _tilemap:
				world_pos = _tilemap.to_global(_tilemap.map_to_local(tc))
			else:
				world_pos = Vector2(tc) * 64.0 + Vector2(32.0, 32.0)
			var too_close := false
			for cave_pos in cave_positions:
				if world_pos.distance_to(cave_pos) < 400.0:
					too_close = true
					break
			if too_close:
				continue
			for other in _all_cave_rock_world_positions:
				if world_pos.distance_squared_to(other) < min_dist_sq:
					too_close = true
					break
			if too_close:
				continue
			for other in placed_this_chunk:
				if world_pos.distance_squared_to(other) < min_dist_sq:
					too_close = true
					break
			if too_close:
				continue
			placed_this_chunk.append(world_pos)
			_all_cave_rock_world_positions.append(world_pos)
			var env_id := "caverock:" + str(cc.x) + ":" + str(cc.y) + ":" + str(placed_this_chunk.size())
			_cave_rock_positions[cc][env_id] = world_pos
			_spawn_cave_rock(env_id, world_pos)
			break

func _spawn_cave_rock(env_id: String, world_pos: Vector2):
	if _cave_active_rocks.has(env_id):
		return
	var scene_node := get_tree().root.get_node_or_null("Scene")
	if not scene_node:
		return
	var rock = _packed_cave_rock_scene.instantiate()
	rock.global_position = world_pos
	rock.set_meta("env_id", env_id)
	scene_node.add_child(rock)
	_cave_active_rocks[env_id] = rock

func _spawn_cave_exit():
	if _cave_exit or not _packed_cave_exit_scene:
		return
	var scene_node := get_tree().root.get_node_or_null("Scene")
	if not scene_node:
		return
	var world_pos := _tile_to_world_center(_cave_exit_tile)
	_cave_exit = _packed_cave_exit_scene.instantiate()
	_cave_exit.name = "LinkedCaveExit"
	_cave_exit.global_position = world_pos
	_cave_exit.set_meta("linked_overworld_tile", _cave_entrance_tile)
	_cave_exit.set_meta("cave_room_tile", _cave_exit_tile)
	scene_node.add_child(_cave_exit)

func _despawn_cave_exit():
	if _cave_exit and is_instance_valid(_cave_exit):
		_cave_exit.queue_free()
	_cave_exit = null

func _find_linked_overworld_entrance_tile(player_pos: Vector2) -> Vector2i:
	if not _world_gen:
		return Vector2i(0, 0)
	var best_pos := player_pos
	var best_dist_sq := INF
	if _env_spawner and _env_spawner.get("_cave_positions") != null:
		for cave_pos in _env_spawner._cave_positions.values():
			var dist_sq: float = player_pos.distance_squared_to(cave_pos)
			if dist_sq < best_dist_sq:
				best_dist_sq = dist_sq
				best_pos = cave_pos
	return _world_gen.world_to_tile(best_pos)

func _despawn_cave_rocks_for_chunk(cc: Vector2i):
	if not _cave_rock_positions.has(cc):
		return
	for env_id in _cave_rock_positions[cc]:
		if _cave_active_rocks.has(env_id):
			var rock = _cave_active_rocks[env_id]
			if is_instance_valid(rock):
				rock.queue_free()
			_cave_active_rocks.erase(env_id)

func _cave_chunk_seed(cc: Vector2i, kind: String) -> int:
	var kind_key := 0
	if kind == "rock":
		kind_key = 7
	return abs(world_seed ^ (cc.x * 374761393) ^ (cc.y * 1234567891) ^ (kind_key * 7919) ^ 99991)

func world_to_tile(world_pos: Vector2) -> Vector2i:
	if _tilemap:
		return _tilemap.local_to_map(_tilemap.to_local(world_pos))
	return Vector2i(floori(world_pos.x / 64), floori(world_pos.y / 64))

func _tile_to_world_center(tile: Vector2i) -> Vector2:
	if _tilemap:
		return _tilemap.to_global(_tilemap.map_to_local(tile))
	return Vector2(tile) * 64.0 + Vector2(32.0, 32.0)

func tile_to_chunk(tc: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(tc.x) / float(chunk_size_tiles)),
		floori(float(tc.y) / float(chunk_size_tiles)))

func chunk_to_start_tile(cc: Vector2i) -> Vector2i:
	return Vector2i(cc.x * chunk_size_tiles, cc.y * chunk_size_tiles)

func is_chunk_loaded(cc: Vector2i) -> bool:
	return loaded_chunks.has(cc)

func _lake_seed(region: Vector2i) -> int:
	return abs(world_seed ^ (region.x * 987654321) ^ (region.y * 123456789) ^ 9876543210)

func _find_tile_sources():
	cave_source_id = -1
	water_source_id = -1
	if not _tilemap or not _tilemap.tile_set:
		push_error("CaveWorldGen: TileMap or TileSet missing")
		return
	var ts := _tilemap.tile_set
	var want_cave := cave_source_name.strip_edges().to_lower()
	var want_water := water_source_name.strip_edges().to_lower()
	for i in ts.get_source_count():
		var sid := ts.get_source_id(i)
		var src := ts.get_source(sid)
		if not src:
			continue
		var n := src.resource_name.strip_edges().to_lower()
		if n == want_cave and cave_source_id == -1:
			cave_source_id = sid
		if n == want_water and water_source_id == -1:
			water_source_id = sid
	if cave_source_id == -1:
		for i in ts.get_source_count():
			var sid := ts.get_source_id(i)
			if sid == cave_source_fallback_id:
				cave_source_id = sid
				break
	if water_source_id == -1:
		for i in ts.get_source_count():
			var sid := ts.get_source_id(i)
			if sid == water_source_fallback_id:
				water_source_id = sid
				break
	if water_source_id == -1 and cave_source_id != -1:
		push_warning("CaveWorldGen: water source not found, using cave source as fallback")
		water_source_id = cave_source_id
	if cave_source_id == -1:
		push_error("CaveWorldGen: Could not find cave tile source '%s'" % cave_source_name)

func _get_cave_entrance_positions() -> Array:
	var env = get_tree().root.get_node_or_null("Scene/EnvironmentGen")
	if not env:
		return []
	return env._cave_positions.values()
