extends Node2D

@export var plains_tree_count = 150
@export var plains_min_distance = 350
@export var world_size = Vector2(16000, 16000)

var spawned_positions = []
var biome_callback: Callable = Callable()

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
	var top_left = Vector2(-world_size.x / 2, -world_size.y / 2)
	var bottom_right = Vector2(world_size.x / 2, world_size.y / 2)
	var scene_node = get_tree().root.get_node("Scene")

	var attempts = 0
	var max_attempts = plains_tree_count * 20
	var plains_spawned = 0
	while plains_spawned < plains_tree_count and attempts < max_attempts:
		attempts += 1
		var random_pos = Vector2(
			randf_range(top_left.x, bottom_right.x),
			randf_range(top_left.y, bottom_right.y)
		)
		if biome_callback.is_valid() and biome_callback.call(random_pos):
			continue
		if not is_safely_in_biome(random_pos, false):
			continue
		if is_position_valid(random_pos, plains_min_distance):
			spawned_positions.append(random_pos)
			scene_node.spawn_tree_with_id(random_pos)
			plains_spawned += 1

const BIOME_MARGIN: float = 200.0

func is_safely_in_biome(pos: Vector2, is_forest: bool) -> bool:
	if not biome_callback.is_valid():
		return true
	var offsets = [
		Vector2(BIOME_MARGIN, 0),
		Vector2(-BIOME_MARGIN, 0),
		Vector2(0, BIOME_MARGIN),
		Vector2(0, -BIOME_MARGIN)
	]
	for offset in offsets:
		var check = biome_callback.call(pos + offset)
		if is_forest and not check:
			return false
		if not is_forest and check:
			return false
	return true

func is_position_valid(pos: Vector2, distance: float) -> bool:
	for existing in spawned_positions:
		if pos.distance_to(existing) < distance:
			return false
	return true
