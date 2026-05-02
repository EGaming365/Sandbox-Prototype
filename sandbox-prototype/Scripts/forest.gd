extends Node2D

@export var tree_scene = preload("res://Scenes/tree.tscn")
@export var tree_count = 1000
@export var min_distance = 200
@export var forest_size = Vector2(1000, 1000)
var spawned_positions = []
var target_parent: Node

func _ready():
	target_parent = get_parent()
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		generate_forest()

func generate_forest():
	var top_left = global_position - forest_size / 2
	var bottom_right = global_position + forest_size / 2
	var attempts = 0
	var max_attempts = tree_count * 10
	while spawned_positions.size() < tree_count and attempts < max_attempts:
		attempts += 1
		var random_pos = Vector2(
			randf_range(top_left.x, bottom_right.x),
			randf_range(top_left.y, bottom_right.y)
		)
		if is_position_valid(random_pos):
			spawned_positions.append(random_pos)
			spawn_tree(random_pos)

func is_position_valid(pos):
	for existing in spawned_positions:
		if pos.distance_to(existing) < min_distance:
			return false
	return true

func spawn_tree(pos):
	var tree = tree_scene.instantiate()
	tree.position = pos
	target_parent.call_deferred("add_child", tree)

func sync_trees_to_client(peer_id: int):
	var flat: Array[float] = []
	for pos in spawned_positions:
		flat.append(pos.x)
		flat.append(pos.y)
	receive_tree_positions.rpc_id(peer_id, flat)

@rpc("authority", "call_remote", "reliable")
func receive_tree_positions(flat: Array[float]):
	# Clear existing trees first
	for child in target_parent.get_children():
		if child.is_in_group("trees"):
			child.queue_free()
	spawned_positions.clear()

	await get_tree().process_frame
	await get_tree().process_frame

	for i in range(0, flat.size(), 2):
		var pos = Vector2(flat[i], flat[i + 1])
		spawned_positions.append(pos)
		spawn_tree(pos)
