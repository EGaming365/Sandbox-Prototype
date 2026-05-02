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
	var grid = $PanelContainer/HBoxContainer/InventoryPanel/GridContainer
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
			drag_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(drag_node)

func _get_hovered_inv_slot():
	for i in inv_slots_ui.size():
		if inv_slots_ui[i].get_global_rect().has_point(get_global_mouse_position()):
			return i
	return -1

func _process(_delta):
	if not visible:
		return
	if drag_node:
		drag_node.global_position = get_global_mouse_position() - Vector2(20, 20)
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var dropped_on = _get_hovered_inv_slot()
			if dropped_on != -1 and dropped_on != dragging_from:
				Inventory.move_item(dragging_from, dropped_on, true, true)
			elif dropped_on == -1:
				# Drop on floor
				var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
				var player = hotbar.get_local_player() if hotbar else null
				if player:
					var wood_scene = preload("res://Scenes/wood.tscn")
					var count = Inventory.inv_slots[dragging_from]["count"]
					var scene_node = get_tree().root.get_node("Scene")
					for i in count:
						var angle = randf_range(0, TAU)
						var radius = randf_range(80, 120)
						var drop_pos = player.global_position + Vector2(cos(angle), sin(angle)) * radius
						if multiplayer.has_multiplayer_peer():
							if multiplayer.is_server():
								scene_node.host_spawn_floor_item(drop_pos)
							else:
								scene_node.request_spawn_floor_item.rpc_id(1, drop_pos.x, drop_pos.y)
						else:
							scene_node.host_spawn_floor_item(drop_pos)
					Inventory.remove_item(dragging_from, true)
			drag_node.queue_free()
			drag_node = null
			dragging_from = -1

func _update_recipe_panel():
	var vbox = $PanelContainer/HBoxContainer/RecipePanel/VBoxContainer
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
		btn.pressed.connect(func(): _on_craft(recipe, btn))
		row.add_child(btn)

		vbox.add_child(row)

		# Separator
		var sep = HSeparator.new()
		vbox.add_child(sep)

func _on_craft(recipe: Dictionary, btn: Button):
	if Crafting.can_craft(recipe):
		Crafting.craft(recipe)
		btn.text = "Done!"
		await get_tree().create_timer(0.5).timeout
		btn.text = "Craft"
	else:
		btn.text = "Need more!"
		await get_tree().create_timer(0.5).timeout
		btn.text = "Craft"

func toggle():
	if visible:
		hide()
	else:
		show()
		update_inventory()
