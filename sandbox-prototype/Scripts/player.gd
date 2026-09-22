# Player character.
# Handles movement, animation, the camera, the held item, sword attacks, blocking and parrying, rolling, health, drowning, death and respawning, and the clothing layers.
# Each player controls their own character and sends its position and state to the other players.

extends CharacterBody2D

# Walking speed in pixels per second.
@export var speed = 350
# Current velocity, shared with the other players.
@export var synced_velocity : Vector2 = Vector2.ZERO
# Name of the held item, shared so others can see it.
@export var synced_held_item: String = ""
# Current health, shared with the other players.
@export var synced_health: int = 10
# Animated picture of the character's body.
@onready var anim = $AnimatedSprite2D
# Animated picture of the hair layer.
@onready var hair_sprite: AnimatedSprite2D = $Hair_Sprite
# Animated picture of the shirt layer.
@onready var shirt_sprite: AnimatedSprite2D = $Shirt_Sprite
# Animated picture of the pants layer.
@onready var pants_sprite: AnimatedSprite2D = $Pants_Sprite

# Whether the hair layer is shown, shared with the other players.
@export var synced_hair: bool = true
# Whether the shirt layer is shown, shared with the other players.
@export var synced_shirt: bool = true
# Whether the pants layer is shown, shared with the other players.
@export var synced_pants: bool = true
# Seconds before the player respawns after dying.
@export var respawn_delay: float = 1.2
# Seconds the character takes to shrink when dying.
@export var death_shrink_time: float = 0.65

# True while the player is fishing.
var is_fishing: bool = false
# Animation that flashes the player red when hurt.
var damage_flash_tween: Tween = null
# Animation played when the player dies.
var death_tween: Tween = null
# Normal size and position of each sprite, restored after effects such as sinking.
var base_anim_scale: Vector2
var base_hair_scale: Vector2
var base_shirt_scale: Vector2
var base_pants_scale: Vector2
var base_anim_position: Vector2
var base_hair_position: Vector2
var base_shirt_position: Vector2
var base_pants_position: Vector2
# Seconds left before the player can chop or mine again.
var chop_cooldown_timer: float = 0.0
# Length of the current chopping or mining cooldown.
var chop_cooldown_max: float = 1.5
# Picture of the held item in the player's hand.
var hand_sprite: Sprite2D = null
# Most health the player can have.
var max_health: int = 10
# True while the player is dead.
var is_dead: bool = false
# Seconds left before the player can attack again.
var attack_cooldown: float = 0.0
# Seconds between sword attacks.
const ATTACK_COOLDOWN_MAX: float = 1.5
# Distance in pixels a sword attack reaches.
const ATTACK_RANGE: float = 120.0
# Damage dealt by a wooden sword.
const SWORD_DAMAGE: int = 2
# Damage dealt by a stone sword.
const STONE_SWORD_DAMAGE: int = 4

# Seconds after starting to block in which a hit counts as a parry.
const PARRY_WINDOW: float = 0.16
# Sword durability used by a parry.
const PARRY_DURABILITY_COST: int = 1
# Sword durability used by a normal block.
const BLOCK_DURABILITY_COST: int = 4
# Damage dealt back to an enemy that is parried.
const PARRY_COUNTER_DAMAGE: int = 9999

# Seconds before the player can block again.
const BLOCK_COOLDOWN_MAX: float = 0.6

# Speed of a roll.
const ROLL_SPEED: float = 900.0
# Seconds a roll lasts.
const ROLL_DURATION: float = 0.22
# Seconds before the player can roll again.
const ROLL_COOLDOWN: float = 0.8

# True during a roll.
var is_rolling: bool = false
# True while the player cannot be hurt, such as during a roll.
var is_invulnerable: bool = false
# Seconds left in the current roll.
var roll_timer: float = 0.0
# Seconds left before the next roll.
var roll_cooldown: float = 0.0
# Direction of the current roll.
var roll_direction: Vector2 = Vector2.ZERO

# Offset used to find the point at the player's feet.
const FEET_OFFSET: float = 1.0
# The camera that follows the local player.
var camera: Camera2D = null
# True while the player is holding a block.
var is_blocking: bool = false
# Seconds left in the parry window.
var parry_timer: float = 0.0
# Seconds left before the player can block again.
var block_cooldown: float = 0.0
# True right after a successful parry.
var _parry_just_landed: bool = false
# Picture of the offhand item.
var offhand_sprite: Sprite2D = null

# Seconds spent in deep water.
var drowning_timer: float = 0.0
# True once the player has drowned, so they only die once.
var drowning_dead: bool = false
# Seconds in water before the player drowns.
const DROWN_TIME: float = 8.0
# How much the player is slowed at the point of drowning.
const DROWN_SLOW_MAX: float = 0.45
# How far the character sinks while drowning.
const DROWN_SINK_PIXELS: float = 18.0


# Gives control of this character to the player whose ID is in its name.
func _enter_tree():
	if multiplayer.has_multiplayer_peer():
		set_multiplayer_authority(name.to_int())
	else:
		set_multiplayer_authority(1)


# Sets up the light, sprites, camera, hand items and Steam ID registration.
func _ready():
	var lighting_system = get_tree().root.get_node_or_null("Scene/LightingSystem")
	if lighting_system:
		lighting_system.add_light_source(self, 0.0, 0.0)
	z_index = 2
	add_to_group("players")
	hair_sprite.visible = true
	shirt_sprite.visible = true
	pants_sprite.visible = true
	base_anim_scale = anim.scale
	base_hair_scale = hair_sprite.scale
	base_shirt_scale = shirt_sprite.scale
	base_pants_scale = pants_sprite.scale
	base_anim_position = anim.position
	base_hair_position = hair_sprite.position
	base_shirt_position = shirt_sprite.position
	base_pants_position = pants_sprite.position
	collision_layer = 1
	collision_mask = 1
	if not multiplayer.has_multiplayer_peer():
		collision_layer = 1
		collision_mask = 1
		$CollisionShape2D.disabled = false
	elif not is_multiplayer_authority():
		collision_layer = 0
		collision_mask = 0
		$CollisionShape2D.disabled = true
	_setup_hand()
	call_deferred("_setup_camera")
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority() \
		and multiplayer.get_unique_id() != 0:
		_register_steam_id_when_ready.call_deferred()


# Tells the host which Steam account owns this character, retrying until the connection is ready.
func _register_steam_id_when_ready():
	var attempts = 0
	while attempts < 20:
		await get_tree().create_timer(0.5).timeout
		if not is_instance_valid(self):
			return
		if not multiplayer.has_multiplayer_peer():
			return
		if multiplayer.get_multiplayer_peer().get_connection_status() \
			== MultiplayerPeer.CONNECTION_CONNECTED:
			break
		attempts += 1
	if not is_instance_valid(self):
		return
	if multiplayer.get_multiplayer_peer().get_connection_status() \
		!= MultiplayerPeer.CONNECTION_CONNECTED:
		print("ERROR: peer never connected, skipping steam id registration")
		return
	var scene_node = get_tree().root.get_node_or_null("Scene")
	if scene_node:
		if multiplayer.is_server():
			scene_node.peer_to_steam_id[multiplayer.get_unique_id()] = Steam.getSteamID()
			scene_node.sync_peer_steam_ids.rpc(scene_node.peer_to_steam_id)
		else:
			scene_node.register_steam_id.rpc_id(1, Steam.getSteamID())


# Plays an animation on the body and every visible clothing layer.
func _play_anim(anim_name: String):
	anim.play(anim_name)
	if hair_sprite.visible:
		hair_sprite.play(anim_name)
	if shirt_sprite.visible:
		shirt_sprite.play(anim_name)
	if pants_sprite.visible:
		pants_sprite.play(anim_name)

# Custom picture size for each item held in the hand.
var _hand_scales: Dictionary = {}


# Creates the sprite that shows the held item.
func _setup_hand():
	hand_sprite = Sprite2D.new()
	hand_sprite.position = Vector2(-7, -19)
	hand_sprite.z_as_relative = true
	hand_sprite.z_index = 0
	hand_sprite.scale = Vector2(0.017, 0.017)
	hand_sprite.visible = false
	hand_sprite.modulate = Color(1, 1, 1, 0)
	add_child(hand_sprite)
	offhand_sprite = Sprite2D.new()
	offhand_sprite.position = Vector2(7, -19)
	offhand_sprite.z_as_relative = true
	offhand_sprite.z_index = 0
	offhand_sprite.scale = Vector2(0.017, 0.017)
	offhand_sprite.visible = false
	offhand_sprite.modulate = Color(1, 1, 1, 0)
	add_child(offhand_sprite)
	for item_name in Inventory.TEXTURE_MAP:
		var item_texture = Inventory.TEXTURE_MAP[item_name]
		if item_texture:
			var s = item_texture.get_size()
			if s.x > 0 and s.y > 0:
				_hand_scales[item_name] = Vector2(12.0 / s.x, 12.0 / s.y)


# Sets the picture and size of the held item.
func _apply_hand_texture(item_texture: Texture2D):
	var scale = _hand_scales.get(synced_held_item, Vector2(0.017, 0.017))
	hand_sprite.scale = scale
	hand_sprite.texture = item_texture
	hand_sprite.visible = false
	hand_sprite.modulate = Color(1, 1, 1, 0)
	RenderingServer.force_draw()
	hand_sprite.visible = true
	hand_sprite.modulate = Color(1, 1, 1, 1)


# Attaches the camera to the local player only.
func _setup_camera():
	var is_local = not multiplayer.has_multiplayer_peer() or is_multiplayer_authority()
	if not is_local:
		return
	camera = get_tree().root.get_node_or_null("Camera2D")
	if not camera:
		camera = Camera2D.new()
		camera.name = "Camera2D"
		get_tree().root.add_child(camera)
	camera.enabled = true
	camera.make_current()
	camera.global_position = global_position


# Does nothing while a menu is open. The main per frame work happens in _physics_process.
func _process(delta):
	if _is_inventory_open():
		return


# Every physics frame: moves the camera, reads movement keys, walks, rolls, blocks, animates and sends the player's position to others.
func _physics_process(delta):
	if camera and (not multiplayer.has_multiplayer_peer() or is_multiplayer_authority()):
		camera.global_position = global_position
	if is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	_update_drowning(delta)
	if roll_cooldown > 0.0:
		roll_cooldown = max(roll_cooldown - delta, 0.0)
	if is_rolling and (is_multiplayer_authority() or not multiplayer.has_multiplayer_peer()):
		_process_roll(delta)
		return
	if _is_inventory_open():
		velocity = Vector2.ZERO
		move_and_slide()
		if is_multiplayer_authority() or not multiplayer.has_multiplayer_peer():
			_play_anim("idle")
		return
	if is_fishing and (is_multiplayer_authority() or not multiplayer.has_multiplayer_peer()):
		velocity = Vector2.ZERO
		move_and_slide()
		_play_anim("idle")
		if multiplayer.has_multiplayer_peer() \
			and multiplayer.get_multiplayer_peer().get_connection_status() \
			== MultiplayerPeer.CONNECTION_CONNECTED:
			sync_position_rpc.rpc(
				global_position.x, global_position.y, velocity.x, velocity.y, synced_held_item,
			)
		return
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		velocity = synced_velocity
		move_and_slide()
		if synced_velocity.length() > 0:
			_play_anim("walk_down")
		else:
			_play_anim("idle")
		hair_sprite.visible = synced_hair
		shirt_sprite.visible = synced_shirt
		pants_sprite.visible = synced_pants
		_update_hand_sprite()
		return

	if is_multiplayer_authority() or not multiplayer.has_multiplayer_peer():
		var cursor = get_tree().root.get_node_or_null("Scene/CanvasLayer/Cursor")

		if chop_cooldown_timer > 0:
			chop_cooldown_timer = max(chop_cooldown_timer - delta, 0.0)
			var pct = chop_cooldown_timer / chop_cooldown_max if chop_cooldown_max > 0 else 0.0
			if cursor:
				cursor.show_cooldown(pct)

		if attack_cooldown > 0:
			attack_cooldown = max(attack_cooldown - delta, 0.0)
			if cursor:
				cursor.show_cooldown(attack_cooldown / ATTACK_COOLDOWN_MAX)

		if parry_timer > 0.0:
			parry_timer = max(parry_timer - delta, 0.0)
			if parry_timer <= 0.0:
				_set_parry_highlight(false)

		if block_cooldown > 0.0:
			block_cooldown = max(block_cooldown - delta, 0.0)

		if is_blocking and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_stop_blocking()

		if Input.is_action_just_pressed("roll") and roll_cooldown <= 0.0 and not is_blocking:
			_start_roll()
			_process_roll(delta)
			return

		var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
		if hotbar:
			var slot = Inventory.slots[hotbar.current_slot - 1]
			synced_held_item = slot["item"]
		var hearts_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hearts")
		if hearts_ui:
			hearts_ui.update_hearts(synced_health)

	var direction = Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		if global_position.x > -9999970:
			direction.x -= 1
	if Input.is_action_pressed("move_right"):
		if global_position.x < 9999970:
			direction.x += 1
	if Input.is_action_pressed("move_up"):
		if global_position.y > -9999890:
			direction.y -= 1
	if Input.is_action_pressed("move_down"):
		if global_position.y < 9999990:
			direction.y += 1
	if direction.length() > 0:
		_play_anim("walk_down")
	else:
		_play_anim("idle")
	direction = direction.normalized()
	velocity = direction * speed
	if drowning_timer > 0.0:
		var drown_pct: float = clamp(drowning_timer / DROWN_TIME, 0.0, 1.0)
		velocity *= lerp(1.0, DROWN_SLOW_MAX, drown_pct)
	synced_velocity = velocity
	move_and_slide()
	_update_hand_sprite()
	_update_offhand_sprite()

	if multiplayer.has_multiplayer_peer() and multiplayer.get_unique_id() != 0 \
		and multiplayer.get_multiplayer_peer().get_connection_status() \
		== MultiplayerPeer.CONNECTION_CONNECTED:
		sync_position_rpc.rpc(
			global_position.x, global_position.y, velocity.x, velocity.y, synced_held_item,
		)
	if is_multiplayer_authority() or not multiplayer.has_multiplayer_peer():
		_update_torch_light()
	if not multiplayer.has_multiplayer_peer():
		return


# Handles attack, block and roll input for the local player.
func _input(event):
	if is_dead:
		return
	if is_rolling:
		return
	if _is_inventory_open():
		return
	if not (is_multiplayer_authority() or not multiplayer.has_multiplayer_peer()):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _is_holding_sword() and chop_cooldown_timer <= 0.0 and attack_cooldown <= 0.0:
			_try_attack()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and _is_holding_raw_fish():
			_send_fish_pun()
		elif event.pressed and _is_holding_sword():
			if block_cooldown <= 0.0:
				_start_blocking()
		elif not event.pressed:
			_stop_blocking()


# Swings the sword at the nearest enemy, boss, egg or chicken in range and starts the attack cooldown.
func _try_attack():
	var scene_node = get_tree().root.get_node("Scene")
	var mouse_world_pos = get_global_mouse_position()

	for enemy in get_tree().get_nodes_in_group("night_enemies"):
		if not is_instance_valid(enemy):
			continue
		var enemy_centre: Vector2 = (enemy as Node2D).global_position + Vector2(0, -30)
		if global_position.distance_to(enemy_centre) < ATTACK_RANGE:
			_apply_attack_cooldown()
			if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
				scene_node.request_damage_night_enemy.rpc_id(1, enemy.get("enemy_id"), _get_sword_damage())
			else:
				if enemy.has_method("take_damage"):
					enemy.take_damage(_get_sword_damage())
			_consume_sword_durability()
			return

	for boss in get_tree().get_nodes_in_group("bosses"):
		if not is_instance_valid(boss):
			continue
		var boss_centre: Vector2 = (boss as Node2D).global_position
		if global_position.distance_to(boss_centre) < ATTACK_RANGE:
			_apply_attack_cooldown()
			if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
				if scene_node.has_method("request_damage_boss"):
					scene_node.request_damage_boss.rpc_id(1, boss.get("enemy_id"), _get_sword_damage())
			else:
				if boss.has_method("take_damage"):
					boss.take_damage(_get_sword_damage())
			_consume_sword_durability()
			return

	for egg in get_tree().get_nodes_in_group("boss_eggs"):
		if not is_instance_valid(egg):
			continue
		if global_position.distance_to((egg as Node2D).global_position) > ATTACK_RANGE:
			continue
		if mouse_world_pos.distance_to((egg as Node2D).global_position) > 60.0:
			continue
		_apply_attack_cooldown()
		if egg.has_method("take_damage"):
			egg.take_damage(_get_sword_damage())
		_consume_sword_durability()
		return

	for child in scene_node.get_children():
		if child == self:
			continue
		if not child is CharacterBody2D:
			continue
		if not child is Node2D:
			continue
		var dist_to_player: float = global_position.distance_to(child.global_position)
		var dist_to_mouse: float = mouse_world_pos.distance_to(child.global_position)
		if dist_to_player > ATTACK_RANGE:
			continue
		if dist_to_mouse > 60.0:
			continue
		if child.is_in_group("players"):
			if multiplayer.has_multiplayer_peer() and child.name.to_int() == multiplayer.get_unique_id():
				continue
			_apply_attack_cooldown()
			if multiplayer.has_multiplayer_peer():
				var target_id = child.name.to_int()
				scene_node.request_deal_damage.rpc_id(1, target_id, _get_sword_damage())
			else:
				child.take_damage(_get_sword_damage())
			_consume_sword_durability()
			return


# Starts the attack cooldown and shows it on the cursor.
func _apply_attack_cooldown() -> void:
	attack_cooldown = ATTACK_COOLDOWN_MAX
	var cursor = get_tree().root.get_node_or_null("Scene/CanvasLayer/Cursor")
	if cursor:
		cursor.show_cooldown(1.0)


# Uses up sword durability and removes the sword when it breaks. Returns false if there was no sword.
func _consume_sword_durability(amount: int = 1) -> bool:
	var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	if not hotbar:
		return false
	var slot_index = hotbar.current_slot - 1
	var slot = Inventory.slots[slot_index]
	if slot["item"] == "Sword" or slot["item"] == "Stone Sword":
		slot["count"] -= amount
		if slot["count"] <= 0:
			Inventory.remove_item(slot_index, false)
		else:
			Inventory.inventory_changed.emit()
		return true
	return false


# Kills a chicken with a burst of feathers.
func _kill_chicken(chicken: Node2D) -> void:
	_spawn_feather_burst(chicken.global_position)
	if chicken.has_method("take_damage"):
		chicken.take_damage(9999)
	else:
		chicken.queue_free()


# Creates a short burst of feather particles at a position.
func _spawn_feather_burst(world_position: Vector2) -> void:
	var particles := CPUParticles2D.new()
	get_tree().root.get_node("Scene").add_child(particles)
	particles.global_position = world_position
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.amount = 18
	particles.lifetime = 0.55
	particles.speed_scale = 1.0
	particles.direction = Vector2(0, -1)
	particles.spread = 180.0
	particles.gravity = Vector2(0, 120)
	particles.initial_velocity_min = 60.0
	particles.initial_velocity_max = 140.0
	particles.scale_amount_min = 2.5
	particles.scale_amount_max = 5.0
	particles.color = Color(0.75, 0.75, 0.75, 1.0)
	particles.color_ramp = null
	var timer := get_tree().create_timer(particles.lifetime + 0.1)
	timer.timeout.connect(func(): if is_instance_valid(particles): particles.queue_free())


# Returns true if the held item is a sword.
func _is_holding_sword() -> bool:
	return synced_held_item == "Sword" or synced_held_item == "Stone Sword"


# Returns true if the held item is a fish.
func _is_holding_raw_fish() -> bool:
	var scene_node = get_tree().root.get_node_or_null("Scene")
	if scene_node and scene_node.has_method("_is_fish_item_name"):
		return scene_node._is_fish_item_name(synced_held_item)
	return false


# Sends a random fish joke to the chat.
func _send_fish_pun() -> void:
	var chat_box = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
	if not chat_box:
		return
	var puns := [
		"This conversation is getting a little fishy.",
		"I am hooked on bad jokes.",
		"Cod help us all.",
		"That was reel unnecessary.",
	]
	var msg: String = puns[randi() % puns.size()]
	if multiplayer.has_multiplayer_peer():
		chat_box._broadcast_message.rpc(msg)
	else:
		chat_box._add_message(msg)


# Returns the damage of the held sword.
func _get_sword_damage() -> int:
	if synced_held_item == "Stone Sword":
		return STONE_SWORD_DAMAGE
	return SWORD_DAMAGE


# Flashes the screen white to show a successful parry.
func _parry_success_flash() -> void:
	var canvas = get_tree().root.get_node_or_null("Scene/CanvasLayer")
	if canvas:
		var flash := ColorRect.new()
		flash.color = Color(1, 1, 1, 0.85)
		flash.anchor_right = 1.0
		flash.anchor_bottom = 1.0
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas.add_child(flash)
		var t := create_tween()
		t.tween_property(flash, "color:a", 0.0, 0.25)
		t.tween_callback(flash.queue_free)
	var orig_c := Color(1, 1, 1, 1)
	var blast_c := Color(3.0, 3.0, 3.0, 1.0)
	anim.modulate = blast_c
	hair_sprite.modulate = blast_c
	shirt_sprite.modulate = blast_c
	pants_sprite.modulate = blast_c
	await get_tree().create_timer(0.12).timeout
	anim.modulate = orig_c
	hair_sprite.modulate = orig_c
	shirt_sprite.modulate = orig_c
	pants_sprite.modulate = orig_c


# Raises the sword to block and opens the parry window.
func _start_blocking() -> void:
	is_blocking = true
	parry_timer = PARRY_WINDOW
	if hand_sprite:
		hand_sprite.rotation_degrees = -35.0
	_set_parry_highlight(true)


# Brightens or resets the character's colour to show the parry window.
func _set_parry_highlight(on: bool) -> void:
	var tint_colour := Color(1.8, 1.8, 1.8, 1.0) if on else Color(1, 1, 1, 1)
	anim.modulate = tint_colour
	hair_sprite.modulate = tint_colour
	shirt_sprite.modulate = tint_colour
	pants_sprite.modulate = tint_colour


# Lowers the sword and starts the block cooldown.
func _stop_blocking() -> void:
	if is_blocking and not _parry_just_landed:
		block_cooldown = BLOCK_COOLDOWN_MAX
	_parry_just_landed = false
	is_blocking = false
	parry_timer = 0.0
	if hand_sprite:
		hand_sprite.rotation_degrees = 0.0
	_set_parry_highlight(false)


# Starts a roll in the direction the player is pressing, becoming invulnerable.
func _start_roll() -> void:
	var move_direction := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		move_direction.x -= 1
	if Input.is_action_pressed("move_right"):
		move_direction.x += 1
	if Input.is_action_pressed("move_up"):
		move_direction.y -= 1
	if Input.is_action_pressed("move_down"):
		move_direction.y += 1
	if move_direction.length() < 0.01:
		move_direction = velocity if velocity.length() > 0.01 else Vector2(0, 1)
	roll_direction = move_direction.normalized()
	is_rolling = true
	is_invulnerable = true
	roll_timer = ROLL_DURATION
	roll_cooldown = ROLL_COOLDOWN
	_add_roll_collision_exceptions()
	if is_blocking:
		_stop_blocking()
	_play_anim("walk_down")


# Lets the player roll through enemies without being blocked by them.
func _add_roll_collision_exceptions() -> void:
	for enemy in get_tree().get_nodes_in_group("night_enemies"):
		if not is_instance_valid(enemy):
			continue
		var body: Node = enemy.get_node_or_null("StaticBody2D")
		if body and body is PhysicsBody2D:
			add_collision_exception_with(body)
	for boss in get_tree().get_nodes_in_group("bosses"):
		if is_instance_valid(boss) and boss is PhysicsBody2D:
			add_collision_exception_with(boss)


# Makes enemies solid again after the roll.
func _remove_roll_collision_exceptions() -> void:
	for enemy in get_tree().get_nodes_in_group("night_enemies"):
		if not is_instance_valid(enemy):
			continue
		var body: Node = enemy.get_node_or_null("StaticBody2D")
		if body and body is PhysicsBody2D:
			remove_collision_exception_with(body)
	for boss in get_tree().get_nodes_in_group("bosses"):
		if is_instance_valid(boss) and boss is PhysicsBody2D:
			remove_collision_exception_with(boss)


# Moves the player during a roll and ends it when the time is up.
func _process_roll(delta: float) -> void:
	roll_timer -= delta
	velocity = roll_direction * ROLL_SPEED
	synced_velocity = velocity
	move_and_slide()
	_update_hand_sprite()
	_update_offhand_sprite()
	if multiplayer.has_multiplayer_peer() and multiplayer.get_unique_id() != 0 \
		and multiplayer.get_multiplayer_peer().get_connection_status() \
		== MultiplayerPeer.CONNECTION_CONNECTED:
		sync_position_rpc.rpc(
			global_position.x, global_position.y, velocity.x, velocity.y, synced_held_item,
		)
	if is_multiplayer_authority() or not multiplayer.has_multiplayer_peer():
		_update_torch_light()
	if roll_timer <= 0.0:
		_end_roll()


# Finishes the roll and removes invulnerability.
func _end_roll() -> void:
	is_rolling = false
	is_invulnerable = false
	roll_timer = 0.0
	_remove_roll_collision_exceptions()


# Called when an enemy hits the player. A well timed block parries it, a normal block reduces the damage and otherwise the player takes damage.
func defend_enemy_attack(amount: int, enemy: Node = null) -> void:
	if is_dead:
		return
	if is_blocking and _is_holding_sword():
		if parry_timer > 0.0:
			_consume_sword_durability(PARRY_DURABILITY_COST)
			parry_timer = 0.0
			block_cooldown = 0.0
			_parry_just_landed = true
			_parry_success_flash()
			if enemy and enemy.has_method("take_damage"):
				if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
					var scene_node = get_tree().root.get_node_or_null("Scene")
					if scene_node and scene_node.has_method("request_damage_night_enemy"):
						scene_node.request_damage_night_enemy.rpc_id(1, enemy.get("enemy_id"), PARRY_COUNTER_DAMAGE)
				else:
					enemy.take_damage(PARRY_COUNTER_DAMAGE)
			return
		if _consume_sword_durability(BLOCK_DURABILITY_COST):
			return
	take_damage(amount)


# Reduces the player's health, flashes them red and starts death at zero. Rolling players ignore damage.
func take_damage(amount: int):
	if is_invulnerable:
		return
	if not is_multiplayer_authority() and multiplayer.has_multiplayer_peer():
		return
	if is_dead:
		return
	synced_health = max(synced_health - amount, 0)
	var right_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/RightUI")
	if right_ui:
		right_ui.regen_timer = 0.0
	if synced_health <= 0:
		die()
	else:
		_flash_damage()


# Adds health, up to the maximum.
func heal(amount: int):
	if not is_multiplayer_authority() and multiplayer.has_multiplayer_peer():
		return
	if is_dead:
		return
	synced_health = min(synced_health + amount, max_health)


# Handles death: drops items, sends a message and starts the respawn sequence.
func die():
	is_dead = true
	if is_multiplayer_authority() or not multiplayer.has_multiplayer_peer():
		var cave_gen = get_tree().root.get_node_or_null("Scene/CaveWorldGen")
		if cave_gen and cave_gen.get("in_cave"):
			if cave_gen.has_method("request_player_died"):
				cave_gen.request_player_died(global_position)
			cave_gen.exit_cave(self)
	var scene_node = get_tree().root.get_node("Scene")
	var drops: Array = []
	for i in Inventory.slots.size():
		var slot = Inventory.slots[i]
		if slot["item"] != "":
			var is_fish = (
				scene_node._is_fish_item_name(slot["item"])
				if scene_node.has_method("_is_fish_item_name")
				else slot["item"] in scene_node.FISH_ITEM_NAMES
			)
			var tool_names := [
				"Axe", "Stone Axe", "Pickaxe", "Stone Pickaxe", "Sword", "Stone Sword",
			]
			var durability = slot.get(
				"durability", slot["count"] if (slot["item"] in tool_names or is_fish) else 60,
			)
			drops.append({
				"item": slot["item"], "count": slot["count"], "durability": durability,
				"hotbar": true, "index": i,
			})
	for i in Inventory.inv_slots.size():
		var slot = Inventory.inv_slots[i]
		if slot["item"] != "":
			var is_fish = (
				scene_node._is_fish_item_name(slot["item"])
				if scene_node.has_method("_is_fish_item_name")
				else slot["item"] in scene_node.FISH_ITEM_NAMES
			)
			var tool_names2 := [
				"Axe", "Stone Axe", "Pickaxe", "Stone Pickaxe", "Sword", "Stone Sword",
			]
			var durability = slot.get(
				"durability", slot["count"] if (slot["item"] in tool_names2 or is_fish) else 60,
			)
			drops.append({
				"item": slot["item"], "count": slot["count"], "durability": durability,
				"hotbar": false, "index": i,
			})
	for drop in drops:
		var is_tool = Inventory.non_stackable_items.has(drop["item"])
		if is_tool:
			var angle = randf_range(0, TAU)
			var radius = randf_range(40, 80)
			var drop_pos = global_position + Vector2(cos(angle), sin(angle)) * radius
			if multiplayer.has_multiplayer_peer():
				if multiplayer.is_server():
					scene_node.host_spawn_floor_item(drop_pos, drop["item"], drop["durability"])
				else:
					scene_node.request_spawn_floor_item.rpc_id(
						1, drop_pos.x, drop_pos.y, drop["item"], drop["durability"],
					)
			else:
				scene_node.host_spawn_floor_item(drop_pos, drop["item"], drop["durability"])
		else:
			var positions_x: Array = []
			var positions_y: Array = []
			for i in drop["count"]:
				var angle = randf_range(0, TAU)
				var radius = randf_range(40, 80)
				var drop_pos = global_position + Vector2(cos(angle), sin(angle)) * radius
				positions_x.append(drop_pos.x)
				positions_y.append(drop_pos.y)
			if multiplayer.has_multiplayer_peer():
				if multiplayer.is_server():
					for i in positions_x.size():
						scene_node.host_spawn_floor_item(Vector2(positions_x[i], positions_y[i]), drop["item"], 1)
				else:
					scene_node.request_spawn_floor_items_batch.rpc_id(
						1, positions_x, positions_y, drop["item"], 1,
					)
			else:
				for i in positions_x.size():
					scene_node.host_spawn_floor_item(Vector2(positions_x[i], positions_y[i]), drop["item"], 1)
	for i in Inventory.slots.size():
		if Inventory.slots[i]["item"] != "":
			Inventory.remove_item(i, false)
	for i in Inventory.inv_slots.size():
		if Inventory.inv_slots[i]["item"] != "":
			Inventory.remove_item(i, true)
	await _play_death_respawn_sequence(scene_node)

# The item that was last shown in the hand.
var _last_hand_item: String = ""


# Shows the held item in the hand when the selected slot changes.
func _update_hand_sprite():
	if not hand_sprite:
		return
	if synced_held_item == "":
		if _last_hand_item != "":
			_last_hand_item = ""
			hand_sprite.texture = null
			hand_sprite.visible = false
			hand_sprite.modulate = Color(1, 1, 1, 0)
		return
	if synced_held_item == _last_hand_item:
		return
	hand_sprite.visible = false
	hand_sprite.modulate = Color(1, 1, 1, 0)
	var item_texture = Inventory.get_texture(synced_held_item)
	if item_texture == null:
		for slot in Inventory.slots:
			if slot["item"] == synced_held_item and slot["texture"] != null:
				item_texture = slot["texture"]
				break
	if item_texture == null:
		for slot in Inventory.inv_slots:
			if slot["item"] == synced_held_item and slot["texture"] != null:
				item_texture = slot["texture"]
				break
	if item_texture == null:
		return
	var tex_size = item_texture.get_size()
	if tex_size.x <= 0 or tex_size.y <= 0:
		return
	_last_hand_item = synced_held_item
	_apply_hand_texture(item_texture)

# The item that was last shown in the offhand.
var _last_offhand_item: String = ""


# Shows the offhand item when it changes.
func _update_offhand_sprite():
	if not offhand_sprite:
		return
	var offhand_item: String = Inventory.offhand_slot.get("item", "")
	if offhand_item == "":
		if _last_offhand_item != "":
			_last_offhand_item = ""
			offhand_sprite.texture = null
			offhand_sprite.visible = false
			offhand_sprite.modulate = Color(1, 1, 1, 0)
		return
	if offhand_item == _last_offhand_item:
		return
	var item_texture = Inventory.get_texture(offhand_item)
	if item_texture == null:
		item_texture = Inventory.offhand_slot.get("texture", null)
	if item_texture == null:
		return
	var tex_size = item_texture.get_size()
	if tex_size.x <= 0 or tex_size.y <= 0:
		return
	_last_offhand_item = offhand_item
	offhand_sprite.texture = item_texture
	offhand_sprite.scale = _hand_scales.get(offhand_item, Vector2(0.017, 0.017))
	offhand_sprite.visible = true
	offhand_sprite.modulate = Color(1, 1, 1, 1)


# Starts the cooldown after chopping or mining.
func start_chop_cooldown(duration: float):
	chop_cooldown_max = duration
	chop_cooldown_timer = duration


# Returns true if the inventory, chat or wardrobe is open.
func _is_inventory_open() -> bool:
	var inventory_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
	var chat_box = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
	var wardrobe = get_tree().root.get_node_or_null("Scene/CanvasLayer/Wardrobe_UI")
	var chat_open = chat_box != null and chat_box.get("is_open")
	return (inventory_ui != null and inventory_ui.visible) or chat_open or (wardrobe != null and wardrobe.visible)


# Returns true if the chat is open.
func _is_chat_open() -> bool:
	var chat_box = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
	return chat_box != null and chat_box.is_open

# Sent when a player changes their clothing so everyone sees it.
@rpc("any_peer", "call_local", "reliable")


# Shows or hides the hair, shirt and pants layers.
func sync_cosmetics_rpc(hair: bool, shirt: bool, pants: bool):
	synced_hair = hair
	synced_shirt = shirt
	synced_pants = pants
	hair_sprite.visible = hair
	shirt_sprite.visible = shirt
	pants_sprite.visible = pants


# Shares the clothing choice with every player, or applies it directly in single player.
func apply_cosmetics(hair: bool, shirt: bool, pants: bool):
	if multiplayer.has_multiplayer_peer():
		sync_cosmetics_rpc.rpc(hair, shirt, pants)
	else:
		sync_cosmetics_rpc(hair, shirt, pants)


# Slows and sinks the player in deep water and kills them if they stay too long.
func _update_drowning(delta: float):
	if is_dead:
		return
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return

	var in_water := false
	var cave_gen = get_tree().root.get_node_or_null("Scene/CaveWorldGen")
	if cave_gen and cave_gen.get("in_cave"):
		in_water = cave_gen._water_tiles.has(cave_gen.world_to_tile(global_position))
	else:
		var world_gen = get_tree().root.get_node_or_null("Scene/WorldGen")
		in_water = world_gen != null \
			and world_gen.has_method("is_water_at") \
			and world_gen.is_water_at(global_position)

	if in_water:
		drowning_timer += delta
	else:
		drowning_timer = max(drowning_timer - delta * 2.0, 0.0)

	var drown_pct: float = clamp(drowning_timer / DROWN_TIME, 0.0, 1.0)
	_set_drowning_alpha(drown_pct)
	if multiplayer.has_multiplayer_peer() \
		and multiplayer.get_multiplayer_peer().get_connection_status() \
		== MultiplayerPeer.CONNECTION_CONNECTED:
		sync_drowning_alpha_rpc.rpc(drown_pct)
	if not multiplayer.has_multiplayer_peer():
		return

	if drowning_timer >= DROWN_TIME and not drowning_dead:
		drowning_dead = true
		_send_death_message("drowned")
		take_damage(max_health)
	elif drowning_timer <= 0.0:
		drowning_dead = false


# Sinks the sprites into the water by an amount that grows with the drowning progress.
func _set_drowning_alpha(progress: float):
	var sink: float = DROWN_SINK_PIXELS * clamp(progress, 0.0, 1.0)
	anim.position = base_anim_position + Vector2(0, sink)
	hair_sprite.position = base_hair_position + Vector2(0, sink)
	shirt_sprite.position = base_shirt_position + Vector2(0, sink)
	pants_sprite.position = base_pants_position + Vector2(0, sink)
	if hand_sprite:
		hand_sprite.position.y = -19 + sink
	if offhand_sprite:
		offhand_sprite.position.y = -19 + sink

# Sent often to show other players how far this player has sunk.
@rpc("any_peer", "call_remote", "unreliable_ordered")


# Shows another player's sinking on this game.
func sync_drowning_alpha_rpc(alpha: float):
	if is_multiplayer_authority():
		return
	_set_drowning_alpha(alpha)


# Announces in the chat how the player died.
func _send_death_message(cause: String):
	var chat_box = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
	if not chat_box:
		return
	var player_name = "Player"
	if multiplayer.has_multiplayer_peer():
		player_name = Steam.getFriendPersonaName(Steam.getSteamID())
	var msg = player_name + " " + cause
	if multiplayer.has_multiplayer_peer():
		chat_box._broadcast_message.rpc(msg)
	else:
		chat_box._add_message(msg)


# Shrinks the character, waits, then respawns them.
func _play_death_respawn_sequence(scene_node):
	drowning_timer = 0.0
	drowning_dead = false

	if death_tween:
		death_tween.kill()

	velocity = Vector2.ZERO
	$CollisionShape2D.disabled = true
	if hand_sprite:
		hand_sprite.visible = false
		hand_sprite.modulate = Color(1, 1, 1, 0)
		_last_hand_item = ""
	if offhand_sprite:
		offhand_sprite.visible = false
		offhand_sprite.modulate = Color(1, 1, 1, 0)
		_last_offhand_item = ""

	anim.modulate = Color(1, 0.05, 0.05, 1)
	hair_sprite.modulate = Color(1, 0.05, 0.05, 1)
	shirt_sprite.modulate = Color(1, 0.05, 0.05, 1)
	pants_sprite.modulate = Color(1, 0.05, 0.05, 1)

	death_tween = create_tween()
	death_tween.set_parallel(true)
	death_tween.tween_property(anim, "scale", base_anim_scale * 0.1, death_shrink_time)
	death_tween.tween_property(hair_sprite, "scale", base_hair_scale * 0.1, death_shrink_time)
	death_tween.tween_property(shirt_sprite, "scale", base_shirt_scale * 0.1, death_shrink_time)
	death_tween.tween_property(pants_sprite, "scale", base_pants_scale * 0.1, death_shrink_time)
	death_tween.tween_property(anim, "modulate:a", 0.0, death_shrink_time)
	death_tween.tween_property(hair_sprite, "modulate:a", 0.0, death_shrink_time)
	death_tween.tween_property(shirt_sprite, "modulate:a", 0.0, death_shrink_time)
	death_tween.tween_property(pants_sprite, "modulate:a", 0.0, death_shrink_time)

	await death_tween.finished
	await get_tree().create_timer(respawn_delay).timeout

	if not is_instance_valid(self):
		return

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		if scene_node:
			scene_node.request_respawn.rpc_id(1, name.to_int())
	else:
		var spawn_pos = get_tree().root.get_node("Scene")._find_safe_spawn(Vector2(0, 0))
		if scene_node and scene_node.has_method("_preload_spawn_area"):
			scene_node._preload_spawn_area(spawn_pos)
		_do_respawn(spawn_pos)

# Sent by a player to ask the host for a respawn position.
@rpc("any_peer", "call_remote", "reliable")


# Host only. Works out a respawn position and sends it back.
func request_respawn_position_rpc():
	if not multiplayer.is_server():
		return
	var scene_node = get_tree().root.get_node_or_null("Scene")
	if not scene_node:
		return
	var spawn_pos = scene_node._find_safe_spawn(Vector2(0, 0))
	var sender = multiplayer.get_remote_sender_id()
	receive_respawn_position_rpc.rpc_id(sender, spawn_pos.x, spawn_pos.y)

# Sent by the host with the position to respawn at.
@rpc("any_peer", "call_remote", "reliable")


# Respawns the player at the position sent by the host.
func receive_respawn_position_rpc(px: float, py: float):
	_do_respawn(Vector2(px, py))


# Moves the player to the spawn position and restores their health.
func _do_respawn(spawn_pos: Vector2):
	drowning_timer = 0.0
	drowning_dead = false
	global_position = spawn_pos
	synced_health = max_health

	var right_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/RightUI")
	if right_ui:
		right_ui.reset_stats()

	anim.scale = base_anim_scale
	hair_sprite.scale = base_hair_scale
	shirt_sprite.scale = base_shirt_scale
	pants_sprite.scale = base_pants_scale
	anim.position = base_anim_position
	hair_sprite.position = base_hair_position
	shirt_sprite.position = base_shirt_position
	pants_sprite.position = base_pants_position

	anim.modulate = Color(1, 1, 1, 1)
	hair_sprite.modulate = Color(1, 1, 1, 1)
	shirt_sprite.modulate = Color(1, 1, 1, 1)
	pants_sprite.modulate = Color(1, 1, 1, 1)

	if multiplayer.has_multiplayer_peer():
		sync_drowning_alpha_rpc.rpc(0.0)

	$CollisionShape2D.disabled = false
	is_dead = false


# Flashes the character red briefly.
func _flash_damage():
	if damage_flash_tween:
		damage_flash_tween.kill()

	damage_flash_tween = create_tween()

	anim.modulate = Color(1, 0.15, 0.15, 1)
	hair_sprite.modulate = Color(1, 0.15, 0.15, 1)
	shirt_sprite.modulate = Color(1, 0.15, 0.15, 1)
	pants_sprite.modulate = Color(1, 0.15, 0.15, 1)

	damage_flash_tween.tween_interval(0.08)
	damage_flash_tween.tween_callback(func():
		anim.modulate = Color(1, 1, 1, 1)
		hair_sprite.modulate = Color(1, 1, 1, 1)
		shirt_sprite.modulate = Color(1, 1, 1, 1)
		pants_sprite.modulate = Color(1, 1, 1, 1)
	)

# Sent often to tell other players where this player is.
@rpc("any_peer", "call_remote", "unreliable_ordered")


# Updates another player's position, velocity and held item on this game.
func sync_position_rpc(px: float, py: float, vx: float, vy: float, held: String):
	if is_multiplayer_authority():
		return
	global_position = Vector2(px, py)
	synced_velocity = Vector2(vx, vy)
	synced_held_item = held

# ID of the light created when holding a torch.
var _torch_light_id: int = -1


# Adds or removes a light when the player holds a torch in the offhand.
func _update_torch_light():
	var lighting_system = get_tree().root.get_node_or_null("Scene/LightingSystem")
	if not lighting_system:
		return
	var offhand_torch := false
	if is_multiplayer_authority() or not multiplayer.has_multiplayer_peer():
		offhand_torch = Inventory.offhand_slot.get("item", "") == "Torch"
	var holding_torch = synced_held_item == "Torch" or offhand_torch
	if holding_torch and _torch_light_id == -1:
		_torch_light_id = lighting_system.add_light_source(self, 22, 1.35, true)
	elif not holding_torch and _torch_light_id != -1:
		lighting_system.remove_light_source(_torch_light_id)
		_torch_light_id = -1
