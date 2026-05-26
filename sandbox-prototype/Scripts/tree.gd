extends Node2D
@onready var area = $Area2D
var player_in_range = false
var player_in_range_node = null
var max_hits = randi_range(4, 8)
var hits = 0
var tree_id: int = -1
var env_id: String = ""
var trunk_base_y: float = 0.0

var _chat: Node = null
var _inv: Node = null
var _hotbar: Node = null

func _ready():
	add_to_group("trees")
	z_index = 2
	trunk_base_y = global_position.y
	if has_meta("env_id"):
		env_id = str(get_meta("env_id"))
	_chat = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
	_inv = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
	_hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")

func _process(_delta):
	if not player_in_range:
		return
	if is_instance_valid(_chat) and "is_open" in _chat and _chat.is_open:
		return
	if is_instance_valid(_inv) and _inv.visible:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	var mouse_pos = get_global_mouse_position()
	var col = $CollisionShape2D
	var shape = col.shape
	var local_mouse = col.to_local(mouse_pos)
	if not shape.get_rect().has_point(local_mouse):
		return
	var held_item = ""
	if is_instance_valid(_hotbar):
		var slot = Inventory.slots[_hotbar.current_slot - 1]
		held_item = slot["item"]
	var scene_node = get_tree().root.get_node("Scene")
	var local_player = _hotbar.get_local_player() if is_instance_valid(_hotbar) else null
	if local_player and (local_player.chop_cooldown_timer > 0 or local_player.attack_cooldown > 0):
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		scene_node.request_chop_env_tree.rpc_id(1, env_id, held_item)
		if local_player:
			local_player.start_chop_cooldown(_get_chop_time(held_item))
	else:
		if local_player:
			local_player.start_chop_cooldown(_get_chop_time(held_item))
		do_chop(multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1, held_item)

func _get_chop_time(held_item: String) -> float:
	match held_item:
		"Stone Axe":
			return 1.0
		"Axe":
			return 1.5
		_:
			return 2.0

func do_chop(chopper_id: int = 1, held_item: String = ""):
	var scene_node = get_tree().root.get_node("Scene")
	var has_axe = held_item in ["Axe", "Stone Axe"]
	hits += 1
	var angle = randf_range(0, TAU)
	var radius = randf_range(75, 95) + 40
	var drop_pos = global_position + Vector2(cos(angle), sin(angle)) * radius + Vector2(0, -40)
	scene_node.host_spawn_floor_item(drop_pos, "Wood", 1)
	if has_axe:
		_consume_axe(chopper_id)
	if hits >= max_hits:
		if env_id != "":
			if multiplayer.has_multiplayer_peer():
				scene_node.sync_destroy_env_object.rpc(env_id)
			else:
				scene_node.sync_destroy_env_object(env_id)
		elif tree_id != -1:
			if multiplayer.has_multiplayer_peer():
				scene_node.sync_remove_tree.rpc(tree_id)
			else:
				scene_node.remove_tree(tree_id)
		else:
			queue_free()

func _consume_axe(chopper_id: int):
	var scene_node = get_tree().root.get_node("Scene")
	if multiplayer.has_multiplayer_peer() and chopper_id != multiplayer.get_unique_id():
		scene_node.consume_axe_on_client.rpc_id(chopper_id)
		return
	var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	if not hotbar:
		return
	var slot_index = hotbar.current_slot - 1
	var current = Inventory.slots[slot_index]
	if current["item"] in ["Axe", "Stone Axe"]:
		current["count"] -= 1
		if current["count"] <= 0:
			Inventory.remove_item(slot_index, false)
		else:
			Inventory.inventory_changed.emit()

func _on_area_2d_body_entered(body):
	if body is CharacterBody2D:
		player_in_range = true
		player_in_range_node = body

func _on_area_2d_body_exited(body):
	if body is CharacterBody2D:
		player_in_range = false
		player_in_range_node = null
