extends Node2D

@export var world_half_size: int = 12000
@export var tile_size: int = 64
@export var biome_noise_frequency: float = 0.00007
@export var forest_threshold: float = 0.12

enum BiomeType { PLAINS, FOREST }

var tilemap: TileMap
var noise: FastNoiseLite
var biome_by_tile: Dictionary = {}

const PLAINS_SOURCE = 0
const PLAINS_ATLAS = Vector2i(2, 2)
const FOREST_SOURCE = 0
const FOREST_ATLAS = Vector2i(0, 0)

func _ready():
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		await get_tree().process_frame
		await get_tree().process_frame

		tilemap = get_tree().root.get_node_or_null("Scene/TileMap")
		if not tilemap:
			push_error("WorldGen: TileMap not found at Scene/TileMap")
			return

		_ensure_noise_ready()


		_paint_tilemap()
		_spawn_objects()

func _world_to_tile(world_pos: Vector2) -> Vector2i:
	if tilemap:
		return tilemap.local_to_map(tilemap.to_local(world_pos))
	return Vector2i(floori(world_pos.x / tile_size), floori(world_pos.y / tile_size))

func _tile_to_world_center(tile_coord: Vector2i) -> Vector2:
	if tilemap:
		return tilemap.to_global(tilemap.map_to_local(tile_coord))
	return Vector2((tile_coord.x + 0.5) * tile_size, (tile_coord.y + 0.5) * tile_size)


func _ensure_noise_ready():
	if noise != null:
		return

	noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = 12345
	noise.frequency = biome_noise_frequency
	noise.fractal_octaves = 4


func _calculate_biome_for_tile(tile_coord: Vector2i) -> BiomeType:
	_ensure_noise_ready()

	var tile_center = _tile_to_world_center(tile_coord)
	if noise.get_noise_2d(tile_center.x, tile_center.y) > forest_threshold:
		return BiomeType.FOREST
	return BiomeType.PLAINS


func get_biome_at(world_pos: Vector2) -> BiomeType:
	var tile_coord = _world_to_tile(world_pos)
	if biome_by_tile.has(tile_coord):
		return biome_by_tile[tile_coord]
	return _calculate_biome_for_tile(tile_coord)

func is_forest_at(world_pos: Vector2) -> bool:
	return get_biome_at(world_pos) == BiomeType.FOREST

func _paint_tilemap():
	biome_by_tile.clear()

	var tiles_per_side = int((world_half_size * 2) / tile_size)
	var start_tile = Vector2i(-world_half_size / tile_size, -world_half_size / tile_size)

	for x in range(tiles_per_side):
		for y in range(tiles_per_side):
			var tile_coord = Vector2i(start_tile.x + x, start_tile.y + y)
			var biome = _calculate_biome_for_tile(tile_coord)
			biome_by_tile[tile_coord] = biome

			if biome == BiomeType.FOREST:
				tilemap.set_cell(0, tile_coord, FOREST_SOURCE, FOREST_ATLAS)
			else:
				tilemap.set_cell(0, tile_coord, PLAINS_SOURCE, PLAINS_ATLAS)

func _spawn_objects():
	var forest_node = get_tree().root.get_node_or_null("Scene/Forest")
	var plains_node = get_tree().root.get_node_or_null("Scene/Plains")

	if forest_node:
		forest_node.world_size = Vector2(world_half_size * 2, world_half_size * 2)
		forest_node.set_biome_callback(func(pos: Vector2) -> bool:
			return is_forest_at(pos)
		)
		forest_node.generate_forest()

	if plains_node:
		plains_node.world_size = Vector2(world_half_size * 2, world_half_size * 2)
		plains_node.set_biome_callback(func(pos: Vector2) -> bool:
			return is_forest_at(pos)
		)
		plains_node.generate_plains()
