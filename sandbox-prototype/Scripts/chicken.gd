extends Node2D

enum State { WANDER, IDLE, FLEE, DEAD, PETTED }

@export var speed_wander: float = 80.0
@export var speed_flee: float = 230.0
@export var flee_radius: float = 300.0
@export var health: int = 10
@export var click_radius: float = 50.0

var state: State = State.WANDER
var _wander_target: Vector2 = Vector2.ZERO
var _idle_timer: float = 0.0
var _player_in_range: bool = false
var chicken_id: int = -1
var _stuck_timer: float = 0.0
var rng := RandomNumberGenerator.new()

var _blocked_escape_timer: float = 0.0
const BLOCKED_ESCAPE_TIME: float = 1.2
const ESCAPE_SEARCH_RADIUS: float = 180.0
const ESCAPE_ATTEMPTS: int = 16

var drowning_timer: float = 0.0
var drowning_dead: bool = false
const DROWN_TIME: float = 4.0

var _ai_tick: float = 0.0
var _sync_tick: float = 0.0
const AI_TICK_RATE: float = 0.1
const SYNC_TICK_RATE: float = 0.1

var _scene: Node = null
var _world_gen: Node = null

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hurtbox: Area2D = $Hurtbox
@onready var staticbody: StaticBody2D = $StaticBody2D

func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()

func _ready() -> void:
	rng.randomize()
	sprite.position.y = -30
	staticbody.position.y = -6
	z_index = 2
	add_to_group("chickens")
	sprite.visible = true
	sprite.modulate = Color(1, 1, 1, 1)
	hurtbox.body_entered.connect(_on_body_entered)
	hurtbox.body_exited.connect(_on_body_exited)
	_pick_wander_target()
	_scene = get_tree().root.get_node_or_null("Scene")
	_world_gen = get_tree().root.get_node_or_null("Scene/WorldGen")

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("players"):
		_player_in_range = true

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("players"):
		_player_in_range = false

func _input(event: InputEvent) -> void:
	if state == State.DEAD:
		return
	if not event is InputEventMouseButton:
		return
	if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		var mouse_world: Vector2 = get_global_mouse_position()
		if (event as InputEventMouseButton).pressed:
			var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
			if hotbar:
				var slot = Inventory.slots[hotbar.current_slot - 1]
				if slot["item"] == "Sword" or slot["item"] == "Stone Sword":
					return
			if global_position.distance_to(mouse_world) > click_radius:
				return
			if _player_in_range:
				_start_petting()
		else:
			if state == State.PETTED:
				state = State.IDLE
				_idle_timer = randf_range(1.0, 2.0)
		return
	if not (event as InputEventMouseButton).pressed:
		return
	if (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	var mouse_world: Vector2 = get_global_mouse_position()
	if global_position.distance_to(mouse_world) > click_radius:
		return
	var player: Node = null
	for p in get_tree().get_nodes_in_group("players"):
		if not multiplayer.has_multiplayer_peer() or (p as Node).is_multiplayer_authority():
			player = p
			break
	if not player:
		return
	var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	if not hotbar:
		return
	var slot = Inventory.slots[hotbar.current_slot - 1]
	if slot["item"] != "Sword" and slot["item"] != "Stone Sword":
		return
	if not _player_in_range:
		return
	if player.attack_cooldown > 0.0 or player.chop_cooldown_timer > 0.0:
		return
	var damage: int = 0
	if slot["item"] == "Sword":
		damage = 2
	elif slot["item"] == "Stone Sword":
		damage = 4
	else:
		return
	player.attack_cooldown = player.ATTACK_COOLDOWN_MAX
	player._consume_sword_durability()
	var cursor = get_tree().root.get_node_or_null("Scene/CanvasLayer/Cursor")
	if cursor:
		cursor.show_cooldown(player.ATTACK_COOLDOWN_MAX)
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_damage_rpc.rpc_id(1, chicken_id, damage)
	else:
		take_damage(damage)

func _start_petting() -> void:
	if state == State.PETTED:
		return
	state = State.PETTED
	sprite.play("idle")
	_pet_heart_loop()

func _pet_heart_loop() -> void:
	while state == State.PETTED:
		var heart = Label.new()
		heart.text = "❤️"
		heart.add_theme_font_size_override("font_size", 12)
		heart.position = Vector2(randf_range(-12, -2), -30)
		heart.z_index = 10
		add_child(heart)
		var tween = create_tween()
		tween.tween_property(heart, "position:y", heart.position.y - 30, 1.0)
		tween.parallel().tween_property(heart, "modulate:a", 0.0, 1.0)
		tween.tween_callback(heart.queue_free)
		await get_tree().create_timer(0.2).timeout

func _process(delta: float) -> void:
	_update_drowning(delta)
	if state == State.DEAD:
		return
	if state == State.PETTED:
		return
	if not _is_host():
		return
	_ai_tick += delta
	if _ai_tick >= AI_TICK_RATE:
		_ai_tick = 0.0
		_apply_separation()
		_check_flee()
	match state:
		State.WANDER: _do_wander(delta)
		State.IDLE:   _do_idle(delta)
		State.FLEE:   _do_flee(delta)
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		_sync_tick += delta
		if _sync_tick >= SYNC_TICK_RATE:
			_sync_tick = 0.0
			if is_inside_tree() and get_meta("sync_ready", false) and _scene:
				_scene.sync_chicken_state_rpc.rpc(chicken_id, global_position.x, global_position.y, int(state))

func _apply_separation() -> void:
	if state == State.FLEE:
		return
	var separation := Vector2.ZERO
	for chicken in get_tree().get_nodes_in_group("chickens"):
		if chicken == self:
			continue
		var diff := global_position - (chicken as Node2D).global_position
		var dist := diff.length()
		if dist < 32.0 and dist > 0.0:
			separation += diff.normalized() * (32.0 - dist)
	if separation.length() > 0.0:
		_try_move(separation * 0.05)

func _check_flee() -> void:
	if state == State.PETTED:
		return
	var player := _get_nearest_player()
	if player and global_position.distance_to(player.global_position) < flee_radius:
		state = State.FLEE
	elif state == State.FLEE:
		state = State.WANDER
		_pick_wander_target()

func _do_wander(delta: float) -> void:
	if global_position.distance_to(_wander_target) < 8.0:
		state = State.IDLE
		_idle_timer = randf_range(1.5, 4.0)
		sprite.play("idle")
		return
	var dir := (_wander_target - global_position).normalized()
	var next_pos := global_position + dir * speed_wander * delta
	if _is_water_at(next_pos):
		_pick_wander_target()
		return
	var prev_pos := global_position
	_try_move(dir * speed_wander * delta)
	if global_position.distance_to(prev_pos) < 0.01:
		_stuck_timer += delta
		if _stuck_timer >= 0.3:
			_stuck_timer = 0.0
			_pick_wander_target()
	else:
		_stuck_timer = 0.0
	sprite.play("walk_down")

func _do_idle(delta: float) -> void:
	sprite.play("idle")
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		state = State.WANDER
		_pick_wander_target()

func _do_flee(delta: float) -> void:
	var player := _get_nearest_player()
	if not player:
		state = State.WANDER
		_pick_wander_target()
		return
	var dir := (global_position - player.global_position).normalized()
	var prev_pos := global_position
	_try_move(dir * speed_flee * delta)
	if global_position.distance_to(prev_pos) < 0.01:
		_stuck_timer += delta
		if _stuck_timer >= 0.3:
			_stuck_timer = 0.0
			var perp := Vector2(-dir.y, dir.x)
			if rng.randf() > 0.5:
				perp = -perp
			_try_move(perp * speed_flee * delta * 3.0)
	else:
		_stuck_timer = 0.0
	sprite.play("walk_down")

func _is_water_at(pos: Vector2) -> bool:
	if _world_gen and _world_gen.has_method("is_water_at"):
		return _world_gen.is_water_at(pos)
	return false

func _pick_wander_target() -> void:
	for _attempt in 12:
		var offset := Vector2(rng.randf_range(-180.0, 180.0), rng.randf_range(-180.0, 180.0))
		var candidate := global_position + offset
		if not _is_water_at(candidate):
			_wander_target = candidate
			return
	_wander_target = global_position

func _get_nearest_player() -> CharacterBody2D:
	var nearest: CharacterBody2D = null
	var nearest_dist := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p is CharacterBody2D:
			var d := global_position.distance_to(p.global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest = p
	return nearest

@rpc("any_peer", "call_remote", "reliable")
func _request_damage_rpc(target_chicken_id: int, amount: int) -> void:
	if not multiplayer.is_server():
		return
	for chicken in get_tree().get_nodes_in_group("chickens"):
		if chicken.get("chicken_id") == target_chicken_id:
			chicken.take_damage(amount)
			return

func take_damage(amount: int) -> void:
	if state == State.DEAD:
		return
	if not _is_host():
		return
	health -= amount
	if multiplayer.has_multiplayer_peer() and _scene:
		_scene.chicken_flash_hit_rpc.rpc(chicken_id)
	else:
		_flash_hit()
	if health <= 0:
		_die()

func _flash_hit() -> void:
	sprite.modulate = Color(1, 0.1, 0.1, 1)
	await get_tree().create_timer(0.08).timeout
	sprite.modulate = Color(1, 1, 1, 1)
	await get_tree().create_timer(0.06).timeout
	sprite.modulate = Color(1, 0.1, 0.1, 1)
	await get_tree().create_timer(0.08).timeout
	sprite.modulate = Color(1, 1, 1, 1)

func _die() -> void:
	if multiplayer.has_multiplayer_peer() and _scene:
		_scene.chicken_die_rpc.rpc(chicken_id)
	else:
		_play_die_sequence()

func _play_die_sequence() -> void:
	state = State.DEAD
	sprite.modulate = Color(1, 0.1, 0.1, 1)
	var tween = create_tween()
	tween.tween_property(sprite, "scale", Vector2(0.1, 0.1), 0.4)
	tween.parallel().tween_property(sprite, "modulate", Color(1, 0.1, 0.1, 0), 0.4)
	await tween.finished
	if _is_host() and _scene:
		var drop_count = rng.randi_range(1, 2)
		for i in drop_count:
			var offset = Vector2(rng.randf_range(-16, 16), rng.randf_range(-16, 16))
			_scene.host_spawn_floor_item(global_position + offset, "Chicken_Raw", 1)
	queue_free()

func _update_drowning(delta: float) -> void:
	if state == State.DEAD:
		return
	if not _is_host():
		return
	var in_water = _world_gen != null and _world_gen.has_method("is_water_at") and _world_gen.is_water_at(global_position)
	if in_water:
		drowning_timer += delta
	else:
		drowning_timer = max(drowning_timer - delta * 2.0, 0.0)
	var alpha = lerp(1.0, 0.35, clamp(drowning_timer / DROWN_TIME, 0.0, 1.0))
	_set_drowning_alpha(alpha)
	if multiplayer.has_multiplayer_peer() and _scene:
		_scene.chicken_drowning_alpha_rpc.rpc(chicken_id, alpha)
	if drowning_timer >= DROWN_TIME and not drowning_dead:
		drowning_dead = true
		take_damage(9999)
	elif drowning_timer <= 0.0:
		drowning_dead = false

func _set_drowning_alpha(alpha: float) -> void:
	sprite.modulate.a = alpha

func _is_position_clear(pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 10.0
	query.shape = shape
	query.transform = Transform2D(0, pos)
	query.collision_mask = 1
	var excludes = [staticbody.get_rid()]
	for p in get_tree().get_nodes_in_group("players"):
		excludes.append(p.get_rid())
	query.exclude = excludes
	var hits := space.intersect_shape(query)
	for hit in hits:
		if hit["collider"] != staticbody:
			return false
	return true

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
			_wander_target = global_position + slide.normalized() * 160.0
			_blocked_escape_timer = 0.0
			return
	if _blocked_escape_timer >= BLOCKED_ESCAPE_TIME:
		if _escape_from_blocked_position():
			_blocked_escape_timer = 0.0

func _escape_from_blocked_position() -> bool:
	for i in ESCAPE_ATTEMPTS:
		var angle = rng.randf_range(0.0, TAU)
		var dist = rng.randf_range(48.0, ESCAPE_SEARCH_RADIUS)
		var candidate = global_position + Vector2(cos(angle), sin(angle)) * dist
		if _is_position_clear(candidate):
			global_position = candidate
			_pick_wander_target()
			return true
	return false

@rpc("authority", "call_local", "reliable")
func chicken_flash_hit_rpc(cid: int) -> void:
	var chicken = get_node_or_null("Chicken_" + str(cid))
	if chicken and is_instance_valid(chicken):
		chicken._flash_hit()

@rpc("authority", "call_local", "reliable")
func chicken_die_rpc(cid: int) -> void:
	var chicken = get_node_or_null("Chicken_" + str(cid))
	if chicken and is_instance_valid(chicken):
		chicken._play_die_sequence()
