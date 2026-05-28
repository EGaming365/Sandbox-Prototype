extends Node2D

@export var tree_scene_path: String = "res://Scenes/tree.tscn"
@export var rock_scene_path: String = "res://Scenes/rock.tscn"
@export var cave_scene_path: String = "res://Scenes/cave.tscn"

@export var render_distance_chunks: int = 3
@export var unload_distance_chunks: int = 4
@export var update_interval: float = 0.15
@export var objects_spawned_per_frame: int = 8
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

@export var grass_count_per_chunk: int = 64
@export var grass_min_scale: float = 2.0
@export var grass_max_scale: float = 3.0
@export var grass_min_rotation: float = -0.2
@export var grass_max_rotation: float = 0.2
@export var grass_color_r_min: float = 0.85
@export var grass_color_g_min: float = 0.90
@export var grass_color_b_min: float = 0.80
@export var grass_min_distance: float = 60.0

@export var cave_region_size_tiles: int = 64
@export var cave_chance_per_region: float = 0.30
@export var cave_spawn_safe_radius: float = 900.0

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

var _chunk_build_queue: Array = []
var _building_chunk: Vector2i = Vector2i(999999, 999999)
var _build_jobs: Array = []
var _build_kind_index: int = 0

var _biome_cache: Dictionary = {}

var _build_kinds: Array = [
	{ "kind": "rock",  "forest": true,  "count": 0.0, "min_dist": 0.0 },
	{ "kind": "rock",  "forest": false, "count": 0.0, "min_dist": 0.0 },
	{ "kind": "tree",  "forest": true,  "count": 0.0, "min_dist": 0.0 },
	{ "kind": "tree",  "forest": false, "count": 0.0, "min_dist": 0.0 },
	{ "kind": "grass", "forest": false, "count": 0.0, "min_dist": 0.0 },
]

var _packed_tree_scene: PackedScene = null
var _packed_rock_scene: PackedScene = null
var _packed_cave_scene: PackedScene = null

var _grass_textures: Array = []
var _grass_nodes: Dictionary = {}

var _world_state_received: bool = false

var _loaded_cave_regions: Dictionary = {}
var _active_caves: Dictionary = {}
var _cave_positions: Dictionary = {}
var _cave_region_load_queue: Array = []

const _BIOME_CELL: float = 24.0
const _MAX_BIOME_QUERIES_PER_FRAME: int = 200

var _biome_queries_this_frame: int = 0

func _ready():
	scene_node = get_tree().root.get_node_or_null("Scene")
	world_gen   = get_tree().root.get_node_or_null("Scene/WorldGen")
	_packed_tree_scene = load(tree_scene_path)
	_packed_rock_scene = load(rock_scene_path)
	_packed_cave_scene = load(cave_scene_path)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if world_gen and world_gen.get("world_seed") != null:
		world_seed = world_gen.world_seed
	for i in range(1, 9):
		var tex = load("res://Assets/Grass" + str(i) + ".png")
		if tex:
			_grass_textures.append(tex)

func _process(delta):
	_process_load_queue_step()
	_step_chunk_build()
	_process_object_spawn_queue()

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		if not _world_state_received:
			return

	update_timer -= delta
	if update_timer > 0.0:
		return
	update_timer = update_interval
	if not _refresh_references():
		return

	var cave_world_gen = get_tree().root.get_node_or_null("Scene/CaveWorldGen")
	if cave_world_gen and cave_world_gen.get("in_cave"):
		return

	_update_chunks_around_player()
	_update_cave_regions()

func _process_load_queue_step():
	if _chunk_load_queue.is_empty():
		return
	var chunk_coord: Vector2i = _chunk_load_queue[0]
	if not loaded_chunks.has(chunk_coord):
		_load_chunk(chunk_coord)
	if not _chunk_load_queue.is_empty() and _chunk_load_queue[0] == chunk_coord:
		_chunk_load_queue.pop_front()

func _start_chunk_build(chunk_coord: Vector2i):
	_building_chunk = chunk_coord
	_build_jobs.clear()
	_build_kind_index = 0
	_biome_cache.clear()
	_build_kinds = [
		{ "kind": "rock",  "forest": true,  "count": forest_rocks_per_chunk,  "min_dist": rock_min_distance },
		{ "kind": "rock",  "forest": false, "count": plains_rocks_per_chunk,  "min_dist": rock_min_distance },
		{ "kind": "tree",  "forest": true,  "count": forest_trees_per_chunk,  "min_dist": forest_tree_min_distance },
		{ "kind": "tree",  "forest": false, "count": plains_trees_per_chunk,  "min_dist": plains_tree_min_distance },
		{ "kind": "grass", "forest": false, "count": float(grass_count_per_chunk), "min_dist": 0.0 },
	]

func _step_chunk_build():
	_biome_queries_this_frame = 0

	if _building_chunk == Vector2i(999999, 999999):
		if _chunk_build_queue.is_empty():
			return
		var next: Vector2i = _chunk_build_queue.pop_front()
		if not loaded_chunks.has(next):
			return
		_start_chunk_build(next)

	if _build_kind_index >= _build_kinds.size():
		for job in _build_jobs:
			_object_spawn_queue.append(job)
		_building_chunk = Vector2i(999999, 999999)
		_build_jobs.clear()
		_biome_cache.clear()
		return

	var pass_def = _build_kinds[_build_kind_index]
	_build_kind_index += 1
	var chunk_coord := _building_chunk

	if pass_def["kind"] == "grass":
		_build_grass_pass(chunk_coord)
		return

	_build_object_pass(chunk_coord, pass_def["kind"], pass_def["forest"], pass_def["count"], pass_def["min_dist"])

func _build_object_pass(chunk_coord: Vector2i, kind: String, wants_forest: bool, count: float, min_dist: float):
	if count <= 0.0:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = _chunk_seed(chunk_coord, kind, wants_forest)

	var actual_count: int
	if count < 1.0:
		actual_count = 1 if rng.randf() < count else 0
		if actual_count == 0:
			return
	else:
		actual_count = int(count)

	var bounds := _get_chunk_world_bounds(chunk_coord)
	var world_min: Vector2 = bounds[0]
	var world_max: Vector2 = bounds[1]

	var spawned := 0
	var attempts := 0
	var max_attempts := actual_count * max_spawn_attempts_per_object

	while spawned < actual_count and attempts < max_attempts:
		attempts += 1
		var pos := Vector2(
			rng.randf_range(world_min.x, world_max.x),
			rng.randf_range(world_min.y, world_max.y)
		)

		if _biome_queries_this_frame >= _MAX_BIOME_QUERIES_PER_FRAME:
			_build_kind_index -= 1
			break
		if not _is_valid_object_position(pos, wants_forest):
			continue
		if _is_too_close_to_cave(pos):
			continue
		if not _passes_distance_rule(chunk_coord, pos, min_dist):
			continue

		var env_id := _make_env_id(kind, chunk_coord, spawned)
		chunk_objects[chunk_coord].append(env_id)
		object_positions_by_chunk[chunk_coord].append(pos)

		if not destroyed_env_objects.has(env_id):
			_build_jobs.append({ "env_id": env_id, "kind": kind, "pos": pos, "chunk_coord": chunk_coord })

		spawned += 1

func _is_valid_object_position(pos: Vector2, wants_forest: bool) -> bool:
	if _is_water_cached(pos):
		return false
	var r := biome_edge_check_radius
	var offsets := [
		Vector2.ZERO,
		Vector2(r, 0), Vector2(-r, 0),
		Vector2(0, r), Vector2(0, -r),
	]
	for offset in offsets:
		var check: Vector2i = pos + offset
		if _is_water_cached(check):
			return false
		if _is_forest_cached(check) != wants_forest:
			return false
	return true

func _build_grass_pass(chunk_coord: Vector2i):
	if _grass_textures.is_empty():
		return
	if _grass_nodes.has(chunk_coord):
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = _chunk_seed(chunk_coord, "grass", false)

	var bounds := _get_chunk_world_bounds(chunk_coord)
	var world_min: Vector2 = bounds[0]
	var world_max: Vector2 = bounds[1]

	var blades: Array = []
	var placed_positions: Array = []
	var attempts := 0
	var max_attempts := grass_count_per_chunk * max_spawn_attempts_per_object

	while placed_positions.size() < grass_count_per_chunk and attempts < max_attempts:
		attempts += 1
		var pos := Vector2(
			rng.randf_range(world_min.x, world_max.x),
			rng.randf_range(world_min.y, world_max.y)
		)

		if _is_water_cached(pos):
			continue
		var too_close_to_water := false
		for offset in [Vector2(60.0, 0), Vector2(-60.0, 0),
				Vector2(0, 60.0), Vector2(0, -60.0)]:
			if _is_water_cached(pos + offset):
				too_close_to_water = true
				break
		if too_close_to_water:
			continue
		if _is_too_close_to_cave(pos):
			continue

		if grass_min_distance > 0.0:
			var min_sq := grass_min_distance * grass_min_distance
			var too_close := false
			for other in placed_positions:
				if pos.distance_squared_to(other) < min_sq:
					too_close = true
					break
			if too_close:
				continue

		placed_positions.append(pos)
		var tex: Texture2D = _grass_textures[rng.randi() % _grass_textures.size()]
		var sc: float = rng.randf_range(grass_min_scale, grass_max_scale)
		var rot: float = rng.randf_range(grass_min_rotation, grass_max_rotation)
		var col := Color(
			rng.randf_range(grass_color_r_min, 1.0),
			rng.randf_range(grass_color_g_min, 1.0),
			rng.randf_range(grass_color_b_min, 0.95)
		)
		blades.append({ "pos": pos, "tex": tex, "sc": sc, "rot": rot, "col": col })

	if blades.is_empty():
		return

	_build_jobs.append({ "env_id": "", "kind": "grass", "pos": Vector2.ZERO,
			"chunk_coord": chunk_coord, "blades": blades })

func _process_object_spawn_queue():
	var spawned := 0
	while spawned < objects_spawned_per_frame and not _object_spawn_queue.is_empty():
		var job = _object_spawn_queue.pop_front()
		var chunk_coord: Vector2i = job["chunk_coord"]

		if not loaded_chunks.has(chunk_coord):
			continue

		if job["kind"] == "grass":
			_build_grass_multimesh(chunk_coord, job["blades"])
			spawned += 1
			continue

		var env_id: String = job["env_id"]
		if destroyed_env_objects.has(env_id):
			continue
		if active_objects.has(env_id):
			continue

		_spawn_object(env_id, job["kind"], job["pos"], chunk_coord)
		spawned += 1

func _build_grass_multimesh(chunk_coord: Vector2i, blades: Array):
	if _grass_nodes.has(chunk_coord):
		return
	if blades.is_empty():
		return

	var by_tex: Dictionary = {}
	for b in blades:
		var key: RID = b["tex"].get_rid()
		if not by_tex.has(key):
			by_tex[key] = { "tex": b["tex"], "list": [] }
		by_tex[key]["list"].append(b)

	var root := Node2D.new()
	root.z_index = -1
	scene_node.add_child(root)

	for key in by_tex:
		var group = by_tex[key]
		var tex: Texture2D  = group["tex"]
		var list: Array     = group["list"]
		var tex_size: Vector2 = tex.get_size()

		var quad := QuadMesh.new()
		quad.size = tex_size

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.mesh = quad
		mm.instance_count = list.size()

		for idx in list.size():
			var b = list[idx]
			var sc: float = b["sc"]
			var xform := Transform2D(b["rot"], b["pos"])
			xform = xform.scaled_local(Vector2(sc, sc))
			mm.set_instance_transform_2d(idx, xform)
			mm.set_instance_color(idx, b["col"])

		var mmi := MultiMeshInstance2D.new()
		mmi.multimesh = mm
		mmi.texture = tex
		root.add_child(mmi)

	_grass_nodes[chunk_coord] = root

func _biome_key(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / _BIOME_CELL), floori(pos.y / _BIOME_CELL))

func _is_water_cached(pos: Vector2) -> bool:
	var k: Vector2i = _biome_key(pos)
	var water_k := Vector2i(k.x * 3 + 1, k.y * 3 + 1)
	if _biome_cache.has(water_k):
		return _biome_cache[water_k]
	_biome_queries_this_frame += 1
	var result: bool = false
	if world_gen.has_method("is_water_at"):
		result = world_gen.is_water_at(pos)
	_biome_cache[water_k] = result
	return result

func _is_forest_cached(pos: Vector2) -> bool:
	var k: Vector2i = _biome_key(pos)
	var forest_k := Vector2i(k.x * 3, k.y * 3)
	if _biome_cache.has(forest_k):
		return _biome_cache[forest_k]
	_biome_queries_this_frame += 1
	var result: bool = false
	if world_gen.has_method("is_forest_at"):
		result = world_gen.is_forest_at(pos)
	_biome_cache[forest_k] = result
	return result

func _is_safely_in_biome_cached(pos: Vector2, wants_forest: bool) -> bool:
	if _is_water_cached(pos):
		return false
	var r := biome_edge_check_radius
	var offsets := [
		Vector2.ZERO,
		Vector2(r, 0), Vector2(-r, 0),
		Vector2(0, r), Vector2(0, -r),
	]
	for offset in offsets:
		if _is_forest_cached(pos + offset) != wants_forest:
			return false
	return true

func _passes_distance_rule(chunk_coord: Vector2i, pos: Vector2, min_distance: float) -> bool:
	var min_sq := min_distance * min_distance
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var cc := chunk_coord + Vector2i(dx, dy)
			if not object_positions_by_chunk.has(cc):
				continue
			for other_pos in object_positions_by_chunk[cc]:
				if pos.distance_squared_to(other_pos) < min_sq:
					return false
	return true

func apply_env_state(destroyed: Dictionary, hits: Dictionary):
	_world_state_received = true
	destroyed_env_objects = destroyed.duplicate(true)
	env_object_hits       = hits.duplicate(true)
	for env_id in destroyed_env_objects.keys():
		_despawn_object(env_id)
	for env_id in env_object_hits.keys():
		set_object_hits(env_id, env_object_hits[env_id])

func set_world_seed(seed: int):
	world_seed = seed
	_world_state_received = false
	_unload_all_chunks()
	_cave_positions.clear()

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
	var player_tile: Vector2i  = world_gen.world_to_tile(local_player.global_position)
	var center_chunk: Vector2i = world_gen.tile_to_chunk(player_tile)

	for x in range(center_chunk.x - render_distance_chunks, center_chunk.x + render_distance_chunks + 1):
		for y in range(center_chunk.y - render_distance_chunks, center_chunk.y + render_distance_chunks + 1):
			var cc := Vector2i(x, y)
			if not loaded_chunks.has(cc) and not _chunk_load_queue.has(cc):
				_chunk_load_queue.append(cc)

	var to_unload: Array = []
	for cc in loaded_chunks.keys():
		if abs(cc.x - center_chunk.x) > unload_distance_chunks or \
		   abs(cc.y - center_chunk.y) > unload_distance_chunks:
			to_unload.append(cc)
	for cc in to_unload:
		_unload_chunk(cc)
		_chunk_load_queue.erase(cc)

func _update_cave_regions():
	if not local_player or not world_gen:
		return

	var player_tile: Vector2i = world_gen.world_to_tile(local_player.global_position)
	var player_region: Vector2i = _tile_to_cave_region(player_tile)

	var chunk_size: int = world_gen.chunk_size_tiles
	var rpc: int = maxi(1, cave_region_size_tiles / chunk_size)
	var view_r: int = render_distance_chunks / rpc + 1
	var unload_r: int = unload_distance_chunks / rpc + 2

	for rx in range(player_region.x - view_r, player_region.x + view_r + 1):
		for ry in range(player_region.y - view_r, player_region.y + view_r + 1):
			var region := Vector2i(rx, ry)
			if not _loaded_cave_regions.has(region) and not _cave_region_load_queue.has(region):
				_cave_region_load_queue.append(region)

	for region in _loaded_cave_regions.keys().duplicate():
		if abs(region.x - player_region.x) > unload_r or \
		   abs(region.y - player_region.y) > unload_r:
			_unload_cave_region(region)

	if not _cave_region_load_queue.is_empty():
		var region: Vector2i = _cave_region_load_queue.pop_front()
		if not _loaded_cave_regions.has(region):
			_load_cave_region(region)

func _load_cave_region(region: Vector2i):
	_loaded_cave_regions[region] = true

	var rng := RandomNumberGenerator.new()
	rng.seed = _cave_region_seed(region)

	if rng.randf() > cave_chance_per_region:
		return

	var margin: int = 8
	var origin := Vector2i(region.x * cave_region_size_tiles, region.y * cave_region_size_tiles)
	var tile := origin + Vector2i(
		rng.randi_range(margin, cave_region_size_tiles - margin),
		rng.randi_range(margin, cave_region_size_tiles - margin))
	var world_pos: Vector2 = world_gen.tile_to_world_center(tile)

	if world_pos.length() < cave_spawn_safe_radius:
		return
	if not _packed_cave_scene:
		return

	var check_offsets := [
		Vector2.ZERO,
		Vector2(200, 0), Vector2(-200, 0),
		Vector2(0, 200), Vector2(0, -200),
	]
	for offset in check_offsets:
		if world_gen.has_method("is_water_at") and world_gen.is_water_at(world_pos + offset):
			return

	for other_pos in _cave_positions.values():
		if world_pos.distance_to(other_pos) < 1200.0:
			return

	_cave_positions[region] = world_pos

	if _active_caves.has(region):
		return

	var cave = _packed_cave_scene.instantiate()
	cave.global_position = world_pos
	scene_node.add_child(cave)
	_active_caves[region] = cave

func _unload_cave_region(region: Vector2i):
	_cave_region_load_queue.erase(region)
	_loaded_cave_regions.erase(region)

func _unload_all_cave_regions():
	_cave_region_load_queue.clear()
	_loaded_cave_regions.clear()

func _tile_to_cave_region(tc: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(tc.x) / float(cave_region_size_tiles)),
		floori(float(tc.y) / float(cave_region_size_tiles)))

func _cave_region_seed(region: Vector2i) -> int:
	return abs(world_seed ^ (region.x * 246813579) ^ (region.y * 135792468) ^ 1357924680)

func _load_chunk(chunk_coord: Vector2i):
	if loaded_chunks.has(chunk_coord):
		return
	if world_gen.has_method("is_chunk_loaded") and not world_gen.is_chunk_loaded(chunk_coord):
		if not _chunk_load_queue.has(chunk_coord):
			_chunk_load_queue.append(chunk_coord)
		return

	loaded_chunks[chunk_coord] = true
	chunk_objects[chunk_coord] = []
	object_positions_by_chunk[chunk_coord] = []

	if not _chunk_build_queue.has(chunk_coord):
		_chunk_build_queue.append(chunk_coord)

func _unload_chunk(chunk_coord: Vector2i):
	_chunk_build_queue.erase(chunk_coord)
	if _building_chunk == chunk_coord:
		_building_chunk = Vector2i(999999, 999999)
		_build_jobs.clear()
		_build_kind_index = 0
		_biome_cache.clear()

	if chunk_objects.has(chunk_coord):
		for env_id in chunk_objects[chunk_coord]:
			_despawn_object(env_id)

	for i in range(_object_spawn_queue.size() - 1, -1, -1):
		if _object_spawn_queue[i]["chunk_coord"] == chunk_coord:
			_object_spawn_queue.remove_at(i)

	if _grass_nodes.has(chunk_coord):
		var node = _grass_nodes[chunk_coord]
		if is_instance_valid(node):
			node.queue_free()
		_grass_nodes.erase(chunk_coord)

	chunk_objects.erase(chunk_coord)
	object_positions_by_chunk.erase(chunk_coord)
	loaded_chunks.erase(chunk_coord)

func _unload_all_chunks():
	_chunk_load_queue.clear()
	_chunk_build_queue.clear()
	_object_spawn_queue.clear()
	_building_chunk = Vector2i(999999, 999999)
	_build_jobs.clear()
	_biome_cache.clear()

	for chunk_coord in loaded_chunks.keys().duplicate():
		_unload_chunk(chunk_coord)

	for env_id in active_objects.keys().duplicate():
		_despawn_object(env_id)

	loaded_chunks.clear()
	chunk_objects.clear()
	object_positions_by_chunk.clear()
	active_objects.clear()

	for chunk_coord in _grass_nodes.keys().duplicate():
		var node = _grass_nodes[chunk_coord]
		if is_instance_valid(node):
			node.queue_free()
	_grass_nodes.clear()

func _spawn_object(env_id: String, kind: String, pos: Vector2, _chunk_coord: Vector2i):
	if active_objects.has(env_id):
		return
	var packed: PackedScene = _packed_rock_scene if kind == "rock" else _packed_tree_scene
	if packed == null:
		return

	var obj = packed.instantiate()
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

func _get_chunk_world_bounds(chunk_coord: Vector2i) -> Array:
	var start_tile: Vector2i = world_gen.chunk_to_start_tile(chunk_coord)
	var chunk_size: int = world_gen.chunk_size_tiles
	var ts: int = world_gen.tile_size
	var end_tile := start_tile + Vector2i(chunk_size - 1, chunk_size - 1)
	var world_min: Vector2 = world_gen.tile_to_world_center(start_tile) - Vector2(ts * 0.5, ts * 0.5)
	var world_max: Vector2 = world_gen.tile_to_world_center(end_tile)   + Vector2(ts * 0.5, ts * 0.5)
	return [world_min, world_max]

func _chunk_seed(chunk_coord: Vector2i, kind: String, wants_forest: bool) -> int:
	var biome_key: int = 1 if wants_forest else 0
	var kind_key: int = 0
	if kind == "rock":
		kind_key = 7
	elif kind == "tree":
		kind_key = 13
	var mixed: int = world_seed ^ (chunk_coord.x * 374761393) ^ (chunk_coord.y * 1234567891) ^ (kind_key * 7919) ^ (biome_key * 104729)
	return abs(mixed)

func _make_env_id(kind: String, chunk_coord: Vector2i, index: int) -> String:
	return kind + ":" + str(chunk_coord.x) + ":" + str(chunk_coord.y) + ":" + str(index)

func _has_property(obj: Object, property_name: String) -> bool:
	for prop in obj.get_property_list():
		if prop.name == property_name:
			return true
	return false

func _is_too_close_to_cave(pos: Vector2) -> bool:
	for cave_pos in _cave_positions.values():
		if pos.distance_to(cave_pos) < 180.0:
			return true
	return false
