extends Node2D

@export var tree_count = 1000
@export var min_distance = 200
@export var forest_size = Vector2(1000, 1000)
var spawned_positions = []
var target_parent: Node

func _ready():
	target_parent = get_parent()
	# Only generate if singleplayer OR we are already the host
	# If we're a client or about to become one, do nothing — wait for sync
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		await get_tree().process_frame
		await get_tree().process_frame
		generate_forest()

func generate_forest():
	var top_left = global_position - forest_size / 2
	var bottom_right = global_position + forest_size / 2
	var attempts = 0
	var max_attempts = tree_count * 10
	var scene_node = get_tree().root.get_node("Scene")
	while spawned_positions.size() < tree_count and attempts < max_attempts:
		attempts += 1
		var random_pos = Vector2(
			randf_range(top_left.x, bottom_right.x),
			randf_range(top_left.y, bottom_right.y)
		)
		if is_position_valid(random_pos):
			spawned_positions.append(random_pos)
			scene_node.spawn_tree_with_id(random_pos)

func is_position_valid(pos):
	for existing in spawned_positions:
		if pos.distance_to(existing) < min_distance:
			return false
	return true
