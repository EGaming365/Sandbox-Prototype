extends Node2D

@onready var area = $Area2D
var player_in_range = false
var max_hits = randi_range(4, 8)
var hits = 0
const CHOP_COOLDOWN = 0.1
static var can_chop = true

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
				# Client just sends a request, never chops directly
				if multiplayer.has_multiplayer_peer():
					if multiplayer.is_server():
						drop_wood()
					else:
						request_chop.rpc_id(1)
				else:
					drop_wood()

# Client asks host to chop this tree
@rpc("any_peer", "call_remote", "reliable")
func request_chop():
	if not can_chop:
		return
	drop_wood()

# Host tells all clients to visually react (optional: shake animation etc)
@rpc("authority", "call_local", "reliable")
func sync_chop():
	# Play chop animation/sound here if you have one
	pass

# Host tells all clients to remove the tree
@rpc("authority", "call_local", "reliable")
func sync_tree_death():
	queue_free()

func drop_wood():
	if not can_chop:
		return
	can_chop = false
	hits += 1

	# Notify all clients a chop happened
	sync_chop.rpc()

	var angle = randf_range(0, TAU)
	var radius = randf_range(75, 95) + 40
	var drop_pos = position + Vector2(cos(angle), sin(angle)) * radius + Vector2(0, -40)

	var scene_node = get_tree().root.get_node("Scene")
	if multiplayer.has_multiplayer_peer():
		scene_node.host_spawn_floor_item(drop_pos)
	else:
		scene_node.host_spawn_floor_item(drop_pos)

	if hits >= max_hits:
		can_chop = true
		sync_tree_death.rpc()  # removes tree on all clients
		return

	await get_tree().create_timer(CHOP_COOLDOWN).timeout
	can_chop = true
