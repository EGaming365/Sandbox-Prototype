# Night enemy.
# A hostile creature that waits until a player comes close, chases them with pathfinding, charges up and then dashes at them to deal damage.
# The host controls the enemy and the other players receive its state. Enemies disappear at day and in water they slowly drown.

extends Node2D

# The enemy's behaviours: waiting, chasing, charging up, dashing, recovering and dead.
enum State { PASSIVE, CHASE, CHARGING, DASHING, COOLDOWN, DEAD }

# ID that lets every player refer to the same enemy.
@export var enemy_id: int = -1
# Walking speed in pixels per second.
@export var speed: float = 170.0
# Health points. It dies when they reach zero.
@export var health: int = 10
# Damage dealt by a successful dash.
@export var attack_damage: int = 1
# Distance at which the enemy starts charging an attack.
@export var attack_range: float = 200.0
# Seconds to recover after a dash that hit.
@export var attack_cooldown_max: float = 3.5
# Seconds spent charging before a dash.
@export var charge_time: float = 1.2
# Speed of the dash.
@export var dash_speed: float = 520.0
# Seconds a dash lasts.
@export var dash_duration: float = 0.32
# Distance within which a dash hits a player.
@export var dash_hit_radius: float = 44.0
# Extra pause after an attack.
@export var post_attack_cooldown: float = 0.9
# If true the enemy disappears when the day begins.
@export var despawn_when_day: bool = true
# Distance at which the enemy notices a player.
@export var detection_radius: float = 650.0
# Grid step size used when planning a path.
@export var path_step_size: int = 2
# Seconds between new paths on the surface.
@export var path_replan_interval: float = 0.4
# Seconds between new paths in the cave, which are slower to calculate.
@export var cave_path_replan_interval: float = 1.1
# Seconds between looking for the nearest player.
@export var sense_interval: float = 0.25
# Seconds between checks for being stuck inside something solid.
@export var physics_check_interval: float = 0.12

# Seconds spent in water.
var drowning_timer: float = 0.0
# True once the enemy has drowned, so it only dies once.
var drowning_dead: bool = false
# Seconds in water before the enemy drowns.
const DROWN_TIME: float = 5.0
# How far the sprite sinks while drowning.
const DROWN_SINK_PIXELS: float = 14.0
# The sprite's normal position, restored after sinking.
var _base_sprite_position: Vector2
# The normal speed, restored after slowing in water.
var _base_speed: float

# The behaviour the enemy is currently in.
var state: State = State.PASSIVE
# Seconds until the enemy can attack again.
var attack_cooldown: float = 0.0
# Seconds spent charging so far.
var charge_timer: float = 0.0
# Seconds spent dashing so far.
var dash_timer: float = 0.0
# Direction of the current dash.
var dash_direction: Vector2 = Vector2.ZERO
# Where the current dash started.
var dash_origin: Vector2 = Vector2.ZERO
# Seconds the enemy has been stuck.
var _blocked_escape_timer: float = 0.0
# Random number generator for this enemy.
var rng := RandomNumberGenerator.new()

# Points of the current path towards the target.
var _path: Array = []
# Seconds until a new path is planned.
var _path_timer: float = 0.0
# Spot the enemy is wandering to while waiting.
var _wander_target: Vector2 = Vector2.ZERO
# Seconds left standing still while waiting.
var _wander_idle_timer: float = 0.0
# Seconds stuck while wandering.
var _passive_stuck_timer: float = 0.0
# Seconds until the next search for a player.
var _sense_timer: float = 0.0
# Seconds until the next stuck check.
var _physics_timer: float = 0.0
# The player currently being chased.
var _cached_target: CharacterBody2D = null
# Remembers which small squares of the map are free, to save physics queries.
var _cached_position_clear: Dictionary = {}
# List of other enemies, used to keep enemies apart.
var _cached_enemies: Array = []
# Seconds until the list of enemies is refreshed.
var _enemies_cache_timer: float = 0.0
# Seconds between refreshing the list of enemies.
const ENEMIES_CACHE_INTERVAL: float = 0.5

# The cave generator, used to find paths in the cave.
var _cave_gen: Node = null
# The weather system, used to tell whether it is night.
var _weather: Node = null
# The overworld generator, used to check for water.
var _world_gen: Node = null
# The main scene, used for damage and drops.
var _scene_node: Node = null
# The tile map, used to convert tile positions to world positions.
var _tilemap: Node = null

# Distance the enemy tries to keep before charging.
const PREFERRED_DISTANCE: float = 72.0
# Seconds stuck before the enemy jumps to a free spot.
const BLOCKED_ESCAPE_TIME: float = 1.0
# Furthest distance to look for a free spot.
const ESCAPE_SEARCH_RADIUS: float = 120.0
# Number of random spots to try.
const ESCAPE_ATTEMPTS: int = 12
# Enemies closer than this push each other apart.
const SEPARATION_RADIUS: float = 52.0
# Strength of that push.
const SEPARATION_FORCE: float = 600.0
# How close the enemy must get to a path point before moving on to the next.
const PATH_NODE_REACH_DIST: float = 24.0
# How far the enemy wanders while waiting.
const PASSIVE_WANDER_RANGE: float = 160.0

# Animated picture of the enemy.
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
# Solid body that stops things walking through the enemy.
@onready var staticbody: StaticBody2D = $StaticBody2D


# Returns true for the host or in a single player game. Only the host controls the enemy.
func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


# Sets up the enemy, joins the night enemies group and finds the other systems it needs.
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


# Runs the enemy's behaviour each frame: senses players, moves, charges, dashes and syncs its state.
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
			if attack_cooldown <= 0.0 \
					and global_position.distance_to(target.global_position) <= attack_range:
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
				_scene_node.sync_enemy_state_rpc.rpc(
					enemy_id, global_position.x, global_position.y, int(state), health,
				)


# Waits and wanders until a player comes within detection range, then starts chasing.
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


# Chooses a clear spot nearby to wander to.
func _pick_passive_wander_target() -> void:
	for _attempt in 10:
		var angle := rng.randf_range(0.0, TAU)
		var distance := rng.randf_range(40.0, PASSIVE_WANDER_RANGE)
		var candidate := global_position + Vector2(cos(angle), sin(angle)) * distance
		if _is_position_clear(candidate):
			_wander_target = candidate
			return
	_wander_target = global_position


# Moves along the current path and drops points as it reaches them.
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


# Plans a path to the target. In the cave it uses A star search, otherwise it steers directly.
func _build_path_to(target_pos: Vector2) -> Array:
	if _cave_gen and is_instance_valid(_cave_gen) \
			and _cave_gen.get("in_cave") and _cave_gen._carved_tiles.size() > 0:
		if _path_segment_clear(global_position, target_pos):
			return _steer_path(target_pos)
		return _astar_cave(target_pos, _cave_gen)
	return _steer_path(target_pos)


# Finds a route through the carved cave tiles using A star search.
func _astar_cave(target_pos: Vector2, cave_gen: Node) -> Array:
	if not _tilemap or not is_instance_valid(_tilemap):
		_tilemap = get_tree().root.get_node_or_null("Scene/TileMap")
		if not _tilemap:
			return _steer_path(target_pos)

	var start_tc: Vector2i = cave_gen.world_to_tile(global_position)
	var goal_tc: Vector2i = cave_gen.world_to_tile(target_pos)

	if not cave_gen._carved_tiles.has(goal_tc):
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
			if not cave_gen._carved_tiles.has(neighbor):
				continue
			if cave_gen._water_tiles.has(neighbor):
				continue
			var step_cost: float = 1.0 if (dir.x == 0 or dir.y == 0) else 1.414
			var tentative_g: float = cur_g + step_cost * path_step_size
			if tentative_g < g_score.get(neighbor, INF):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				var f: float = tentative_g + neighbor.distance_to(goal_tc)
				_heap_push(heap, [f, neighbor])

	return []


# Adds an entry to the priority queue used by the search, keeping the lowest cost first.
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


# Restores the order of the priority queue after the first entry is removed.
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


# Creates a straight line path to the target made of evenly spaced points.
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


# Removes unnecessary points from a path where a straight line is clear.
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


# Returns true if a straight line between two points is free of obstacles.
func _path_segment_clear(from: Vector2, to: Vector2) -> bool:
	var distance: float = from.distance_to(to)
	var steps := int(distance / 24.0) + 1
	var inv_steps: float = 1.0 / float(steps)
	for i in range(1, steps + 1):
		if not _is_position_clear(from.lerp(to, i * inv_steps)):
			return false
	return true


# Starts charging an attack at the target.
func _begin_charge(target: CharacterBody2D) -> void:
	state = State.CHARGING
	charge_timer = 0.0
	sprite.play("idle")


# Starts the dash and tells the other players.
func _begin_dash() -> void:
	state = State.DASHING
	dash_timer = 0.0
	dash_origin = global_position
	_clear_charge_glow()
	if multiplayer.has_multiplayer_peer():
		_sync_begin_dash_rpc.rpc(dash_direction.x, dash_direction.y)


# The dash reached a player, so damage them and recover.
func _on_dash_hit(target: CharacterBody2D) -> void:
	state = State.COOLDOWN
	attack_cooldown = attack_cooldown_max
	dash_timer = 0.0
	if _scene_node and _scene_node.has_method("apply_damage_to_player"):
		_scene_node.apply_damage_to_player(target, attack_damage, self)
	elif target.has_method("defend_enemy_attack"):
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


# The dash missed, so recover for a shorter time and tell the other players.
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


# Briefly tints the enemy red to show the miss.
func _play_miss_stumble() -> void:
	sprite.modulate = Color(1, 0.3, 0.3, 1.0)
	await get_tree().create_timer(0.25).timeout
	if state != State.DEAD:
		_reset_visuals()


# Returns the enemy to its normal colour.
func _reset_visuals() -> void:
	sprite.modulate = Color(1, 1, 1, 1)


# Pushes the enemy away from other enemies that are too close.
func _apply_separation(delta: float) -> void:
	for other in _cached_enemies:
		if other == self or not is_instance_valid(other):
			continue
		var offset_to_other := global_position - (other as Node2D).global_position
		var distance := offset_to_other.length()
		if distance < SEPARATION_RADIUS and distance > 0.01:
			var push := offset_to_other.normalized() * SEPARATION_FORCE * delta
			global_position += push
			(other as Node2D).global_position -= push


# Returns true if the position is free for a dash, using a small circle physics test.
# Returns true if a small circle at the position touches nothing solid. Results are remembered to save work.
func _is_position_clear_for_dash(world_position: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 10.0
	query.shape = shape
	query.transform = Transform2D(0, world_position)
	query.collision_mask = 1
	query.exclude = [staticbody.get_rid()]
	for player_node in get_tree().get_nodes_in_group("players"):
		if player_node is CollisionObject2D:
			query.exclude.append(player_node.get_rid())
	for enemy in _cached_enemies:
		if enemy == self or not is_instance_valid(enemy):
			continue
		if enemy.get("staticbody") != null and is_instance_valid(enemy.staticbody):
			query.exclude.append((enemy.staticbody as CollisionObject2D).get_rid())
	var hits := space.intersect_shape(query)
	return hits.size() == 0


# Moves the enemy out of solid objects it has become stuck in.
func _resolve_overlap() -> void:
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 10.0
	query.shape = shape
	query.transform = Transform2D(0, global_position)
	query.collision_mask = 1
	query.exclude = [staticbody.get_rid()]
	for player_node in get_tree().get_nodes_in_group("players"):
		if player_node is CollisionObject2D:
			query.exclude.append(player_node.get_rid())
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


# Colours the enemy from dark red to yellow as its charge builds.
func _set_charge_glow(pct: float) -> void:
	sprite.modulate = Color(0.55, 0.1, 0.1, 1.0).lerp(Color(1.0, 1.0, 0.0, 1.0), pct)


# Removes the charge colour.
func _clear_charge_glow() -> void:
	_reset_visuals()


# Reduces the enemy's health, flashes it and kills it at zero. Only the host does this.
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


# Ends the enemy's life on every player's game, optionally dropping loot.
func _die(drop_loot: bool = true) -> void:
	if state == State.DEAD:
		return
	if drop_loot:
		_drop_string()
	if multiplayer.has_multiplayer_peer():
		_sync_die_rpc.rpc()
	else:
		_play_die_sequence()


# Drops one or two pieces of string where the enemy died.
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


# Flashes the enemy red.
func _flash_hit() -> void:
	sprite.modulate = Color(1, 0.1, 0.1, 1)
	await get_tree().create_timer(0.08).timeout
	if state != State.DEAD:
		_reset_visuals()


# Shrinks and fades the enemy, then removes it.
func _play_die_sequence() -> void:
	state = State.DEAD
	sprite.modulate = Color(1, 0.1, 0.1, 1)
	var tween = create_tween()
	tween.tween_property(sprite, "scale", Vector2(0.1, 0.1), 0.35)
	tween.parallel().tween_property(sprite, "modulate", Color(1, 0.1, 0.1, 0), 0.35)
	await tween.finished
	queue_free()


# Returns the closest player, or null.
func _get_nearest_player() -> CharacterBody2D:
	var nearest: CharacterBody2D = null
	var nearest_dist := INF
	for player_node in get_tree().get_nodes_in_group("players"):
		if player_node is CharacterBody2D and is_instance_valid(player_node):
			var player_distance := global_position.distance_to(player_node.global_position)
			if player_distance < nearest_dist:
				nearest_dist = player_distance
				nearest = player_node
	return nearest


# Returns true if it is night. With no weather system it counts as night.
func _is_night() -> bool:
	if not _weather or not is_instance_valid(_weather):
		return true
	return not _weather.has_method("is_night") or _weather.is_night()


# Returns true if the player is in the cave world.
func _is_in_cave() -> bool:
	return _cave_gen != null and is_instance_valid(_cave_gen) and _cave_gen.get("in_cave")


# Moves the enemy if the way is clear, otherwise slides sideways or jumps to a free spot.
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


func _is_position_clear(world_position: Vector2) -> bool:
	var key := Vector2i(floori(world_position.x / 16.0), floori(world_position.y / 16.0))
	if _cached_position_clear.has(key):
		return _cached_position_clear[key]
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 10.0
	query.shape = shape
	query.transform = Transform2D(0, world_position)
	query.collision_mask = 1
	query.exclude = [staticbody.get_rid()]
	for player_node in get_tree().get_nodes_in_group("players"):
		if player_node is CollisionObject2D:
			query.exclude.append(player_node.get_rid())
	var hits := space.intersect_shape(query)
	for hit in hits:
		if hit["collider"] != staticbody:
			_cached_position_clear[key] = false
			return false
	_cached_position_clear[key] = true
	return true


# Tries random spots around the enemy and moves to the first clear one.
func _escape_from_blocked_position() -> bool:
	for i in ESCAPE_ATTEMPTS:
		var angle = rng.randf_range(0.0, TAU)
		var distance = rng.randf_range(36.0, ESCAPE_SEARCH_RADIUS)
		var candidate = global_position + Vector2(cos(angle), sin(angle)) * distance
		if _is_position_clear(candidate):
			global_position = candidate
			return true
	return false


# Host only. Sinks and slows the enemy in water and kills it if it stays too long.
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


# Returns true if the enemy is standing on water in the cave or on the surface.
func _is_current_world_water() -> bool:
	if _cave_gen and is_instance_valid(_cave_gen) and _cave_gen.get("in_cave"):
		var tile_position: Vector2i = _cave_gen.world_to_tile(global_position)
		return _cave_gen._water_tiles.has(tile_position)
	return _world_gen != null and is_instance_valid(_world_gen) \
		and _world_gen.has_method("is_water_at") \
		and _world_gen.is_water_at(global_position)

# Sent often by the host to show the charge glow. It does not matter if one is lost.
@rpc("authority", "call_remote", "unreliable_ordered")


# Shows the charge glow on the other players' games.
func _sync_charge_glow_rpc(pct: float) -> void:
	_set_charge_glow(pct)

# Sent by the host when a dash begins.
@rpc("authority", "call_remote", "reliable")


# Starts the dash on the other players' games.
func _sync_begin_dash_rpc(dir_x: float, dir_y: float) -> void:
	dash_direction = Vector2(dir_x, dir_y)
	dash_timer = 0.0
	_clear_charge_glow()
	sprite.play("idle")

# Sent by the host when a dash misses.
@rpc("authority", "call_remote", "reliable")


# Plays the miss reaction on the other players' games.
func _sync_dash_miss_rpc() -> void:
	_play_miss_stumble()

# Sent by the host so every player sees the enemy flash.
@rpc("authority", "call_local", "reliable")


# Flashes the enemy.
func _sync_flash_hit_rpc() -> void:
	_flash_hit()

# Sent by the host so every player sees the enemy die.
@rpc("authority", "call_local", "reliable")


# Plays the death sequence.
func _sync_die_rpc() -> void:
	_play_die_sequence()
