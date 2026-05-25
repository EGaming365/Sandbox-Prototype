extends Control

func _process(_delta):
	if Input.is_action_just_pressed("click"):
		var mouse = get_global_mouse_position()

		var extras = get_tree().root.get_node_or_null("Scene/CanvasLayer/Extras")
		if extras and extras.visible:
			var panel = extras.get_node_or_null("PanelContainer")
			if panel and panel.get_global_rect().has_point(mouse):
				return

		if $HBoxContainer/Button.get_global_rect().has_point(mouse):
			get_viewport().set_input_as_handled()
			if extras:
				extras.toggle()

		elif $HBoxContainer/Button2.get_global_rect().has_point(mouse):
			get_viewport().set_input_as_handled()
			var inv = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
			if inv:
				if inv.visible and inv.current_tab == "inventory":
					inv.toggle()
				else:
					inv.toggle_to("inventory")
