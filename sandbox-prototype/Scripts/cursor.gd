# Custom mouse cursor.
# Follows the mouse, hides the system cursor and draws small cooldown bars above the pointer.

extends Sprite2D

# Active cooldown bars. Each entry holds an 'id' and a 'pct' value between 0 and 1.
var cooldowns: Array = []


# Hide the operating system cursor because this sprite replaces it.
func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


# Adds or updates the cooldown bar with the given id. A value near zero removes the bar.
func show_cooldown(progress_fraction: float, cooldown_id: String = "default"):
	# Look for an existing bar with the same id and update it.
	for cooldown in cooldowns:
		if cooldown["id"] == cooldown_id:
			cooldown["pct"] = progress_fraction
			if progress_fraction <= 0.01:
				cooldowns.erase(cooldown)
			return
	# No existing bar was found, so create a new one.
	if progress_fraction > 0.01:
		cooldowns.append({"id": cooldown_id, "pct": progress_fraction})


# Keep the sprite on the mouse and redraw the bars every frame.
func _process(_delta):
	position = get_viewport().get_mouse_position()
	queue_redraw()


# Draws one bar per active cooldown, stacked above the cursor.
func _draw():
	if cooldowns.is_empty():
		return
	# Size of each bar in pixels.
	var bar_width = 10.0
	var bar_height = 4.0
	# Vertical gap between stacked bars.
	var bar_spacing = 6.0
	for i in cooldowns.size():
		var progress_fraction = cooldowns[i]["pct"]
		# Top left corner of this bar, stacked upwards for each cooldown.
		var offset = Vector2(-bar_width / 2, -10 - (i * bar_spacing))
		# Dark background for the bar.
		draw_rect(
			Rect2(offset, Vector2(bar_width, bar_height)),
			Color(0.15, 0.15, 0.15, 0.95),
		)
		# The bar grows brighter as the cooldown finishes.
		var brightness = 0.2 + (0.6 * (1.0 - progress_fraction))
		# Filled part of the bar that shows the progress.
		draw_rect(
			Rect2(offset, Vector2(bar_width * progress_fraction, bar_height)),
			Color(brightness, brightness, brightness, 0.95),
		)
