extends Node2D

@onready var area = $Area2D
var player_in_range = false
var max_hits = randi_range(4, 8)
var hits = 0
const CHOP_COOLDOWN = 1.5
static var can_chop = true
var tree_id: int = -1
var chop_cooldown_timer: float = 0.0
var chop_cooldown_max: float = CHOP_COOLDOWN

func _ready():
	add_to_group("trees")

func _process(delta):
	z_index = int(global_position.y)
	if not can_chop and chop_cooldown_max > 0:
		chop_cooldown_timer = max(chop_cooldown_timer - delta, 0.0)
		var pct = chop_cooldown_timer / chop_cooldown_max
		var cursor_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/Cursor")
		if cursor_ui:
			cursor_ui.show_cooldown(pct)

func _on_area_2d_body_entered(body):
	if body is CharacterBody2D:
		player_in_range = true

func _on_area_2d_body_exited(body):
	if body is CharacterBody2D:
		player_in_range = false

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if player_in_range and can_chop:
			var mouse_pos = get_global_mouse_position()
			var col = $CollisionShape2D
			var shape = col.shape
			var local_mouse = col.to_local(mouse_pos)
			if shape.get_rect().has_point(local_mouse):
				if multiplayer.has_multiplayer_peer():
					if multiplayer.is_server():
						do_chop()
					else:
						get_tree().root.get_node("Scene").request_chop_tree.rpc_id(1, tree_id)
				else:
					do_chop()

func do_chop():
	if not can_chop:
		return
	can_chop = false
	hits += 1

	var angle = randf_range(0, TAU)
	var radius = randf_range(75, 95) + 40
	var drop_pos = global_position + Vector2(cos(angle), sin(angle)) * radius + Vector2(0, -40)
	get_tree().root.get_node("Scene").host_spawn_floor_item(drop_pos)

	var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	var chop_time = CHOP_COOLDOWN
	if hotbar:
		var slot_index = hotbar.current_slot - 1
		var current = Inventory.slots[slot_index]
		if current["item"] == "Axe":
			chop_time = 1.0
			current["count"] -= 1
			if current["count"] <= 0:
				Inventory.remove_item(slot_index, false)
			else:
				Inventory.inventory_changed.emit()

	if hits >= max_hits:
		can_chop = true
		if multiplayer.has_multiplayer_peer():
			get_tree().root.get_node("Scene").sync_remove_tree.rpc(tree_id)
		else:
			get_tree().root.get_node("Scene").remove_tree(tree_id)
		return

	chop_cooldown_max = chop_time
	chop_cooldown_timer = chop_time
	await get_tree().create_timer(chop_time).timeout
	can_chop = true
