extends Node2D
@onready var area = $Area2D
var player_in_range = false
var max_hits = randi_range(10, 15)
var hits = 0
var rock_id: int = -1
var env_id: String = ""
var trunk_base_y: float = 0.0
@export var average_coal_per_rock: float = 3.0

func _ready():
	add_to_group("rocks")
	z_index = 2
	trunk_base_y = global_position.y
	if has_meta("env_id"):
		env_id = str(get_meta("env_id"))

func _process(_delta):
	var chat = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
	if chat and chat.is_open:
		return
	var inv = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
	if inv and inv.visible:
		return
	if not player_in_range:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	var mouse_pos = get_global_mouse_position()
	var col = $CollisionShape2D
	var shape = col.shape
	var local_mouse = col.to_local(mouse_pos)
	if not shape.get_rect().has_point(local_mouse):
		return
	var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	if not hotbar:
		return
	var slot = Inventory.slots[hotbar.current_slot - 1]
	var held_item = slot["item"]
	if held_item not in ["Pickaxe", "Stone Pickaxe"]:
		return
	var scene_node = get_tree().root.get_node("Scene")
	var local_player = hotbar.get_local_player()
	if local_player and (local_player.chop_cooldown_timer > 0 or local_player.attack_cooldown > 0):
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		scene_node.request_mine_env_rock.rpc_id(1, env_id, held_item)
		if local_player:
			local_player.start_chop_cooldown(_get_mine_time(held_item))
	else:
		if local_player:
			local_player.start_chop_cooldown(_get_mine_time(held_item))
		do_mine(multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1, held_item)

func _get_mine_time(held_item: String) -> float:
	match held_item:
		"Stone Pickaxe":
			return 1.5
		"Pickaxe":
			return 2.0
		_:
			return 2.0

func do_mine(miner_id: int = 1, held_item: String = ""):
	var scene_node = get_tree().root.get_node("Scene")
	hits += 1
	_consume_pickaxe(miner_id)
	var angle = randf_range(0, TAU)
	var radius = randf_range(75, 95) + 40
	var drop_pos = global_position + Vector2(cos(angle), sin(angle)) * radius + Vector2(0, -40)
	if randf() < clamp(average_coal_per_rock / float(max_hits), 0.0, 1.0):
		scene_node.host_spawn_floor_item(drop_pos, "Coal", 1)
	else:
		scene_node.host_spawn_floor_item(drop_pos, "Stone", 1)
	if hits >= max_hits:
		_destroy_self(scene_node)

func _destroy_self(scene_node: Node):
	# Cave rocks use "caverock:" prefix — route to CaveWorldGen's rock tracker
	if env_id.begins_with("caverock:"):
		var cave_gen = get_tree().root.get_node_or_null("Scene/CaveWorldGen")
		if cave_gen and cave_gen._cave_active_rocks.has(env_id):
			cave_gen._cave_active_rocks.erase(env_id)
		# Also remove from position cache so it doesn't respawn on chunk reload
		for cc in cave_gen._cave_rock_positions.keys() if cave_gen else []:
			if cave_gen._cave_rock_positions[cc].has(env_id):
				cave_gen._cave_rock_positions[cc].erase(env_id)
				break
		queue_free()
		return

	if env_id != "":
		if multiplayer.has_multiplayer_peer():
			scene_node.sync_destroy_env_object.rpc(env_id)
		else:
			scene_node.sync_destroy_env_object(env_id)
	elif rock_id != -1:
		if multiplayer.has_multiplayer_peer():
			scene_node.sync_remove_rock.rpc(rock_id)
		else:
			scene_node.remove_rock(rock_id)
	else:
		queue_free()

func _consume_pickaxe(miner_id: int):
	var scene_node = get_tree().root.get_node("Scene")
	if multiplayer.has_multiplayer_peer() and miner_id != multiplayer.get_unique_id():
		scene_node.consume_pickaxe_on_client.rpc_id(miner_id)
		return
	var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	if not hotbar:
		return
	var slot_index = hotbar.current_slot - 1
	var current = Inventory.slots[slot_index]
	if current["item"] in ["Pickaxe", "Stone Pickaxe"]:
		current["count"] -= 1
		if current["count"] <= 0:
			Inventory.remove_item(slot_index, false)
		else:
			Inventory.inventory_changed.emit()

func _on_area_2d_body_entered(body):
	if body is CharacterBody2D:
		player_in_range = true

func _on_area_2d_body_exited(body):
	if body is CharacterBody2D:
		player_in_range = false
