extends Node2D

const GRID_SIZE = 64
const PLACE_RANGE = 300.0

const ITEM_PLACED_SCALE = {
	"Wardrobe": Vector2(3.2, 3.2),
	"Crafting_Bench": Vector2(2, 2),
	"Torch": Vector2(0.42, 0.42),
}
const DEFAULT_PLACED_SCALE = Vector2(1, 1)

const ITEM_SPAWN_OFFSET = {
	"Wardrobe": Vector2(0, -48),
	"Crafting_Bench": Vector2(0, -34),
	"Torch": Vector2(0, -14),
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
	preview_sprite.texture = texture
	preview_sprite.scale = ITEM_PLACED_SCALE.get(item_name, DEFAULT_PLACED_SCALE)
	preview_sprite.offset = Vector2.ZERO
	preview_sprite.rotation_degrees = 0.0
	preview_sprite.flip_h = false
	preview_sprite.flip_v = false
	preview_sprite.position = Vector2.ZERO
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
		if child is CharacterBody2D and child.is_in_group("players"):
			if multiplayer.has_multiplayer_peer():
				if child.is_multiplayer_authority():
					return child
			else:
				return child
	return null

func get_current_rotation() -> float:
	return current_rotation_deg

func _input(_event):
	pass

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
	for player in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(player):
			if (player as Node2D).global_position.distance_to(pos) < 24.0:
				return true
	for enemy in get_tree().get_nodes_in_group("night_enemies"):
		if is_instance_valid(enemy):
			if (enemy as Node2D).global_position.distance_to(pos) < 24.0:
				return true
	for chicken in get_tree().get_nodes_in_group("chickens"):
		if is_instance_valid(chicken):
			if (chicken as Node2D).global_position.distance_to(pos) < 24.0:
				return true
	return false
