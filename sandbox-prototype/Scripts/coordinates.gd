extends Label

var toggle_ui = false
var can_toggle_ui = true

func get_local_player():
	for child in get_tree().root.get_node("Scene").get_children():
		if child is CharacterBody2D:
			if multiplayer.has_multiplayer_peer():
				if child.is_multiplayer_authority():
					return child
			else:
				return child
	return null

func get_current_biome_name(player_pos: Vector2) -> String:
	var world_gen = get_tree().root.get_node_or_null("Scene/WorldGen")
	if not world_gen:
		return "Unknown"

	if world_gen.has_method("is_forest_at") and world_gen.is_forest_at(player_pos):
		return "Forest"

	return "Plains"

func get_day_type() -> String:
	var weather = get_tree().root.get_node_or_null("Scene/Weather")
	if not weather:
		return "Unknown"

	if weather.time_of_day < 0.25:
		return "Night"
	elif weather.time_of_day < 0.35:
		return "Morning"
	elif weather.time_of_day < 0.75:
		return "Day"
	elif weather.time_of_day < 0.85:
		return "Evening"

	return "Night"

func get_weather_type() -> String:
	var weather = get_tree().root.get_node_or_null("Scene/Weather")
	if not weather:
		return "Unknown"

	match weather.current_weather:
		weather.WeatherType.CLEAR:
			return "Clear"
		weather.WeatherType.RAIN:
			return "Rain"
		weather.WeatherType.THUNDER:
			return "Thunder"
		weather.WeatherType.THUNDERSTORM:
			return "Thunderstorm"
		_:
			return "Unknown"

func _process(_delta):
	var player = get_local_player()
	if player:
		var x = snappedf(player.global_position.x / 100.0, 0.1)
		var y = snappedf((player.global_position.y * -1) / 100.0, 0.1)
		var feet_pos = player.global_position + Vector2(0, 48)
		var biome_name = get_current_biome_name(feet_pos)
		var day_type = get_day_type()
		var weather_type = get_weather_type()

		text = "X: " + str(x) \
			+ "\nY: " + str(y) \
			+ "\nBiome: " + biome_name \
			+ "\nTime: " + day_type \
			+ "\nWeather: " + weather_type

	if Input.is_action_just_pressed("toggle_debug"):
		if toggle_ui == true and can_toggle_ui == true:
			toggle_ui = false
		else:
			toggle_ui = true
		can_toggle_ui = false

	if Input.is_action_just_released("toggle_debug"):
		can_toggle_ui = true

	if toggle_ui == true:
		show()
	else:
		hide()
