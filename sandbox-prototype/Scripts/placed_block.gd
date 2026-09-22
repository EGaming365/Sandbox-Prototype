# Placed block.
# A block, torch, bench or wardrobe that a player has put down in the world.
# Players hit it with the left mouse button to break it and the block gives itself back as an item.

extends StaticBody2D

# Name of the item this block was made from.
var item_name: String = ""
# Picture of the block.
var item_texture: Texture2D = null
# ID used to refer to this block across the network.
var block_id: int = -1
# Hits the block has taken so far.
var hits: int = 0
# Hits needed to break the block.
var max_hits: int = 1
# Rotation of the block.
var current_rotation: float = 0.0
# ID of the light this block created, or -1 if it has none.
var _light_id: int = -1

# Picture used for wood plank blocks when none is supplied.
var plank_texture = preload("res://Assets/Wood_Planks.png")


# Returns the built in picture for an item, or null if there is none.
func _get_texture_for_item(new_item_name: String) -> Texture2D:
	match new_item_name:
		"Wood Plank":
			return plank_texture
		"Torch":
			return Inventory.torch_texture
		_:
			return null


# Sets the block's item, picture and ID. The rotation argument is ignored, so rotation stays at zero.
func setup(new_item_name: String, texture: Texture2D, new_block_id: int, rotation_angle: float = 0.0):
	item_name = new_item_name
	item_texture = texture if texture != null else _get_texture_for_item(new_item_name)
	block_id = new_block_id
	max_hits = BuildingManager.get_max_hits(item_name)
	current_rotation = 0.0


# Sets up the sprite, collision shape and, for torches, a light, depending on the item.
func _ready():
	add_to_group("placed_blocks")
	z_index = 2
	if item_name == "Crafting_Bench":
		add_to_group("crafting_benches")
	if item_texture == null and item_name != "":
		item_texture = _get_texture_for_item(item_name)

	# Each item type has its own picture scale, position and collision box.
	match item_name:
		"Crafting_Bench":
			if item_texture:
				$Sprite2D.texture = item_texture
				$Sprite2D.scale = Vector2(2, 2)
				$Sprite2D.centered = true
				$Sprite2D.position = Vector2(0, -24)
			var collision_rectangle = RectangleShape2D.new()
			collision_rectangle.size = Vector2(64, 40)
			$CollisionShape2D.shape = collision_rectangle
			$CollisionShape2D.position = Vector2(0, 12)
		"Wardrobe":
			# Wardrobe is handled by its own scene, this is a fallback
			if item_texture:
				$Sprite2D.texture = item_texture
				$Sprite2D.scale = Vector2(3.2, 3.2)
				$Sprite2D.centered = true
				$Sprite2D.position = Vector2(0, -48)
			var collision_rectangle = RectangleShape2D.new()
			collision_rectangle.size = Vector2(64, 48)
			$CollisionShape2D.shape = collision_rectangle
			$CollisionShape2D.position = Vector2(0, 8)
		"Torch":
			if item_texture:
				$Sprite2D.texture = item_texture
				$Sprite2D.modulate = Color(1.0, 0.72, 0.22, 1.0)
				$Sprite2D.scale = Vector2(0.42, 0.42)
				$Sprite2D.centered = true
				$Sprite2D.position = Vector2(0, -14)
			var collision_rectangle = RectangleShape2D.new()
			collision_rectangle.size = Vector2(28, 56)
			$CollisionShape2D.shape = collision_rectangle
			$CollisionShape2D.position = Vector2(0, -4)
			# Torches give off light, so register a static light with the lighting system.
			var lighting_system = get_tree().root.get_node_or_null("Scene/LightingSystem")
			if lighting_system and lighting_system.has_method("add_static_light"):
				_light_id = lighting_system.add_static_light(global_position, 22, 1.35, true)
		_:
			if item_texture:
				$Sprite2D.texture = item_texture
				$Sprite2D.scale = Vector2(1, 1)
				$Sprite2D.centered = true
				$Sprite2D.position = Vector2.ZERO
			var collision_rectangle = RectangleShape2D.new()
			collision_rectangle.size = Vector2(64, 64)
			$CollisionShape2D.shape = collision_rectangle
			$CollisionShape2D.position = Vector2.ZERO

	# Look up how many hits the block can take.
	if item_name != "":
		max_hits = BuildingManager.get_max_hits(item_name)


# Nothing needs to happen every frame.
func _process(_delta):
	pass


# Returns a 64 by 64 pixel box around the block, used for mouse hit tests.
func get_global_rect() -> Rect2:
	return Rect2(global_position - Vector2(32, 32), Vector2(64, 64))


# Left clicking the block while close to it damages it.
func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Ignore clicks while the inventory or chat is open.
		var inventory_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
		var chat_box = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
		if (inventory_ui and inventory_ui.visible) or (chat_box and chat_box.is_open):
			return
		var mouse_position = get_global_mouse_position()
		if not get_global_rect().has_point(mouse_position):
			return
		var player = _get_local_player()
		if not player:
			return
		if player.global_position.distance_to(global_position) > 300.0:
			return
		# Flash the block red briefly to show it was hit.
		$Sprite2D.modulate = Color(1, 0.5, 0.5, 1)
		await get_tree().create_timer(0.1).timeout
		if not is_instance_valid(self):
			return
		$Sprite2D.modulate = Color(1, 1, 1, 1)
		# The host works out the damage, so clients send their hit to the host.
		var scene_node = get_tree().root.get_node("Scene")
		if multiplayer.has_multiplayer_peer():
			if multiplayer.is_server():
				scene_node.process_block_hit(block_id)
			else:
				scene_node.register_block_hit.rpc_id(1, block_id)
		else:
			scene_node.process_block_hit(block_id)


# Gives the item back to the player and removes the block from the world.
func _break_block():
	var scene_node = get_tree().root.get_node("Scene")
	_remove_torch_light()
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			Inventory.add_item(item_name, item_texture)
			scene_node.sync_remove_placed_block.rpc(block_id)
		else:
			scene_node.register_block_hit.rpc_id(1, block_id)
	else:
		Inventory.add_item(item_name, item_texture)
		scene_node.remove_placed_block(block_id)


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


# Remove any light when the block leaves the scene.
func _exit_tree():
	_remove_torch_light()


# Removes the light created by a torch so it does not stay behind.
func _remove_torch_light():
	if _light_id == -1:
		return
	var lighting_system = get_tree().root.get_node_or_null("Scene/LightingSystem")
	if lighting_system and lighting_system.has_method("remove_light_source"):
		lighting_system.remove_light_source(_light_id)
	_light_id = -1
