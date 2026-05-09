extends Node2D
@onready var area = $Area2D
var player_in_range = false
var max_hits = randi_range(10, 15)
var hits = 0
const MINE_COOLDOWN = 2.0
var rock_id: int = -1

func _ready():
	add_to_group("rocks")
	z_as_relative = false
	z_index = clamp(int(global_position.y / 10), -1000, 1000)
	var img = Image.create(24, 24, false, Image.FORMAT_RGB8)
	img.fill(Color(0.5, 0.5, 0.5))
	var tex = ImageTexture.create_from_image(img)
	$Sprite2D.texture = tex
	$Sprite2D.scale = Vector2(1, 1)

func _process(_delta):
	z_index = clamp(int(global_position.y / 10), -1000, 1000)
	if player_in_range and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var scene_node = get_tree().root.get_node("Scene")
		if scene_node.chop_cooldown_active:
			return
		var mouse_pos = get_global_mouse_position()
		var col = $CollisionShape2D
		var shape = col.shape
		var local_mouse = col.to_local(mouse_pos)
		if shape.get_rect().has_point(local_mouse):
			var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
			var has_pickaxe = false
			if hotbar:
				var slot = Inventory.slots[hotbar.current_slot - 1]
				has_pickaxe = slot["item"] in ["Pickaxe", "Stone Pickaxe"]
			if not has_pickaxe:
				return
			do_mine(1, has_pickaxe)

func do_mine(miner_id: int = 1, has_pickaxe: bool = false):
	var scene_node = get_tree().root.get_node("Scene")
	var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	var mine_time = MINE_COOLDOWN
	if hotbar:
		var slot = Inventory.slots[hotbar.current_slot - 1]
		if slot["item"] == "Stone Pickaxe":
			mine_time = 1.5
		elif slot["item"] == "Pickaxe":
			mine_time = MINE_COOLDOWN
	scene_node.set_chop_cooldown(mine_time)
	hits += 1
	if hotbar:
		var slot_index = hotbar.current_slot - 1
		var slot = Inventory.slots[slot_index]
		if slot["item"] in ["Pickaxe", "Stone Pickaxe"]:
			slot["count"] -= 1
			if slot["count"] <= 0:
				Inventory.remove_item(slot_index, false)
			else:
				Inventory.inventory_changed.emit()
	var angle = randf_range(0, TAU)
	var radius = randf_range(75, 95) + 40
	var drop_pos = global_position + Vector2(cos(angle), sin(angle)) * radius + Vector2(0, -40)
	scene_node.host_spawn_floor_item(drop_pos, "Stone")
	var local_player = hotbar.get_local_player() if hotbar else null
	if local_player and local_player.has_method("start_chop_cooldown"):
		local_player.start_chop_cooldown(mine_time)
	if hits >= max_hits:
		if multiplayer.has_multiplayer_peer():
			scene_node.sync_remove_rock.rpc(rock_id)
		else:
			scene_node.remove_rock(rock_id)
		return
	await get_tree().create_timer(mine_time).timeout

func _on_area_2d_body_entered(body):
	if body is CharacterBody2D:
		player_in_range = true

func _on_area_2d_body_exited(body):
	if body is CharacterBody2D:
		player_in_range = false
