extends CharacterBody2D

@export var speed = 450
@export var synced_velocity : Vector2 = Vector2.ZERO
@export var synced_held_item: String = ""
@export var synced_health: int = 10
@onready var anim = $AnimatedSprite2D
var chop_cooldown_timer: float = 0.0
var chop_cooldown_max: float = 1.5
var hand_sprite: Sprite2D = null
var max_health: int = 10
var is_dead: bool = false
var attack_cooldown: float = 0.0
const ATTACK_COOLDOWN_MAX: float = 0.8
const ATTACK_RANGE: float = 80.0
const SWORD_DAMAGE: int = 2
const FEET_OFFSET: float = 1.0
var camera: Camera2D = null

func _enter_tree():
	if multiplayer.has_multiplayer_peer():
		set_multiplayer_authority(name.to_int())
	else:
		set_multiplayer_authority(1)

func _ready():
	z_index = 2
	add_to_group("players")
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

func _setup_hand():
	hand_sprite = Sprite2D.new()
	hand_sprite.position = Vector2(-10, -16)
	hand_sprite.z_as_relative = true  # inherits player's z_index
	hand_sprite.z_index = 0           # 0 relative to parent = same as player
	hand_sprite.visible = false
	hand_sprite.modulate = Color(1, 1, 1, 0)
	add_child(hand_sprite)

func _setup_camera():
	var is_local = not multiplayer.has_multiplayer_peer() or is_multiplayer_authority()
	if not is_local:
		return
	camera = get_tree().root.get_node_or_null("Camera2D")
	if not camera:
		camera = Camera2D.new()
		camera.name = "Camera2D"
		get_tree().root.add_child(camera)  # add to ROOT not Scene
	camera.enabled = true
	camera.make_current()
	camera.global_position = global_position

func _process(delta):
	if camera and (not multiplayer.has_multiplayer_peer() or is_multiplayer_authority()):
		camera.global_position = global_position
	if _is_inventory_open():
		return

func _physics_process(delta):
	if _is_inventory_open():
		velocity = Vector2.ZERO
		move_and_slide()
		if is_multiplayer_authority() or not multiplayer.has_multiplayer_peer():
			anim.play("idle")
		return

	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		velocity = synced_velocity
		move_and_slide()
		if synced_velocity.length() > 0:
			anim.play("walk_down")
		else:
			anim.play("idle")
		_update_hand_sprite()
		return

	if is_multiplayer_authority() or not multiplayer.has_multiplayer_peer():
		if chop_cooldown_timer > 0:
			chop_cooldown_timer = max(chop_cooldown_timer - delta, 0.0)
			var pct = chop_cooldown_timer / chop_cooldown_max if chop_cooldown_max > 0 else 0.0
			var cursor = get_tree().root.get_node_or_null("Scene/CanvasLayer/Cursor")
			if cursor:
				cursor.show_cooldown(pct)
		if attack_cooldown > 0:
			attack_cooldown = max(attack_cooldown - delta, 0.0)
		var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
		if hotbar:
			var slot = Inventory.slots[hotbar.current_slot - 1]
			synced_held_item = slot["item"]
		var hearts_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hearts")
		if hearts_ui:
			hearts_ui.update_hearts(synced_health)

	var direction = Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		direction.x -= 1
	if Input.is_action_pressed("move_right"):
		direction.x += 1
	if Input.is_action_pressed("move_up"):
		direction.y -= 1
	if Input.is_action_pressed("move_down"):
		direction.y += 1
	if direction.length() > 0:
		anim.play("walk_down")
	else:
		anim.play("idle")
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
	if _is_inventory_open():
		return
	if not (is_multiplayer_authority() or not multiplayer.has_multiplayer_peer()):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if synced_held_item == "Sword" and attack_cooldown <= 0.0:
			_try_attack()

func _try_attack():
	attack_cooldown = ATTACK_COOLDOWN_MAX
	var scene_node = get_tree().root.get_node("Scene")
	for child in scene_node.get_children():
		if child is CharacterBody2D and child != self:
			var dist = global_position.distance_to(child.global_position)
			if dist <= ATTACK_RANGE:
				var target_id = child.name.to_int()
				if multiplayer.has_multiplayer_peer():
					scene_node.request_deal_damage.rpc_id(1, target_id, SWORD_DAMAGE)
				else:
					child.take_damage(SWORD_DAMAGE)
				_consume_sword_durability()
				break

func _consume_sword_durability():
	var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	if not hotbar:
		return
	var slot_index = hotbar.current_slot - 1
	var slot = Inventory.slots[slot_index]
	if slot["item"] == "Sword":
		slot["count"] -= 1
		if slot["count"] <= 0:
			Inventory.remove_item(slot_index, false)
		else:
			Inventory.inventory_changed.emit()

func take_damage(amount: int):
	if not is_multiplayer_authority() and multiplayer.has_multiplayer_peer():
		return
	if is_dead:
		return
	synced_health = max(synced_health - amount, 0)
	if synced_health <= 0:
		die()

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

	for i in Inventory.slots.size():
		if Inventory.slots[i]["item"] != "":
			Inventory.remove_item(i, false)
	for i in Inventory.inv_slots.size():
		if Inventory.inv_slots[i]["item"] != "":
			Inventory.remove_item(i, true)

	global_position = Vector2(0, 0)
	synced_health = max_health
	is_dead = false

func _update_hand_sprite():
	if not hand_sprite:
		return
	if synced_held_item == "":
		hand_sprite.texture = null
		hand_sprite.visible = false
		hand_sprite.modulate = Color(1, 1, 1, 0)
		return
	for slot in Inventory.slots:
		if slot["item"] == synced_held_item and slot["texture"] != null:
			_apply_hand_texture(slot["texture"])
			return
	for slot in Inventory.inv_slots:
		if slot["item"] == synced_held_item and slot["texture"] != null:
			_apply_hand_texture(slot["texture"])
			return
	hand_sprite.texture = null
	hand_sprite.visible = false
	hand_sprite.modulate = Color(1, 1, 1, 0)

func _apply_hand_texture(tex: Texture2D):
	hand_sprite.texture = tex
	hand_sprite.visible = true
	hand_sprite.modulate = Color(1, 1, 1, 1)
	var tex_size = tex.get_size()
	if tex_size.x > 0 and tex_size.y > 0:
		hand_sprite.scale = Vector2(12.0 / tex_size.x, 12.0 / tex_size.y)

func start_chop_cooldown(duration: float):
	chop_cooldown_max = duration
	chop_cooldown_timer = duration

func _is_inventory_open() -> bool:
	var inv = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
	var chat = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
	var chat_open = chat != null and chat.is_open
	return (inv != null and inv.visible) or chat_open

func _is_chat_open() -> bool:
	var chat = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
	return chat != null and chat.is_open
