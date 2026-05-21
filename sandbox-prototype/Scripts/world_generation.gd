extends Node2D

@export var tile_size: int = 64
@export var biome_noise_frequency: float = 0.00007
@export var forest_threshold: float = 0.08
@export var world_seed: int = 0

@export var chunk_size_tiles: int = 24
@export var chunk_view_distance: int = 3
@export var chunk_unload_distance: int = 5
@export var chunk_update_interval: float = 0.25
@export var tiles_painted_per_frame: int = 192

@export var water_source_name: String = "Water Tiles"
@export var water_source_fallback_id: int = 1
@export var water_atlas: Vector2i = Vector2i(0, 0)
@export var spawn_water_safe_radius: float = 900.0

@export var lake_region_size_tiles: int = 72
@export var lake_chance_per_region: float = 0.65
@export var lake_second_chance: float = 0.18
@export var lake_min_radius_tiles: float = 3.5
@export var lake_max_radius_tiles: float = 8.5
@export var lake_forest_margin_tiles: int = 5

@export var river_region_size_tiles: int = 192
@export var river_chance_per_region: float = 0.015
@export var river_loop_radius_min_tiles: float = 7.0
@export var river_loop_radius_max_tiles: float = 14.0
@export var river_path_points: int = 6
@export var river_min_width_tiles: float = 0.4
@export var river_max_width_tiles: float = 0.8

enum BiomeType { PLAINS, FOREST, WATER }

var tilemap: TileMap
var noise: FastNoiseLite
var water_source_id: int = -1

var biome_by_tile: Dictionary = {}
var land_biome_cache: Dictionary = {}
var lake_region_cache: Dictionary = {}
var river_region_cache: Dictionary = {}
var loaded_chunks: Dictionary = {}

var chunk_paint_queue: Array = []
var chunks_painting: Dictionary = {}
var active_paint_chunk: Vector2i = Vector2i(99999999, 99999999)
var active_paint_index: int = 0
var chunk_update_timer: float = 0.0

const PLAINS_SOURCE = 0
const PLAINS_ATLAS = Vector2i(2, 2)
const FOREST_SOURCE = 0
const FOREST_ATLAS = Vector2i(0, 0)

func _ready():
	await get_tree().process_frame
	await get_tree().process_frame

	if world_seed == 0 and (not multiplayer.has_multiplayer_peer() or multiplayer.is_server()):
		world_seed = randi()
		print("World seed: ", world_seed)

	generate_world()

func _process(delta):
	_process_chunk_paint_queue()

	chunk_update_timer -= delta
	if chunk_update_timer > 0.0:
		return

	chunk_update_timer = chunk_update_interval
	_update_chunks_around_player()

func generate_world():
	tilemap = get_tree().root.get_node_or_null("Scene/TileMap")
	if not tilemap:
		push_error("WorldGen: TileMap not found at Scene/TileMap")
		return

	noise = null
	_find_water_source()
	_ensure_noise_ready()

	biome_by_tile.clear()
	land_biome_cache.clear()
	lake_region_cache.clear()
	river_region_cache.clear()
	loaded_chunks.clear()
	chunk_paint_queue.clear()
	chunks_painting.clear()
	active_paint_chunk = Vector2i(99999999, 99999999)
	active_paint_index = 0

	_update_chunks_around_player()

func set_world_settings(seed: int, synced_tile_size: int, frequency: float, threshold: float):
	world_seed = seed
	tile_size = synced_tile_size
	biome_noise_frequency = frequency
	forest_threshold = threshold
	generate_world()

func world_to_tile(world_pos: Vector2) -> Vector2i:
	if tilemap:
		return tilemap.local_to_map(tilemap.to_local(world_pos))
	return Vector2i(floori(world_pos.x / tile_size), floori(world_pos.y / tile_size))

func tile_to_world_center(tile_coord: Vector2i) -> Vector2:
	if tilemap:
		return tilemap.to_global(tilemap.map_to_local(tile_coord))
	return Vector2((tile_coord.x + 0.5) * tile_size, (tile_coord.y + 0.5) * tile_size)

func tile_to_chunk(tile_coord: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(tile_coord.x) / float(chunk_size_tiles)),
		floori(float(tile_coord.y) / float(chunk_size_tiles))
	)

func chunk_to_start_tile(chunk_coord: Vector2i) -> Vector2i:
	return Vector2i(chunk_coord.x * chunk_size_tiles, chunk_coord.y * chunk_size_tiles)

func is_chunk_loaded(chunk_coord: Vector2i) -> bool:
	return loaded_chunks.has(chunk_coord)

func _get_local_player():
	var scene_node = get_tree().root.get_node_or_null("Scene")
	if not scene_node:
		return null

	if scene_node.get("local_player"):
		return scene_node.get("local_player")

	for child in scene_node.get_children():
		if child is CharacterBody2D:
			if not multiplayer.has_multiplayer_peer() or child.is_multiplayer_authority():
				return child

	return null

func _update_chunks_around_player():
	if not tilemap:
		return
	var player = _get_local_player()
	if not player:
		return

	var player_tile = world_to_tile(player.global_position)
	var player_chunk = tile_to_chunk(player_tile)

	for cx in range(player_chunk.x - chunk_view_distance, player_chunk.x + chunk_view_distance + 1):
		for cy in range(player_chunk.y - chunk_view_distance, player_chunk.y + chunk_view_distance + 1):
			var chunk_coord = Vector2i(cx, cy)
			if not loaded_chunks.has(chunk_coord) and not chunks_painting.has(chunk_coord):
				_queue_paint_chunk(chunk_coord)

	var chunks_to_unload = []
	for chunk_coord in loaded_chunks.keys():
		var dx = abs(chunk_coord.x - player_chunk.x)
		var dy = abs(chunk_coord.y - player_chunk.y)
		if dx > chunk_unload_distance or dy > chunk_unload_distance:
			chunks_to_unload.append(chunk_coord)

	for chunk_coord in chunks_to_unload:
		_unload_chunk(chunk_coord)

func _queue_paint_chunk(chunk_coord: Vector2i):
	chunks_painting[chunk_coord] = true
	chunk_paint_queue.append(chunk_coord)

func _process_chunk_paint_queue():
	var painted_this_frame := 0

	while painted_this_frame < tiles_painted_per_frame:
		if active_paint_chunk == Vector2i(99999999, 99999999):
			if chunk_paint_queue.is_empty():
				return
			active_paint_chunk = chunk_paint_queue.pop_front()
			active_paint_index = 0

		var start_tile = chunk_to_start_tile(active_paint_chunk)
		var total_tiles = chunk_size_tiles * chunk_size_tiles

		while active_paint_index < total_tiles and painted_this_frame < tiles_painted_per_frame:
			var x = active_paint_index % chunk_size_tiles
			var y = floori(float(active_paint_index) / float(chunk_size_tiles))
			var tile_coord = Vector2i(start_tile.x + x, start_tile.y + y)

			var biome = _calculate_biome_for_tile(tile_coord)
			biome_by_tile[tile_coord] = biome

			if biome == BiomeType.WATER:
				_paint_water(tile_coord)
			elif biome == BiomeType.FOREST:
				tilemap.set_cell(0, tile_coord, FOREST_SOURCE, FOREST_ATLAS)
			else:
				tilemap.set_cell(0, tile_coord, PLAINS_SOURCE, PLAINS_ATLAS)

			active_paint_index += 1
			painted_this_frame += 1

		if active_paint_index >= total_tiles:
			loaded_chunks[active_paint_chunk] = true
			chunks_painting.erase(active_paint_chunk)
			active_paint_chunk = Vector2i(99999999, 99999999)
			active_paint_index = 0

func _unload_chunk(chunk_coord: Vector2i):
	chunks_painting.erase(chunk_coord)
	chunk_paint_queue.erase(chunk_coord)

	if active_paint_chunk == chunk_coord:
		active_paint_chunk = Vector2i(99999999, 99999999)
		active_paint_index = 0

	loaded_chunks.erase(chunk_coord)
	var start_tile = chunk_to_start_tile(chunk_coord)

	for x in range(chunk_size_tiles):
		for y in range(chunk_size_tiles):
			var tile_coord = Vector2i(start_tile.x + x, start_tile.y + y)
			tilemap.erase_cell(0, tile_coord)
			biome_by_tile.erase(tile_coord)
			land_biome_cache.erase(tile_coord)

func _ensure_noise_ready():
	if noise != null:
		return

	noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = world_seed
	noise.frequency = biome_noise_frequency
	noise.fractal_octaves = 4

func _calculate_biome_for_tile(tile_coord: Vector2i) -> BiomeType:
	var land_biome = _calculate_land_biome_for_tile(tile_coord)

	if land_biome == BiomeType.FOREST and _is_forest_lake_tile(tile_coord):
		return BiomeType.WATER

	if land_biome == BiomeType.PLAINS and _is_river_tile(tile_coord):
		return BiomeType.WATER

	return land_biome

func _calculate_land_biome_for_tile(tile_coord: Vector2i) -> BiomeType:
	if land_biome_cache.has(tile_coord):
		return land_biome_cache[tile_coord]

	_ensure_noise_ready()
	var tile_center = tile_to_world_center(tile_coord)
	var result = BiomeType.PLAINS

	if noise.get_noise_2d(tile_center.x, tile_center.y) > forest_threshold:
		result = BiomeType.FOREST

	land_biome_cache[tile_coord] = result
	return result

func _paint_water(tile_coord: Vector2i):
	if water_source_id == -1:
		tilemap.set_cell(0, tile_coord, PLAINS_SOURCE, PLAINS_ATLAS)
		return
	tilemap.set_cell(0, tile_coord, water_source_id, water_atlas)

func _find_water_source():
	water_source_id = -1
	if not tilemap or not tilemap.tile_set:
		return

	var tile_set = tilemap.tile_set
	var wanted_name = water_source_name.strip_edges().to_lower()

	for i in range(tile_set.get_source_count()):
		var source_id = tile_set.get_source_id(i)
		var source = tile_set.get_source(source_id)
		if source and source.resource_name.strip_edges().to_lower() == wanted_name:
			water_source_id = source_id
			return

	for i in range(tile_set.get_source_count()):
		var source_id = tile_set.get_source_id(i)
		if source_id == water_source_fallback_id:
			water_source_id = source_id
			return

	push_warning("WorldGen: water tile source not found. Add a TileSet source named '%s'." % water_source_name)

func _is_forest_lake_tile(tile_coord: Vector2i) -> bool:
	var world_pos = tile_to_world_center(tile_coord)
	if world_pos.length() < spawn_water_safe_radius:
		return false

	var region = Vector2i(
		floori(float(tile_coord.x) / float(lake_region_size_tiles)),
		floori(float(tile_coord.y) / float(lake_region_size_tiles))
	)

	return _is_inside_lake_region(tile_coord, region)

func _is_inside_lake_region(tile_coord: Vector2i, region: Vector2i) -> bool:
	var lakes = _get_lakes_for_region(region)

	for lake in lakes:
		var center: Vector2 = lake["center"]
		var radius_x: float = lake["radius_x"]
		var radius_y: float = lake["radius_y"]
		var offset = Vector2(tile_coord) - center
		var ellipse_value = (offset.x * offset.x) / (radius_x * radius_x) + (offset.y * offset.y) / (radius_y * radius_y)
		if ellipse_value <= 1.0:
			return true

	return false

func _get_lakes_for_region(region: Vector2i) -> Array:
	if lake_region_cache.has(region):
		return lake_region_cache[region]

	var lakes = []
	var rng = RandomNumberGenerator.new()
	rng.seed = _lake_region_seed(region)

	if rng.randf() > lake_chance_per_region:
		lake_region_cache[region] = lakes
		return lakes

	var lake_count = 1
	if rng.randf() < lake_second_chance:
		lake_count = 2

	for i in range(lake_count):
		var center = _pick_lake_center_in_region(region, rng)
		if center == Vector2i(99999999, 99999999):
			continue

		lakes.append({
			"center": Vector2(center),
			"radius_x": rng.randf_range(lake_min_radius_tiles, lake_max_radius_tiles),
			"radius_y": rng.randf_range(lake_min_radius_tiles, lake_max_radius_tiles)
		})

	lake_region_cache[region] = lakes
	return lakes

func _pick_lake_center_in_region(region: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	var region_origin = Vector2i(region.x * lake_region_size_tiles, region.y * lake_region_size_tiles)

	for attempt in range(6):
		var center = region_origin + Vector2i(
			rng.randi_range(lake_forest_margin_tiles, lake_region_size_tiles - lake_forest_margin_tiles),
			rng.randi_range(lake_forest_margin_tiles, lake_region_size_tiles - lake_forest_margin_tiles)
		)

		if _is_forest_core_tile(center):
			return center

	return Vector2i(99999999, 99999999)

func _is_forest_core_tile(tile_coord: Vector2i) -> bool:
	var checks = [
		Vector2i.ZERO,
		Vector2i(lake_forest_margin_tiles, 0),
		Vector2i(-lake_forest_margin_tiles, 0),
		Vector2i(0, lake_forest_margin_tiles),
		Vector2i(0, -lake_forest_margin_tiles),
		Vector2i(lake_forest_margin_tiles, lake_forest_margin_tiles),
		Vector2i(-lake_forest_margin_tiles, -lake_forest_margin_tiles),
		Vector2i(lake_forest_margin_tiles, -lake_forest_margin_tiles),
		Vector2i(-lake_forest_margin_tiles, lake_forest_margin_tiles)
	]

	for offset in checks:
		if _calculate_land_biome_for_tile(tile_coord + offset) != BiomeType.FOREST:
			return false

	return true

func _is_river_tile(tile_coord: Vector2i) -> bool:
	var world_pos = tile_to_world_center(tile_coord)
	if world_pos.length() < spawn_water_safe_radius:
		return false

	var region = Vector2i(
		floori(float(tile_coord.x) / float(river_region_size_tiles)),
		floori(float(tile_coord.y) / float(river_region_size_tiles))
	)

	return _is_inside_river_region(world_pos, region)

func _is_inside_river_region(world_pos: Vector2, region: Vector2i) -> bool:
	var rivers = _get_rivers_for_region(region)

	for river in rivers:
		var points = river["points"]
		var width = river["width_tiles"] * tile_size

		for i in range(points.size()):
			var a = points[i]
			var b = points[(i + 1) % points.size()]
			if _distance_to_segment(world_pos, a, b) <= width:
				return true

	return false

func _get_rivers_for_region(region: Vector2i) -> Array:
	if river_region_cache.has(region):
		return river_region_cache[region]

	var rivers = []
	var rng = RandomNumberGenerator.new()
	rng.seed = _river_region_seed(region)

	if rng.randf() > river_chance_per_region:
		river_region_cache[region] = rivers
		return rivers

	var region_origin_tile = Vector2i(region.x * river_region_size_tiles, region.y * river_region_size_tiles)
	var center_tile = region_origin_tile + Vector2i(
		rng.randi_range(12, river_region_size_tiles - 12),
		rng.randi_range(12, river_region_size_tiles - 12)
	)

	var center_world = tile_to_world_center(center_tile)
	var radius_x = rng.randf_range(river_loop_radius_min_tiles, river_loop_radius_max_tiles) * tile_size
	var radius_y = rng.randf_range(river_loop_radius_min_tiles, river_loop_radius_max_tiles) * tile_size

	var points = []
	for i in range(river_path_points):
		var angle = TAU * float(i) / float(river_path_points)
		var wobble = rng.randf_range(0.65, 1.25)
		points.append(center_world + Vector2(cos(angle) * radius_x * wobble, sin(angle) * radius_y * wobble))

	rivers.append({
		"points": points,
		"width_tiles": rng.randf_range(river_min_width_tiles, river_max_width_tiles)
	})

	river_region_cache[region] = rivers
	return rivers

func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab = b - a
	var ab_len_sq = ab.length_squared()
	if ab_len_sq <= 0.001:
		return point.distance_to(a)

	var t = clamp((point - a).dot(ab) / ab_len_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)

func get_biome_at(world_pos: Vector2) -> BiomeType:
	var tile_coord = world_to_tile(world_pos)
	if biome_by_tile.has(tile_coord):
		return biome_by_tile[tile_coord]
	return _calculate_land_biome_for_tile(tile_coord)

func is_forest_at(world_pos: Vector2) -> bool:
	return get_biome_at(world_pos) == BiomeType.FOREST

func is_forest_tile_at(world_pos: Vector2) -> bool:
	return is_forest_at(world_pos)

func is_water_at(world_pos: Vector2) -> bool:
	var tile_coord = world_to_tile(world_pos)
	return biome_by_tile.has(tile_coord) and biome_by_tile[tile_coord] == BiomeType.WATER

func is_water_tile_at(world_pos: Vector2) -> bool:
	return is_water_at(world_pos)

func _lake_region_seed(region: Vector2i) -> int:
	var mixed = world_seed
	mixed = mixed ^ (region.x * 374761393)
	mixed = mixed ^ (region.y * 668265263)
	mixed = mixed ^ 1442695041
	return abs(mixed)

func _river_region_seed(region: Vector2i) -> int:
	var mixed = world_seed
	mixed = mixed ^ (region.x * 73856093)
	mixed = mixed ^ (region.y * 19349663)
	mixed = mixed ^ 83492791
	return abs(mixed)
