extends Node2D

@export var world_half_size: int = 8000
@export var tile_size: int = 64

enum BiomeType { PLAINS, FOREST }

var tilemap: TileMap
var noise: FastNoiseLite

const PLAINS_SOURCE = 0
const PLAINS_ATLAS = Vector2i(2, 2)
const FOREST_SOURCE = 0
const FOREST_ATLAS = Vector2i(0, 0)
const TRANSITION_ATLAS = Vector2i(2, 2)

const FOREST_THRESHOLD: float = 0.1
const TRANSITION_RANGE: float = 0.15

func _ready():
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		await get_tree().process_frame
		await get_tree().process_frame
		tilemap = get_tree().root.get_node_or_null("Scene/TileMap")
		if not tilemap:
			push_error("WorldGen: TileMap not found at Scene/TileMap")
			return
		noise = FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.seed = randi()
		noise.frequency = 0.00015
		noise.fractal_octaves = 3
		_paint_tilemap()
		_spawn_objects()

func get_noise_at(world_pos: Vector2) -> float:
	return noise.get_noise_2d(world_pos.x, world_pos.y)

func get_biome_at(world_pos: Vector2) -> BiomeType:
	var n = get_noise_at(world_pos)
	if n > FOREST_THRESHOLD:
		return BiomeType.FOREST
	return BiomeType.PLAINS

func is_forest_at(pos: Vector2) -> bool:
	return get_biome_at(pos) == BiomeType.FOREST

func _paint_tilemap():
	var tiles_per_side_x = (world_half_size * 2) / tile_size
	var tiles_per_side_y = (world_half_size * 2) / tile_size
	var start_tile = Vector2i(-world_half_size / tile_size, -world_half_size / tile_size)
	for x in tiles_per_side_x:
		for y in tiles_per_side_y:
			var tile_coord = Vector2i(start_tile.x + x, start_tile.y + y)
			var world_pos = Vector2(tile_coord.x * tile_size, tile_coord.y * tile_size)
			var n = get_noise_at(world_pos)
			if n > FOREST_THRESHOLD + TRANSITION_RANGE:
				tilemap.set_cell(0, tile_coord, FOREST_SOURCE, FOREST_ATLAS)
			elif n > FOREST_THRESHOLD - TRANSITION_RANGE:
				tilemap.set_cell(0, tile_coord, PLAINS_SOURCE, TRANSITION_ATLAS)
			else:
				tilemap.set_cell(0, tile_coord, PLAINS_SOURCE, PLAINS_ATLAS)

func _spawn_objects():
	var forest_node = get_tree().root.get_node_or_null("Scene/Forest")
	var plains_node = get_tree().root.get_node_or_null("Scene/Plains")
	if forest_node:
		forest_node.set_biome_callback(func(pos: Vector2) -> bool:
			return get_biome_at(pos) == BiomeType.FOREST
		)
		forest_node.generate_forest()
	if plains_node:
		plains_node.set_biome_callback(func(pos: Vector2) -> bool:
			return get_biome_at(pos) == BiomeType.FOREST
		)
		plains_node.generate_plains()
