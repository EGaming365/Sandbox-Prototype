# Health display for the HUD.
# Draws one heart icon per point of health and dims the hearts that have been lost.

extends Control

# Image used for every heart icon.
var heart_texture = preload("res://Assets/heart.png")
# Holds the icon node for each heart so they can be dimmed later.
var heart_icons = []
# Total number of hearts shown.
var max_health = 10
# Health value most recently passed to update_hearts.
var current_health = 10


# Build the row of hearts as soon as this node enters the scene.
func _ready():
	_build_hearts()


# Creates one heart icon for each point of maximum health and lays them out in a row.
func _build_hearts():
	# Horizontal container that places the hearts side by side.
	var heart_row = HBoxContainer.new()
	# Position the row near the bottom left of the screen.
	heart_row.position = Vector2(20, 940)
	heart_row.add_theme_constant_override("separation", 2)
	add_child(heart_row)
	# Create one icon for every point of health.
	for i in max_health:
		var heart_icon = TextureRect.new()
		heart_icon.texture = heart_texture
		heart_icon.custom_minimum_size = Vector2(25, 25)
		heart_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		heart_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH
		heart_icons.append(heart_icon)
		heart_row.add_child(heart_icon)


# Dims every heart above the given health value so the row matches the player's health.
func update_hearts(health: int):
	current_health = health
	# Set each heart to full brightness if it is still filled, otherwise dark and faded.
	for i in heart_icons.size():
		heart_icons[i].modulate = Color(1, 1, 1, 1) if i < health else Color(0.2, 0.2, 0.2, 0.5)
