extends Control

var toggle_ui = true
var can_toggle_ui = true
var slots = []
var dragging_from = -1
var drag_node : TextureRect = null
var wood_scene = preload("res://Scenes/wood.tscn")

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
			tex.offset_left = 8
			tex.offset_right = -8
			tex.offset_top = 8
			tex.offset_bottom = -8
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

func _gui_input_for_slot(event, index):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and Inventory.slots[index]["item"] != "":
			dragging_from = index
			drag_node = TextureRect.new()
			drag_node.texture = Inventory.slots[index]["texture"]
			drag_node.size = Vector2(40, 40)
			drag_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(drag_node)

func _ready_slots():
	for i in range(10):
		var slot = slots[i]
		var idx = i
		slot.gui_input.connect(func(event): _gui_input_for_slot(event, idx))

func _get_hovered_slot():
	for i in range(slots.size()):
		if slots[i].get_global_rect().has_point(get_global_mouse_position()):
			return i
	return -1

func _process(_delta: float) -> void:
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
			var dropped_on = _get_hovered_slot()
			if dropped_on != -1 and dropped_on != dragging_from:
				Inventory.move_item(dragging_from, dropped_on)
			elif dropped_on == -1:
				var player = get_local_player()
				if player:
					var count = Inventory.slots[dragging_from]["count"]
					var scene_node = get_tree().root.get_node("Scene")
					for i in count:
						var angle = randf_range(0, TAU)
						var radius = randf_range(80, 120)
						var drop_pos = player.global_position + Vector2(cos(angle), sin(angle)) * radius
						if multiplayer.has_multiplayer_peer():
							scene_node.host_spawn_floor_item(drop_pos)
						else:
							scene_node.request_spawn_floor_item.rpc_id(1, drop_pos.x, drop_pos.y)
					Inventory.remove_item(dragging_from)
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
