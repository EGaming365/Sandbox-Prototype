extends Node

signal inventory_changed

var slots = []
var max_slots = 10
var wood_texture = preload("res://Assets/Ninja Adventure - Asset Pack/Items/Resource/Branch.png")

func _ready():
	for i in max_slots:
		slots.append({"item": "", "count": 0, "texture": null})
	
	for i in 0:
		add_item("wood", wood_texture)

func add_item(item_name, texture):
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

func remove_item(from_index):
	slots[from_index]["item"] = ""
	slots[from_index]["count"] = 0
	slots[from_index]["texture"] = null
	emit_signal("inventory_changed")

func move_item(from_index, to_index):
	var temp = slots[from_index].duplicate()
	slots[from_index] = slots[to_index].duplicate()
	slots[to_index] = temp
	emit_signal("inventory_changed")
