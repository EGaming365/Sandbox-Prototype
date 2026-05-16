extends StaticBody2D

var item_name: String = ""
var item_texture: Texture2D = null
var block_id: int = -1
var hits: int = 0
var max_hits: int = 1
var current_rotation: float = 0.0

var plank_h = preload("res://Assets/Wood_Plank.png")
var plank_v = preload("res://Assets/Wood_Plank_Rotated.png")

func _get_texture_for_item(i_name: String) -> Texture2D:
	match i_name:
		"Wood Plank":
			return plank_h
		"Crafting_Bench":
			var img = Image.create(32, 32, false, Image.FORMAT_RGB8)
			img.fill(Color.RED)
			return ImageTexture.create_from_image(img)
		_:
			return null

func setup(i_name: String, texture: Texture2D, b_id: int, rot: float = 0.0):
	item_name = i_name
	item_texture = texture if texture != null else _get_texture_for_item(i_name)
	block_id = b_id
	max_hits = BuildingManager.get_max_hits(item_name)
	current_rotation = rot

func _ready():
	add_to_group("placed_blocks")
	z_index = 2
	if item_name == "Crafting_Bench":
		add_to_group("crafting_benches")
	if item_texture == null and item_name != "":
		item_texture = _get_texture_for_item(item_name)
	if item_texture:
		$Sprite2D.texture = item_texture
		$Sprite2D.scale = Vector2(2, 2)
	if item_name != "":
		max_hits = BuildingManager.get_max_hits(item_name)
	$CollisionShape2D.shape = $CollisionShape2D.shape.duplicate()
	call_deferred("_update_collision_for_rotation")

func _update_collision_for_rotation():
	var shape = $CollisionShape2D.shape as RectangleShape2D
	if not shape:
		return
	var rot = fmod(abs(current_rotation), 360.0)
	if item_name == "Wood Plank":
		match int(rot):
			0:
				$Sprite2D.texture = plank_v
				$Sprite2D.rotation_degrees = 90.0
				$Sprite2D.flip_h = false
				$Sprite2D.flip_v = true
				$Sprite2D.scale = Vector2(2, -2)
				$Sprite2D.position = Vector2(0, 0)
				shape.size = Vector2(64, 14)
			90:
				$Sprite2D.texture = plank_v
				$Sprite2D.rotation_degrees = 0.0
				$Sprite2D.flip_h = false
				$Sprite2D.flip_v = false
				$Sprite2D.scale = Vector2(2, 2)
				$Sprite2D.position = Vector2(0, 0)
				shape.size = Vector2(14, 64)
			180:
				$Sprite2D.texture = plank_v
				$Sprite2D.rotation_degrees = 90.0
				$Sprite2D.flip_h = false
				$Sprite2D.flip_v = false
				$Sprite2D.scale = Vector2(2, 2)
				$Sprite2D.position = Vector2(0, -46)
				shape.size = Vector2(64, 14)
			270:
				$Sprite2D.texture = plank_v
				$Sprite2D.rotation_degrees = 0.0
				$Sprite2D.flip_h = true
				$Sprite2D.flip_v = true
				$Sprite2D.scale = Vector2(2, 2)
				$Sprite2D.position = Vector2(-2, 0)
				shape.size = Vector2(14, 64)
	else:
		$Sprite2D.rotation_degrees = 0.0
		$Sprite2D.flip_h = false
		$Sprite2D.position = Vector2(0, 0)
		shape.size = Vector2(64, 64)
		$CollisionShape2D.position = Vector2(0, 0)

func _process(_delta):
	pass

func get_global_rect() -> Rect2:
	return Rect2(global_position - Vector2(32, 32), Vector2(64, 64))

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var inv = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
		var chat = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
		if (inv and inv.visible) or (chat and chat.is_open):
			return
		var mouse = get_global_mouse_position()
		if not get_global_rect().has_point(mouse):
			return
		var player = _get_local_player()
		if not player:
			return
		if player.global_position.distance_to(global_position) > 300.0:
			return
		$Sprite2D.modulate = Color(1, 0.5, 0.5, 1)
		await get_tree().create_timer(0.1).timeout
		if not is_instance_valid(self):
			return
		$Sprite2D.modulate = Color(1, 1, 1, 1)
		var scene_node = get_tree().root.get_node("Scene")
		if multiplayer.has_multiplayer_peer():
			if multiplayer.is_server():
				scene_node.process_block_hit(block_id)
			else:
				scene_node.register_block_hit.rpc_id(1, block_id)
		else:
			scene_node.process_block_hit(block_id)

func _break_block():
	var scene_node = get_tree().root.get_node("Scene")
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			Inventory.add_item(item_name, item_texture)
			scene_node.sync_remove_placed_block.rpc(block_id)
		else:
			scene_node.register_block_hit.rpc_id(1, block_id)
	else:
		Inventory.add_item(item_name, item_texture)
		scene_node.remove_placed_block(block_id)

func _get_local_player():
	for child in get_tree().root.get_node("Scene").get_children():
		if child is CharacterBody2D:
			if multiplayer.has_multiplayer_peer():
				if child.is_multiplayer_authority():
					return child
			else:
				return child
	return null
