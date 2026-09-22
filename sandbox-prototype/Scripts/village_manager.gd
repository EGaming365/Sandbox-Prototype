# Village manager.
# Builds a small village of coloured houses and a guide NPC, and can switch the whole village on or off when the player changes world.

extends Node2D

# Where the player appears, relative to the village.
@export var spawn_position: Vector2 = Vector2(0, 0)
# Default width and height of a house in pixels.
@export var house_size: Vector2 = Vector2(220, 160)
# Centre of each house, relative to the village.
@export var house_positions: Array[Vector2] = [
	Vector2(-340, -170),
	Vector2(340, -170),
	Vector2(-340, 210),
	Vector2(340, 210)
]
# Positions for villagers, relative to the village.
@export var npc_positions: Array[Vector2] = [
	Vector2(-120, 40),
	Vector2(140, 70)
]

# True once the village has been built, so it is only built once.
var _loaded: bool = false
# Script that gives a villager its dialogue behaviour.
var _npc_script: Script = preload("res://Scripts/eric_the_guide.gd")


# Builds the houses and villagers the first time it is called.
func preload_village() -> void:
	if _loaded:
		return
	_loaded = true
	_spawn_houses()
	_spawn_npcs()


# Returns the world position where players should appear.
func get_spawn_position() -> Vector2:
	return global_position + spawn_position


# Creates a house from coloured rectangles with a solid collision box and returns it.
func add_house(local_position: Vector2, house_dimensions: Vector2 = house_size) -> Node2D:
	var house := Node2D.new()
	house.name = "VillageHouse"
	house.position = local_position
	house.z_index = 1
	add_child(house)

	# Brown floor rectangle centred on the house.
	var floor_rect := ColorRect.new()
	floor_rect.color = Color(0.56, 0.34, 0.18, 1.0)
	floor_rect.size = house_dimensions
	floor_rect.position = -house_dimensions * 0.5
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	house.add_child(floor_rect)

	# Red roof strip that overhangs the top of the house.
	var roof_rect := ColorRect.new()
	roof_rect.color = Color(0.45, 0.12, 0.10, 1.0)
	roof_rect.size = Vector2(house_dimensions.x + 28, 42)
	roof_rect.position = Vector2(-house_dimensions.x * 0.5 - 14, -house_dimensions.y * 0.5 - 28)
	roof_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	house.add_child(roof_rect)

	# Dark door at the bottom centre of the house.
	var door_rect := ColorRect.new()
	door_rect.color = Color(0.22, 0.12, 0.06, 1.0)
	door_rect.size = Vector2(42, 64)
	door_rect.position = Vector2(-21, house_dimensions.y * 0.5 - 64)
	door_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	house.add_child(door_rect)

	# Solid body so players cannot walk through the house.
	var collision_body := StaticBody2D.new()
	house.add_child(collision_body)
	var collision_shape := CollisionShape2D.new()
	var collision_rectangle := RectangleShape2D.new()
	collision_rectangle.size = house_dimensions
	collision_shape.shape = collision_rectangle
	collision_body.add_child(collision_shape)
	return house


# Creates a villager with the given name, dialogue line and portrait, and returns it.
func add_npc(
	local_position: Vector2,
	npc_name: String = "Villager",
	dialogue_line: String = "",
	portrait: Texture2D = null,
) -> Node:
	var npc := CharacterBody2D.new()
	npc.name = npc_name.replace(" ", "_")
	# Give the character body the dialogue script.
	npc.set_script(_npc_script)
	add_child(npc)
	npc.position = local_position
	npc.npc_name = npc_name
	if dialogue_line != "":
		npc.dialogue_line = dialogue_line
	if portrait:
		npc.npc_portrait = portrait
	return npc


# Shows or hides the village and turns its collisions on or off, for example when the player enters the cave.
func set_surface_active(is_active: bool) -> void:
	visible = is_active
	process_mode = Node.PROCESS_MODE_INHERIT if is_active else Node.PROCESS_MODE_DISABLED
	# Houses store their collision in a child body, while villagers collide directly.
	for child in get_children():
		if child.name == "VillageHouse":
			for house_part in child.get_children():
				if house_part is StaticBody2D:
					house_part.set_collision_layer_value(1, is_active)
					house_part.set_collision_mask_value(1, is_active)
		elif child is CharacterBody2D:
			child.set_collision_layer_value(1, is_active)
			child.set_collision_mask_value(1, is_active)


# Creates one house at each configured position.
func _spawn_houses() -> void:
	for local_position in house_positions:
		add_house(local_position)


# Creates the village guide.
func _spawn_npcs() -> void:
	add_npc(Vector2(0, 60), "Eric the Guide", "Hello traveller!")
