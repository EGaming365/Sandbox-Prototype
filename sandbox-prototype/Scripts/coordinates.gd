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
	var cave_gen = get_tree().root.get_node_or_null("Scene/CaveWorldGen")
	if cave_gen != null and cave_gen.get("in_cave") == true:
		return "Cave"
	var world_gen = get_tree().root.get_node_or_null("Scene/WorldGen")
	if not world_gen:
		return "Unknown"
	if world_gen.has_method("is_forest_at") and world_gen.is_forest_at(player_pos):
		return "Forest"
	return "Plains"

func _process(_delta):
	var player = get_local_player()
	if player:
		var x = snappedf(player.global_position.x / 100.0, 0.1)
		var y = snappedf((player.global_position.y * -1) / 100.0, 0.1)
		var feet_pos = player.global_position + Vector2(0, 48)
		var biome_name = get_current_biome_name(feet_pos)
		text = "X: " + str(x) \
			+ "\nY: " + str(y) \
			+ "\nBiome: " + biome_name
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
