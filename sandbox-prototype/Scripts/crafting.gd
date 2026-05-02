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
	}
]

var plank_texture: Texture2D
var axe_texture: Texture2D

func _ready():
	# Create blank white textures for now
	var img = Image.create(32, 32, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	plank_texture = ImageTexture.create_from_image(img)
	axe_texture = ImageTexture.create_from_image(img)

func get_item_texture(item_name: String) -> Texture2D:
	match item_name:
		"Wood Plank":
			return plank_texture
		"Axe":
			return axe_texture
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
		var count = recipe["ingredients"][item]
		_remove_item(item, count)
	var tex = get_item_texture(recipe["result"])
	for i in recipe["result_count"]:
		Inventory.add_item(recipe["result"], tex)

func _count_item(item_name: String) -> int:
	var total = 0
	for slot in Inventory.slots:
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
				Inventory.slots[i]["item"] = ""
				Inventory.slots[i]["texture"] = null
				Inventory.slots[i]["count"] = 0
	Inventory.inventory_changed.emit()
