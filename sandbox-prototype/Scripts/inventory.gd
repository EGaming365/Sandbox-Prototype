extends Node

signal inventory_changed

var slots = []
var max_slots = 10
var inv_slots = []
var max_inv_slots = 80
var unlocked_inv_slots: int = 20

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
var fishing_rod_texture = preload("res://Assets/Fishing_Rod.png")
var stone_fishing_rod_texture = preload("res://Assets/Stone_Fishing_Rod.png")
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

var TEXTURE_MAP: Dictionary = {}

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
]
var discovered_items: Dictionary = {}

var _emit_dirty: bool = false
var _emit_timer: float = 0.0

func _ready():
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
		"Stone Fishing Rod": stone_fishing_rod_texture,
	}
	TEXTURE_MAP = {}
	for item_name in textures_to_resize:
		var tex = textures_to_resize[item_name]
		if tex:
			var img = tex.get_image()
			if img:
				img.resize(64, 64, Image.INTERPOLATE_NEAREST)
				TEXTURE_MAP[item_name] = ImageTexture.create_from_image(img)
			else:
				TEXTURE_MAP[item_name] = tex
		else:
			TEXTURE_MAP[item_name] = tex
	for i in max_slots:
		slots.append({"item": "", "count": 0, "texture": null})
	for i in max_inv_slots:
		inv_slots.append({"item": "", "count": 0, "texture": null})

func get_texture(item_name: String) -> Texture2D:
	return TEXTURE_MAP.get(item_name, null)

func _process(delta):
	if _emit_dirty:
		_emit_timer -= delta
		if _emit_timer <= 0.0:
			_emit_dirty = false
			_emit_timer = 0.0
			inventory_changed.emit()

func _queue_emit():
	_emit_dirty = true
	_emit_timer = 0.05

func discover(item_name: String):
	if not discovered_items.has(item_name):
		discovered_items[item_name] = true
		inventory_changed.emit()

func is_discovered(recipe: Dictionary) -> bool:
	for item in recipe["ingredients"]:
		if not discovered_items.has(item):
			return false
	return true

func add_item(item_name, texture):
	var tex = get_texture(item_name)
	if tex == null:
		tex = texture
	discover(item_name)
	var stackable = not non_stackable_items.has(item_name)
	if stackable:
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
			slot["texture"] = tex
			_queue_emit()
			return
	for i in unlocked_inv_slots:
		if inv_slots[i]["item"] == "":
			inv_slots[i]["item"] = item_name
			inv_slots[i]["count"] = 1
			inv_slots[i]["texture"] = tex
			_queue_emit()
			return

func add_item_with_count(item_name: String, texture: Texture2D, count: int):
	var tex = get_texture(item_name)
	if tex == null:
		tex = texture
	discover(item_name)
	for slot in slots:
		if slot["item"] == "":
			slot["item"] = item_name
			slot["count"] = count
			slot["texture"] = tex
			inventory_changed.emit()
			return
	for i in unlocked_inv_slots:
		if inv_slots[i]["item"] == "":
			inv_slots[i]["item"] = item_name
			inv_slots[i]["count"] = count
			inv_slots[i]["texture"] = tex
			inventory_changed.emit()
			return

func add_item_with_count_silent(item_name: String, texture: Texture2D, count: int):
	var tex = get_texture(item_name)
	if tex == null:
		tex = texture
	discover(item_name)
	for slot in slots:
		if slot["item"] == "":
			slot["item"] = item_name
			slot["count"] = count
			slot["texture"] = tex
			return
	for i in unlocked_inv_slots:
		if inv_slots[i]["item"] == "":
			inv_slots[i]["item"] = item_name
			inv_slots[i]["count"] = count
			inv_slots[i]["texture"] = tex
			return

func batch_add_item(item_name: String, texture: Texture2D, count: int = 1) -> int:
	var tex = get_texture(item_name)
	if tex == null:
		tex = texture
	discover(item_name)
	var remaining = count
	var stackable = not non_stackable_items.has(item_name)
	if stackable:
		for slot in slots:
			if remaining <= 0:
				break
			if slot["item"] == item_name and slot["count"] < 99:
				var add = min(99 - slot["count"], remaining)
				slot["count"] += add
				remaining -= add
		for i in unlocked_inv_slots:
			if remaining <= 0:
				break
			if inv_slots[i]["item"] == item_name and inv_slots[i]["count"] < 99:
				var add = min(99 - inv_slots[i]["count"], remaining)
				inv_slots[i]["count"] += add
				remaining -= add
	for slot in slots:
		if remaining <= 0:
			break
		if slot["item"] == "":
			var add = min(99, remaining)
			slot["item"] = item_name
			slot["count"] = add
			slot["texture"] = tex
			remaining -= add
	for i in unlocked_inv_slots:
		if remaining <= 0:
			break
		if inv_slots[i]["item"] == "":
			var add = min(99, remaining)
			inv_slots[i]["item"] = item_name
			inv_slots[i]["count"] = add
			inv_slots[i]["texture"] = tex
			remaining -= add
	return count - remaining

func remove_item(from_index: int, from_inv: bool = false):
	var target = inv_slots if from_inv else slots
	target[from_index]["item"] = ""
	target[from_index]["count"] = 0
	target[from_index]["texture"] = null
	inventory_changed.emit()

func move_item(from_index: int, to_index: int, from_inv: bool = false, to_inv: bool = false):
	var from_arr = inv_slots if from_inv else slots
	var to_arr = inv_slots if to_inv else slots
	var temp = from_arr[from_index].duplicate()
	from_arr[from_index] = to_arr[to_index].duplicate()
	to_arr[to_index] = temp
	inventory_changed.emit()

func remove_item_by_name(item_name: String, amount: int):
	var remaining = amount
	for i in slots.size():
		if remaining <= 0:
			break
		if slots[i]["item"] == item_name:
			var take = min(slots[i]["count"], remaining)
			slots[i]["count"] -= take
			remaining -= take
			if slots[i]["count"] <= 0:
				slots[i] = {"item": "", "count": 0, "texture": null}
	for i in unlocked_inv_slots:
		if remaining <= 0:
			break
		if inv_slots[i]["item"] == item_name:
			var take = min(inv_slots[i]["count"], remaining)
			inv_slots[i]["count"] -= take
			remaining -= take
			if inv_slots[i]["count"] <= 0:
				inv_slots[i] = {"item": "", "count": 0, "texture": null}
	inventory_changed.emit()

func count_item(item_name: String) -> int:
	var total = 0
	for slot in slots:
		if slot["item"] == item_name:
			total += slot["count"]
	for i in unlocked_inv_slots:
		if inv_slots[i]["item"] == item_name:
			total += inv_slots[i]["count"]
	return total

func flush_inventory_signal():
	inventory_changed.emit()

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

func request_inventory_update():
	inventory_changed.emit()

func get_fish_weight_display(item_name: String, grams: int) -> String:
	if grams <= 0:
		return ""
	if grams < 1000:
		return str(grams) + "g"
	return str(snappedf(grams / 1000.0, 0.01)) + "kg"
