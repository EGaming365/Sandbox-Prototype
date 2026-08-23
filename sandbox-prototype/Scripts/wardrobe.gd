extends StaticBody2D

var block_id: int = -1
var item_id: int = -1
var is_placed: bool = false
var is_open: bool = false
var wardrobe_texture: Texture2D = preload("res://Assets/Wardrobe.png")
var wardrobe_open_texture: Texture2D = preload("res://Assets/Wardrobe_Open.png")

func _ready():
	visible = false
	add_to_group("placed_blocks")
	add_to_group("trees")
	$Sprite2D.texture = wardrobe_texture
	var col_shape = RectangleShape2D.new()
	col_shape.size = Vector2(30, 8)
	$CollisionShape2D.shape = col_shape
	$CollisionShape2D.position = Vector2(0, 24)
	var area_shape = RectangleShape2D.new()
	area_shape.size = Vector2(72, 72)
	$Area2D/CollisionShape2D.shape = area_shape
	$Area2D/CollisionShape2D.position = Vector2.ZERO
	call_deferred("_setup_area")
	z_index = 2
	await get_tree().process_frame
	visible = true

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

func setup_placed(b_id: int):
	block_id = b_id
	is_placed = true
	$Sprite2D.scale = Vector2(3.2, 3.2)
	$Sprite2D.offset = Vector2.ZERO
	call_deferred("_setup_area")

func setup_floor(i_id: int):
	item_id = i_id
	is_placed = false
	$Sprite2D.scale = Vector2(1.5, 1.5)

func _input(event):
	if not is_placed:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var inv = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
		var chat = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
		if (inv and inv.visible) or (chat and chat.is_open):
			return
		if not _get_rect().has_point(get_global_mouse_position()):
			return
		var player = _get_local_player()
		if not player:
			return
		if player.global_position.distance_to(global_position) > 300.0:
			return
		_toggle_wardrobe_ui()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var inv = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
		var chat = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
		if (inv and inv.visible) or (chat and chat.is_open):
			return
		if not _get_rect().has_point(get_global_mouse_position()):
			return
		var player = _get_local_player()
		if not player:
			return
		if player.global_position.distance_to(global_position) > 300.0:
			return
		_hit_wardrobe()

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

func close_ui():
	is_open = false
	$Sprite2D.texture = wardrobe_texture
	var wardrobe_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/Wardrobe_UI")
	if wardrobe_ui:
		wardrobe_ui.visible = false

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

func _remove_self():
	var scene_node = get_tree().root.get_node_or_null("Scene")
	if scene_node and multiplayer.has_multiplayer_peer():
		remove_wardrobe_rpc.rpc(block_id)
	else:
		var s = get_tree().root.get_node_or_null("Scene")
		if s:
			s.remove_placed_block(block_id)
		else:
			queue_free()

@rpc("authority", "call_local", "reliable")
func remove_wardrobe_rpc(_b_id: int):
	queue_free()

func _on_body_entered(body):
	if is_placed:
		return
	if body is CharacterBody2D:
		if not multiplayer.has_multiplayer_peer() or body.is_multiplayer_authority():
			_pickup()

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

func _get_rect() -> Rect2:
	return Rect2(global_position - Vector2(32, 32), Vector2(64, 64))

func _get_local_player():
	for child in get_tree().root.get_node("Scene").get_children():
		if child is CharacterBody2D and child.is_in_group("players"):
			if multiplayer.has_multiplayer_peer():
				if child.is_multiplayer_authority():
					return child
			else:
				return child
	return null

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
