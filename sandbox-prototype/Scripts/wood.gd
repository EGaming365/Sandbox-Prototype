extends Node2D

var wood_texture = preload("res://Assets/Ninja Adventure - Asset Pack/Items/Resource/Branch.png")

func _on_area_2d_body_entered(body):
	if body is CharacterBody2D and body.is_multiplayer_authority():
		Inventory.add_item("Wood", wood_texture)
		queue_free()
