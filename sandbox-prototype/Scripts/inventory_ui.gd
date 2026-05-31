extends Control

var inv_slots_ui = []
var dragging_from = -1
var dragging_from_inv = false
var drag_node: Control = null
var hovered_slot: int = -1
var current_tab: String = "inventory"

const UNLOCKED_SLOTS = 20
const TOTAL_SLOTS = 80
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

var slot_scene_default: StyleBox = preload("res://Resources/hotbar_default.tres")
var slot_scene_selected: StyleBox = preload("res://Resources/hotbar_selected.tres")

var selected_recipe: Dictionary = {}
var recipe_category: String = "all"
var category_buttons: Array = []
var tab_buttons: Array = []

func _ready():
	hide()
	Inventory.inventory_changed.connect(update_inventory)
	_build_slots()
	_build_tabs()
	update_inventory()
	_switch_tab("inventory")
	call_deferred("_create_overlay")

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

func _spawn_drop(player, item_type: String, spawn_durability: int):
	var scene_node = get_tree().root.get_node("Scene")
	var angle = randf_range(0, TAU)
	var radius = randf_range(80, 120)
	var drop_pos = player.global_position + Vector2(cos(angle), sin(angle)) * radius
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			scene_node.host_spawn_floor_item(drop_pos, item_type, spawn_durability)
		else:
			scene_node.request_spawn_floor_item.rpc_id(1, drop_pos.x, drop_pos.y, item_type, spawn_durability)
	else:
		scene_node.host_spawn_floor_item(drop_pos, item_type, spawn_durability)

func _spawn_drop_stack(player, item_type: String, count: int):
	var scene_node = get_tree().root.get_node("Scene")
	var positions: Array = []
	var positions_x: Array = []
	var positions_y: Array = []
	for i in count:
		var angle = randf_range(0, TAU)
		var radius = randf_range(80, 120)
		var drop_pos = player.global_position + Vector2(cos(angle), sin(angle)) * radius
		positions.append(drop_pos)
		positions_x.append(drop_pos.x)
		positions_y.append(drop_pos.y)
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			scene_node.host_spawn_floor_items_batch(positions, item_type, 1)
		else:
			scene_node.request_spawn_floor_items_batch.rpc_id(1, positions_x, positions_y, item_type, 1)
	else:
		scene_node.host_spawn_floor_items_batch(positions, item_type, 1)

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
		var btn = tab_buttons[i]
		var is_active = (i == 0 and tab == "inventory") or (i == 1 and tab == "recipes")
		btn.modulate = Color(1.5, 1.8, 1.5, 1.0) if is_active else Color(0.6, 0.6, 0.6, 1.0)

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

func _on_slot_hover(index: int):
	hovered_slot = index
	if Inventory.inv_slots[index]["item"] != "":
		inv_slots_ui[index].add_theme_stylebox_override("panel", slot_scene_selected.duplicate())

func _on_slot_unhover(index: int):
	if hovered_slot == index:
		hovered_slot = -1
	inv_slots_ui[index].add_theme_stylebox_override("panel", slot_scene_default.duplicate())

func update_inventory():
	for i in UNLOCKED_SLOTS:
		var slot = inv_slots_ui[i]
		var data = Inventory.inv_slots[i]
		var prev_item = slot.get_meta("last_item", "")
		var prev_count = slot.get_meta("last_count", -1)
		if prev_item == data["item"] and prev_count == data["count"]:
			continue
		slot.set_meta("last_item", data["item"])
		slot.set_meta("last_count", data["count"])
		for child in slot.get_children():
			child.queue_free()
		if data["item"] == "":
			continue
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
			label.offset_left = -24 if data["count"] >= 10 else -14
			slot.add_child(label)
		elif _is_fish_item(data["item"]) and data["count"] > 0:
			var label = Label.new()
			label.text = Inventory.get_fish_weight_display(data["item"], data["count"])
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
		if TOOL_MAX_DURABILITY.has(data["item"]):
			_add_durability_bar(slot, data["count"], TOOL_MAX_DURABILITY[data["item"]])
	if current_tab == "recipes":
		_update_recipe_panel()

func _add_durability_bar(slot: Panel, current: float, max_dur: float):
	var pct = clamp(current / max_dur, 0.0, 1.0)
	if pct >= 1.0:
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
	bar.color = Color(1.0 - pct, pct, 0.0)
	bar.set_anchor_and_offset(SIDE_LEFT, 0, 0)
	bar.set_anchor_and_offset(SIDE_TOP, 0, 0)
	bar.set_anchor_and_offset(SIDE_BOTTOM, 1, 0)
	bar.set_anchor_and_offset(SIDE_RIGHT, pct, 0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(bar)

func _gui_input_for_slot(event, index):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and Inventory.inv_slots[index]["item"] != "":
			if Input.is_key_pressed(KEY_SHIFT):
				var item_name = Inventory.inv_slots[index]["item"]
				var tex = Inventory.inv_slots[index]["texture"]
				if Input.is_key_pressed(KEY_CTRL):
					var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
					if not Inventory.move_slot_to_offhand(index, true) and hotbar and hotbar.has_method("_flash_offhand_red"):
						hotbar._flash_offhand_red()
					return
				var is_non_stackable = Inventory.non_stackable_items.has(item_name)
				var remaining = Inventory.inv_slots[index]["count"]
				if _is_fish_item(item_name):
					for i in Inventory.slots.size():
						if Inventory.slots[i]["item"] == "":
							Inventory.slots[i]["item"] = item_name
							Inventory.slots[i]["count"] = remaining
							Inventory.slots[i]["texture"] = tex
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
						Inventory.slots[i]["texture"] = tex
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
			var tex = TextureRect.new()
			tex.texture = Inventory.inv_slots[index]["texture"]
			tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			container.add_child(tex)
			add_child(container)
			drag_node = container

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

var _last_near_bench: bool = false

func _process(_delta):
	var chat = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
	if chat and chat.get("is_open"):
		return
	var extras = get_tree().root.get_node_or_null("Scene/CanvasLayer/Extras")
	if Input.is_action_just_pressed("inventory"):
		if extras and extras.visible:
			extras.hide()
		if visible and current_tab == "inventory":
			toggle()
		elif visible and current_tab == "recipes":
			_switch_tab("inventory")
		else:
			toggle_to("inventory")
		get_viewport().set_input_as_handled()
		return
	if Input.is_action_just_pressed("crafting"):
		if extras and extras.visible:
			extras.hide()
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
		var data = Inventory.inv_slots[hovered_slot]
		if data["item"] != "":
			var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
			var player = hotbar.get_local_player() if hotbar else null
			if player:
				var item_type = data["item"]
				var count = data["count"]
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
		if hotbar and hotbar.has_method("_is_mouse_over_offhand") and hotbar.has_method("set_offhand_drag_valid"):
			var over_offhand = hotbar._is_mouse_over_offhand()
			hotbar.set_offhand_drag_valid(not over_offhand or Inventory.can_item_go_offhand(Inventory.inv_slots[dragging_from]["item"]))
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var dropped_on_inv = get_hovered_slot()
			var dropped_on_hotbar = hotbar._get_hovered_slot() if hotbar else -1
			var dropped_on_offhand = hotbar != null and hotbar.has_method("_is_mouse_over_offhand") and hotbar._is_mouse_over_offhand()
			if dropped_on_inv != -1 and dropped_on_inv != dragging_from:
				Inventory.move_item(dragging_from, dropped_on_inv, true, true)
			elif dropped_on_offhand:
				if not Inventory.move_slot_to_offhand(dragging_from, true) and hotbar and hotbar.has_method("_flash_offhand_red"):
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

func _update_recipe_panel():
	var scroll_vbox = $PanelContainer/VBoxContainer/HBoxContainer/Recipes/HBoxContainer/ScrollContainer/VBoxContainer
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
		var btn = Button.new()
		btn.text = cat
		var c = cat.to_lower()
		btn.pressed.connect(func():
			recipe_category = c
			_update_recipe_panel()
		)
		cat_bar.add_child(btn)
		category_buttons.append(btn)
		btn.modulate = Color(2.0, 2.0, 2.0, 1.0) if cat.to_lower() == recipe_category else Color(0.6, 0.6, 0.6, 1.0)
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
		if recipe["result"] in ["Axe", "Sword", "Pickaxe", "Stone Axe", "Stone Sword", "Stone Pickaxe", "Fishing Rod", "Stone Fishing Rod"]:
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

func _add_recipe_icon(grid: GridContainer, recipe: Dictionary, detail: VBoxContainer):
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(52, 52)
	var can_craft = Crafting.can_craft(recipe)
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.5, 0.5, 0.5, 1.0) if can_craft else Color(0.25, 0.25, 0.25, 1.0)
	btn_style.corner_radius_top_left = 4
	btn_style.corner_radius_top_right = 4
	btn_style.corner_radius_bottom_left = 4
	btn_style.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("normal", btn_style)
	btn.add_theme_stylebox_override("hover", btn_style)
	btn.add_theme_stylebox_override("pressed", btn_style)
	var tex = TextureRect.new()
	tex.texture = Crafting.get_item_texture(recipe["result"])
	tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.offset_left = 4
	tex.offset_right = -4
	tex.offset_top = 4
	tex.offset_bottom = -4
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(tex)
	var r = recipe
	var state = {"last_click": 0.0, "timer": null}
	btn.gui_input.connect(func(event):
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
	grid.add_child(btn)

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

func _on_craft(recipe: Dictionary, btn: Button):
	if Crafting.can_craft(recipe):
		Crafting.craft(recipe)
		if btn != null and is_instance_valid(btn):
			btn.text = "Done!"
		if not selected_recipe.is_empty():
			var detail = $PanelContainer/VBoxContainer/HBoxContainer/Recipes/HBoxContainer/Detail
			_show_recipe_detail(selected_recipe, detail)
		await get_tree().create_timer(0.5).timeout
		if btn != null and is_instance_valid(btn):
			btn.text = "Craft"
	else:
		if btn != null and is_instance_valid(btn):
			btn.text = "Need more!"
			await get_tree().create_timer(0.5).timeout
			if is_instance_valid(btn):
				btn.text = "Craft"

func _on_craft_max(recipe: Dictionary, btn: Button):
	if btn != null and is_instance_valid(btn):
		btn.disabled = true
		btn.text = "Crafting..."
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
	if btn != null and is_instance_valid(btn):
		btn.disabled = false
		btn.text = "Done x" + str(crafted) + "!" if crafted > 0 else "Need more!"
		await get_tree().create_timer(0.5).timeout
		if is_instance_valid(btn):
			btn.text = "Craft"

func toggle():
	toggle_to("inventory")

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

func _is_fish_item(item_name: String) -> bool:
	var fishing_manager = get_tree().root.get_node_or_null("FishingManager")
	if fishing_manager:
		for fish in fishing_manager.FISH_TABLE:
			var base_name: String = fish.get("name", "")
			if item_name == base_name or item_name == "Albino " + base_name:
				return true
	for f in ["Minnow", "Perch", "Bass", "Pike", "Catfish", "Sturgeon", "Tophat Fish", "Salmon", "Clownfish", "Blue Tang", "Red Tang", "Lionfish", "Tire"]:
		if item_name == f or item_name == "Albino " + f:
			return true
	return false
