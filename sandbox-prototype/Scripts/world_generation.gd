extends Node2D

@export var tile_size: int = 64
@export var biome_noise_frequency: float = 0.00007
@export var forest_threshold: float = 0.08
@export var world_seed: int = 0

@export var chunk_size_tiles: int = 24
@export var chunk_view_distance: int = 3
@export var chunk_unload_distance: int = 5
@export var chunk_update_interval: float = 0.1

@export var tiles_per_frame: int = 80

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

const PLAINS_SOURCE := 0
const PLAINS_ATLAS  := Vector2i(2, 2)
const FOREST_SOURCE := 0
const FOREST_ATLAS  := Vector2i(0, 0)

var tilemap: TileMap
var noise: FastNoiseLite
var water_source_id: int = -1

var biome_by_tile: Dictionary = {}
var land_biome_cache: Dictionary = {}
var lake_region_cache: Dictionary = {}
var river_region_cache: Dictionary = {}

var loaded_chunks: Dictionary = {}
var pending_chunks: Array = []

var _paint_chunk: Vector2i = Vector2i(999999, 999999)
var _paint_index: int = 0
var _paint_tiles: Array = []

var chunk_update_timer: float = 0.0

func _ready():
	await get_tree().process_frame
	Loading_Screens.show_loading("Creating World", 4.0)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		if world_seed == 0:
			world_seed = randi()
		print("World seed: ", world_seed)

	generate_world()

func generate_world():
	tilemap = get_tree().root.get_node_or_null("Scene/TileMap")
	if not tilemap:
		push_error("WorldGen: TileMap not found at Scene/TileMap")
		return

	_find_water_source()
	_ensure_noise_ready()

	biome_by_tile.clear()
	land_biome_cache.clear()
	lake_region_cache.clear()
	river_region_cache.clear()
	loaded_chunks.clear()
	pending_chunks.clear()
	_paint_chunk = Vector2i(999999, 999999)
	_paint_index = 0
	_paint_tiles.clear()

	_update_chunks_around_player()

func set_world_settings(seed: int, synced_tile_size: int, frequency: float, threshold: float):
	world_seed = seed
	tile_size = synced_tile_size
	biome_noise_frequency = frequency
	forest_threshold = threshold
	generate_world()

func _process(delta):
	_paint_next_tiles()

	chunk_update_timer -= delta
	if chunk_update_timer > 0.0:
		return
	chunk_update_timer = chunk_update_interval
	_update_chunks_around_player()

func _get_local_player():
	var scene_node = get_tree().root.get_node_or_null("Scene")
	if not scene_node:
		return null
	var lp = scene_node.get("local_player")
	if lp and is_instance_valid(lp):
		return lp
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

	var player_tile  = world_to_tile(player.global_position)
	var player_chunk = tile_to_chunk(player_tile)

	var to_queue: Array = []
	for cx in range(player_chunk.x - chunk_view_distance, player_chunk.x + chunk_view_distance + 1):
		for cy in range(player_chunk.y - chunk_view_distance, player_chunk.y + chunk_view_distance + 1):
			var cc := Vector2i(cx, cy)
			if loaded_chunks.has(cc):
				continue
			if pending_chunks.has(cc):
				continue
			if _paint_chunk == cc:
				continue
			to_queue.append(cc)

	to_queue.sort_custom(func(a, b):
		return a.distance_squared_to(player_chunk) < b.distance_squared_to(player_chunk)
	)
	for cc in to_queue:
		pending_chunks.append(cc)

	var to_unload: Array = []
	for cc in loaded_chunks.keys():
		if abs(cc.x - player_chunk.x) > chunk_unload_distance or \
		   abs(cc.y - player_chunk.y) > chunk_unload_distance:
			to_unload.append(cc)
	for cc in to_unload:
		_unload_chunk(cc)

	pending_chunks = pending_chunks.filter(func(cc):
		return abs(cc.x - player_chunk.x) <= chunk_unload_distance and \
			   abs(cc.y - player_chunk.y) <= chunk_unload_distance
	)

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
		_apply_tile(entry[0], entry[1])
		_paint_index += 1
		painted += 1

func _precompute_chunk(chunk_coord: Vector2i):
	_paint_tiles.clear()
	var start = chunk_to_start_tile(chunk_coord)
	var total  = chunk_size_tiles * chunk_size_tiles
	_paint_tiles.resize(total)
	for i in total:
		var x: int = i % chunk_size_tiles
		var y: int = i / chunk_size_tiles
		var tc := Vector2i(start.x + x, start.y + y)
		var biome := _calculate_biome_for_tile(tc)
		biome_by_tile[tc] = biome
		_paint_tiles[i] = [tc, biome]

func _apply_tile(tile_coord: Vector2i, biome: BiomeType):
	match biome:
		BiomeType.WATER:
			if water_source_id == -1:
				tilemap.set_cell(0, tile_coord, PLAINS_SOURCE, PLAINS_ATLAS)
			else:
				tilemap.set_cell(0, tile_coord, water_source_id, water_atlas)
		BiomeType.FOREST:
			tilemap.set_cell(0, tile_coord, FOREST_SOURCE, FOREST_ATLAS)
		_:
			tilemap.set_cell(0, tile_coord, PLAINS_SOURCE, PLAINS_ATLAS)

func _unload_chunk(chunk_coord: Vector2i):
	pending_chunks.erase(chunk_coord)
	if _paint_chunk == chunk_coord:
		_paint_chunk = Vector2i(999999, 999999)
		_paint_index = 0
		_paint_tiles.clear()
	loaded_chunks.erase(chunk_coord)
	var start = chunk_to_start_tile(chunk_coord)
	for x in chunk_size_tiles:
		for y in chunk_size_tiles:
			var tc := Vector2i(start.x + x, start.y + y)
			tilemap.erase_cell(0, tc)
			biome_by_tile.erase(tc)
			land_biome_cache.erase(tc)

func _calculate_biome_for_tile(tile_coord: Vector2i) -> BiomeType:
	var land = _calculate_land_biome_for_tile(tile_coord)
	if land == BiomeType.FOREST and _is_forest_lake_tile(tile_coord):
		return BiomeType.WATER
	if land == BiomeType.PLAINS and _is_river_tile(tile_coord):
		return BiomeType.WATER
	return land

func _calculate_land_biome_for_tile(tile_coord: Vector2i) -> BiomeType:
	if land_biome_cache.has(tile_coord):
		return land_biome_cache[tile_coord]
	_ensure_noise_ready()
	var center := tile_to_world_center(tile_coord)
	var result := BiomeType.PLAINS
	if noise.get_noise_2d(center.x, center.y) > forest_threshold:
		result = BiomeType.FOREST
	land_biome_cache[tile_coord] = result
	return result

func _is_forest_lake_tile(tile_coord: Vector2i) -> bool:
	if tile_to_world_center(tile_coord).length() < spawn_water_safe_radius:
		return false
	var region := Vector2i(
		floori(float(tile_coord.x) / float(lake_region_size_tiles)),
		floori(float(tile_coord.y) / float(lake_region_size_tiles))
	)
	return _is_inside_lake_region(tile_coord, region)

func _is_inside_lake_region(tile_coord: Vector2i, region: Vector2i) -> bool:
	for lake in _get_lakes_for_region(region):
		var offset: Vector2 = Vector2(tile_coord) - lake["center"]
		var rx: float = lake["radius_x"]
		var ry: float = lake["radius_y"]
		if (offset.x * offset.x) / (rx * rx) + (offset.y * offset.y) / (ry * ry) <= 1.0:
			return true
	return false

func _get_lakes_for_region(region: Vector2i) -> Array:
	if lake_region_cache.has(region):
		return lake_region_cache[region]
	var lakes := []
	var rng := RandomNumberGenerator.new()
	rng.seed = _lake_region_seed(region)
	if rng.randf() <= lake_chance_per_region:
		var count := 2 if rng.randf() < lake_second_chance else 1
		for i in count:
			var center := _pick_lake_center_in_region(region, rng)
			if center != Vector2i(99999999, 99999999):
				lakes.append({
					"center":   Vector2(center),
					"radius_x": rng.randf_range(lake_min_radius_tiles, lake_max_radius_tiles),
					"radius_y": rng.randf_range(lake_min_radius_tiles, lake_max_radius_tiles)
				})
	lake_region_cache[region] = lakes
	return lakes

func _pick_lake_center_in_region(region: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	var origin := Vector2i(region.x * lake_region_size_tiles, region.y * lake_region_size_tiles)
	for _attempt in 6:
		var center := origin + Vector2i(
			rng.randi_range(lake_forest_margin_tiles, lake_region_size_tiles - lake_forest_margin_tiles),
			rng.randi_range(lake_forest_margin_tiles, lake_region_size_tiles - lake_forest_margin_tiles)
		)
		if _is_forest_core_tile(center):
			return center
	return Vector2i(99999999, 99999999)

func _is_forest_core_tile(tile_coord: Vector2i) -> bool:
	var m := lake_forest_margin_tiles
	for offset in [Vector2i(0,0), Vector2i(m,0), Vector2i(-m,0), Vector2i(0,m), Vector2i(0,-m),
				   Vector2i(m,m), Vector2i(-m,-m), Vector2i(m,-m), Vector2i(-m,m)]:
		if _calculate_land_biome_for_tile(tile_coord + offset) != BiomeType.FOREST:
			return false
	return true

func _is_river_tile(tile_coord: Vector2i) -> bool:
	if tile_to_world_center(tile_coord).length() < spawn_water_safe_radius:
		return false
	var region := Vector2i(
		floori(float(tile_coord.x) / float(river_region_size_tiles)),
		floori(float(tile_coord.y) / float(river_region_size_tiles))
	)
	return _is_inside_river_region(tile_to_world_center(tile_coord), region)

func _is_inside_river_region(world_pos: Vector2, region: Vector2i) -> bool:
	for river in _get_rivers_for_region(region):
		var pts: Array = river["points"]
		var width: float = river["width_tiles"] * tile_size
		for i in pts.size():
			if _distance_to_segment(world_pos, pts[i], pts[(i + 1) % pts.size()]) <= width:
				return true
	return false

func _get_rivers_for_region(region: Vector2i) -> Array:
	if river_region_cache.has(region):
		return river_region_cache[region]
	var rivers := []
	var rng := RandomNumberGenerator.new()
	rng.seed = _river_region_seed(region)
	if rng.randf() <= river_chance_per_region:
		var origin_tile := Vector2i(region.x * river_region_size_tiles, region.y * river_region_size_tiles)
		var center_tile := origin_tile + Vector2i(
			rng.randi_range(12, river_region_size_tiles - 12),
			rng.randi_range(12, river_region_size_tiles - 12)
		)
		var cw := tile_to_world_center(center_tile)
		var rx := rng.randf_range(river_loop_radius_min_tiles, river_loop_radius_max_tiles) * tile_size
		var ry := rng.randf_range(river_loop_radius_min_tiles, river_loop_radius_max_tiles) * tile_size
		var pts := []
		for i in river_path_points:
			var angle := TAU * float(i) / float(river_path_points)
			var wobble := rng.randf_range(0.65, 1.25)
			pts.append(cw + Vector2(cos(angle) * rx * wobble, sin(angle) * ry * wobble))
		rivers.append({"points": pts, "width_tiles": rng.randf_range(river_min_width_tiles, river_max_width_tiles)})
	river_region_cache[region] = rivers
	return rivers

func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq <= 0.001:
		return point.distance_to(a)
	var t: float = clamp((point - a).dot(ab) / len_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)

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

func _ensure_noise_ready():
	noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = world_seed
	noise.frequency = biome_noise_frequency
	noise.fractal_octaves = 4

func _find_water_source():
	water_source_id = -1
	if not tilemap or not tilemap.tile_set:
		return
	var ts := tilemap.tile_set
	var wanted := water_source_name.strip_edges().to_lower()
	for i in ts.get_source_count():
		var sid := ts.get_source_id(i)
		var src := ts.get_source(sid)
		if src and src.resource_name.strip_edges().to_lower() == wanted:
			water_source_id = sid
			return
	for i in ts.get_source_count():
		if ts.get_source_id(i) == water_source_fallback_id:
			water_source_id = water_source_fallback_id
			return
	push_warning("WorldGen: water tile source '%s' not found." % water_source_name)

func get_biome_at(world_pos: Vector2) -> BiomeType:
	var tc := world_to_tile(world_pos)
	if biome_by_tile.has(tc):
		return biome_by_tile[tc]
	return _calculate_land_biome_for_tile(tc)

func is_forest_at(world_pos: Vector2) -> bool:
	return get_biome_at(world_pos) == BiomeType.FOREST

func is_forest_tile_at(world_pos: Vector2) -> bool:
	return is_forest_at(world_pos)

func is_water_at(world_pos: Vector2) -> bool:
	var tc := world_to_tile(world_pos)
	return biome_by_tile.has(tc) and biome_by_tile[tc] == BiomeType.WATER

func is_water_tile_at(world_pos: Vector2) -> bool:
	return is_water_at(world_pos)

func _lake_region_seed(region: Vector2i) -> int:
	var m := world_seed ^ (region.x * 374761393) ^ (region.y * 668265263) ^ 1442695041
	return abs(m)

func _river_region_seed(region: Vector2i) -> int:
	var m := world_seed ^ (region.x * 73856093) ^ (region.y * 19349663) ^ 83492791
	return abs(m)
