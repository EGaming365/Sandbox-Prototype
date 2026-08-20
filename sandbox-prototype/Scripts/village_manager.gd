extends Node2D

@export var spawn_position: Vector2 = Vector2(0, 0)
@export var house_size: Vector2 = Vector2(220, 160)
@export var house_positions: Array[Vector2] = [
	Vector2(-340, -170),
	Vector2(340, -170),
	Vector2(-340, 210),
	Vector2(340, 210)
]
@export var npc_positions: Array[Vector2] = [
	Vector2(-120, 40),
	Vector2(140, 70)
]

var _loaded: bool = false
var _npc_script: Script = preload("res://Scripts/eric_the_guide.gd")

func preload_village() -> void:
	if _loaded:
		return
	_loaded = true
	_spawn_houses()
	_spawn_npcs()

func get_spawn_position() -> Vector2:
	return global_position + spawn_position

func add_house(pos: Vector2, size: Vector2 = house_size) -> Node2D:
	var house := Node2D.new()
	house.name = "VillageHouse"
	house.position = pos
	house.z_index = 1
	add_child(house)

	var floor := ColorRect.new()
	floor.color = Color(0.56, 0.34, 0.18, 1.0)
	floor.size = size
	floor.position = -size * 0.5
	floor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	house.add_child(floor)

	var roof := ColorRect.new()
	roof.color = Color(0.45, 0.12, 0.10, 1.0)
	roof.size = Vector2(size.x + 28, 42)
	roof.position = Vector2(-size.x * 0.5 - 14, -size.y * 0.5 - 28)
	roof.mouse_filter = Control.MOUSE_FILTER_IGNORE
	house.add_child(roof)

	var door := ColorRect.new()
	door.color = Color(0.22, 0.12, 0.06, 1.0)
	door.size = Vector2(42, 64)
	door.position = Vector2(-21, size.y * 0.5 - 64)
	door.mouse_filter = Control.MOUSE_FILTER_IGNORE
	house.add_child(door)

	var collision := StaticBody2D.new()
	house.add_child(collision)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	collision.add_child(shape)
	return house

func add_npc(pos: Vector2, npc_name: String = "Villager", dialogue_line: String = "", portrait: Texture2D = null) -> Node:
	var npc := CharacterBody2D.new()
	npc.name = npc_name.replace(" ", "_")
	npc.set_script(_npc_script)
	add_child(npc)
	npc.position = pos
	npc.npc_name = npc_name
	if dialogue_line != "":
		npc.dialogue_line = dialogue_line
	if portrait:
		npc.npc_portrait = portrait
	return npc

func set_surface_active(active: bool) -> void:
	visible = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	for child in get_children():
		if child.name == "VillageHouse":
			for sub in child.get_children():
				if sub is StaticBody2D:
					sub.set_collision_layer_value(1, active)
					sub.set_collision_mask_value(1, active)
		elif child is CharacterBody2D:
			child.set_collision_layer_value(1, active)
			child.set_collision_mask_value(1, active)

func _spawn_houses() -> void:
	for pos in house_positions:
		add_house(pos)

func _spawn_npcs() -> void:
	add_npc(Vector2(0, 60), "Eric the Guide", "Hello traveller!")
