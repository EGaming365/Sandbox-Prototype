# Inventory autoload.
# Stores the hotbar, the backpack and the offhand slot, and provides functions to add, remove, move, stack and count items.
# It also holds the item pictures, tracks which items the player has discovered and tells other scripts when the inventory changes.

extends Node

# Emitted whenever the inventory changes, so the UI can redraw.
signal inventory_changed

# The hotbar slots. Each slot is a dictionary with an item name, a count and a texture.
var slots = []
# Number of hotbar slots.
var max_slots = 10
# The backpack slots, in the same format as the hotbar.
var inv_slots = []
# Total number of backpack slots.
var max_inv_slots = 80
# How many backpack slots the player can currently use.
var unlocked_inv_slots: int = 20

# Pictures for every item, loaded when the game starts.
var wood_texture = preload("res://Assets/Wood.png")
var axe_texture = preload("res://Assets/Axe.png")
var sword_texture = preload("res://Assets/Sword.png")
var pickaxe_texture = preload("res://Assets/Pickaxe.png")
var stone_axe_texture = preload("res://Assets/Stone_Axe.png")
var stone_sword_texture = preload("res://Assets/Stone_Sword.png")
var stone_pickaxe_texture = preload("res://Assets/Stone_Pickaxe.png")
var bench_texture = preload("res://Assets/Crafting_Bench.png")
var wardrobe_texture = preload("res://Assets/Wardrobe.png")
var wood_plank_texture = preload("res://Assets/Wood_Planks.png")
var stone_texture = preload("res://Assets/Stone.png")
var chicken_raw_texture = preload("res://Assets/Chicken_Raw.png")
var string_texture = preload("res://Assets/String.png")
var coal_texture = preload("res://Assets/Coal.png")
var torch_texture = preload("res://Assets/Torch.png")
var fishing_rod_texture = preload("res://Assets/Fishing_Rod.png")
var stone_fishing_rod_texture = preload("res://Assets/Stone_Fishing_Rod.png")
var copper_fishing_rod_texture = preload("res://Assets/copper_fishing_rod.png")
var tophat_fish_texture = preload("res://Assets/Fish_Tophat_Raw.png")
var perch_texture = preload("res://Assets/Fish_Perch_Raw.png")
var catfish_texture = preload("res://Assets/Fish_Catfish_Raw.png")
var bass_texture = preload("res://Assets/Fish_Bass_Raw.png")
var minnow_texture = preload("res://Assets/Fish_Minnow_Raw.png")
var pike_texture = preload("res://Assets/Fish_Pike_Raw.png")
var sturgeon_texture = preload("res://Assets/Fish_Sturgeon_Raw.png")
var clownfish_texture = preload("res://Assets/Fish_Clownfish_Raw.png")
var salmon_texture = preload("res://Assets/Fish_Catfish_Raw.png")
var lionfish_texture = preload("res://Assets/Fish_Lionfish_Raw.png")
var blue_tang_texture = preload("res://Assets/Fish_Blue_Tang_Raw.png")
var tire_texture = preload("res://Assets/Trash_Tire.png")
var red_tang_texture = preload("res://Assets/Fish_Red_Tang_Raw.png")
var guppy_texture = preload("res://Assets/Fish_Guppy_Raw.png")
var snapper_texture = preload("res://Assets/Fish_Snapper_Raw.png")
var muskie_texture = preload("res://Assets/Fish_Muskie_Raw.png")
var ghost_eel_texture = preload("res://Assets/Fish_Ghost_Eel_Raw.png")
var crystal_creeper_texture = preload("res://Assets/Fish_Crystal_Creeper_Raw.png")

# The fishing manager script, used to read the table of fish.
const FISHING_MANAGER_SCRIPT = preload("res://Scripts/FishingManager.gd")

# Size in pixels that item pictures are resized to.
@export var icon_size: int = 64
# Pattern for finding a fish picture from the fish's name.
@export var fish_texture_path_format: String = "res://Assets/Fish_%s_Raw.png"

# Resized picture for each item name.
var TEXTURE_MAP: Dictionary = {}

# Items that cannot be stacked. Tools, wardrobes and fish each need their own slot because their count stores durability or weight.
var non_stackable_items = [
	"Axe", "Sword", "Pickaxe", "Stone Axe", "Stone Sword", "Stone Pickaxe",
	"Wardrobe", "Fishing Rod", "Stone Fishing Rod",
	"Tophat Fish", "Albino Tophat Fish",
	"Minnow", "Albino Minnow",
	"Perch", "Albino Perch",
	"Bass", "Albino Bass",
	"Pike", "Albino Pike",
	"Catfish", "Albino Catfish",
	"Sturgeon", "Albino Sturgeon",
	"Salmon", "Albino Salmon",
	"Clownfish", "Albino Clownfish",
	"Lionfish", "Albino Lionfish",
	"Blue Tang", "Albino Blue Tang",
	"Tire", "Albino Tire",
	"Red Tang", "Albino Red Tang",
	"Guppy", "Albino Guppy",
	"Snapper", "Albino Snapper",
	"Muskie", "Albino Muskie",
	"Ghost Eel", "Albino Ghost Eel",
	"Crystal Creeper", "Albino Crystal Creeper",
	"Copper Fishing Rod",
]
# Items the player has owned at least once. It is used to reveal recipes.
var discovered_items: Dictionary = {}
# The offhand slot, in the same format as other slots.
var offhand_slot: Dictionary = {"item": "", "count": 0, "texture": null}
# Items that can be held in the offhand.
var offhand_allowed_items: Array = ["Torch"]

# True when a change signal is waiting to be sent.
var _emit_dirty: bool = false
# Time left before the waiting change signal is sent.
var _emit_timer: float = 0.0


# Resizes every item picture, registers the fish pictures and creates the empty slots.
func _ready():
	# Item names and their original pictures. Albino fish share the normal fish picture.
	var textures_to_resize = {
		"Wood": wood_texture,
		"Axe": axe_texture,
		"Sword": sword_texture,
		"Pickaxe": pickaxe_texture,
		"Stone Axe": stone_axe_texture,
		"Stone Sword": stone_sword_texture,
		"Stone Pickaxe": stone_pickaxe_texture,
		"Crafting_Bench": bench_texture,
		"Wardrobe": wardrobe_texture,
		"Wood Plank": wood_plank_texture,
		"Stone": stone_texture,
		"Chicken_Raw": chicken_raw_texture,
		"String": string_texture,
		"Coal": coal_texture,
		"Torch": torch_texture,
		"Fishing Rod": fishing_rod_texture,
		"Tophat Fish": tophat_fish_texture,
		"Albino Tophat Fish": tophat_fish_texture,
		"Perch": perch_texture,
		"Albino Perch": perch_texture,
		"Catfish": catfish_texture,
		"Albino Catfish": catfish_texture,
		"Bass": bass_texture,
		"Albino Bass": bass_texture,
		"Minnow": minnow_texture,
		"Albino Minnow": minnow_texture,
		"Pike": pike_texture,
		"Albino Pike": pike_texture,
		"Sturgeon": sturgeon_texture,
		"Albino Sturgeon": sturgeon_texture,
		"Salmon": salmon_texture,
		"Albino Salmon": salmon_texture,
		"Lionfish": lionfish_texture,
		"Albino Lionfish": lionfish_texture,
		"Clownfish": clownfish_texture,
		"Albino Clownfish": clownfish_texture,
		"Blue Tang": blue_tang_texture,
		"Albino Blue Tang": blue_tang_texture,
		"Tire": tire_texture,
		"Albino Tire": tire_texture,
		"Red Tang": red_tang_texture,
		"Albino Red Tang": red_tang_texture,
		"Guppy": guppy_texture,
		"Albino Guppy": guppy_texture,
		"Snapper": snapper_texture,
		"Albino Snapper": snapper_texture,
		"Muskie": muskie_texture,
		"Albino Muskie": muskie_texture,
		"Ghost Eel": ghost_eel_texture,
		"Albino Ghost Eel": ghost_eel_texture,
		"Crystal Creeper": crystal_creeper_texture,
		"Albino Crystal Creeper": crystal_creeper_texture,
		"Stone Fishing Rod": stone_fishing_rod_texture,
		"Copper Fishing Rod": copper_fishing_rod_texture,
	}
	# Add any fish from the fishing table that are missing.
	_auto_register_fish_textures(textures_to_resize)
	TEXTURE_MAP = {}
	# Resize each picture to the icon size and store it in the texture map.
	for item_name in textures_to_resize:
		var item_texture = textures_to_resize[item_name]
		if item_texture:
			var icon_image = item_texture.get_image()
			if icon_image:
				icon_image.resize(icon_size, icon_size, Image.INTERPOLATE_NEAREST)
				TEXTURE_MAP[item_name] = ImageTexture.create_from_image(icon_image)
			else:
				TEXTURE_MAP[item_name] = item_texture
		else:
			TEXTURE_MAP[item_name] = item_texture
	# Create the empty hotbar and backpack slots.
	for i in max_slots:
		slots.append({"item": "", "count": 0, "texture": null})
	for i in max_inv_slots:
		inv_slots.append({"item": "", "count": 0, "texture": null})


# Makes sure every fish in the fishing table, and its albino version, is non stackable and has a picture.
func _auto_register_fish_textures(target: Dictionary) -> void:
	for fish in FISHING_MANAGER_SCRIPT.FISH_TABLE:
		var fish_name: String = fish.get("name", "")
		if fish_name == "":
			continue
		var albino_name = "Albino " + fish_name
		if not non_stackable_items.has(fish_name):
			non_stackable_items.append(fish_name)
		if not non_stackable_items.has(albino_name):
			non_stackable_items.append(albino_name)
		if target.has(fish_name) and target[fish_name] != null:
			if not target.has(albino_name) or target[albino_name] == null:
				target[albino_name] = target[fish_name]
			continue
		var path = fish_texture_path_format % fish_name.replace(" ", "_")
		if not ResourceLoader.exists(path):
			continue
		var item_texture = load(path)
		if item_texture == null:
			continue
		target[fish_name] = item_texture
		target[albino_name] = item_texture


# Returns the resized picture for an item, or null.
func get_texture(item_name: String) -> Texture2D:
	return TEXTURE_MAP.get(item_name, null)


# Sends the queued change signal once its short delay has passed.
func _process(delta):
	if _emit_dirty:
		_emit_timer -= delta
		if _emit_timer <= 0.0:
			_emit_dirty = false
			_emit_timer = 0.0
			inventory_changed.emit()


# Requests a change signal after 0.05 seconds, so many quick changes only cause one redraw.
func _queue_emit():
	_emit_dirty = true
	_emit_timer = 0.05


# Records that the player has owned the item.
func discover(item_name: String):
	if not discovered_items.has(item_name):
		discovered_items[item_name] = true
		inventory_changed.emit()


# Returns true if the player has discovered every ingredient of the recipe.
func is_discovered(recipe: Dictionary) -> bool:
	for item in recipe["ingredients"]:
		if not discovered_items.has(item):
			return false
	return true


# Adds one item. Stackable items first join an existing stack, otherwise the first empty slot is used. If there is no room the item is lost.
func add_item(item_name, texture):
	var item_texture = get_texture(item_name)
	if item_texture == null:
		item_texture = texture
	discover(item_name)
	var stackable = not non_stackable_items.has(item_name)
	if stackable:
		if offhand_slot["item"] == item_name and offhand_slot["count"] < 99:
			offhand_slot["count"] += 1
			_queue_emit()
			return
		for slot in slots:
			if slot["item"] == item_name and slot["count"] < 99:
				slot["count"] += 1
				_queue_emit()
				return
		for i in unlocked_inv_slots:
			if inv_slots[i]["item"] == item_name and inv_slots[i]["count"] < 99:
				inv_slots[i]["count"] += 1
				_queue_emit()
				return
	for slot in slots:
		if slot["item"] == "":
			slot["item"] = item_name
			slot["count"] = 1
			slot["texture"] = item_texture
			_queue_emit()
			return
	for i in unlocked_inv_slots:
		if inv_slots[i]["item"] == "":
			inv_slots[i]["item"] = item_name
			inv_slots[i]["count"] = 1
			inv_slots[i]["texture"] = item_texture
			_queue_emit()
			return


# Adds an item to the first empty slot with a given count, such as a tool's durability.
func add_item_with_count(item_name: String, texture: Texture2D, count: int):
	var item_texture = get_texture(item_name)
	if item_texture == null:
		item_texture = texture
	discover(item_name)
	for slot in slots:
		if slot["item"] == "":
			slot["item"] = item_name
			slot["count"] = count
			slot["texture"] = item_texture
			inventory_changed.emit()
			return
	for i in unlocked_inv_slots:
		if inv_slots[i]["item"] == "":
			inv_slots[i]["item"] = item_name
			inv_slots[i]["count"] = count
			inv_slots[i]["texture"] = item_texture
			inventory_changed.emit()
			return


# Does the same as add_item_with_count but without sending a change signal.
func add_item_with_count_silent(item_name: String, texture: Texture2D, count: int):
	var item_texture = get_texture(item_name)
	if item_texture == null:
		item_texture = texture
	discover(item_name)
	for slot in slots:
		if slot["item"] == "":
			slot["item"] = item_name
			slot["count"] = count
			slot["texture"] = item_texture
			return
	for i in unlocked_inv_slots:
		if inv_slots[i]["item"] == "":
			inv_slots[i]["item"] = item_name
			inv_slots[i]["count"] = count
			inv_slots[i]["texture"] = item_texture
			return


# Adds many items at once, filling existing stacks and then empty slots. Returns how many actually fitted.
func batch_add_item(item_name: String, texture: Texture2D, count: int = 1) -> int:
	var item_texture = get_texture(item_name)
	if item_texture == null:
		item_texture = texture
	discover(item_name)
	var remaining = count
	var stackable = not non_stackable_items.has(item_name)
	if stackable:
		if offhand_slot["item"] == item_name and offhand_slot["count"] < 99:
			var amount_to_add = min(99 - offhand_slot["count"], remaining)
			offhand_slot["count"] += amount_to_add
			remaining -= amount_to_add
		for slot in slots:
			if remaining <= 0:
				break
			if slot["item"] == item_name and slot["count"] < 99:
				var amount_to_add = min(99 - slot["count"], remaining)
				slot["count"] += amount_to_add
				remaining -= amount_to_add
		for i in unlocked_inv_slots:
			if remaining <= 0:
				break
			if inv_slots[i]["item"] == item_name and inv_slots[i]["count"] < 99:
				var amount_to_add = min(99 - inv_slots[i]["count"], remaining)
				inv_slots[i]["count"] += amount_to_add
				remaining -= amount_to_add
	for slot in slots:
		if remaining <= 0:
			break
		if slot["item"] == "":
			var amount_to_add = min(99, remaining)
			slot["item"] = item_name
			slot["count"] = amount_to_add
			slot["texture"] = item_texture
			remaining -= amount_to_add
	for i in unlocked_inv_slots:
		if remaining <= 0:
			break
		if inv_slots[i]["item"] == "":
			var amount_to_add = min(99, remaining)
			inv_slots[i]["item"] = item_name
			inv_slots[i]["count"] = amount_to_add
			inv_slots[i]["texture"] = item_texture
			remaining -= amount_to_add
	return count - remaining


# Empties the slot at the given index.
func remove_item(from_index: int, from_inv: bool = false):
	var target = inv_slots if from_inv else slots
	target[from_index]["item"] = ""
	target[from_index]["count"] = 0
	target[from_index]["texture"] = null
	inventory_changed.emit()


# Puts an item into the offhand slot.
func set_offhand_item(item_name: String, texture: Texture2D, count: int):
	offhand_slot = {"item": item_name, "count": count, "texture": texture}
	discover(item_name)
	inventory_changed.emit()


# Empties the offhand slot.
func clear_offhand():
	offhand_slot = {"item": "", "count": 0, "texture": null}
	inventory_changed.emit()


# Returns true if the item is allowed in the offhand. An empty slot is always allowed.
func can_item_go_offhand(item_name: String) -> bool:
	return item_name == "" or offhand_allowed_items.has(item_name)


# Moves or swaps a slot's item with the offhand. Returns false if the move is not allowed.
func move_slot_to_offhand(index: int, from_inv: bool = false) -> bool:
	var source = inv_slots if from_inv else slots
	if index < 0 or index >= source.size():
		return false
	var slot_data = source[index]
	if slot_data["item"] == "":
		return false
	if not can_item_go_offhand(slot_data["item"]):
		return false
	if offhand_slot["item"] == slot_data["item"] and not non_stackable_items.has(slot_data["item"]):
		var move_count = min(slot_data["count"], 99 - offhand_slot["count"])
		if move_count <= 0:
			return false
		offhand_slot["count"] += move_count
		slot_data["count"] -= move_count
		if slot_data["count"] <= 0:
			source[index] = {"item": "", "count": 0, "texture": null}
	else:
		source[index] = offhand_slot.duplicate()
		offhand_slot = slot_data.duplicate()
	if offhand_slot["item"] != "":
		discover(offhand_slot["item"])
	inventory_changed.emit()
	return true


# Swaps a hotbar slot with the offhand slot. Returns false if the swap is not allowed.
func swap_hotbar_with_offhand(index: int) -> bool:
	if index < 0 or index >= slots.size():
		return false
	if not can_item_go_offhand(slots[index]["item"]):
		return false
	var swapped_slot = slots[index].duplicate()
	slots[index] = offhand_slot.duplicate()
	offhand_slot = swapped_slot
	if offhand_slot["item"] != "":
		discover(offhand_slot["item"])
	if slots[index]["item"] != "":
		discover(slots[index]["item"])
	inventory_changed.emit()
	return true


# Moves an item between slots. Matching stackable items merge up to 99, otherwise the two slots swap.
func move_item(from_index: int, to_index: int, from_inv: bool = false, to_inv: bool = false):
	var from_arr = inv_slots if from_inv else slots
	var to_arr = inv_slots if to_inv else slots
	var from_slot = from_arr[from_index]
	var to_slot = to_arr[to_index]

	var same_item = from_slot["item"] != "" and from_slot["item"] == to_slot["item"]
	var stackable = same_item and not non_stackable_items.has(from_slot["item"])

	if stackable and to_slot["count"] < 99:
		var space = 99 - to_slot["count"]
		var move_count = min(from_slot["count"], space)
		var new_to_count = to_slot["count"] + move_count
		var new_from_count = from_slot["count"] - move_count
		to_arr[to_index] = {
			"item": to_slot["item"],
			"count": new_to_count,
			"texture": to_slot["texture"],
		}
		if new_from_count <= 0:
			from_arr[from_index] = {"item": "", "count": 0, "texture": null}
		else:
			from_arr[from_index] = {
				"item": from_slot["item"],
				"count": new_from_count,
				"texture": from_slot["texture"],
			}
	else:
		var swapped_slot = from_arr[from_index].duplicate()
		from_arr[from_index] = to_arr[to_index].duplicate()
		to_arr[to_index] = swapped_slot
	inventory_changed.emit()


# Removes an amount of an item, taking from the offhand first, then the hotbar, then the backpack.
func remove_item_by_name(item_name: String, amount: int):
	var remaining = amount
	if offhand_slot["item"] == item_name:
		var amount_to_take = min(offhand_slot["count"], remaining)
		offhand_slot["count"] -= amount_to_take
		remaining -= amount_to_take
		if offhand_slot["count"] <= 0:
			offhand_slot = {"item": "", "count": 0, "texture": null}
	for i in slots.size():
		if remaining <= 0:
			break
		if slots[i]["item"] == item_name:
			var amount_to_take = min(slots[i]["count"], remaining)
			slots[i]["count"] -= amount_to_take
			remaining -= amount_to_take
			if slots[i]["count"] <= 0:
				slots[i] = {"item": "", "count": 0, "texture": null}
	for i in unlocked_inv_slots:
		if remaining <= 0:
			break
		if inv_slots[i]["item"] == item_name:
			var amount_to_take = min(inv_slots[i]["count"], remaining)
			inv_slots[i]["count"] -= amount_to_take
			remaining -= amount_to_take
			if inv_slots[i]["count"] <= 0:
				inv_slots[i] = {"item": "", "count": 0, "texture": null}
	inventory_changed.emit()


# Returns the total number of an item the player has.
func count_item(item_name: String) -> int:
	var item_total = 0
	if offhand_slot["item"] == item_name:
		item_total += offhand_slot["count"]
	for slot in slots:
		if slot["item"] == item_name:
			item_total += slot["count"]
	for i in unlocked_inv_slots:
		if inv_slots[i]["item"] == item_name:
			item_total += inv_slots[i]["count"]
	return item_total


# Sends the change signal immediately.
func flush_inventory_signal():
	inventory_changed.emit()


# Uses up one point of durability on the selected axe and removes it when it breaks.
func consume_axe_durability():
	var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	if not hotbar:
		return
	var slot_index = hotbar.current_slot - 1
	var slot = slots[slot_index]
	if slot["item"] == "Axe":
		slot["count"] -= 1
		if slot["count"] <= 0:
			remove_item(slot_index, false)
		else:
			inventory_changed.emit()


# Sends the change signal so the UI redraws.
func request_inventory_update():
	inventory_changed.emit()


# Returns a fish's weight as text, in grams below one kilogram and in kilograms above.
func get_fish_weight_display(item_name: String, grams: int) -> String:
	if grams <= 0:
		return ""
	if grams < 1000:
		return str(grams) + "g"
	return str(snappedf(grams / 1000.0, 0.01)) + "kg"
