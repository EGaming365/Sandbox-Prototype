extends Node
var basic_recipes = [
	{
		"result": "Wood Plank",
		"result_count": 4,
		"ingredients": { "Wood": 4 }
	}
]
var advanced_recipes = [
	{
		"result": "Axe",
		"result_count": 1,
		"ingredients": { "Wood": 2, "Wood Plank": 3 }
	},
	{
		"result": "Sword",
		"result_count": 1,
		"ingredients": { "Wood": 1, "Wood Plank": 2 }
	}
]
var plank_texture: Texture2D
var axe_texture: Texture2D
var sword_texture: Texture2D
func _ready():
	var img = Image.create(32, 32, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	plank_texture = ImageTexture.create_from_image(img)
	var axe_img = Image.create(32, 32, false, Image.FORMAT_RGB8)
	axe_img.fill(Color.YELLOW)
	axe_texture = ImageTexture.create_from_image(axe_img)
	var sword_img = Image.create(32, 32, false, Image.FORMAT_RGB8)
	sword_img.fill(Color.SILVER)
	sword_texture = ImageTexture.create_from_image(sword_img)
func get_item_texture(item_name: String) -> Texture2D:
	match item_name:
		"Wood Plank":
			return plank_texture
		"Axe":
			return axe_texture
		"Sword":
			return sword_texture
	return null
func can_craft(recipe: Dictionary) -> bool:
	for item in recipe["ingredients"]:
		var count = recipe["ingredients"][item]
		if _count_item(item) < count:
			return false
	return true
func craft(recipe: Dictionary):
	if not can_craft(recipe):
		return
	for item in recipe["ingredients"]:
		_remove_item(item, recipe["ingredients"][item])
	var tex = get_item_texture(recipe["result"])
	if recipe["result"] == "Axe":
		Inventory.add_item_with_count("Axe", tex, 80)
	elif recipe["result"] == "Sword":
		Inventory.add_item_with_count("Sword", tex, 30)
	else:
		for i in recipe["result_count"]:
			Inventory.add_item(recipe["result"], tex)
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
	Inventory.inventory_changed.emit()
