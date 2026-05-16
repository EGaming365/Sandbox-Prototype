extends Node2D

const GRID_SIZE = 64
const PLACE_RANGE = 300.0

const ITEM_PLACED_SCALE = {
	"Wardrobe": Vector2(3.2, 3.2),
}
const DEFAULT_PLACED_SCALE = Vector2(2, 2)

const ITEM_PREVIEW_OFFSET = {
	"Wardrobe": Vector2(0, -48),
}

const ITEM_SPAWN_OFFSET = {
	"Wardrobe": Vector2(0, -48),
}

var preview_sprite: Sprite2D
var can_place: bool = false
var active: bool = false
var current_rotation_deg: float = 0.0
var current_item_name: String = ""

func get_place_pos() -> Vector2:
	return global_position

func get_place_offset() -> Vector2:
	return Vector2.ZERO

func _ready():
	z_index = 100
	preview_sprite = Sprite2D.new()
	preview_sprite.modulate = Color(0, 1, 0, 0.5)
	add_child(preview_sprite)
	hide()

func activate(texture: Texture2D, item_name: String = ""):
	current_item_name = item_name
	current_rotation_deg = 0.0
	if item_name == "Wood Plank":
		current_rotation_deg = 0.0
		preview_sprite.texture = load("res://Assets/Wood_Plank_Rotated.png")
		preview_sprite.rotation_degrees = 90.0
		preview_sprite.flip_h = false
		preview_sprite.position = Vector2.ZERO
	else:
		preview_sprite.texture = texture
	preview_sprite.scale = ITEM_PLACED_SCALE.get(item_name, DEFAULT_PLACED_SCALE)
	preview_sprite.offset = Vector2.ZERO
	preview_sprite.rotation_degrees = 0.0
	active = true
	show()

func deactivate():
	active = false
	current_item_name = ""
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
	var inv = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
	var chat = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
	if (inv and inv.visible) or (chat and chat.is_open):
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		if current_item_name != "Wood Plank":
			return
		current_rotation_deg += 90.0
		if current_rotation_deg >= 360.0:
			current_rotation_deg = 0.0
		_update_plank_preview()
		get_viewport().set_input_as_handled()

func _update_plank_preview():
	preview_sprite.flip_h = false
	preview_sprite.rotation_degrees = 0.0
	preview_sprite.position = Vector2.ZERO
	match int(current_rotation_deg):
		0:
			preview_sprite.texture = load("res://Assets/Wood_Plank_Rotated.png")
			preview_sprite.rotation_degrees = 90.0
			preview_sprite.flip_h = false
			preview_sprite.flip_v = true
			preview_sprite.scale = Vector2(2, -2)
			preview_sprite.position = Vector2(0, 0)
		180:
			preview_sprite.texture = load("res://Assets/Wood_Plank_Rotated.png")
			preview_sprite.rotation_degrees = 90.0
			preview_sprite.flip_h = false
			preview_sprite.flip_v = true
			preview_sprite.scale = Vector2(2, 2)
			preview_sprite.position = Vector2(0, -46)
		90:
			preview_sprite.scale = Vector2(2, 2)
			preview_sprite.flip_h = false
			preview_sprite.flip_v = false
			preview_sprite.texture = load("res://Assets/Wood_Plank_Rotated.png")
			preview_sprite.position = Vector2(0, 0)
		270:
			preview_sprite.scale = Vector2(2, 2)
			preview_sprite.texture = load("res://Assets/Wood_Plank_Rotated.png")
			preview_sprite.flip_h = true
			preview_sprite.flip_v = true
			preview_sprite.position = Vector2(-2, 0)

func _process(_delta):
	if not active:
		return
	var snapped = get_snapped_mouse_pos()
	global_position = snapped + ITEM_SPAWN_OFFSET.get(current_item_name, Vector2.ZERO)
	var player = get_local_player()
	if player:
		var dist = player.global_position.distance_to(snapped)
		can_place = dist <= PLACE_RANGE and not _is_occupied(global_position)
	else:
		can_place = false
	preview_sprite.modulate = Color(0, 1, 0, 0.5) if can_place else Color(1, 0, 0, 0.5)

func _is_occupied(pos: Vector2) -> bool:
	for block in get_tree().get_nodes_in_group("placed_blocks"):
		if is_instance_valid(block):
			if block.global_position.distance_to(pos) < 1.0:
				return true
	for tree in get_tree().get_nodes_in_group("trees"):
		if is_instance_valid(tree):
			var tree_rect = Rect2(
				tree.global_position + Vector2(-96, -110),
				Vector2(192, 140)
			)
			if tree_rect.has_point(pos):
				return true
	return false
