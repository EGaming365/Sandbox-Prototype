extends Control

var toggle_ui = true
var can_toggle_ui = true
var slots = []
var dragging_from = -1
var dragging_from_inv = false
var drag_node : Control = null
var hovered_hotbar_slot: int = -1

var current_slot = 1
var hotbar_default: StyleBox = preload("res://Resources/hotbar_default.tres")
var hotbar_selected: StyleBox = preload("res://Resources/hotbar_selected.tres")

var drop_hold_timer: float = 0.0
var drop_hold_triggered: bool = false

const TOOL_MAX_DURABILITY = {
	"Axe": 80.0,
	"Sword": 30.0,
	"Pickaxe": 80.0,
	"Stone Axe": 120.0,
	"Stone Sword": 40.0,
	"Stone Pickaxe": 100.0,
	"Fishing Rod": 50.0,
	"Stone Fishing Rod": 100.0
}

func _ready():
	for i in range(10):
		slots.append($HBoxContainer.get_node("Item" + str(i + 1)))
	_ready_slots()
	Inventory.inventory_changed.connect(update_hotbar)
	_prewarm_textures()
	update_hotbar()

func _prewarm_textures():
	var dummy = TextureRect.new()
	dummy.visible = false
	add_child(dummy)
	for i in range(10):
		var tex = Inventory.slots[i].get("texture")
		if tex:
			dummy.texture = tex
	await get_tree().process_frame
	dummy.queue_free()

func get_local_player():
	for child in get_tree().root.get_node("Scene").get_children():
		if child is CharacterBody2D:
			if multiplayer.has_multiplayer_peer():
				if child.is_multiplayer_authority():
					return child
			else:
				return child
	return null

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
	var positions_x: Array = []
	var positions_y: Array = []
	for i in count:
		var angle = randf_range(0, TAU)
		var radius = randf_range(80, 120)
		var drop_pos = player.global_position + Vector2(cos(angle), sin(angle)) * radius
		positions_x.append(drop_pos.x)
		positions_y.append(drop_pos.y)
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			for i in positions_x.size():
				scene_node.host_spawn_floor_item(Vector2(positions_x[i], positions_y[i]), item_type, 1)
		else:
			scene_node.request_spawn_floor_items_batch.rpc_id(1, positions_x, positions_y, item_type, 1)
	else:
		for i in positions_x.size():
			scene_node.host_spawn_floor_item(Vector2(positions_x[i], positions_y[i]), item_type, 1)

func update_hotbar():
	for i in range(10):
		var slot = slots[i]
		var data = Inventory.slots[i]
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
		var tex = Inventory.get_texture(data["item"])
		if tex == null:
			tex = data["texture"]
		var tex_rect = TextureRect.new()
		tex_rect.texture = tex
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex_rect.size = Vector2(slot.size.x - 12, slot.size.y - 12)
		tex_rect.position = Vector2(6, 6)
		slot.add_child(tex_rect)
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
			var max_dur = TOOL_MAX_DURABILITY[data["item"]]
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
				bar.color = Color(1.0 - pct, pct, 0.0)
				bar.set_anchor_and_offset(SIDE_LEFT, 0, 0)
				bar.set_anchor_and_offset(SIDE_TOP, 0, 0)
				bar.set_anchor_and_offset(SIDE_BOTTOM, 1, 0)
				bar.set_anchor_and_offset(SIDE_RIGHT, pct, 0)
				bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
				bar_bg.add_child(bar)

func _gui_input_for_slot(event, index):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			current_slot = index + 1
		if event.pressed and Inventory.slots[index]["item"] != "":
			if Input.is_key_pressed(KEY_SHIFT):
				var item_name = Inventory.slots[index]["item"]
				var tex = Inventory.slots[index]["texture"]
				var is_non_stackable = Inventory.non_stackable_items.has(item_name)
				var remaining = Inventory.slots[index]["count"]
				var inv_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
				if _is_fish_item(item_name):
					for i in 20:
						if Inventory.inv_slots[i]["item"] == "":
							Inventory.inv_slots[i]["item"] = item_name
							Inventory.inv_slots[i]["count"] = remaining
							Inventory.inv_slots[i]["texture"] = tex
							Inventory.slots[index] = {"item": "", "count": 0, "texture": null}
							Inventory.inventory_changed.emit()
							break
					return
				if inv_ui:
					if not is_non_stackable:
						for i in 20:
							if remaining <= 0:
								break
							if Inventory.inv_slots[i]["item"] == item_name and Inventory.inv_slots[i]["count"] < 99:
								var space = 99 - Inventory.inv_slots[i]["count"]
								var add = min(space, remaining)
								Inventory.inv_slots[i]["count"] += add
								remaining -= add
					for i in 20:
						if remaining <= 0:
							break
						if Inventory.inv_slots[i]["item"] == "":
							var add = min(99, remaining)
							Inventory.inv_slots[i]["item"] = item_name
							Inventory.inv_slots[i]["count"] = add
							Inventory.inv_slots[i]["texture"] = tex
							remaining -= add
					if remaining <= 0:
						Inventory.slots[index] = {"item": "", "count": 0, "texture": null}
					else:
						Inventory.slots[index]["count"] = remaining
					Inventory.inventory_changed.emit()
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
		slot.mouse_entered.connect(func(): _on_slot_hover(idx))
		slot.mouse_exited.connect(func(): _on_slot_unhover(idx))

func _on_slot_hover(index: int):
	hovered_hotbar_slot = index

func _on_slot_unhover(index: int):
	if hovered_hotbar_slot == index:
		hovered_hotbar_slot = -1

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

func _process(delta: float) -> void:
	var chat = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
	if chat and chat.get("is_open"):
		return

	var inv_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
	var inv_open = inv_ui and inv_ui.visible

	for i in range(1, 11):
		var panel: Panel = $HBoxContainer.get_node("Item" + str(i))
		if i == current_slot and not inv_open:
			panel.add_theme_stylebox_override("panel", hotbar_selected)
			panel.z_index = 1
		elif inv_open and i == hovered_hotbar_slot + 1 and Inventory.slots[hovered_hotbar_slot]["item"] != "":
			panel.add_theme_stylebox_override("panel", hotbar_selected)
			panel.z_index = 1
		else:
			panel.add_theme_stylebox_override("panel", hotbar_default)
			panel.z_index = 0

	var prev_slot = current_slot
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
		if current_slot == 1:
			current_slot = 10
		else:
			current_slot = current_slot - 1
	if Input.is_action_just_pressed("slot_down"):
		if current_slot == 10:
			current_slot = 1
		else:
			current_slot = current_slot + 1
	var fishing_manager = get_tree().root.get_node_or_null("FishingManager")
	if current_slot != prev_slot and fishing_manager:
		if fishing_manager._minigame_active or fishing_manager._catch_icon_scene != null:
			current_slot = prev_slot
		elif fishing_manager._waiting_for_bite:
			fishing_manager._cancel_cast()

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
				var mouse = get_global_mouse_position()
				var inv_ui_node = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
				var on_inv_panel = false
				if inv_ui_node and inv_ui_node.visible:
					on_inv_panel = inv_ui_node.get_node("PanelContainer").get_global_rect().has_point(mouse)
				if not on_inv_panel:
					var player = get_local_player()
					if player:
						var item_type = Inventory.slots[dragging_from]["item"]
						var count = Inventory.slots[dragging_from]["count"]
						var is_tool = Inventory.non_stackable_items.has(item_type)
						if is_tool:
							_spawn_drop(player, item_type, count)
						else:
							_spawn_drop_stack(player, item_type, count)
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
		drop_hold_timer = 0.0
		drop_hold_triggered = false

	if Input.is_action_pressed("drop") and not drag_node:
		if not inv_open:
			drop_hold_timer += delta
			if drop_hold_timer >= 1.0 and not drop_hold_triggered:
				drop_hold_triggered = true
				var drop_index = current_slot - 1
				var data = Inventory.slots[drop_index]
				if data["item"] != "":
					var player = get_local_player()
					if player:
						var item_type = data["item"]
						var count = data["count"]
						var is_tool = Inventory.non_stackable_items.has(item_type)
						if is_tool:
							_spawn_drop(player, item_type, count)
						else:
							_spawn_drop_stack(player, item_type, count)
						Inventory.remove_item(drop_index, false)

	if Input.is_action_just_released("drop") and not drag_node and not drop_hold_triggered:
		var drop_index = -1
		if inv_open and hovered_hotbar_slot != -1:
			drop_index = hovered_hotbar_slot
		elif not inv_open:
			drop_index = current_slot - 1
		if drop_index != -1:
			var data = Inventory.slots[drop_index]
			if data["item"] != "":
				var player = get_local_player()
				if player:
					var item_type = data["item"]
					var count = data["count"]
					var is_tool = Inventory.non_stackable_items.has(item_type)
					if inv_open:
						if is_tool:
							_spawn_drop(player, item_type, count)
						else:
							_spawn_drop_stack(player, item_type, count)
						Inventory.remove_item(drop_index, false)
					else:
						var spawn_durability = count if is_tool else 1
						_spawn_drop(player, item_type, spawn_durability)
						if is_tool or count <= 1:
							Inventory.remove_item(drop_index, false)
						else:
							Inventory.slots[drop_index]["count"] -= 1
							Inventory.inventory_changed.emit()

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if not drag_node:
			var slot_index = current_slot - 1
			var data = Inventory.slots[slot_index]
			if data["item"] == "Chicken_Raw" and data["count"] > 0:
				var hud = get_tree().root.get_node_or_null("Scene/CanvasLayer/RightUI")
				if hud:
					hud.hunger = clamp(hud.hunger + 30.0, 0.0, 100.0)
				if data["count"] <= 1:
					Inventory.remove_item(slot_index, false)
				else:
					Inventory.slots[slot_index]["count"] -= 1
					Inventory.inventory_changed.emit()
			elif data["item"] == "Fishing Rod" or data["item"] == "Stone Fishing Rod":
				_try_fish_cast(event.position)

func _try_fish_cast(screen_pos: Vector2) -> void:
	var fishing_manager = get_tree().root.get_node_or_null("FishingManager")
	if fishing_manager:
		fishing_manager.try_cast(screen_pos)

func _is_fish_item(item_name: String) -> bool:
	for f in ["Minnow", "Perch", "Bass", "Pike", "Catfish", "Sturgeon", "Tophat Fish", "Salmon", "Clownfish", "Blue Tang", "Lionfish"]:
		if item_name == f or item_name == "Albino " + f:
			return true
	return false
