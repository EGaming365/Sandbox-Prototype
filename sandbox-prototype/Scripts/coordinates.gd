# Debug label that shows the local player's coordinates and biome.
# Visibility is toggled with the toggle_debug key.

extends Label

# Tracks whether the label is currently shown.
var is_ui_visible = false
# Stops the label flickering while the debug key is held down.
var can_toggle_visibility = true


# Returns the player node controlled by this game instance, or null if none exists.
func get_local_player():
	for child in get_tree().root.get_node("Scene").get_children():
		if child is CharacterBody2D and child.is_in_group("players"):
			# In multiplayer only the player this peer controls counts.
			if multiplayer.has_multiplayer_peer():
				if child.is_multiplayer_authority():
					return child
			else:
				# Offline there is only one player, so return it directly.
				return child
	return null


# Returns the name of the area at the given position: Cave, Forest, Plains or Unknown.
func get_current_biome_name(player_pos: Vector2) -> String:
	# The cave world takes priority over the overworld biomes.
	var cave_gen = get_tree().root.get_node_or_null("Scene/CaveWorldGen")
	if cave_gen != null and cave_gen.get("in_cave") == true:
		return "Cave"
	# Ask the overworld generator whether the position is inside a forest.
	var world_gen = get_tree().root.get_node_or_null("Scene/WorldGen")
	if not world_gen:
		return "Unknown"
	if world_gen.has_method("is_forest_at") and world_gen.is_forest_at(player_pos):
		return "Forest"
	return "Plains"


# Updates the text every frame and handles showing or hiding the label.
func _process(_delta):
	var player = get_local_player()
	if player:
		# Convert pixels to map units (100 pixels per unit) rounded to one decimal place.
		var display_x = snappedf(player.global_position.x / 100.0, 0.1)
		# Flip the sign because screen Y grows downwards but map Y should grow upwards.
		var display_y = snappedf((player.global_position.y * -1) / 100.0, 0.1)
		# Use a point near the player's feet so the biome matches where they stand.
		var feet_pos = player.global_position + Vector2(0, 48)
		var biome_name = get_current_biome_name(feet_pos)
		text = "X: " + str(display_x) \
			+ "\nY: " + str(display_y) \
			+ "\nBiome: " + biome_name
	# Toggle the label once per key press.
	if Input.is_action_just_pressed("toggle_debug"):
		# Apply the stored visibility state.
		if is_ui_visible == true and can_toggle_visibility == true:
			is_ui_visible = false
		else:
			is_ui_visible = true
		can_toggle_visibility = false
	# Allow toggling again after the key is released.
	if Input.is_action_just_released("toggle_debug"):
		can_toggle_visibility = true
	if is_ui_visible == true:
		show()
	else:
		hide()
