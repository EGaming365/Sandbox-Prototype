extends Node2D

@export var tile_size: int = 64
@export var biome_noise_frequency: float = 0.00007
@export var forest_threshold: float = 0.12
@export var world_seed: int = 0

@export var chunk_size_tiles: int = 24
@export var chunk_view_distance: int = 3
@export var chunk_unload_distance: int = 5
@export var chunk_update_interval: float = 0.25

enum BiomeType { PLAINS, FOREST }

var tilemap: TileMap
var noise: FastNoiseLite
var biome_by_tile: Dictionary = {}
var loaded_chunks: Dictionary = {}
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
	_ensure_noise_ready()
	biome_by_tile.clear()
	_clear_loaded_chunks()
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

func chunk_to_world_origin(chunk_coord: Vector2i) -> Vector2:
	return tile_to_world_center(chunk_to_start_tile(chunk_coord))

func is_chunk_loaded(chunk_coord: Vector2i) -> bool:
	return loaded_chunks.has(chunk_coord)

func _get_local_player():
	var scene_node = get_tree().root.get_node_or_null("Scene")
	if not scene_node:
		return null

	if scene_node.local_player:
		return scene_node.local_player

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
			if not loaded_chunks.has(chunk_coord):
				_paint_chunk(chunk_coord)

	var chunks_to_unload = []
	for chunk_coord in loaded_chunks.keys():
		var dx = abs(chunk_coord.x - player_chunk.x)
		var dy = abs(chunk_coord.y - player_chunk.y)
		if dx > chunk_unload_distance or dy > chunk_unload_distance:
			chunks_to_unload.append(chunk_coord)

	for chunk_coord in chunks_to_unload:
		_unload_chunk(chunk_coord)

func _paint_chunk(chunk_coord: Vector2i):
	loaded_chunks[chunk_coord] = true
	var start_tile = chunk_to_start_tile(chunk_coord)

	for x in range(chunk_size_tiles):
		for y in range(chunk_size_tiles):
			var tile_coord = Vector2i(start_tile.x + x, start_tile.y + y)
			var biome = _calculate_biome_for_tile(tile_coord)
			biome_by_tile[tile_coord] = biome

			if biome == BiomeType.FOREST:
				tilemap.set_cell(0, tile_coord, FOREST_SOURCE, FOREST_ATLAS)
			else:
				tilemap.set_cell(0, tile_coord, PLAINS_SOURCE, PLAINS_ATLAS)

func _unload_chunk(chunk_coord: Vector2i):
	loaded_chunks.erase(chunk_coord)
	var start_tile = chunk_to_start_tile(chunk_coord)

	for x in range(chunk_size_tiles):
		for y in range(chunk_size_tiles):
			var tile_coord = Vector2i(start_tile.x + x, start_tile.y + y)
			tilemap.erase_cell(0, tile_coord)
			biome_by_tile.erase(tile_coord)

func _clear_loaded_chunks():
	if not tilemap:
		return

	for chunk_coord in loaded_chunks.keys():
		_unload_chunk(chunk_coord)

	loaded_chunks.clear()

func _ensure_noise_ready():
	if noise != null:
		return

	noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = world_seed
	noise.frequency = biome_noise_frequency
	noise.fractal_octaves = 4

func _calculate_biome_for_tile(tile_coord: Vector2i) -> BiomeType:
	_ensure_noise_ready()

	var tile_center = tile_to_world_center(tile_coord)
	if noise.get_noise_2d(tile_center.x, tile_center.y) > forest_threshold:
		return BiomeType.FOREST

	return BiomeType.PLAINS

func get_biome_at(world_pos: Vector2) -> BiomeType:
	var tile_coord = world_to_tile(world_pos)

	if biome_by_tile.has(tile_coord):
		return biome_by_tile[tile_coord]

	return _calculate_biome_for_tile(tile_coord)

func is_forest_at(world_pos: Vector2) -> bool:
	return get_biome_at(world_pos) == BiomeType.FOREST

func is_forest_tile_at(world_pos: Vector2) -> bool:
	var tile_coord = world_to_tile(world_pos)

	if biome_by_tile.has(tile_coord):
		return biome_by_tile[tile_coord] == BiomeType.FOREST

	return _calculate_biome_for_tile(tile_coord) == BiomeType.FOREST
