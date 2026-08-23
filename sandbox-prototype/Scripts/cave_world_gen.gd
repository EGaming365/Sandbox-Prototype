extends Node2D

@export var chunk_size_tiles: int = 24
@export var chunk_view_distance: int = 3
@export var chunk_unload_distance: int = 5
@export var chunk_update_interval: float = 0.1
@export var tiles_per_frame: int = 80

@export var cave_source_name: String = "Cave Tiles"
@export var cave_source_fallback_id: int = 2
@export var cave_atlas: Vector2i = Vector2i(0, 0)
@export var cave_wall_atlas: Vector2i = Vector2i(1, 1)
@export var cave_door_atlas: Vector2i = Vector2i(2, 0)
@export var cave_door_open_atlas: Vector2i = Vector2i(2, 1)

@export var water_source_name: String = "Water Tiles"
@export var water_source_fallback_id: int = 1
@export var water_atlas: Vector2i = Vector2i(0, 0)

@export var grid_cols: int = 7
@export var grid_rows: int = 7
@export var room_tile_size_min: int = 16
@export var room_tile_size_max: int = 28
@export var room_spacing_tiles: int = 8
@export var corridor_width: int = 5

@export var size_multiplier_spawn: float = 0.9
@export var size_multiplier_novice_fight: float = 1.2
@export var size_multiplier_basic_fight: float = 1.1
@export var size_multiplier_lake: float = 1.4
@export var size_multiplier_boss: float = 1.8

@export var lake_inner_margin: int = 3

@export var count_novice_fight_min: int = 2
@export var count_novice_fight_max: int = 4
@export var count_basic_fight_min: int = 2
@export var count_basic_fight_max: int = 4
@export var count_lake_min: int = 1
@export var count_lake_max: int = 3

@export var cave_rock_scene_path: String = "res://Scenes/rock.tscn"
@export var cave_exit_scene_path: String = "res://Scenes/cave.tscn"
@export var cave_rocks_per_room: float = 2.0
@export var cave_rock_min_distance: float = 128.0
@export var cave_rock_spawn_attempts: int = 20
@export var combat_enemy_base_count: int = 2
@export var novice_fight_bonus_enemies: int = 0
@export var basic_fight_bonus_enemies: int = 2
@export var boss_room_bonus_enemies: int = 4
@export var combat_enemy_count_per_12_tiles: int = 1
@export var combat_spawn_min_separation: float = 96.0

signal room_locked(room_id: int, room_type: RoomType)
signal room_cleared(room_id: int, room_type: RoomType)
signal boss_room_entered(room_id: int)
signal request_enemy_spawn(room_id: int, room_type: RoomType, spawn_positions: Array)

enum RoomType { SPAWN, NOVICE_FIGHT, BASIC_FIGHT, LAKE, BOSS }
enum BiomeType { CAVE_FLOOR, CAVE_WALL, WATER_LAKE, DOOR_CLOSED, DOOR_OPEN }

class RoomData:
	var id: int
	var grid_pos: Vector2i
	var tile_origin: Vector2i
	var tile_size: int
	var room_type: RoomType
	var neighbors: Array[int] = []
	var is_locked: bool = false
	var is_cleared: bool = false
	var enemy_count: int = 0
	var door_tiles: Array[Vector2i] = []
	var wall_tiles_on_lock: Array[Vector2i] = []
	var spawned_enemy_ids: Array[int] = []

var in_cave: bool = false
var world_seed: int = 0
var _enter_cooldown: float = 0.0
const ENTER_COOLDOWN_TIME: float = 2.0

var _active: bool = false
var _tilemap: TileMap
var _world_gen: Node
var _env_spawner: Node
var cave_source_id: int = -1
var water_source_id: int = -1

var _rooms: Array[RoomData] = []
var _spawn_room_id: int = -1
var _boss_room_id: int = -1
var _room_grid: Dictionary = {}

var _carved_tiles: Dictionary = {}
var _wall_tiles: Dictionary = {}
var _water_tiles: Dictionary = {}
var _door_tile_data: Dictionary = {}
var _tile_to_room: Dictionary = {}
var _locked_wall_tiles: Dictionary = {}

const ROOM_ACTIVATION_DELAY: float = 1.0
const BOSS_DEATH_COOLDOWN: float = 8.0
var _room_pending_timer: Dictionary = {}
var _room_waiting: Dictionary = {}
var _room_cooldown: Dictionary = {}

var _cave_entrance_tile: Vector2i = Vector2i(0, 0)
var _cave_exit_tile: Vector2i = Vector2i(0, 0)
var _cave_exit: Node2D = null

var loaded_chunks: Dictionary = {}
var pending_chunks: Array = []
var _paint_chunk: Vector2i = Vector2i(999999, 999999)
var _paint_index: int = 0
var _paint_tiles: Array = []
var _chunk_update_timer: float = 0.0

var _cave_rock_positions: Dictionary = {}
var _cave_active_rocks: Dictionary = {}
var _packed_cave_rock_scene: PackedScene = null
var _packed_cave_exit_scene: PackedScene = null
var _all_cave_rock_world_positions: Array = []

func _ready() -> void:
	await get_tree().process_frame
	_resolve_refs()
	_packed_cave_rock_scene = load(cave_rock_scene_path)
	_packed_cave_exit_scene = load(cave_exit_scene_path)

func _resolve_refs() -> void:
	_tilemap = get_tree().root.get_node_or_null("Scene/TileMap")
	_world_gen = get_tree().root.get_node_or_null("Scene/WorldGen")
	_env_spawner = get_tree().root.get_node_or_null("Scene/EnvironmentGen")
	if not _env_spawner:
		var scene: Node = get_tree().root.get_node_or_null("Scene")
		if scene:
			for child: Node in scene.get_children():
				if child.get_script() and child.has_method("_unload_all_chunks"):
					_env_spawner = child
					break

func enter_cave(player: CharacterBody2D) -> void:
	if in_cave or _enter_cooldown > 0.0:
		return
	_resolve_refs()
	in_cave = true
	_enter_cooldown = ENTER_COOLDOWN_TIME
	_cave_entrance_tile = _find_linked_overworld_entrance_tile(player.global_position)
	var animal_spawner: Node = get_tree().root.get_node_or_null("AnimalSpawner")
	if animal_spawner and animal_spawner.has_method("clear_all_entities"):
		animal_spawner.clear_all_entities()
	if _world_gen:
		_world_gen.set_process(false)
		if _tilemap:
			for cc: Vector2i in _world_gen.loaded_chunks.keys():
				var start: Vector2i = _world_gen.chunk_to_start_tile(cc)
				for x: int in _world_gen.chunk_size_tiles:
					for y: int in _world_gen.chunk_size_tiles:
						_tilemap.erase_cell(0, Vector2i(start.x + x, start.y + y))
	if _env_spawner:
		_env_spawner.set_process(false)
		if _env_spawner.has_method("_unload_all_chunks"):
			_env_spawner._unload_all_chunks()
		if _env_spawner.has_method("_unload_all_cave_regions"):
			_env_spawner._unload_all_cave_regions()
	var seed: int = _world_gen.world_seed if _world_gen else 0
	_activate(seed)
	var scene: Node = get_tree().root.get_node_or_null("Scene")
	if scene and scene.has_method("_refresh_floor_item_visibility"):
		scene._refresh_floor_item_visibility()
	_chunk_update_timer = 0.0
	_update_chunks_around_player()
	for i: int in 6:
		_paint_next_tiles()

func exit_cave(player: CharacterBody2D) -> void:
	if not in_cave or _enter_cooldown > 0.0:
		return
	var return_tile: Vector2i = _cave_entrance_tile
	var return_world_pos: Vector2 = _tile_to_world_center(return_tile)
	return_world_pos.y += _get_tile_pixel_size().y * 0.5
	in_cave = false
	_enter_cooldown = ENTER_COOLDOWN_TIME
	var animal_spawner: Node = get_tree().root.get_node_or_null("AnimalSpawner")
	if animal_spawner and animal_spawner.has_method("clear_all_entities"):
		animal_spawner.clear_all_entities()
	_deactivate()
	if is_instance_valid(player):
		player.global_position = return_world_pos
	if _world_gen:
		_world_gen.set_process(true)
		if _world_gen.has_method("_force_reload_all_chunks"):
			_world_gen._force_reload_all_chunks()
		elif _world_gen.has_method("_update_chunks_around_player"):
			_world_gen._update_chunks_around_player()
		_world_gen.chunk_update_timer = 0.0
		for i: int in 6:
			_world_gen._paint_next_tiles()
	if _env_spawner:
		_env_spawner.set_process(true)
		_env_spawner.update_timer = 0.0
		if _env_spawner.has_method("_refresh_references"):
			_env_spawner._refresh_references()
		if _env_spawner.has_method("queue_chunks_around_world_pos") and _world_gen:
			_env_spawner.queue_chunks_around_world_pos(return_world_pos, 4)
		if _env_spawner.has_method("_update_cave_regions"):
			_env_spawner._update_cave_regions()
		for i: int in 8:
			if _env_spawner.has_method("_process_load_queue_step"):
				_env_spawner._process_load_queue_step()
		for i: int in 8:
			if _env_spawner.has_method("_process_object_spawn_queue"):
				_env_spawner._process_object_spawn_queue()
	var scene: Node = get_tree().root.get_node_or_null("Scene")
	if scene and scene.has_method("_refresh_floor_item_visibility"):
		scene._refresh_floor_item_visibility()

func get_room_at_world_pos(world_pos: Vector2) -> RoomData:
	var tc: Vector2i = world_to_tile(world_pos)
	if _tile_to_room.has(tc):
		return _rooms[_tile_to_room[tc]]
	return null

func _update_room_presence(delta: float) -> void:
	if not in_cave:
		return
	var present_by_room: Dictionary = {}
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p):
			continue
		var tc: Vector2i = world_to_tile((p as Node2D).global_position)
		if not _tile_to_room.has(tc):
			continue
		var rid: int = _tile_to_room[tc]
		if not present_by_room.has(rid):
			present_by_room[rid] = []
		present_by_room[rid].append(p)
	for room: RoomData in _rooms:
		if room.is_locked or room.is_cleared:
			_room_pending_timer.erase(room.id)
			continue
		if room.room_type != RoomType.NOVICE_FIGHT and room.room_type != RoomType.BASIC_FIGHT and room.room_type != RoomType.BOSS:
			continue
		if _room_cooldown.has(room.id):
			_room_cooldown[room.id] -= delta
			if _room_cooldown[room.id] > 0.0:
				continue
			_room_cooldown.erase(room.id)
		var occupants: Array = present_by_room.get(room.id, [])
		if occupants.is_empty():
			if _room_pending_timer.has(room.id):
				_room_pending_timer.erase(room.id)
			if room.room_type == RoomType.BOSS and _room_waiting.get(room.id, false):
				_clear_boss_wait_message(room.id)
			continue
		if room.room_type == RoomType.BOSS:
			var required: int = _connected_player_count()
			if occupants.size() < required:
				_room_pending_timer.erase(room.id)
				_send_boss_wait_message(room.id, occupants, required - occupants.size())
				continue
			elif _room_waiting.get(room.id, false):
				_clear_boss_wait_message(room.id)
		if not _room_pending_timer.has(room.id):
			_room_pending_timer[room.id] = ROOM_ACTIVATION_DELAY
		_room_pending_timer[room.id] -= delta
		if _room_pending_timer[room.id] <= 0.0:
			_room_pending_timer.erase(room.id)
			_lock_room(room)
			if room.room_type == RoomType.BOSS:
				emit_signal("boss_room_entered", room.id)
				if _room_waiting.get(room.id, false):
					_clear_boss_wait_message(room.id)

func _send_boss_wait_message(room_id: int, occupants: Array, missing: int) -> void:
	var scene_node: Node = get_tree().root.get_node_or_null("Scene")
	if not scene_node or not scene_node.has_method("set_boss_wait_ui"):
		return
	_room_waiting[room_id] = true
	for p in occupants:
		if not is_instance_valid(p):
			continue
		var pid: int = String(p.name).to_int()
		if not multiplayer.has_multiplayer_peer() or pid == multiplayer.get_unique_id():
			scene_node.set_boss_wait_ui(true, missing)
		else:
			scene_node.set_boss_wait_ui.rpc_id(pid, true, missing)

func _clear_boss_wait_message(room_id: int) -> void:
	_room_waiting[room_id] = false
	var scene_node: Node = get_tree().root.get_node_or_null("Scene")
	if not scene_node or not scene_node.has_method("set_boss_wait_ui"):
		return
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p):
			continue
		var pid: int = String(p.name).to_int()
		if not multiplayer.has_multiplayer_peer() or pid == multiplayer.get_unique_id():
			scene_node.set_boss_wait_ui(false, 0)
		else:
			scene_node.set_boss_wait_ui.rpc_id(pid, false, 0)

func notify_enemy_died(world_pos: Vector2) -> void:
	var room: RoomData = get_room_at_world_pos(world_pos)
	if not room or not room.is_locked:
		return
	room.enemy_count = max(0, room.enemy_count - 1)
	if room.enemy_count <= 0:
		_unlock_room(room)

func set_room_enemy_count(room_id: int, count: int) -> void:
	if room_id < _rooms.size():
		_rooms[room_id].enemy_count = count

func get_spawn_room() -> RoomData:
	if _spawn_room_id >= 0:
		return _rooms[_spawn_room_id]
	return null

func get_boss_room() -> RoomData:
	if _boss_room_id >= 0:
		return _rooms[_boss_room_id]
	return null

func get_all_rooms() -> Array[RoomData]:
	return _rooms

func get_room_center_world(room_id: int) -> Vector2:
	if room_id < 0 or room_id >= _rooms.size():
		return Vector2.ZERO
	var room: RoomData = _rooms[room_id]
	var half: int = room.tile_size / 2
	var tc: Vector2i = room.tile_origin + Vector2i(half, half)
	return _tile_to_world_center(tc)

func get_room_floor_positions(room_id: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if room_id < 0 or room_id >= _rooms.size():
		return positions
	var room: RoomData = _rooms[room_id]
	var margin: int = 2
	for dx: int in range(margin, room.tile_size - margin):
		for dy: int in range(margin, room.tile_size - margin):
			var tc: Vector2i = room.tile_origin + Vector2i(dx, dy)
			if _carved_tiles.has(tc) and not _water_tiles.has(tc) and not _door_tile_data.has(tc):
				positions.append(_tile_to_world_center(tc))
	return positions

func _carve_corridor_tiles(a: RoomData, b: RoomData) -> void:
	var ac: Vector2i = a.tile_origin + Vector2i(a.tile_size / 2, a.tile_size / 2)
	var bc: Vector2i = b.tile_origin + Vector2i(b.tile_size / 2, b.tile_size / 2)
	var half: int = corridor_width / 2
	var grid_diff: Vector2i = b.grid_pos - a.grid_pos
	var is_horizontal: bool = grid_diff.x != 0

	if is_horizontal:
		var x_start: int = min(ac.x, bc.x)
		var x_end: int = max(ac.x, bc.x)
		var y_mid: int = ac.y
		for x: int in range(x_start, x_end + 1):
			for dy: int in range(-half, half + 1):
				var tc: Vector2i = Vector2i(x, y_mid + dy)
				_carved_tiles[tc] = true
				_wall_tiles.erase(tc)
				if not _tile_to_room.has(tc):
					_tile_to_room[tc] = a.id
		for x: int in range(x_start, x_end + 1):
			for side: int in [-1, 1]:
				var tc: Vector2i = Vector2i(x, y_mid + side * (half + 1))
				if not _carved_tiles.has(tc):
					_wall_tiles[tc] = true
		var door_a_x: int = a.tile_origin.x + a.tile_size if ac.x < bc.x else a.tile_origin.x - 1
		var door_b_x: int = b.tile_origin.x - 1 if ac.x < bc.x else b.tile_origin.x + b.tile_size
		_place_door_pair(a, b,
			Vector2i(door_a_x, y_mid),
			Vector2i(door_b_x, y_mid),
			is_horizontal)
	else:
		var y_start: int = min(ac.y, bc.y)
		var y_end: int = max(ac.y, bc.y)
		var x_mid: int = ac.x
		for y: int in range(y_start, y_end + 1):
			for dx: int in range(-half, half + 1):
				var tc: Vector2i = Vector2i(x_mid + dx, y)
				_carved_tiles[tc] = true
				_wall_tiles.erase(tc)
				if not _tile_to_room.has(tc):
					_tile_to_room[tc] = a.id
		for y: int in range(y_start, y_end + 1):
			for side: int in [-1, 1]:
				var tc: Vector2i = Vector2i(x_mid + side * (half + 1), y)
				if not _carved_tiles.has(tc):
					_wall_tiles[tc] = true
		var door_a_y: int = a.tile_origin.y + a.tile_size if ac.y < bc.y else a.tile_origin.y - 1
		var door_b_y: int = b.tile_origin.y - 1 if ac.y < bc.y else b.tile_origin.y + b.tile_size
		_place_door_pair(a, b,
			Vector2i(x_mid, door_a_y),
			Vector2i(x_mid, door_b_y),
			is_horizontal)

func _generate_dungeon() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = abs(world_seed ^ 0xD00DCAFE)

	var n_novice: int = rng.randi_range(count_novice_fight_min, count_novice_fight_max)
	var n_basic: int = rng.randi_range(count_basic_fight_min, count_basic_fight_max)
	var n_lake: int = rng.randi_range(count_lake_min, count_lake_max)
	var n_rooms: int = 1 + n_novice + n_basic + n_lake + 1

	var placed_grid_positions: Array[Vector2i] = []
	var center: Vector2i = Vector2i(grid_cols / 2, grid_rows / 2)
	placed_grid_positions.append(center)

	var frontier: Array[Vector2i] = [center]
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	while placed_grid_positions.size() < n_rooms and not frontier.is_empty():
		var idx: int = rng.randi() % frontier.size()
		var cur: Vector2i = frontier[idx]
		var shuffled: Array[Vector2i] = dirs.duplicate()
		for i: int in range(shuffled.size() - 1, 0, -1):
			var j: int = rng.randi() % (i + 1)
			var tmp: Vector2i = shuffled[i]
			shuffled[i] = shuffled[j]
			shuffled[j] = tmp
		var placed: bool = false
		for d: Vector2i in shuffled:
			var candidate: Vector2i = cur + d
			if candidate.x < 0 or candidate.x >= grid_cols:
				continue
			if candidate.y < 0 or candidate.y >= grid_rows:
				continue
			if _room_grid.has(candidate):
				continue
			placed_grid_positions.append(candidate)
			_room_grid[candidate] = placed_grid_positions.size() - 1
			frontier.append(candidate)
			placed = true
			break
		if not placed:
			frontier.remove_at(idx)

	while placed_grid_positions.size() > n_rooms:
		placed_grid_positions.pop_back()
	_room_grid.clear()

	var adjacency: Dictionary = {}
	for i: int in placed_grid_positions.size():
		adjacency[i] = []

	for i: int in range(1, placed_grid_positions.size()):
		var best_j: int = 0
		var best_dist: float = INF
		for j: int in range(0, i):
			var d: float = placed_grid_positions[i].distance_squared_to(placed_grid_positions[j])
			if d < best_dist:
				best_dist = d
				best_j = j
		adjacency[i].append(best_j)
		adjacency[best_j].append(i)

	var extra: int = rng.randi_range(1, 3)
	for _e: int in extra:
		var ai: int = rng.randi() % placed_grid_positions.size()
		for d: Vector2i in dirs:
			var neighbor_pos: Vector2i = placed_grid_positions[ai] + d
			var found_j: int = -1
			for j: int in placed_grid_positions.size():
				if placed_grid_positions[j] == neighbor_pos:
					found_j = j
					break
			if found_j >= 0 and found_j != ai and not (found_j in adjacency[ai]):
				adjacency[ai].append(found_j)
				adjacency[found_j].append(ai)
				break

	var spawn_idx: int = 0
	var best_center_dist: float = INF
	for i: int in placed_grid_positions.size():
		var d: float = placed_grid_positions[i].distance_squared_to(center)
		if d < best_center_dist:
			best_center_dist = d
			spawn_idx = i

	var bfs_depth: Dictionary = _bfs_depths(spawn_idx, adjacency, placed_grid_positions.size())
	var boss_idx: int = 0
	var max_depth: int = -1
	for i: int in bfs_depth.keys():
		if bfs_depth[i] > max_depth:
			max_depth = bfs_depth[i]
			boss_idx = i

	var type_pool: Array[RoomType] = []
	for _i: int in n_novice:
		type_pool.append(RoomType.NOVICE_FIGHT)
	for _i: int in n_basic:
		type_pool.append(RoomType.BASIC_FIGHT)
	for _i: int in n_lake:
		type_pool.append(RoomType.LAKE)
	for i: int in range(type_pool.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var tmp: RoomType = type_pool[i]
		type_pool[i] = type_pool[j]
		type_pool[j] = tmp

	var pool_idx: int = 0
	var type_assignments: Array[RoomType] = []
	type_assignments.resize(placed_grid_positions.size())
	for i: int in placed_grid_positions.size():
		if i == spawn_idx:
			type_assignments[i] = RoomType.SPAWN
		elif i == boss_idx:
			type_assignments[i] = RoomType.BOSS
		else:
			if pool_idx < type_pool.size():
				type_assignments[i] = type_pool[pool_idx]
				pool_idx += 1
			else:
				type_assignments[i] = RoomType.NOVICE_FIGHT

	type_assignments[spawn_idx] = RoomType.SPAWN
	if boss_idx != spawn_idx:
		type_assignments[boss_idx] = RoomType.BOSS

	var room_sizes: Array[int] = []
	room_sizes.resize(placed_grid_positions.size())
	for i: int in placed_grid_positions.size():
		room_sizes[i] = _room_size_for_type(type_assignments[i], rng)

	var max_size: int = room_tile_size_max
	for s: int in room_sizes:
		if s > max_size:
			max_size = s
	var block: int = max_size + room_spacing_tiles

	var spawn_grid: Vector2i = placed_grid_positions[spawn_idx]
	var spawn_size: int = room_sizes[spawn_idx]
	var tile_offset: Vector2i = _cave_entrance_tile - Vector2i(
		spawn_grid.x * block + max_size / 2,
		spawn_grid.y * block + max_size / 2)

	for i: int in placed_grid_positions.size():
		var gp: Vector2i = placed_grid_positions[i]
		var sz: int = room_sizes[i]
		var cell_center: Vector2i = Vector2i(gp.x * block + max_size / 2, gp.y * block + max_size / 2)
		var tile_origin: Vector2i = cell_center - Vector2i(sz / 2, sz / 2) + tile_offset
		var rd: RoomData = RoomData.new()
		rd.id = i
		rd.grid_pos = gp
		rd.tile_origin = tile_origin
		rd.tile_size = sz
		rd.room_type = type_assignments[i]
		for nb: int in adjacency[i]:
			rd.neighbors.append(nb)
		_rooms.append(rd)
		_room_grid[gp] = i

	_spawn_room_id = spawn_idx
	_boss_room_id = boss_idx
	_cave_exit_tile = _rooms[spawn_idx].tile_origin + Vector2i(room_sizes[spawn_idx] / 2, room_sizes[spawn_idx] / 2)

	for room: RoomData in _rooms:
		_carve_room_tiles(room)
	for i: int in placed_grid_positions.size():
		for nb: int in adjacency[i]:
			if nb > i:
				_carve_corridor_tiles(_rooms[i], _rooms[nb])

func _activate(seed: int) -> void:
	world_seed = seed
	_find_tile_sources()
	_clear_state()
	_generate_dungeon()
	_spawn_cave_exit()
	_active = true
	_update_chunks_around_player()

func _clear_state() -> void:
	_rooms.clear()
	_room_grid.clear()
	_carved_tiles.clear()
	_wall_tiles.clear()
	_water_tiles.clear()
	_door_tile_data.clear()
	_tile_to_room.clear()
	_locked_wall_tiles.clear()
	_cave_rock_positions.clear()
	_cave_active_rocks.clear()
	_all_cave_rock_world_positions.clear()
	loaded_chunks.clear()
	pending_chunks.clear()
	_paint_chunk = Vector2i(999999, 999999)
	_paint_index = 0
	_paint_tiles.clear()
	_chunk_update_timer = 0.0
	_spawn_room_id = -1
	_boss_room_id = -1
	_despawn_cave_exit()

func _deactivate() -> void:
	_active = false
	_despawn_cave_exit()
	for cc: Vector2i in loaded_chunks.keys():
		_erase_chunk_tiles(cc)
		_despawn_cave_rocks_for_chunk(cc)
	_clear_state()

func _get_size_multiplier(rt: RoomType) -> float:
	match rt:
		RoomType.SPAWN:         return size_multiplier_spawn
		RoomType.NOVICE_FIGHT:  return size_multiplier_novice_fight
		RoomType.BASIC_FIGHT:   return size_multiplier_basic_fight
		RoomType.LAKE:          return size_multiplier_lake
		RoomType.BOSS:          return size_multiplier_boss
	return 1.0

func _room_size_for_type(rt: RoomType, rng: RandomNumberGenerator) -> int:
	var base: int = rng.randi_range(room_tile_size_min, room_tile_size_max)
	var mult: float = _get_size_multiplier(rt)
	var result: int = int(float(base) * mult)
	result = max(result, room_tile_size_min)
	if result % 2 != 0:
		result += 1
	return result

func _bfs_depths(start: int, adj: Dictionary, _n: int) -> Dictionary:
	var depth: Dictionary = {}
	var queue: Array[int] = [start]
	depth[start] = 0
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		for nb: int in adj[cur]:
			if not depth.has(nb):
				depth[nb] = depth[cur] + 1
				queue.append(nb)
	return depth

func _carve_room_tiles(room: RoomData) -> void:
	for dx: int in room.tile_size:
		for dy: int in room.tile_size:
			var tc: Vector2i = room.tile_origin + Vector2i(dx, dy)
			_carved_tiles[tc] = true
			_wall_tiles.erase(tc)
			_tile_to_room[tc] = room.id
	if room.room_type == RoomType.LAKE and room.id != _spawn_room_id:
		_carve_lake_interior(room)
	for dx: int in range(-1, room.tile_size + 1):
		for dy: int in range(-1, room.tile_size + 1):
			if dx >= 0 and dx < room.tile_size and dy >= 0 and dy < room.tile_size:
				continue
			var tc: Vector2i = room.tile_origin + Vector2i(dx, dy)
			if not _carved_tiles.has(tc):
				_wall_tiles[tc] = true

func _carve_lake_interior(room: RoomData) -> void:
	var m: int = lake_inner_margin
	var inner_size: int = room.tile_size - m * 2
	if inner_size <= 0:
		return
	var cx: float = float(room.tile_size) / 2.0
	var cy: float = float(room.tile_size) / 2.0
	var rx: float = float(inner_size) / 2.0
	var ry: float = float(inner_size) / 2.0
	for dx: int in room.tile_size:
		for dy: int in room.tile_size:
			var fx: float = float(dx) + 0.5 - cx
			var fy: float = float(dy) + 0.5 - cy
			if (fx * fx) / (rx * rx) + (fy * fy) / (ry * ry) <= 1.0:
				var tc: Vector2i = room.tile_origin + Vector2i(dx, dy)
				_water_tiles[tc] = true

func _get_corridor_entrance_wall_tiles(door_tc: Vector2i, is_horizontal: bool) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var half: int = corridor_width / 2
	if is_horizontal:
		for offset in range(-half, half + 1):
			result.append(Vector2i(door_tc.x, door_tc.y + offset))
	else:
		for offset in range(-half, half + 1):
			result.append(Vector2i(door_tc.x + offset, door_tc.y))
	return result

func _place_door_pair(a: RoomData, b: RoomData, tc_a: Vector2i, tc_b: Vector2i, is_horizontal: bool) -> void:
	for pair: Array in [[tc_a, a.id], [tc_b, b.id]]:
		var tc: Vector2i = pair[0]
		var rid: int = pair[1]
		var room: RoomData = _rooms[rid]
		if room.room_type == RoomType.NOVICE_FIGHT \
		or room.room_type == RoomType.BASIC_FIGHT \
		or room.room_type == RoomType.BOSS:
			_door_tile_data[tc] = {"room_id": rid, "is_closed": false}
			room.door_tiles.append(tc)
			var wall_set: Array[Vector2i] = _get_corridor_entrance_wall_tiles(tc, is_horizontal)
			for wt: Vector2i in wall_set:
				if not room.wall_tiles_on_lock.has(wt):
					room.wall_tiles_on_lock.append(wt)

func _place_lock_walls(room: RoomData) -> void:
	for tc: Vector2i in room.wall_tiles_on_lock:
		if _carved_tiles.has(tc):
			_locked_wall_tiles[tc] = true
			if _tilemap:
				_tilemap.set_cell(0, tc, cave_source_id, cave_wall_atlas)

func _remove_lock_walls(room: RoomData) -> void:
	for tc: Vector2i in room.wall_tiles_on_lock:
		if _locked_wall_tiles.has(tc):
			_locked_wall_tiles.erase(tc)
			if _tilemap:
				_tilemap.set_cell(0, tc, cave_source_id, cave_atlas)

func _lock_room(room: RoomData) -> void:
	room.is_locked = true
	room.enemy_count = _enemy_count_for_room(room)
	room.spawned_enemy_ids.clear()
	for tc: Vector2i in room.door_tiles:
		if _door_tile_data.has(tc):
			_door_tile_data[tc]["is_closed"] = true
		if _tilemap:
			_tilemap.set_cell(0, tc, cave_source_id, cave_door_atlas)
	_place_lock_walls(room)
	var spawn_positions: Array = get_room_floor_positions(room.id)
	emit_signal("room_locked", room.id, room.room_type)
	emit_signal("request_enemy_spawn", room.id, room.room_type, spawn_positions)
	_spawn_room_enemies(room, spawn_positions)
	if room.enemy_count <= 0:
		_unlock_room(room)

func _unlock_room(room: RoomData) -> void:
	room.is_locked = false
	room.is_cleared = true
	room.enemy_count = 0
	room.spawned_enemy_ids.clear()
	for tc: Vector2i in room.door_tiles:
		if _door_tile_data.has(tc):
			_door_tile_data[tc]["is_closed"] = false
		if _tilemap:
			_tilemap.set_cell(0, tc, cave_source_id, cave_door_open_atlas)
	_remove_lock_walls(room)
	emit_signal("room_cleared", room.id, room.room_type)

func _reset_room(room: RoomData, cooldown: float = 0.0) -> void:
	room.is_locked = false
	room.is_cleared = false
	room.enemy_count = 0
	room.spawned_enemy_ids.clear()
	for tc: Vector2i in room.door_tiles:
		if _door_tile_data.has(tc):
			_door_tile_data[tc]["is_closed"] = false
		if _tilemap:
			_tilemap.set_cell(0, tc, cave_source_id, cave_door_open_atlas)
	_remove_lock_walls(room)
	_room_pending_timer.erase(room.id)
	if cooldown > 0.0:
		_room_cooldown[room.id] = cooldown
	else:
		_room_cooldown.erase(room.id)
	emit_signal("room_cleared", room.id, room.room_type)

func request_player_died(world_pos: Vector2) -> void:
	if _is_host():
		notify_player_died(world_pos)
		return
	var scene_node: Node = get_tree().root.get_node_or_null("Scene")
	if scene_node and scene_node.has_method("request_room_death_reset"):
		scene_node.request_room_death_reset.rpc_id(1, world_pos.x, world_pos.y)

func notify_player_died(world_pos: Vector2) -> void:
	if not _is_host():
		return
	var room: RoomData = get_room_at_world_pos(world_pos)
	if not room or not room.is_locked:
		return
	var animal_spawner: Node = get_tree().root.get_node_or_null("AnimalSpawner")
	if animal_spawner and animal_spawner.has_method("clear_room_entities"):
		animal_spawner.clear_room_entities(room.id)
	if room.room_type == RoomType.BOSS:
		if _room_waiting.get(room.id, false):
			_clear_boss_wait_message(room.id)
		_reset_room(room, BOSS_DEATH_COOLDOWN)
	else:
		_reset_room(room)

func _process(delta: float) -> void:
	if _enter_cooldown > 0.0:
		_enter_cooldown -= delta
	if not _active:
		return
	if _is_host():
		_update_room_presence(delta)
		_check_locked_rooms_clear()
	_paint_next_tiles()
	_chunk_update_timer -= delta
	if _chunk_update_timer > 0.0:
		return
	_chunk_update_timer = chunk_update_interval
	_update_chunks_around_player()

func _get_local_player() -> CharacterBody2D:
	var scene: Node = get_tree().root.get_node_or_null("Scene")
	if not scene:
		return null
	var lp: Variant = scene.get("local_player")
	if lp and is_instance_valid(lp):
		return lp
	for child: Node in scene.get_children():
		if child is CharacterBody2D and child.is_in_group("players"):
			if not multiplayer.has_multiplayer_peer() or child.is_multiplayer_authority():
				return child
	return null

func _connected_player_count() -> int:
	if not multiplayer.has_multiplayer_peer():
		return 1
	return multiplayer.get_peers().size() + 1

func _update_chunks_around_player() -> void:
	if not _tilemap:
		return
	var player: CharacterBody2D = _get_local_player()
	if not player:
		return
	var player_chunk: Vector2i = tile_to_chunk(world_to_tile(player.global_position))
	var to_queue: Array[Vector2i] = []
	for cx: int in range(player_chunk.x - chunk_view_distance, player_chunk.x + chunk_view_distance + 1):
		for cy: int in range(player_chunk.y - chunk_view_distance, player_chunk.y + chunk_view_distance + 1):
			var cc: Vector2i = Vector2i(cx, cy)
			if loaded_chunks.has(cc) or pending_chunks.has(cc) or _paint_chunk == cc:
				continue
			to_queue.append(cc)
	to_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_squared_to(player_chunk) < b.distance_squared_to(player_chunk))
	for cc: Vector2i in to_queue:
		pending_chunks.append(cc)
	for cc: Vector2i in loaded_chunks.keys().duplicate():
		if abs(cc.x - player_chunk.x) > chunk_unload_distance or \
		   abs(cc.y - player_chunk.y) > chunk_unload_distance:
			_unload_chunk(cc)
	pending_chunks = pending_chunks.filter(func(cc: Vector2i) -> bool:
		return abs(cc.x - player_chunk.x) <= chunk_unload_distance and \
			   abs(cc.y - player_chunk.y) <= chunk_unload_distance)

func _paint_next_tiles() -> void:
	var painted: int = 0
	while painted < tiles_per_frame:
		if _paint_chunk == Vector2i(999999, 999999):
			if pending_chunks.is_empty():
				return
			_paint_chunk = pending_chunks.pop_front()
			_paint_index = 0
			_precompute_chunk(_paint_chunk)
		if _paint_index >= _paint_tiles.size():
			loaded_chunks[_paint_chunk] = true
			_paint_chunk = Vector2i(999999, 999999)
			_paint_tiles.clear()
			_paint_index = 0
			continue
		var entry: Array = _paint_tiles[_paint_index]
		if entry[1] != null:
			_apply_tile(entry[0], entry[1])
		_paint_index += 1
		painted += 1

func _precompute_chunk(chunk_coord: Vector2i) -> void:
	_paint_tiles.clear()
	var start: Vector2i = chunk_to_start_tile(chunk_coord)
	var total: int = chunk_size_tiles * chunk_size_tiles
	_paint_tiles.resize(total)

	var chunk_has_content: bool = false
	for i: int in total:
		var tc: Vector2i = Vector2i(start.x + i % chunk_size_tiles, start.y + i / chunk_size_tiles)
		if _carved_tiles.has(tc) or _wall_tiles.has(tc):
			chunk_has_content = true
			break

	if not chunk_has_content:
		for i: int in total:
			_paint_tiles[i] = [Vector2i(start.x + i % chunk_size_tiles, start.y + i / chunk_size_tiles), null]
		return

	for i: int in total:
		var tc: Vector2i = Vector2i(start.x + i % chunk_size_tiles, start.y + i / chunk_size_tiles)
		if _wall_tiles.has(tc) or _locked_wall_tiles.has(tc):
			_paint_tiles[i] = [tc, BiomeType.CAVE_WALL]
		elif _door_tile_data.has(tc):
			var closed: bool = _door_tile_data[tc]["is_closed"]
			_paint_tiles[i] = [tc, BiomeType.DOOR_CLOSED if closed else BiomeType.DOOR_OPEN]
		elif _water_tiles.has(tc):
			_paint_tiles[i] = [tc, BiomeType.WATER_LAKE]
		elif _carved_tiles.has(tc):
			_paint_tiles[i] = [tc, BiomeType.CAVE_FLOOR]
		else:
			_paint_tiles[i] = [tc, null]

	_spawn_cave_rocks_for_chunk(chunk_coord)

func _apply_tile(tc: Vector2i, biome: BiomeType) -> void:
	match biome:
		BiomeType.WATER_LAKE:
			var src: int = water_source_id if water_source_id != -1 else cave_source_id
			_tilemap.set_cell(0, tc, src, water_atlas)
		BiomeType.CAVE_WALL:
			_tilemap.set_cell(0, tc, cave_source_id, cave_wall_atlas)
		BiomeType.DOOR_CLOSED:
			_tilemap.set_cell(0, tc, cave_source_id, cave_door_atlas)
		BiomeType.DOOR_OPEN:
			_tilemap.set_cell(0, tc, cave_source_id, cave_door_open_atlas)
		BiomeType.CAVE_FLOOR:
			_tilemap.set_cell(0, tc, cave_source_id, cave_atlas)

func _unload_chunk(cc: Vector2i) -> void:
	pending_chunks.erase(cc)
	if _paint_chunk == cc:
		_paint_chunk = Vector2i(999999, 999999)
		_paint_index = 0
		_paint_tiles.clear()
	_erase_chunk_tiles(cc)
	_despawn_cave_rocks_for_chunk(cc)
	loaded_chunks.erase(cc)

func _erase_chunk_tiles(cc: Vector2i) -> void:
	var start: Vector2i = chunk_to_start_tile(cc)
	for x: int in chunk_size_tiles:
		for y: int in chunk_size_tiles:
			_tilemap.erase_cell(0, Vector2i(start.x + x, start.y + y))

func _spawn_cave_rocks_for_chunk(cc: Vector2i) -> void:
	if not _packed_cave_rock_scene:
		return
	if _cave_rock_positions.has(cc):
		for env_id: String in _cave_rock_positions[cc]:
			if not _cave_active_rocks.has(env_id):
				_spawn_cave_rock(env_id, _cave_rock_positions[cc][env_id])
		return

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _cave_chunk_seed(cc, "rock")
	var start_tile: Vector2i = chunk_to_start_tile(cc)
	_cave_rock_positions[cc] = {}
	var placed_this_chunk: Array[Vector2] = []
	var min_dist_sq: float = cave_rock_min_distance * cave_rock_min_distance

	var attempts: int = max(1, int(cave_rocks_per_room * chunk_size_tiles * chunk_size_tiles /
								   (room_tile_size_max * room_tile_size_max)))

	for _i: int in attempts:
		for _attempt: int in cave_rock_spawn_attempts:
			var tx: int = rng.randi_range(start_tile.x, start_tile.x + chunk_size_tiles - 1)
			var ty: int = rng.randi_range(start_tile.y, start_tile.y + chunk_size_tiles - 1)
			var tc: Vector2i = Vector2i(tx, ty)
			if not _carved_tiles.has(tc) or _water_tiles.has(tc):
				continue
			if _door_tile_data.has(tc):
				continue
			if not _tile_to_room.has(tc):
				continue
			var rid: int = _tile_to_room[tc]
			var room: RoomData = _rooms[rid]
			if room.room_type == RoomType.SPAWN or room.room_type == RoomType.BOSS:
				continue
			if room.room_type == RoomType.NOVICE_FIGHT or room.room_type == RoomType.BASIC_FIGHT:
				continue

			var world_pos: Vector2
			if _tilemap:
				world_pos = _tilemap.to_global(_tilemap.map_to_local(tc))
			else:
				world_pos = Vector2(tc) * 64.0 + Vector2(32.0, 32.0)

			var too_close: bool = false
			for other: Vector2 in _all_cave_rock_world_positions:
				if world_pos.distance_squared_to(other) < min_dist_sq:
					too_close = true
					break
			if too_close:
				continue
			for other: Vector2 in placed_this_chunk:
				if world_pos.distance_squared_to(other) < min_dist_sq:
					too_close = true
					break
			if too_close:
				continue

			placed_this_chunk.append(world_pos)
			_all_cave_rock_world_positions.append(world_pos)
			var env_id: String = "caverock:%d:%d:%d" % [cc.x, cc.y, placed_this_chunk.size()]
			_cave_rock_positions[cc][env_id] = world_pos
			_spawn_cave_rock(env_id, world_pos)
			break

func _spawn_cave_rock(env_id: String, world_pos: Vector2) -> void:
	if _cave_active_rocks.has(env_id):
		return
	var scene_node: Node = get_tree().root.get_node_or_null("Scene")
	if not scene_node:
		return
	var rock: Node = _packed_cave_rock_scene.instantiate()
	rock.global_position = world_pos
	rock.set_meta("env_id", env_id)
	scene_node.add_child(rock)
	_cave_active_rocks[env_id] = rock

func _despawn_cave_rocks_for_chunk(cc: Vector2i) -> void:
	if not _cave_rock_positions.has(cc):
		return
	for env_id: String in _cave_rock_positions[cc]:
		if _cave_active_rocks.has(env_id):
			var rock: Node = _cave_active_rocks[env_id]
			if is_instance_valid(rock):
				rock.queue_free()
			_cave_active_rocks.erase(env_id)

func _spawn_cave_exit() -> void:
	if _cave_exit or not _packed_cave_exit_scene:
		return
	var scene_node: Node = get_tree().root.get_node_or_null("Scene")
	if not scene_node:
		return
	var world_pos: Vector2 = _tile_to_world_center(_cave_exit_tile)
	_cave_exit = _packed_cave_exit_scene.instantiate()
	_cave_exit.name = "LinkedCaveExit"
	_cave_exit.global_position = world_pos
	_cave_exit.set_meta("linked_overworld_tile", _cave_entrance_tile)
	_cave_exit.set_meta("cave_room_tile", _cave_exit_tile)
	scene_node.add_child(_cave_exit)

func _despawn_cave_exit() -> void:
	if _cave_exit and is_instance_valid(_cave_exit):
		_cave_exit.queue_free()
	_cave_exit = null

func _find_linked_overworld_entrance_tile(player_pos: Vector2) -> Vector2i:
	if not _world_gen:
		return Vector2i(0, 0)
	var best_pos: Vector2 = player_pos
	var best_dist_sq: float = INF
	if _env_spawner and _env_spawner.get("_cave_positions") != null:
		for cave_pos: Vector2 in _env_spawner._cave_positions.values():
			var dist_sq: float = player_pos.distance_squared_to(cave_pos)
			if dist_sq < best_dist_sq:
				best_dist_sq = dist_sq
				best_pos = cave_pos
	return _world_gen.world_to_tile(best_pos)

func _cave_chunk_seed(cc: Vector2i, kind: String) -> int:
	var kind_key: int = 7 if kind == "rock" else 0
	return abs(world_seed ^ (cc.x * 374761393) ^ (cc.y * 1234567891) ^ (kind_key * 7919) ^ 99991)

func world_to_tile(world_pos: Vector2) -> Vector2i:
	if _tilemap:
		return _tilemap.local_to_map(_tilemap.to_local(world_pos))
	return Vector2i(floori(world_pos.x / 64), floori(world_pos.y / 64))

func is_tile_solid(world_pos: Vector2) -> bool:
	if not _active:
		return false
	var tc: Vector2i = world_to_tile(world_pos)
	if not _carved_tiles.has(tc):
		return true
	if _wall_tiles.has(tc):
		return true
	if _locked_wall_tiles.has(tc):
		return true
	return false

func _tile_to_world_center(tile: Vector2i) -> Vector2:
	if _tilemap:
		return _tilemap.to_global(_tilemap.map_to_local(tile))
	return Vector2(tile) * 64.0 + Vector2(32.0, 32.0)

func _get_tile_pixel_size() -> Vector2:
	if _tilemap and _tilemap.tile_set:
		return Vector2(_tilemap.tile_set.tile_size)
	return Vector2(64.0, 64.0)

func tile_to_chunk(tc: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(tc.x) / float(chunk_size_tiles)),
		floori(float(tc.y) / float(chunk_size_tiles)))

func chunk_to_start_tile(cc: Vector2i) -> Vector2i:
	return Vector2i(cc.x * chunk_size_tiles, cc.y * chunk_size_tiles)

func is_chunk_loaded(cc: Vector2i) -> bool:
	return loaded_chunks.has(cc)

func _find_tile_sources() -> void:
	cave_source_id = -1
	water_source_id = -1
	if not _tilemap or not _tilemap.tile_set:
		push_error("CaveWorldGen: TileMap or TileSet missing")
		return
	var ts: TileSet = _tilemap.tile_set
	var want_cave: String = cave_source_name.strip_edges().to_lower()
	var want_water: String = water_source_name.strip_edges().to_lower()
	for i: int in ts.get_source_count():
		var sid: int = ts.get_source_id(i)
		var src: TileSetSource = ts.get_source(sid)
		if not src:
			continue
		var n: String = src.resource_name.strip_edges().to_lower()
		if n == want_cave and cave_source_id == -1:
			cave_source_id = sid
		if n == want_water and water_source_id == -1:
			water_source_id = sid
	if cave_source_id == -1:
		for i: int in ts.get_source_count():
			if ts.get_source_id(i) == cave_source_fallback_id:
				cave_source_id = ts.get_source_id(i)
				break
	if water_source_id == -1:
		for i: int in ts.get_source_count():
			if ts.get_source_id(i) == water_source_fallback_id:
				water_source_id = ts.get_source_id(i)
				break
	if water_source_id == -1 and cave_source_id != -1:
		push_warning("CaveWorldGen: water source not found, using cave as fallback")
		water_source_id = cave_source_id
	if cave_source_id == -1:
		push_error("CaveWorldGen: Could not find cave tile source '%s'" % cave_source_name)

func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()

func _check_locked_rooms_clear() -> void:
	for room: RoomData in _rooms:
		if not room.is_locked or room.is_cleared:
			continue
		if room.spawned_enemy_ids.is_empty():
			continue
		var remaining: int = 0
		for enemy_id: int in room.spawned_enemy_ids:
			var enemy: Node = _find_night_enemy(enemy_id)
			if enemy and is_instance_valid(enemy):
				if "state" in enemy:
					var state_value: Variant = enemy.get("state")
					if int(state_value) != 5:
						remaining += 1
				else:
					remaining += 1
		room.enemy_count = remaining
		if remaining <= 0:
			_unlock_room(room)

func _enemy_count_for_room(room: RoomData) -> int:
	var count: int = combat_enemy_base_count + int(room.tile_size / 12) * combat_enemy_count_per_12_tiles
	match room.room_type:
		RoomType.NOVICE_FIGHT:
			count += novice_fight_bonus_enemies
		RoomType.BASIC_FIGHT:
			count += basic_fight_bonus_enemies
		RoomType.BOSS:
			count += boss_room_bonus_enemies
		_:
			count = 0
	return max(0, count)

func _spawn_room_enemies(room: RoomData, spawn_positions: Array) -> void:
	if not _is_host():
		return
	var animal_spawner: Node = get_tree().root.get_node_or_null("AnimalSpawner")
	if not animal_spawner:
		room.enemy_count = 0
		return
	if room.room_type == RoomType.BOSS:
		var center: Vector2 = Vector2.ZERO
		if not spawn_positions.is_empty():
			var sum: Vector2 = Vector2.ZERO
			for p: Variant in spawn_positions:
				if p is Vector2:
					sum += p
			center = sum / spawn_positions.size()
		var boss: Node = animal_spawner.spawn_combat_boss(center, room.id)
		if boss and is_instance_valid(boss):
			room.spawned_enemy_ids.append(int(boss.get("enemy_id")))
			room.enemy_count = 1
		else:
			room.enemy_count = 0
		return
	if not animal_spawner.has_method("spawn_combat_night_enemy"):
		room.enemy_count = 0
		return
	var selected_positions: Array[Vector2] = _pick_enemy_spawn_positions(room, spawn_positions, room.enemy_count)
	room.enemy_count = selected_positions.size()
	for spawn_pos: Vector2 in selected_positions:
		var enemy: Node = animal_spawner.spawn_combat_night_enemy(spawn_pos, room.id)
		if enemy and is_instance_valid(enemy):
			room.spawned_enemy_ids.append(int(enemy.get("enemy_id")))

func _pick_enemy_spawn_positions(room: RoomData, spawn_positions: Array, count: int) -> Array[Vector2]:
	var selected: Array[Vector2] = []
	if count <= 0 or spawn_positions.is_empty():
		return selected
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = abs(world_seed ^ (room.id * 9176) ^ 0x51515)
	var pool: Array[Vector2] = []
	for pos: Variant in spawn_positions:
		if pos is Vector2:
			pool.append(pos)
	for i: int in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var tmp: Vector2 = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	for pos: Vector2 in pool:
		if selected.size() >= count:
			break
		if not _is_spawn_position_clear(pos):
			continue
		var too_close: bool = false
		for existing: Vector2 in selected:
			if existing.distance_to(pos) < combat_spawn_min_separation:
				too_close = true
				break
		if too_close:
			continue
		selected.append(pos)
	return selected

func _is_spawn_position_clear(pos: Vector2) -> bool:
	var tc: Vector2i = world_to_tile(pos)
	if not _carved_tiles.has(tc):
		return false
	if _wall_tiles.has(tc):
		return false
	if _locked_wall_tiles.has(tc):
		return false
	if _water_tiles.has(tc):
		return false
	if _door_tile_data.has(tc):
		return false
	var scene_node: Node = get_tree().root.get_node_or_null("Scene")
	if not scene_node:
		return true
	var space: PhysicsDirectSpaceState2D = scene_node.get_world_2d().direct_space_state
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 14.0
	query.shape = shape
	query.transform = Transform2D(0, pos)
	query.collision_mask = 1
	return space.intersect_shape(query).is_empty()

func _find_night_enemy(enemy_id: int) -> Node:
	for enemy: Node in get_tree().get_nodes_in_group("night_enemies"):
		if is_instance_valid(enemy) and int(enemy.get("enemy_id")) == enemy_id:
			return enemy
	for boss: Node in get_tree().get_nodes_in_group("bosses"):
		if is_instance_valid(boss) and int(boss.get("enemy_id")) == enemy_id:
			return boss
	return null
