extends Node2D

enum State { PASSIVE, CHASE, CHARGING, DASHING, COOLDOWN, DEAD }

@export var enemy_id: int = -1
@export var speed: float = 170.0
@export var health: int = 10
@export var attack_damage: int = 1
@export var attack_range: float = 200.0
@export var attack_cooldown_max: float = 3.5
@export var charge_time: float = 1.2
@export var dash_speed: float = 520.0
@export var dash_duration: float = 0.32
@export var dash_hit_radius: float = 44.0
@export var post_attack_cooldown: float = 0.9
@export var despawn_when_day: bool = true
@export var detection_radius: float = 650.0
@export var path_step_size: int = 2
@export var path_replan_interval: float = 0.4
@export var cave_path_replan_interval: float = 1.1
@export var sense_interval: float = 0.25
@export var physics_check_interval: float = 0.12

var drowning_timer: float = 0.0
var drowning_dead: bool = false
const DROWN_TIME: float = 5.0
const DROWN_SINK_PIXELS: float = 14.0
var _base_sprite_position: Vector2
var _base_speed: float

var state: State = State.PASSIVE
var attack_cooldown: float = 0.0
var charge_timer: float = 0.0
var dash_timer: float = 0.0
var dash_direction: Vector2 = Vector2.ZERO
var dash_origin: Vector2 = Vector2.ZERO
var _blocked_escape_timer: float = 0.0
var rng := RandomNumberGenerator.new()

var _path: Array = []
var _path_timer: float = 0.0
var _wander_target: Vector2 = Vector2.ZERO
var _wander_idle_timer: float = 0.0
var _passive_stuck_timer: float = 0.0
var _sense_timer: float = 0.0
var _physics_timer: float = 0.0
var _cached_target: CharacterBody2D = null
var _cached_position_clear: Dictionary = {}
var _cached_enemies: Array = []
var _enemies_cache_timer: float = 0.0
const ENEMIES_CACHE_INTERVAL: float = 0.5

var _cave_gen: Node = null
var _weather: Node = null
var _world_gen: Node = null
var _scene_node: Node = null
var _tilemap: Node = null

const PREFERRED_DISTANCE: float = 72.0
const BLOCKED_ESCAPE_TIME: float = 1.0
const ESCAPE_SEARCH_RADIUS: float = 120.0
const ESCAPE_ATTEMPTS: int = 12
const SEPARATION_RADIUS: float = 52.0
const SEPARATION_FORCE: float = 600.0
const PATH_NODE_REACH_DIST: float = 24.0
const PASSIVE_WANDER_RANGE: float = 160.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var staticbody: StaticBody2D = $StaticBody2D

func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()

func _ready() -> void:
	rng.randomize()
	_base_speed = speed
	z_index = 2
	add_to_group("night_enemies")
	sprite.position.y = -30
	_base_sprite_position = sprite.position
	staticbody.position.y = -6
	sprite.play("walk_down")
	attack_cooldown = rng.randf_range(0.5, attack_cooldown_max)
	_pick_passive_wander_target()
	_cave_gen = get_tree().root.get_node_or_null("Scene/CaveWorldGen")
	_weather = get_tree().root.get_node_or_null("Scene/Weather")
	_world_gen = get_tree().root.get_node_or_null("Scene/WorldGen")
	_scene_node = get_tree().root.get_node_or_null("Scene")
	_tilemap = get_tree().root.get_node_or_null("Scene/TileMap")

func _process(delta: float) -> void:
	_update_drowning(delta)
	if state == State.DEAD:
		return
	if not _is_host():
		return
	if despawn_when_day and not _is_in_cave() and not _is_night():
		_die(false)
		return

	attack_cooldown = max(attack_cooldown - delta, 0.0)

	_enemies_cache_timer -= delta
	if _enemies_cache_timer <= 0.0:
		_enemies_cache_timer = ENEMIES_CACHE_INTERVAL
		_cached_enemies = get_tree().get_nodes_in_group("night_enemies")

	_physics_timer -= delta
	if _physics_timer <= 0.0:
		_physics_timer = physics_check_interval
		_cached_position_clear.clear()
		_resolve_overlap()
		_apply_separation(delta)

	_sense_timer -= delta
	if _sense_timer <= 0.0 or not is_instance_valid(_cached_target):
		_sense_timer = sense_interval
		_cached_target = _get_nearest_player()
	var target := _cached_target

	match state:
		State.PASSIVE:
			_do_passive(delta, target)

		State.CHASE:
			if not target:
				state = State.PASSIVE
				_pick_passive_wander_target()
				return
			if target.global_position.distance_to(global_position) > detection_radius * 1.5:
				state = State.PASSIVE
				_path.clear()
				_pick_passive_wander_target()
				return
			if attack_cooldown <= 0.0 and global_position.distance_to(target.global_position) <= attack_range:
				_begin_charge(target)
			else:
				_path_timer -= delta
				if _path_timer <= 0.0 or _path.is_empty():
					_path_timer = cave_path_replan_interval if _is_in_cave() else path_replan_interval
					_path = _build_path_to(target.global_position)
					if _path.is_empty():
						state = State.PASSIVE
						_pick_passive_wander_target()
						return
				_follow_path(delta)

		State.CHARGING:
			if not target:
				state = State.PASSIVE
				return
			sprite.play("idle")
			charge_timer += delta
			var pct: float = clamp(charge_timer / charge_time, 0.0, 1.0)
			_set_charge_glow(pct)
			if multiplayer.has_multiplayer_peer():
				_sync_charge_glow_rpc.rpc(pct)
			if charge_timer >= charge_time:
				dash_direction = (target.global_position - global_position).normalized()
				_begin_dash()

		State.DASHING:
			if not target:
				_on_dash_miss()
				return
			dash_timer += delta
			var step := dash_direction * dash_speed * delta
			var next_pos := global_position + step
			if not _is_position_clear_for_dash(next_pos):
				_on_dash_miss()
				return
			global_position = next_pos
			if global_position.distance_to(target.global_position) <= dash_hit_radius:
				_on_dash_hit(target)
				return
			if dash_timer >= dash_duration:
				_on_dash_miss()

		State.COOLDOWN:
			pass

	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		if is_inside_tree() and get_meta("sync_ready", false):
			if _scene_node:
				_scene_node.sync_enemy_state_rpc.rpc(enemy_id, global_position.x, global_position.y, int(state), health)

func _do_passive(delta: float, target: CharacterBody2D) -> void:
	if target and global_position.distance_to(target.global_position) <= detection_radius:
		state = State.CHASE
		_path.clear()
		_path_timer = 0.0
		return

	_wander_idle_timer -= delta
	if _wander_idle_timer > 0.0:
		sprite.play("idle")
		return

	if global_position.distance_to(_wander_target) < 12.0:
		_wander_idle_timer = rng.randf_range(1.5, 4.0)
		_pick_passive_wander_target()
		return

	var dir := (_wander_target - global_position).normalized()
	var prev := global_position
	_try_move(dir * speed * 0.45 * delta)
	if global_position.distance_to(prev) < 0.01:
		_passive_stuck_timer += delta
		if _passive_stuck_timer > 0.5:
			_passive_stuck_timer = 0.0
			_pick_passive_wander_target()
	else:
		_passive_stuck_timer = 0.0
	sprite.play("walk_down")

func _pick_passive_wander_target() -> void:
	for _attempt in 10:
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(40.0, PASSIVE_WANDER_RANGE)
		var candidate := global_position + Vector2(cos(angle), sin(angle)) * dist
		if _is_position_clear(candidate):
			_wander_target = candidate
			return
	_wander_target = global_position

func _follow_path(delta: float) -> void:
	if _path.is_empty():
		return
	var next_point: Vector2 = _path[0]
	var to_next := next_point - global_position
	if to_next.length() < PATH_NODE_REACH_DIST:
		_path.pop_front()
		if _path.is_empty():
			return
		next_point = _path[0]
		to_next = next_point - global_position
	var dir := to_next.normalized()
	_try_move(dir * speed * delta)
	sprite.play("walk_down")

func _build_path_to(target_pos: Vector2) -> Array:
	if _cave_gen and is_instance_valid(_cave_gen) and _cave_gen.get("in_cave") and _cave_gen._reachable_tiles.size() > 0:
		if _path_segment_clear(global_position, target_pos):
			return _steer_path(target_pos)
		return _astar_cave(target_pos, _cave_gen)
	return _steer_path(target_pos)

func _astar_cave(target_pos: Vector2, cave_gen: Node) -> Array:
	if not _tilemap or not is_instance_valid(_tilemap):
		_tilemap = get_tree().root.get_node_or_null("Scene/TileMap")
		if not _tilemap:
			return _steer_path(target_pos)

	var start_tc: Vector2i = cave_gen.world_to_tile(global_position)
	var goal_tc: Vector2i = cave_gen.world_to_tile(target_pos)

	if not cave_gen._reachable_tiles.has(goal_tc):
		return []

	var dirs := [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
	]

	var came_from: Dictionary = {}
	var g_score: Dictionary = {}

	g_score[start_tc] = 0.0
	var start_h: float = start_tc.distance_to(goal_tc)

	var heap: Array = [[start_h, start_tc]]
	var closed: Dictionary = {}

	var iterations := 0
	var max_iterations := 420

	while not heap.is_empty() and iterations < max_iterations:
		iterations += 1

		var current_entry: Array = heap[0]
		heap[0] = heap[heap.size() - 1]
		heap.resize(heap.size() - 1)
		_heap_sift_down(heap, 0)

		var current: Vector2i = current_entry[1]

		if closed.has(current):
			continue
		closed[current] = true

		if current == goal_tc:
			var world_path: Array = []
			var node := goal_tc
			while came_from.has(node):
				world_path.push_front(_tilemap.to_global(_tilemap.map_to_local(node)))
				node = came_from[node]
			return _simplify_path(world_path)

		var cur_g: float = g_score.get(current, INF)

		for dir in dirs:
			var neighbor: Vector2i = current + dir * path_step_size
			if closed.has(neighbor):
				continue
			if not cave_gen._reachable_tiles.has(neighbor):
				continue
			if cave_gen._biome_for_tile(neighbor) == cave_gen.BiomeType.WATER_LAKE:
				continue
			var step_cost: float = 1.0 if (dir.x == 0 or dir.y == 0) else 1.414
			var tentative_g: float = cur_g + step_cost * path_step_size
			if tentative_g < g_score.get(neighbor, INF):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				var f: float = tentative_g + neighbor.distance_to(goal_tc)
				_heap_push(heap, [f, neighbor])

	return []

func _heap_push(heap: Array, entry: Array) -> void:
	heap.append(entry)
	var i: int = heap.size() - 1
	while i > 0:
		var parent: int = (i - 1) / 2
		if heap[parent][0] <= heap[i][0]:
			break
		var tmp = heap[parent]
		heap[parent] = heap[i]
		heap[i] = tmp
		i = parent

func _heap_sift_down(heap: Array, i: int) -> void:
	var size: int = heap.size()
	while true:
		var smallest: int = i
		var left: int = 2 * i + 1
		var right: int = 2 * i + 2
		if left < size and heap[left][0] < heap[smallest][0]:
			smallest = left
		if right < size and heap[right][0] < heap[smallest][0]:
			smallest = right
		if smallest == i:
			break
		var tmp = heap[smallest]
		heap[smallest] = heap[i]
		heap[i] = tmp
		i = smallest

func _steer_path(target_pos: Vector2) -> Array:
	var path: Array = []
	var steps := 12
	for i in steps:
		var t := float(i + 1) / float(steps)
		var point := global_position.lerp(target_pos, t)
		if not _is_position_clear(point):
			break
		path.append(point)
	return path

func _simplify_path(path: Array) -> Array:
	if path.size() <= 2:
		return path
	var simplified: Array = [path[0]]
	var i := 0
	while i < path.size() - 1:
		var j := path.size() - 1
		while j > i + 1:
			if _path_segment_clear(path[i], path[j]):
				break
			j -= 1
		simplified.append(path[j])
		i = j
	return simplified

func _path_segment_clear(from: Vector2, to: Vector2) -> bool:
	var dist: float = from.distance_to(to)
	var steps := int(dist / 24.0) + 1
	var inv_steps: float = 1.0 / float(steps)
	for i in range(1, steps + 1):
		if not _is_position_clear(from.lerp(to, i * inv_steps)):
			return false
	return true

func _begin_charge(target: CharacterBody2D) -> void:
	state = State.CHARGING
	charge_timer = 0.0
	sprite.play("idle")

func _begin_dash() -> void:
	state = State.DASHING
	dash_timer = 0.0
	dash_origin = global_position
	_clear_charge_glow()
	if multiplayer.has_multiplayer_peer():
		_sync_begin_dash_rpc.rpc(dash_direction.x, dash_direction.y)

func _on_dash_hit(target: CharacterBody2D) -> void:
	state = State.COOLDOWN
	attack_cooldown = attack_cooldown_max
	dash_timer = 0.0
	if multiplayer.has_multiplayer_peer():
		var target_id := target.name.to_int()
		if _scene_node:
			_scene_node.enemy_attack_player.rpc_id(target_id, attack_damage, enemy_id)
	else:
		if target.has_method("defend_enemy_attack"):
			target.defend_enemy_attack(attack_damage, self)
		else:
			target.take_damage(attack_damage)
	if multiplayer.has_multiplayer_peer():
		_sync_flash_hit_rpc.rpc()
	else:
		_flash_hit()
	await get_tree().create_timer(post_attack_cooldown).timeout
	if state != State.DEAD:
		state = State.CHASE
		_reset_visuals()

func _on_dash_miss() -> void:
	state = State.COOLDOWN
	attack_cooldown = attack_cooldown_max * 0.5
	dash_timer = 0.0
	if multiplayer.has_multiplayer_peer():
		_sync_dash_miss_rpc.rpc()
	else:
		_play_miss_stumble()
	await get_tree().create_timer(post_attack_cooldown).timeout
	if state != State.DEAD:
		state = State.CHASE
		_reset_visuals()

func _play_miss_stumble() -> void:
	sprite.modulate = Color(1, 0.3, 0.3, 1.0)
	await get_tree().create_timer(0.25).timeout
	if state != State.DEAD:
		_reset_visuals()

func _reset_visuals() -> void:
	sprite.modulate = Color(1, 1, 1, 1)

func _apply_separation(delta: float) -> void:
	for other in _cached_enemies:
		if other == self or not is_instance_valid(other):
			continue
		var diff := global_position - (other as Node2D).global_position
		var dist := diff.length()
		if dist < SEPARATION_RADIUS and dist > 0.01:
			var push := diff.normalized() * SEPARATION_FORCE * delta
			global_position += push
			(other as Node2D).global_position -= push

func _is_position_clear_for_dash(pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 10.0
	query.shape = shape
	query.transform = Transform2D(0, pos)
	query.collision_mask = 1
	query.exclude = [staticbody.get_rid()]
	for p in get_tree().get_nodes_in_group("players"):
		if p is CollisionObject2D:
			query.exclude.append(p.get_rid())
	for enemy in _cached_enemies:
		if enemy == self or not is_instance_valid(enemy):
			continue
		if enemy.get("staticbody") != null and is_instance_valid(enemy.staticbody):
			query.exclude.append((enemy.staticbody as CollisionObject2D).get_rid())
	var hits := space.intersect_shape(query)
	return hits.size() == 0

func _resolve_overlap() -> void:
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 10.0
	query.shape = shape
	query.transform = Transform2D(0, global_position)
	query.collision_mask = 1
	query.exclude = [staticbody.get_rid()]
	for p in get_tree().get_nodes_in_group("players"):
		if p is CollisionObject2D:
			query.exclude.append(p.get_rid())
	for enemy in _cached_enemies:
		if enemy == self or not is_instance_valid(enemy):
			continue
		if enemy.get("staticbody") != null and is_instance_valid(enemy.staticbody):
			query.exclude.append((enemy.staticbody as CollisionObject2D).get_rid())
	var hits := space.intersect_shape(query, 4)
	for hit in hits:
		var collider = hit["collider"]
		if collider == staticbody:
			continue
		var other_pos: Vector2 = collider.global_position
		var push_dir := global_position - other_pos
		if push_dir.length() < 0.01:
			push_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1))
		global_position += push_dir.normalized() * 4.0

func _set_charge_glow(pct: float) -> void:
	sprite.modulate = Color(0.55, 0.1, 0.1, 1.0).lerp(Color(1.0, 1.0, 0.0, 1.0), pct)

func _clear_charge_glow() -> void:
	_reset_visuals()

func take_damage(amount: int) -> void:
	if state == State.DEAD:
		return
	if not _is_host():
		return
	health -= amount
	if state == State.PASSIVE:
		state = State.CHASE
	if multiplayer.has_multiplayer_peer():
		_sync_flash_hit_rpc.rpc()
	else:
		_flash_hit()
	if health <= 0:
		_die()

func _die(drop_loot: bool = true) -> void:
	if state == State.DEAD:
		return
	if drop_loot:
		_drop_string()
	if multiplayer.has_multiplayer_peer():
		_sync_die_rpc.rpc()
	else:
		_play_die_sequence()

func _drop_string() -> void:
	if not _is_host():
		return
	if not _scene_node or not _scene_node.has_method("host_spawn_floor_item"):
		return
	var drop_count := rng.randi_range(1, 2)
	for i in drop_count:
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(18.0, 44.0)
		var drop_pos := global_position + Vector2(cos(angle), sin(angle)) * radius
		_scene_node.host_spawn_floor_item(drop_pos, "String", 1)

func _flash_hit() -> void:
	sprite.modulate = Color(1, 0.1, 0.1, 1)
	await get_tree().create_timer(0.08).timeout
	if state != State.DEAD:
		_reset_visuals()

func _play_die_sequence() -> void:
	state = State.DEAD
	sprite.modulate = Color(1, 0.1, 0.1, 1)
	var tween = create_tween()
	tween.tween_property(sprite, "scale", Vector2(0.1, 0.1), 0.35)
	tween.parallel().tween_property(sprite, "modulate", Color(1, 0.1, 0.1, 0), 0.35)
	await tween.finished
	queue_free()

func _get_nearest_player() -> CharacterBody2D:
	var nearest: CharacterBody2D = null
	var nearest_dist := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p is CharacterBody2D and is_instance_valid(p):
			var d := global_position.distance_to(p.global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest = p
	return nearest

func _is_night() -> bool:
	if not _weather or not is_instance_valid(_weather):
		return true
	return not _weather.has_method("is_night") or _weather.is_night()

func _is_in_cave() -> bool:
	return _cave_gen != null and is_instance_valid(_cave_gen) and _cave_gen.get("in_cave")

func _try_move(delta: Vector2) -> void:
	if delta.length() <= 0.001:
		return
	var target = global_position + delta
	if _is_position_clear(target):
		global_position = target
		_blocked_escape_timer = 0.0
		return
	_blocked_escape_timer += get_process_delta_time()
	var slide_dirs = [
		Vector2(delta.x, 0),
		Vector2(0, delta.y),
		Vector2(-delta.y, delta.x).normalized() * delta.length(),
		Vector2(delta.y, -delta.x).normalized() * delta.length()
	]
	for slide in slide_dirs:
		if slide.length() <= 0.001:
			continue
		var slide_target = global_position + slide
		if _is_position_clear(slide_target):
			global_position = slide_target
			_blocked_escape_timer = 0.0
			return
	if _blocked_escape_timer >= BLOCKED_ESCAPE_TIME:
		_escape_from_blocked_position()
		_blocked_escape_timer = 0.0

func _is_position_clear(pos: Vector2) -> bool:
	var key := Vector2i(floori(pos.x / 16.0), floori(pos.y / 16.0))
	if _cached_position_clear.has(key):
		return _cached_position_clear[key]
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 10.0
	query.shape = shape
	query.transform = Transform2D(0, pos)
	query.collision_mask = 1
	query.exclude = [staticbody.get_rid()]
	for p in get_tree().get_nodes_in_group("players"):
		if p is CollisionObject2D:
			query.exclude.append(p.get_rid())
	var hits := space.intersect_shape(query)
	for hit in hits:
		if hit["collider"] != staticbody:
			_cached_position_clear[key] = false
			return false
	_cached_position_clear[key] = true
	return true

func _escape_from_blocked_position() -> bool:
	for i in ESCAPE_ATTEMPTS:
		var angle = rng.randf_range(0.0, TAU)
		var dist = rng.randf_range(36.0, ESCAPE_SEARCH_RADIUS)
		var candidate = global_position + Vector2(cos(angle), sin(angle)) * dist
		if _is_position_clear(candidate):
			global_position = candidate
			return true
	return false

func _update_drowning(delta: float) -> void:
	if state == State.DEAD:
		return
	if not _is_host():
		return
	var in_water := _is_current_world_water()
	if in_water:
		drowning_timer += delta
		speed = lerp(speed, 80.0, delta * 2.0)
	else:
		drowning_timer = max(drowning_timer - delta * 2.0, 0.0)
		speed = lerp(speed, _base_speed, delta * 2.0)
	var drown_pct: float = clamp(drowning_timer / DROWN_TIME, 0.0, 1.0)
	sprite.position = _base_sprite_position + Vector2(0, DROWN_SINK_PIXELS * drown_pct)
	if drowning_timer >= DROWN_TIME and not drowning_dead:
		drowning_dead = true
		take_damage(9999)
	elif drowning_timer <= 0.0:
		drowning_dead = false

func _is_current_world_water() -> bool:
	if _cave_gen and is_instance_valid(_cave_gen) and _cave_gen.get("in_cave"):
		var tc: Vector2i = _cave_gen.world_to_tile(global_position)
		if not _cave_gen._reachable_tiles.has(tc):
			return false
		return _cave_gen._biome_for_tile(tc) == _cave_gen.BiomeType.WATER_LAKE
	return _world_gen != null and is_instance_valid(_world_gen) and _world_gen.has_method("is_water_at") and _world_gen.is_water_at(global_position)

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_charge_glow_rpc(pct: float) -> void:
	_set_charge_glow(pct)

@rpc("authority", "call_remote", "reliable")
func _sync_begin_dash_rpc(dir_x: float, dir_y: float) -> void:
	dash_direction = Vector2(dir_x, dir_y)
	dash_timer = 0.0
	_clear_charge_glow()
	sprite.play("idle")

@rpc("authority", "call_remote", "reliable")
func _sync_dash_miss_rpc() -> void:
	_play_miss_stumble()

@rpc("authority", "call_local", "reliable")
func _sync_flash_hit_rpc() -> void:
	_flash_hit()

@rpc("authority", "call_local", "reliable")
func _sync_die_rpc() -> void:
	_play_die_sequence()
