# Shows or hides the host ID text box each time the exit key is pressed.
# The key is ignored while the chat box or inventory is open.

extends LineEdit

# Tracks whether this control is currently meant to be shown.
var is_ui_visible = false
# Stops the visibility flipping every frame while the exit key is held down.
var can_toggle_visibility = true


# Checks the exit key every frame and shows or hides this control.
func _process(_delta: float) -> void:
	# Look up the chat box and inventory so the exit key is ignored while either is open.
	var chat_box = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
	var inventory_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
	# Only react on the frame the exit key is first pressed.
	if Input.is_action_just_pressed("exit"):
		if (chat_box and chat_box.is_open) or (inventory_ui and inventory_ui.visible):
			# Do nothing here, because the exit key closes the chat box or inventory instead.
			pass
		# Hide the control if it is showing and the key has been released since the last toggle.
		elif is_ui_visible == true and can_toggle_visibility == true:
			is_ui_visible = false
		else:
			is_ui_visible = true
		# Block further toggles until the exit key is released.
		can_toggle_visibility = false
	# Allow toggling again once the exit key is let go.
	if Input.is_action_just_released("exit"):
		can_toggle_visibility = true
	# Apply the stored visibility state to this control.
	if is_ui_visible == true:
		$".".show()
	else:
		$".".hide()
