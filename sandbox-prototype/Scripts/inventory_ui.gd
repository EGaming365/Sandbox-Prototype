# Inventory screen.
# A full screen menu with tabs for the backpack, the crafting recipes and the equipped items.
# The player can drag items between slots, split stacks, drop items and craft recipes here. The item data itself is stored in the Inventory autoload.

extends Control

# The slot nodes on screen.
var inv_slots_ui = []
# Index of the slot an item is being dragged from, or -1.
var dragging_from = -1
# True if the dragged item came from the backpack.
var dragging_from_inv = false
# The picture that follows the mouse while dragging.
var drag_node: Control = null
# Index of the slot under the mouse, or -1.
var hovered_slot: int = -1
# The tab currently shown: inventory, recipes or equipped.
var current_tab: String = "inventory"
# True when dragging half of a stack rather than all of it.
var split_drag: bool = false
# The part of the stack currently being carried during a split drag.
var split_hold: Dictionary = {"item": "", "count": 0, "texture": null}

# Number of backpack slots the player can use.
const UNLOCKED_SLOTS = 20
# Total number of backpack slots, including locked ones.
const TOTAL_SLOTS = 80
# Full durability of each tool, used to draw its durability bar.
const TOOL_MAX_DURABILITY = {
	"Axe": 80.0,
	"Sword": 30.0,
	"Pickaxe": 80.0,
	"Stone Axe": 120.0,
	"Stone Sword": 40.0,
	"Stone Pickaxe": 100.0,
	"Fishing Rod": 50.0,
	"Stone Fishing Rod": 100.0,
	"Copper Fishing Rod": 120.0,
}

# Style of a normal slot.
var slot_scene_default: StyleBox = preload("res://Resources/hotbar_default.tres")
# Style of a highlighted slot.
var slot_scene_selected: StyleBox = preload("res://Resources/hotbar_selected.tres")

# The recipe whose details are shown.
var selected_recipe: Dictionary = {}
# Category filter for the recipe list.
var recipe_category: String = "all"
# The category filter buttons.
var category_buttons: Array = []
# The tab buttons at the top.
var tab_buttons: Array = []


# Starts hidden and builds the slots and tabs.
func _ready():
	hide()
	Inventory.inventory_changed.connect(update_inventory)
	_build_slots()
	_build_tabs()
	update_inventory()
	_switch_tab("inventory")
	call_deferred("_create_overlay")


# Creates the dark background shown behind the menu.
func _create_overlay():
	var overlay = ColorRect.new()
	overlay.name = "DarkOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.5)
	overlay.z_index = -1
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.position = Vector2.ZERO
	overlay.size = get_viewport().get_visible_rect().size
	overlay.hide()
	get_parent().add_child(overlay)
	get_parent().move_child(overlay, get_index())


# Drops a single item on the floor near the player.
func _spawn_drop(player, item_type: String, spawn_durability: int):
	var scene_node = get_tree().root.get_node("Scene")
	var angle = randf_range(0, TAU)
	var radius = randf_range(80, 120)
	var drop_position = player.global_position + Vector2(cos(angle), sin(angle)) * radius
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			scene_node.host_spawn_floor_item(drop_position, item_type, spawn_durability)
		else:
			scene_node.request_spawn_floor_item.rpc_id(
				1, drop_position.x, drop_position.y, item_type, spawn_durability,
			)
	else:
		scene_node.host_spawn_floor_item(drop_position, item_type, spawn_durability)


# Drops a whole stack as separate items scattered near the player.
func _spawn_drop_stack(player, item_type: String, count: int):
	var scene_node = get_tree().root.get_node("Scene")
	var positions: Array = []
	var positions_x: Array = []
	var positions_y: Array = []
	for i in count:
		var angle = randf_range(0, TAU)
		var radius = randf_range(80, 120)
		var drop_position = player.global_position + Vector2(cos(angle), sin(angle)) * radius
		positions.append(drop_position)
		positions_x.append(drop_position.x)
		positions_y.append(drop_position.y)
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			scene_node.host_spawn_floor_items_batch(positions, item_type, 1)
		else:
			scene_node.request_spawn_floor_items_batch.rpc_id(1, positions_x, positions_y, item_type, 1)
	else:
		scene_node.host_spawn_floor_items_batch(positions, item_type, 1)


# Creates the tab buttons.
func _build_tabs():
	var tab_bar = $PanelContainer/VBoxContainer/Tab_Buttons
	for child in tab_bar.get_children():
		child.queue_free()
	tab_buttons.clear()
	var inv_tab = Button.new()
	inv_tab.text = "Inventory"
	inv_tab.pressed.connect(func(): _switch_tab("inventory"))
	tab_bar.add_child(inv_tab)
	tab_buttons.append(inv_tab)
	var recipe_tab = Button.new()
	recipe_tab.text = "Recipes"
	recipe_tab.pressed.connect(func(): _switch_tab("recipes"))
	tab_bar.add_child(recipe_tab)
	tab_buttons.append(recipe_tab)


# Shows the chosen tab and hides the others.
func _switch_tab(tab: String):
	current_tab = tab
	var inv_section = $PanelContainer/VBoxContainer/HBoxContainer/Inventory
	var recipes_section = $PanelContainer/VBoxContainer/HBoxContainer/Recipes
	var equipped_section = $PanelContainer/VBoxContainer/HBoxContainer/Equipped
	match tab:
		"inventory":
			inv_section.visible = true
			equipped_section.visible = true
			recipes_section.visible = false
		"recipes":
			inv_section.visible = false
			equipped_section.visible = false
			recipes_section.visible = true
			_update_recipe_panel()
	for i in tab_buttons.size():
		var button = tab_buttons[i]
		var is_active = (i == 0 and tab == "inventory") or (i == 1 and tab == "recipes")
		button.modulate = Color(1.5, 1.8, 1.5, 1.0) if is_active else Color(0.6, 0.6, 0.6, 1.0)


# Creates the grid of backpack slots and connects their mouse events.
func _build_slots():
	var grid = $PanelContainer/VBoxContainer/HBoxContainer/Inventory/PanelContainer/GridContainer
	for child in grid.get_children():
		child.queue_free()
	inv_slots_ui.clear()
	for i in TOTAL_SLOTS:
		var panel = Panel.new()
		panel.custom_minimum_size = Vector2(64, 64)
		var style = slot_scene_default.duplicate()
		panel.add_theme_stylebox_override("panel", style)
		grid.add_child(panel)
		inv_slots_ui.append(panel)
		if i >= UNLOCKED_SLOTS:
			var overlay = ColorRect.new()
			overlay.color = Color(0.0, 0.0, 0.0, 0.4)
			overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.add_child(overlay)
			var lock_label = Label.new()
			lock_label.text = "🔒"
			lock_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
			lock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.add_child(lock_label)
		else:
			var idx = i
			panel.gui_input.connect(func(event): _gui_input_for_slot(event, idx))
			panel.mouse_entered.connect(func(): _on_slot_hover(idx))
			panel.mouse_exited.connect(func(): _on_slot_unhover(idx))


# Highlights the slot under the mouse if it holds an item.
func _on_slot_hover(index: int):
	hovered_slot = index
	if Inventory.inv_slots[index]["item"] != "":
		inv_slots_ui[index].add_theme_stylebox_override("panel", slot_scene_selected.duplicate())


# Removes the highlight when the mouse leaves a slot.
func _on_slot_unhover(index: int):
	if hovered_slot == index:
		hovered_slot = -1
	inv_slots_ui[index].add_theme_stylebox_override("panel", slot_scene_default.duplicate())


# Redraws every unlocked slot with its item picture, stack count and durability bar.
func update_inventory():
	for i in UNLOCKED_SLOTS:
		var slot = inv_slots_ui[i]
		var slot_data = Inventory.inv_slots[i]
		var prev_item = slot.get_meta("last_item", "")
		var prev_count = slot.get_meta("last_count", -1)
		if prev_item == slot_data["item"] and prev_count == slot_data["count"]:
			continue
		slot.set_meta("last_item", slot_data["item"])
		slot.set_meta("last_count", slot_data["count"])
		for child in slot.get_children():
			child.queue_free()
		if slot_data["item"] == "":
			continue
		var item_texture = TextureRect.new()
		item_texture.texture = slot_data["texture"]
		item_texture.expand_mode = TextureRect.EXPAND_FIT_WIDTH
		item_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		item_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		item_texture.offset_left = 6
		item_texture.offset_right = -6
		item_texture.offset_top = 6
		item_texture.offset_bottom = -6
		item_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(item_texture)
		if not Inventory.non_stackable_items.has(slot_data["item"]):
			var label = Label.new()
			label.text = str(min(slot_data["count"], 99))
			label.add_theme_font_size_override("font_size", 16)
			label.add_theme_color_override("font_color", Color.WHITE)
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			label.add_theme_constant_override("outline_size", 4)
			label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
			label.offset_top = -24
			label.offset_bottom = -16
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.offset_left = -24 if slot_data["count"] >= 10 else -14
			slot.add_child(label)
		elif _is_fish_item(slot_data["item"]) and slot_data["count"] > 0:
			var label = Label.new()
			label.text = Inventory.get_fish_weight_display(slot_data["item"], slot_data["count"])
			label.add_theme_font_size_override("font_size", 11)
			label.add_theme_color_override("font_color", Color.WHITE)
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			label.add_theme_constant_override("outline_size", 4)
			label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
			label.offset_top = -22
			label.offset_bottom = -8
			label.offset_left = -48
			label.offset_right = -2
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(label)
		if TOOL_MAX_DURABILITY.has(slot_data["item"]):
			_add_durability_bar(slot, slot_data["count"], TOOL_MAX_DURABILITY[slot_data["item"]])
	if current_tab == "recipes":
		_update_recipe_panel()


# Draws a small bar showing how much durability a tool has left. Nothing is drawn for a new tool.
func _add_durability_bar(slot: Panel, current: float, max_dur: float):
	var fraction_remaining = clamp(current / max_dur, 0.0, 1.0)
	if fraction_remaining >= 1.0:
		return
	var bar_bg = ColorRect.new()
	bar_bg.color = Color(0.2, 0.2, 0.2, 0.8)
	bar_bg.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar_bg.offset_top = -13
	bar_bg.offset_bottom = -8
	bar_bg.offset_left = 7
	bar_bg.offset_right = -5
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(bar_bg)
	var bar = ColorRect.new()
	bar.color = Color(1.0 - fraction_remaining, fraction_remaining, 0.0)
	bar.set_anchor_and_offset(SIDE_LEFT, 0, 0)
	bar.set_anchor_and_offset(SIDE_TOP, 0, 0)
	bar.set_anchor_and_offset(SIDE_BOTTOM, 1, 0)
	bar.set_anchor_and_offset(SIDE_RIGHT, fraction_remaining, 0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(bar)


# Starts dragging half of a stack.
func _start_split_drag(index: int, item_name: String, item_texture: Texture2D):
	dragging_from = index
	dragging_from_inv = true
	split_drag = true
	split_hold = {"item": item_name, "count": 0, "texture": item_texture}
	var container = Control.new()
	container.size = Vector2(40, 40)
	container.z_index = 9
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex_rect = TextureRect.new()
	tex_rect.texture = item_texture
	tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(tex_rect)
	add_child(container)
	drag_node = container


# Starts dragging a whole slot.
func _start_full_drag(index: int, item_texture: Texture2D):
	dragging_from = index
	dragging_from_inv = true
	split_drag = false
	var container = Control.new()
	container.size = Vector2(40, 40)
	container.z_index = 9
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex_rect = TextureRect.new()
	tex_rect.texture = item_texture
	tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(tex_rect)
	add_child(container)
	drag_node = container


# Puts the carried items into a slot, stacking with matching items when possible.
func _merge_or_place(
	arr: Array,
	index: int,
	item_name: String,
	item_texture: Texture2D,
	count: int,
) -> bool:
	var slot = arr[index]
	if slot["item"] == "":
		slot["item"] = item_name
		slot["count"] = count
		slot["texture"] = item_texture
		Inventory.discover(item_name)
		Inventory.inventory_changed.emit()
		return true
	if slot["item"] == item_name and slot["count"] < 99:
		var space = 99 - slot["count"]
		var add = min(space, count)
		slot["count"] += add
		var leftover = count - add
		Inventory.inventory_changed.emit()
		if leftover > 0:
			_return_split_to_source(leftover)
		return true
	return false


# Adds carried items to the offhand slot if that is allowed.
func _merge_split_into_offhand(item_name: String, item_texture: Texture2D, count: int) -> bool:
	if not Inventory.can_item_go_offhand(item_name):
		return false
	if Inventory.offhand_slot["item"] == "":
		Inventory.offhand_slot = {"item": item_name, "count": count, "texture": item_texture}
		Inventory.discover(item_name)
		Inventory.inventory_changed.emit()
		return true
	if Inventory.offhand_slot["item"] == item_name and Inventory.offhand_slot["count"] < 99:
		var space = 99 - Inventory.offhand_slot["count"]
		var add = min(space, count)
		Inventory.offhand_slot["count"] += add
		var leftover = count - add
		Inventory.inventory_changed.emit()
		if leftover > 0:
			_return_split_to_source(leftover)
		return true
	return false


# Puts any carried items back into the slot they came from.
func _return_split_to_source(leftover: int = -1) -> void:
	var amount = split_hold["count"] if leftover == -1 else leftover
	if amount <= 0:
		return
	var slot = Inventory.inv_slots[dragging_from]
	if slot["item"] == "":
		slot["item"] = split_hold["item"]
		slot["count"] = amount
		slot["texture"] = split_hold["texture"]
	elif slot["item"] == split_hold["item"]:
		slot["count"] = min(99, slot["count"] + amount)
	else:
		Inventory.batch_add_item(split_hold["item"], split_hold["texture"], amount)
	Inventory.inventory_changed.emit()


# Places the carried items where the mouse was released: a backpack slot, a hotbar slot or the offhand.
func _resolve_split_drop() -> void:
	var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	var dropped_on_inv = get_hovered_slot()
	var dropped_on_hotbar = hotbar._get_hovered_slot() if hotbar else -1
	var dropped_on_offhand = hotbar != null \
		and hotbar.has_method("_is_mouse_over_offhand") \
		and hotbar._is_mouse_over_offhand()
	var item_name = split_hold["item"]
	var count = split_hold["count"]
	var item_texture = split_hold["texture"]
	if dropped_on_inv != -1:
		if not _merge_or_place(Inventory.inv_slots, dropped_on_inv, item_name, item_texture, count):
			_return_split_to_source()
	elif dropped_on_offhand:
		if not _merge_split_into_offhand(item_name, item_texture, count):
			if hotbar and hotbar.has_method("_flash_offhand_red"):
				hotbar._flash_offhand_red()
	elif dropped_on_hotbar != -1:
		if not _merge_or_place(Inventory.slots, dropped_on_hotbar, item_name, item_texture, count):
			_return_split_to_source()
	else:
		var inv_panel = $PanelContainer
		var mouse = get_global_mouse_position()
		if not inv_panel.get_global_rect().has_point(mouse):
			var hotbar2 = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
			var player = hotbar2.get_local_player() if hotbar2 else null
			if player:
				var scene_node = get_tree().root.get_node("Scene")
				var positions_x: Array = []
				var positions_y: Array = []
				for i in count:
					var angle = randf_range(0, TAU)
					var radius = randf_range(80, 120)
					var drop_position = player.global_position + Vector2(cos(angle), sin(angle)) * radius
					positions_x.append(drop_position.x)
					positions_y.append(drop_position.y)
				if multiplayer.has_multiplayer_peer():
					if multiplayer.is_server():
						for i in positions_x.size():
							scene_node.host_spawn_floor_item(Vector2(positions_x[i], positions_y[i]), item_name, 1)
					else:
						scene_node.request_spawn_floor_items_batch.rpc_id(1, positions_x, positions_y, item_name, 1)
				else:
					for i in positions_x.size():
						scene_node.host_spawn_floor_item(Vector2(positions_x[i], positions_y[i]), item_name, 1)
			else:
				_return_split_to_source()
		else:
			_return_split_to_source()
	split_drag = false
	split_hold = {"item": "", "count": 0, "texture": null}


# Handles clicks on a slot: right click starts a split drag and left click starts a full drag.
func _gui_input_for_slot(event, index):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT \
			and event.pressed and not drag_node:
		var slot_data = Inventory.inv_slots[index]
		if slot_data["item"] != "":
			var item_name = slot_data["item"]
			var item_texture = slot_data["texture"]
			if Inventory.non_stackable_items.has(item_name):
				_start_full_drag(index, item_texture)
			else:
				var total = slot_data["count"]
				var take = int(ceil(total / 2.0))
				if take > 0:
					var remain = total - take
					if remain <= 0:
						Inventory.inv_slots[index] = {"item": "", "count": 0, "texture": null}
					else:
						Inventory.inv_slots[index]["count"] = remain
					Inventory.inventory_changed.emit()
					_start_split_drag(index, item_name, item_texture)
					split_hold["count"] = take
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and Inventory.inv_slots[index]["item"] != "":
			if Input.is_key_pressed(KEY_SHIFT):
				var item_name = Inventory.inv_slots[index]["item"]
				var item_texture = Inventory.inv_slots[index]["texture"]
				if Input.is_key_pressed(KEY_CTRL):
					var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
					if not Inventory.move_slot_to_offhand(index, true) \
							and hotbar and hotbar.has_method("_flash_offhand_red"):
						hotbar._flash_offhand_red()
					return
				var is_non_stackable = Inventory.non_stackable_items.has(item_name)
				var remaining = Inventory.inv_slots[index]["count"]
				if _is_fish_item(item_name):
					for i in Inventory.slots.size():
						if Inventory.slots[i]["item"] == "":
							Inventory.slots[i]["item"] = item_name
							Inventory.slots[i]["count"] = remaining
							Inventory.slots[i]["texture"] = item_texture
							Inventory.inv_slots[index] = {"item": "", "count": 0, "texture": null}
							Inventory.inventory_changed.emit()
							break
					return
				if not is_non_stackable:
					for i in Inventory.slots.size():
						if remaining <= 0:
							break
						if Inventory.slots[i]["item"] == item_name and Inventory.slots[i]["count"] < 99:
							var space = 99 - Inventory.slots[i]["count"]
							var add = min(space, remaining)
							Inventory.slots[i]["count"] += add
							remaining -= add
				for i in Inventory.slots.size():
					if remaining <= 0:
						break
					if Inventory.slots[i]["item"] == "":
						var add = min(99, remaining)
						Inventory.slots[i]["item"] = item_name
						Inventory.slots[i]["count"] = add
						Inventory.slots[i]["texture"] = item_texture
						remaining -= add
				if remaining <= 0:
					Inventory.inv_slots[index] = {"item": "", "count": 0, "texture": null}
				else:
					Inventory.inv_slots[index]["count"] = remaining
				Inventory.inventory_changed.emit()
				return
			dragging_from = index
			dragging_from_inv = true
			var container = Control.new()
			container.size = Vector2(40, 40)
			container.z_index = 9
			container.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var item_texture = TextureRect.new()
			item_texture.texture = Inventory.inv_slots[index]["texture"]
			item_texture.expand_mode = TextureRect.EXPAND_FIT_WIDTH
			item_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			item_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			item_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
			container.add_child(item_texture)
			add_child(container)
			drag_node = container


# Returns the slot nearest to the mouse if it is close enough, or -1.
func get_hovered_slot() -> int:
	var closest = -1
	var closest_dist = 40.0
	for i in UNLOCKED_SLOTS:
		var center = inv_slots_ui[i].get_global_rect().get_center()
		var dist = get_global_mouse_position().distance_to(center)
		if dist < closest_dist:
			closest_dist = dist
			closest = i
	return closest

# Whether the player was near a crafting bench at the last check, to refresh recipes when it changes.
var _last_near_bench: bool = false


# Runs every frame: opens and closes the menu with the inventory and crafting keys, handles the exit key, releases dragged items and drops items with the drop key.
func _process(_delta):
	var chat_box = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
	if chat_box and chat_box.get("is_open"):
		return
	var extras_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/Extras")
	if Input.is_action_just_pressed("inventory"):
		if extras_ui and extras_ui.visible:
			extras_ui.hide()
		if visible and current_tab == "inventory":
			toggle()
		elif visible and current_tab == "recipes":
			_switch_tab("inventory")
		else:
			toggle_to("inventory")
		get_viewport().set_input_as_handled()
		return
	if Input.is_action_just_pressed("crafting"):
		if extras_ui and extras_ui.visible:
			extras_ui.hide()
		if visible and current_tab == "recipes":
			toggle()
		elif visible and current_tab == "inventory":
			_switch_tab("recipes")
		else:
			toggle_to("recipes")
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	if Input.is_action_just_pressed("slot_up") or Input.is_action_just_pressed("slot_down"):
		if current_tab == "inventory":
			_switch_tab("recipes")
		else:
			_switch_tab("inventory")
		get_viewport().set_input_as_handled()
		return
	if Input.is_action_just_pressed("exit"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	var near_bench = Crafting.is_near_bench()
	if near_bench != _last_near_bench:
		_last_near_bench = near_bench
		if not near_bench and Crafting.bench_recipes.has(selected_recipe):
			selected_recipe = {}
		if current_tab == "recipes":
			_update_recipe_panel()
	if not drag_node:
		if Input.is_action_just_pressed("click"):
			var inv_panel = $PanelContainer
			var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
			var left_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/LeftUI")
			var mouse = get_global_mouse_position()
			var on_inv = inv_panel.get_global_rect().has_point(mouse)
			var on_hotbar = false
			if hotbar:
				for slot in hotbar.slots:
					if slot.get_global_rect().grow(6).has_point(mouse):
						on_hotbar = true
						break
			var on_left_ui = false
			if left_ui:
				on_left_ui = left_ui.get_node("HBoxContainer/Button2").get_global_rect().has_point(mouse)
			if not on_inv and not on_hotbar and not on_left_ui:
				toggle()
	if Input.is_action_just_pressed("drop") and not drag_node and hovered_slot != -1:
		var slot_data = Inventory.inv_slots[hovered_slot]
		if slot_data["item"] != "":
			var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
			var player = hotbar.get_local_player() if hotbar else null
			if player:
				var item_type = slot_data["item"]
				var count = slot_data["count"]
				var is_tool = Inventory.non_stackable_items.has(item_type)
				if is_tool:
					_spawn_drop(player, item_type, count)
				else:
					_spawn_drop_stack(player, item_type, count)
				Inventory.remove_item(hovered_slot, true)
		return
	if drag_node:
		drag_node.global_position = get_global_mouse_position() - Vector2(20, 20)
		var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
		var held_item_name = (
			split_hold["item"] if split_drag else Inventory.inv_slots[dragging_from]["item"]
		)
		if hotbar and hotbar.has_method("_is_mouse_over_offhand") \
				and hotbar.has_method("set_offhand_drag_valid"):
			var over_offhand = hotbar._is_mouse_over_offhand()
			hotbar.set_offhand_drag_valid(not over_offhand or Inventory.can_item_go_offhand(held_item_name))
		var release_button = MOUSE_BUTTON_RIGHT if split_drag else MOUSE_BUTTON_LEFT
		if not Input.is_mouse_button_pressed(release_button):
			if split_drag:
				_resolve_split_drop()
			else:
				var dropped_on_inv = get_hovered_slot()
				var dropped_on_hotbar = hotbar._get_hovered_slot() if hotbar else -1
				var dropped_on_offhand = hotbar != null \
					and hotbar.has_method("_is_mouse_over_offhand") \
					and hotbar._is_mouse_over_offhand()
				if dropped_on_inv != -1 and dropped_on_inv != dragging_from:
					Inventory.move_item(dragging_from, dropped_on_inv, true, true)
				elif dropped_on_offhand:
					if not Inventory.move_slot_to_offhand(dragging_from, true) \
							and hotbar and hotbar.has_method("_flash_offhand_red"):
						hotbar._flash_offhand_red()
				elif dropped_on_hotbar != -1:
					Inventory.move_item(dragging_from, dropped_on_hotbar, true, false)
				elif dropped_on_inv == -1 and dropped_on_hotbar == -1:
					var inv_panel = $PanelContainer
					var mouse = get_global_mouse_position()
					if not inv_panel.get_global_rect().has_point(mouse):
						var hotbar2 = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
						var player = hotbar2.get_local_player() if hotbar2 else null
						if player:
							var item_type = Inventory.inv_slots[dragging_from]["item"]
							var count = Inventory.inv_slots[dragging_from]["count"]
							var is_tool = Inventory.non_stackable_items.has(item_type)
							if is_tool:
								_spawn_drop(player, item_type, count)
							else:
								_spawn_drop_stack(player, item_type, count)
							Inventory.remove_item(dragging_from, true)
			drag_node.queue_free()
			drag_node = null
			dragging_from = -1
			if hotbar and hotbar.has_method("set_offhand_drag_valid"):
				hotbar.set_offhand_drag_valid(true)
			var now_hovered = get_hovered_slot()
			if now_hovered != -1:
				_on_slot_hover(now_hovered)


# Rebuilds the list of recipes the player has discovered, filtered by category.
func _update_recipe_panel():
	var scroll_vbox = get_node(
		"PanelContainer/VBoxContainer/HBoxContainer/Recipes/HBoxContainer/ScrollContainer/VBoxContainer",
	)
	var detail = $PanelContainer/VBoxContainer/HBoxContainer/Recipes/HBoxContainer/Detail
	for child in scroll_vbox.get_children():
		scroll_vbox.remove_child(child)
		child.queue_free()
	if selected_recipe.is_empty():
		for child in detail.get_children():
			detail.remove_child(child)
			child.queue_free()
	var cat_bar = HBoxContainer.new()
	cat_bar.add_theme_constant_override("separation", 4)
	scroll_vbox.add_child(cat_bar)
	category_buttons.clear()
	for cat in ["All", "Blocks", "Equipment"]:
		var button = Button.new()
		button.text = cat
		var c = cat.to_lower()
		button.pressed.connect(func():
			recipe_category = c
			_update_recipe_panel()
		)
		cat_bar.add_child(button)
		category_buttons.append(button)
		button.modulate = (
			Color(2.0, 2.0, 2.0, 1.0) if cat.to_lower() == recipe_category else Color(0.6, 0.6, 0.6, 1.0)
		)
	var grid = GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll_vbox.add_child(grid)
	var blocks = []
	var equipment = []
	var all_recipes = Crafting.basic_recipes + Crafting.bench_recipes
	for recipe in all_recipes:
		if not Inventory.is_discovered(recipe):
			continue
		if Crafting.bench_recipes.has(recipe) and not Crafting.is_near_bench():
			continue
		if recipe["result"] in [
			"Axe", "Sword", "Pickaxe", "Stone Axe", "Stone Sword",
			"Stone Pickaxe", "Fishing Rod", "Stone Fishing Rod",
		]:
			equipment.append(recipe)
		else:
			blocks.append(recipe)
	var filtered: Array = []
	match recipe_category:
		"all":
			filtered = blocks + equipment
		"equipment":
			filtered = equipment
		"blocks":
			filtered = blocks
	for recipe in filtered:
		_add_recipe_icon(grid, recipe, detail)


# Adds a recipe button, coloured to show whether it can be crafted.
func _add_recipe_icon(grid: GridContainer, recipe: Dictionary, detail: VBoxContainer):
	var button = Button.new()
	button.custom_minimum_size = Vector2(52, 52)
	var can_craft = Crafting.can_craft(recipe)
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.5, 0.5, 0.5, 1.0) if can_craft else Color(0.25, 0.25, 0.25, 1.0)
	btn_style.corner_radius_top_left = 4
	btn_style.corner_radius_top_right = 4
	btn_style.corner_radius_bottom_left = 4
	btn_style.corner_radius_bottom_right = 4
	button.add_theme_stylebox_override("normal", btn_style)
	button.add_theme_stylebox_override("hover", btn_style)
	button.add_theme_stylebox_override("pressed", btn_style)
	var item_texture = TextureRect.new()
	item_texture.texture = Crafting.get_item_texture(recipe["result"])
	item_texture.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	item_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	item_texture.offset_left = 4
	item_texture.offset_right = -4
	item_texture.offset_top = 4
	item_texture.offset_bottom = -4
	item_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(item_texture)
	var r = recipe
	var state = {"last_click": 0.0, "timer": null}
	button.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var now = Time.get_ticks_msec() / 1000.0
			var is_double = (now - state["last_click"]) < 0.2
			state["last_click"] = now
			state["timer"] = null
			if is_double:
				if Input.is_key_pressed(KEY_SHIFT):
					_on_craft_max(r, null)
				else:
					_on_craft(r, null)
			else:
				var t = get_tree().create_timer(0.2)
				state["timer"] = t
				t.timeout.connect(func():
					if state["timer"] == t:
						state["timer"] = null
						_show_recipe_detail(r, detail)
				)
	)
	grid.add_child(button)


# Shows the ingredients and Craft buttons of the selected recipe.
func _show_recipe_detail(recipe: Dictionary, detail: VBoxContainer):
	selected_recipe = recipe
	for child in detail.get_children():
		child.queue_free()
	var icon = TextureRect.new()
	icon.texture = Crafting.get_item_texture(recipe["result"])
	icon.custom_minimum_size = Vector2(64, 64)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	detail.add_child(icon)
	var name_label = Label.new()
	name_label.text = str(recipe["result_count"]) + "x " + recipe["result"]
	name_label.add_theme_font_size_override("font_size", 16)
	detail.add_child(name_label)
	var ing_header = Label.new()
	ing_header.text = "Requires:"
	ing_header.add_theme_font_size_override("font_size", 12)
	detail.add_child(ing_header)
	for item in recipe["ingredients"]:
		var ing_label = Label.new()
		var have = Inventory.count_item(item)
		var need = recipe["ingredients"][item]
		ing_label.text = str(need) + "x " + item + " (" + str(have) + " owned)"
		ing_label.modulate = Color(0.6, 1.0, 0.6) if have >= need else Color(1.0, 0.5, 0.5)
		detail.add_child(ing_label)
	if Crafting.bench_recipes.has(recipe):
		var bench_label = Label.new()
		bench_label.text = "Requires Crafting Bench"
		bench_label.modulate = Color(1.0, 0.8, 0.4)
		detail.add_child(bench_label)
	var craft_btn = Button.new()
	craft_btn.text = "Craft"
	craft_btn.disabled = not Crafting.can_craft(recipe)
	var r = recipe
	craft_btn.pressed.connect(func():
		if Input.is_key_pressed(KEY_SHIFT):
			_on_craft_max(r, craft_btn)
		else:
			_on_craft(r, craft_btn)
	)
	detail.add_child(craft_btn)


# Crafts the recipe once if the player has the ingredients and briefly shows the result on the button.
func _on_craft(recipe: Dictionary, button: Button):
	if Crafting.can_craft(recipe):
		Crafting.craft(recipe)
		if button != null and is_instance_valid(button):
			button.text = "Done!"
		if not selected_recipe.is_empty():
			var detail = $PanelContainer/VBoxContainer/HBoxContainer/Recipes/HBoxContainer/Detail
			_show_recipe_detail(selected_recipe, detail)
		await get_tree().create_timer(0.5).timeout
		if button != null and is_instance_valid(button):
			button.text = "Craft"
	else:
		if button != null and is_instance_valid(button):
			button.text = "Need more!"
			await get_tree().create_timer(0.5).timeout
			if is_instance_valid(button):
				button.text = "Craft"


# Crafts the recipe repeatedly until the player runs out of ingredients.
func _on_craft_max(recipe: Dictionary, button: Button):
	if button != null and is_instance_valid(button):
		button.disabled = true
		button.text = "Crafting..."
	var crafted = 0
	while Crafting.can_craft(recipe):
		for item in recipe["ingredients"]:
			Crafting._remove_item(item, recipe["ingredients"][item])
		Crafting._add_result_silent(recipe)
		crafted += 1
	if crafted > 0:
		Inventory.inventory_changed.emit()
		if not selected_recipe.is_empty():
			var detail = $PanelContainer/VBoxContainer/HBoxContainer/Recipes/HBoxContainer/Detail
			_show_recipe_detail(selected_recipe, detail)
	if button != null and is_instance_valid(button):
		button.disabled = false
		button.text = "Done x" + str(crafted) + "!" if crafted > 0 else "Need more!"
		await get_tree().create_timer(0.5).timeout
		if is_instance_valid(button):
			button.text = "Craft"


# Opens or closes the menu on the inventory tab.
func toggle():
	toggle_to("inventory")


# Closes the menu if it is open. Otherwise opens it on the given tab.
func toggle_to(tab: String):
	var overlay = get_parent().get_node_or_null("DarkOverlay")
	if visible:
		selected_recipe = {}
		hide()
		if overlay:
			overlay.hide()
	else:
		show()
		if overlay:
			overlay.show()
		_switch_tab(tab)
		update_inventory()


# Returns true if the item is a fish, including the albino version.
func _is_fish_item(item_name: String) -> bool:
	var fishing_manager = get_tree().root.get_node_or_null("FishingManager")
	if fishing_manager:
		for fish in fishing_manager.FISH_TABLE:
			var base_name: String = fish.get("name", "")
			if item_name == base_name or item_name == "Albino " + base_name:
				return true
	for f in [
		"Minnow", "Perch", "Bass", "Pike", "Catfish", "Sturgeon", "Tophat Fish",
		"Salmon", "Clownfish", "Blue Tang", "Red Tang", "Lionfish", "Tire",
		"Guppy", "Snapper", "Muskie", "Ghost Eel", "Crystal Creeper",
	]:
		if item_name == f or item_name == "Albino " + f:
			return true
	return false
