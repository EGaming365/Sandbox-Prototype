extends Node2D

@export var plains_tree_count = 900
@export var plains_min_distance = 500
@export var world_size = Vector2(128000, 128000)

var spawned_positions = []
var biome_callback: Callable = Callable()

const EDGE_MARGIN: float = 256.0

func _ready():
	var world_gen = get_tree().root.get_node_or_null("Scene/WorldGen")
	if world_gen:
		return

	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		await get_tree().process_frame
		await get_tree().process_frame
		generate_plains()

func set_biome_callback(callback: Callable):
	biome_callback = callback

func generate_plains():
	spawned_positions.clear()

	var top_left = Vector2(-world_size.x / 2, -world_size.y / 2)
	var bottom_right = Vector2(world_size.x / 2, world_size.y / 2)
	var scene_node = get_tree().root.get_node("Scene")

	var plains_spawned = 0
	var attempts = 0
	var max_attempts = plains_tree_count * 80

	while plains_spawned < plains_tree_count and attempts < max_attempts:
		attempts += 1
		var random_pos = Vector2(
			randf_range(top_left.x, bottom_right.x),
			randf_range(top_left.y, bottom_right.y)
		)

		if not is_safely_in_plains(random_pos):
			continue

		if is_position_valid(random_pos, plains_min_distance):
			spawned_positions.append(random_pos)
			scene_node.spawn_tree_with_id(random_pos)
			plains_spawned += 1

func is_safely_in_plains(pos: Vector2) -> bool:
	if not biome_callback.is_valid():
		return true

	var checks = [
		pos,
		pos + Vector2(-EDGE_MARGIN, 0),
		pos + Vector2(EDGE_MARGIN, 0),
		pos + Vector2(0, -EDGE_MARGIN),
		pos + Vector2(0, EDGE_MARGIN)
	]

	for check_pos in checks:
		if biome_callback.call(check_pos):
			return false

	return true

func is_position_valid(pos: Vector2, distance: float) -> bool:
	for existing in spawned_positions:
		if pos.distance_to(existing) < distance:
			return false
	return true
