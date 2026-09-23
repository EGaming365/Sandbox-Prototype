extends Node2D

# Grid cell size (in pixels) that placement positions snap to.
const GRID_SIZE = 64
# Max distance from the local player that a placement is allowed at.
const PLACE_RANGE = 300.0

# Per-item scale overrides applied to the preview/placed sprite.
# Anything not listed here falls back to DEFAULT_PLACED_SCALE.
const ITEM_PLACED_SCALE = {
	"Wardrobe": Vector2(3.2, 3.2),
	"Crafting_Bench": Vector2(2, 2),
	"Torch": Vector2(0.42, 0.42),
}
const DEFAULT_PLACED_SCALE = Vector2(1, 1)

# Per-item offset applied on top of the snapped grid position, so
# sprites with off-center art still line up with the grid cell.
const ITEM_SPAWN_OFFSET = {
	"Wardrobe": Vector2(0, -48),
	"Crafting_Bench": Vector2(0, -34),
	"Torch": Vector2(0, -14),
}

# The actual sprite shown while previewing a placement.
var preview_sprite: Sprite2D
# Whether the current snapped position is a valid place to build.
var can_place: bool = false
# Whether the preview is currently active (being shown/dragged around).
var active: bool = false
# Current rotation of the item being previewed, in degrees.
var current_rotation_deg: float = 0.0
# Name of the item currently being previewed (used to look up scale/offset).
var current_item_name: String = ""


# Returns the world position the item would actually be placed at.
func get_place_pos() -> Vector2:
	return global_position


# Returns any additional placement offset (currently unused, always zero).
func get_place_offset() -> Vector2:
	return Vector2.ZERO


func _ready():
	# Draw above everything else in the scene.
	z_index = 100
	# Build the preview sprite in code rather than as a scene child.
	preview_sprite = Sprite2D.new()
	preview_sprite.modulate = Color(0, 1, 0, 0.5)
	add_child(preview_sprite)
	# Hidden until activate() is called.
	hide()


# Turns on the preview for a given item, resetting rotation/flip/offset
# back to defaults so leftover state from a previous item doesn't carry over.
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


# Turns off the preview and clears its texture/state.
func deactivate():
	active = false
	current_item_name = ""
	hide()
	preview_sprite.texture = null


# Snaps the current mouse position to the placement grid.
func get_snapped_mouse_pos() -> Vector2:
	var mouse = get_global_mouse_position()
	return Vector2(
		snapped(mouse.x, GRID_SIZE),
		snapped(mouse.y, GRID_SIZE)
	)


# Finds the player this client controls (the multiplayer authority),
# or just the first player found in single-player.
func get_local_player() -> Node:
	for child in get_tree().root.get_node("Scene").get_children():
		if child is CharacterBody2D and child.is_in_group("players"):
			if multiplayer.has_multiplayer_peer():
				if child.is_multiplayer_authority():
					return child
			else:
				return child
	return null


# Returns the preview's current rotation, in degrees.
func get_current_rotation() -> float:
	return current_rotation_deg


func _input(_event):
	# Intentionally empty — input handling lives elsewhere (e.g. building_manager.gd).
	pass


func _process(_delta):
	# Nothing to update while the preview isn't active.
	if not active:
		return
	# Snap to the grid, then apply the item's spawn offset on top.
	var snapped = get_snapped_mouse_pos()
	global_position = snapped + ITEM_SPAWN_OFFSET.get(current_item_name, Vector2.ZERO)
	# Placement is only valid within range of the local player and on
	# a tile that isn't already occupied.
	var player = get_local_player()
	if player:
		var dist = player.global_position.distance_to(snapped)
		can_place = dist <= PLACE_RANGE and not _is_occupied(global_position)
	else:
		can_place = false
	# Green when placeable, red when not — visual feedback for the player.
	preview_sprite.modulate = Color(0, 1, 0, 0.5) if can_place else Color(1, 0, 0, 0.5)


# Checks whether a given position is blocked by an existing placed block,
# a tree, a player, a night enemy, or a chicken.
func _is_occupied(pos: Vector2) -> bool:
	# Existing placed blocks: blocked if essentially on the same spot.
	for block in get_tree().get_nodes_in_group("placed_blocks"):
		if is_instance_valid(block):
			if block.global_position.distance_to(pos) < 1.0:
				return true
	# Trees: blocked if the position falls inside the tree's footprint rect.
	for tree in get_tree().get_nodes_in_group("trees"):
		if is_instance_valid(tree):
			var tree_rect = Rect2(
				tree.global_position + Vector2(-96, -110),
				Vector2(192, 140)
			)
			if tree_rect.has_point(pos):
				return true
	# Players, night enemies, chickens: blocked if too close to any of them.
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
