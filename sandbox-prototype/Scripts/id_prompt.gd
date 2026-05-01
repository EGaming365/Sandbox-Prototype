extends LineEdit

var toggle_ui = false
var can_toggle_ui = true

func _process(_delta: float) -> void:

	if Input.is_action_just_pressed("settings"):
		if toggle_ui == true and can_toggle_ui == true:
			toggle_ui = false
		else:
			toggle_ui = true
		can_toggle_ui = false
		
	if Input.is_action_just_released("settings"):
		can_toggle_ui = true

	if toggle_ui == true:
		$".".show()
	else:
		$".".hide()
		
