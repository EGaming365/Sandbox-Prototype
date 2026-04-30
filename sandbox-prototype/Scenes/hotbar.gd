extends Control

var toggle_ui = true
var can_toggle_ui = true

func _process(delta: float) -> void:

	if Input.is_action_just_pressed("toggle_ui"):
		if toggle_ui == true and can_toggle_ui == true:
			toggle_ui = false
		else:
			toggle_ui = true
		can_toggle_ui = false
		
	if Input.is_action_just_released("toggle_ui"):
		can_toggle_ui = true

	if toggle_ui == true:
		$".".show()
	else:
		$".".hide()
		
