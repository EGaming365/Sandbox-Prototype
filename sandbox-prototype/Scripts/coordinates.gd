extends Label

var toggle_ui = false
var can_toggle_ui = true

func _process(_delta):
	var player = get_tree().root.get_node("Scene/Player")
	if player:
		text = "X: " + str(snappedf(player.global_position.x, 0.1)) + "\nY: " + str(snappedf(player.global_position.y, 0.1))

	if Input.is_action_just_pressed("toggle_debug"):
		if toggle_ui == true and can_toggle_ui == true:
			toggle_ui = false
		else:
			toggle_ui = true
		can_toggle_ui = false
		
	if Input.is_action_just_released("toggle_debug"):
		can_toggle_ui = true

	if toggle_ui == true:
		$".".show()
	else:
		$".".hide()
		
