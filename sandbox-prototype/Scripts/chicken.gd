# Chicken.
# Wanders around, idles, and runs away from players. Players can pet it with a right click or attack it with a sword, and it drops raw chicken when it dies.
# The host controls the chicken's behaviour and sends its position and state to the other players.

extends Node2D

# The chicken's behaviours. Petted is used while a player is stroking it.
enum State { WANDER, IDLE, FLEE, DEAD, PETTED }

# Walking speed in pixels per second.
@export var speed_wander: float = 80.0
# Running speed when frightened.
@export var speed_flee: float = 230.0
# Distance in pixels at which a player scares the chicken.
@export var flee_radius: float = 300.0
# Health points. It dies when they reach zero.
@export var health: int = 10
# How close the mouse must be to the chicken to click it.
@export var click_radius: float = 50.0

# The behaviour the chicken is currently in.
var state: State = State.WANDER
# The spot the chicken is walking towards.
var _wander_target: Vector2 = Vector2.ZERO
# Seconds left to stand still.
var _idle_timer: float = 0.0
# True while a player is close enough to interact.
var _player_in_range: bool = false
# ID that lets every player refer to the same chicken.
var chicken_id: int = -1
# Seconds the chicken has been unable to move.
var _stuck_timer: float = 0.0
# Random number generator for this chicken.
var rng := RandomNumberGenerator.new()

# Seconds the chicken has been completely blocked.
var _blocked_escape_timer: float = 0.0
# Seconds blocked before the chicken jumps to a free spot.
const BLOCKED_ESCAPE_TIME: float = 1.2
# Furthest distance to look for a free spot.
const ESCAPE_SEARCH_RADIUS: float = 180.0
# Number of random spots to try.
const ESCAPE_ATTEMPTS: int = 16

# Seconds spent in water. The chicken fades as this grows.
var drowning_timer: float = 0.0
# True once the chicken has drowned, so it only dies once.
var drowning_dead: bool = false
# Seconds in water before the chicken drowns.
const DROWN_TIME: float = 4.0

# Time since the behaviour was last checked.
var _ai_tick: float = 0.0
# Time since the state was last sent to other players.
var _sync_tick: float = 0.0
# Seconds between behaviour checks.
const AI_TICK_RATE: float = 0.1
# Seconds between updates sent to other players.
const SYNC_TICK_RATE: float = 0.1

# The main scene, used for network messages and drops.
var _scene: Node = null
# The world generator, used to check for water.
var _world_gen: Node = null

# Animated picture of the chicken.
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
# Detects players who are close enough to interact.
@onready var hurtbox: Area2D = $Hurtbox
# Solid body that stops other things walking through the chicken.
@onready var staticbody: StaticBody2D = $StaticBody2D


# Returns true for the host or in a single player game. Only the host controls the chicken.
func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


# Sets up the sprite, joins the chickens group and picks a first place to walk to.
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


# A player came close.
func _on_body_entered(body: Node) -> void:
	if body.is_in_group("players"):
		_player_in_range = true


# A player moved away.
func _on_body_exited(body: Node) -> void:
	if body.is_in_group("players"):
		_player_in_range = false


# Right click pets the chicken, and left click with a sword attacks it.
func _input(event: InputEvent) -> void:
	if state == State.DEAD:
		return
	# Right click (or its controller equivalent). Holding a sword does nothing here, otherwise start petting when close, and stop when the button is released.
	if event.is_action_pressed("right_click"):
		var mouse_world: Vector2 = get_global_mouse_position()
		var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
		if hotbar:
			var slot = Inventory.slots[hotbar.current_slot - 1]
			if slot["item"] == "Sword" or slot["item"] == "Stone Sword":
				return
		if global_position.distance_to(mouse_world) > click_radius:
			return
		if _player_in_range:
			_start_petting()
		return
	if event.is_action_released("right_click"):
		if state == State.PETTED:
			state = State.IDLE
			_idle_timer = randf_range(1.0, 2.0)
		return
	if not event.is_action_pressed("click"):
		return
	var mouse_world: Vector2 = get_global_mouse_position()
	if global_position.distance_to(mouse_world) > click_radius:
		return
	# Left click with a sword: find this game's player and check they are close and ready to attack.
	var player: Node = null
	for player_node in get_tree().get_nodes_in_group("players"):
		if not multiplayer.has_multiplayer_peer() or (player_node as Node).is_multiplayer_authority():
			player = player_node
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
	# A stone sword deals more damage than a wooden sword.
	var damage: int = 0
	if slot["item"] == "Sword":
		damage = 2
	elif slot["item"] == "Stone Sword":
		damage = 4
	else:
		return
	# Start the attack cooldown, wear down the sword and show the cooldown on the cursor.
	player.attack_cooldown = player.ATTACK_COOLDOWN_MAX
	player._consume_sword_durability()
	var cursor = get_tree().root.get_node_or_null("Scene/CanvasLayer/Cursor")
	if cursor:
		cursor.show_cooldown(player.ATTACK_COOLDOWN_MAX)
	# Clients ask the host to apply the damage, while the host applies it directly.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_damage_rpc.rpc_id(1, chicken_id, damage)
	else:
		take_damage(damage)


# Starts petting. The chicken stands still while hearts float up.
func _start_petting() -> void:
	if state == State.PETTED:
		return
	state = State.PETTED
	sprite.play("idle")
	_pet_heart_loop()


# Spawns a small heart every fifth of a second that floats up and fades out, until petting stops.
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


# Runs the chicken's behaviour on the host and sends its state to the other players.
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
	# Carry out the current behaviour.
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


# Gently pushes the chicken away from other chickens that are too close.
func _apply_separation() -> void:
	if state == State.FLEE:
		return
	var separation := Vector2.ZERO
	for chicken in get_tree().get_nodes_in_group("chickens"):
		if chicken == self:
			continue
		var offset_to_other := global_position - (chicken as Node2D).global_position
		var distance := offset_to_other.length()
		if distance < 32.0 and distance > 0.0:
			separation += offset_to_other.normalized() * (32.0 - distance)
	if separation.length() > 0.0:
		_try_move(separation * 0.05)


# Runs away if a player is close, and goes back to wandering once they are far enough away.
func _check_flee() -> void:
	if state == State.PETTED:
		return
	var player := _get_nearest_player()
	if player and global_position.distance_to(player.global_position) < flee_radius:
		state = State.FLEE
	elif state == State.FLEE:
		state = State.WANDER
		_pick_wander_target()


# Walks towards the target. It stops when it arrives, avoids water and picks a new target if it gets stuck.
func _do_wander(delta: float) -> void:
	if global_position.distance_to(_wander_target) < 8.0:
		state = State.IDLE
		_idle_timer = randf_range(1.5, 4.0)
		sprite.play("idle")
		return
	var direction := (_wander_target - global_position).normalized()
	var next_pos := global_position + direction * speed_wander * delta
	if _is_water_at(next_pos):
		_pick_wander_target()
		return
	var prev_pos := global_position
	_try_move(direction * speed_wander * delta)
	if global_position.distance_to(prev_pos) < 0.01:
		_stuck_timer += delta
		if _stuck_timer >= 0.3:
			_stuck_timer = 0.0
			_pick_wander_target()
	else:
		_stuck_timer = 0.0
	sprite.play("walk_down")


# Stands still until the timer runs out, then wanders again.
func _do_idle(delta: float) -> void:
	sprite.play("idle")
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		state = State.WANDER
		_pick_wander_target()


# Runs directly away from the nearest player and tries sidestepping if it gets stuck.
func _do_flee(delta: float) -> void:
	var player := _get_nearest_player()
	if not player:
		state = State.WANDER
		_pick_wander_target()
		return
	var direction := (global_position - player.global_position).normalized()
	var prev_pos := global_position
	_try_move(direction * speed_flee * delta)
	if global_position.distance_to(prev_pos) < 0.01:
		_stuck_timer += delta
		if _stuck_timer >= 0.3:
			_stuck_timer = 0.0
			var perpendicular_direction := Vector2(-direction.y, direction.x)
			if rng.randf() > 0.5:
				perpendicular_direction = -perpendicular_direction
			_try_move(perpendicular_direction * speed_flee * delta * 3.0)
	else:
		_stuck_timer = 0.0
	sprite.play("walk_down")


# Returns true if there is water at the position.
func _is_water_at(world_position: Vector2) -> bool:
	if _world_gen and _world_gen.has_method("is_water_at"):
		return _world_gen.is_water_at(world_position)
	return false


# Chooses a random spot nearby that is not in water, trying up to 12 times.
func _pick_wander_target() -> void:
	for _attempt in 12:
		var offset := Vector2(rng.randf_range(-180.0, 180.0), rng.randf_range(-180.0, 180.0))
		var candidate := global_position + offset
		if not _is_water_at(candidate):
			_wander_target = candidate
			return
	_wander_target = global_position


# Returns the closest player, or null if there are none.
func _get_nearest_player() -> CharacterBody2D:
	var nearest: CharacterBody2D = null
	var nearest_dist := INF
	for player_node in get_tree().get_nodes_in_group("players"):
		if player_node is CharacterBody2D:
			var player_distance := global_position.distance_to(player_node.global_position)
			if player_distance < nearest_dist:
				nearest_dist = player_distance
				nearest = player_node
	return nearest

# Sent by a client to ask the host to damage a chicken.
@rpc("any_peer", "call_remote", "reliable")


# Host only. Finds the chicken with the given ID and damages it.
func _request_damage_rpc(target_chicken_id: int, amount: int) -> void:
	if not multiplayer.is_server():
		return
	for chicken in get_tree().get_nodes_in_group("chickens"):
		if chicken.get("chicken_id") == target_chicken_id:
			chicken.take_damage(amount)
			return


# Reduces the chicken's health, flashes it red and kills it at zero health. Only the host does this.
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


# Flashes the chicken red twice.
func _flash_hit() -> void:
	sprite.modulate = Color(1, 0.1, 0.1, 1)
	await get_tree().create_timer(0.08).timeout
	sprite.modulate = Color(1, 1, 1, 1)
	await get_tree().create_timer(0.06).timeout
	sprite.modulate = Color(1, 0.1, 0.1, 1)
	await get_tree().create_timer(0.08).timeout
	sprite.modulate = Color(1, 1, 1, 1)


# Starts the chicken's death on every player's game.
func _die() -> void:
	if multiplayer.has_multiplayer_peer() and _scene:
		_scene.chicken_die_rpc.rpc(chicken_id)
	else:
		_play_die_sequence()


# Shrinks and fades the chicken, then the host drops one or two raw chicken and removes it.
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


# Host only. Fades the chicken while it is in water and kills it if it stays there too long.
func _update_drowning(delta: float) -> void:
	if state == State.DEAD:
		return
	if not _is_host():
		return
	var in_water = _world_gen != null \
		and _world_gen.has_method("is_water_at") \
		and _world_gen.is_water_at(global_position)
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


# Sets how see through the chicken is.
func _set_drowning_alpha(alpha: float) -> void:
	sprite.modulate.a = alpha


# Returns true if a small circle at the position touches nothing solid, ignoring the chicken and the players.
func _is_position_clear(world_position: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 10.0
	query.shape = shape
	query.transform = Transform2D(0, world_position)
	query.collision_mask = 1
	var excludes = [staticbody.get_rid()]
	for player_node in get_tree().get_nodes_in_group("players"):
		excludes.append(player_node.get_rid())
	query.exclude = excludes
	var hits := space.intersect_shape(query)
	for hit in hits:
		if hit["collider"] != staticbody:
			return false
	return true


# Moves the chicken if the way is clear. Otherwise it tries sliding sideways, and eventually jumps to a free spot.
func _try_move(delta: Vector2) -> void:
	if delta.length() <= 0.001:
		return
	var target = global_position + delta
	if _is_position_clear(target):
		global_position = target
		_blocked_escape_timer = 0.0
		return
	_blocked_escape_timer += get_process_delta_time()
	# Sideways directions to try when the direct path is blocked.
	var slide_dirs = [
		Vector2(delta.x, 0),
		Vector2(0, delta.y),
		Vector2(-delta.y, delta.x).normalized() * delta.length(),
		Vector2(delta.y, -delta.x).normalized() * delta.length()
	]
	for slide_offset in slide_dirs:
		if slide_offset.length() <= 0.001:
			continue
		var slide_target = global_position + slide_offset
		if _is_position_clear(slide_target):
			global_position = slide_target
			_wander_target = global_position + slide_offset.normalized() * 160.0
			_blocked_escape_timer = 0.0
			return
	if _blocked_escape_timer >= BLOCKED_ESCAPE_TIME:
		if _escape_from_blocked_position():
			_blocked_escape_timer = 0.0


# Tries random spots around the chicken and moves to the first clear one. Returns true if it succeeded.
func _escape_from_blocked_position() -> bool:
	for i in ESCAPE_ATTEMPTS:
		var angle = rng.randf_range(0.0, TAU)
		var distance = rng.randf_range(48.0, ESCAPE_SEARCH_RADIUS)
		var candidate = global_position + Vector2(cos(angle), sin(angle)) * distance
		if _is_position_clear(candidate):
			global_position = candidate
			_pick_wander_target()
			return true
	return false

# Sent by the host so every player sees the chicken flash.
@rpc("authority", "call_local", "reliable")


# Flashes the chicken with the given ID.
func chicken_flash_hit_rpc(chicken_number: int) -> void:
	var chicken = get_node_or_null("Chicken_" + str(chicken_number))
	if chicken and is_instance_valid(chicken):
		chicken._flash_hit()

# Sent by the host so every player sees the chicken die.
@rpc("authority", "call_local", "reliable")


# Plays the death sequence for the chicken with the given ID.
func chicken_die_rpc(chicken_number: int) -> void:
	var chicken = get_node_or_null("Chicken_" + str(chicken_number))
	if chicken and is_instance_valid(chicken):
		chicken._play_die_sequence()
