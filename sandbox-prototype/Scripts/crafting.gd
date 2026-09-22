# Crafting system autoload.
# Holds the recipe lists and item pictures, checks whether the player can craft a recipe and carries out the crafting.
# Some recipes need a nearby crafting bench.

extends Node

# Recipes that can be crafted anywhere. Each recipe has a result, how many are made and the ingredients with amounts.
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
	},
	{
		"result": "Torch",
		"result_count": 4,
		"ingredients": { "Wood": 1, "Coal": 1 }
	}
]
# Recipes that need a crafting bench nearby.
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
		"result": "Fishing Rod",
		"result_count": 1,
		"ingredients": { "Wood": 3, "String": 2 }
	},
	{
		"result": "Stone Fishing Rod",
		"result_count": 1,
		"ingredients": { "Stone": 2, "Wood": 1, "String": 3 }
	},
	{
		"result": "Copper Fishing Rod",
		"result_count": 1,
		"ingredients": { "Copper": 2, "Wood": 1, "String": 3 }
	},
	{
		"result": "Wardrobe",
		"result_count": 1,
		"ingredients": { "Wood Plank": 5, "Stone": 1 }
	}
]
# Another name for the bench recipes, used by the crafting menu.
var advanced_recipes = bench_recipes
# Pictures for each craftable item and ingredient. They are loaded in _ready.
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
var string_texture: Texture2D
var coal_texture: Texture2D
var torch_texture: Texture2D
var fishing_rod_texture: Texture2D
var stone_fishing_rod_texture: Texture2D


# Loads the picture for every item. Coal currently uses the stone picture.
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
	string_texture = load("res://Assets/String.png")
	coal_texture = load("res://Assets/Stone.png")
	torch_texture = load("res://Assets/Torch.png")
	fishing_rod_texture = load("res://Assets/Fishing_Rod.png")
	stone_fishing_rod_texture = load("res://Assets/Stone_Fishing_Rod.png")


# Returns the picture for an item name, or null if the item has no picture.
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
		"String":
			return Inventory.string_texture
		"Coal":
			return Inventory.coal_texture
		"Torch":
			return Inventory.torch_texture
		"Fishing Rod":
			return Inventory.fishing_rod_texture
		"Stone Fishing Rod":
			return Inventory.stone_fishing_rod_texture
	return null


# Returns true if the local player is within 100 pixels of a crafting bench.
func is_near_bench() -> bool:
	var player = _get_local_player()
	if not player:
		return false
	for crafting_bench in get_tree().get_nodes_in_group("crafting_benches"):
		if is_instance_valid(crafting_bench):
			if player.global_position.distance_to(crafting_bench.global_position) <= 100.0:
				return true
	return false


# Returns the player controlled by this game instance, or null.
func _get_local_player():
	for child in get_tree().root.get_node("Scene").get_children():
		if child is CharacterBody2D and child.is_in_group("players"):
			if multiplayer.has_multiplayer_peer():
				if child.is_multiplayer_authority():
					return child
			else:
				return child
	return null


# Returns true if the player has every ingredient, and is near a bench when the recipe needs one.
func can_craft(recipe: Dictionary) -> bool:
	if bench_recipes.has(recipe) and not is_near_bench():
		return false

	for item in recipe["ingredients"]:
		var count = recipe["ingredients"][item]
		if _count_item(item) < count:
			return false

	return true


# Returns true if any hotbar or inventory slot is empty.
func _has_inventory_space() -> bool:
	for slot in Inventory.slots:
		if slot["item"] == "":
			return true
	for slot in Inventory.inv_slots:
		if slot["item"] == "":
			return true
	return false


# Uses up the ingredients and gives the player the result. If the inventory is full the result drops on the floor near the player.
func craft(recipe: Dictionary, silent: bool = false):
	if not can_craft(recipe):
		return
	for item in recipe["ingredients"]:
		_remove_item(item, recipe["ingredients"][item])
	var item_texture = get_item_texture(recipe["result"])
	var player = _get_local_player()
	var scene_node = get_tree().root.get_node("Scene")

	# Tools are created with a starting durability stored as their count. The silent version skips the inventory sound and messages.
	if recipe["result"] == "Axe":
		if _has_inventory_space():
			if silent:
				Inventory.add_item_with_count_silent("Axe", item_texture, 80)
			else:
				Inventory.add_item_with_count("Axe", item_texture, 80)
		elif player:
			var drop_position = player.global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60))
			if multiplayer.has_multiplayer_peer():
				if multiplayer.is_server():
					scene_node.host_spawn_floor_item(drop_position, "Axe", 80)
				else:
					scene_node.request_spawn_floor_item.rpc_id(1, drop_position.x, drop_position.y, "Axe", 80)
			else:
				scene_node.host_spawn_floor_item(drop_position, "Axe", 80)
	# Sword with 30 durability.
	elif recipe["result"] == "Sword":
		if _has_inventory_space():
			if silent:
				Inventory.add_item_with_count_silent("Sword", item_texture, 30)
			else:
				Inventory.add_item_with_count("Sword", item_texture, 30)
		elif player:
			var drop_position = player.global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60))
			if multiplayer.has_multiplayer_peer():
				if multiplayer.is_server():
					scene_node.host_spawn_floor_item(drop_position, "Sword", 30)
				else:
					scene_node.request_spawn_floor_item.rpc_id(1, drop_position.x, drop_position.y, "Sword", 30)
			else:
				scene_node.host_spawn_floor_item(drop_position, "Sword", 30)
	# Stone axe with 120 durability.
	elif recipe["result"] == "Stone Axe":
		if _has_inventory_space():
			Inventory.add_item_with_count("Stone Axe", item_texture, 120)
		elif player:
			var drop_position = player.global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60))
			if multiplayer.has_multiplayer_peer():
				if multiplayer.is_server():
					scene_node.host_spawn_floor_item(drop_position, "Stone Axe", 120)
				else:
					scene_node.request_spawn_floor_item.rpc_id(1, drop_position.x, drop_position.y, "Stone Axe", 120)
			else:
				scene_node.host_spawn_floor_item(drop_position, "Stone Axe", 120)
	# Stone sword with 40 durability.
	elif recipe["result"] == "Stone Sword":
		if _has_inventory_space():
			Inventory.add_item_with_count("Stone Sword", item_texture, 40)
		elif player:
			var drop_position = player.global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60))
			if multiplayer.has_multiplayer_peer():
				if multiplayer.is_server():
					scene_node.host_spawn_floor_item(drop_position, "Stone Sword", 40)
				else:
					scene_node.request_spawn_floor_item.rpc_id(1, drop_position.x, drop_position.y, "Stone Sword", 40)
			else:
				scene_node.host_spawn_floor_item(drop_position, "Stone Sword", 40)
	# Stone pickaxe with 100 durability.
	elif recipe["result"] == "Stone Pickaxe":
		if _has_inventory_space():
			Inventory.add_item_with_count("Stone Pickaxe", item_texture, 100)
		elif player:
			var drop_position = player.global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60))
			if multiplayer.has_multiplayer_peer():
				if multiplayer.is_server():
					scene_node.host_spawn_floor_item(drop_position, "Stone Pickaxe", 100)
				else:
					scene_node.request_spawn_floor_item.rpc_id(1, drop_position.x, drop_position.y, "Stone Pickaxe", 100)
			else:
				scene_node.host_spawn_floor_item(drop_position, "Stone Pickaxe", 100)
	# Fishing rod with 50 durability.
	elif recipe["result"] == "Fishing Rod":
		if _has_inventory_space():
			if silent:
				Inventory.add_item_with_count_silent("Fishing Rod", item_texture, 50)
			else:
				Inventory.add_item_with_count("Fishing Rod", item_texture, 50)
		elif player:
			var drop_position = player.global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60))
			if multiplayer.has_multiplayer_peer():
				if multiplayer.is_server():
					scene_node.host_spawn_floor_item(drop_position, "Fishing Rod", 50)
				else:
					scene_node.request_spawn_floor_item.rpc_id(1, drop_position.x, drop_position.y, "Fishing Rod", 50)
			else:
				scene_node.host_spawn_floor_item(drop_position, "Fishing Rod", 50)
	# Stone fishing rod with 100 durability.
	elif recipe["result"] == "Stone Fishing Rod":
		if _has_inventory_space():
			if silent:
				Inventory.add_item_with_count_silent("Stone Fishing Rod", item_texture, 100)
			else:
				Inventory.add_item_with_count("Stone Fishing Rod", item_texture, 100)
		elif player:
			var drop_position = player.global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60))
			if multiplayer.has_multiplayer_peer():
				if multiplayer.is_server():
					scene_node.host_spawn_floor_item(drop_position, "Stone Fishing Rod", 100)
				else:
					scene_node.request_spawn_floor_item.rpc_id(
						1, drop_position.x, drop_position.y, "Stone Fishing Rod", 100,
					)
			else:
				scene_node.host_spawn_floor_item(drop_position, "Stone Fishing Rod", 100)
	# Pickaxe with 80 durability.
	elif recipe["result"] == "Pickaxe":
		if _has_inventory_space():
			if silent:
				Inventory.add_item_with_count_silent("Pickaxe", item_texture, 80)
			else:
				Inventory.add_item_with_count("Pickaxe", item_texture, 80)
		elif player:
			var drop_position = player.global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60))
			if multiplayer.has_multiplayer_peer():
				if multiplayer.is_server():
					scene_node.host_spawn_floor_item(drop_position, "Pickaxe", 80)
				else:
					scene_node.request_spawn_floor_item.rpc_id(1, drop_position.x, drop_position.y, "Pickaxe", 80)
			else:
				scene_node.host_spawn_floor_item(drop_position, "Pickaxe", 80)
	# Wardrobe, which is a single item.
	elif recipe["result"] == "Wardrobe":
		if _has_inventory_space():
			if silent:
				Inventory.add_item_with_count_silent("Wardrobe", item_texture, 1)
			else:
				Inventory.add_item_with_count("Wardrobe", item_texture, 1)
		elif player:
			var drop_position = player.global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60))
			if multiplayer.has_multiplayer_peer():
				if multiplayer.is_server():
					scene_node.host_spawn_floor_item(drop_position, "Wardrobe", 1)
				else:
					scene_node.request_spawn_floor_item.rpc_id(1, drop_position.x, drop_position.y, "Wardrobe", 1)
			else:
				scene_node.host_spawn_floor_item(drop_position, "Wardrobe", 1)
	else:
		# Every other recipe, such as planks, benches and torches, gives ordinary items that can stack.
		for i in recipe["result_count"]:
			if _has_inventory_space():
				if silent:
					Inventory.batch_add_item(recipe["result"], item_texture, 1)
				else:
					Inventory.add_item(recipe["result"], item_texture)
			elif player:
				var drop_position = player.global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60))
				if multiplayer.has_multiplayer_peer():
					if multiplayer.is_server():
						scene_node.host_spawn_floor_item(drop_position, recipe["result"], 1)
					else:
						scene_node.request_spawn_floor_item.rpc_id(1, drop_position.x, drop_position.y, recipe["result"], 1)
				else:
					scene_node.host_spawn_floor_item(drop_position, recipe["result"], 1)

	# Silent crafts do not update the inventory display themselves, so signal the change once at the end.
	if not silent:
		return
	Inventory.inventory_changed.emit()


# Returns how many of an item the player has in the offhand, hotbar and inventory.
func _count_item(item_name: String) -> int:
	var item_total = 0
	if Inventory.offhand_slot["item"] == item_name:
		item_total += Inventory.offhand_slot["count"]
	for slot in Inventory.slots:
		if slot["item"] == item_name:
			item_total += slot["count"]
	for slot in Inventory.inv_slots:
		if slot["item"] == item_name:
			item_total += slot["count"]
	return item_total


# Removes the given amount of an item, taking from the offhand first, then the hotbar, then the inventory.
func _remove_item(item_name: String, amount: int):
	var remaining = amount
	if Inventory.offhand_slot["item"] == item_name:
		var amount_to_take = min(Inventory.offhand_slot["count"], remaining)
		Inventory.offhand_slot["count"] -= amount_to_take
		remaining -= amount_to_take
		if Inventory.offhand_slot["count"] <= 0:
			Inventory.offhand_slot = {"item": "", "count": 0, "texture": null}
	for i in Inventory.slots.size():
		if remaining <= 0:
			break
		if Inventory.slots[i]["item"] == item_name:
			var amount_to_take = min(Inventory.slots[i]["count"], remaining)
			Inventory.slots[i]["count"] -= amount_to_take
			remaining -= amount_to_take
			if Inventory.slots[i]["count"] <= 0:
				Inventory.slots[i] = {"item": "", "count": 0, "texture": null}
	for i in Inventory.inv_slots.size():
		if remaining <= 0:
			break
		if Inventory.inv_slots[i]["item"] == item_name:
			var amount_to_take = min(Inventory.inv_slots[i]["count"], remaining)
			Inventory.inv_slots[i]["count"] -= amount_to_take
			remaining -= amount_to_take
			if Inventory.inv_slots[i]["count"] <= 0:
				Inventory.inv_slots[i] = {"item": "", "count": 0, "texture": null}


# Adds the crafted result without messages, using the same starting durability as craft.
func _add_result_silent(recipe: Dictionary):
	var item_texture = get_item_texture(recipe["result"])
	var result = recipe["result"]
	match result:
		"Axe":
			Inventory.add_item_with_count_silent(result, item_texture, 80)
		"Sword":
			Inventory.add_item_with_count_silent(result, item_texture, 30)
		"Pickaxe":
			Inventory.add_item_with_count_silent(result, item_texture, 80)
		"Stone Axe":
			Inventory.add_item_with_count_silent(result, item_texture, 120)
		"Stone Sword":
			Inventory.add_item_with_count_silent(result, item_texture, 40)
		"Stone Pickaxe":
			Inventory.add_item_with_count_silent(result, item_texture, 100)
		"Fishing Rod":
			Inventory.add_item_with_count_silent(result, item_texture, 50)
		"Stone Fishing Rod":
			Inventory.add_item_with_count_silent(result, item_texture, 100)
		"Wardrobe":
			Inventory.add_item_with_count_silent(result, item_texture, 1)
		_:
			for i in recipe["result_count"]:
				Inventory.batch_add_item(result, item_texture, 1)
