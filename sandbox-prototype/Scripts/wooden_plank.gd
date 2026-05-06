extends Node2D
@export var item_id: int = -1
@export var durability: int = 1
var plank_texture: Texture2D
func _ready():
	var img = Image.create(32, 32, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	plank_texture = ImageTexture.create_from_image(img)
	$Sprite2D.texture = plank_texture
	z_index = int(global_position.y)
func _on_area_2d_body_entered(body):
	if body is CharacterBody2D:
		if not multiplayer.has_multiplayer_peer() or body.is_multiplayer_authority():
			if _is_inventory_full("Wood Plank"):
				return
			Inventory.batch_add_item("Wood Plank", plank_texture, durability)
			Inventory.request_inventory_update()
			var scene_node = get_tree().root.get_node("Scene")
			if multiplayer.has_multiplayer_peer():
				if multiplayer.is_server():
					scene_node.sync_remove_floor_item.rpc(item_id)
				else:
					scene_node.request_remove_floor_item.rpc_id(1, item_id)
			else:
				scene_node.remove_floor_item(item_id)
func _is_inventory_full(item_name: String) -> bool:
	for slot in Inventory.slots:
		if slot["item"] == "" or (slot["item"] == item_name and slot["count"] < 99):
			return false
	for slot in Inventory.inv_slots:
		if slot["item"] == "" or (slot["item"] == item_name and slot["count"] < 99):
			return false
	return true
