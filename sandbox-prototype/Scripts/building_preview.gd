extends Node2D

const GRID_SIZE = 64
const PLACE_RANGE = 300.0

var preview_sprite: Sprite2D
var can_place: bool = false
var active: bool = false
var current_rotation_deg: float = 0.0

func _ready():
	preview_sprite = Sprite2D.new()
	preview_sprite.modulate = Color(0, 1, 0, 0.5)
	add_child(preview_sprite)
	hide()

func activate(texture: Texture2D):
	preview_sprite.texture = texture
	preview_sprite.scale = Vector2(2, 2)
	active = true
	show()

func deactivate():
	active = false
	hide()
	preview_sprite.texture = null

func get_snapped_mouse_pos() -> Vector2:
	var mouse = get_global_mouse_position()
	return Vector2(
		snapped(mouse.x, GRID_SIZE),
		snapped(mouse.y, GRID_SIZE)
	)

func get_local_player() -> Node:
	for child in get_tree().root.get_node("Scene").get_children():
		if child is CharacterBody2D:
			if multiplayer.has_multiplayer_peer():
				if child.is_multiplayer_authority():
					return child
			else:
				return child
	return null

func get_current_rotation() -> float:
	return current_rotation_deg

func _input(event):
	if not active:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		current_rotation_deg += 90.0
		if current_rotation_deg >= 360.0:
			current_rotation_deg = 0.0
		preview_sprite.rotation_degrees = current_rotation_deg
		get_viewport().set_input_as_handled()

func _process(_delta):
	if not active:
		return

	var snapped = get_snapped_mouse_pos()
	global_position = snapped

	var player = get_local_player()
	if player:
		var dist = player.global_position.distance_to(snapped)
		can_place = dist <= PLACE_RANGE and not _is_occupied(snapped)
	else:
		can_place = false

	if can_place:
		preview_sprite.modulate = Color(0, 1, 0, 0.5)
	else:
		preview_sprite.modulate = Color(1, 0, 0, 0.5)

func _is_occupied(pos: Vector2) -> bool:
	# Check placed blocks
	for block in get_tree().get_nodes_in_group("placed_blocks"):
		if is_instance_valid(block):
			if block.global_position.distance_to(pos) < 1.0:
				return true
	# Check trees using full visual size
	for tree in get_tree().get_nodes_in_group("trees"):
		if is_instance_valid(tree):
			var tree_rect = Rect2(
				tree.global_position + Vector2(-96, -110),
				Vector2(192, 140)
			)
			if tree_rect.has_point(pos):
				return true
	return false
