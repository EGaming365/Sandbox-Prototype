extends Node2D

var wood_texture = preload("res://Assets/Ninja Adventure - Asset Pack/Items/Resource/Branch.png")

func _on_area_2d_body_entered(body):
	if body is CharacterBody2D:
		if not multiplayer.has_multiplayer_peer() or body.is_multiplayer_authority():
			Inventory.add_item("Wood", wood_texture)
			queue_free()
