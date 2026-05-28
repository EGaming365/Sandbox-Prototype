extends Control

func _input(event):
	if Input.is_action_just_pressed("exit"):
		var extras = get_tree().root.get_node_or_null("Scene/CanvasLayer/Extras")
		var inv = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
		if inv and inv.visible:
			return
		if extras and not extras.visible:
			extras.toggle()
			get_viewport().set_input_as_handled()

func _process(_delta):
	if Input.is_action_just_pressed("click"):
		var mouse = get_global_mouse_position()
		var extras = get_tree().root.get_node_or_null("Scene/CanvasLayer/Extras")
		var inv = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
		if $HBoxContainer/Button.get_global_rect().has_point(mouse):
			get_viewport().set_input_as_handled()
			if inv and inv.visible:
				inv.toggle()
			if extras:
				if extras.visible:
					extras.hide()
				else:
					extras.toggle()
			return
		if extras and extras.visible:
			var panel = extras.get_node_or_null("PanelContainer")
			if panel and panel.get_global_rect().has_point(mouse):
				return
		if $HBoxContainer/Button2.get_global_rect().has_point(mouse):
			get_viewport().set_input_as_handled()
			if extras and extras.visible:
				extras.hide()
			if inv:
				if inv.visible and inv.current_tab == "inventory":
					inv.toggle()
				else:
					inv.toggle_to("inventory")
