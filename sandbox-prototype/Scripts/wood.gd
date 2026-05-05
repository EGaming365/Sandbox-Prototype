extends Node2D

var wood_texture = preload("res://Assets/Wood.png")
@export var item_id: int = -1

func _ready():
	z_index = int(global_position.y)

func _process(_delta):
	z_index = int(global_position.y)

func _on_area_2d_body_entered(body):
	if body is CharacterBody2D:
		if not multiplayer.has_multiplayer_peer() or body.is_multiplayer_authority():
			if _is_inventory_full("Wood"):
				return
			Inventory.add_item("Wood", wood_texture)
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
