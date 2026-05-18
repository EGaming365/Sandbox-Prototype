extends CharacterBody2D

@export var speed = 450
@export var synced_velocity : Vector2 = Vector2.ZERO
@export var synced_held_item: String = ""
@export var synced_health: int = 10
@onready var anim = $AnimatedSprite2D
@onready var hair_sprite: AnimatedSprite2D = $Hair_Sprite
@onready var shirt_sprite: AnimatedSprite2D = $Shirt_Sprite
@onready var pants_sprite: AnimatedSprite2D = $Pants_Sprite

@export var synced_hair: bool = true
@export var synced_shirt: bool = true
@export var synced_pants: bool = true
@export var respawn_delay: float = 1.2
@export var death_shrink_time: float = 0.65

var damage_flash_tween: Tween = null
var death_tween: Tween = null
var base_anim_scale: Vector2
var base_hair_scale: Vector2
var base_shirt_scale: Vector2
var base_pants_scale: Vector2
var chop_cooldown_timer: float = 0.0
var chop_cooldown_max: float = 1.5
var hand_sprite: Sprite2D = null
var max_health: int = 10
var is_dead: bool = false
var attack_cooldown: float = 0.0
const ATTACK_COOLDOWN_MAX: float = 1.5
const ATTACK_RANGE: float = 120.0
const SWORD_DAMAGE: int = 2
const STONE_SWORD_DAMAGE: int = 4

# Parry / block constants
# The parry window opens when the enemy enters the final PARRY_WINDOW seconds of
# its charge glow (right-click starts a timer; if the dash lands inside that window
# it counts as a perfect parry).
const PARRY_WINDOW: float = 0.16  # tighter parry window
const PARRY_DURABILITY_COST: int = 1
const BLOCK_DURABILITY_COST: int = 4
const PARRY_COUNTER_DAMAGE: int = 9999  # one-shots any night enemy

# After releasing block the player cannot re-block for this duration.
# This stops spam-parrying by repeatedly tapping right-click.
const BLOCK_COOLDOWN_MAX: float = 0.6

const FEET_OFFSET: float = 1.0
var camera: Camera2D = null
var is_blocking: bool = false
var parry_timer: float = 0.0
var block_cooldown: float = 0.0   # counts DOWN; player can't block while > 0
var _parry_just_landed: bool = false  # prevents _stop_blocking re-applying cooldown after a parry

var drowning_timer: float = 0.0
var drowning_dead: bool = false
const DROWN_TIME: float = 4.0

func _enter_tree():
	if multiplayer.has_multiplayer_peer():
		set_multiplayer_authority(name.to_int())
	else:
		set_multiplayer_authority(1)

func _ready():
	z_index = 2
	add_to_group("players")
	hair_sprite.visible = true
	shirt_sprite.visible = true
	pants_sprite.visible = true
	base_anim_scale = anim.scale
	base_hair_scale = hair_sprite.scale
	base_shirt_scale = shirt_sprite.scale
	base_pants_scale = pants_sprite.scale
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

func _play_anim(anim_name: String):
	anim.play(anim_name)
	if hair_sprite.visible:
		hair_sprite.play(anim_name)
	if shirt_sprite.visible:
		shirt_sprite.play(anim_name)
	if pants_sprite.visible:
		pants_sprite.play(anim_name)

var _hand_scales: Dictionary = {}

func _setup_hand():
	hand_sprite = Sprite2D.new()
	hand_sprite.position = Vector2(-10, -16)
	hand_sprite.z_as_relative = true
	hand_sprite.z_index = 0
	hand_sprite.scale = Vector2(0.017, 0.017)
	hand_sprite.visible = false
	hand_sprite.modulate = Color(1, 1, 1, 0)
	add_child(hand_sprite)
	for item_name in Inventory.TEXTURE_MAP:
		var tex = Inventory.TEXTURE_MAP[item_name]
		if tex:
			var s = tex.get_size()
			if s.x > 0 and s.y > 0:
				_hand_scales[item_name] = Vector2(12.0 / s.x, 12.0 / s.y)

func _apply_hand_texture(tex: Texture2D):
	var scale = _hand_scales.get(synced_held_item, Vector2(0.017, 0.017))
	hand_sprite.scale = scale
	hand_sprite.texture = tex
	hand_sprite.visible = false
	hand_sprite.modulate = Color(1, 1, 1, 0)
	RenderingServer.force_draw()
	hand_sprite.visible = true
	hand_sprite.modulate = Color(1, 1, 1, 1)

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

func _process(delta):
	if _is_inventory_open():
		return

func _physics_process(delta):
	if camera and (not multiplayer.has_multiplayer_peer() or is_multiplayer_authority()):
		camera.global_position = global_position
	if is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	_update_drowning(delta)
	if _is_inventory_open():
		velocity = Vector2.ZERO
		move_and_slide()
		if is_multiplayer_authority() or not multiplayer.has_multiplayer_peer():
			_play_anim("idle")
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
			# Turn off highlight as soon as parry window closes
			if parry_timer <= 0.0:
				_set_parry_highlight(false)

		# Tick down the block cooldown (spam prevention)
		if block_cooldown > 0.0:
			block_cooldown = max(block_cooldown - delta, 0.0)

		# Auto-release block if mouse is no longer held
		if is_blocking and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_stop_blocking()

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
	synced_velocity = velocity
	move_and_slide()
	_update_hand_sprite()

	if multiplayer.has_multiplayer_peer():
		sync_position_rpc.rpc(global_position.x, global_position.y, velocity.x, velocity.y, synced_held_item)

@rpc("authority", "call_remote", "unreliable_ordered")
func sync_position_rpc(px: float, py: float, vx: float, vy: float, held: String):
	global_position = Vector2(px, py)
	synced_velocity = Vector2(vx, vy)
	synced_held_item = held

func _input(event):
	if is_dead:
		return
	if _is_inventory_open():
		return
	if not (is_multiplayer_authority() or not multiplayer.has_multiplayer_peer()):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _is_holding_sword() and chop_cooldown_timer <= 0.0 and attack_cooldown <= 0.0:
			_try_attack()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and _is_holding_sword():
			# Only allow blocking if the cooldown has expired
			if block_cooldown <= 0.0:
				_start_blocking()
		elif not event.pressed:
			_stop_blocking()

func _try_attack():
	# Cooldown and cursor are only applied if something is actually hit
	var scene_node = get_tree().root.get_node("Scene")
	var mouse_world_pos = get_global_mouse_position()

	# ── Night enemies: group search, nearest within range ───────────────────
	var best_enemy: Node = null
	var best_dist: float = ATTACK_RANGE + 1.0
	for enemy in get_tree().get_nodes_in_group("night_enemies"):
		if not is_instance_valid(enemy):
			continue
		var enemy_centre: Vector2 = (enemy as Node2D).global_position + Vector2(0, -30)
		var dist_to_player: float = global_position.distance_to(enemy_centre)
		if dist_to_player < best_dist:
			best_dist = dist_to_player
			best_enemy = enemy
	if best_enemy != null:
		_apply_attack_cooldown()
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			scene_node.request_damage_night_enemy.rpc_id(1, best_enemy.get("enemy_id"), _get_sword_damage())
		else:
			if best_enemy.has_method("take_damage"):
				best_enemy.take_damage(_get_sword_damage())
		_consume_sword_durability()
		return

	# ── Chickens and players ────────────────────────────────────────────────
	for child in scene_node.get_children():
		if child == self:
			continue
		if not child is Node2D:
			continue
		var dist_to_player: float = global_position.distance_to(child.global_position)
		var dist_to_mouse: float  = mouse_world_pos.distance_to(child.global_position)
		if dist_to_player > ATTACK_RANGE:
			continue
		if dist_to_mouse > 60.0:
			continue
		if child.is_in_group("players"):
			_apply_attack_cooldown()
			if multiplayer.has_multiplayer_peer():
				var target_id = child.name.to_int()
				scene_node.request_deal_damage.rpc_id(1, target_id, _get_sword_damage())
			else:
				child.take_damage(_get_sword_damage())
			_consume_sword_durability()
			return
		if child.is_in_group("chickens"):
			_apply_attack_cooldown()
			_kill_chicken(child)
			_consume_sword_durability()
			return

func _apply_attack_cooldown() -> void:
	attack_cooldown = ATTACK_COOLDOWN_MAX
	var cursor = get_tree().root.get_node_or_null("Scene/CanvasLayer/Cursor")
	if cursor:
		cursor.show_cooldown(1.0)

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

func _kill_chicken(chicken: Node2D) -> void:
	# Spawn a burst of grey particles at the chicken's position, then remove it
	_spawn_feather_burst(chicken.global_position)
	if chicken.has_method("take_damage"):
		# Pass massive damage so any health value dies
		chicken.take_damage(9999)
	else:
		chicken.queue_free()

func _spawn_feather_burst(pos: Vector2) -> void:
	# CPUParticles2D — works without a GPU, no extra scene needed
	var particles := CPUParticles2D.new()
	get_tree().root.get_node("Scene").add_child(particles)
	particles.global_position = pos
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
	# Grey/white puff colour
	particles.color = Color(0.75, 0.75, 0.75, 1.0)
	particles.color_ramp = null
	# Auto-free after burst finishes
	var timer := get_tree().create_timer(particles.lifetime + 0.1)
	timer.timeout.connect(func(): if is_instance_valid(particles): particles.queue_free())

func _is_holding_sword() -> bool:
	return synced_held_item == "Sword" or synced_held_item == "Stone Sword"

func _get_sword_damage() -> int:
	if synced_held_item == "Stone Sword":
		return STONE_SWORD_DAMAGE
	return SWORD_DAMAGE

func _parry_success_flash() -> void:
	# Massive white screen flash to make parry feel impactful
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
	# Also blast the player sprite bright white then back
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

func _start_blocking() -> void:
	is_blocking = true
	parry_timer = PARRY_WINDOW
	if hand_sprite:
		hand_sprite.rotation_degrees = -35.0
	# Highlight immediately — parry window is open right now
	_set_parry_highlight(true)

func _set_parry_highlight(on: bool) -> void:
	var c := Color(1.8, 1.8, 1.8, 1.0) if on else Color(1, 1, 1, 1)
	anim.modulate = c
	hair_sprite.modulate = c
	shirt_sprite.modulate = c
	pants_sprite.modulate = c

func _stop_blocking() -> void:
	if is_blocking and not _parry_just_landed:
		# Only apply cooldown if this wasn't a successful parry
		block_cooldown = BLOCK_COOLDOWN_MAX
	_parry_just_landed = false
	is_blocking = false
	parry_timer = 0.0
	if hand_sprite:
		hand_sprite.rotation_degrees = 0.0
	# Remove parry highlight
	_set_parry_highlight(false)

func defend_enemy_attack(amount: int, enemy: Node = null) -> void:
	if is_dead:
		return
	if is_blocking and _is_holding_sword():
		if parry_timer > 0.0:
			# Perfect parry — player right-clicked while glow was near full yellow
			_consume_sword_durability(PARRY_DURABILITY_COST)
			parry_timer = 0.0
			block_cooldown = 0.0
			_parry_just_landed = true  # stop _stop_blocking from re-applying cooldown
			_parry_success_flash()
			if enemy and enemy.has_method("take_damage"):
				if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
					# Client — send request to host
					var scene_node = get_tree().root.get_node_or_null("Scene")
					if scene_node and scene_node.has_method("request_damage_night_enemy"):
						scene_node.request_damage_night_enemy.rpc_id(1, enemy.get("enemy_id"), PARRY_COUNTER_DAMAGE)
				else:
					# Singleplayer or we ARE the host — never RPC to ourselves
					enemy.take_damage(PARRY_COUNTER_DAMAGE)
			return
		# Late block — absorbed but costs more durability, no counter
		if _consume_sword_durability(BLOCK_DURABILITY_COST):
			return
	take_damage(amount)

func take_damage(amount: int):
	if not is_multiplayer_authority() and multiplayer.has_multiplayer_peer():
		return
	if is_dead:
		return
	synced_health = max(synced_health - amount, 0)
	if synced_health <= 0:
		die()
	else:
		_flash_damage()

func die():
	is_dead = true
	var scene_node = get_tree().root.get_node("Scene")
	var drops: Array = []
	for i in Inventory.slots.size():
		var slot = Inventory.slots[i]
		if slot["item"] != "":
			var durability = slot.get("durability", slot["count"] if slot["item"] in ["Axe", "Stone Axe", "Pickaxe", "Stone Pickaxe", "Sword", "Stone Sword"] else 60)
			drops.append({"item": slot["item"], "count": slot["count"], "durability": durability, "hotbar": true, "index": i})
	for i in Inventory.inv_slots.size():
		var slot = Inventory.inv_slots[i]
		if slot["item"] != "":
			var durability = slot.get("durability", slot["count"] if slot["item"] in ["Axe", "Stone Axe", "Pickaxe", "Stone Pickaxe", "Sword", "Stone Sword"] else 60)
			drops.append({"item": slot["item"], "count": slot["count"], "durability": durability, "hotbar": false, "index": i})

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
					scene_node.request_spawn_floor_item.rpc_id(1, drop_pos.x, drop_pos.y, drop["item"], drop["durability"])
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
					scene_node.request_spawn_floor_items_batch.rpc_id(1, positions_x, positions_y, drop["item"], 1)
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

var _last_hand_item: String = ""

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
	var tex = Inventory.get_texture(synced_held_item)
	if tex == null:
		for slot in Inventory.slots:
			if slot["item"] == synced_held_item and slot["texture"] != null:
				tex = slot["texture"]
				break
	if tex == null:
		for slot in Inventory.inv_slots:
			if slot["item"] == synced_held_item and slot["texture"] != null:
				tex = slot["texture"]
				break
	if tex == null:
		return
	var tex_size = tex.get_size()
	if tex_size.x <= 0 or tex_size.y <= 0:
		return
	_last_hand_item = synced_held_item
	_apply_hand_texture(tex)

func start_chop_cooldown(duration: float):
	chop_cooldown_max = duration
	chop_cooldown_timer = duration

func _is_inventory_open() -> bool:
	var inv = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
	var chat = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
	var wardrobe = get_tree().root.get_node_or_null("Scene/CanvasLayer/Wardrobe_UI")
	var chat_open = chat != null and chat.is_open
	return (inv != null and inv.visible) or chat_open or (wardrobe != null and wardrobe.visible)

func _is_chat_open() -> bool:
	var chat = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
	return chat != null and chat.is_open

@rpc("any_peer", "call_local", "reliable")
func sync_cosmetics_rpc(hair: bool, shirt: bool, pants: bool):
	synced_hair = hair
	synced_shirt = shirt
	synced_pants = pants
	hair_sprite.visible = hair
	shirt_sprite.visible = shirt
	pants_sprite.visible = pants

func apply_cosmetics(hair: bool, shirt: bool, pants: bool):
	if multiplayer.has_multiplayer_peer():
		sync_cosmetics_rpc.rpc(hair, shirt, pants)
	else:
		sync_cosmetics_rpc(hair, shirt, pants)

func _update_drowning(delta: float):
	if is_dead:
		return
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return

	var world_gen = get_tree().root.get_node_or_null("Scene/WorldGen")
	var in_water = world_gen != null and world_gen.has_method("is_water_at") and world_gen.is_water_at(global_position)

	if in_water:
		drowning_timer += delta
	else:
		drowning_timer = max(drowning_timer - delta * 2.0, 0.0)

	var alpha = lerp(1.0, 0.35, clamp(drowning_timer / DROWN_TIME, 0.0, 1.0))
	_set_drowning_alpha(alpha)
	if multiplayer.has_multiplayer_peer():
		sync_drowning_alpha_rpc.rpc(alpha)

	if drowning_timer >= DROWN_TIME and not drowning_dead:
		drowning_dead = true
		_send_death_message("drowned")
		take_damage(max_health)
	elif drowning_timer <= 0.0:
		drowning_dead = false

func _set_drowning_alpha(alpha: float):
	anim.modulate.a = alpha
	hair_sprite.modulate.a = alpha
	shirt_sprite.modulate.a = alpha
	pants_sprite.modulate.a = alpha
	if hand_sprite:
		hand_sprite.modulate.a = alpha

@rpc("any_peer", "call_remote", "unreliable_ordered")
func sync_drowning_alpha_rpc(alpha: float):
	_set_drowning_alpha(alpha)

func _send_death_message(cause: String):
	var chat = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
	if not chat:
		return
	var player_name = "Player"
	if multiplayer.has_multiplayer_peer():
		player_name = Steam.getFriendPersonaName(Steam.getSteamID())
	var msg = player_name + " " + cause
	if multiplayer.has_multiplayer_peer():
		chat._broadcast_message.rpc(msg)
	else:
		chat._add_message(msg)

func _play_death_respawn_sequence(scene_node):
	if death_tween:
		death_tween.kill()

	velocity = Vector2.ZERO
	$CollisionShape2D.disabled = true
	if hand_sprite:
		hand_sprite.visible = false
		hand_sprite.modulate = Color(1, 1, 1, 0)
		_last_hand_item = ""  # force re-apply on respawn

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

	global_position = scene_node._find_safe_spawn(Vector2(0, 0))
	synced_health = max_health

	var right_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/RightUI")
	if right_ui:
		right_ui.hunger = 100.0
		right_ui.thirst = 100.0
		right_ui.hunger_bar.value = 100.0
		right_ui.thirst_bar.value = 100.0

	anim.scale = base_anim_scale
	hair_sprite.scale = base_hair_scale
	shirt_sprite.scale = base_shirt_scale
	pants_sprite.scale = base_pants_scale

	anim.modulate = Color(1, 1, 1, 1)
	hair_sprite.modulate = Color(1, 1, 1, 1)
	shirt_sprite.modulate = Color(1, 1, 1, 1)
	pants_sprite.modulate = Color(1, 1, 1, 1)

	$CollisionShape2D.disabled = false
	is_dead = false
	# Hand sprite will re-appear automatically via _update_hand_sprite on next frame

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
