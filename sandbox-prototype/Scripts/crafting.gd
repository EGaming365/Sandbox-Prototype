extends Node

var basic_recipes = [
	{
		"result": "Wood Plank",
		"result_count": 4,
		"ingredients": { "Wood": 4 }
	},
	{
		"result": "Crafting_Bench",
		"result_count": 1,
		"ingredients": { "Wood Plank": 4 }
	}
]
var bench_recipes = [
	{
		"result": "Axe",
		"result_count": 1,
		"ingredients": { "Wood": 2, "Wood Plank": 3 }
	},
	{
		"result": "Sword",
		"result_count": 1,
		"ingredients": { "Wood": 1, "Wood Plank": 2 }
	},
	{
		"result": "Pickaxe",
		"result_count": 1,
		"ingredients": { "Wood": 2, "Wood Plank": 3 }
	},
	{
		"result": "Stone Axe",
		"result_count": 1,
		"ingredients": { "Stone": 3, "Wood": 2 }
	},
	{
		"result": "Stone Sword",
		"result_count": 1,
		"ingredients": { "Stone": 2, "Wood": 1 }
	},
	{
		"result": "Stone Pickaxe",
		"result_count": 1,
		"ingredients": { "Stone": 3, "Wood": 2 }
	},
	{
		"result": "Wardrobe",
		"result_count": 1,
		"ingredients": { "Wood Plank": 5, "Stone": 1 }
	}
]
var plank_texture: Texture2D
var axe_texture: Texture2D
var sword_texture: Texture2D
var bench_texture: Texture2D
var wood_texture: Texture2D
var stone_texture: Texture2D
var pickaxe_texture: Texture2D
var stone_axe_texture: Texture2D
var stone_sword_texture: Texture2D
var stone_pickaxe_texture: Texture2D
var wardrobe_texture: Texture2D

func _ready():
	stone_texture = load("res://Assets/Stone.png")
	wood_texture = load("res://Assets/Wood.png")
	axe_texture = load("res://Assets/Axe.png")
	sword_texture = load("res://Assets/Sword.png")
	pickaxe_texture = load("res://Assets/Pickaxe.png")
	stone_axe_texture = load("res://Assets/Stone_Axe.png")
	stone_sword_texture = load("res://Assets/Stone_Sword.png")
	stone_pickaxe_texture = load("res://Assets/Stone_Pickaxe.png")
	plank_texture = load("res://Assets/Wood_Planks.png")
	bench_texture = load("res://Assets/Crafting_Bench.png")
	wardrobe_texture = load("res://Assets/Wardrobe.png")

func get_item_texture(item_name: String) -> Texture2D:
	match item_name:
		"Wood":
			return Inventory.wood_texture
		"Wood Plank":
			return plank_texture
		"Axe":
			return Inventory.axe_texture
		"Sword":
			return Inventory.sword_texture
		"Crafting_Bench":
			return Inventory.bench_texture
		"Stone":
			return Inventory.stone_texture
		"Pickaxe":
			return Inventory.pickaxe_texture
		"Stone Axe":
			return Inventory.stone_axe_texture
		"Stone Sword":
			return Inventory.stone_sword_texture
		"Stone Pickaxe":
			return Inventory.stone_pickaxe_texture
		"Wardrobe":
			return Inventory.wardrobe_texture
	return null

func is_near_bench() -> bool:
	var player = _get_local_player()
	if not player:
		return false
	for bench in get_tree().get_nodes_in_group("crafting_benches"):
		if is_instance_valid(bench):
			if player.global_position.distance_to(bench.global_position) <= 100.0:
				return true
	return false
func _get_local_player():
	for child in get_tree().root.get_node("Scene").get_children():
		if child is CharacterBody2D:
			if multiplayer.has_multiplayer_peer():
				if child.is_multiplayer_authority():
					return child
			else:
				return child
	return null
func can_craft(recipe: Dictionary) -> bool:
	if bench_recipes.has(recipe) and not is_near_bench():
		return false

	for item in recipe["ingredients"]:
		var count = recipe["ingredients"][item]
		if _count_item(item) < count:
			return false

	return true

func _has_inventory_space() -> bool:
	for slot in Inventory.slots:
		if slot["item"] == "":
			return true
	for slot in Inventory.inv_slots:
		if slot["item"] == "":
			return true
	return false

func craft(recipe: Dictionary, silent: bool = false):
	if not can_craft(recipe):
		return
	for item in recipe["ingredients"]:
		_remove_item(item, recipe["ingredients"][item])
	var tex = get_item_texture(recipe["result"])
	var player = _get_local_player()
	var scene_node = get_tree().root.get_node("Scene")

	if recipe["result"] == "Axe":
		if _has_inventory_space():
			if silent:
				Inventory.add_item_with_count_silent("Axe", tex, 80)
			else:
				Inventory.add_item_with_count("Axe", tex, 80)
		elif player:
			var drop_pos = player.global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60))
			if multiplayer.has_multiplayer_peer():
				if multiplayer.is_server():
					scene_node.host_spawn_floor_item(drop_pos, "Axe", 80)
				else:
					scene_node.request_spawn_floor_item.rpc_id(1, drop_pos.x, drop_pos.y, "Axe", 80)
			else:
				scene_node.host_spawn_floor_item(drop_pos, "Axe", 80)
	elif recipe["result"] == "Sword":
		if _has_inventory_space():
			if silent:
				Inventory.add_item_with_count_silent("Sword", tex, 30)
			else:
				Inventory.add_item_with_count("Sword", tex, 30)
		elif player:
			var drop_pos = player.global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60))
			if multiplayer.has_multiplayer_peer():
				if multiplayer.is_server():
					scene_node.host_spawn_floor_item(drop_pos, "Sword", 30)
				else:
					scene_node.request_spawn_floor_item.rpc_id(1, drop_pos.x, drop_pos.y, "Sword", 30)
			else:
				scene_node.host_spawn_floor_item(drop_pos, "Sword", 30)
	elif recipe["result"] == "Stone Axe":
		if _has_inventory_space():
			Inventory.add_item_with_count("Stone Axe", tex, 120)
		elif player:
			var drop_pos = player.global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60))
			if multiplayer.has_multiplayer_peer():
				if multiplayer.is_server():
					scene_node.host_spawn_floor_item(drop_pos, "Stone Axe", 120)
				else:
					scene_node.request_spawn_floor_item.rpc_id(1, drop_pos.x, drop_pos.y, "Stone Axe", 120)
			else:
				scene_node.host_spawn_floor_item(drop_pos, "Stone Axe", 120)
	elif recipe["result"] == "Stone Sword":
		if _has_inventory_space():
			Inventory.add_item_with_count("Stone Sword", tex, 40)
		elif player:
			var drop_pos = player.global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60))
			if multiplayer.has_multiplayer_peer():
				if multiplayer.is_server():
					scene_node.host_spawn_floor_item(drop_pos, "Stone Sword", 40)
				else:
					scene_node.request_spawn_floor_item.rpc_id(1, drop_pos.x, drop_pos.y, "Stone Sword", 40)
			else:
				scene_node.host_spawn_floor_item(drop_pos, "Stone Sword", 40)
	elif recipe["result"] == "Stone Pickaxe":
		if _has_inventory_space():
			Inventory.add_item_with_count("Stone Pickaxe", tex, 100)
		elif player:
			var drop_pos = player.global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60))
			if multiplayer.has_multiplayer_peer():
				if multiplayer.is_server():
					scene_node.host_spawn_floor_item(drop_pos, "Stone Pickaxe", 100)
				else:
					scene_node.request_spawn_floor_item.rpc_id(1, drop_pos.x, drop_pos.y, "Stone Pickaxe", 100)
			else:
				scene_node.host_spawn_floor_item(drop_pos, "Stone Pickaxe", 100)
	elif recipe["result"] == "Pickaxe":
		if _has_inventory_space():
			if silent:
				Inventory.add_item_with_count_silent("Pickaxe", tex, 80)
			else:
				Inventory.add_item_with_count("Pickaxe", tex, 80)
		elif player:
			var drop_pos = player.global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60))
			if multiplayer.has_multiplayer_peer():
				if multiplayer.is_server():
					scene_node.host_spawn_floor_item(drop_pos, "Pickaxe", 80)
				else:
					scene_node.request_spawn_floor_item.rpc_id(1, drop_pos.x, drop_pos.y, "Pickaxe", 80)
			else:
				scene_node.host_spawn_floor_item(drop_pos, "Pickaxe", 80)
	elif recipe["result"] == "Wardrobe":
		if _has_inventory_space():
			if silent:
				Inventory.add_item_with_count_silent("Wardrobe", tex, 1)
			else:
				Inventory.add_item_with_count("Wardrobe", tex, 1)
		elif player:
			var drop_pos = player.global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60))
			if multiplayer.has_multiplayer_peer():
				if multiplayer.is_server():
					scene_node.host_spawn_floor_item(drop_pos, "Wardrobe", 1)
				else:
					scene_node.request_spawn_floor_item.rpc_id(1, drop_pos.x, drop_pos.y, "Wardrobe", 1)
			else:
				scene_node.host_spawn_floor_item(drop_pos, "Wardrobe", 1)
	else:
		for i in recipe["result_count"]:
			if _has_inventory_space():
				if silent:
					Inventory.batch_add_item(recipe["result"], tex, 1)
				else:
					Inventory.add_item(recipe["result"], tex)
			elif player:
				var drop_pos = player.global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60))
				if multiplayer.has_multiplayer_peer():
					if multiplayer.is_server():
						scene_node.host_spawn_floor_item(drop_pos, recipe["result"], 1)
					else:
						scene_node.request_spawn_floor_item.rpc_id(1, drop_pos.x, drop_pos.y, recipe["result"], 1)
				else:
					scene_node.host_spawn_floor_item(drop_pos, recipe["result"], 1)

	if not silent:
		return
	Inventory.inventory_changed.emit()

func _count_item(item_name: String) -> int:
	var total = 0
	for slot in Inventory.slots:
		if slot["item"] == item_name:
			total += slot["count"]
	for slot in Inventory.inv_slots:
		if slot["item"] == item_name:
			total += slot["count"]
	return total
func _remove_item(item_name: String, amount: int):
	var remaining = amount
	for i in Inventory.slots.size():
		if remaining <= 0:
			break
		if Inventory.slots[i]["item"] == item_name:
			var take = min(Inventory.slots[i]["count"], remaining)
			Inventory.slots[i]["count"] -= take
			remaining -= take
			if Inventory.slots[i]["count"] <= 0:
				Inventory.slots[i] = {"item": "", "count": 0, "texture": null}
	for i in Inventory.inv_slots.size():
		if remaining <= 0:
			break
		if Inventory.inv_slots[i]["item"] == item_name:
			var take = min(Inventory.inv_slots[i]["count"], remaining)
			Inventory.inv_slots[i]["count"] -= take
			remaining -= take
			if Inventory.inv_slots[i]["count"] <= 0:
				Inventory.inv_slots[i] = {"item": "", "count": 0, "texture": null}

func _add_result_silent(recipe: Dictionary):
	var tex = get_item_texture(recipe["result"])
	var result = recipe["result"]
	match result:
		"Axe":
			Inventory.add_item_with_count_silent(result, tex, 80)
		"Sword":
			Inventory.add_item_with_count_silent(result, tex, 30)
		"Pickaxe":
			Inventory.add_item_with_count_silent(result, tex, 80)
		"Stone Axe":
			Inventory.add_item_with_count_silent(result, tex, 120)
		"Stone Sword":
			Inventory.add_item_with_count_silent(result, tex, 40)
		"Stone Pickaxe":
			Inventory.add_item_with_count_silent(result, tex, 100)
		"Wardrobe":
			Inventory.add_item_with_count_silent(result, tex, 1)
		_:
			for i in recipe["result_count"]:
				Inventory.batch_add_item(result, tex, 1)
