extends Node2D

enum State { WANDER, IDLE, FLEE, DEAD }

@export var speed_wander: float = 80.0
@export var speed_flee: float = 80.0
@export var flee_radius: float = 300.0
@export var health: int = 10
@export var click_radius: float = 50.0

var state: State = State.WANDER
var _wander_target: Vector2 = Vector2.ZERO
var _idle_timer: float = 0.0
var _player_in_range: bool = false
var _is_host: bool = false
var chicken_id: int = -1

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hurtbox: Area2D = $Hurtbox
@onready var staticbody: StaticBody2D = $StaticBody2D

func _ready() -> void:
	sprite.position.y = -30
	staticbody.position.y = -6
	z_index = 2
	add_to_group("chickens")
	sprite.visible = true
	sprite.modulate = Color(1, 1, 1, 1)
	hurtbox.body_entered.connect(_on_body_entered)
	hurtbox.body_exited.connect(_on_body_exited)
	_pick_wander_target()
	_is_host = not multiplayer.has_multiplayer_peer() or multiplayer.is_server()

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

func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	if not _is_host:
		return
	_apply_separation()
	_check_flee()
	match state:
		State.WANDER: _do_wander(delta)
		State.IDLE:   _do_idle(delta)
		State.FLEE:   _do_flee(delta)
	if multiplayer.has_multiplayer_peer():
		_sync_state_rpc.rpc(global_position.x, global_position.y, int(state))

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
		global_position += separation * 0.05

func _check_flee() -> void:
	var player := _get_nearest_player()
	if player and global_position.distance_to(player.global_position) < flee_radius:
		state = State.FLEE
	elif state == State.FLEE:
		state = State.WANDER
		_pick_wander_target()

func _do_wander(delta: float) -> void:
	var to_target := _wander_target - global_position
	if to_target.length() < 8.0:
		state = State.IDLE
		_idle_timer = randf_range(1.5, 4.0)
		sprite.play("idle")
		return
	global_position += to_target.normalized() * speed_wander * delta
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
	var away := (global_position - player.global_position).normalized()
	global_position += away * speed_flee * delta
	sprite.play("walk_down")

func _pick_wander_target() -> void:
	var offset := Vector2(randf_range(-180.0, 180.0), randf_range(-180.0, 180.0))
	_wander_target = global_position + offset

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

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_state_rpc(px: float, py: float, s: int) -> void:
	global_position = Vector2(px, py)
	state = s as State
	match state:
		State.WANDER, State.FLEE:
			sprite.play("walk_down")
		State.IDLE:
			sprite.play("idle")

@rpc("authority", "call_local", "reliable")
func _sync_flash_hit_rpc() -> void:
	_flash_hit()

@rpc("authority", "call_local", "reliable")
func _sync_die_rpc() -> void:
	_play_die_sequence()

func take_damage(amount: int) -> void:
	if state == State.DEAD:
		return
	if not _is_host:
		return
	health -= amount
	if multiplayer.has_multiplayer_peer():
		_sync_flash_hit_rpc.rpc()
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
	if multiplayer.has_multiplayer_peer():
		_sync_die_rpc.rpc()
	else:
		_play_die_sequence()

func _play_die_sequence() -> void:
	state = State.DEAD
	sprite.modulate = Color(1, 0.1, 0.1, 1)
	var tween = create_tween()
	tween.tween_property(sprite, "scale", Vector2(0.1, 0.1), 0.4)
	tween.parallel().tween_property(sprite, "modulate", Color(1, 0.1, 0.1, 0), 0.4)
	await tween.finished
	queue_free()
