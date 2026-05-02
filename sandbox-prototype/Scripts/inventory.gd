extends Node

signal inventory_changed

var slots = []
var max_slots = 10
var inv_slots = []
var max_inv_slots = 30

var wood_texture = preload("res://Assets/Ninja Adventure - Asset Pack/Items/Resource/Branch.png")

func _ready():
	for i in max_slots:
		slots.append({"item": "", "count": 0, "texture": null})
	for i in max_inv_slots:
		inv_slots.append({"item": "", "count": 0, "texture": null})

func add_item(item_name, texture):
	# Try hotbar first
	for slot in slots:
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
	# Hotbar full, try inventory
	for slot in inv_slots:
		if slot["item"] == item_name and slot["count"] < 99:
			slot["count"] += 1
			emit_signal("inventory_changed")
			return
	for slot in inv_slots:
		if slot["item"] == "":
			slot["item"] = item_name
			slot["count"] = 1
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
	
	
