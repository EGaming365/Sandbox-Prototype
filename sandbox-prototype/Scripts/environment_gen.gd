extends Node2D

@export var tree_scene_path: String = "res://Scenes/tree.tscn"
@export var rock_scene_path: String = "res://Scenes/rock.tscn"

@export var render_distance_chunks: int = 2
@export var unload_distance_chunks: int = 4
@export var update_interval: float = 0.5
@export var objects_spawned_per_frame: int = 3
@export var water_clearance_radius: float = 140.0

@export var forest_trees_per_chunk: float = 16.0
@export var forest_rocks_per_chunk: float = 0.25
@export var plains_trees_per_chunk: float = 2.0
@export var plains_rocks_per_chunk: float = 0.0

@export var forest_tree_min_distance: float = 230.0
@export var plains_tree_min_distance: float = 850.0
@export var rock_min_distance: float = 260.0
@export var biome_edge_check_radius: float = 200.0
@export var max_spawn_attempts_per_object: int = 30

var scene_node: Node
var world_gen: Node
var local_player: CharacterBody2D

var world_seed: int = 0
var update_timer: float = 0.0

var loaded_chunks: Dictionary = {}
var chunk_objects: Dictionary = {}
var active_objects: Dictionary = {}
var object_positions_by_chunk: Dictionary = {}

var destroyed_env_objects: Dictionary = {}
var env_object_hits: Dictionary = {}

var _chunk_load_queue: Array = []
var _object_spawn_queue: Array = []
var _packed_tree_scene: PackedScene = null
var _packed_rock_scene: PackedScene = null

func _ready():
	scene_node = get_tree().root.get_node_or_null("Scene")
	world_gen = get_tree().root.get_node_or_null("Scene/WorldGen")
	_packed_tree_scene = load(tree_scene_path)
	_packed_rock_scene = load(rock_scene_path)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	if world_gen and world_gen.get("world_seed") != null:
		world_seed = world_gen.world_seed

func _process(delta):
	_process_load_queue()
	_process_object_spawn_queue()

	update_timer -= delta
	if update_timer > 0.0:
		return

	update_timer = update_interval

	if not _refresh_references():
		return

	_update_chunks_around_player()

func _process_load_queue():
	if _chunk_load_queue.is_empty():
		return

	var chunk_coord = _chunk_load_queue.pop_front()
	if not loaded_chunks.has(chunk_coord):
		_load_chunk(chunk_coord)

func _process_object_spawn_queue():
	var spawned_this_frame := 0

	while spawned_this_frame < objects_spawned_per_frame and not _object_spawn_queue.is_empty():
		var job = _object_spawn_queue.pop_front()
		var chunk_coord: Vector2i = job["chunk_coord"]
		var env_id: String = job["env_id"]

		if not loaded_chunks.has(chunk_coord):
			continue
		if destroyed_env_objects.has(env_id):
			continue
		if active_objects.has(env_id):
			continue

		_spawn_object(env_id, job["kind"], job["pos"], chunk_coord)
		spawned_this_frame += 1

func _refresh_references() -> bool:
	if not scene_node:
		scene_node = get_tree().root.get_node_or_null("Scene")
	if not world_gen:
		world_gen = get_tree().root.get_node_or_null("Scene/WorldGen")

	if not scene_node or not world_gen:
		return false

	local_player = null
	for child in scene_node.get_children():
		if child is CharacterBody2D:
			if not multiplayer.has_multiplayer_peer() or child.is_multiplayer_authority():
				local_player = child
				break

	return local_player != null

func set_world_seed(seed: int):
	world_seed = seed
	_unload_all_chunks()

func apply_env_state(destroyed: Dictionary, hits: Dictionary):
	destroyed_env_objects = destroyed.duplicate(true)
	env_object_hits = hits.duplicate(true)

	for env_id in destroyed_env_objects.keys():
		_despawn_object(env_id)

	for env_id in env_object_hits.keys():
		set_object_hits(env_id, env_object_hits[env_id])

func mark_destroyed(env_id: String):
	destroyed_env_objects[env_id] = true
	_despawn_object(env_id)

func set_object_hits(env_id: String, hits: int):
	env_object_hits[env_id] = hits

	if active_objects.has(env_id):
		var obj = active_objects[env_id]
		if is_instance_valid(obj) and _has_property(obj, "hits"):
			obj.hits = hits

func _update_chunks_around_player():
	var player_tile = world_gen.world_to_tile(local_player.global_position)
	var center_chunk = world_gen.tile_to_chunk(player_tile)

	for x in range(center_chunk.x - render_distance_chunks, center_chunk.x + render_distance_chunks + 1):
		for y in range(center_chunk.y - render_distance_chunks, center_chunk.y + render_distance_chunks + 1):
			var chunk_coord = Vector2i(x, y)
			if not loaded_chunks.has(chunk_coord) and not _chunk_load_queue.has(chunk_coord):
				_chunk_load_queue.append(chunk_coord)

	var chunks_to_unload: Array = []
	for chunk_coord in loaded_chunks.keys():
		var dist_x = abs(chunk_coord.x - center_chunk.x)
		var dist_y = abs(chunk_coord.y - center_chunk.y)
		if dist_x > unload_distance_chunks or dist_y > unload_distance_chunks:
			chunks_to_unload.append(chunk_coord)

	for chunk_coord in chunks_to_unload:
		_unload_chunk(chunk_coord)
		_chunk_load_queue.erase(chunk_coord)

func _load_chunk(chunk_coord: Vector2i):
	if loaded_chunks.has(chunk_coord):
		return

	if world_gen.has_method("is_chunk_loaded"):
		if not world_gen.is_chunk_loaded(chunk_coord):
			return

	loaded_chunks[chunk_coord] = true
	chunk_objects[chunk_coord] = []
	object_positions_by_chunk[chunk_coord] = []

	_queue_chunk_objects(chunk_coord)

func _unload_chunk(chunk_coord: Vector2i):
	if chunk_objects.has(chunk_coord):
		for env_id in chunk_objects[chunk_coord]:
			_despawn_object(env_id)

	for i in range(_object_spawn_queue.size() - 1, -1, -1):
		if _object_spawn_queue[i]["chunk_coord"] == chunk_coord:
			_object_spawn_queue.remove_at(i)

	chunk_objects.erase(chunk_coord)
	object_positions_by_chunk.erase(chunk_coord)
	loaded_chunks.erase(chunk_coord)

func _unload_all_chunks():
	_chunk_load_queue.clear()
	_object_spawn_queue.clear()

	for chunk_coord in loaded_chunks.keys():
		_unload_chunk(chunk_coord)

	loaded_chunks.clear()
	chunk_objects.clear()
	object_positions_by_chunk.clear()
	active_objects.clear()

func _queue_chunk_objects(chunk_coord: Vector2i):
	_queue_kind_in_chunk(chunk_coord, "rock", true, forest_rocks_per_chunk, rock_min_distance)
	_queue_kind_in_chunk(chunk_coord, "rock", false, plains_rocks_per_chunk, rock_min_distance)
	_queue_kind_in_chunk(chunk_coord, "tree", true, forest_trees_per_chunk, forest_tree_min_distance)
	_queue_kind_in_chunk(chunk_coord, "tree", false, plains_trees_per_chunk, plains_tree_min_distance)

func _queue_kind_in_chunk(chunk_coord: Vector2i, kind: String, wants_forest: bool, count: float, min_distance: float):
	if count <= 0.0:
		return

	var rng = RandomNumberGenerator.new()
	rng.seed = _chunk_seed(chunk_coord, kind, wants_forest)

	var actual_count: int
	if count < 1.0:
		if rng.randf() < count:
			actual_count = 1
		else:
			return
	else:
		actual_count = int(count)

	var bounds = _get_chunk_world_bounds(chunk_coord)
	var world_min: Vector2 = bounds[0]
	var world_max: Vector2 = bounds[1]

	var spawned := 0
	var attempts := 0
	var max_attempts := actual_count * max_spawn_attempts_per_object

	while spawned < actual_count and attempts < max_attempts:
		attempts += 1

		var pos = Vector2(
			rng.randf_range(world_min.x, world_max.x),
			rng.randf_range(world_min.y, world_max.y)
		)

		if not _is_safely_in_biome(pos, wants_forest):
			continue

		if not _passes_distance_rule(chunk_coord, pos, min_distance):
			continue

		var env_id = _make_env_id(kind, chunk_coord, spawned)

		if destroyed_env_objects.has(env_id):
			spawned += 1
			continue

		_object_spawn_queue.append({
			"env_id": env_id,
			"kind": kind,
			"pos": pos,
			"chunk_coord": chunk_coord
		})

		chunk_objects[chunk_coord].append(env_id)
		object_positions_by_chunk[chunk_coord].append(pos)
		spawned += 1

func _spawn_object(env_id: String, kind: String, pos: Vector2, chunk_coord: Vector2i):
	if active_objects.has(env_id):
		return

	var packed_scene: PackedScene
	if kind == "rock":
		packed_scene = _packed_rock_scene
	else:
		packed_scene = _packed_tree_scene

	if packed_scene == null:
		return

	var obj = packed_scene.instantiate()
	obj.global_position = pos
	obj.set_meta("env_id", env_id)

	if _has_property(obj, "env_id"):
		obj.env_id = env_id

	if kind == "tree" and _has_property(obj, "tree_id"):
		obj.tree_id = hash(env_id)

	if kind == "rock" and _has_property(obj, "rock_id"):
		obj.rock_id = hash(env_id)

	if env_object_hits.has(env_id) and _has_property(obj, "hits"):
		obj.hits = env_object_hits[env_id]

	scene_node.add_child(obj)
	active_objects[env_id] = obj

func _despawn_object(env_id: String):
	if not active_objects.has(env_id):
		return

	var obj = active_objects[env_id]
	if is_instance_valid(obj):
		obj.queue_free()

	active_objects.erase(env_id)

func _passes_distance_rule(chunk_coord: Vector2i, pos: Vector2, min_distance: float) -> bool:
	var chunks_to_check = [
		chunk_coord,
		chunk_coord + Vector2i(1, 0),
		chunk_coord + Vector2i(-1, 0),
		chunk_coord + Vector2i(0, 1),
		chunk_coord + Vector2i(0, -1),
		chunk_coord + Vector2i(1, 1),
		chunk_coord + Vector2i(-1, -1),
		chunk_coord + Vector2i(1, -1),
		chunk_coord + Vector2i(-1, 1)
	]

	for check_chunk in chunks_to_check:
		if not object_positions_by_chunk.has(check_chunk):
			continue

		for other_pos in object_positions_by_chunk[check_chunk]:
			if pos.distance_to(other_pos) < min_distance:
				return false

	return true

func _is_safely_in_biome(pos: Vector2, wants_forest: bool) -> bool:
	if _is_water_near(pos):
		return false

	var offsets = [
		Vector2.ZERO,
		Vector2(biome_edge_check_radius, 0),
		Vector2(-biome_edge_check_radius, 0),
		Vector2(0, biome_edge_check_radius),
		Vector2(0, -biome_edge_check_radius)
	]

	for offset in offsets:
		if _is_forest_at(pos + offset) != wants_forest:
			return false

	return true

func _is_water_near(pos: Vector2) -> bool:
	if not world_gen:
		return false

	var checks = [
		Vector2.ZERO,
		Vector2(water_clearance_radius, 0),
		Vector2(-water_clearance_radius, 0),
		Vector2(0, water_clearance_radius),
		Vector2(0, -water_clearance_radius),
		Vector2(water_clearance_radius * 0.7, water_clearance_radius * 0.7),
		Vector2(-water_clearance_radius * 0.7, water_clearance_radius * 0.7),
		Vector2(water_clearance_radius * 0.7, -water_clearance_radius * 0.7),
		Vector2(-water_clearance_radius * 0.7, -water_clearance_radius * 0.7)
	]

	for offset in checks:
		var check_pos = pos + offset
		if world_gen.has_method("is_water_tile_at") and world_gen.is_water_tile_at(check_pos):
			return true
		if world_gen.has_method("is_water_at") and world_gen.is_water_at(check_pos):
			return true

	return false

func _is_forest_at(pos: Vector2) -> bool:
	if world_gen.has_method("is_forest_tile_at"):
		return world_gen.is_forest_tile_at(pos)
	if world_gen.has_method("is_forest_at"):
		return world_gen.is_forest_at(pos)
	return false

func _get_chunk_world_bounds(chunk_coord: Vector2i) -> Array:
	var start_tile: Vector2i = world_gen.chunk_to_start_tile(chunk_coord)
	var chunk_size: int = world_gen.chunk_size_tiles
	var ts: int = world_gen.tile_size
	var end_tile = start_tile + Vector2i(chunk_size - 1, chunk_size - 1)

	var world_min = world_gen.tile_to_world_center(start_tile) - Vector2(ts * 0.5, ts * 0.5)
	var world_max = world_gen.tile_to_world_center(end_tile) + Vector2(ts * 0.5, ts * 0.5)

	return [world_min, world_max]

func _chunk_seed(chunk_coord: Vector2i, kind: String, wants_forest: bool) -> int:
	var biome_key := 0
	if wants_forest:
		biome_key = 1

	var kind_key := 0
	if kind == "rock":
		kind_key = 7
	elif kind == "tree":
		kind_key = 13

	var mixed = world_seed ^ (chunk_coord.x * 374761393) ^ (chunk_coord.y * 1234567891) ^ (kind_key * 7919) ^ (biome_key * 104729)
	return abs(mixed)

func _make_env_id(kind: String, chunk_coord: Vector2i, index: int) -> String:
	return kind + ":" + str(chunk_coord.x) + ":" + str(chunk_coord.y) + ":" + str(index)

func _has_property(obj: Object, property_name: String) -> bool:
	for prop in obj.get_property_list():
		if prop.name == property_name:
			return true
	return false
