extends Control

var inv_slots_ui = []
var dragging_from = -1
var dragging_from_inv = false
var drag_node: TextureRect = null

var slot_scene_default: StyleBox = preload("res://Resources/hotbar_default.tres")

func _ready():
	hide()
	Inventory.inventory_changed.connect(update_inventory)
	_build_slots()
	update_inventory()

func _build_slots():
	var grid = $PanelContainer/HBoxContainer/Inventory/MarginContainer/GridContainer
	for child in grid.get_children():
		child.queue_free()
	inv_slots_ui.clear()

	for i in 30:
		var panel = Panel.new()
		panel.custom_minimum_size = Vector2(50, 50)
		var style = slot_scene_default.duplicate()
		panel.add_theme_stylebox_override("panel", style)
		grid.add_child(panel)
		inv_slots_ui.append(panel)
		var idx = i
		panel.gui_input.connect(func(event): _gui_input_for_slot(event, idx))

func update_inventory():
	for i in 30:
		var slot = inv_slots_ui[i]
		for child in slot.get_children():
			child.queue_free()
		var data = Inventory.inv_slots[i]
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

			var label = Label.new()
			label.text = str(min(data["count"], 99))
			label.add_theme_font_size_override("font_size", 12)
			label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
			label.offset_top = -20
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if data["count"] >= 10:
				label.offset_left = -17
			else:
				label.offset_left = -11
			slot.add_child(label)

	_update_recipe_panel()

func _gui_input_for_slot(event, index):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and Inventory.inv_slots[index]["item"] != "":
			dragging_from = index
			dragging_from_inv = true
			drag_node = TextureRect.new()
			drag_node.texture = Inventory.inv_slots[index]["texture"]
			drag_node.size = Vector2(40, 40)
			drag_node.z_index = 9
			drag_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(drag_node)

func get_hovered_slot() -> int:
	var closest = -1
	var closest_dist = 40.0  # max snap distance in pixels
	for i in inv_slots_ui.size():
		var center = inv_slots_ui[i].get_global_rect().get_center()
		var dist = get_global_mouse_position().distance_to(center)
		if dist < closest_dist:
			closest_dist = dist
			closest = i
	return closest

func _process(_delta):
	if not visible:
		return
	if drag_node:
		drag_node.global_position = get_global_mouse_position() - Vector2(20, 20)
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var dropped_on_inv = get_hovered_slot()
			var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
			var dropped_on_hotbar = hotbar._get_hovered_slot() if hotbar else -1

			if dropped_on_inv != -1 and dropped_on_inv != dragging_from:
				# Inventory -> Inventory
				Inventory.move_item(dragging_from, dropped_on_inv, true, true)
			elif dropped_on_hotbar != -1:
				# Inventory -> Hotbar
				Inventory.move_item(dragging_from, dropped_on_hotbar, true, false)
			elif dropped_on_inv == -1 and dropped_on_hotbar == -1:
				var player = hotbar.get_local_player() if hotbar else null
				if player:
					var item_type = Inventory.inv_slots[dragging_from]["item"]
					var count = Inventory.inv_slots[dragging_from]["count"]
					var scene_node = get_tree().root.get_node("Scene")
					for i in count:
						var angle = randf_range(0, TAU)
						var radius = randf_range(80, 120)
						var drop_pos = player.global_position + Vector2(cos(angle), sin(angle)) * radius
						if multiplayer.has_multiplayer_peer():
							if multiplayer.is_server():
								scene_node.host_spawn_floor_item(drop_pos, item_type)
							else:
								scene_node.request_spawn_floor_item.rpc_id(1, drop_pos.x, drop_pos.y, item_type)
						else:
							scene_node.host_spawn_floor_item(drop_pos, item_type)
					Inventory.remove_item(dragging_from, true)

			drag_node.queue_free()
			drag_node = null
			dragging_from = -1

func _update_recipe_panel():
	var vbox = $PanelContainer/HBoxContainer/Recipes/ScrollContainer/VBoxContainer
	for child in vbox.get_children():
		child.queue_free()

	var all_recipes = Crafting.basic_recipes + Crafting.advanced_recipes
	for recipe in all_recipes:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var icon = TextureRect.new()
		icon.texture = Crafting.get_item_texture(recipe["result"])
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH
		row.add_child(icon)

		var info = VBoxContainer.new()
		var name_label = Label.new()
		name_label.text = str(recipe["result_count"]) + "x " + recipe["result"]
		name_label.add_theme_font_size_override("font_size", 13)
		info.add_child(name_label)

		var ing_label = Label.new()
		var ing_text = ""
		for item in recipe["ingredients"]:
			ing_text += str(recipe["ingredients"][item]) + "x " + item + "  "
		ing_label.text = ing_text
		ing_label.add_theme_font_size_override("font_size", 11)
		info.add_child(ing_label)
		row.add_child(info)

		var btn = Button.new()
		btn.text = "Craft"
		btn.disabled = not Crafting.can_craft(recipe)
		var r = recipe
		btn.pressed.connect(func(): _on_craft(r, btn))
		row.add_child(btn)

		vbox.add_child(row)

		var sep = HSeparator.new()
		vbox.add_child(sep)

func _on_craft(recipe: Dictionary, btn: Button):
	if not is_instance_valid(btn):
		return
	if Crafting.can_craft(recipe):
		Crafting.craft(recipe)
		if is_instance_valid(btn):
			btn.text = "Done!"
		await get_tree().create_timer(0.5).timeout
		if is_instance_valid(btn):
			btn.text = "Craft"
	else:
		if is_instance_valid(btn):
			btn.text = "Need more!"
		await get_tree().create_timer(0.5).timeout
		if is_instance_valid(btn):
			btn.text = "Craft"

func toggle():
	if visible:
		hide()
	else:
		show()
		update_inventory()
