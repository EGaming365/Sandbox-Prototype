# Wardrobe.
# Acts as a floor item that is picked up when walked over, and as a placed block that opens the wardrobe menu with a right click and breaks with a left click.

extends StaticBody2D

# ID used to refer to this block across the network once it is placed.
var block_id: int = -1
# ID used to refer to this item across the network while it lies on the floor.
var item_id: int = -1
# True when placed as a block, false when lying on the floor as a pickup.
var is_placed: bool = false
# True while the wardrobe menu is open.
var is_open: bool = false
# Closed wardrobe picture.
var wardrobe_texture: Texture2D = preload("res://Assets/Wardrobe.png")
# Open wardrobe picture.
var wardrobe_open_texture: Texture2D = preload("res://Assets/Wardrobe_Open.png")


# Sets up the picture and collision shapes, then reveals the wardrobe after one frame.
func _ready():
	visible = false
	# Join the block and tree groups, which other systems use to find blocking objects.
	add_to_group("placed_blocks")
	add_to_group("trees")
	$Sprite2D.texture = wardrobe_texture
	var collision_rectangle = RectangleShape2D.new()
	collision_rectangle.size = Vector2(30, 8)
	$CollisionShape2D.shape = collision_rectangle
	$CollisionShape2D.position = Vector2(0, 24)
	var pickup_area_rectangle = RectangleShape2D.new()
	pickup_area_rectangle.size = Vector2(72, 72)
	$Area2D/CollisionShape2D.shape = pickup_area_rectangle
	$Area2D/CollisionShape2D.position = Vector2.ZERO
	# Configure the collision after the scene has finished loading.
	call_deferred("_setup_area")
	z_index = 2
	await get_tree().process_frame
	visible = true


# Placed wardrobes are solid and cannot be walked over. Floor wardrobes are not solid and are picked up when a player touches them.
func _setup_area():
	if is_placed:
		$CollisionShape2D.disabled = false
		$Area2D.monitoring = false
		$Area2D/CollisionShape2D.disabled = true
	else:
		$CollisionShape2D.disabled = true
		$Area2D.monitoring = true
		$Area2D/CollisionShape2D.disabled = false
		$Area2D.body_entered.connect(_on_body_entered)


# Turns this wardrobe into a placed block with the given ID.
func setup_placed(new_block_id: int):
	block_id = new_block_id
	is_placed = true
	$Sprite2D.scale = Vector2(2, 2)
	$Sprite2D.offset = Vector2.ZERO
	call_deferred("_setup_area")


# Turns this wardrobe into a floor pickup with the given ID.
func setup_floor(new_item_id: int):
	item_id = new_item_id
	is_placed = false
	$Sprite2D.scale = Vector2(1.5, 1.5)


# Right click opens or closes the menu and left click breaks the wardrobe, when the player is close enough.
func _input(event):
	if not is_placed:
		return
	if event.is_action_pressed("right_click"):
		# Ignore clicks while the inventory or chat is open.
		var inventory_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
		var chat_box = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
		if (inventory_ui and inventory_ui.visible) or (chat_box and chat_box.is_open):
			return
		if not _get_rect().has_point(get_global_mouse_position()):
			return
		var player = _get_local_player()
		if not player:
			return
		if player.global_position.distance_to(global_position) > 300.0:
			return
		_toggle_wardrobe_ui()
	elif event.is_action_pressed("click"):
		var inventory_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
		var chat_box = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
		if (inventory_ui and inventory_ui.visible) or (chat_box and chat_box.is_open):
			return
		if not _get_rect().has_point(get_global_mouse_position()):
			return
		var player = _get_local_player()
		if not player:
			return
		if player.global_position.distance_to(global_position) > 300.0:
			return
		_hit_wardrobe()


# Opens or closes the wardrobe menu and swaps between the open and closed picture.
func _toggle_wardrobe_ui():
	var wardrobe_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/Wardrobe_UI")
	if not wardrobe_ui:
		return
	is_open = not is_open
	$Sprite2D.texture = wardrobe_open_texture if is_open else wardrobe_texture
	if is_open:
		wardrobe_ui.open()
	else:
		wardrobe_ui.close()


# Closes the menu and shows the closed picture.
func close_ui():
	is_open = false
	$Sprite2D.texture = wardrobe_texture
	var wardrobe_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/Wardrobe_UI")
	if wardrobe_ui:
		wardrobe_ui.visible = false


# Flashes red, then breaks the wardrobe and drops it as an item. Clients ask the host to do this.
func _hit_wardrobe():
	$Sprite2D.modulate = Color(1, 0.5, 0.5, 1)
	await get_tree().create_timer(0.1).timeout
	if not is_instance_valid(self):
		return
	$Sprite2D.modulate = Color(1, 1, 1, 1)
	close_ui()
	var scene_node = get_tree().root.get_node("Scene")
	var drop_pos = global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			scene_node.host_spawn_floor_item(drop_pos, "Wardrobe", 1)
			_remove_self()
		else:
			scene_node.request_break_wardrobe.rpc_id(1, block_id, drop_pos.x, drop_pos.y)
	else:
		scene_node.host_spawn_floor_item(drop_pos, "Wardrobe", 1)
		_remove_self()


# Removes the wardrobe on every player's game, or just this one when playing alone.
func _remove_self():
	var scene_node = get_tree().root.get_node_or_null("Scene")
	if scene_node and multiplayer.has_multiplayer_peer():
		remove_wardrobe_rpc.rpc(block_id)
	else:
		var scene_fallback = get_tree().root.get_node_or_null("Scene")
		if scene_fallback:
			scene_fallback.remove_placed_block(block_id)
		else:
			queue_free()

# Sent by the host so the wardrobe is removed on every player's game.
@rpc("authority", "call_local", "reliable")


func remove_wardrobe_rpc(_removed_block_id: int):
	queue_free()


# A floor wardrobe is picked up when the local player walks into it.
func _on_body_entered(body):
	if is_placed:
		return
	if body is CharacterBody2D:
		if not multiplayer.has_multiplayer_peer() or body.is_multiplayer_authority():
			_pickup()


# Adds the wardrobe to the inventory and removes the floor item.
func _pickup():
	Inventory.add_item("Wardrobe", wardrobe_texture)
	var scene_node = get_tree().root.get_node_or_null("Scene")
	if scene_node:
		if multiplayer.has_multiplayer_peer():
			if multiplayer.is_server():
				scene_node.remove_floor_item(item_id)
			else:
				scene_node.request_remove_floor_item.rpc_id(1, item_id)
		else:
			scene_node.remove_floor_item(item_id)


# Returns a 64 by 64 pixel box around the wardrobe, used for mouse hit tests.
func _get_rect() -> Rect2:
	return Rect2(global_position - Vector2(32, 32), Vector2(64, 64))


# Returns the player controlled by this game instance, or null.
func _get_local_player():
	for child in get_tree().root.get_node("Scene").get_children():
		if child is CharacterBody2D and child.is_in_group("players"):
			if multiplayer.has_multiplayer_peer():
				if child.is_multiplayer_authority():
					return child
			else:
				return child
	return null


# Returns true when the item has nowhere to go in the inventory. This function is not currently called.
func _is_inventory_full(item_name: String) -> bool:
	if Inventory.non_stackable_items.has(item_name):
		for slot in Inventory.slots:
			if slot["item"] == "":
				return false
		for slot in Inventory.inv_slots:
			if slot["item"] == "":
				return false
		return true
	for slot in Inventory.slots:
		if slot["item"] == "" or (slot["item"] == item_name and slot["count"] < 99):
			return false
	for slot in Inventory.inv_slots:
		if slot["item"] == "" or (slot["item"] == item_name and slot["count"] < 99):
			return false
	return true
