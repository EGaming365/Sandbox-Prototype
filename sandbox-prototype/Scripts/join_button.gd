extends Button

var toggle_ui = false
var can_toggle_ui = true
func _process(_delta: float) -> void:
	var chat = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
	var inv = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
	if Input.is_action_just_pressed("exit"):
		if (chat and chat.is_open) or (inv and inv.visible):
			pass
		elif toggle_ui == true and can_toggle_ui == true:
			toggle_ui = false
		else:
			toggle_ui = true
		can_toggle_ui = false
	if Input.is_action_just_released("exit"):
		can_toggle_ui = true
	if toggle_ui == true:
		$".".show()
	else:
		$".".hide()
