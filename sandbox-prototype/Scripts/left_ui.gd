# Left hand navigation buttons.
# Handles clicks on the Extras and Inventory buttons and opens the exit menu with the exit key.

extends Control


# Run before other UI so these buttons can claim mouse clicks first.
func _ready():
	process_priority = -100


# Checks each frame whether a nav button was clicked.
func _process(_delta):
	# Only handle the frame the mouse button goes down.
	if Input.is_action_just_pressed("click"):
		var mouse_position = get_global_mouse_position()
		# Find the Extras and Inventory screens in the HUD.
		var extras_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/Extras")
		var inventory_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
		# Extras button: close the inventory if open, then toggle the Extras screen.
		if $HBoxContainer/Button.get_global_rect().has_point(mouse_position):
			get_viewport().set_input_as_handled()
			if inventory_ui and inventory_ui.visible:
				inventory_ui.toggle()
			if extras_ui:
				if extras_ui.visible:
					extras_ui.close_ui()
				else:
					extras_ui.toggle()
			return
		# Ignore clicks inside the open Extras panel so they do not close it.
		if extras_ui and extras_ui.visible:
			var extras_panel = extras_ui.get_node_or_null("PanelContainer")
			if extras_panel and extras_panel.get_global_rect().has_point(mouse_position):
				return
		# Inventory button: close Extras if open, then toggle the inventory tab.
		if $HBoxContainer/Button2.get_global_rect().has_point(mouse_position):
			get_viewport().set_input_as_handled()
			if extras_ui and extras_ui.visible:
				extras_ui.close_ui()
			if inventory_ui:
				if inventory_ui.visible and inventory_ui.current_tab == "inventory":
					inventory_ui.toggle()
				else:
					inventory_ui.toggle_to("inventory")


# Opens the Extras screen when the exit key is pressed and nothing else is open.
func _input(event):
	if Input.is_action_just_pressed("exit"):
		var extras_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/Extras")
		var inventory_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
		# The exit key closes the inventory elsewhere, so do nothing here.
		if inventory_ui and inventory_ui.visible:
			return
		if extras_ui and not extras_ui.visible:
			extras_ui.toggle()
			get_viewport().set_input_as_handled()
