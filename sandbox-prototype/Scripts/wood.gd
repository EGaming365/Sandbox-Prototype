extends Node2D

var wood_texture = preload("res://Assets/Ninja Adventure - Asset Pack/Items/Resource/Branch.png")
@export var item_id: int = -1

func _on_area_2d_body_entered(body):
	if body is CharacterBody2D:
		if not multiplayer.has_multiplayer_peer() or body.is_multiplayer_authority():
			Inventory.add_item("Wood", wood_texture)
			if multiplayer.has_multiplayer_peer():
				remove_item_rpc.rpc(item_id)
			else:
				# Singleplayer: just remove directly
				get_tree().root.get_node("Scene").remove_floor_item(item_id)

@rpc("any_peer", "call_local", "reliable")
func remove_item_rpc(id: int):
	get_tree().root.get_node("Scene").remove_floor_item(id)
