extends Node
signal inventory_changed
var slots = []
var max_slots = 10
var inv_slots = []
var max_inv_slots = 80
var wood_texture = preload("res://Assets/Wood.png")
var axe_texture = preload("res://Assets/Axe.png")
var sword_texture = preload("res://Assets/Sword.png")

func _ready():
	for i in max_slots:
		slots.append({"item": "", "count": 0, "texture": null})
	for i in max_inv_slots:
		inv_slots.append({"item": "", "count": 0, "texture": null})
var non_stackable_items = ["Axe", "Sword"]

func add_item(item_name, texture):
	discover(item_name)
	var stackable = not non_stackable_items.has(item_name)
	if stackable:
		for slot in slots:
			if slot["item"] == item_name and slot["count"] < 99:
				slot["count"] += 1
				emit_signal("inventory_changed")
				return
		for slot in inv_slots:
			if slot["item"] == item_name and slot["count"] < 99:
				slot["count"] += 1
				emit_signal("inventory_changed")
				return
	for slot in slots:
		if slot["item"] == "":
			slot["item"] = item_name
			slot["count"] = 1
			slot["texture"] = texture
			emit_signal("inventory_changed")
			return
	for slot in inv_slots:
		if slot["item"] == "":
			slot["item"] = item_name
			slot["count"] = 1
			slot["texture"] = texture
			emit_signal("inventory_changed")
			return

func add_item_with_count(item_name: String, texture: Texture2D, count: int):
	discover(item_name)
	for slot in slots:
		if slot["item"] == "":
			slot["item"] = item_name
			slot["count"] = count
			slot["texture"] = texture
			emit_signal("inventory_changed")
			return
	for slot in inv_slots:
		if slot["item"] == "":
			slot["item"] = item_name
			slot["count"] = count
			slot["texture"] = texture
			emit_signal("inventory_changed")
			return
func remove_item(from_index: int, from_inv: bool = false):
	var target = inv_slots if from_inv else slots
	target[from_index]["item"] = ""
	target[from_index]["count"] = 0
	target[from_index]["texture"] = null
	emit_signal("inventory_changed")
func move_item(from_index: int, to_index: int, from_inv: bool = false, to_inv: bool = false):
	var from_arr = inv_slots if from_inv else slots
	var to_arr = inv_slots if to_inv else slots
	var temp = from_arr[from_index].duplicate()
	from_arr[from_index] = to_arr[to_index].duplicate()
	to_arr[to_index] = temp
	emit_signal("inventory_changed")
func count_item(item_name: String) -> int:
	var total = 0
	for slot in slots:
		if slot["item"] == item_name:
			total += slot["count"]
	for slot in inv_slots:
		if slot["item"] == item_name:
			total += slot["count"]
	return total
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
	for i in inv_slots.size():
		if remaining <= 0:
			break
		if inv_slots[i]["item"] == item_name:
			var take = min(inv_slots[i]["count"], remaining)
			inv_slots[i]["count"] -= take
			remaining -= take
			if inv_slots[i]["count"] <= 0:
				inv_slots[i] = {"item": "", "count": 0, "texture": null}
	emit_signal("inventory_changed")

func consume_axe_durability():
	print("=== consume_axe_durability CALLED ===")
	var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	if not hotbar:
		print("ERROR: no hotbar found")
		return
	var slot_index = hotbar.current_slot - 1
	var slot = slots[slot_index]
	print("slot_index: ", slot_index, " | item: ", slot["item"], " | count: ", slot["count"])
	if slot["item"] == "Axe":
		slot["count"] -= 1
		print("new count: ", slot["count"])
		if slot["count"] <= 0:
			remove_item(slot_index, false)
		else:
			emit_signal("inventory_changed")
	else:
		print("ERROR: slot is not Axe, it is: ", slot["item"])
var discovered_items: Dictionary = {}

func discover(item_name: String):
	if not discovered_items.has(item_name):
		discovered_items[item_name] = true
		inventory_changed.emit()

func is_discovered(recipe: Dictionary) -> bool:
	for item in recipe["ingredients"]:
		if not Inventory.discovered_items.has(item):
			return false
	return true

var _emit_pending: bool = false

func batch_add_item(item_name: String, texture: Texture2D, count: int = 1):
	discover(item_name)
	var stackable = not non_stackable_items.has(item_name)
	if stackable:
		for slot in slots:
			if slot["item"] == item_name and slot["count"] < 99:
				slot["count"] += min(count, 99 - slot["count"])
				return
		for slot in inv_slots:
			if slot["item"] == item_name and slot["count"] < 99:
				slot["count"] += min(count, 99 - slot["count"])
				return
	for slot in slots:
		if slot["item"] == "":
			slot["item"] = item_name
			slot["count"] = count
			slot["texture"] = texture
			return
	for slot in inv_slots:
		if slot["item"] == "":
			slot["item"] = item_name
			slot["count"] = count
			slot["texture"] = texture
			return

func flush_inventory_signal():
	inventory_changed.emit()

var _signal_timer: SceneTree = null

func request_inventory_update():
	if not _emit_pending:
		_emit_pending = true
		Engine.get_main_loop().create_timer(0.05).timeout.connect(_do_emit)

func _do_emit():
	_emit_pending = false
	inventory_changed.emit()
