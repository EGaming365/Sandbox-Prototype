extends Control

var toggle_ui = true
var can_toggle_ui = true
var slots = []
var dragging_from = -1
var dragging_from_inv = false
var drag_node : Control = null

var current_slot = 1
var hotbar_default: StyleBox = preload("res://Resources/hotbar_default.tres")
var hotbar_selected: StyleBox = preload("res://Resources/hotbar_selected.tres")

func _ready():
	for i in range(10):
		slots.append($HBoxContainer.get_node("Item" + str(i + 1)))
	_ready_slots()
	Inventory.inventory_changed.connect(update_hotbar)
	update_hotbar()

func get_local_player():
	for child in get_tree().root.get_node("Scene").get_children():
		if child is CharacterBody2D:
			if multiplayer.has_multiplayer_peer():
				if child.is_multiplayer_authority():
					return child
			else:
				return child
	return null

func update_hotbar():
	for i in range(10):
		var slot = slots[i]
		for child in slot.get_children():
			child.queue_free()
		var data = Inventory.slots[i]
		if data["item"] != "":
			var tex = TextureRect.new()
			tex.texture = data["texture"]
			tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			tex.offset_left = 6
			tex.offset_right = -6
			tex.offset_top = 6
			tex.offset_bottom = -6
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(tex)

			if not Inventory.non_stackable_items.has(data["item"]):
				var label = Label.new()
				label.text = str(min(data["count"], 99))
				label.add_theme_font_size_override("font_size", 16)
				label.add_theme_color_override("font_color", Color.WHITE)
				label.add_theme_color_override("font_outline_color", Color.BLACK)
				label.add_theme_constant_override("outline_size", 4)
				label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
				label.offset_top = -24
				label.offset_bottom = -16
				label.mouse_filter = Control.MOUSE_FILTER_IGNORE
				if data["count"] >= 10:
					label.offset_left = -24
				else:
					label.offset_left = -14
				slot.add_child(label)

			if data["item"] == "Axe":
				var max_dur = 80.0
				var pct = clamp(data["count"] / max_dur, 0.0, 1.0)
				if pct < 1.0:
					var bar_bg = ColorRect.new()
					bar_bg.color = Color(0.2, 0.2, 0.2, 0.8)
					bar_bg.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
					bar_bg.offset_top = -14
					bar_bg.offset_bottom = -9
					bar_bg.offset_left = 7
					bar_bg.offset_right = -7
					bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
					slot.add_child(bar_bg)
					var bar = ColorRect.new()
					var bar_color = Color(1.0 - pct, pct, 0.0)
					bar.color = bar_color
					bar.set_anchor_and_offset(SIDE_LEFT, 0, 0)
					bar.set_anchor_and_offset(SIDE_TOP, 0, 0)
					bar.set_anchor_and_offset(SIDE_BOTTOM, 1, 0)
					bar.set_anchor_and_offset(SIDE_RIGHT, pct, 0)
					bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
					bar_bg.add_child(bar)

func _gui_input_for_slot(event, index):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and Inventory.slots[index]["item"] != "":
			if Input.is_key_pressed(KEY_SHIFT):
				var item_name = Inventory.slots[index]["item"]
				var is_non_stackable = Inventory.non_stackable_items.has(item_name)
				var inv_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
				if inv_ui:
					for i in Inventory.inv_slots.size():
						if Inventory.inv_slots[i]["item"] == "":
							Inventory.move_item(index, i, false, true)
							break
						elif not is_non_stackable and Inventory.inv_slots[i]["item"] == item_name and Inventory.inv_slots[i]["count"] < 99:
							Inventory.move_item(index, i, false, true)
							break
				return
			dragging_from = index
			dragging_from_inv = false
			var container = Control.new()
			container.size = Vector2(40, 40)
			container.z_index = 9
			container.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var tex = TextureRect.new()
			tex.texture = Inventory.slots[index]["texture"]
			tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			container.add_child(tex)
			add_child(container)
			drag_node = container

func _ready_slots():
	for i in range(10):
		var slot = slots[i]
		var idx = i
		slot.gui_input.connect(func(event): _gui_input_for_slot(event, idx))

func _get_hovered_slot() -> int:
	var closest = -1
	var closest_dist = 40.0
	for i in range(slots.size()):
		var center = slots[i].get_global_rect().get_center()
		var dist = get_global_mouse_position().distance_to(center)
		if dist < closest_dist:
			closest_dist = dist
			closest = i
	return closest

func _get_hovered_inv_slot():
	var inv_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
	if inv_ui and inv_ui.visible:
		return inv_ui.get_hovered_slot()
	return -1

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("inventory"):
		var inv_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
		if inv_ui:
			inv_ui.toggle()

	for i in range(1, 11):
		var panel: Panel = $HBoxContainer.get_node("Item" + str(i))
		if i == current_slot:
			panel.add_theme_stylebox_override("panel", hotbar_selected)
			panel.z_index = 1
		else:
			panel.add_theme_stylebox_override("panel", hotbar_default)
			panel.z_index = 0

	if Input.is_action_just_pressed("slot_1"):
		current_slot = 1
	if Input.is_action_just_pressed("slot_2"):
		current_slot = 2
	if Input.is_action_just_pressed("slot_3"):
		current_slot = 3
	if Input.is_action_just_pressed("slot_4"):
		current_slot = 4
	if Input.is_action_just_pressed("slot_5"):
		current_slot = 5
	if Input.is_action_just_pressed("slot_6"):
		current_slot = 6
	if Input.is_action_just_pressed("slot_7"):
		current_slot = 7
	if Input.is_action_just_pressed("slot_8"):
		current_slot = 8
	if Input.is_action_just_pressed("slot_9"):
		current_slot = 9
	if Input.is_action_just_pressed("slot_0"):
		current_slot = 10

	if Input.is_action_just_pressed("slot_up"):
		if current_slot == 10:
			current_slot = 1
		else:
			current_slot = current_slot + 1
	if Input.is_action_just_pressed("slot_down"):
		if current_slot == 1:
			current_slot = 10
		else:
			current_slot = current_slot - 1

	if drag_node:
		drag_node.global_position = get_global_mouse_position() - Vector2(20, 20)
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var dropped_on_hotbar = _get_hovered_slot()
			var dropped_on_inv = _get_hovered_inv_slot()

			if dropped_on_hotbar != -1 and dropped_on_hotbar != dragging_from:
				Inventory.move_item(dragging_from, dropped_on_hotbar, false, false)
			elif dropped_on_inv != -1:
				Inventory.move_item(dragging_from, dropped_on_inv, false, true)
			elif dropped_on_hotbar == -1 and dropped_on_inv == -1:
				var player = get_local_player()
				if player:
					var item_type = Inventory.slots[dragging_from]["item"]
					var count = Inventory.slots[dragging_from]["count"]
					var drop_count = 1 if Inventory.non_stackable_items.has(item_type) else count
					var durability = count if item_type == "Axe" else 60
					var scene_node = get_tree().root.get_node("Scene")
					for i in drop_count:
						var angle = randf_range(0, TAU)
						var radius = randf_range(80, 120)
						var drop_pos = player.global_position + Vector2(cos(angle), sin(angle)) * radius
						if multiplayer.has_multiplayer_peer():
							if multiplayer.is_server():
								scene_node.host_spawn_floor_item(drop_pos, item_type, durability)
							else:
								scene_node.request_spawn_floor_item.rpc_id(1, drop_pos.x, drop_pos.y, item_type, durability)
						else:
							scene_node.host_spawn_floor_item(drop_pos, item_type, durability)
					Inventory.remove_item(dragging_from, false)

			drag_node.queue_free()
			drag_node = null
			dragging_from = -1

	if Input.is_action_just_pressed("toggle_ui"):
		if toggle_ui == true and can_toggle_ui == true:
			toggle_ui = false
		else:
			toggle_ui = true
		can_toggle_ui = false

	if Input.is_action_just_released("toggle_ui"):
		can_toggle_ui = true

	if toggle_ui == true:
		self.show()
	else:
		self.hide()

	if Input.is_action_just_pressed("drop") and not drag_node:
		var data = Inventory.slots[current_slot - 1]
		if data["item"] != "":
			var player = get_local_player()
			if player:
				var item_type = data["item"]
				var count = data["count"]
				var drop_count = 1 if Inventory.non_stackable_items.has(item_type) else count
				var durability = count if item_type == "Axe" else 60
				var scene_node = get_tree().root.get_node("Scene")
				for i in drop_count:
					var angle = randf_range(0, TAU)
					var radius = randf_range(80, 120)
					var drop_pos = player.global_position + Vector2(cos(angle), sin(angle)) * radius
					if multiplayer.has_multiplayer_peer():
						if multiplayer.is_server():
							scene_node.host_spawn_floor_item(drop_pos, item_type, durability)
						else:
							scene_node.request_spawn_floor_item.rpc_id(1, drop_pos.x, drop_pos.y, item_type, durability)
					else:
						scene_node.host_spawn_floor_item(drop_pos, item_type, durability)
				Inventory.remove_item(current_slot - 1, false)
