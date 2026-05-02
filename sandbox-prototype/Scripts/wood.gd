extends Node2D

var wood_texture = preload("res://Assets/Ninja Adventure - Asset Pack/Items/Resource/Branch.png")
@export var item_id: int = -1

func _on_area_2d_body_entered(body):
	if body is CharacterBody2D:
		if not multiplayer.has_multiplayer_peer() or body.is_multiplayer_authority():
			Inventory.add_item("Wood", wood_texture)
			var scene_node = get_tree().root.get_node("Scene")
			if multiplayer.has_multiplayer_peer():
				if multiplayer.is_server():
					# Host removes directly
					scene_node.remove_floor_item(item_id)
				else:
					# Client asks host to remove
					scene_node.request_remove_floor_item.rpc_id(1, item_id)
			else:
				scene_node.remove_floor_item(item_id)
