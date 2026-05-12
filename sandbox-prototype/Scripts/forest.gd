extends Node2D

@export var forest_tree_count = 1800
@export var rock_count = 250
@export var min_distance = 260
@export var world_size = Vector2(48000, 48000)

var spawned_positions = []
var biome_callback: Callable = Callable()

const EDGE_MARGIN: float = 128.0

func _ready():
	var world_gen = get_tree().root.get_node_or_null("Scene/WorldGen")
	if world_gen:
		return

	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		await get_tree().process_frame
		await get_tree().process_frame
		generate_forest()

func set_biome_callback(callback: Callable):
	biome_callback = callback

func generate_forest():
	spawned_positions.clear()

	var scene_node = get_tree().root.get_node("Scene")
	var top_left = Vector2(-world_size.x / 2, -world_size.y / 2)
	var bottom_right = Vector2(world_size.x / 2, world_size.y / 2)

	var tree_candidates = _get_grid_candidates(top_left, bottom_right, min_distance)
	var trees_spawned = 0

	for pos in tree_candidates:
		if trees_spawned >= forest_tree_count:
			break
		if not is_tree_inside_forest(pos):
			continue
		spawned_positions.append(pos)
		scene_node.spawn_tree_with_id(pos)
		trees_spawned += 1

	var rock_candidates = _get_grid_candidates(top_left, bottom_right, min_distance)
	var rocks_spawned = 0

	for pos in rock_candidates:
		if rocks_spawned >= rock_count:
			break
		if not is_rock_inside_forest(pos):
			continue
		if not is_position_valid(pos, min_distance):
			continue
		spawned_positions.append(pos)
		scene_node.spawn_rock_with_id(pos)
		rocks_spawned += 1

func _get_grid_candidates(top_left: Vector2, bottom_right: Vector2, spacing: float) -> Array:
	var candidates = []
	var y = top_left.y

	while y <= bottom_right.y:
		var x = top_left.x
		while x <= bottom_right.x:
			var jitter = Vector2(
				randf_range(-spacing * 0.25, spacing * 0.25),
				randf_range(-spacing * 0.25, spacing * 0.25)
			)
			candidates.append(Vector2(x, y) + jitter)
			x += spacing
		y += spacing

	candidates.shuffle()
	return candidates

func is_tree_inside_forest(pos: Vector2) -> bool:
	if not biome_callback.is_valid():
		return true

	var checks = [
		pos,
		pos + Vector2(0, -160),
		pos + Vector2(-160, -120),
		pos + Vector2(160, -120),
		pos + Vector2(-EDGE_MARGIN, 0),
		pos + Vector2(EDGE_MARGIN, 0),
		pos + Vector2(0, EDGE_MARGIN),
		pos + Vector2(0, -EDGE_MARGIN)
	]

	for check_pos in checks:
		if not biome_callback.call(check_pos):
			return false

	return true

func is_rock_inside_forest(pos: Vector2) -> bool:
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
		if not biome_callback.call(check_pos):
			return false

	return true

func is_position_valid(pos: Vector2, distance: float) -> bool:
	for existing in spawned_positions:
		if pos.distance_to(existing) < distance:
			return false
	return true
