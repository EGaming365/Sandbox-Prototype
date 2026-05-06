extends Node2D
@onready var area = $Area2D
var player_in_range = false
var player_in_range_node = null
var max_hits = randi_range(4, 8)
var hits = 0
const CHOP_COOLDOWN = 1.5
var tree_id: int = -1
func _ready():
	z_as_relative = false
	z_index = int(global_position.y)
func _process(_delta):
	z_index = int(global_position.y)
	var chat = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
	if chat and chat.is_open:
		return
	var inv = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
	if inv and inv.visible:
		return
	if player_in_range and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var mouse_pos = get_global_mouse_position()
		var col = $CollisionShape2D
		var shape = col.shape
		var local_mouse = col.to_local(mouse_pos)
		if not shape.get_rect().has_point(local_mouse):
			return
		var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
		var has_axe = false
		if hotbar:
			var slot = Inventory.slots[hotbar.current_slot - 1]
			has_axe = slot["item"] == "Axe"
		var scene_node = get_tree().root.get_node("Scene")
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			var local_player = hotbar.get_local_player() if hotbar else null
			if local_player and local_player.chop_cooldown_timer > 0:
				return
			scene_node.request_chop_tree.rpc_id(1, tree_id, has_axe)
			var chop_time = 1.0 if has_axe else CHOP_COOLDOWN
			if local_player:
				local_player.start_chop_cooldown(chop_time)
		else:
			if scene_node.chop_cooldown_active:
				return
			do_chop(multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1, has_axe)
func _on_area_2d_body_entered(body):
	if body is CharacterBody2D:
		player_in_range = true
		player_in_range_node = body
func _on_area_2d_body_exited(body):
	if body is CharacterBody2D:
		player_in_range = false
		player_in_range_node = null
func do_chop(chopper_id: int = 1, has_axe: bool = false):
	var scene_node = get_tree().root.get_node("Scene")
	var chop_time = 1.0 if has_axe else CHOP_COOLDOWN
	scene_node.set_chop_cooldown(chop_time)
	hits += 1
	var angle = randf_range(0, TAU)
	var radius = randf_range(75, 95) + 40
	var drop_pos = global_position + Vector2(cos(angle), sin(angle)) * radius + Vector2(0, -40)
	scene_node.host_spawn_floor_item(drop_pos, "Wood", 1)
	if has_axe:
		if multiplayer.has_multiplayer_peer() and chopper_id != multiplayer.get_unique_id():
			scene_node.consume_axe_on_client.rpc_id(chopper_id)
		else:
			var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
			if hotbar:
				var slot_index = hotbar.current_slot - 1
				var current = Inventory.slots[slot_index]
				if current["item"] == "Axe":
					current["count"] -= 1
					if current["count"] <= 0:
						Inventory.remove_item(slot_index, false)
					else:
						Inventory.inventory_changed.emit()
	if multiplayer.has_multiplayer_peer() and chopper_id == multiplayer.get_unique_id():
		var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
		var local_player = hotbar.get_local_player() if hotbar else null
		if local_player:
			local_player.start_chop_cooldown(chop_time)
	elif not multiplayer.has_multiplayer_peer():
		var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
		var local_player = hotbar.get_local_player() if hotbar else null
		if local_player:
			local_player.start_chop_cooldown(chop_time)
	if hits >= max_hits:
		if multiplayer.has_multiplayer_peer():
			scene_node.sync_remove_tree.rpc(tree_id)
		else:
			scene_node.remove_tree(tree_id)
		return
	await get_tree().create_timer(chop_time).timeout
