extends Node2D

enum State { CHASE, CHARGING, DASHING, COOLDOWN, DEAD }

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

var drowning_timer: float = 0.0
var drowning_dead: bool = false
const DROWN_TIME: float = 5.0

var state: State = State.CHASE
var attack_cooldown: float = 0.0
var charge_timer: float = 0.0
var dash_timer: float = 0.0
var dash_direction: Vector2 = Vector2.ZERO
var dash_origin: Vector2 = Vector2.ZERO
var _blocked_escape_timer: float = 0.0
var rng := RandomNumberGenerator.new()

const PREFERRED_DISTANCE: float = 72.0
const BLOCKED_ESCAPE_TIME: float = 1.0
const ESCAPE_SEARCH_RADIUS: float = 120.0
const ESCAPE_ATTEMPTS: int = 12
const SEPARATION_RADIUS: float = 52.0
const SEPARATION_FORCE: float = 600.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var staticbody: StaticBody2D = $StaticBody2D

func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()

func _ready() -> void:
	rng.randomize()
	z_index = 2
	add_to_group("night_enemies")
	sprite.position.y = -30
	staticbody.position.y = -6
	sprite.play("walk_down")
	attack_cooldown = rng.randf_range(0.5, attack_cooldown_max)

func _process(delta: float) -> void:
	_update_drowning(delta)
	if state == State.DEAD:
		return
	if not _is_host():
		return
	if despawn_when_day and not _is_night():
		_die()
		return

	attack_cooldown = max(attack_cooldown - delta, 0.0)
	_resolve_overlap()
	_apply_separation(delta)
	var target := _get_nearest_player()
	if not target:
		return

	var distance := global_position.distance_to(target.global_position)

	match state:
		State.CHASE:
			if distance <= attack_range and attack_cooldown <= 0.0:
				_begin_charge(target)
			else:
				_chase(target, delta)

		State.CHARGING:
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
			dash_timer += delta
			var step := dash_direction * dash_speed * delta
			var next_pos := global_position + step
			if not _is_position_clear_for_dash(next_pos):
				_on_dash_miss()
				return
			global_position = next_pos
			var dist_to_target := global_position.distance_to(target.global_position)
			if dist_to_target <= dash_hit_radius:
				_on_dash_hit(target)
				return
			if dash_timer >= dash_duration:
				_on_dash_miss()

		State.COOLDOWN:
			pass

	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		if is_inside_tree() and get_meta("sync_ready", false):
			var scene = get_tree().root.get_node_or_null("Scene")
			if scene:
				scene.sync_enemy_state_rpc.rpc(enemy_id, global_position.x, global_position.y, int(state), health)

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
	for enemy in get_tree().get_nodes_in_group("night_enemies"):
		if enemy != self and enemy.get("staticbody") != null:
			query.exclude.append((enemy.staticbody as CollisionObject2D).get_rid())
	var hits := space.intersect_shape(query)
	return hits.size() == 0

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
		var scene_node = get_tree().root.get_node_or_null("Scene")
		if scene_node:
			scene_node.enemy_attack_player.rpc_id(target_id, attack_damage, enemy_id)
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

func _chase(target: CharacterBody2D, delta: float) -> void:
	state = State.CHASE
	var to_target := target.global_position - global_position
	var distance := to_target.length()
	var dir := to_target.normalized()
	if distance < PREFERRED_DISTANCE:
		_try_move(-dir * speed * delta)
	else:
		_try_move(dir * speed * delta)
	sprite.play("walk_down")

func _apply_separation(delta: float) -> void:
	for other in get_tree().get_nodes_in_group("night_enemies"):
		if other == self or not is_instance_valid(other):
			continue
		var diff := global_position - (other as Node2D).global_position
		var dist := diff.length()
		if dist < SEPARATION_RADIUS and dist > 0.01:
			var push := diff.normalized() * SEPARATION_FORCE * delta
			global_position += push
			(other as Node2D).global_position -= push

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
	for enemy in get_tree().get_nodes_in_group("night_enemies"):
		if enemy != self and enemy.get("staticbody") != null:
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
	if multiplayer.has_multiplayer_peer():
		_sync_flash_hit_rpc.rpc()
	else:
		_flash_hit()
	if health <= 0:
		_die()

func _die() -> void:
	if state == State.DEAD:
		return
	if multiplayer.has_multiplayer_peer():
		_sync_die_rpc.rpc()
	else:
		_play_die_sequence()

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
	var weather = get_tree().root.get_node_or_null("Scene/Weather")
	return weather == null or not weather.has_method("is_night") or weather.is_night()

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
			return false
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

func _update_drowning(delta: float) -> void:
	if state == State.DEAD:
		return
	if not _is_host():
		return
	var world_gen = get_tree().root.get_node_or_null("Scene/WorldGen")
	var in_water = world_gen != null and world_gen.has_method("is_water_at") and world_gen.is_water_at(global_position)
	if in_water:
		drowning_timer += delta
	else:
		drowning_timer = max(drowning_timer - delta * 2.0, 0.0)
	var alpha = lerp(1.0, 0.35, clamp(drowning_timer / DROWN_TIME, 0.0, 1.0))
	sprite.modulate.a = alpha
	if drowning_timer >= DROWN_TIME and not drowning_dead:
		drowning_dead = true
		take_damage(9999)
	elif drowning_timer <= 0.0:
		drowning_dead = false
