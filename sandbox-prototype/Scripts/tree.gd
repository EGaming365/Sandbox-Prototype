extends Node2D

@onready var area = $Area2D
var player_in_range = false
var max_hits = randi_range(4, 8)
var hits = 0
const CHOP_COOLDOWN = 0.1
static var can_chop = true
var tree_id: int = -1

func _ready():
	add_to_group("trees")

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

	if hits >= max_hits:
		can_chop = true
		if multiplayer.has_multiplayer_peer():
			get_tree().root.get_node("Scene").sync_remove_tree.rpc(tree_id)
		else:
			get_tree().root.get_node("Scene").remove_tree(tree_id)
		return

	await get_tree().create_timer(CHOP_COOLDOWN).timeout
	can_chop = true
